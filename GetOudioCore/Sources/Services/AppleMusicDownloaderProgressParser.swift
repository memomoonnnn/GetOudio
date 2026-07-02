import Foundation

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
