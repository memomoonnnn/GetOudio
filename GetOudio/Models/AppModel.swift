import AppKit
import Foundation
import GetOudioCore

struct OpenFileItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var category: FileCategory
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: - Launch State

    /// How the app was launched.
    @Published var launchSource: LaunchSource = .direct

    // MARK: - File & Job State

    @Published var openItems: [OpenFileItem] = []
    @Published var queuedJobs: [JobRequest] = []
    @Published var statusMessage = "准备就绪"
    @Published var isRunning = false
    @Published var lastSummary: ConversionSummary?

    // MARK: - Private Services

    private let audioConversionService = AudioConversionService()
    private let mediaExtractionService = MediaExtractionService()
    private let ncmConversionService = NCMConversionService()
    private let appleMusicDownloadService = AppleMusicDownloadService()
    private let notificationService = NotificationService()
    private let settingsStore = SettingsStore()
    private var isHandlingQueuedJobs = false
    private var lastOpenFileEventSignature: String?
    private var lastOpenFileEventDate = Date.distantPast

    // MARK: - Computed

    var hasConvertibleAudioItems: Bool { openItems.contains { $0.category == .audio } }
    var hasVideoItems: Bool { openItems.contains { $0.category == .video } }
    var hasNCMItems: Bool { openItems.contains { $0.category == .ncm } }
    var hasAppleMusicItems: Bool { openItems.contains { $0.category == .appleMusic } }

    // MARK: - File input

    func receiveOpenFileURLs(_ urls: [URL]) -> Bool {
        guard !isDuplicateOpenFileEvent(urls) else { return false }
        openItems = urls.map { OpenFileItem(url: $0, category: FileCategory.classify($0)) }
        queuedJobs = []
        lastSummary = nil
        statusMessage = "收到 \(urls.count) 个文件"
        return true
    }

    func receiveQueuedJobs() async {
        do {
            let queue = try JobQueue()
            queuedJobs = try queue.drain()
            openItems = queuedJobs.map { OpenFileItem(url: $0.fileURL, category: $0.category) }
            statusMessage = queuedJobs.isEmpty ? "没有待处理的 Finder 任务" : "收到 \(queuedJobs.count) 个 Finder 任务"
        } catch {
            statusMessage = "读取 Finder 任务失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Background processing (from URL scheme / extension)

    /// Process queued jobs silently in the background.  Returns `true` when the
    /// convert window should be opened (Apple Music format selection needed).
    func processQueuedJobsInBackground() async -> Bool {
        guard !isHandlingQueuedJobs, !isRunning else { return false }
        isHandlingQueuedJobs = true
        defer { isHandlingQueuedJobs = false }

        // Clear extension launch markers
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            defaults.removeObject(forKey: AppConstants.extensionLaunchSourceKey)
            defaults.removeObject(forKey: AppConstants.extensionLaunchTimestampKey)
            defaults.synchronize()
        }

        do {
            let queue = try JobQueue()
            let jobs = try queue.drain()
            guard !jobs.isEmpty else {
                statusMessage = "没有待处理的 Finder 任务"
                DiagnosticLog.append("app queued jobs empty")
                return false
            }

            openItems = jobs.map { OpenFileItem(url: $0.fileURL, category: $0.category) }
            queuedJobs = jobs
            lastSummary = nil

            if shouldOpenWindowForQueuedJobs(jobs) {
                statusMessage = "收到 \(jobs.count) 个 Apple Music 任务，请确认下载选项"
                return true
            }

            DiagnosticLog.append("app bg run count=\(jobs.count)")
            await executeAndNotify(jobs)
            queuedJobs = []
            return false
        } catch {
            statusMessage = "读取 Finder 任务失败：\(error.localizedDescription)"
            DiagnosticLog.append("app queued jobs failed \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - User-triggered actions (convert window)

    func runTranscode(preset: ConversionPreset) async {
        let jobs = openItems
            .filter { $0.category == .audio }
            .map { JobRequest(fileURL: $0.url, category: .audio, operation: .transcode(preset), source: .openWith) }
        await executeAndNotify(jobs)
    }

    func runExtractAudio() async {
        let jobs = openItems
            .filter { $0.category == .video }
            .map { JobRequest(fileURL: $0.url, category: .video, operation: .extractAudio, source: .openWith) }
        await executeAndNotify(jobs)
    }

    func runNCMConversion() async {
        let jobs = openItems
            .filter { $0.category == .ncm }
            .map { JobRequest(fileURL: $0.url, category: .ncm, operation: .convertNCM, source: .openWith) }
        await executeAndNotify(jobs)
    }

    func runAppleMusicDownload(format: AppleMusicDownloadFormat?) async {
        let jobs = openItems
            .filter { $0.category == .appleMusic }
            .map { JobRequest(fileURL: $0.url, category: .appleMusic, operation: .appleMusicDownload(format), source: .shareExtension) }
        await executeAndNotify(jobs)
    }

    func runQueuedJobs() async {
        let jobs = queuedJobs
        queuedJobs = []
        await executeAndNotify(jobs)
    }

    // MARK: - Core execution

    private func executeAndNotify(_ jobs: [JobRequest]) async {
        guard !jobs.isEmpty else {
            statusMessage = "没有可执行任务"
            DiagnosticLog.append("app run skipped empty jobs")
            return
        }

        isRunning = true
        statusMessage = "正在处理 \(jobs.count) 个任务..."
        DiagnosticLog.append("app run start count=\(jobs.count)")

        let summary = await execute(jobs)
        lastSummary = summary
        isRunning = false
        statusMessage = "处理完成：成功 \(summary.successCount)，失败 \(summary.failureCount)"
        DiagnosticLog.append("app run finished success=\(summary.successCount) failure=\(summary.failureCount)")

        writeConversionLog(summary: summary, jobs: jobs)
        await notificationService.notifyConversionFinished(summary: summary, jobs: jobs)
    }

    private func execute(_ jobs: [JobRequest]) async -> ConversionSummary {
        var totalSuccess = 0
        var totalFailure = 0
        var messages: [String] = []

        let transcodeJobs = jobs.filter { if case .transcode = $0.operation { true } else { false } }
        let extractJobs = jobs.filter { $0.operation == .extractAudio }
        let ncmJobs = jobs.filter { $0.operation == .convertNCM }
        let amJobs = jobs.filter { if case .appleMusicDownload = $0.operation { true } else { false } }

        var summaries: [ConversionSummary] = []

        if !transcodeJobs.isEmpty {
            summaries.append(await audioConversionService.convert(transcodeJobs))
        }
        if !extractJobs.isEmpty {
            summaries.append(await mediaExtractionService.extractAudio(from: extractJobs))
        }
        if !ncmJobs.isEmpty {
            summaries.append(await ncmConversionService.convert(ncmJobs))
        }
        if !amJobs.isEmpty {
            summaries.append(await appleMusicDownloadService.download(amJobs))
        }

        for s in summaries {
            totalSuccess += s.successCount
            totalFailure += s.failureCount
            messages.append(contentsOf: s.messages)
        }

        return ConversionSummary(successCount: totalSuccess, failureCount: totalFailure, messages: messages)
    }

    // MARK: - Helpers

    private func isDuplicateOpenFileEvent(_ urls: [URL]) -> Bool {
        let signature = urls.map(\.absoluteString).sorted().joined(separator: "\n")
        let now = Date()
        defer { lastOpenFileEventSignature = signature; lastOpenFileEventDate = now }
        return lastOpenFileEventSignature == signature && now.timeIntervalSince(lastOpenFileEventDate) < 1
    }

    private func shouldOpenWindowForQueuedJobs(_ jobs: [JobRequest]) -> Bool {
        guard settingsStore.appleMusicDownloadFormat == .askEveryTime else { return false }
        return jobs.contains { if case .appleMusicDownload = $0.operation { true } else { false } }
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        do {
            let logURL = try SharedContainer.conversionLogFileURL()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var lines = [
                "===== \(timestamp) =====",
                "Result: success=\(summary.successCount), failure=\(summary.failureCount), total=\(summary.totalCount)"
            ]
            for job in jobs {
                lines.append("Job: \(job.fileURL.path)")
            }
            if summary.messages.isEmpty {
                lines.append("Messages: <none>")
            } else {
                lines.append("Messages:")
                lines.append(contentsOf: summary.messages)
            }
            lines.append("")
            let data = (lines.joined(separator: "\n")).data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            statusMessage = "处理完成，但写入日志失败：\(error.localizedDescription)"
        }
    }
}
