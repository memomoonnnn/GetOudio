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
}

