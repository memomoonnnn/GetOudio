import Foundation
import Darwin

public final class RecordingControlStore {
    private let stateURL: URL
    private let commandDirectoryURL: URL
    private let lockURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        stateURL = rootURL.appendingPathComponent("state.json")
        commandDirectoryURL = rootURL.appendingPathComponent("commands", isDirectory: true)
        lockURL = rootURL.appendingPathComponent("control.lock")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: commandDirectoryURL, withIntermediateDirectories: true)
    }

    public convenience init(container: SharedContainer, fileManager: FileManager = .default) throws {
        try self.init(rootURL: container.url(for: .recordingControl), fileManager: fileManager)
    }

    public func snapshot() -> RecordingSessionSnapshot {
        withLock { snapshotUnlocked() }
    }

    public func save(_ snapshot: RecordingSessionSnapshot) throws {
        try withLock { try saveUnlocked(snapshot) }
    }

    public func enqueue(_ kind: RecordingCommandKind) throws {
        try withLock { try enqueueUnlocked(kind) }
    }

    /// Reserves the inactive state and enqueues exactly one start command while holding the
    /// interprocess lock. A concurrent toggle therefore observes `.starting` and becomes a stop.
    public func reserveStart() throws -> RecordingSessionSnapshot? {
        try withLock {
            guard !snapshotUnlocked().phase.isActive else { return nil }
            let reservation = RecordingSessionSnapshot(phase: .starting, startedAt: Date())
            try saveUnlocked(reservation)
            try enqueueUnlocked(.start)
            return reservation
        }
    }

    public func drainCommands() -> [RecordingCommand] {
        withLock { drainCommandsUnlocked() }
    }

    private func snapshotUnlocked() -> RecordingSessionSnapshot {
        guard let data = try? Data(contentsOf: stateURL),
              let snapshot = try? decoder.decode(RecordingSessionSnapshot.self, from: data) else {
            return .idle
        }
        return snapshot
    }

    private func saveUnlocked(_ snapshot: RecordingSessionSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stateURL, options: [.atomic])
    }

    private func enqueueUnlocked(_ kind: RecordingCommandKind) throws {
        let command = RecordingCommand(kind: kind)
        let data = try encoder.encode(command)
        let destination = commandDirectoryURL.appendingPathComponent("\(command.createdAt.timeIntervalSince1970)-\(command.id.uuidString).json")
        try data.write(to: destination, options: [.atomic])
    }

    private func drainCommandsUnlocked() -> [RecordingCommand] {
        let urls = ((try? fileManager.contentsOfDirectory(
            at: commandDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return urls.compactMap { url in
            defer { try? fileManager.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(RecordingCommand.self, from: data)
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try operation() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return try operation() }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
