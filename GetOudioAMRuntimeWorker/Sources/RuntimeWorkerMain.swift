import Darwin
import Foundation
import GetOudioCore

/// An on-demand, non-sandboxed helper for the managed Apple Music toolchain.
/// launchd starts it only when the Background Agent connects to its Mach service.
@main
enum GetOudioAMRuntimeWorker {
    static func main() {
        do {
            let store = try runtimeStore()
            DiagnosticLog.configureRuntimeWorker(store: store)
            let state = RuntimeWorkerState()
            let loginState = WrapperLoginState()
            let activityTracker = RuntimeWorkerActivityTracker()
            let server = RuntimeWorkerXPCServer(
                state: state,
                hasBackgroundActivity: { activityTracker.isActive },
                handle: {
                    request in await handle(
                        request,
                        store: store,
                        state: state,
                        loginState: loginState,
                        activityTracker: activityTracker
                    )
                }
            )
            server.start()
            withExtendedLifetime(server) {
                dispatchMain()
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func handle(
        _ request: AppleMusicRuntimeWorkerRequest,
        store: AgentDataStore,
        state: RuntimeWorkerState,
        loginState: WrapperLoginState,
        activityTracker: RuntimeWorkerActivityTracker
    ) async -> AppleMusicRuntimeAgentResponseEnvelope {
        do {
            DiagnosticLog.configureRuntimeWorker(store: store)
            let resourceRoot = request.resourceRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(
                container: store,
                resourceRoot: resourceRoot,
                gpacPackageURLOverride: request.gpacPackageURLOverride,
                progressHandler: { state.publish(progress: $0) }
            )
            switch request.command {
            case .status:
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case .install:
                _ = try await manager.installManagedRuntime()
                try await wrapperRuntime(manager: manager)
                    .finalizeManagedImageUpdate(resetAuthentication: true)
                loginState.publish(.init(phase: .notInitialized, message: "Apple Music 下载功能尚未初始化"))
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case .uninstall:
                try await manager.uninstallManagedRuntime()
                loginState.publish(.init(phase: .notInitialized, message: "Apple Music 下载功能尚未启用"))
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case .download:
                guard let downloadRequest = request.downloadRequest else {
                    throw ProcessRunnerError.processFailed("download 请求缺少任务。")
                }
                let summary = await worker(
                    resourceRoot: resourceRoot,
                    manager: manager,
                    state: state,
                    executionSettings: request.executionSettings
                )
                    .download(downloadRequest.jobs)
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case .initialize:
                guard let initializeRequest = request.initializeRequest else {
                    throw ProcessRunnerError.processFailed("initialize 请求缺少凭据。")
                }
                loginState.publish(.init(phase: .starting, message: "正在启动登录容器"))
                let wrapper = wrapperRuntime(
                    manager: manager,
                    useSystemProxy: initializeRequest.useSystemProxy
                )
                let summary = await worker(
                    resourceRoot: resourceRoot,
                    manager: manager,
                    wrapperRuntime: wrapper,
                    state: state,
                    executionSettings: request.executionSettings
                )
                    .initializeWrapper(
                        username: initializeRequest.username,
                        password: initializeRequest.password,
                        verificationCode: initializeRequest.verificationCode,
                        useSystemProxy: initializeRequest.useSystemProxy
                    )
                if summary.failureCount == 0 {
                    monitorLoginStatus(
                        runtime: wrapper,
                        loginState: loginState,
                        activityTracker: activityTracker
                    )
                } else {
                    loginState.publish(.init(phase: .failed, message: "登录容器启动失败，可以重新初始化"))
                }
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case .submitCode:
                guard let verificationRequest = request.verificationRequest else {
                    throw ProcessRunnerError.processFailed("submit-code 请求缺少验证码。")
                }
                let summary = await worker(
                    resourceRoot: resourceRoot,
                    manager: manager,
                    state: state,
                    executionSettings: request.executionSettings
                )
                    .submitWrapperVerificationCode(verificationRequest.code)
                if summary.failureCount == 0 {
                    loginState.publish(.init(phase: .verificationCodeSubmitted, message: "验证码已写入，等待 wrapper 读取"))
                }
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case .wrapperStatus:
                let status = await loginState.reconcile(runtime: wrapperRuntime(manager: manager))
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, wrapperLoginStatus: status)
            case .stopRuntime:
                await ColimaDockerRuntime(runtimeManager: manager).stopIfRunning()
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id)
            case .cancel:
                state.requestCancellation()
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id)
            case .progress:
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, progress: state.progress)
            case .snapshot:
                _ = await loginState.reconcile(runtime: wrapperRuntime(manager: manager))
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    wrapperLoginSnapshot: loginState.snapshot
                )
            }
        } catch {
            return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, errorMessage: error.localizedDescription)
        }
    }

    private static func runtimeStore() throws -> AgentDataStore {
        try AgentDataStore.runtimeWorker()
    }

    private static func statusReport(manager: AppleMusicRuntimeManager) async -> AppleMusicRuntimeAgentStatusReport {
        let statuses = manager.localComponentStatuses()
        let missingCount = statuses.filter { !$0.isReady }.count
        return AppleMusicRuntimeAgentStatusReport(
            isEnabled: manager.isEnabled,
            rootPath: manager.rootURL.path,
            message: missingCount == 0 && manager.isEnabled
                ? "Downloader Runtime 已就绪，位置：\(manager.rootURL.path)"
                : "\(missingCount) 个 Downloader Runtime 组件未就绪",
            statuses: statuses
        )
    }

    private static func worker(
        resourceRoot: URL?,
        manager: AppleMusicRuntimeManager,
        wrapperRuntime: AppleMusicWrapperRuntime? = nil,
        state: RuntimeWorkerState,
        executionSettings: AppleMusicRuntimeExecutionSettings?
    ) -> AppleMusicDownloadService {
        AppleMusicDownloadService(
            componentManager: BundledComponentManager(resourceRoot: resourceRoot),
            runtimeManager: manager,
            wrapperRuntime: wrapperRuntime ?? self.wrapperRuntime(manager: manager),
            settingsStore: nil,
            agentClient: nil,
            useAgent: false,
            cancellationRequested: { state.isCancellationRequested },
            executionSettings: executionSettings,
            progressHandler: { state.publish(progress: $0) }
        )
    }

    private static func wrapperRuntime(
        manager: AppleMusicRuntimeManager,
        useSystemProxy: Bool? = nil
    ) -> AppleMusicWrapperRuntime {
        AppleMusicWrapperRuntime(runtimeManager: manager, systemProxyEnabled: useSystemProxy)
    }

    private static func monitorLoginStatus(
        runtime: AppleMusicWrapperRuntime,
        loginState: WrapperLoginState,
        activityTracker: RuntimeWorkerActivityTracker
    ) {
        guard activityTracker.begin() else { return }
        Task.detached {
            await AppleMusicWrapperLoginStatusPolling.observe(
                poll: { await loginState.reconcile(runtime: runtime) },
                publish: { _ in }
            )
            activityTracker.end()
        }
    }
}

