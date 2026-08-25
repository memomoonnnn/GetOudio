import Darwin
import Foundation

/// Control-plane data shared by the sandboxed App and its launchd Agent.
/// Extensions use XPC and never receive this filesystem capability.
public struct AgentDataStore {
    public enum Resource {
        case jobQueue
        case shareEvents
        case pendingAppleMusicDownloads
        case notificationEvents
        case conversionLog
        case appleMusicRuntime
        case appleMusicRuntimeIPC
        case recordingControl
        case recordingCache
    }

    public let directoryURL: URL
    public let defaults: UserDefaults

    /// The non-sandbox Runtime Worker's managed root.
    public static var defaultRootURL: URL {
        rootURL(homeDirectory: systemHomeDirectory)
    }

    /// 偏好仅由同 bundle identifier 的主 App/普通后台 Agent 使用。
    /// Runtime Worker receives resolved execution settings over its socket.
    public static var productionDefaults: UserDefaults {
        .standard
    }

    static func rootURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/GetOudioV2", isDirectory: true)
    }

    public init(directoryURL: URL, defaults: UserDefaults = .standard, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL
        self.defaults = defaults
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public static func production(fileManager: FileManager = .default) throws -> AgentDataStore {
        let rootURL = controlRootURL(fileManager: fileManager)
        return try AgentDataStore(
            directoryURL: rootURL,
            defaults: productionDefaults,
            fileManager: fileManager
        )
    }

    /// Only the unsandboxed Runtime Worker may use this factory.
    public static func runtimeWorker(fileManager: FileManager = .default) throws -> AgentDataStore {
        try AgentDataStore(
            directoryURL: defaultRootURL,
            defaults: productionDefaults,
            fileManager: fileManager
        )
    }

    public static func diagnostic(
        rootURL: URL,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) throws -> AgentDataStore {
        try AgentDataStore(directoryURL: rootURL, defaults: defaults, fileManager: fileManager)
    }

    /// Only host-process code should call this.  Extensions use XPC and do not
    /// receive a filesystem capability for the v2 root.
    public static func forCurrentProcess(fileManager: FileManager = .default) throws -> AgentDataStore {
        try production(fileManager: fileManager)
    }

    static func controlRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("GetOudioV2", isDirectory: true)
    }

    private static var systemHomeDirectory: URL {
        guard let account = getpwuid(getuid()),
              let homeDirectory = account.pointee.pw_dir
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
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
            return directoryURL.appendingPathComponent("IPC", isDirectory: true)
        case .recordingControl:
            return directoryURL.appendingPathComponent("RecordingControl", isDirectory: true)
        case .recordingCache:
            return directoryURL.appendingPathComponent("Library/Caches/Recordings", isDirectory: true)
        }
    }
}
