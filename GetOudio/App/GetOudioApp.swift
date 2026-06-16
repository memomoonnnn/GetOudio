import SwiftUI

struct GetOudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        // Main window — NavigationSplitView for settings & overview
        WindowGroup("Get Oudio", id: "main") {
            EventHandlingView(sceneRole: .main) {
                MainView()
            }
            .environmentObject(appModel)
        }
        .defaultSize(width: 820, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Convert/confirmation window
        Window("转换", id: "convert") {
            EventHandlingView(sceneRole: .convert) {
                ConvertWindowView()
            }
            .environmentObject(appModel)
        }
        .defaultSize(width: 760, height: 560)
    }
}
