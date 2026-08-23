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
    private let store: SettingsStore
    private var observationCancellables = Set<AnyCancellable>()

    init(container: SharedContainer) {
        let store = SettingsStore(container: container)
        self.store = store
        presetSettings = PresetSettingsModel(store: store)
        finderSettings = FinderDirectorySettingsModel(store: store)
        systemExtensionSettings = SystemExtensionSettingsModel()
        ncmSettings = NCMSettingsModel(store: store)
        defaultOpenWithSettings = DefaultOpenWithSettingsModel(store: store)
        appleMusicSettings = AppleMusicSettingsModel(container: container, store: store)
        recordingSettings = RecordingSettingsModel(container: container, store: store)
        diagnosticSettings = DiagnosticSettingsModel(container: container, store: store)

        [
            recordingSettings.objectWillChange.eraseToAnyPublisher(),
            appleMusicSettings.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &observationCancellables)
        }
    }

    func hasOpenedSettingsDocumentation(_ item: SettingsAttentionItem) -> Bool {
        store.hasOpenedSettingsDocumentation(item)
    }

    func markSettingsDocumentationOpened(_ item: SettingsAttentionItem) {
        store.markSettingsDocumentationOpened(item)
        objectWillChange.send()
    }
}
