import AppKit
import Foundation
import GetOudioCore
import Darwin
import UserNotifications

/// Runs from the host executable under launchd and owns the ordinary v2 XPC
/// service. Apple Music runtime work is delegated to the scoped helper.
final class BackgroundAgent: NSObject, NSXPCListenerDelegate, BackgroundAgentXPCProtocol, UNUserNotificationCenterDelegate {
    private let listener = NSXPCListener(machServiceName: BackgroundAgentXPC.machServiceName)
    private let store: AgentDataStore
    private let notificationService: NotificationService
    private let notificationDispatcher: AgentNotificationDispatcher
    private let appleMusicWorker: AppleMusicRuntimeWorkerClient
    private let taskCoordinator: BackgroundTaskCoordinator
    private let appleMusicState = AgentAppleMusicState()
    private var appleMusicLoginMonitor: Task<Void, Never>?

    init(store: AgentDataStore) {
        self.store = store
        notificationService = NotificationService(container: store)
        notificationDispatcher = AgentNotificationDispatcher(container: store)
        let appleMusicWorker = AppleMusicRuntimeWorkerClient(container: store)
        self.appleMusicWorker = appleMusicWorker
        taskCoordinator = BackgroundTaskCoordinator(
            container: store,
            appleMusicWorker: appleMusicWorker
        )
        super.init()
        listener.delegate = self
    }

    static func main() {
        do {
            let store = try AgentDataStore.production()
            DiagnosticLog.configure(store: store)
            let agent = BackgroundAgent(store: store)
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.delegate = agent
            agent.notificationService.registerAppleMusicNotificationCategories()
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
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        connection.exportedInterface = NSXPCInterface(with: BackgroundAgentXPCProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: BackgroundAgentEventXPCProtocol.self)
        connection.resume()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(NotificationService.foregroundPresentationOptions)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let copyInfo = notificationService.copyInfo(for: response) {
            DiagnosticLog.append("agent notification copy action received")
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyInfo, forType: .string)
                completionHandler()
            }
            return
        }

        guard let format = notificationService.appleMusicFormat(for: response.actionIdentifier) else {
            DiagnosticLog.append("agent notification action ignored id=\(response.actionIdentifier)")
            completionHandler()
            return
        }

