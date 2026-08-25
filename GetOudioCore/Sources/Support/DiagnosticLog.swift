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

    public static func configure(store: AgentDataStore) {
        lock.lock()
        configuredLogURL = store.url(for: .conversionLog)
        configuredSettingsStore = SettingsStore(container: store)
        lock.unlock()
    }

    /// The non-sandboxed Runtime Worker must not read the host app's defaults.
    /// It therefore keeps file diagnostics disabled and relies on system logs.
    public static func configureRuntimeWorker(store: AgentDataStore) {
        lock.lock()
        configuredLogURL = store.url(for: .conversionLog)
        configuredSettingsStore = nil
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
