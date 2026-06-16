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
                if sceneRole == .main { configureOnAppear() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .getOudioOpenFiles)) { notification in
                guard sceneRole == .main else { return }
                let urls = notification.userInfo?[OpenFileNotificationKey.urls] as? [URL] ?? []
                guard !urls.isEmpty else { return }
                Task {
                    guard appModel.receiveOpenFileURLs(urls) else { return }
                    if appModel.openItems.allSatisfy({ $0.category == .ncm }) {
                        // NCM files: run silently in background, show notification
                        await appModel.runNCMConversion()
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "convert")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
            .onOpenURL { url in
                guard sceneRole == .main, url.scheme == AppConstants.appURLScheme else { return }
                Task { await handleURLScheme(url) }
            }
    }

    // MARK: - Launch

    private func configureOnAppear() {
        if let delegate = NSApp.delegate as? AppDelegate {
            appModel.launchSource = delegate.detectedLaunchSource
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - URL Scheme (from Finder/Share extensions)

    private func handleURLScheme(_ url: URL) async {
        let shouldOpenConvert = await appModel.processQueuedJobsInBackground()
        if shouldOpenConvert {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "convert")
            NSApp.activate(ignoringOtherApps: true)
        }
        // If not opening convert window: jobs are processed silently in background.
        // Notification is sent by AppModel when done.
    }
}