        DiagnosticLog.append("agent Apple Music format action received format=\(format.rawValue)")
        completionHandler()
        Task { [weak self] in
            guard let self else { return }
            let guidance = await taskCoordinator.handlePendingAppleMusicDownload(format: format)
            await notificationDispatcher.dispatch()
            if let guidance {
                await SettingsAttentionLauncher.open(guidance, container: store)
            }
            DiagnosticLog.append("agent Apple Music format action finished format=\(format.rawValue)")
        }
    }

    func handle(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let connection = NSXPCConnection.current()
        Task {
            do {
                let request = try JSONDecoder().decode(BackgroundAgentCommandRequest.self, from: requestData)
                let response = await handle(request, connection: connection)
                reply((try? JSONEncoder().encode(response)) ?? Data())
            } catch {
                let response = BackgroundAgentCommandResponse(id: UUID(), errorMessage: error.localizedDescription)
                reply((try? JSONEncoder().encode(response)) ?? Data())
            }
        }
    }

    private func handle(
        _ request: BackgroundAgentCommandRequest,
        connection: NSXPCConnection?
    ) async -> BackgroundAgentCommandResponse {
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
                Task {
                    await taskCoordinator.processPendingWork()
                    await notificationDispatcher.dispatch()
                }
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
            case .handlePendingAppleMusicDownload:
                guard let format = request.appleMusicDownloadFormat else {
                    throw ProcessRunnerError.processFailed("缺少 Apple Music 下载格式。")
                }
                let guidance = await taskCoordinator.handlePendingAppleMusicDownload(
                    format: format
                )
                await notificationDispatcher.dispatch()
                return BackgroundAgentCommandResponse(
                    id: request.id,
                    settingsAttention: guidance
                )
            case .appleMusicStatus:
                return appleMusicResponse(request.id, statusReport: try await appleMusicWorker.status())
            case .appleMusicInstall:
                return appleMusicResponse(
                    request.id,
                    statusReport: try await performMonitored { try await self.appleMusicWorker.install() }
                )
            case .appleMusicUninstall:
                return appleMusicResponse(
                    request.id,
                    statusReport: try await performMonitored { try await self.appleMusicWorker.uninstall() }
                )
            case .appleMusicDownload:
                let jobs = request.jobs ?? []
                let summary = try await performMonitored { try await self.appleMusicWorker.download(jobs) }
                if jobs.contains(where: { $0.source == .shareExtension }) {
                    try NotificationEventQueue(container: store).enqueueConversionFinished(
                        summary: summary,
                        jobs: jobs
                    )
                    await notificationDispatcher.dispatch()
                }
                return appleMusicResponse(request.id, summary: summary)
            case .appleMusicInitialize:
                guard let value = request.appleMusicInitializeRequest else {
                    throw ProcessRunnerError.processFailed("initialize 请求缺少凭据。")
                }
                let summary = try await performMonitored {
                    try await self.appleMusicWorker.initializeWrapper(
                        username: value.username,
                        password: value.password,
                        verificationCode: value.verificationCode,
                        useSystemProxy: value.useSystemProxy
                    )
                }
                if summary.failureCount == 0 {
                    startAppleMusicLoginMonitor()
                }
                return appleMusicResponse(
                    request.id,
                    summary: summary
                )
            case .appleMusicSubmitCode:
                guard let value = request.appleMusicVerificationRequest else {
                    throw ProcessRunnerError.processFailed("submit-code 请求缺少验证码。")
                }
                return appleMusicResponse(
                    request.id,
                    summary: try await appleMusicWorker.submitVerificationCode(value.code)
                )
            case .appleMusicWrapperStatus:
                return appleMusicResponse(
                    request.id,
                    wrapperLoginStatus: try await appleMusicWorker.wrapperLoginStatus()
                )
            case .appleMusicSnapshot:
                let snapshot = try await appleMusicWorker.wrapperLoginSnapshot()
                appleMusicState.publish(loginSnapshot: snapshot)
                return BackgroundAgentCommandResponse(
                    id: request.id,
                    appleMusicLoginSnapshot: snapshot
                )
            case .appleMusicProgress:
                let progress = try await appleMusicWorker.progress()
                appleMusicState.publish(progress: progress)
                return BackgroundAgentCommandResponse(
                    id: request.id,
                    appleMusicProgress: progress
                )
            case .appleMusicCancel:
                try await appleMusicWorker.requestDownloadCancellation()
                return BackgroundAgentCommandResponse(id: request.id)
            case .subscribeAppleMusicEvents:
                guard let connection else {
                    throw BackgroundAgentXPCError.unavailable
                }
                await refreshAppleMusicWorkerState(reconcileLoginStatus: true)
                guard let event = appleMusicState.subscribe(connection: connection) else {
                    throw BackgroundAgentXPCError.invalidResponse
                }
                return BackgroundAgentCommandResponse(
                    id: request.id,
                    appleMusicEvent: event
                )
            }
        } catch {
            return BackgroundAgentCommandResponse(id: request.id, errorMessage: error.localizedDescription)
        }
    }

    private func performMonitored<T>(
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAppleMusicWorkerState()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { monitor.cancel() }
        let result = try await operation()
        await refreshAppleMusicWorkerState()
        return result
    }

    private func startAppleMusicLoginMonitor() {
        appleMusicLoginMonitor?.cancel()
        appleMusicLoginMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshAppleMusicWorkerState()
                let snapshot = appleMusicState.snapshot.loginSnapshot
                guard snapshot?.status.isInProgress == true else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func refreshAppleMusicWorkerState(reconcileLoginStatus: Bool = false) async {
        do {
            let progress = try await appleMusicWorker.progress()
            appleMusicState.publish(progress: progress)
        } catch {
            // Preserve the last published progress across transient Worker errors.
        }

        do {
            if reconcileLoginStatus {
                _ = try await appleMusicWorker.wrapperLoginStatus()
            }
            let snapshot = try await appleMusicWorker.wrapperLoginSnapshot()
            appleMusicState.publish(loginSnapshot: snapshot)
        } catch {
            // Preserve the last published login snapshot across transient errors.
        }
    }

    private func appleMusicResponse(
        _ requestID: UUID,
        statusReport: AppleMusicRuntimeAgentStatusReport? = nil,
        summary: ConversionSummary? = nil,
        wrapperLoginStatus: AppleMusicWrapperLoginStatus? = nil
    ) -> BackgroundAgentCommandResponse {
        BackgroundAgentCommandResponse(
            id: requestID,
            appleMusicResponse: AppleMusicRuntimeAgentResponseEnvelope(
                id: requestID,
                statusReport: statusReport,
                summary: summary,
                wrapperLoginStatus: wrapperLoginStatus
            )
        )
    }

    private func recoverPendingWork() async {
        await taskCoordinator.processPendingWork()
        await taskCoordinator.recoverPendingAppleMusicDownloadIfNeeded()
        await notificationDispatcher.dispatch()
    }
}

