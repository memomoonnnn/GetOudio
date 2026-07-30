import AppKit
import GetOudioCore

@MainActor
enum SettingsGuidanceLauncher {
    static func open(_ target: SettingsGuidanceTarget, container: SharedContainer) {
        SettingsGuidanceStore(container: container).request(target)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                DiagnosticLog.append("settings guidance launch failed target=\(target.rawValue) error=\(error.localizedDescription)")
            }
        }
    }
}
