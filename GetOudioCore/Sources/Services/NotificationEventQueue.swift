import Foundation

public enum NotificationEventKind: String, Codable, Sendable {
    case conversionFinished
    case recordingFinished
    case tasksInterrupted
}

public struct RecordingNotificationEvent: Codable, Equatable, Sendable {
    public var fileName: String?
    public var message: String?

    public init(fileName: String?, message: String?) {
        self.fileName = fileName
        self.message = message
    }
}

public struct NotificationEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: NotificationEventKind
    public var summary: ConversionSummary?
    public var jobs: [JobRequest]
    public var recording: RecordingNotificationEvent?
    public var createdAt: Date
    public var attemptCount: Int
    public var nextAttemptAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case summary
        case jobs
        case recording
        case createdAt
        case attemptCount
        case nextAttemptAt
    }

    public init(
        id: UUID = UUID(),
        summary: ConversionSummary,
        jobs: [JobRequest],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = .conversionFinished
        self.summary = summary
        self.jobs = jobs
        recording = nil
        self.createdAt = createdAt
        attemptCount = 0
        nextAttemptAt = nil
    }

    public init(
        id: UUID = UUID(),
        recording: RecordingNotificationEvent,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = .recordingFinished
        summary = nil
        jobs = []
        self.recording = recording
        self.createdAt = createdAt
        attemptCount = 0
        nextAttemptAt = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(NotificationEventKind.self, forKey: .kind)
        summary = try container.decodeIfPresent(ConversionSummary.self, forKey: .summary)
        jobs = try container.decodeIfPresent([JobRequest].self, forKey: .jobs) ?? []
        recording = try container.decodeIfPresent(RecordingNotificationEvent.self, forKey: .recording)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
    }

    public init(interruptedJobs: [JobRequest], id: UUID = UUID()) {
        self.id = id
        kind = .tasksInterrupted
        summary = nil
        jobs = interruptedJobs
        recording = nil
        createdAt = Date()
        attemptCount = 0
        nextAttemptAt = nil
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
    private let suppressedURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = rootURL
        pendingURL = self.rootURL.appendingPathComponent("pending", isDirectory: true)
        processingURL = self.rootURL.appendingPathComponent("processing", isDirectory: true)
        suppressedURL = self.rootURL.appendingPathComponent("suppressed", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: processingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: suppressedURL, withIntermediateDirectories: true)
    }

    public convenience init(container: AgentDataStore, fileManager: FileManager = .default) throws {
        try self.init(rootURL: container.url(for: .notificationEvents), fileManager: fileManager)
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

    public func enqueueRecordingFinished(fileURL: URL?, message: String?) throws {
        try enqueue(NotificationEvent(
            recording: RecordingNotificationEvent(fileName: fileURL?.lastPathComponent, message: message)
        ))
    }

    public func claimPending(limit: Int = 20, now: Date = Date()) throws -> [ClaimedNotificationEvent] {
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
                if let nextAttemptAt = event.nextAttemptAt, nextAttemptAt > now {
                    try fileManager.moveItem(at: claimURL, to: sourceURL)
                    continue
                }
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

    public func nextAttemptDate() throws -> Date? {
        let urls = try fileManager.contentsOfDirectory(
            at: pendingURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        return try urls.compactMap { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(NotificationEvent.self, from: data).nextAttemptAt
        }
        .min()
    }

    public func retry(_ claimed: ClaimedNotificationEvent, after delay: TimeInterval) {
        var event = claimed.event
        event.attemptCount += 1
        event.nextAttemptAt = Date().addingTimeInterval(delay)
        move(claimed, event: event, to: pendingURL, action: "retry")
    }

    public func suppress(_ claimed: ClaimedNotificationEvent, reason: String) {
        move(claimed, event: claimed.event, to: suppressedURL, action: "suppressed reason=\(reason)")
    }

    private func move(
        _ claimed: ClaimedNotificationEvent,
        event: NotificationEvent,
        to destinationDirectory: URL,
        action: String
    ) {
        let destination = destinationDirectory.appendingPathComponent("\(event.id.uuidString).json")
        do {
            let data = try encoder.encode(event)
            try data.write(to: destination, options: [.atomic])
            try fileManager.removeItem(at: claimed.claimURL)
            DiagnosticLog.append("notification event \(action) id=\(event.id.uuidString) attempt=\(event.attemptCount)")
        } catch {
            DiagnosticLog.append("notification event \(action) failed id=\(event.id.uuidString): \(error.localizedDescription)")
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
