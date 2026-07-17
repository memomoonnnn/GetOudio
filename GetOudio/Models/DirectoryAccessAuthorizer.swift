import AppKit
import Foundation
import GetOudioCore

enum DirectoryAccessAuthorizer {
    static func authorizeSourceDirectories(_ directories: [URL], store: SettingsStore) -> Bool {
        let uniqueDirectories = Array(Set(directories.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }

        for directoryURL in uniqueDirectories where store.directoryBookmarkData(for: directoryURL) == nil {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = directoryURL
            panel.prompt = "授权"
            panel.message = "请选择源文件所在文件夹或其上级文件夹，以授权 Get Oudio 将转换结果写回源文件夹。"

            guard panel.runModal() == .OK, let selectedURL = panel.url else {
                return false
            }
            guard contains(selectedURL, directoryURL) else {
                NSAlert(error: DirectoryAccessError.directoryUnavailable(directoryURL.path)).runModal()
                return false
            }

            do {
                try store.storeDirectoryBookmark(for: selectedURL)
            } catch {
                NSAlert(error: error).runModal()
                return false
            }
        }

        return true
    }

    private static func contains(_ ancestor: URL, _ descendant: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.resolvingSymlinksInPath().path
        let descendantPath = descendant.standardizedFileURL.resolvingSymlinksInPath().path
        return descendantPath == ancestorPath || descendantPath.hasPrefix(ancestorPath + "/")
    }
}
