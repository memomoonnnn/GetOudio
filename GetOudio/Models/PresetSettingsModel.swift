import Combine
import Foundation
import GetOudioCore

@MainActor
final class PresetSettingsModel: ObservableObject {
    @Published var enabledPresets: Set<ConversionPreset>

    private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        enabledPresets = store.enabledPresets
    }

    func toggle(_ preset: ConversionPreset, isEnabled: Bool) {
        if isEnabled {
            enabledPresets.insert(preset)
        } else {
            guard enabledPresets.count > 1 else {
                enabledPresets = store.enabledPresets
                return
            }
            enabledPresets.remove(preset)
        }
        store.enabledPresets = enabledPresets
        enabledPresets = store.enabledPresets
    }
}
