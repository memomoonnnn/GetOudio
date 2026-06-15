import Foundation
import GetOudioCore

struct OpenFileItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var category: FileCategory
}

@MainActor
final class AppModel: ObservableObject {
    @Published var openItems: [OpenFileItem] = []
    @Published var queuedJobs: [JobRequest] = []
    @Published var statusMessage = "准备就绪"
    @Published var isRunning = false
    @Published var lastSummary: ConversionSummary?

    private let audioConversionService = AudioConversionService()
    private let mediaExtractionService = MediaExtractionService()
    private let ncmConversionService = NCMConversionService()
    private let appleMusicDownloadService = AppleMusicDownloadService()
    private let notificationService = NotificationService()

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

    func receiveOpenFileURLs(_ urls: [URL]) {
        openItems = urls.map { OpenFileItem(url: $0, category: FileCategory.classify($0)) }
        queuedJobs = []
        lastSummary = nil
        statusMessage = "收到 \(urls.count) 个文件"
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

    func runAppleMusicDownload(format: AppleMusicDownloadFormat?) async {
        let jobs = openItems
            .filter { $0.category == .appleMusic }
            .map { JobRequest(fileURL: $0.url, category: .appleMusic, operation: .appleMusicDownload(format), source: .shareExtension) }

        await runJobs(jobs)
    }

    private func runJobs(_ jobs: [JobRequest]) async {
        guard !jobs.isEmpty else {
            statusMessage = "没有可执行任务"
            return
        }

        isRunning = true
        statusMessage = "正在处理 \(jobs.count) 个任务..."
        let summary = await execute(jobs)
        lastSummary = summary
        isRunning = false
        statusMessage = "处理完成：成功 \(summary.successCount)，失败 \(summary.failureCount)"
        await notificationService.notifyConversionFinished(summary: summary)
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
        if !transcodeJobs.isEmpty {
            summaries.append(await audioConversionService.convert(transcodeJobs))
        }
        if !extractJobs.isEmpty {
            summaries.append(await mediaExtractionService.extractAudio(from: extractJobs))
        }
        if !ncmJobs.isEmpty {
            summaries.append(await ncmConversionService.convert(ncmJobs))
        }
        if !appleMusicJobs.isEmpty {
            summaries.append(await appleMusicDownloadService.download(appleMusicJobs))
        }

        for summary in summaries {
            totalSuccess += summary.successCount
            totalFailure += summary.failureCount
            messages.append(contentsOf: summary.messages)
        }

        return ConversionSummary(successCount: totalSuccess, failureCount: totalFailure, messages: messages)
    }
}
