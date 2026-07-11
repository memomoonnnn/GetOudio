import Foundation

public struct SharedContainer {
    public static let diagnosticRootEnvironmentKey = "GET_OUDIO_DIAGNOSTIC_SHARED_CONTAINER_ROOT"
    public static let diagnosticDefaultsSuiteName = "com.shengjiacheng.GetOudio.Diagnostic"

    public enum AccessMode: Equatable {
        case appGroup
        case diagnostic
    }

    public enum Resource {
        case jobQueue
        case shareEvents
        case pendingAppleMusicDownloads
        case notificationEvents
        case conversionLog
        case appleMusicRuntime
        case appleMusicRuntimeIPC
    }

    public enum AccessError: LocalizedError {
        case appGroupDirectoryUnavailable(String)
        case appGroupDefaultsUnavailable(String)
        case diagnosticDefaultsUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .appGroupDirectoryUnavailable(let groupIdentifier):
                return "App Group directory unavailable for \(groupIdentifier)"
            case .appGroupDefaultsUnavailable(let suiteName):
                return "App Group defaults unavailable for \(suiteName)"
            case .diagnosticDefaultsUnavailable(let suiteName):
                return "Diagnostic defaults unavailable for \(suiteName)"
            }
        }
    }

    public let directoryURL: URL
    public let defaults: UserDefaults
    public let accessMode: AccessMode

    private init(directoryURL: URL, defaults: UserDefaults, accessMode: AccessMode) {
        self.directoryURL = directoryURL
        self.defaults = defaults
        self.accessMode = accessMode
    }

    public static func production(
        groupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) throws -> SharedContainer {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw AccessError.appGroupDirectoryUnavailable(groupIdentifier)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            throw AccessError.appGroupDefaultsUnavailable(groupIdentifier)
        }
        return SharedContainer(directoryURL: directoryURL, defaults: defaults, accessMode: .appGroup)
    }

    public static func diagnostic(
        rootURL: URL,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) throws -> SharedContainer {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return SharedContainer(directoryURL: rootURL, defaults: defaults, accessMode: .diagnostic)
    }

    public static func forCurrentProcess(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> SharedContainer {
#if DEBUG
        if let rootPath = environment[diagnosticRootEnvironmentKey], !rootPath.isEmpty {
            guard let defaults = UserDefaults(suiteName: diagnosticDefaultsSuiteName) else {
                throw AccessError.diagnosticDefaultsUnavailable(diagnosticDefaultsSuiteName)
            }
            return try diagnostic(
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
                defaults: defaults,
                fileManager: fileManager
            )
        }
#endif
        return try production(fileManager: fileManager)
    }

    public func url(for resource: Resource) -> URL {
        switch resource {
        case .jobQueue:
            return directoryURL.appendingPathComponent("queued-jobs.json")
        case .shareEvents:
            return directoryURL.appendingPathComponent("share-events.json")
        case .pendingAppleMusicDownloads:
            return directoryURL.appendingPathComponent("pending-apple-music-downloads.json")
        case .notificationEvents:
            return directoryURL.appendingPathComponent("notification-events", isDirectory: true)
        case .conversionLog:
            return directoryURL.appendingPathComponent("conversion-log.txt")
        case .appleMusicRuntime:
            return directoryURL.appendingPathComponent("AppleMusicRuntime", isDirectory: true)
        case .appleMusicRuntimeIPC:
            return directoryURL.appendingPathComponent("AppleMusicRuntimeIPC", isDirectory: true)
        }
    }
}
