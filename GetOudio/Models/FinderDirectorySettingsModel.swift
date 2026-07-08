import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class FinderDirectorySettingsModel: ObservableObject {
    @Published var finderDirectories: [URL]
    @Published var finderDirectoryMessage = ""

    private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        finderDirectories = store.finderDirectoryURLs
    }

    func addFinderDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        panel.message = "选择要启用 Get Oudio Finder 菜单的目录"
        panel.directoryURL = SettingsStore.realUserHomeDirectory()

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                Task { @MainActor in
                    self?.appendFinderDirectories(panel.urls)
                }
            }
        } else if panel.runModal() == .OK {
            appendFinderDirectories(panel.urls)
        }
    }

    func removeFinderDirectories(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            finderDirectories.remove(at: index)
        }
        saveFinderDirectories()
    }

    func removeFinderDirectory(_ url: URL) {
        finderDirectories.removeAll { $0 == url }
        saveFinderDirectories()
    }

    func revealFinderDirectory(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func restoreDefaultFinderDirectories() {
        finderDirectories = SettingsStore.defaultFinderDirectories()
        saveFinderDirectories()
    }

    private func appendFinderDirectories(_ urls: [URL]) {
        let merged = finderDirectories + urls
        finderDirectories = Array(Set(merged.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        saveFinderDirectories()
    }

    private func saveFinderDirectories() {
        store.finderDirectoryURLs = finderDirectories
        finderDirectories = store.finderDirectoryURLs
        finderDirectoryMessage = "已保存 \(finderDirectories.count) 个 Finder 监听目录；重启 Finder 后生效。"
    }
}
