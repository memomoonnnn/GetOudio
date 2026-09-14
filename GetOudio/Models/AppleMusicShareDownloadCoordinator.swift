import Foundation
import GetOudioCore

final class AppleMusicShareDownloadCoordinator {
    private let container: AgentDataStore
    private let settingsStore: SettingsStore
    private let runtimeClient: AppleMusicRuntimeServing
    private let notificationService: NotificationService
    private let pendingStoreFactory: () throws -> PendingAppleMusicDownloadStore

    init(
        container: AgentDataStore,
        settingsStore: SettingsStore? = nil,
        runtimeClient: AppleMusicRuntimeServing,
        notificationService: NotificationService? = nil,
        pendingStoreFactory: (() throws -> PendingAppleMusicDownloadStore)? = nil
    ) {
        self.container = container
        self.settingsStore = settingsStore ?? SettingsStore(container: container)
        self.runtimeClient = runtimeClient
        self.notificationService = notificationService ?? NotificationService(container: container)
        self.pendingStoreFactory = pendingStoreFactory ?? { try PendingAppleMusicDownloadStore(container: container) }
    }

    func handleShareAppleMusicJobs(
        _ jobs: [JobRequest]
    ) async -> (remainingJobs: [JobRequest], settingsAttention: SettingsAttentionItem?) {
        let shareJobs = jobs.filter { $0.isShareAppleMusicDownload }
        let remainingJobs = jobs.filter { !$0.isShareAppleMusicDownload }
        guard !shareJobs.isEmpty else {
            return (remainingJobs, nil)
        }

        var guidance: SettingsAttentionItem?
        // Confirmed submissions may select different formats before one claim.
        // Do not apply the first submission's format to the entire batch.
        for format: AppleMusicDownloadFormat? in [nil, .alac, .aac, .atmos] {
            let group = shareJobs.filter { job in
                guard case .appleMusicDownload(let selected) = job.operation else { return false }
                return (selected == .askEveryTime ? nil : selected) == format
            }
            guard !group.isEmpty else { continue }
            let result = await handleAppleMusicJobs(group, forcedFormat: format)
            guidance = guidance ?? result
        }
        return (remainingJobs, guidance)
    }

    private func handleAppleMusicJobs(
        _ jobs: [JobRequest],
        forcedFormat: AppleMusicDownloadFormat? = nil
    ) async -> SettingsAttentionItem? {
        switch await appleMusicDownloadAvailability() {
        case .needsRuntimeInstallation:
            DiagnosticLog.append("Apple Music share requires Downloader Runtime installation")
            return .appleMusicDependencies
        case .needsInitialization:
            DiagnosticLog.append("Apple Music share requires wrapper initialization")
            return .appleMusicInitialization
        case .unavailable:
            await notificationService.notifyAppleMusicUnavailable()
            return nil
        case .ready:
            break
        }

        if forcedFormat == nil, settingsStore.appleMusicDownloadFormat == .askEveryTime {
            do {
                let batch = try pendingStoreFactory().save(jobs)
                await notificationService.notifyAppleMusicFormatSelection(
                    jobCount: jobs.count,
                    identifier: batch.id.uuidString
                )
            } catch {
                DiagnosticLog.append("pending Apple Music downloads save failed: \(error.localizedDescription)")
                await notificationService.notifyUnsupportedDownloadSource(urls: jobs.map(\.fileURL))
            }
            return nil
        }

        let format = forcedFormat ?? settingsStore.appleMusicDownloadFormat
        let resolvedJobs = jobs.map { $0.withAppleMusicDownloadFormat(format == .askEveryTime ? .alac : format) }
        DiagnosticLog.append("share Apple Music download started count=\(resolvedJobs.count) format=\(format.rawValue)")
        await notificationService.notifyAppleMusicDownloadStarted()
        let progressTask = startProgressNotifications()
        let summary: ConversionSummary
        do {
            summary = try await runtimeClient.download(resolvedJobs)
        } catch {
            summary = ConversionSummary(
                successCount: 0,
                failureCount: resolvedJobs.count,
                messages: [error.localizedDescription]
            )
        }
        progressTask.cancel()
        DiagnosticLog.append("share Apple Music download finished success=\(summary.successCount) failure=\(summary.failureCount)")
        writeConversionLog(summary: summary, jobs: resolvedJobs)
        await notificationService.enqueueAndDispatchConversionFinished(
            summary: summary,
            jobs: resolvedJobs
        )
        return nil
    }

    private enum AppleMusicDownloadAvailability {
        case ready
        case needsRuntimeInstallation
        case needsInitialization
        case unavailable
    }

    private func appleMusicDownloadAvailability() async -> AppleMusicDownloadAvailability {
        guard settingsStore.isAppleMusicDownloadEnabled else {
            return .needsRuntimeInstallation
        }

        do {
            let report = try await runtimeClient.status()
            guard report.isEnabled, report.statuses.allSatisfy(\.isReady) else {
                return .needsRuntimeInstallation
            }
            let loginStatus = try await runtimeClient.wrapperLoginStatus()
            return loginStatus.isAuthenticated ? .ready : .needsInitialization
        } catch {
            DiagnosticLog.append("Apple Music share activation check failed: \(error.localizedDescription)")
            return .unavailable
        }
    }

    private func startProgressNotifications() -> Task<Void, Never> {
        Task { [notificationService, runtimeClient] in
            var gate = AppleMusicDownloadNotificationGate(
                lastNotificationVersion: (try? await runtimeClient.progress())?.notificationVersion
            )
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                let progress = try? await runtimeClient.progress()
                guard let message = gate.nextMessage(for: progress) else { continue }
                await notificationService.notifyAppleMusicDownloadInProgress(progress: message)
            }
        }
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        var lines = [
            "===== share Apple Music =====",
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
        DiagnosticLog.append(lines.joined(separator: "\n"), level: .info)
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
