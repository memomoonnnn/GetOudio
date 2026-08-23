import Combine
import Foundation
import GetOudioCore

@MainActor
final class SettingsAttentionState: ObservableObject {
    private static let documentationItems: Set<SettingsAttentionItem> = [
        .transcodingDocumentation,
        .ncmDocumentation,
        .appleMusicDocumentation,
        .recordingDocumentation
    ]

    @Published private(set) var outstandingItems = Set<SettingsAttentionItem>()

    private let store: SettingsStore
    private let recordingSettings: RecordingSettingsModel
    private let notificationAuthorization: NotificationAuthorizationModel
    private let appleMusicSettings: AppleMusicSettingsModel
    private var observationCancellables = Set<AnyCancellable>()

    init(
        store: SettingsStore,
        recordingSettings: RecordingSettingsModel,
        notificationAuthorization: NotificationAuthorizationModel,
        appleMusicSettings: AppleMusicSettingsModel
    ) {
        self.store = store
        self.recordingSettings = recordingSettings
        self.notificationAuthorization = notificationAuthorization
        self.appleMusicSettings = appleMusicSettings

        [
            recordingSettings.objectWillChange.eraseToAnyPublisher(),
            notificationAuthorization.objectWillChange.eraseToAnyPublisher(),
            appleMusicSettings.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &observationCancellables)
        }
        refresh()
    }

    func markDocumentationOpened(_ item: SettingsAttentionItem) {
        store.markSettingsDocumentationOpened(item)
        refresh()
    }

    private func refresh() {
        var items: Set<SettingsAttentionItem> = []
        if !recordingSettings.microphoneAuthorized {
            items.insert(.microphonePermission)
        }
        if notificationAuthorization.state != .authorized {
            items.insert(.notificationPermission)
        }
        if !recordingSettings.hasConfiguredInput {
            items.insert(.recordingInput)
        }
        for item in Self.documentationItems where !store.hasOpenedSettingsDocumentation(item) {
            items.insert(item)
        }

        let dependenciesNeedAttention = !appleMusicSettings.isAppleMusicDownloadEnabled
            || (appleMusicSettings.hasLoadedAppleMusicRuntimeStatus && (
                appleMusicSettings.appleMusicRuntimeStatuses.isEmpty
                    || appleMusicSettings.appleMusicRuntimeStatuses.contains {
                        !$0.isReady || $0.updateState == .updateAvailable || $0.updateState == .legacy
                    }
            ))
        if dependenciesNeedAttention {
            items.insert(.appleMusicDependencies)
        } else if appleMusicSettings.hasLoadedAppleMusicRuntimeStatus,
                  !appleMusicSettings.appleMusicWrapperLoginStatus.isAuthenticated {
            items.insert(.appleMusicInitialization)
        }
        outstandingItems = items
    }
}
