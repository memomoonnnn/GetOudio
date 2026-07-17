import AppKit
import Foundation

enum DirectoryChooser {
    static func chooseDirectory(
        prompt: String,
        message: String? = nil,
        initialDirectory: URL? = nil
    ) -> URL? {
        chooseDirectories(
            prompt: prompt,
            message: message,
            initialDirectory: initialDirectory,
            allowsMultipleSelection: false
        ).first
    }

    static func chooseDirectories(
        prompt: String,
        message: String? = nil,
        initialDirectory: URL? = nil,
        allowsMultipleSelection: Bool
    ) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.prompt = prompt
        panel.message = message ?? ""
        panel.directoryURL = initialDirectory

        return panel.runModal() == .OK ? panel.urls : []
    }
}
