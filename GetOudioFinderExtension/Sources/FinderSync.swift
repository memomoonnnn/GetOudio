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
    private var lastAudioSelection: [URL] = []

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
            let presets = enabledPresets()
            lastAudioSelection = audioURLs

            DiagnosticLog.append(
                "finder menu kind=\(menuKind.rawValue) selected=\(selectedURLs.count) audio=\(audioURLs.count) video=\(videoURLs.count) ncm=\(ncmURLs.count) presets=\(presets.count)"
            )

            if audioURLs.isEmpty && videoURLs.isEmpty && ncmURLs.isEmpty {
                let disabledItem = NSMenuItem(title: "没有可处理的音视频或 NCM 文件", action: nil, keyEquivalent: "")
                disabledItem.isEnabled = false
                menu.addItem(disabledItem)
                return menu
            }

            if !audioURLs.isEmpty || [videoURLs.isEmpty, ncmURLs.isEmpty].filter({ !$0 }).count > 1 {
                let parent = NSMenuItem(title: "Get Oudio", action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: "Get Oudio")

                if !audioURLs.isEmpty {
                    for preset in presets {
                        let item = NSMenuItem(title: "转换为 \(preset.finderMenuTitle)", action: actionSelector(for: preset), keyEquivalent: "")
                        item.target = self
                        submenu.addItem(item)
                    }
                }

                if !videoURLs.isEmpty {
                    if !submenu.items.isEmpty {
                        submenu.addItem(.separator())
                    }
                    let item = NSMenuItem(title: "提取视频音频", action: #selector(extractVideoAudio(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = FinderActionContext(urls: videoURLs)
                    submenu.addItem(item)
                }

                if !ncmURLs.isEmpty {
                    if !submenu.items.isEmpty {
                        submenu.addItem(.separator())
                    }
                    let item = NSMenuItem(title: "转换 NCM", action: #selector(convertNCM(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = FinderActionContext(urls: ncmURLs)
                    submenu.addItem(item)
                }

                menu.setSubmenu(submenu, for: parent)
                menu.addItem(parent)
            } else if !videoURLs.isEmpty {
                let item = NSMenuItem(title: "Get Oudio", action: #selector(extractVideoAudio(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = FinderActionContext(urls: videoURLs)
                menu.addItem(item)
            } else if !ncmURLs.isEmpty {
                let item = NSMenuItem(title: "Get Oudio", action: #selector(convertNCM(_:)), keyEquivalent: "")
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

    @objc private func runAAC128(_ sender: NSMenuItem) { runPreset(.aac128) }
    @objc private func runAAC256(_ sender: NSMenuItem) { runPreset(.aac256) }
    @objc private func runAAC320(_ sender: NSMenuItem) { runPreset(.aac320) }
    @objc private func runMP3128(_ sender: NSMenuItem) { runPreset(.mp3128) }
    @objc private func runMP3256(_ sender: NSMenuItem) { runPreset(.mp3256) }
    @objc private func runMP3320(_ sender: NSMenuItem) { runPreset(.mp3320) }
    @objc private func runALAC24Bit48k(_ sender: NSMenuItem) { runPreset(.alac24Bit48k) }
    @objc private func runALAC16Bit44_1k(_ sender: NSMenuItem) { runPreset(.alac16Bit44_1k) }
    @objc private func runALACSource(_ sender: NSMenuItem) { runPreset(.alacSource) }
    @objc private func runFLAC24Bit48k(_ sender: NSMenuItem) { runPreset(.flac24Bit48k) }
    @objc private func runFLAC16Bit44_1k(_ sender: NSMenuItem) { runPreset(.flac16Bit44_1k) }
    @objc private func runFLACSource(_ sender: NSMenuItem) { runPreset(.flacSource) }
    @objc private func runPCM24Bit48k(_ sender: NSMenuItem) { runPreset(.pcm24Bit48k) }
    @objc private func runPCM16Bit44_1k(_ sender: NSMenuItem) { runPreset(.pcm16Bit44_1k) }
    @objc private func runPCMSource(_ sender: NSMenuItem) { runPreset(.pcmSource) }

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
            DiagnosticLog.append("finder enqueue skipped empty jobs")
            return
        }

        do {
            DiagnosticLog.append("finder enqueue start count=\(jobs.count) operations=\(jobs.map { operationDescription($0.operation) }.joined(separator: ","))")
            let queue = try JobQueue()
            try queue.enqueue(jobs)
            openContainingApp()
        } catch {
            DiagnosticLog.append("finder enqueue failed \(error.localizedDescription)")
            NSLog("Get Oudio Finder extension failed to enqueue jobs: \(error.localizedDescription)")
        }
    }

    @objc private func openContainingApp() {
        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }

        // Signal launch source before opening app
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            sharedDefaults.set(LaunchSource.finderSync.rawValue, forKey: AppConstants.extensionLaunchSourceKey)
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: AppConstants.extensionLaunchTimestampKey)
            sharedDefaults.synchronize()
        }

        DiagnosticLog.append("finder open url \(url.absoluteString)")
        NSWorkspace.shared.open(url)
    }

    private func operationDescription(_ operation: JobOperation) -> String {
        switch operation {
        case .transcode(let preset):
            return "transcode(\(preset.rawValue))"
        case .extractAudio:
            return "extractAudio"
        case .convertNCM:
            return "convertNCM"
        case .appleMusicDownload(let format):
            return "appleMusicDownload(\(format?.rawValue ?? "default"))"
        }
    }

    private func reloadObservedDirectories() {
        FIFinderSyncController.default().directoryURLs = Set(settingsStore.finderDirectoryURLs)
    }

    private func enabledPresets() -> [ConversionPreset] {
        let presets = ConversionPreset.allCases.filter { settingsStore.enabledPresets.contains($0) }
        return presets.isEmpty ? ConversionPreset.allCases : presets
    }

    private func runPreset(_ preset: ConversionPreset) {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let urls = selectedURLs.isEmpty ? lastAudioSelection : selectedURLs
        DiagnosticLog.append("finder audio action preset=\(preset.rawValue) selected=\(urls.count)")

        let jobs = urls
            .filter { FileCategory.classify($0) == .audio }
            .map { makeJob(fileURL: $0, category: .audio, operation: .transcode(preset)) }

        enqueue(jobs)
    }

    private func actionSelector(for preset: ConversionPreset) -> Selector {
        switch preset {
        case .aac128:
            return #selector(runAAC128(_:))
        case .aac256:
            return #selector(runAAC256(_:))
        case .aac320:
            return #selector(runAAC320(_:))
        case .mp3128:
            return #selector(runMP3128(_:))
        case .mp3256:
            return #selector(runMP3256(_:))
        case .mp3320:
            return #selector(runMP3320(_:))
        case .alac24Bit48k:
            return #selector(runALAC24Bit48k(_:))
        case .alac16Bit44_1k:
            return #selector(runALAC16Bit44_1k(_:))
        case .alacSource:
            return #selector(runALACSource(_:))
        case .flac24Bit48k:
            return #selector(runFLAC24Bit48k(_:))
        case .flac16Bit44_1k:
            return #selector(runFLAC16Bit44_1k(_:))
        case .flacSource:
            return #selector(runFLACSource(_:))
        case .pcm24Bit48k:
            return #selector(runPCM24Bit48k(_:))
        case .pcm16Bit44_1k:
            return #selector(runPCM16Bit44_1k(_:))
        case .pcmSource:
            return #selector(runPCMSource(_:))
        }
    }
}
