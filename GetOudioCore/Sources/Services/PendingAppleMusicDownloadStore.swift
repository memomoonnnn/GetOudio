import Foundation

public struct PendingAppleMusicDownloadBatch: Codable, Equatable, Sendable {
    public var id: UUID
    public var jobs: [JobRequest]
    public var createdAt: Date

    public init(id: UUID = UUID(), jobs: [JobRequest], createdAt: Date = Date()) {
        self.id = id
        self.jobs = jobs
        self.createdAt = createdAt
    }
}

public final class PendingAppleMusicDownloadStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) throws {
        self.fileURL = try fileURL ?? SharedContainer.pendingAppleMusicDownloadsFileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func save(_ jobs: [JobRequest]) throws -> PendingAppleMusicDownloadBatch {
        let batch = PendingAppleMusicDownloadBatch(jobs: jobs)
        let data = try encoder.encode(batch)
        try data.write(to: fileURL, options: [.atomic])
        DiagnosticLog.append("pending Apple Music downloads saved count=\(jobs.count)")
        return batch
    }

    public func read() throws -> PendingAppleMusicDownloadBatch? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }
        return try decoder.decode(PendingAppleMusicDownloadBatch.self, from: data)
    }

    public func drain() throws -> PendingAppleMusicDownloadBatch? {
        let batch = try read()
        try? FileManager.default.removeItem(at: fileURL)
        DiagnosticLog.append("pending Apple Music downloads drain count=\(batch?.jobs.count ?? 0)")
        return batch
    }
}
