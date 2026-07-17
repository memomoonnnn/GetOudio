import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class FinderDirectorySettingsModel: ObservableObject {
    @Published var finderDirectories: [URL]
    @Published var finderDirectoryMessage = ""

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        finderDirectories = store.finderDirectoryURLs
    }

    func addFinderDirectory() {
        let urls = DirectoryChooser.chooseDirectories(
            prompt: "添加",
            message: "选择要允许 Get Oudio 访问并显示 Finder 菜单的文件夹。",
            initialDirectory: SettingsStore.realUserHomeDirectory(),
            allowsMultipleSelection: true
        )
        appendFinderDirectories(urls)
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

    func resetFinderDirectories() {
        let defaultDirectories = SettingsStore.defaultFinderDirectories()
        guard !defaultDirectories.isEmpty else {
            finderDirectoryMessage = "没有可重置的默认文件/文件夹访问权限。"
            return
        }

        guard let authorizationRoot = DirectoryChooser.chooseDirectory(
            prompt: "授权并重置",
            message: "选择你的个人文件夹，以重新授权 Get Oudio 访问默认文件夹并将转换结果写回源文件夹。",
            initialDirectory: SettingsStore.realUserHomeDirectory()
        ) else {
            return
        }
        guard defaultDirectories.allSatisfy({ contains(authorizationRoot, $0) }) else {
            finderDirectoryMessage = "请选择包含桌面、文稿、下载、影片和音乐文件夹的个人文件夹。"
            return
        }

        do {
            try store.storeDirectoryBookmark(for: authorizationRoot)
            finderDirectories = defaultDirectories
            saveFinderDirectories(message: "已重置默认文件/文件夹访问权限；重启 Finder 后生效。")
        } catch {
            finderDirectoryMessage = "无法保存文件/文件夹访问权限：\(error.localizedDescription)"
        }
    }

    private func appendFinderDirectories(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            try urls.forEach { try store.storeDirectoryBookmark(for: $0) }
        } catch {
            finderDirectoryMessage = "无法保存文件/文件夹访问权限：\(error.localizedDescription)"
            return
        }
        let merged = finderDirectories + urls
        finderDirectories = Array(Set(merged.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        saveFinderDirectories()
    }

    private func saveFinderDirectories(message: String? = nil) {
        store.finderDirectoryURLs = finderDirectories
        finderDirectories = store.finderDirectoryURLs
        finderDirectoryMessage = message ?? "已保存 \(finderDirectories.count) 个可访问文件夹；重启 Finder 后生效。"
    }

    private func contains(_ ancestor: URL, _ descendant: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.resolvingSymlinksInPath().path
        let descendantPath = descendant.standardizedFileURL.resolvingSymlinksInPath().path
        return descendantPath == ancestorPath || descendantPath.hasPrefix(ancestorPath + "/")
    }
}
