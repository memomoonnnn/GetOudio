import AppKit
import GetOudioCore

final class OpenWithPresetMenuController: NSObject {
    private var onSelect: ((ConversionPreset) -> Void)?
    private var onCancel: (() -> Void)?
    private var didSelect = false

    func present(
        fileURLs: [URL],
        presets: [ConversionPreset],
        at point: NSPoint,
        onSelect: @escaping (ConversionPreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        didSelect = false

        let menu = NSMenu(title: "Get Oudio")
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "\(fileURLs.count) 个音频文件", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for preset in presets {
            let item = NSMenuItem(title: "to \(preset.finderMenuTitle)", action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            menu.addItem(item)
        }

        DiagnosticLog.append("open with menu present count=\(fileURLs.count) presets=\(presets.count)")
        menu.popUp(positioning: nil, at: point, in: nil)

        let cancelHandler = self.onCancel
        let shouldCancel = !didSelect
        clear()
        if shouldCancel {
            DiagnosticLog.append("open with menu cancelled")
            cancelHandler?()
        }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = ConversionPreset(rawValue: rawValue) else {
            DiagnosticLog.append("open with menu selection invalid")
            return
        }

        didSelect = true
        DiagnosticLog.append("open with menu selected preset=\(preset.rawValue)")
        onSelect?(preset)
    }

    private func clear() {
        onSelect = nil
        onCancel = nil
        didSelect = false
    }
}
