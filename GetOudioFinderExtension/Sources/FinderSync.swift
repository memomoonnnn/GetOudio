import Cocoa
import FinderSync
import GetOudioCore

private final class FinderActionContext: NSObject {
    let urls: [URL]
    let presetID: String?

    init(urls: [URL], presetID: String? = nil) {
        self.urls = urls
        self.presetID = presetID
    }
}

@objc final class FinderSync: FIFinderSync {
    private let settingsStore = SettingsStore()

    override init() {
        super.init()
        reloadObservedDirectories()
    }

    override var toolbarItemName: String {
        "Get Oudio"
    }

    override var toolbarItemToolTip: String {
        "Get Oudio"
    }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "waveform", accessibilityDescription: "Get Oudio") ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        reloadObservedDirectories()

        let menu = NSMenu(title: "Get Oudio")

        switch menuKind {
        case .contextualMenuForItems, .toolbarItemMenu:
            let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
            let audioURLs = selectedURLs.filter { FileCategory.classify($0) == .audio }
            let videoURLs = selectedURLs.filter { FileCategory.classify($0) == .video }
            let ncmURLs = selectedURLs.filter { FileCategory.classify($0) == .ncm }

            if audioURLs.isEmpty && videoURLs.isEmpty && ncmURLs.isEmpty {
                let disabledItem = NSMenuItem(title: "没有可处理的音视频或 NCM 文件", action: nil, keyEquivalent: "")
                disabledItem.isEnabled = false
                menu.addItem(disabledItem)
                return menu
            }

            if !audioURLs.isEmpty {
                let transcodeMenu = NSMenu(title: "Get Oudio")
                for preset in enabledPresets() {
                    let item = NSMenuItem(title: preset.finderMenuTitle, action: #selector(runPreset(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = FinderActionContext(urls: audioURLs, presetID: preset.rawValue)
                    transcodeMenu.addItem(item)
                }
                let parent = NSMenuItem(title: "Get Oudio", action: nil, keyEquivalent: "")
                menu.setSubmenu(transcodeMenu, for: parent)
                menu.addItem(parent)
            }

            if !videoURLs.isEmpty {
                let item = NSMenuItem(title: "提取视频音频", action: #selector(extractVideoAudio(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = FinderActionContext(urls: videoURLs)
                menu.addItem(item)
            }

            if !ncmURLs.isEmpty {
                let item = NSMenuItem(title: "转换 NCM", action: #selector(convertNCM(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = FinderActionContext(urls: ncmURLs)
                menu.addItem(item)
            }

        default:
            let item = NSMenuItem(title: "打开 Get Oudio", action: #selector(openContainingApp), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        return menu
    }

    @objc private func runPreset(_ sender: NSMenuItem) {
        guard
            let context = sender.representedObject as? FinderActionContext,
            let presetID = context.presetID,
            let preset = ConversionPreset(rawValue: presetID)
        else {
            return
        }

        let jobs = context.urls
            .filter { FileCategory.classify($0) == .audio }
            .map { makeJob(fileURL: $0, category: .audio, operation: .transcode(preset)) }

        enqueue(jobs)
    }

    @objc private func extractVideoAudio(_ sender: NSMenuItem) {
        let urls = (sender.representedObject as? FinderActionContext)?.urls ?? FIFinderSyncController.default().selectedItemURLs() ?? []
        let jobs = urls
            .filter { FileCategory.classify($0) == .video }
            .map { makeJob(fileURL: $0, category: .video, operation: .extractAudio) }

        enqueue(jobs)
    }

    @objc private func convertNCM(_ sender: NSMenuItem) {
        let urls = (sender.representedObject as? FinderActionContext)?.urls ?? FIFinderSyncController.default().selectedItemURLs() ?? []
        let jobs = urls
            .filter { FileCategory.classify($0) == .ncm }
            .map { makeJob(fileURL: $0, category: .ncm, operation: .convertNCM) }

        enqueue(jobs)
    }

    private func makeJob(fileURL: URL, category: FileCategory, operation: JobOperation) -> JobRequest {
        JobRequest(
            fileURL: fileURL,
            fileBookmarkData: JobRequest.securityScopedBookmarkData(for: fileURL),
            directoryBookmarkData: JobRequest.securityScopedBookmarkData(for: fileURL.deletingLastPathComponent()),
            category: category,
            operation: operation,
            source: .finderSync
        )
    }

    private func enqueue(_ jobs: [JobRequest]) {
        guard !jobs.isEmpty else {
            return
        }

        do {
            let queue = try JobQueue()
            try queue.enqueue(jobs)
            openContainingApp()
        } catch {
            NSLog("Get Oudio Finder extension failed to enqueue jobs: \(error.localizedDescription)")
        }
    }

    @objc private func openContainingApp() {
        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func reloadObservedDirectories() {
        FIFinderSyncController.default().directoryURLs = Set(settingsStore.finderDirectoryURLs)
    }

    private func enabledPresets() -> [ConversionPreset] {
        ConversionPreset.allCases.filter { settingsStore.enabledPresets.contains($0) }
    }
}