private final class RuntimeWorkerActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !active else { return false }
        active = true
        return true
    }

    func end() {
        lock.lock()
        active = false
        lock.unlock()
    }
}

private final class RuntimeWorkerState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false
    private var latestProgress: AppleMusicRuntimeProgress?

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    var progress: AppleMusicRuntimeProgress? {
        lock.lock()
        defer { lock.unlock() }
        return latestProgress
    }

    func requestCancellation() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    func clearCancellation() {
        lock.lock()
        cancellationRequested = false
        lock.unlock()
    }

    func publish(progress: AppleMusicRuntimeProgress) {
        lock.lock()
        latestProgress = progress
        lock.unlock()
    }
}

private final class RuntimeWorkerXPCServer: NSObject, NSXPCListenerDelegate, AppleMusicRuntimeWorkerXPCProtocol {
    private let listener = NSXPCListener(machServiceName: AppleMusicRuntimeWorkerXPC.machServiceName)
    private let state: RuntimeWorkerState
    private let hasBackgroundActivity: @Sendable () -> Bool
    private let operationHandler: @Sendable (AppleMusicRuntimeWorkerRequest) async -> AppleMusicRuntimeAgentResponseEnvelope
    private let queue = DispatchQueue(label: "com.shengjiacheng.GetOudio.runtime-worker.xpc")
    private let lock = NSLock()
    private var activeTaskID: UUID?
    private var idleTimer: DispatchSourceTimer?

