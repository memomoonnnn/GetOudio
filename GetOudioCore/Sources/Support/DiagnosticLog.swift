import Foundation

public enum DiagnosticLog {
    public enum Level: String {
        case debug
        case info
        case notice
        case error
    }

    private static let lock = NSLock()
    private static var configuredLogURL: URL?
    private static var configuredSettingsStore: SettingsStore?

    public static func configure(container: SharedContainer) {
        lock.lock()
        configuredLogURL = container.url(for: .conversionLog)
        configuredSettingsStore = SettingsStore(container: container)
        lock.unlock()
    }

    public static func append(_ message: String, level: Level = .debug) {
        lock.lock()
        defer { lock.unlock() }

        guard configuredSettingsStore?.isDebugLoggingEnabled == true else {
            return
        }

        guard let logURL = configuredLogURL else { return }

        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)\n"
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
