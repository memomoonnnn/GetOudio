import Foundation

public struct AppleMusicDownloaderEvent: Codable, Equatable, Sendable {
    public struct Content: Codable, Equatable, Sendable {
        public var id: String?
        public var kind: String?
        public var title: String?
        public var artist: String?
        public var album: String?
        public var playlistTitle: String?
        public var position: Int?
        public var total: Int?

        private enum CodingKeys: String, CodingKey {
            case id, kind, title, artist, album, position, total
            case playlistTitle = "playlist_title"
        }
    }

    public struct Data: Codable, Equatable, Sendable {
        public var content: Content?
        public var phase: String?
        public var completedBytes: Int64?
        public var totalBytes: Int64?
        public var fraction: Double?
        public var madeProgress: Bool?
        public var outputPath: String?
        public var status: String?
        public var completed: Int?
        public var warnings: Int?
        public var failures: Int?
        public var level: String?
        public var code: String?
        public var message: String?

        private enum CodingKeys: String, CodingKey {
            case content, phase, fraction, status, completed, warnings, failures, level, code, message
            case completedBytes = "completed_bytes"
            case totalBytes = "total_bytes"
            case madeProgress = "made_progress"
            case outputPath = "output_path"
        }
    }

    public var schemaVersion: Int
    public var event: String
    public var sequence: UInt64
    public var runID: String
    public var itemID: String?
    public var data: Data?

    private enum CodingKeys: String, CodingKey {
        case event, sequence, data
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case itemID = "item_id"
    }
}

public struct AppleMusicDownloaderRunCompletion: Equatable, Sendable {
    public var status: String
    public var completed: Int
    public var warnings: Int
    public var failures: Int

    public init(status: String, completed: Int, warnings: Int, failures: Int) {
        self.status = status
        self.completed = completed
        self.warnings = warnings
        self.failures = failures
    }

    public var failureMessage: String? {
        switch status {
        case "completed":
            return nil
        case "partial":
            return "Apple Music 下载未完整完成。成功 \(completed) 个，警告 \(warnings) 个。"
        case "failed":
            return "Apple Music 下载失败。成功 \(completed) 个，失败 \(failures) 个。"
        default:
            return "Apple Music 下载未正常完成（状态：\(status)）。"
        }
    }
}

public final class AppleMusicDownloaderEventTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var storedContent: AppleMusicDownloaderEvent.Content?
    private var storedFailureMessage = ""
    private var storedDiagnosticMessage = ""
    private var storedCompletion: AppleMusicDownloaderRunCompletion?

    public init() {}

    public func observe(_ chunk: String) -> [AppleMusicDownloaderEvent] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        var events: [AppleMusicDownloaderEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(AppleMusicDownloaderEvent.self, from: data),
                  event.schemaVersion == 1
            else {
                continue
            }
            if let content = event.data?.content {
                storedContent = content
            }
            if event.event == "item_failed", let message = event.data?.message, !message.isEmpty {
                storedFailureMessage = message
            }
            if event.event == "diagnostic", let message = event.data?.message, !message.isEmpty {
                storedDiagnosticMessage = message
            }
            if event.event == "run_completed", let status = event.data?.status {
                storedCompletion = AppleMusicDownloaderRunCompletion(
                    status: status,
                    completed: event.data?.completed ?? 0,
                    warnings: event.data?.warnings ?? 0,
                    failures: event.data?.failures ?? 0
                )
            }
            events.append(event)
        }
        if buffer.count > 64_000 {
            buffer = String(buffer.suffix(64_000))
        }
        return events
    }

    public var currentContent: AppleMusicDownloaderEvent.Content? {
        lock.lock()
        defer { lock.unlock() }
        return storedContent
    }

    public var failureMessage: String {
        lock.lock()
        defer { lock.unlock() }
        return storedFailureMessage
    }

    public var completionStatus: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletion?.status
    }

    public var diagnosticMessage: String {
        lock.lock()
        defer { lock.unlock() }
        return storedDiagnosticMessage
    }

    public var completion: AppleMusicDownloaderRunCompletion? {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletion
    }
}

public enum AppleMusicDownloaderProgressParser {
    public static func progressMessage(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in normalized.reversed() {
            if line.localizedCaseInsensitiveContains("Downloading") {
                return compact(line)
            }
            if line.localizedCaseInsensitiveContains("Decrypting") {
                return compact(line)
            }
            if line.localizedCaseInsensitiveContains("Song:") || line.localizedCaseInsensitiveContains("Album:") {
                return compact(line)
            }
            if line.localizedCaseInsensitiveContains("Quality set to") {
                return compact(line)
            }
        }

        return nil
    }

    private static func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class AppleMusicDownloaderProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var lastMessage: String?

    public init() {}

    public func observe(_ chunk: String) -> String? {
        lock.lock()
        buffer.append(chunk)
        if buffer.count > 16_000 {
            buffer = String(buffer.suffix(16_000))
        }
        if let message = AppleMusicDownloaderProgressParser.progressMessage(from: buffer),
           message != lastMessage {
            lastMessage = message
            lock.unlock()
            return message
        }
        lock.unlock()
        return nil
    }
}
