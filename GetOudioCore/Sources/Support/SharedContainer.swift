import Foundation

public enum SharedContainer {
    public enum AccessMode: Equatable {
        case appGroup
        case diagnosticFallback(String)
    }

    public struct DefaultsResolution {
        public let defaults: UserDefaults
        public let accessMode: AccessMode
    }

    public struct DirectoryResolution {
        public let url: URL
        public let accessMode: AccessMode
    }

    public enum AccessError: LocalizedError {
        case appGroupDefaultsUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .appGroupDefaultsUnavailable(let suiteName):
                return "App Group defaults unavailable for \(suiteName)"
            }
        }
    }

    public static func defaults(suiteName: String = AppConstants.appGroupIdentifier) -> UserDefaults {
        resolvedDefaults(suiteName: suiteName).defaults
    }

    public static func appGroupDefaults(suiteName: String = AppConstants.appGroupIdentifier) -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public static func requiredDefaults(suiteName: String = AppConstants.appGroupIdentifier) throws -> UserDefaults {
        guard let defaults = appGroupDefaults(suiteName: suiteName) else {
            throw AccessError.appGroupDefaultsUnavailable(suiteName)
        }
        return defaults
    }

    public static func resolvedDefaults(suiteName: String = AppConstants.appGroupIdentifier) -> DefaultsResolution {
        if let defaults = appGroupDefaults(suiteName: suiteName) {
            return DefaultsResolution(defaults: defaults, accessMode: .appGroup)
        }

        DiagnosticLog.append("shared defaults fallback suite=\(suiteName)")
        return DefaultsResolution(
            defaults: .standard,
            accessMode: .diagnosticFallback("standard UserDefaults")
        )
    }

    public static func directory() throws -> URL {
        try resolvedDirectory().url
    }

    public static func resolvedDirectory(
        groupIdentifier: String = AppConstants.appGroupIdentifier,
        fallbackBaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DirectoryResolution {
        try resolvedDirectory(
            containerURL: fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier),
            groupIdentifier: groupIdentifier,
            fallbackBaseURL: fallbackBaseURL,
            fileManager: fileManager
        )
    }

    static func resolvedDirectory(
        containerURL: URL?,
        groupIdentifier: String = AppConstants.appGroupIdentifier,
        fallbackBaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DirectoryResolution {
        if let containerURL {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            return DirectoryResolution(url: containerURL, accessMode: .appGroup)
        }

        let fallback = (fallbackBaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true))
            .appendingPathComponent("Get Oudio", isDirectory: true)
        try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        DiagnosticLog.append("shared container fallback group=\(groupIdentifier) path=\(fallback.path)")
        return DirectoryResolution(
            url: fallback,
            accessMode: .diagnosticFallback("Application Support")
        )
    }

    public static func requiredDirectory(
        groupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            return containerURL
        }

        throw CocoaError(.fileNoSuchFile)
    }

    public static func queueFileURL() throws -> URL {
        try directory().appendingPathComponent("queued-jobs.json")
    }

    public static func shareEventsFileURL() throws -> URL {
        try directory().appendingPathComponent("share-events.json")
    }

    public static func pendingAppleMusicDownloadsFileURL() throws -> URL {
        try directory().appendingPathComponent("pending-apple-music-downloads.json")
    }

    public static func notificationEventsDirectoryURL() throws -> URL {
        try directory().appendingPathComponent("notification-events", isDirectory: true)
    }

    public static func conversionLogFileURL() throws -> URL {
        try directory().appendingPathComponent("conversion-log.txt")
    }
}
