import Foundation

public enum ShareEventKind: String, Codable, Sendable {
    case unsupportedDownloadSource
}

public struct ShareEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ShareEventKind
    public var urls: [URL]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ShareEventKind,
        urls: [URL],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.urls = urls
        self.createdAt = createdAt
    }
}

public final class ShareEventQueue {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) throws {
        self.fileURL = try fileURL ?? SharedContainer.shareEventsFileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func enqueue(_ events: [ShareEvent]) throws {
        guard !events.isEmpty else { return }
        var existing = try read()
        existing.append(contentsOf: events)
        try write(existing)
        DiagnosticLog.append("share events enqueue count=\(events.count) total=\(existing.count)")
    }

    public func read() throws -> [ShareEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([ShareEvent].self, from: data)
    }

    public func drain() throws -> [ShareEvent] {
        let events = try read()
        try write([])
        DiagnosticLog.append("share events drain count=\(events.count)")
        return events
    }

    private func write(_ events: [ShareEvent]) throws {
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: [.atomic])
    }
}
