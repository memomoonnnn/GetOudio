import AppKit
import GetOudioCore
import SwiftUI
import UserNotifications

/// Handles direct settings-window launches and transient Open With interactions.
/// Background conversion is delegated to HeadlessRunner through JobQueue.
final class NormalLauncher: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum SettingsWindowMetrics {
        static let outerMargin: CGFloat = 22
        static let sidebarWidth: CGFloat = 272
        static let settingsContentMaxWidth: CGFloat = 760
        static let contentMaxWidth: CGFloat = outerMargin + sidebarWidth + outerMargin + settingsContentMaxWidth + outerMargin
        static let contentMinWidth: CGFloat = 900
        static let contentMinHeight: CGFloat = 560
        static let contentInitialHeight: CGFloat = 660
        static let windowCornerRadius: CGFloat = 28
    }

    private enum LaunchIntent {
        case undecided
        case settings
        case transientOpenWith
        case backgroundWake
    }

    private var mainWindow: NSWindow?
    private let container: SharedContainer
    private let notificationService: NotificationService
    private let openWithDispatcher: OpenWithJobDispatcher
    private let recordingControl: RecordingControlCoordinator
    private let openWithMenuController = OpenWithPresetMenuController()
    private var launchIntent: LaunchIntent = .undecided
    private var activeNotificationResponses = 0
    private var isPresentingAudioMenu = false
    private var lastAudioOpenSignature: String?
    private var lastAudioOpenDate = Date.distantPast
    private var isSupervisingRecording = false

    init(container: SharedContainer) {
        self.container = container
        notificationService = NotificationService(container: container)
        openWithDispatcher = OpenWithJobDispatcher(container: container)
        recordingControl = RecordingControlCoordinator(container: container)
        super.init()
    }

    // MARK: - Entry point

    static func main(container: SharedContainer) {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let launcher = NormalLauncher(container: container)
            app.delegate = launcher
            launcher.installURLHandler()
            DiagnosticLog.append("[Recording] normal launcher ready; URL handler installed before app run")
            app.run()
        }
    }

    // MARK: - NSApplicationDelegate

    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.append("[Recording] normal launcher did finish launching")
        UNUserNotificationCenter.current().delegate = self

        Task {
            await notificationService.requestAuthorization()
            await notificationService.dispatchPendingNotificationEvents()
        }

        recordingControl.recoverStaleSessionIfNeeded()

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
        DiagnosticLog.append("[Recording] delayed settings decision intent=\(String(describing: launchIntent))")
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

    private func showSettingsWindow(recordingPage: Bool = false) {
        if let mainWindow {
            NSApp.setActivationPolicy(.regular)
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if recordingPage {
                NotificationCenter.default.post(name: .getOudioShowRecordingSettings, object: nil)
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        let hostingController = NSHostingController(
            rootView: MainView(container: container, initialRecordingPage: recordingPage)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.setAccessibilityTitle("Get Oudio")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = SettingsWindowMetrics.windowCornerRadius
        window.contentView?.layer?.masksToBounds = true
        window.contentMinSize = NSSize(
            width: SettingsWindowMetrics.contentMinWidth,
            height: SettingsWindowMetrics.contentMinHeight
        )
        window.contentMaxSize = NSSize(
            width: SettingsWindowMetrics.contentMaxWidth,
            height: 10_000
        )
        window.setContentSize(NSSize(
            width: SettingsWindowMetrics.contentMaxWidth,
            height: SettingsWindowMetrics.contentInitialHeight
        ))
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
        hideStandardWindowControls(in: window)
        mainWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideStandardWindowControls(in window: NSWindow) {
        DispatchQueue.main.async {
            let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for buttonType in buttonTypes {
                guard let button = window.standardWindowButton(buttonType) else { continue }
                button.isHidden = true
            }
        }
    }

    // MARK: - URL Scheme (getoudio://)

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == AppConstants.appURLScheme else { return }

        if url.host == "recording" {
            DiagnosticLog.append("[Recording] toggle URL received path=\(url.path)")
            if mainWindow?.isVisible != true { launchIntent = .backgroundWake }
            let result = recordingControl.toggle { [weak self] in
                guard let self else { return }
                self.isSupervisingRecording = false
                self.finishTransientInteractionIfNeeded()
            }
            switch result {
            case .launchedRunner:
                DiagnosticLog.append("[Recording] toggle result=launchedRunner")
                isSupervisingRecording = true
            case .requestedStop:
                DiagnosticLog.append("[Recording] toggle result=requestedStop")
                finishTransientInteractionIfNeeded()
            case .needsConfiguration:
                DiagnosticLog.append("[Recording] toggle result=needsConfiguration")
                launchIntent = .settings
                showSettingsWindow(recordingPage: true)
            case .failed(let message):
                DiagnosticLog.append("[Recording] toggle result=failed error=\(message)")
                Task { await notificationService.notifyRecordingFinished(fileURL: nil, message: message) }
                finishTransientInteractionIfNeeded()
            }
            return
        }

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
              !isSupervisingRecording,
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
            await AppleMusicShareDownloadCoordinator(container: container)
                .handlePendingAppleMusicDownload(format: format)
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
