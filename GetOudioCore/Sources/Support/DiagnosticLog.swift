import Foundation

public enum DiagnosticLog {
    private static let lock = NSLock()
    private static var configuredLogURL: URL?

    public static func configure(container: SharedContainer) {
        lock.lock()
        configuredLogURL = container.url(for: .conversionLog)
        lock.unlock()
    }

    public static func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let logURL = configuredLogURL else {
            NSLog("Get Oudio: \(message)")
            return
        }

        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = line.data(using: .utf8) ?? Data()

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: [.atomic])
            }
        } catch {
            NSLog("Get Oudio diagnostic log failed: \(error.localizedDescription)")
        }
    }
}
