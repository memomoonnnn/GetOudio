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
    @Published var usesCustomCacheDirectory: Bool
    @Published var cacheDirectoryPath = ""
    @Published var microphoneAuthorized = false
    @Published var trimsSilence: Bool
    @Published var normalizesPeak: Bool
    @Published var silenceThresholdDBFS: Double
    @Published var silencePaddingMilliseconds: Int
    @Published var message = ""

    private let container: SharedContainer
    private let store: SettingsStore

    init(container: SharedContainer, store: SettingsStore) {
        self.container = container
        self.store = store
        selectedBridgeUID = store.recordingBridgeDeviceUID
        cacheLimitBytes = store.recordingCacheLimitBytes
        usesCustomCacheDirectory = store.recordingUsesCustomCacheDirectory
        let postProcessing = store.recordingPostProcessingOptions
        trimsSilence = postProcessing.trimsSilence
        normalizesPeak = postProcessing.normalizesPeak
        silenceThresholdDBFS = postProcessing.silenceThresholdDBFS
        silencePaddingMilliseconds = postProcessing.silencePaddingMilliseconds
        refresh()
    }

    func refresh() {
        bridgeDevices = RecordingDeviceService.devices().filter(\.isSupportedProToolsAudioBridge)
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        updateCacheDirectoryPath()
        updateCacheSize()
    }

    func selectBridge(_ uid: String?) {
        selectedBridgeUID = uid
        store.recordingBridgeDeviceUID = uid
    }

    func setCacheLimit(_ bytes: Int64) {
        cacheLimitBytes = bytes
        store.recordingCacheLimitBytes = bytes
        cacheAccess()?.store.enforceLimit(bytes)
        updateCacheSize()
    }

    func setUsesCustomCacheDirectory(_ enabled: Bool) {
        guard enabled else {
            usesCustomCacheDirectory = false
            store.recordingUsesCustomCacheDirectory = false
            updateCacheDirectoryPath()
            updateCacheSize()
            return
        }
        guard store.recordingCustomCacheBookmarkData != nil else {
            chooseCacheDirectory()
            return
        }
        usesCustomCacheDirectory = true
        store.recordingUsesCustomCacheDirectory = true
        updateCacheDirectoryPath()
        updateCacheSize()
    }

    func setTrimsSilence(_ enabled: Bool) {
        trimsSilence = enabled
        savePostProcessingOptions()
    }

    func setNormalizesPeak(_ enabled: Bool) {
        normalizesPeak = enabled
        savePostProcessingOptions()
    }

    func setSilenceThresholdDBFS(_ value: Double) {
        silenceThresholdDBFS = value
        savePostProcessingOptions()
    }

    func setSilencePaddingMilliseconds(_ value: Int) {
        silencePaddingMilliseconds = value
        savePostProcessingOptions()
    }

    func chooseCacheDirectory() {
        guard let url = DirectoryChooser.chooseDirectory(prompt: "选择缓存位置") else { return }
        do {
            store.recordingCustomCacheBookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            usesCustomCacheDirectory = true
            store.recordingUsesCustomCacheDirectory = true
            updateCacheDirectoryPath()
            updateCacheSize()
            message = "录音缓存将保存在 \(url.path)"
        } catch {
            message = error.localizedDescription
        }
    }

    func restoreDefaultCacheDirectory() {
        usesCustomCacheDirectory = false
        store.recordingUsesCustomCacheDirectory = false
        store.recordingCustomCacheBookmarkData = nil
        updateCacheDirectoryPath()
        updateCacheSize()
        message = "已恢复默认缓存目录；原指定目录中的录音未删除。"
    }

    func revealCacheDirectory() {
        guard let access = cacheAccess(reportFailure: true) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([access.store.directoryURL])
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneAuthorized = granted
            message = granted ? "音频输入权限已启用。" : "请在系统设置的隐私与安全性中允许 Get Oudio 使用麦克风。"
        }
    }

    func clearCache() {
        let count = cacheAccess(reportFailure: true)?.store.clearCompletedFiles().count ?? 0
        updateCacheSize()
        message = count == 0 ? "缓存中没有可清理的录音。" : "已清理 \(count) 个录音文件。"
    }

    private func updateCacheSize() {
        cacheSizeText = ByteCountFormatter.string(
            fromByteCount: cacheAccess()?.store.completedSize() ?? 0,
            countStyle: .file
        )
    }

    private func updateCacheDirectoryPath() {
        guard let access = cacheAccess() else {
            cacheDirectoryPath = "默认缓存目录不可用"
            return
        }
        cacheDirectoryPath = access.store.directoryURL.path
    }

    private func savePostProcessingOptions() {
        let options = RecordingPostProcessingOptions(
            trimsSilence: trimsSilence,
            normalizesPeak: normalizesPeak,
            silenceThresholdDBFS: silenceThresholdDBFS,
            silencePaddingMilliseconds: silencePaddingMilliseconds
        )
        store.recordingPostProcessingOptions = options
        silenceThresholdDBFS = options.silenceThresholdDBFS
        silencePaddingMilliseconds = options.silencePaddingMilliseconds
    }

    private func cacheAccess(reportFailure: Bool = false) -> RecordingCacheDirectoryAccess? {
        do {
            let access = try RecordingCacheDirectoryAccess(container: container, settings: store)
            if reportFailure, let fallbackMessage = access.fallbackMessage {
                message = fallbackMessage
            }
            return access
        } catch {
            if reportFailure {
                message = "无法访问默认缓存目录：\(error.localizedDescription)"
            }
            return nil
        }
    }
}
