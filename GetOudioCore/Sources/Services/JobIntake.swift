import Foundation

public final class JobIntake {
    private let queue: JobQueue
    private let markerStore: LaunchMarkerStore

    public init(queue: JobQueue, markerStore: LaunchMarkerStore) {
        self.queue = queue
        self.markerStore = markerStore
    }

    public convenience init(container: SharedContainer) throws {
        try self.init(
            queue: JobQueue(container: container),
            markerStore: LaunchMarkerStore(container: container)
        )
    }

    public func enqueue(_ jobs: [JobRequest], launchSource: LaunchSource) throws {
        guard !jobs.isEmpty else {
            DiagnosticLog.append("job intake skipped empty source=\(launchSource.rawValue)")
            return
        }

        try queue.enqueue(jobs)
        markerStore.mark(launchSource)
        DiagnosticLog.append("job intake enqueue source=\(launchSource.rawValue) count=\(jobs.count)")
    }
}
