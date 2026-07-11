import AppKit
import Darwin
import GetOudioCore

// Headless detection
//
//   • Direct launch without marker → NormalLauncher shows the settings window.
//   • Finder/Share/Open With marker → HeadlessRunner drains JobQueue, notifies, exits.
//   • Transient Open With UI is menu-style and only enqueues work.

let sharedContainer: SharedContainer
do {
    sharedContainer = try SharedContainer.forCurrentProcess()
    DiagnosticLog.configure(container: sharedContainer)
} catch {
    NSLog("Get Oudio shared container unavailable: \(error.localizedDescription)")
    let alert = NSAlert()
    alert.messageText = "Get Oudio 无法访问共享容器"
    alert.informativeText = "请检查应用签名和 App Group 配置后重新启动。\n\n\(error.localizedDescription)"
    alert.alertStyle = .critical
    alert.runModal()
    exit(EXIT_FAILURE)
}

let isHeadless = LaunchMarkerStore(container: sharedContainer).activeSource() != nil

if isHeadless {
    HeadlessRunner.main(container: sharedContainer)
} else {
    NormalLauncher.main(container: sharedContainer)
}
