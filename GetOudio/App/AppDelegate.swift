import AppKit
import GetOudioCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Detected launch source.  Read by EventHandlingView.  In headless mode
    /// this delegate is never instantiated — `main.swift` routes to HeadlessRunner.
    private(set) var detectedLaunchSource: LaunchSource = .direct

    func applicationWillFinishLaunching(_ notification: Notification) {
        // In normal (non-headless) mode, the source can only be .direct.
        // Headless launches are intercepted in main.swift before SwiftUI starts.
        detectedLaunchSource = .direct
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task {
            await NotificationService().requestAuthorization()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty, urls.allSatisfy({ FileCategory.classify($0) == .ncm }) else {
            DiagnosticLog.append("app open files rejected non-ncm count=\(urls.count)")
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        DiagnosticLog.append("app open files ncm count=\(urls.count)")
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
}
