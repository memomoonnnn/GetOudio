import AppKit
import GetOudioCore
import SwiftUI
import UserNotifications

/// Launched when the user opens Get Oudio.app directly.
/// With LSUIElement=true in Info.plist, SwiftUI's WindowGroup cannot create
/// visible windows.  Instead we manually build NSWindow + NSHostingController
/// and apply floating-panel attributes so the window sits above normal windows
/// and is invisible to Stage Manager / window managers.
final class NormalLauncher: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var appModel: AppModel!
    private var mainWindow: NSWindow?
    private var convertWindow: NSWindow?

    // MARK: - Entry point

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let launcher = NormalLauncher()
            launcher.appModel = AppModel()
            app.delegate = launcher
            app.run()
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register URL scheme handler for getoudio:// events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task {
            await NotificationService().requestAuthorization()
        }

        // Build the main window
        let contentView = MainView().environmentObject(appModel)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Get Oudio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 600))
        window.isReleasedWhenClosed = false

        // Floating panel attributes
        window.level = .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        window.center()
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

        NSApp.activate(ignoringOtherApps: true)
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

        guard appModel.receiveOpenFileURLs(urls) else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        Task {
            await appModel.runNCMConversion()
        }
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: - URL Scheme (getoudio://)

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == AppConstants.appURLScheme else { return }

        Task {
            let shouldOpenConvert = await appModel.processQueuedJobsInBackground()
            if shouldOpenConvert {
                await MainActor.run { openConvertWindow() }
            }
        }
    }

    // MARK: - Convert Window

    private func openConvertWindow() {
        if convertWindow == nil {
            let contentView = ConvertWindowView().environmentObject(appModel)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "转换"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            window.center()
            convertWindow = window
        }
        convertWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
