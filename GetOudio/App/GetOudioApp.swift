import SwiftUI

/// GetOudioApp is no longer the @main entry point.
/// Normal launches are handled by NormalLauncher (AppKit NSWindow + NSHostingController).
/// Headless launches are handled by HeadlessRunner.
/// This struct remains only to avoid breaking the project file list.
struct GetOudioApp: App {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}
