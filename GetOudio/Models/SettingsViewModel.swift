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
    let notificationAuthorization: NotificationAuthorizationModel
    let backgroundAgentAuthorization: BackgroundAgentAuthorizationModel
    let diagnosticSettings: DiagnosticSettingsModel
    let attentionState: SettingsAttentionState

    init(container: AgentDataStore) {
        let store = SettingsStore(container: container)
        presetSettings = PresetSettingsModel(store: store)
        finderSettings = FinderDirectorySettingsModel(store: store)
        systemExtensionSettings = SystemExtensionSettingsModel()
        ncmSettings = NCMSettingsModel(store: store)
        defaultOpenWithSettings = DefaultOpenWithSettingsModel(store: store)
        appleMusicSettings = AppleMusicSettingsModel(container: container, store: store)
        recordingSettings = RecordingSettingsModel(container: container, store: store)
        notificationAuthorization = NotificationAuthorizationModel(container: container)
        backgroundAgentAuthorization = BackgroundAgentAuthorizationModel()
        diagnosticSettings = DiagnosticSettingsModel(container: container, store: store)
        attentionState = SettingsAttentionState(
            store: store,
            recordingSettings: recordingSettings,
            notificationAuthorization: notificationAuthorization,
            backgroundAgentAuthorization: backgroundAgentAuthorization,
            appleMusicSettings: appleMusicSettings
        )
    }
}
