import SwiftUI

@main
struct GetOudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Get Oudio", id: "main") {
            EventHandlingView {
                MainView()
            }
            .environmentObject(appModel)
        }

        Window("转换", id: "convert") {
            EventHandlingView {
                ConvertWindowView()
            }
            .environmentObject(appModel)
        }
        .defaultSize(width: 760, height: 560)
    }
}
