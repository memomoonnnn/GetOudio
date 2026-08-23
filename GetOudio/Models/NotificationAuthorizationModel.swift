import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class NotificationAuthorizationModel: ObservableObject {
    @Published private(set) var state: NotificationService.AuthorizationState = .notDetermined

    private let notificationService: NotificationService

    init(container: SharedContainer) {
        notificationService = NotificationService(container: container)
        refresh()
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            state = await notificationService.authorizationState()
        }
    }

    func requestAuthorization() {
        guard state == .notDetermined else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await notificationService.requestAuthorization()
            state = await notificationService.authorizationState()
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
