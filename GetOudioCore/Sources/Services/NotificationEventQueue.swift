import Foundation

public enum NotificationEventKind: String, Codable, Sendable {
    case conversionFinished
}

public struct NotificationEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: NotificationEventKind
    public var summary: ConversionSummary
    public var jobs: [JobRequest]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: NotificationEventKind = .conversionFinished,
        summary: ConversionSummary,
        jobs: [JobRequest],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.jobs = jobs
        self.createdAt = createdAt
    }
}

public struct ClaimedNotificationEvent: Sendable {
    public var event: NotificationEvent
    fileprivate var claimURL: URL
}

public final class NotificationEventQueue {
    private let rootURL: URL
    private let pendingURL: URL
    private let processingURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    public init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = try rootURL ?? SharedContainer.notificationEventsDirectoryURL()
        pendingURL = self.rootURL.appendingPathComponent("pending", isDirectory: true)
        processingURL = self.rootURL.appendingPathComponent("processing", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: processingURL, withIntermediateDirectories: true)
    }

    public func enqueue(_ event: NotificationEvent) throws {
        let destination = pendingURL.appendingPathComponent("\(event.id.uuidString).json")
        let data = try encoder.encode(event)
        try data.write(to: destination, options: [.atomic])
        DiagnosticLog.append("notification event enqueue id=\(event.id.uuidString) kind=\(event.kind.rawValue)")
    }

    public func enqueueConversionFinished(summary: ConversionSummary, jobs: [JobRequest]) throws {
        try enqueue(NotificationEvent(summary: summary, jobs: jobs))
    }

    public func claimPending(limit: Int = 20) throws -> [ClaimedNotificationEvent] {
        try requeueStaleClaims()
        let urls = try fileManager.contentsOfDirectory(
            at: pendingURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .prefix(limit)

        var claimed: [ClaimedNotificationEvent] = []
        for sourceURL in urls {
            let claimURL = processingURL.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                try fileManager.moveItem(at: sourceURL, to: claimURL)
                let data = try Data(contentsOf: claimURL)
                let event = try decoder.decode(NotificationEvent.self, from: data)
                claimed.append(ClaimedNotificationEvent(event: event, claimURL: claimURL))
            } catch {
                try? fileManager.removeItem(at: claimURL)
                DiagnosticLog.append("notification event claim skipped \(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !claimed.isEmpty {
            DiagnosticLog.append("notification event claim count=\(claimed.count)")
        }
        return claimed
    }

    public func acknowledge(_ claimed: ClaimedNotificationEvent) {
        do {
            try fileManager.removeItem(at: claimed.claimURL)
            DiagnosticLog.append("notification event acknowledged id=\(claimed.event.id.uuidString)")
        } catch {
            DiagnosticLog.append("notification event acknowledge failed id=\(claimed.event.id.uuidString): \(error.localizedDescription)")
        }
    }

    private func requeueStaleClaims(maxAge: TimeInterval = 300) throws {
        let now = Date()
        let urls = try fileManager.contentsOfDirectory(
            at: processingURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        for claimURL in urls {
            let values = try? claimURL.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modifiedAt = values?.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > maxAge else {
                continue
            }
            let pending = pendingURL.appendingPathComponent(claimURL.lastPathComponent)
            do {
                try fileManager.moveItem(at: claimURL, to: pending)
                DiagnosticLog.append("notification event requeued stale claim \(claimURL.lastPathComponent)")
            } catch {
                DiagnosticLog.append("notification event stale requeue failed \(claimURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
