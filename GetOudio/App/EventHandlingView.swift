import SwiftUI
import GetOudioCore

struct EventHandlingView<Content: View>: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .getOudioOpenFiles)) { notification in
                let urls = notification.userInfo?[OpenFileNotificationKey.urls] as? [URL] ?? []
                guard !urls.isEmpty else { return }
                appModel.receiveOpenFileURLs(urls)
                openWindow(id: "convert")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onOpenURL { url in
                guard url.scheme == AppConstants.appURLScheme else { return }
                Task {
                    await appModel.receiveQueuedJobs()
                    openWindow(id: "convert")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
