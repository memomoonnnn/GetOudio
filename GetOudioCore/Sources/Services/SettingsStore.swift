import Darwin
import Foundation

public final class SettingsStore {
    public enum Keys {
        public static let enabledPresetIDs = "enabledPresetIDs"
        public static let finderDirectoryPaths = "finderDirectoryPaths"
        public static let ncmOutputMode = "ncmOutputMode"
        public static let ncmCustomOutputPath = "ncmCustomOutputPath"
        public static let appleMusicOutputPath = "appleMusicOutputPath"
        public static let appleMusicDownloadMode = "appleMusicDownloadMode"
        public static let isAppleMusicDownloadEnabled = "isAppleMusicDownloadEnabled"
        public static let appleMusicUseSystemProxy = "appleMusicUseSystemProxy"
        public static let defaultAudioPlayerPath = "defaultAudioPlayerPath"
        public static let recordingBridgeDeviceUID = "recordingBridgeDeviceUID"
        public static let recordingCacheLimitBytes = "recordingCacheLimitBytes"
        public static let recordingCustomCacheBookmark = "recordingCustomCacheBookmark"
        public static let recordingUsesCustomCacheDirectory = "recordingUsesCustomCacheDirectory"
        public static let recordingTrimsSilence = "recordingTrimsSilence"
        public static let recordingNormalizesPeak = "recordingNormalizesPeak"
        public static let recordingSilenceThresholdDBFS = "recordingSilenceThresholdDBFS"
        public static let recordingSilencePaddingMilliseconds = "recordingSilencePaddingMilliseconds"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        seedDefaultsIfNeeded()
    }

    public convenience init(container: SharedContainer) {
        self.init(defaults: container.defaults)
    }

    public var enabledPresets: Set<ConversionPreset> {
        get {
            let ids = defaults.stringArray(forKey: Keys.enabledPresetIDs) ?? ConversionPreset.defaultEnabled.map(\.rawValue)
            let presets = Set(ids.compactMap(ConversionPreset.init(rawValue:)))
            return presets.isEmpty ? ConversionPreset.defaultEnabled : presets
        }
        set {
            let presets = newValue.isEmpty ? ConversionPreset.defaultEnabled : newValue
            defaults.set(presets.map(\.rawValue).sorted(), forKey: Keys.enabledPresetIDs)
        }
    }

    public var finderDirectoryURLs: [URL] {
        get {
            let paths = defaults.stringArray(forKey: Keys.finderDirectoryPaths) ?? Self.defaultFinderDirectories().map(\.path)
            return paths.map {
                let url = URL(fileURLWithPath: $0, isDirectory: true)
                return URL(fileURLWithPath: Self.normalizedDirectoryPath(for: url), isDirectory: true)
            }
        }
        set {
            let uniquePaths = Array(Set(newValue.map(Self.normalizedDirectoryPath(for:)))).sorted()
            defaults.set(uniquePaths, forKey: Keys.finderDirectoryPaths)
        }
    }

    public var ncmOutputMode: String {
        get { defaults.string(forKey: Keys.ncmOutputMode) ?? "sourceDirectory" }
        set { defaults.set(newValue, forKey: Keys.ncmOutputMode) }
    }

    public var ncmCustomOutputURL: URL? {
        get {
            defaults.string(forKey: Keys.ncmCustomOutputPath).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            defaults.set(newValue?.path, forKey: Keys.ncmCustomOutputPath)
        }
    }

