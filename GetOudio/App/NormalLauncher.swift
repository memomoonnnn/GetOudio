import AppKit
import GetOudioCore
import SwiftUI
import UserNotifications

/// Handles direct settings-window launches and transient Open With interactions.
/// Background conversion is delegated to HeadlessRunner through JobQueue.
final class NormalLauncher: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum LaunchIntent {
        case undecided
        case settings
        case transientOpenWith
        case backgroundWake
    }

    private var mainWindow: NSWindow?
    private let notificationService = NotificationService()
    private let openWithDispatcher = OpenWithJobDispatcher()
    private let openWithMenuController = OpenWithPresetMenuController()
    private var launchIntent: LaunchIntent = .undecided
    private var activeNotificationResponses = 0
    private var isPresentingAudioMenu = false
    private var lastAudioOpenSignature: String?
    private var lastAudioOpenDate = Date.distantPast

    // MARK: - Entry point

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let launcher = NormalLauncher()
            app.delegate = launcher
            app.run()
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
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
            await notificationService.requestAuthorization()
            await notificationService.dispatchPendingNotificationEvents()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            showSettingsWindowIfNeeded()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        activeNotificationResponses == 0
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else {
            DiagnosticLog.append("app open files rejected empty")
            markTransientOpenWithIfNoSettingsWindow()
            sender.reply(toOpenOrPrint: .failure)
            finishTransientInteractionIfNeeded()
            return
        }

        if urls.allSatisfy({ FileCategory.classify($0) == .audio }) {
            sender.reply(toOpenOrPrint: .success)
            presentOpenWithAudioMenu(for: urls)
            return
        }

        guard urls.allSatisfy({ FileCategory.classify($0) == .ncm }) else {
            DiagnosticLog.append("app open files rejected unsupported count=\(urls.count)")
            markTransientOpenWithIfNoSettingsWindow()
            sender.reply(toOpenOrPrint: .failure)
            finishTransientInteractionIfNeeded()
            return
        }

        markTransientOpenWithIfNoSettingsWindow()
        DiagnosticLog.append("app open files ncm enqueue count=\(urls.count)")
        let didEnqueue = openWithDispatcher.enqueueNCMJobs(urls: urls)
        sender.reply(toOpenOrPrint: didEnqueue ? .success : .failure)
        finishTransientInteractionIfNeeded()
    }

    private func showSettingsWindowIfNeeded() {
        guard launchIntent == .undecided || launchIntent == .settings else { return }
        if let mainWindow {
            NSApp.setActivationPolicy(.regular)
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        launchIntent = .settings
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let hostingController = NSHostingController(rootView: MainView())

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Get Oudio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 600))
        window.isReleasedWhenClosed = false
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

    // MARK: - URL Scheme (getoudio://)

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == AppConstants.appURLScheme else { return }

        DiagnosticLog.append("normal url wake forwarded \(url.absoluteString)")
        if mainWindow?.isVisible != true {
            launchIntent = .backgroundWake
        }
        openWithDispatcher.launchHeadlessProcessor()
        finishTransientInteractionIfNeeded()
    }

    private func presentOpenWithAudioMenu(for urls: [URL]) {
        markTransientOpenWithIfNoSettingsWindow()

        guard !isPresentingAudioMenu, !isDuplicateAudioOpenEvent(urls) else {
            DiagnosticLog.append("app open files audio duplicate ignored count=\(urls.count)")
            return
        }

        isPresentingAudioMenu = true
        DiagnosticLog.append("app open files audio menu count=\(urls.count)")
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        openWithMenuController.present(
            fileURLs: urls,
            presets: openWithDispatcher.enabledPresets(),
            at: NSEvent.mouseLocation,
            onSelect: { [weak self] preset in
                self?.enqueueOpenWithAudio(urls: urls, preset: preset)
            },
            onCancel: { [weak self] in
                self?.finishTransientInteractionIfNeeded()
            }
        )
        isPresentingAudioMenu = false
        finishTransientInteractionIfNeeded()
    }

    private func enqueueOpenWithAudio(urls: [URL], preset: ConversionPreset) {
        DiagnosticLog.append("app open files audio enqueue preset=\(preset.rawValue) count=\(urls.count)")
        _ = openWithDispatcher.enqueueAudioJobs(urls: urls, preset: preset)
    }

    private func markTransientOpenWithIfNoSettingsWindow() {
        if mainWindow?.isVisible != true {
            launchIntent = .transientOpenWith
        }
    }

    private func finishTransientInteractionIfNeeded() {
        guard mainWindow?.isVisible != true,
              activeNotificationResponses == 0,
              launchIntent == .transientOpenWith || launchIntent == .backgroundWake else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self.mainWindow?.isVisible != true, self.activeNotificationResponses == 0 else { return }
            NSApp.terminate(nil)
        }
    }

    private func isDuplicateAudioOpenEvent(_ urls: [URL]) -> Bool {
        let signature = urls.map(\.standardizedFileURL.path).sorted().joined(separator: "\n")
        let now = Date()
        defer {
            lastAudioOpenSignature = signature
            lastAudioOpenDate = now
        }
        return lastAudioOpenSignature == signature && now.timeIntervalSince(lastAudioOpenDate) < 1.5
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let copyInfo = notificationService.copyInfo(for: response) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyInfo, forType: .string)
            completionHandler()
            return
        }

        guard let format = notificationService.appleMusicFormat(for: response.actionIdentifier) else {
            completionHandler()
            return
        }

        beginNotificationResponse()
        Task {
            await AppleMusicShareDownloadCoordinator().handlePendingAppleMusicDownload(format: format)
            completionHandler()
            await MainActor.run {
                self.endNotificationResponse()
            }
        }
    }

    private func beginNotificationResponse() {
        activeNotificationResponses += 1
        DiagnosticLog.append("normal notification response started active=\(activeNotificationResponses)")
    }

    @MainActor
    private func endNotificationResponse() {
        activeNotificationResponses = max(0, activeNotificationResponses - 1)
        DiagnosticLog.append("normal notification response finished active=\(activeNotificationResponses)")
        finishTransientInteractionIfNeeded()
    }
}
