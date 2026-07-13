import Combine
import GetOudioCore

@MainActor
final class DiagnosticSettingsModel: ObservableObject {
    @Published var isDebugLoggingEnabled: Bool

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        isDebugLoggingEnabled = store.isDebugLoggingEnabled
    }

    func setDebugLoggingEnabled(_ isEnabled: Bool) {
        isDebugLoggingEnabled = isEnabled
        store.isDebugLoggingEnabled = isEnabled
    }
}
