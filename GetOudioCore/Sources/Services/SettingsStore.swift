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
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = SharedContainer.defaults()) {
        self.defaults = defaults
        seedDefaultsIfNeeded()
    }

    public var enabledPresets: Set<ConversionPreset> {
        get {
            let ids = defaults.stringArray(forKey: Keys.enabledPresetIDs) ?? ConversionPreset.defaultEnabled.map(\.rawValue)
            return Set(ids.compactMap(ConversionPreset.init(rawValue:)))
        }
        set {
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Keys.enabledPresetIDs)
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
