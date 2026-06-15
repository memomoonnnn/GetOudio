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
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Label("设置...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("转换", id: "convert") {
            EventHandlingView {
                ConvertWindowView()
            }
            .environmentObject(appModel)
        }
        .defaultSize(width: 760, height: 560)

        Settings {
            SettingsView()
        }
    }
}
