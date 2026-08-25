import Foundation
import GetOudioCore

/// The Background Agent's serialized owner for queued conversion work.
actor BackgroundTaskCoordinator {
    private let container: AgentDataStore
    private let audioService = AudioConversionService()
    private let mediaService = MediaExtractionService()
    private let ncmService: NCMConversionService
    private let appleMusicWorker: AppleMusicRuntimeWorkerClient
    private let notificationService: NotificationService
    private let appleMusicShareCoordinator: AppleMusicShareDownloadCoordinator
    private var isProcessing = false

    init(container: AgentDataStore, appleMusicWorker: AppleMusicRuntimeWorkerClient) {
        self.container = container
        self.appleMusicWorker = appleMusicWorker
        ncmService = NCMConversionService(container: container)
        notificationService = NotificationService(container: container)
        appleMusicShareCoordinator = AppleMusicShareDownloadCoordinator(
            container: container,
            runtimeClient: appleMusicWorker
        )
    }

    func handlePendingAppleMusicDownload(
        format: AppleMusicDownloadFormat
    ) async -> SettingsAttentionItem? {
        await appleMusicShareCoordinator.handlePendingAppleMusicDownload(format: format)
    }

    func recoverPendingAppleMusicDownloadIfNeeded() async {
        await appleMusicShareCoordinator.recoverPendingAppleMusicDownloadIfNeeded()
    }

    func processPendingWork() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let shareEvents: [ShareEvent]
        let jobs: [JobRequest]
        let queue: JobQueue
        let claimedJobs: ClaimedJobBatch?
        do {
            let eventQueue = try ShareEventQueue(container: container)
            shareEvents = try eventQueue.drain()
            await appleMusicShareCoordinator.notifyShareEvents(shareEvents)

            queue = try JobQueue(container: container)
            claimedJobs = try queue.claimPending()
            jobs = claimedJobs?.jobs ?? []
        } catch {
            DiagnosticLog.append("agent queue claim failed: \(error.localizedDescription)")
            return
        }

        let shareHandling = await appleMusicShareCoordinator.handleShareAppleMusicJobs(jobs)
        if let target = shareHandling.settingsAttention {
            await SettingsAttentionLauncher.open(target, container: container)
        }
        let remainingJobs = shareHandling.remainingJobs
        guard !jobs.isEmpty else {
            DiagnosticLog.append(shareEvents.isEmpty ? "agent no pending jobs" : "agent processed share events")
            return
        }
        guard !remainingJobs.isEmpty else {
            acknowledge(claimedJobs, queue: queue)
            return
        }

        DiagnosticLog.append("agent processing \(remainingJobs.count) jobs")
        let summary = await execute(remainingJobs)
        writeConversionLog(summary: summary, jobs: remainingJobs)
        await notificationService.enqueueAndDispatchConversionFinished(summary: summary, jobs: remainingJobs)
        acknowledge(claimedJobs, queue: queue)
    }

    private func execute(_ jobs: [JobRequest]) async -> ConversionSummary {
        var successCount = 0
        var failureCount = 0
        var messages: [String] = []
        let progress: @Sendable (JobRequest, JobProgressPhase, String?) -> Void = { job, phase, message in
            DiagnosticLog.append(
                "agent progress \(job.fileURL.lastPathComponent) → \(phase.rawValue)" +
                (message.map { " | \($0)" } ?? "")
            )
        }

        func merge(_ summary: ConversionSummary) {
            successCount += summary.successCount
            failureCount += summary.failureCount
            messages += summary.messages
        }

        let transcodeJobs = jobs.filter { if case .transcode = $0.operation { true } else { false } }
        let extractJobs = jobs.filter { $0.operation == .extractAudio }
        let ncmJobs = jobs.filter { $0.operation == .convertNCM }
        let appleMusicJobs = jobs.filter { if case .appleMusicDownload = $0.operation { true } else { false } }

        if !transcodeJobs.isEmpty {
            merge(await audioService.convert(transcodeJobs, progressHandler: progress))
        }
        if !extractJobs.isEmpty {
            merge(await mediaService.extractAudio(from: extractJobs, progressHandler: progress))
        }
        if !ncmJobs.isEmpty {
            merge(await ncmService.convert(ncmJobs, progressHandler: progress))
        }
        if !appleMusicJobs.isEmpty {
            await notificationService.notifyAppleMusicDownloadStarted()
            do {
                merge(try await appleMusicWorker.download(appleMusicJobs))
            } catch {
                merge(ConversionSummary(
                    successCount: 0,
                    failureCount: appleMusicJobs.count,
                    messages: [error.localizedDescription]
                ))
            }
        }

        return ConversionSummary(
            successCount: successCount,
            failureCount: failureCount,
            messages: messages
        )
    }

    private func acknowledge(_ batch: ClaimedJobBatch?, queue: JobQueue) {
        guard let batch else { return }
        do {
            try queue.acknowledge(batch)
        } catch {
            DiagnosticLog.append("agent queue acknowledge failed: \(error.localizedDescription)")
        }
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        var lines = [
            "===== background agent =====",
            "Result: success=\(summary.successCount) failure=\(summary.failureCount)"
        ]
        lines.append(contentsOf: jobs.map { "Job: \($0.fileURL.path)" })
        if !summary.messages.isEmpty {
            lines.append("Messages:")
            lines.append(contentsOf: summary.messages)
        }
        DiagnosticLog.append(lines.joined(separator: "\n"), level: .info)
    }
}
