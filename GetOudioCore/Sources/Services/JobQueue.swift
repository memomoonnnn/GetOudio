import Darwin
import Foundation

public struct ClaimedJobBatch: Sendable {
    public let jobs: [JobRequest]
    fileprivate let fileURL: URL
}

public enum JobSubmissionDecision: String, Codable, Sendable {
    case withdraw
    case enqueue
}

public final class JobQueue: @unchecked Sendable {
    private struct WaitingSubmission: Codable {
        var id: UUID
        var jobs: [JobRequest]
    }

    private struct Contents: Codable {
        var jobs: [JobRequest] = []
        var waiting: [WaitingSubmission] = []
    }

    private struct ProcessingContents: Codable {
        var jobs: [JobRequest]
        var processes: [ProcessIdentity] = []
    }

    private let fileURL: URL
    private let processingFileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.processingFileURL = Self.processingFileURL(for: self.fileURL)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public convenience init(container: AgentDataStore, fileManager: FileManager = .default) throws {
        try self.init(fileURL: container.url(for: .jobQueue), fileManager: fileManager)
    }

    public func enqueue(_ jobs: [JobRequest]) throws {
        guard !jobs.isEmpty else { return }
        let lock = try queueLock()
        defer { lock.unlock() }
        var contents = try readContents()
        let newJobs = try uniqueJobs(jobs, in: contents)
        guard !newJobs.isEmpty else {
            DiagnosticLog.append("queue enqueue skipped duplicate count=\(jobs.count)")
            return
        }
        contents.jobs.append(contentsOf: newJobs)
        try write(contents)
        DiagnosticLog.append("queue enqueue count=\(newJobs.count) total=\(contents.jobs.count)")
    }

    public func read() throws -> [JobRequest] {
        let lock = try queueLock()
        defer { lock.unlock() }
        return try readContents().jobs
    }

