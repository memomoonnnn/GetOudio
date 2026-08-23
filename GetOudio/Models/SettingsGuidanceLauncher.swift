import AppKit
import GetOudioCore

@MainActor
enum SettingsAttentionLauncher {
    static func open(_ item: SettingsAttentionItem, container: SharedContainer) {
        SettingsAttentionRequestStore(container: container).request(item)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                DiagnosticLog.append("settings attention launch failed item=\(item.rawValue) error=\(error.localizedDescription)")
            }
        }
    }
}
