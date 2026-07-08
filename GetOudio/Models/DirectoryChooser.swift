import AppKit
import Foundation

enum DirectoryChooser {
    static func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        return panel.runModal() == .OK ? panel.url : nil
    }
}