    init(
        state: RuntimeWorkerState,
        hasBackgroundActivity: @escaping @Sendable () -> Bool,
        handle: @escaping @Sendable (AppleMusicRuntimeWorkerRequest) async -> AppleMusicRuntimeAgentResponseEnvelope
    ) {
        self.state = state
        self.hasBackgroundActivity = hasBackgroundActivity
        operationHandler = handle
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        armIdleExit()
        DiagnosticLog.append("[RuntimeWorker] launchd Mach XPC listener started")
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: AppleMusicRuntimeWorkerXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func handle(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        do {
            let request = try JSONDecoder().decode(
                AppleMusicRuntimeWorkerRequest.self,
                from: requestData
            )
            switch request.command {
            case .status, .wrapperStatus, .progress, .snapshot:
                cancelIdleExit()
                Task { [weak self] in
                    guard let self else { return }
                    let response = await operationHandler(request)
                    reply(encode(.init(id: request.id, response: response)))
                    armIdleExit()
                }
            case .cancel:
                state.requestCancellation()
                reply(encode(.init(id: request.id, response: .init(id: request.id))))
            case .install, .uninstall, .download, .initialize, .submitCode, .stopRuntime:
                try submit(request, reply: reply)
            }
        } catch {
            reply(encode(.init(id: decodedRequestID(from: requestData), errorMessage: error.localizedDescription)))
        }
    }

    private func submit(
        _ request: AppleMusicRuntimeWorkerRequest,
        reply: @escaping (Data) -> Void
    ) throws {
        lock.lock()
        guard activeTaskID == nil else {
            lock.unlock()
            throw ProcessRunnerError.processFailed("Apple Music Runtime Worker 正在执行其他任务。")
        }
        activeTaskID = request.id
        lock.unlock()
        cancelIdleExit()
        state.clearCancellation()

        Task.detached { [weak self] in
            guard let self else { return }
            let response = await self.operationHandler(request)
            reply(self.encode(.init(id: request.id, response: response)))
            self.state.clearCancellation()
            self.releaseActiveTask()
            self.armIdleExit()
        }
    }

    private func releaseActiveTask() {
        lock.lock()
        activeTaskID = nil
        lock.unlock()
    }

    private func armIdleExit() {
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.isIdle else {
                self.armIdleExit()
                return
            }
            DiagnosticLog.append("[RuntimeWorker] idle exit")
            Darwin.exit(EXIT_SUCCESS)
        }
        timer.resume()
        idleTimer = timer
    }

    private var isIdle: Bool {
        lock.lock()
        let hasActiveTask = activeTaskID != nil
        lock.unlock()
        return !hasActiveTask && !hasBackgroundActivity()
    }

    private func cancelIdleExit() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func encode(_ response: AppleMusicRuntimeWorkerResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data()
    }

    private func decodedRequestID(from data: Data) -> UUID {
        (try? JSONDecoder().decode(AppleMusicRuntimeWorkerRequest.self, from: data).id) ?? UUID()
    }
}

private final class WrapperLoginState {
    private let lock = NSLock()
    private var value = AppleMusicWrapperLoginSnapshot(
        revision: 0,
        status: .init(phase: .notInitialized, message: "Apple Music 下载功能尚未初始化")
    )

    var snapshot: AppleMusicWrapperLoginSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func publish(_ status: AppleMusicWrapperLoginStatus) {
        lock.lock()
        defer { lock.unlock() }
        guard value.status != status else { return }
        value = AppleMusicWrapperLoginSnapshot(revision: value.revision + 1, status: status)
    }

    func reconcile(runtime: AppleMusicWrapperRuntime) async -> AppleMusicWrapperLoginStatus {
        let observed = await runtime.loginStatus()
        let current = snapshot
        if current.status.phase == .verificationCodeSubmitted,
           observed.phase == .waitingForVerificationCode {
            return current.status
        }
        publish(observed)
        return observed
    }
}