    public var appleMusicOutputURL: URL {
        get {
            if let path = defaults.string(forKey: Keys.appleMusicOutputPath), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }

            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Get Oudio", isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: Keys.appleMusicOutputPath)
        }
    }

    public var appleMusicDownloadMode: String {
        get { defaults.string(forKey: Keys.appleMusicDownloadMode) ?? "askEveryTime" }
        set { defaults.set(newValue, forKey: Keys.appleMusicDownloadMode) }
    }

    public var appleMusicDownloadFormat: AppleMusicDownloadFormat {
        get { AppleMusicDownloadFormat(rawValue: appleMusicDownloadMode) ?? .askEveryTime }
        set { appleMusicDownloadMode = newValue.rawValue }
    }

    public var isAppleMusicDownloadEnabled: Bool {
        get { defaults.bool(forKey: Keys.isAppleMusicDownloadEnabled) }
        set { defaults.set(newValue, forKey: Keys.isAppleMusicDownloadEnabled) }
    }

    public var appleMusicUseSystemProxy: Bool {
        get { defaults.bool(forKey: Keys.appleMusicUseSystemProxy) }
        set { defaults.set(newValue, forKey: Keys.appleMusicUseSystemProxy) }
    }

    public var defaultAudioPlayerURL: URL? {
        get {
            defaults.string(forKey: Keys.defaultAudioPlayerPath).map { URL(fileURLWithPath: $0) }
        }
        set {
            defaults.set(newValue?.path, forKey: Keys.defaultAudioPlayerPath)
        }
    }

    public var recordingBridgeDeviceUID: String? {
        get { defaults.string(forKey: Keys.recordingBridgeDeviceUID) }
        set { defaults.set(newValue, forKey: Keys.recordingBridgeDeviceUID) }
    }

    public var recordingCacheLimitBytes: Int64 {
        get {
            let value = defaults.object(forKey: Keys.recordingCacheLimitBytes) as? NSNumber
            return value?.int64Value ?? 1_073_741_824
        }
        set { defaults.set(NSNumber(value: newValue), forKey: Keys.recordingCacheLimitBytes) }
    }

    public var recordingCustomCacheBookmarkData: Data? {
        get { defaults.data(forKey: Keys.recordingCustomCacheBookmark) }
        set { defaults.set(newValue, forKey: Keys.recordingCustomCacheBookmark) }
    }

    public var recordingUsesCustomCacheDirectory: Bool {
        get { defaults.bool(forKey: Keys.recordingUsesCustomCacheDirectory) }
        set { defaults.set(newValue, forKey: Keys.recordingUsesCustomCacheDirectory) }
    }

    public var recordingPostProcessingOptions: RecordingPostProcessingOptions {
        get {
            RecordingPostProcessingOptions(
                trimsSilence: defaults.bool(forKey: Keys.recordingTrimsSilence),
                normalizesPeak: defaults.bool(forKey: Keys.recordingNormalizesPeak),
                silenceThresholdDBFS: defaults.object(forKey: Keys.recordingSilenceThresholdDBFS) as? Double ?? RecordingPostProcessingOptions.defaultSilenceThresholdDBFS,
                silencePaddingMilliseconds: defaults.object(forKey: Keys.recordingSilencePaddingMilliseconds) as? Int ?? RecordingPostProcessingOptions.defaultSilencePaddingMilliseconds
            )
        }
        set {
            defaults.set(newValue.trimsSilence, forKey: Keys.recordingTrimsSilence)
            defaults.set(newValue.normalizesPeak, forKey: Keys.recordingNormalizesPeak)
            defaults.set(newValue.silenceThresholdDBFS, forKey: Keys.recordingSilenceThresholdDBFS)
            defaults.set(newValue.silencePaddingMilliseconds, forKey: Keys.recordingSilencePaddingMilliseconds)
        }
    }

    public static func defaultFinderDirectories() -> [URL] {
        let home = realUserHomeDirectory()
        let candidates = ["Desktop", "Downloads", "Music", "Movies", "Documents"]
        return candidates
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func realUserHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithFileSystemRepresentation: home, isDirectory: true, relativeTo: nil)
        }

        return FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
    }

    private func seedDefaultsIfNeeded() {
        if defaults.object(forKey: Keys.enabledPresetIDs) == nil {
            defaults.set(ConversionPreset.defaultEnabled.map(\.rawValue).sorted(), forKey: Keys.enabledPresetIDs)
        }

        if defaults.object(forKey: Keys.finderDirectoryPaths) == nil {
            defaults.set(Self.defaultFinderDirectories().map(\.path), forKey: Keys.finderDirectoryPaths)
        } else if let paths = defaults.stringArray(forKey: Keys.finderDirectoryPaths) {
            let normalizedPaths = paths
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                .map(Self.normalizedDirectoryPath(for:))
                .sorted()
            if normalizedPaths != paths.sorted() {
                defaults.set(normalizedPaths, forKey: Keys.finderDirectoryPaths)
            }
        }
    }

    private static func normalizedDirectoryPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
