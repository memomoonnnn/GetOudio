import AppKit
import Combine
import GetOudioCore

@MainActor
final class DiagnosticSettingsModel: ObservableObject {
    @Published var isDebugLoggingEnabled: Bool

    private let container: SharedContainer
    private let store: SettingsStore

    init(container: SharedContainer, store: SettingsStore) {
        self.container = container
        self.store = store
        isDebugLoggingEnabled = store.isDebugLoggingEnabled
    }

    func setDebugLoggingEnabled(_ isEnabled: Bool) {
        isDebugLoggingEnabled = isEnabled
        store.isDebugLoggingEnabled = isEnabled
    }

    func revealLogLocation() {
        let logURL = container.url(for: .conversionLog)
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            NSWorkspace.shared.open(logURL.deletingLastPathComponent())
        }
    }
}
