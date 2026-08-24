import Foundation
import GetOudioCore

/// Runs from the host executable under launchd and owns the ordinary v2 XPC
/// service. Apple Music runtime work is delegated to the scoped helper.
final class BackgroundAgent: NSObject, NSXPCListenerDelegate, BackgroundAgentXPCProtocol {
    private let listener = NSXPCListener(machServiceName: BackgroundAgentXPC.machServiceName)
    private let store: AgentDataStore
    private let notificationDispatcher: AgentNotificationDispatcher

    init(store: AgentDataStore) {
        self.store = store
        notificationDispatcher = AgentNotificationDispatcher(container: store)
        super.init()
        listener.delegate = self
    }

    static func main() {
        do {
            let store = try AgentDataStore.production()
            DiagnosticLog.configure(store: store)
            let agent = BackgroundAgent(store: store)
            agent.listener.resume()
            DiagnosticLog.append("[Agent] XPC listener started pid=\(ProcessInfo.processInfo.processIdentifier)")
            Task {
                await agent.recoverPendingWork()
            }
            RunLoop.main.run()
        } catch {
            NSLog("Get Oudio background agent unavailable: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: BackgroundAgentXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func handle(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        Task {
            do {
                let request = try JSONDecoder().decode(BackgroundAgentCommandRequest.self, from: requestData)
                let response = await handle(request)
                reply((try? JSONEncoder().encode(response)) ?? Data())
            } catch {
                let response = BackgroundAgentCommandResponse(id: UUID(), errorMessage: error.localizedDescription)
                reply((try? JSONEncoder().encode(response)) ?? Data())
            }
        }
    }

    private func handle(_ request: BackgroundAgentCommandRequest) async -> BackgroundAgentCommandResponse {
        do {
            switch request.command {
            case .healthCheck:
                return BackgroundAgentCommandResponse(id: request.id)
            case .finderConfiguration:
                let settings = SettingsStore(container: store)
                return BackgroundAgentCommandResponse(
                    id: request.id,
                    finderConfiguration: BackgroundAgentFinderConfiguration(
                        finderDirectories: settings.finderDirectoryURLs,
                        enabledPresets: ConversionActionFactory(settingsStore: settings).enabledPresets()
                    )
                )
            case .enqueueJobs:
                let jobs = request.jobs ?? []
                guard !jobs.isEmpty else { return BackgroundAgentCommandResponse(id: request.id) }
                let queue = try JobQueue(container: store)
                try queue.enqueue(jobs)
                let runner = HeadlessRunner(container: store)
                Task { await runner.processAndNotify() }
                return BackgroundAgentCommandResponse(id: request.id)
            case .unsupportedShareURLs:
                await NotificationService(container: store).notifyUnsupportedDownloadSource(urls: request.urls ?? [])
                return BackgroundAgentCommandResponse(id: request.id)
            case .recordingSnapshot:
                let snapshot = try RecordingControlStore(container: store).snapshot()
                return BackgroundAgentCommandResponse(id: request.id, recordingSnapshot: snapshot)
            case .dispatchNotificationEvents:
                await notificationDispatcher.dispatch()
                return BackgroundAgentCommandResponse(id: request.id)
            }
        } catch {
            return BackgroundAgentCommandResponse(id: request.id, errorMessage: error.localizedDescription)
        }
    }

    private func recoverPendingWork() async {
        let runner = HeadlessRunner(container: store)
        await runner.processAndNotify()
        await notificationDispatcher.dispatch()
    }
}

private actor AgentNotificationDispatcher {
    private let service: NotificationService
    private var retryTask: Task<Void, Never>?

    init(container: AgentDataStore) {
        service = NotificationService(container: container)
    }

    func dispatch() async {
        _ = await service.dispatchPendingNotificationEvents()
        scheduleRetryIfNeeded()
    }

    private func scheduleRetryIfNeeded() {
        retryTask?.cancel()
        guard let retryDate = service.nextPendingNotificationRetryDate() else { return }
        let delay = max(0, retryDate.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            await self?.dispatch()
        }
    }
}
