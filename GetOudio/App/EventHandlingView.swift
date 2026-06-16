import SwiftUI
import GetOudioCore

enum EventHandlingSceneRole {
    case main
    case convert
}

struct EventHandlingView<Content: View>: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    let content: Content
    let sceneRole: EventHandlingSceneRole

    init(sceneRole: EventHandlingSceneRole, @ViewBuilder content: () -> Content) {
        self.sceneRole = sceneRole
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                if sceneRole == .main { configureMainWindow() }
                else if sceneRole == .convert { configureFloatingPanel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .getOudioOpenFiles)) { notification in
                guard sceneRole == .main else { return }
                let urls = notification.userInfo?[OpenFileNotificationKey.urls] as? [URL] ?? []
                guard !urls.isEmpty else { return }
                Task {
                    guard appModel.receiveOpenFileURLs(urls) else { return }
                    if appModel.openItems.allSatisfy({ $0.category == .ncm }) {
                        await appModel.runNCMConversion()
                    }
                }
            }
            .onOpenURL { url in
                guard sceneRole == .main, url.scheme == AppConstants.appURLScheme else { return }
                Task { await handleURLScheme(url) }
            }
    }

    // MARK: - Window Configuration

    /// Configure the main window:
    /// 1. Apply floating-panel properties (above normal windows, invisible to Stage Manager)
    /// 2. Promote from LSUIElement/background to foreground if needed
    private func configureMainWindow() {
        if let delegate = NSApp.delegate as? AppDelegate {
            appModel.launchSource = delegate.detectedLaunchSource
        }

        // Apply floating-panel attributes
        configureFloatingPanel()

        // Bring to front — necessary after TransformProcessType foreground
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Get Oudio" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Make the window float above normal windows and be excluded from
    /// Stage Manager, Mission Control, and third-party window managers.
    private func configureFloatingPanel() {
        guard let window = NSApp.windows.first(where: {
            $0.title == "Get Oudio" || $0.title == "转换"
        }) else { return }

        window.level = .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
    }

    // MARK: - URL Scheme (from Finder/Share extensions)

    private func handleURLScheme(_ url: URL) async {
        await appModel.processQueuedJobsInBackground()
    }
}
