import AppKit
import Combine
import FinderSync

@MainActor
final class SystemExtensionSettingsModel: ObservableObject {
    @Published private(set) var finderRestartMessage = ""
    @Published private(set) var isRestartingFinder = false

    func openFileProviderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func openShareExtensionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.share-services"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func restartFinder() {
        guard !isRestartingFinder else {
            return
        }

        isRestartingFinder = true
        finderRestartMessage = "正在重启 Finder…"

        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty {
            launchFinder()
            return
        }

        var scriptError: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"com.apple.finder\" to quit")
        guard script?.executeAndReturnError(&scriptError) != nil else {
            isRestartingFinder = false
            finderRestartMessage = finderQuitFailureMessage(scriptError)
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.launchFinder()
        }
    }

    private func launchFinder() {
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let configuration = NSWorkspace.OpenConfiguration()

        NSWorkspace.shared.openApplication(at: finderURL, configuration: configuration) { [weak self] application, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRestartingFinder = false

                if application != nil {
                    self.finderRestartMessage = "Finder 已重启。"
                } else {
                    self.finderRestartMessage = "Finder 已退出，但无法重新启动：\(error?.localizedDescription ?? "未知错误")"
                }
            }
        }
    }

    private func finderQuitFailureMessage(_ error: NSDictionary?) -> String {
        guard let message = error?[NSAppleScript.errorMessage] as? String, !message.isEmpty else {
            return "无法请求 Finder 退出，请在系统设置中允许 Get Oudio 控制 Finder。"
        }

        return "无法请求 Finder 退出：\(message)"
    }
}
