import Darwin
import Foundation

/// The only persistent root used by the v2 installation.  It deliberately does
/// not inspect the legacy App Group container.
public struct AgentDataStore {
    public static let settingsSuiteName = "com.shengjiacheng.GetOudio"
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

    /// The managed root is intentionally outside the sandbox container so
    /// downloaded, verified runtime tools can execute from it.
    public static var defaultRootURL: URL {
        rootURL(homeDirectory: systemHomeDirectory)
    }

    /// 主 App、launchd Agent 与独立 Runtime Worker 共用同一偏好域。
    public static var productionDefaults: UserDefaults {
        UserDefaults(suiteName: settingsSuiteName) ?? .standard
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
        try migrateSandboxRootIfNeeded(fileManager: fileManager)
        return try AgentDataStore(
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

    static func migrateSandboxRootIfNeeded(fileManager: FileManager) throws {
        let sandboxRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("GetOudioV2", isDirectory: true)
        guard let sandboxRoot else { return }
        try migrateDataIfNeeded(
            from: sandboxRoot,
            to: defaultRootURL,
            fileManager: fileManager
        )
    }

    private static var systemHomeDirectory: URL {
        guard let account = getpwuid(getuid()),
              let homeDirectory = account.pointee.pw_dir
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
    }

    static func migrateDataIfNeeded(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        guard source != destination else { return }

        // The home-relative sandbox exception deliberately covers GetOudioV2,
        // not its parent.  Create that root atomically and keep all migration
        // coordination inside it so the exception remains narrow.
        if mkdir(destination.path, S_IRWXU) != 0 && errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let lockURL = destination.appendingPathComponent(".migration.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(.EIO)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(.EWOULDBLOCK)
        }
        defer { flock(descriptor, LOCK_UN) }

        let completionURL = destination.appendingPathComponent(".migration-complete")
        guard !fileManager.fileExists(atPath: completionURL.path) else { return }
        guard fileManager.fileExists(atPath: source.path) else {
            try Data().write(to: completionURL, options: .atomic)
            return
        }

        let retainedItems = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard retainedItems.isEmpty else { return }

        let staging = destination.appendingPathComponent(".migration-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staging)
            for item in try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                try fileManager.moveItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
            }
            try fileManager.removeItem(at: staging)
            try Data().write(to: completionURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
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