private final class AgentAppleMusicState: @unchecked Sendable {
    private struct Subscriber {
        let connection: NSXPCConnection
        let sink: BackgroundAgentEventXPCProtocol
    }

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var progress: AppleMusicRuntimeProgress?
    private var loginSnapshot: AppleMusicWrapperLoginSnapshot?
    private var subscribers: [UUID: Subscriber] = [:]

    var snapshot: AppleMusicRuntimeAgentEvent {
        lock.withLock {
            AppleMusicRuntimeAgentEvent(
                revision: revision,
                progress: progress,
                loginSnapshot: loginSnapshot
            )
        }
    }

    func subscribe(connection: NSXPCConnection) -> AppleMusicRuntimeAgentEvent? {
        let id = UUID()
        guard let sink = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            self?.removeSubscriber(id)
        }) as? BackgroundAgentEventXPCProtocol else { return nil }

        let event = lock.withLock { () -> AppleMusicRuntimeAgentEvent in
            subscribers[id] = Subscriber(connection: connection, sink: sink)
            return AppleMusicRuntimeAgentEvent(
                revision: revision,
                progress: progress,
                loginSnapshot: loginSnapshot
            )
        }
        connection.invalidationHandler = { [weak self] in
            self?.removeSubscriber(id)
        }
        return event
    }

    func publish(progress value: AppleMusicRuntimeProgress?) {
        publishIfChanged {
            guard progress != value else { return false }
            progress = value
            return true
        }
    }

    func publish(loginSnapshot value: AppleMusicWrapperLoginSnapshot?) {
        publishIfChanged {
            guard loginSnapshot != value else { return false }
            loginSnapshot = value
            return true
        }
    }

    private func publishIfChanged(_ update: () -> Bool) {
        let publication = lock.withLock { () -> (AppleMusicRuntimeAgentEvent, [Subscriber])? in
            guard update() else { return nil }
            revision &+= 1
            let event = AppleMusicRuntimeAgentEvent(
                revision: revision,
                progress: progress,
                loginSnapshot: loginSnapshot
            )
            return (event, Array(subscribers.values))
        }
        guard let (event, subscribers) = publication,
              let data = try? JSONEncoder().encode(event) else { return }
        for subscriber in subscribers {
            subscriber.sink.handleEvent(data)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        _ = lock.withLock {
            subscribers.removeValue(forKey: id)
        }
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
