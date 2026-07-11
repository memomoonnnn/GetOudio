import Foundation
import GetOudioCore

final class AppleMusicShareDownloadCoordinator {
    private let container: SharedContainer
    private let settingsStore: SettingsStore
    private let agentClient: AppleMusicRuntimeAgentClient
    private let agentLauncher: AppleMusicRuntimeAgentLauncher
    private let downloadService: AppleMusicDownloadService
    private let notificationService: NotificationService
    private let pendingStoreFactory: () throws -> PendingAppleMusicDownloadStore

    init(
        container: SharedContainer,
        settingsStore: SettingsStore? = nil,
        agentClient: AppleMusicRuntimeAgentClient? = nil,
        agentLauncher: AppleMusicRuntimeAgentLauncher = .shared,
        downloadService: AppleMusicDownloadService? = nil,
        notificationService: NotificationService? = nil,
        pendingStoreFactory: (() throws -> PendingAppleMusicDownloadStore)? = nil
    ) {
        self.container = container
        self.settingsStore = settingsStore ?? SettingsStore(container: container)
        self.agentClient = agentClient ?? AppleMusicRuntimeAgentClient(container: container)
        self.agentLauncher = agentLauncher
        self.downloadService = downloadService ?? AppleMusicDownloadService(container: container)
        self.notificationService = notificationService ?? NotificationService(container: container)
        self.pendingStoreFactory = pendingStoreFactory ?? { try PendingAppleMusicDownloadStore(container: container) }
    }

    func notifyShareEvents(_ events: [ShareEvent]) async {
        for event in events where event.kind == .unsupportedDownloadSource {
            await notificationService.notifyUnsupportedDownloadSource(urls: event.urls)
        }
    }

    func handleShareAppleMusicJobs(_ jobs: [JobRequest]) async -> [JobRequest] {
        let shareJobs = jobs.filter { $0.isShareAppleMusicDownload }
        let remainingJobs = jobs.filter { !$0.isShareAppleMusicDownload }
        guard !shareJobs.isEmpty else {
            return remainingJobs
        }

        await handleAppleMusicJobs(shareJobs)
        return remainingJobs
    }

    func handlePendingAppleMusicDownload(format: AppleMusicDownloadFormat) async {
        do {
            guard let batch = try pendingStoreFactory().drain(), !batch.jobs.isEmpty else {
                await notificationService.notifyUnsupportedDownloadSource(urls: [])
                return
            }
            await handleAppleMusicJobs(batch.jobs, forcedFormat: format)
        } catch {
            DiagnosticLog.append("pending Apple Music downloads failed: \(error.localizedDescription)")
            await notificationService.notifyUnsupportedDownloadSource(urls: [])
        }
    }

    private func handleAppleMusicJobs(_ jobs: [JobRequest], forcedFormat: AppleMusicDownloadFormat? = nil) async {
        guard await isAppleMusicDownloadActive() else {
            await notificationService.notifyAppleMusicInactive()
            return
        }

        if forcedFormat == nil, settingsStore.appleMusicDownloadFormat == .askEveryTime {
            do {
                _ = try pendingStoreFactory().save(jobs)
                markShareExtensionHeadlessLaunch()
                await notificationService.notifyAppleMusicFormatSelection(jobCount: jobs.count)
            } catch {
                DiagnosticLog.append("pending Apple Music downloads save failed: \(error.localizedDescription)")
                await notificationService.notifyUnsupportedDownloadSource(urls: jobs.map(\.fileURL))
            }
            return
        }

        let format = forcedFormat ?? settingsStore.appleMusicDownloadFormat
        let resolvedJobs = jobs.map { $0.withAppleMusicDownloadFormat(format == .askEveryTime ? .alac : format) }
        DiagnosticLog.append("share Apple Music download started count=\(resolvedJobs.count) format=\(format.rawValue)")
        let progressTask = startProgressNotifications()
        let summary = await downloadService.download(resolvedJobs)
        progressTask.cancel()
        DiagnosticLog.append("share Apple Music download finished success=\(summary.successCount) failure=\(summary.failureCount)")
        writeConversionLog(summary: summary, jobs: resolvedJobs)
        let dispatched = await notificationService.dispatchPendingNotificationEvents()
        DiagnosticLog.append("share Apple Music completion notification dispatched count=\(dispatched)")
    }

    private func isAppleMusicDownloadActive() async -> Bool {
        guard settingsStore.isAppleMusicDownloadEnabled else {
            return false
        }

        do {
            try await agentLauncher.ensureRunning()
            let report = try await agentClient.status()
            guard report.isEnabled, report.statuses.allSatisfy(\.isReady) else {
                return false
            }
            return hasCompletedAppleMusicAuthentication()
        } catch {
            DiagnosticLog.append("Apple Music share activation check failed: \(error.localizedDescription)")
            return false
        }
    }

    private func hasCompletedAppleMusicAuthentication() -> Bool {
        let manager = AppleMusicRuntimeManager(container: container, resourceRoot: Bundle.main.resourceURL)
        let markerURL = manager.wrapperDataDirectory.appendingPathComponent(".login-completed")
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    private func startProgressNotifications() -> Task<Void, Never> {
        Task { [notificationService, agentClient] in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                let progress = agentClient.progress()
                await notificationService.notifyAppleMusicDownloadInProgress(
                    elapsed: Date().timeIntervalSince(start),
                    progress: progress?.isActive == true ? progress?.message : nil
                )
            }
        }
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        do {
            let logURL = container.url(for: .conversionLog)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var lines = [
                "===== \(timestamp) (share Apple Music) =====",
                "Result: success=\(summary.successCount) failure=\(summary.failureCount)"
            ]
            for job in jobs {
                lines.append("Job: \(job.fileURL.absoluteString)")
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
            DiagnosticLog.append("share Apple Music log write failed: \(error.localizedDescription)")
        }
    }

    private func markShareExtensionHeadlessLaunch() {
        LaunchMarkerStore(container: container).mark(.shareExtension)
    }
}

private extension JobRequest {
    var isShareAppleMusicDownload: Bool {
        guard source == .shareExtension else {
            return false
        }
        if case .appleMusicDownload = operation {
            return true
        }
        return false
    }

    func withAppleMusicDownloadFormat(_ format: AppleMusicDownloadFormat) -> JobRequest {
        JobRequest(
            id: id,
            fileURL: fileURL,
            fileBookmarkData: fileBookmarkData,
            directoryBookmarkData: directoryBookmarkData,
            category: .appleMusic,
            operation: .appleMusicDownload(format),
            source: source,
            createdAt: createdAt
        )
    }
}
