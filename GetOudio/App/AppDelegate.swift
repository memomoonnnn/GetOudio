import AppKit
import GetOudioCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(hasPendingQueuedJobs() ? .accessory : .regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(hasPendingQueuedJobs() ? .accessory : .regular)
        UNUserNotificationCenter.current().delegate = self

        Task {
            await NotificationService().requestAuthorization()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.post(name: .getOudioOpenFiles, object: nil, userInfo: [OpenFileNotificationKey.urls: urls])
        sender.reply(toOpenOrPrint: .success)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func hasPendingQueuedJobs() -> Bool {
        do {
            return try !JobQueue().read().isEmpty
        } catch {
            return false
        }
    }
}
