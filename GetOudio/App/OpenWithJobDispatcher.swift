import AppKit
import GetOudioCore

final class OpenWithJobDispatcher {
    private let settingsStore: SettingsStore
    private let actionFactory: ConversionActionFactory

    init(container: AgentDataStore, actionFactory: ConversionActionFactory? = nil) {
        let settingsStore = SettingsStore(container: container)
        self.settingsStore = settingsStore
        self.actionFactory = actionFactory ?? ConversionActionFactory(settingsStore: settingsStore)
    }

    func enabledPresets() -> [ConversionPreset] {
        actionFactory.enabledPresets()
    }

    func makeAudioJobs(urls: [URL], preset: ConversionPreset) -> [JobRequest]? {
        guard ensureSourceDirectoryAccess(for: urls) else { return nil }
        let jobs = actionFactory.audioTranscodeJobs(for: urls, preset: preset, source: .openWith)
        guard jobs.count == urls.count, !jobs.isEmpty else {
            DiagnosticLog.append("open with enqueue audio rejected count=\(urls.count) jobs=\(jobs.count)")
            return nil
        }
        return jobs
    }

    func makeNCMJobs(urls: [URL]) -> [JobRequest]? {
        if settingsStore.ncmOutputMode == .sourceDirectory,
           !ensureSourceDirectoryAccess(for: urls) {
            return nil
        }
        let jobs = urls
            .filter { FileCategory.classify($0) == .ncm }
            .map {
                let directoryURL = $0.deletingLastPathComponent()
                return JobRequest(
                    fileURL: $0,
                    fileBookmarkData: JobRequest.securityScopedBookmarkData(for: $0),
                    directoryBookmarkData: settingsStore.directoryBookmarkData(for: directoryURL)
                        ?? JobRequest.securityScopedBookmarkData(for: directoryURL),
                    category: .ncm,
                    operation: .convertNCM,
                    source: .openWith
                )
            }

        guard jobs.count == urls.count, !jobs.isEmpty else {
            DiagnosticLog.append("open with enqueue ncm rejected count=\(urls.count) jobs=\(jobs.count)")
            return nil
        }
        return jobs
    }

    private func ensureSourceDirectoryAccess(for urls: [URL]) -> Bool {
        DirectoryAccessAuthorizer.authorizeSourceDirectories(
            urls.map { $0.deletingLastPathComponent() },
            store: settingsStore
        )
    }

    /// Waits for the Agent's durable queue acknowledgement. Callers must keep
    /// their transient process alive until this returns.
    func submit(_ jobs: [JobRequest], launchSource: LaunchSource) async -> Bool {
        guard !jobs.isEmpty else { return false }
        DiagnosticLog.append("open with agent enqueue source=\(launchSource.rawValue) count=\(jobs.count)")
        do {
            try await BackgroundAgentClient().enqueue(jobs)
            DiagnosticLog.append("open with agent enqueue acknowledged source=\(launchSource.rawValue) count=\(jobs.count)")
            return true
        } catch {
            DiagnosticLog.append("open with agent enqueue failed \(error.localizedDescription)")
            return false
        }
    }
}
