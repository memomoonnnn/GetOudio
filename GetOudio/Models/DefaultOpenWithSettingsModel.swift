import Combine
import Foundation
import GetOudioCore

@MainActor
final class DefaultOpenWithSettingsModel: ObservableObject {
    @Published var audioDefaultOpenWithRows: [DefaultOpenWithFormatStatus] = []
    @Published var audioDefaultOpenWithStatus = DefaultOpenWithStatus(configuredCount: 0, totalCount: 0)
    @Published var ncmDefaultOpenWithStatus = DefaultOpenWithStatus(configuredCount: 0, totalCount: 0)
    @Published var defaultAudioPlayerURL: URL?
    @Published var defaultAudioPlayerOptions: [DefaultAudioPlayerOption] = []
    @Published var audioDefaultOpenWithMessage = ""
    @Published var ncmDefaultOpenWithMessage = ""
    @Published var audioDefaultOpenWithBusyGroupIDs: Set<String> = []
    @Published var isSettingNCMDefaultOpenWith = false

    private let store: SettingsStore
    private let defaultOpenWithService: DefaultOpenWithService

    init(
        store: SettingsStore = SettingsStore(),
        defaultOpenWithService: DefaultOpenWithService? = nil
    ) {
        self.store = store
        self.defaultOpenWithService = defaultOpenWithService ?? DefaultOpenWithService()
        defaultAudioPlayerURL = store.defaultAudioPlayerURL
        refreshDefaultOpenWithStatus()
    }

    var defaultAudioPlayerName: String {
        defaultAudioPlayerURL?.deletingPathExtension().lastPathComponent ?? "未选择播放器"
    }

    func refreshDefaultOpenWithStatus() {
        defaultAudioPlayerURL = store.defaultAudioPlayerURL
        defaultAudioPlayerOptions = defaultOpenWithService.defaultAudioPlayerOptions()
        audioDefaultOpenWithRows = defaultOpenWithService.audioStatuses()
        audioDefaultOpenWithStatus = defaultOpenWithService.audioSummaryStatus()
        ncmDefaultOpenWithStatus = defaultOpenWithService.ncmStatus()
        audioDefaultOpenWithMessage = Self.defaultOpenWithMessage(
            status: audioDefaultOpenWithStatus,
            configuredText: "列表中的音频格式已全部设为 Get Oudio",
            pendingText: "列表中的音频格式只有一部分设为 Get Oudio"
        )
        ncmDefaultOpenWithMessage = Self.defaultOpenWithMessage(
            status: ncmDefaultOpenWithStatus,
            configuredText: ".ncm 已设为 Get Oudio",
            pendingText: ".ncm 尚未设为 Get Oudio"
        )
    }

    func selectDefaultAudioPlayer(_ option: DefaultAudioPlayerOption) {
        defaultAudioPlayerURL = option.url
        store.defaultAudioPlayerURL = option.url
        audioDefaultOpenWithMessage = "关闭格式开关时会将默认打开方式设为 \(option.displayName)。"
    }

    func setAudioDefaultOpenWith(_ row: DefaultOpenWithFormatStatus, isEnabled: Bool) async {
        guard !audioDefaultOpenWithBusyGroupIDs.contains(row.group.id) else { return }
        if !isEnabled, defaultAudioPlayerURL == nil {
            audioDefaultOpenWithMessage = "请先选择关闭开关时使用的播放器。"
            return
        }

        audioDefaultOpenWithBusyGroupIDs.insert(row.group.id)
        let actionText = isEnabled ? "Get Oudio" : defaultAudioPlayerName
        audioDefaultOpenWithMessage = "正在将 \(row.group.displayName) 默认打开方式设为 \(actionText)..."
        do {
            if isEnabled {
                try await defaultOpenWithService.setGetOudioDefault(for: row.group)
            } else if let playerURL = defaultAudioPlayerURL {
                try await defaultOpenWithService.setFallbackPlayerDefault(for: row.group, playerURL: playerURL)
            }
            refreshDefaultOpenWithStatus()
        } catch {
            refreshDefaultOpenWithStatus()
            audioDefaultOpenWithMessage = "设置失败：\(error.localizedDescription)"
        }
        audioDefaultOpenWithBusyGroupIDs.remove(row.group.id)
    }

    func setNCMDefaultOpenWith() async {
        guard !isSettingNCMDefaultOpenWith else { return }
        isSettingNCMDefaultOpenWith = true
        ncmDefaultOpenWithMessage = "正在设置 .ncm 默认打开方式..."
        do {
            ncmDefaultOpenWithStatus = try await defaultOpenWithService.setNCMDefault()
            ncmDefaultOpenWithMessage = Self.defaultOpenWithMessage(
                status: ncmDefaultOpenWithStatus,
                configuredText: ".ncm 已设为 Get Oudio",
                pendingText: ".ncm 尚未设为 Get Oudio"
            )
        } catch {
            refreshDefaultOpenWithStatus()
            ncmDefaultOpenWithMessage = "设置失败：\(error.localizedDescription)"
        }
        isSettingNCMDefaultOpenWith = false
    }

    private static func defaultOpenWithMessage(
        status: DefaultOpenWithStatus,
        configuredText: String,
        pendingText: String
    ) -> String {
        guard status.totalCount > 0 else {
            return "没有可设置的文件格式。"
        }

        if status.isFullyConfigured {
            return "\(configuredText)（\(status.configuredCount)/\(status.totalCount)）。"
        }

        return "\(pendingText)（\(status.configuredCount)/\(status.totalCount)）。"
    }
}
