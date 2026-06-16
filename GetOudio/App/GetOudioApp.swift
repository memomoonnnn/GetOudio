import SwiftUI

@main
struct GetOudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Get Oudio", id: "main") {
            EventHandlingView {
                if appModel.showsProgressInMainWindow {
                    ProgressWindowView()
                } else {
                    MainView()
                }
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

        Window("处理进度", id: "progress") {
            EventHandlingView {
                ProgressWindowView()
            }
            .environmentObject(appModel)
        }
        .defaultSize(width: 520, height: 220)
        .windowResizability(.contentSize)
    }
}
