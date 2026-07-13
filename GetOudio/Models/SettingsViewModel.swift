import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class SettingsViewModel: ObservableObject {
    let presetSettings: PresetSettingsModel
    let finderSettings: FinderDirectorySettingsModel
    let systemExtensionSettings: SystemExtensionSettingsModel
    let ncmSettings: NCMSettingsModel
    let defaultOpenWithSettings: DefaultOpenWithSettingsModel
    let appleMusicSettings: AppleMusicSettingsModel
    let recordingSettings: RecordingSettingsModel
    let diagnosticSettings: DiagnosticSettingsModel

    init(container: SharedContainer) {
        let store = SettingsStore(container: container)
        presetSettings = PresetSettingsModel(store: store)
        finderSettings = FinderDirectorySettingsModel(store: store)
        systemExtensionSettings = SystemExtensionSettingsModel()
        ncmSettings = NCMSettingsModel(store: store)
        defaultOpenWithSettings = DefaultOpenWithSettingsModel(store: store)
        appleMusicSettings = AppleMusicSettingsModel(container: container, store: store)
        recordingSettings = RecordingSettingsModel(container: container, store: store)
        diagnosticSettings = DiagnosticSettingsModel(store: store)
    }
}
