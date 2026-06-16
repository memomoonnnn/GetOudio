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
                Task {
                    guard appModel.receiveOpenFileURLs(urls) else { return }
                    if appModel.openItems.allSatisfy({ $0.category == .ncm }) {
                        await appModel.runOpenFileNCMConversionIfNeeded()
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "convert")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
            .onChange(of: appModel.progressWindowRequest) { _, request in
                guard request != nil else { return }
                NSApp.setActivationPolicy(.regular)
                if appModel.showsProgressInMainWindow {
                    configureProgressWindows(matching: ["Get Oudio"])
                } else {
                    openWindow(id: "progress")
                    DispatchQueue.main.async {
                        configureProgressWindows(matching: ["处理进度"])
                    }
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            .onOpenURL { url in
                guard url.scheme == AppConstants.appURLScheme else { return }
                Task {
                    let shouldOpenWindow = await appModel.receiveAndRunQueuedJobs()
                    if shouldOpenWindow {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "convert")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
    }

    private func configureProgressWindows(matching titles: Set<String>) {
        let size = progressWindowSize()

        for window in NSApp.windows where titles.contains(window.title) {
            window.title = "Get Oudio"
            window.styleMask.remove(.resizable)
            window.minSize = size
            window.maxSize = size
            window.setContentSize(size)
            window.center()
        }
    }

    private func progressWindowSize() -> NSSize {
        let rowHeight = 42
        let verticalPadding = 34
        let height = min(max(verticalPadding + appModel.progressItems.count * rowHeight, 120), 420)
        return NSSize(width: 520, height: height)
    }
}
