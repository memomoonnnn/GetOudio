import Foundation
import GetOudioCore

struct OpenFileItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var category: FileCategory
}

struct ConversionProgressItem: Identifiable, Equatable {
    let id: UUID
    var fileName: String
    var directoryPath: String
    var operation: String
    var phase: JobProgressPhase
    var message: String?

    var progressValue: Double? {
        switch phase {
        case .pending:
            return 0
        case .running:
            return nil
        case .succeeded, .failed:
            return 1
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var openItems: [OpenFileItem] = []
    @Published var queuedJobs: [JobRequest] = []
    @Published var statusMessage = "准备就绪"
    @Published var isRunning = false
    @Published var lastSummary: ConversionSummary?
    @Published var progressItems: [ConversionProgressItem] = []
    @Published var progressWindowRequest: UUID?
    @Published var shouldCloseMainWindowForProgress = false
    @Published var showsProgressInMainWindow: Bool

    private let audioConversionService = AudioConversionService()
    private let mediaExtractionService = MediaExtractionService()
    private let ncmConversionService = NCMConversionService()
    private let appleMusicDownloadService = AppleMusicDownloadService()
    private let notificationService = NotificationService()
    private let settingsStore = SettingsStore()
    private var isHandlingQueuedJobs = false
    private var lastOpenFileEventSignature: String?
    private var lastOpenFileEventDate = Date.distantPast

    init() {
        showsProgressInMainWindow = Self.hasPendingQueuedJobs()
    }

    var hasConvertibleAudioItems: Bool {
        openItems.contains { $0.category == .audio }
    }

    var hasVideoItems: Bool {
        openItems.contains { $0.category == .video }
    }

    var hasNCMItems: Bool {
        openItems.contains { $0.category == .ncm }
    }

    var hasAppleMusicItems: Bool {
        openItems.contains { $0.category == .appleMusic }
    }

    func receiveOpenFileURLs(_ urls: [URL]) -> Bool {
        guard !isDuplicateOpenFileEvent(urls) else {
            return false
        }

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

    func receiveAndRunQueuedJobs() async -> Bool {
        guard !isHandlingQueuedJobs, !isRunning else {
            return false
        }

        isHandlingQueuedJobs = true
        defer { isHandlingQueuedJobs = false }

        do {
            let queue = try JobQueue()
            let jobs = try queue.drain()
            queuedJobs = jobs
            openItems = jobs.map { OpenFileItem(url: $0.fileURL, category: $0.category) }
            lastSummary = nil

            guard !jobs.isEmpty else {
                showsProgressInMainWindow = false
                statusMessage = "没有待处理的 Finder 任务"
                DiagnosticLog.append("app queued jobs empty")
                return false
            }

            if shouldOpenWindowForQueuedJobs(jobs) {
                showsProgressInMainWindow = false
                statusMessage = "收到 \(jobs.count) 个 Apple Music 任务，请确认下载选项"
                return true
            }

            statusMessage = "收到 \(jobs.count) 个后台任务"
            DiagnosticLog.append("app queued jobs run count=\(jobs.count)")
            await runJobs(jobs, suppressMainWindow: true)
            queuedJobs = []
            return false
        } catch {
            statusMessage = "读取 Finder 任务失败：\(error.localizedDescription)"
            DiagnosticLog.append("app queued jobs failed \(error.localizedDescription)")
            return false
        }
    }

    func runTranscode(preset: ConversionPreset) async {
        let jobs = openItems
            .filter { $0.category == .audio }
            .map { JobRequest(fileURL: $0.url, category: .audio, operation: .transcode(preset), source: .openWith) }

        await runTranscodeJobs(jobs)
    }

    func runQueuedJobs() async {
        await runJobs(queuedJobs)
    }

    private func runTranscodeJobs(_ jobs: [JobRequest]) async {
        await runJobs(jobs)
    }

    func runExtractAudio() async {
        let jobs = openItems
            .filter { $0.category == .video }
            .map { JobRequest(fileURL: $0.url, category: .video, operation: .extractAudio, source: .openWith) }

        await runJobs(jobs)
    }

    func runNCMConversion() async {
        let jobs = openItems
            .filter { $0.category == .ncm }
            .map { JobRequest(fileURL: $0.url, category: .ncm, operation: .convertNCM, source: .openWith) }

        await runJobs(jobs)
    }

    func runOpenFileNCMConversionIfNeeded() async {
        guard !openItems.isEmpty, openItems.allSatisfy({ $0.category == .ncm }) else {
            return
        }

        let jobs = openItems
            .filter { $0.category == .ncm }
            .map { JobRequest(fileURL: $0.url, category: .ncm, operation: .convertNCM, source: .openWith) }

        await runJobs(jobs, suppressMainWindow: true)
    }

    func runAppleMusicDownload(format: AppleMusicDownloadFormat?) async {
        let jobs = openItems
            .filter { $0.category == .appleMusic }
            .map { JobRequest(fileURL: $0.url, category: .appleMusic, operation: .appleMusicDownload(format), source: .shareExtension) }

        await runJobs(jobs)
    }

    private func runJobs(_ jobs: [JobRequest], suppressMainWindow: Bool = false) async {
        guard !jobs.isEmpty else {
            statusMessage = "没有可执行任务"
            DiagnosticLog.append("app run skipped empty jobs")
            return
        }

        prepareProgressItems(for: jobs)
        shouldCloseMainWindowForProgress = suppressMainWindow
        showsProgressInMainWindow = suppressMainWindow
        isRunning = true
        statusMessage = "正在处理 \(jobs.count) 个任务..."
        progressWindowRequest = UUID()
        DiagnosticLog.append("app run start count=\(jobs.count)")
        let summary = await execute(jobs)
        lastSummary = summary
        isRunning = false
        shouldCloseMainWindowForProgress = false
        statusMessage = "处理完成：成功 \(summary.successCount)，失败 \(summary.failureCount)"
        DiagnosticLog.append("app run finished success=\(summary.successCount) failure=\(summary.failureCount)")
        writeConversionLog(summary: summary, jobs: jobs)
        await notificationService.notifyConversionFinished(summary: summary, jobs: jobs)
    }

    func finishProgressWindowDismissal() {
        showsProgressInMainWindow = false
        shouldCloseMainWindowForProgress = false
    }

    private func execute(_ jobs: [JobRequest]) async -> ConversionSummary {
        var totalSuccess = 0
        var totalFailure = 0
        var messages: [String] = []

        let transcodeJobs = jobs.filter {
            if case .transcode = $0.operation { return true }
            return false
        }
        let extractJobs = jobs.filter { $0.operation == .extractAudio }
        let ncmJobs = jobs.filter { $0.operation == .convertNCM }
        let appleMusicJobs = jobs.filter {
            if case .appleMusicDownload = $0.operation { return true }
            return false
        }

        var summaries: [ConversionSummary] = []
        let progressHandler: @Sendable (JobRequest, JobProgressPhase, String?) -> Void = { [weak self] job, phase, message in
            Task { @MainActor in
                self?.updateProgress(for: job, phase: phase, message: message)
            }
        }

        if !transcodeJobs.isEmpty {
            summaries.append(await audioConversionService.convert(transcodeJobs, progressHandler: progressHandler))
        }
        if !extractJobs.isEmpty {
            summaries.append(await mediaExtractionService.extractAudio(from: extractJobs, progressHandler: progressHandler))
        }
        if !ncmJobs.isEmpty {
            summaries.append(await ncmConversionService.convert(ncmJobs, progressHandler: progressHandler))
        }
        if !appleMusicJobs.isEmpty {
            appleMusicJobs.forEach { updateProgress(for: $0, phase: .running, message: nil) }
            summaries.append(await appleMusicDownloadService.download(appleMusicJobs))
            let appleMusicSummary = summaries.last
            let phase: JobProgressPhase = appleMusicSummary?.failureCount == 0 ? .succeeded : .failed
            appleMusicJobs.forEach { updateProgress(for: $0, phase: phase, message: appleMusicSummary?.messages.first) }
        }

        for summary in summaries {
            totalSuccess += summary.successCount
            totalFailure += summary.failureCount
            messages.append(contentsOf: summary.messages)
        }

        return ConversionSummary(successCount: totalSuccess, failureCount: totalFailure, messages: messages)
    }

    private func isDuplicateOpenFileEvent(_ urls: [URL]) -> Bool {
        let signature = urls.map(\.absoluteString).sorted().joined(separator: "\n")
        let now = Date()
        defer {
            lastOpenFileEventSignature = signature
            lastOpenFileEventDate = now
        }

        return lastOpenFileEventSignature == signature && now.timeIntervalSince(lastOpenFileEventDate) < 1
    }

    private func shouldOpenWindowForQueuedJobs(_ jobs: [JobRequest]) -> Bool {
        guard settingsStore.appleMusicDownloadFormat == .askEveryTime else {
            return false
        }

        return jobs.contains {
            if case .appleMusicDownload = $0.operation {
                return true
            }
            return false
        }
    }

    private func prepareProgressItems(for jobs: [JobRequest]) {
        progressItems = jobs.map {
            ConversionProgressItem(
                id: $0.id,
                fileName: $0.fileURL.lastPathComponent,
                directoryPath: $0.fileURL.deletingLastPathComponent().path,
                operation: operationDescription(for: $0.operation),
                phase: .pending,
                message: nil
            )
        }
    }

    private func updateProgress(for job: JobRequest, phase: JobProgressPhase, message: String?) {
        guard let index = progressItems.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        progressItems[index].phase = phase
        progressItems[index].message = message
        DiagnosticLog.append("app progress \(operationDescription(for: job.operation)) \(phase.rawValue) \(job.fileURL.path)\(message.map { " | \($0)" } ?? "")")
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        do {
            let logURL = try SharedContainer.conversionLogFileURL()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var lines: [String] = [
                "===== \(timestamp) =====",
                "Result: success=\(summary.successCount), failure=\(summary.failureCount), total=\(summary.totalCount)"
            ]

            for job in jobs {
                lines.append("Job: \(operationDescription(for: job.operation)) | \(job.fileURL.path)")
            }

            if summary.messages.isEmpty {
                lines.append("Messages: <none>")
            } else {
                lines.append("Messages:")
                lines.append(contentsOf: summary.messages)
            }

            lines.append("")
            let data = lines.joined(separator: "\n").data(using: .utf8) ?? Data()

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: [.atomic])
            }
        } catch {
            statusMessage = "处理完成，但写入日志失败：\(error.localizedDescription)"
        }
    }

    private func operationDescription(for operation: JobOperation) -> String {
        switch operation {
        case .transcode(let preset):
            return "transcode(\(preset.rawValue))"
        case .extractAudio:
            return "extractAudio"
        case .convertNCM:
            return "convertNCM"
        case .appleMusicDownload(let format):
            return "appleMusicDownload(\(format?.rawValue ?? "default"))"
        }
    }

    private static func hasPendingQueuedJobs() -> Bool {
        do {
            return try !JobQueue().read().isEmpty
        } catch {
            return false
        }
    }
}
