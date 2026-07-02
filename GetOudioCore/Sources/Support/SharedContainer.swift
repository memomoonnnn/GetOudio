import Foundation

public enum SharedContainer {
    public static func defaults(suiteName: String = AppConstants.appGroupIdentifier) -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static func directory() throws -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            return containerURL
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Get Oudio", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
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
