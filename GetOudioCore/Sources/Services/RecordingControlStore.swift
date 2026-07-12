import Foundation

public final class RecordingControlStore {
    private let stateURL: URL
    private let commandDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        stateURL = rootURL.appendingPathComponent("state.json")
        commandDirectoryURL = rootURL.appendingPathComponent("commands", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: commandDirectoryURL, withIntermediateDirectories: true)
    }

    public convenience init(container: SharedContainer, fileManager: FileManager = .default) throws {
        try self.init(rootURL: container.url(for: .recordingControl), fileManager: fileManager)
    }

    public func snapshot() -> RecordingSessionSnapshot {
        guard let data = try? Data(contentsOf: stateURL),
              let snapshot = try? decoder.decode(RecordingSessionSnapshot.self, from: data) else {
            return .idle
        }
        return snapshot
    }

    public func save(_ snapshot: RecordingSessionSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stateURL, options: [.atomic])
    }

    public func enqueue(_ kind: RecordingCommandKind) throws {
        let command = RecordingCommand(kind: kind)
        let data = try encoder.encode(command)
        let destination = commandDirectoryURL.appendingPathComponent("\(command.createdAt.timeIntervalSince1970)-\(command.id.uuidString).json")
        try data.write(to: destination, options: [.atomic])
    }

    public func drainCommands() -> [RecordingCommand] {
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
}

