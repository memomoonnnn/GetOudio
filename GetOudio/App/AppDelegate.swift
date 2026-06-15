import AppKit
import GetOudioCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        Task {
            await NotificationService().requestAuthorization()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.post(name: .getOudioOpenFiles, object: nil, userInfo: [OpenFileNotificationKey.urls: urls])
        sender.reply(toOpenOrPrint: .success)
    }
}

