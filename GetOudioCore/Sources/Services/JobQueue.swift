import Foundation

public struct ClaimedJobBatch: Sendable {
    public let jobs: [JobRequest]
    fileprivate let fileURL: URL
}

public final class JobQueue {
    private let fileURL: URL
    private let processingFileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileURL = try fileURL ?? SharedContainer.queueFileURL()
        self.fileManager = fileManager
        self.processingFileURL = Self.processingFileURL(for: self.fileURL)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func enqueue(_ jobs: [JobRequest]) throws {
        guard !jobs.isEmpty else { return }
        var existing = try read()
        existing.append(contentsOf: jobs)
        try write(existing)
        DiagnosticLog.append("queue enqueue count=\(jobs.count) total=\(existing.count)")
    }

    public func read() throws -> [JobRequest] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([JobRequest].self, from: data)
    }

    public func drain() throws -> [JobRequest] {
        guard let claim = try claimPending() else {
            DiagnosticLog.append("queue drain count=0")
            return []
        }

        try acknowledge(claim)
        DiagnosticLog.append("queue drain count=\(claim.jobs.count)")
        return claim.jobs
    }

    public func claimPending(staleClaimMaxAge: TimeInterval = 300) throws -> ClaimedJobBatch? {
        try requeueStaleClaim(maxAge: staleClaimMaxAge)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard !fileManager.fileExists(atPath: processingFileURL.path) else {
            DiagnosticLog.append("queue claim skipped active processing batch")
            return nil
        }

        try fileManager.moveItem(at: fileURL, to: processingFileURL)
        let data = try Data(contentsOf: processingFileURL)
        guard !data.isEmpty else {
            try removeProcessingFileIfPresent()
            return nil
        }

        let jobs = try decoder.decode([JobRequest].self, from: data)
        guard !jobs.isEmpty else {
            try removeProcessingFileIfPresent()
            return nil
        }

        DiagnosticLog.append("queue claim count=\(jobs.count)")
        return ClaimedJobBatch(jobs: jobs, fileURL: processingFileURL)
    }

    public func acknowledge(_ claim: ClaimedJobBatch) throws {
        guard fileManager.fileExists(atPath: claim.fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: claim.fileURL)
        DiagnosticLog.append("queue acknowledge count=\(claim.jobs.count)")
    }

    private func write(_ jobs: [JobRequest]) throws {
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func requeueStaleClaim(maxAge: TimeInterval) throws {
        guard fileManager.fileExists(atPath: processingFileURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: processingFileURL.path)
        if let modificationDate = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modificationDate) < maxAge {
            return
        }

        let data = try Data(contentsOf: processingFileURL)
        let claimedJobs = data.isEmpty ? [] : try decoder.decode([JobRequest].self, from: data)
        if !claimedJobs.isEmpty {
            let pendingJobs = try read()
            try write(claimedJobs + pendingJobs)
        }
        try removeProcessingFileIfPresent()
        DiagnosticLog.append("queue requeued stale claim count=\(claimedJobs.count)")
    }

    private func removeProcessingFileIfPresent() throws {
        guard fileManager.fileExists(atPath: processingFileURL.path) else {
            return
        }
        try fileManager.removeItem(at: processingFileURL)
    }

    private static func processingFileURL(for fileURL: URL) -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let pathExtension = fileURL.pathExtension
        let fileName = pathExtension.isEmpty
            ? "\(baseName).processing"
            : "\(baseName).processing.\(pathExtension)"
        return directory.appendingPathComponent(fileName)
    }
}