    private func readContents() throws -> Contents {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Contents()
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return Contents()
        }
        // Older versions stored only the executable jobs array.
        if let jobs = try? decoder.decode([JobRequest].self, from: data) {
            return Contents(jobs: jobs)
        }
        return try decoder.decode(Contents.self, from: data)
    }

    @discardableResult
    public func hold(_ jobs: [JobRequest], submissionID: UUID) throws -> Bool {
        let lock = try queueLock()
        defer { lock.unlock() }
        var contents = try readContents()
        guard !contents.waiting.contains(where: { $0.id == submissionID }) else { return false }
        let jobs = try uniqueJobs(jobs, in: contents)
        guard !jobs.isEmpty else { return false }
        contents.waiting.append(WaitingSubmission(id: submissionID, jobs: jobs))
        try write(contents)
        return true
    }

    @discardableResult
    public func resolve(_ submissionID: UUID, decision: JobSubmissionDecision) throws -> Bool {
        let lock = try queueLock()
        defer { lock.unlock() }
        var contents = try readContents()
        guard let index = contents.waiting.firstIndex(where: { $0.id == submissionID }) else { return false }
        let submission = contents.waiting.remove(at: index)
        if decision == .enqueue {
            contents.jobs.append(contentsOf: submission.jobs)
        }
        try write(contents)
        return true
    }

    /// Called once before the Agent accepts requests, never during execution.
    /// Record the interruption before deleting task state, so a failed Outbox write
    /// leaves the old tasks available for the next startup cleanup attempt.
    public func discardUnfinished(beforeDiscard: ([JobRequest]) throws -> Void) throws {
        let lock = try queueLock()
        defer { lock.unlock() }
        let contents = try readContents()
        let processing = try readProcessingContents()
        for process in processing.processes {
            try process.terminateIfStillRunning()
        }
        let jobs = processing.jobs + contents.jobs + contents.waiting.flatMap(\.jobs)
        try beforeDiscard(jobs)
        try removeProcessingFileIfPresent()
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        DiagnosticLog.append("queue discarded unfinished count=\(jobs.count)")
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

    public func claimPending() throws -> ClaimedJobBatch? {
        let lock = try queueLock()
        defer { lock.unlock() }
        guard !fileManager.fileExists(atPath: processingFileURL.path) else {
            DiagnosticLog.append("queue claim skipped active processing batch")
            return nil
        }

        var contents = try readContents()
        let jobs = contents.jobs
        guard !jobs.isEmpty else { return nil }
        // Persist the claim first. A crash between these writes is handled by
        // startup discard, never by replaying either copy of the jobs.
        try encoder.encode(ProcessingContents(jobs: jobs)).write(to: processingFileURL, options: [.atomic])
        contents.jobs = []
        try write(contents)

        DiagnosticLog.append("queue claim count=\(jobs.count)")
        return ClaimedJobBatch(jobs: jobs, fileURL: processingFileURL)
    }

    public func acknowledge(_ claim: ClaimedJobBatch) throws {
        let lock = try queueLock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: claim.fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: claim.fileURL)
        DiagnosticLog.append("queue acknowledge count=\(claim.jobs.count)")
    }

    private func write(_ contents: Contents) throws {
        let data = try encoder.encode(contents)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func queueLock() throws -> QueueLock {
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return QueueLock(descriptor: descriptor)
    }

    private func readProcessingContents() throws -> ProcessingContents {
        guard fileManager.fileExists(atPath: processingFileURL.path) else { return ProcessingContents(jobs: []) }
        let data = try Data(contentsOf: processingFileURL)
        guard !data.isEmpty else { return ProcessingContents(jobs: []) }
        if let jobs = try? decoder.decode([JobRequest].self, from: data) {
            return ProcessingContents(jobs: jobs)
        }
        return try decoder.decode(ProcessingContents.self, from: data)
    }

    func recordProcess(_ identity: ProcessIdentity) throws {
        let lock = try queueLock()
        defer { lock.unlock() }
        var contents = try readProcessingContents()
        guard !contents.jobs.isEmpty else {
            throw ProcessRunnerError.processFailed("任务认领记录不存在，不能启动子进程。")
        }
        contents.processes.append(identity)
        try encoder.encode(contents).write(to: processingFileURL, options: [.atomic])
    }

    private func uniqueJobs(_ jobs: [JobRequest], in contents: Contents) throws -> [JobRequest] {
        var ids = Set(try (readProcessingContents().jobs + contents.jobs + contents.waiting.flatMap(\.jobs)).map(\.id))
        return jobs.filter { ids.insert($0.id).inserted }
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

/// The Agent's single queue consumer. Decisions and submissions share this actor
/// so an awaited notification or conversion cannot lose a later enqueue.
public actor JobQueueScheduler {
    private let queue: JobQueue
    private let notifications: NotificationService
    private let execute: @Sendable ([JobRequest]) async -> Void
    private var processingTask: Task<Void, Never>?
    private var processingError: Error?

    public init(
        queue: JobQueue,
        notifications: NotificationService,
        execute: @escaping @Sendable ([JobRequest]) async -> Void
    ) {
        self.queue = queue
        self.notifications = notifications
        self.execute = execute
    }

    public func submit(_ jobs: [JobRequest], submissionID: UUID) async throws {
        if let processingError { throw processingError }
        guard !jobs.isEmpty else { return }
        if processingTask != nil {
            guard try queue.hold(jobs, submissionID: submissionID) else { return }
            do {
                try await notifications.notifyJobSubmissionDecision(submissionID: submissionID)
            } catch {
                try queue.resolve(submissionID, decision: .withdraw)
                notifications.removeJobSubmissionNotification(submissionID)
                throw error
            }
        } else {
            try queue.enqueue(jobs)
            startProcessingIfNeeded()
        }
    }

    public func resolve(_ submissionID: UUID, decision: JobSubmissionDecision) throws {
        if let processingError { throw processingError }
        guard try queue.resolve(submissionID, decision: decision) else { return }
        notifications.removeJobSubmissionNotification(submissionID)
        if decision == .enqueue { startProcessingIfNeeded() }
    }

    public func waitUntilIdle() async {
        await processingTask?.value
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        // Reserve the consumer synchronously, before another submit can enter.
        processingTask = Task { await self.processPendingWork() }
    }

    private func processPendingWork() async {
        defer { processingTask = nil }
        do {
            while let batch = try queue.claimPending() {
                await ProcessRunner.$processStarted.withValue({ [queue] in try queue.recordProcess($0) }) {
                    await execute(batch.jobs)
                }
                try queue.acknowledge(batch)
            }
        } catch {
            processingError = error
            DiagnosticLog.append("agent queue processing failed: \(error.localizedDescription)")
        }
    }
}

private final class QueueLock {
    private let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func unlock() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
