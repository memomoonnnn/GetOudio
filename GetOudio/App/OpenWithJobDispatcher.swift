import AppKit
import GetOudioCore

final class OpenWithJobDispatcher {
    private let container: SharedContainer
    private let actionFactory: ConversionActionFactory

    init(container: SharedContainer, actionFactory: ConversionActionFactory? = nil) {
        self.container = container
        self.actionFactory = actionFactory ?? ConversionActionFactory(container: container)
    }

    func enabledPresets() -> [ConversionPreset] {
        actionFactory.enabledPresets()
    }

    func enqueueAudioJobs(urls: [URL], preset: ConversionPreset) -> Bool {
        let jobs = actionFactory.audioTranscodeJobs(for: urls, preset: preset, source: .openWith)
        guard jobs.count == urls.count, !jobs.isEmpty else {
            DiagnosticLog.append("open with enqueue audio rejected count=\(urls.count) jobs=\(jobs.count)")
            return false
        }

        return enqueue(jobs, launchSource: .openWithAudio)
    }

    func enqueueNCMJobs(urls: [URL]) -> Bool {
        let jobs = urls
            .filter { FileCategory.classify($0) == .ncm }
            .map {
                JobRequest(
                    fileURL: $0,
                    fileBookmarkData: JobRequest.securityScopedBookmarkData(for: $0),
                    directoryBookmarkData: JobRequest.securityScopedBookmarkData(for: $0.deletingLastPathComponent()),
                    category: .ncm,
                    operation: .convertNCM,
                    source: .openWith
                )
            }

        guard jobs.count == urls.count, !jobs.isEmpty else {
            DiagnosticLog.append("open with enqueue ncm rejected count=\(urls.count) jobs=\(jobs.count)")
            return false
        }

        return enqueue(jobs, launchSource: .openWithNCM)
    }

    func launchHeadlessProcessor() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        if let diagnosticRoot = ProcessInfo.processInfo.environment[SharedContainer.diagnosticRootEnvironmentKey] {
            configuration.environment = [SharedContainer.diagnosticRootEnvironmentKey: diagnosticRoot]
        }

        let bundleURL = Bundle.main.bundleURL
        DiagnosticLog.append("open with launch headless bundle=\(bundleURL.path)")
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                DiagnosticLog.append("open with launch headless failed \(error.localizedDescription)")
            } else {
                DiagnosticLog.append("open with launch headless requested")
            }
        }
    }

    private func enqueue(_ jobs: [JobRequest], launchSource: LaunchSource) -> Bool {
        do {
            DiagnosticLog.append("open with enqueue start source=\(launchSource.rawValue) count=\(jobs.count)")
            let intake = try JobIntake(container: container)
            try intake.enqueue(jobs, launchSource: launchSource)
            launchHeadlessProcessor()
            return true
        } catch {
            DiagnosticLog.append("open with enqueue failed \(error.localizedDescription)")
            return false
        }
    }
}
