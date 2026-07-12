import AVFoundation
import AppKit
import Combine
import Foundation
import GetOudioCore

@MainActor
final class RecordingSettingsModel: ObservableObject {
    struct CacheLimitOption: Identifiable {
        let bytes: Int64
        let title: String
        var id: Int64 { bytes }
    }

    static let cacheLimitOptions = [
        CacheLimitOption(bytes: 512 * 1_024 * 1_024, title: "512 MB"),
        CacheLimitOption(bytes: 1_024 * 1_024 * 1_024, title: "1 GB"),
        CacheLimitOption(bytes: 2 * 1_024 * 1_024 * 1_024, title: "2 GB"),
        CacheLimitOption(bytes: 5 * 1_024 * 1_024 * 1_024, title: "5 GB"),
        CacheLimitOption(bytes: 10 * 1_024 * 1_024 * 1_024, title: "10 GB"),
        CacheLimitOption(bytes: 20 * 1_024 * 1_024 * 1_024, title: "20 GB")
    ]

    @Published var bridgeDevices: [AudioDeviceDescriptor] = []
    @Published var selectedBridgeUID: String?
    @Published var cacheLimitBytes: Int64
    @Published var cacheSizeText = "0 MB"
    @Published var usesCustomOutputDirectory: Bool
    @Published var customOutputDirectoryName = "未选择"
    @Published var microphoneAuthorized = false
    @Published var message = ""

    private let store: SettingsStore
    private let cacheStore: RecordingCacheStore?

    init(container: SharedContainer, store: SettingsStore) {
        self.store = store
        cacheStore = try? RecordingCacheStore(container: container)
        selectedBridgeUID = store.recordingBridgeDeviceUID
        cacheLimitBytes = store.recordingCacheLimitBytes
        usesCustomOutputDirectory = store.recordingUsesCustomOutputDirectory
        refresh()
    }

    func refresh() {
        bridgeDevices = RecordingDeviceService.devices().filter(\.isSupportedProToolsAudioBridge)
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        updateCustomDirectoryName()
        updateCacheSize()
    }

    func selectBridge(_ uid: String?) {
        selectedBridgeUID = uid
        store.recordingBridgeDeviceUID = uid
    }

    func setCacheLimit(_ bytes: Int64) {
        cacheLimitBytes = bytes
        store.recordingCacheLimitBytes = bytes
        cacheStore?.enforceLimit(bytes)
        updateCacheSize()
    }

    func setUsesCustomOutputDirectory(_ enabled: Bool) {
        usesCustomOutputDirectory = enabled
        store.recordingUsesCustomOutputDirectory = enabled
    }

    func chooseOutputDirectory() {
        guard let url = DirectoryChooser.chooseDirectory(prompt: "选择") else { return }
        do {
            store.recordingCustomOutputBookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            setUsesCustomOutputDirectory(true)
            customOutputDirectoryName = url.lastPathComponent
            message = "录音完成后将移动到 \(url.path)"
        } catch {
            message = error.localizedDescription
        }
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneAuthorized = granted
            message = granted ? "音频输入权限已启用。" : "请在系统设置的隐私与安全性中允许 Get Oudio 使用麦克风。"
        }
    }

    func clearCache() {
        let count = cacheStore?.clearCompletedFiles().count ?? 0
        updateCacheSize()
        message = count == 0 ? "缓存中没有可清理的录音。" : "已清理 \(count) 个录音文件。"
    }

    private func updateCacheSize() {
        cacheSizeText = ByteCountFormatter.string(
            fromByteCount: cacheStore?.completedSize() ?? 0,
            countStyle: .file
        )
    }

    private func updateCustomDirectoryName() {
        guard let data = store.recordingCustomOutputBookmarkData else {
            customOutputDirectoryName = "未选择"
            return
        }
        var stale = false
        customOutputDirectoryName = (try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).lastPathComponent) ?? "目录不可用"
    }
}

