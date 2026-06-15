import Foundation

public final class JobQueue {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) throws {
        self.fileURL = try fileURL ?? SharedContainer.queueFileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func enqueue(_ jobs: [JobRequest]) throws {
        guard !jobs.isEmpty else { return }
        var existing = try read()
        existing.append(contentsOf: jobs)
        try write(existing)
    }

    public func read() throws -> [JobRequest] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([JobRequest].self, from: data)
    }

    public func drain() throws -> [JobRequest] {
        let jobs = try read()
        try write([])
        return jobs
    }

    private func write(_ jobs: [JobRequest]) throws {
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: [.atomic])
    }
}

