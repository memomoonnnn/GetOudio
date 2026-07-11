import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class SettingsViewModel: ObservableObject {
    let presetSettings: PresetSettingsModel
    let finderSettings: FinderDirectorySettingsModel
    let ncmSettings: NCMSettingsModel
    let defaultOpenWithSettings: DefaultOpenWithSettingsModel
    let appleMusicSettings: AppleMusicSettingsModel

    init(container: SharedContainer) {
        let store = SettingsStore(container: container)
        presetSettings = PresetSettingsModel(store: store)
        finderSettings = FinderDirectorySettingsModel(store: store)
        ncmSettings = NCMSettingsModel(store: store)
        defaultOpenWithSettings = DefaultOpenWithSettingsModel(store: store)
        appleMusicSettings = AppleMusicSettingsModel(container: container, store: store)
    }
}
