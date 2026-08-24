import Darwin
import Foundation
import GetOudioCore

/// An on-demand, non-sandboxed helper for the managed Apple Music toolchain.
/// It has no daemon mode and never communicates through App Group storage.
@main
enum GetOudioAMRuntimeWorker {
    static func main() async {
        do {
            let arguments = CommandLine.arguments.dropFirst().filter {
                !$0.hasPrefix("-psn_")
            }
            if arguments.isEmpty {
                try await processRequestsUntilIdle()
                return
            }
            guard arguments.count == 2, arguments[0] == "--request" else {
                throw ProcessRunnerError.processFailed("缺少 Apple Music Runtime Helper 请求。")
            }
            let requestURL = URL(fileURLWithPath: arguments[1])
            let request = try JSONDecoder().decode(
                AppleMusicRuntimeAgentRequestEnvelope.self,
                from: Data(contentsOf: requestURL)
            )
            let response = await handle(request)
            try write(response)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    /// Launch Services starts this app outside its caller's sandbox. It serves
    /// queued requests briefly, then exits instead of remaining a background
    /// service. A move claim prevents concurrent launches from running one job
    /// twice.
    private static func processRequestsUntilIdle() async throws {
        let store = try runtimeStore()
        DiagnosticLog.configure(store: store)
        let directory = store.url(for: .appleMusicRuntimeIPC)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var idlePolls = 0

        while idlePolls < 120 {
            let requestURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.lastPathComponent.hasSuffix(".runtime-request.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard let requestURL = requestURLs.first else {
                idlePolls += 1
                try await Task.sleep(nanoseconds: 250_000_000)
                continue
            }

            let claimURL = requestURL.deletingPathExtension().appendingPathExtension("processing")
            do {
                try fileManager.moveItem(at: requestURL, to: claimURL)
            } catch {
                continue
            }

            do {
                let request = try JSONDecoder().decode(
                    AppleMusicRuntimeAgentRequestEnvelope.self,
                    from: Data(contentsOf: claimURL)
                )
                let response = await handle(request)
                let responseURL = directory.appendingPathComponent("\(request.id.uuidString).runtime-response.json")
                try JSONEncoder().encode(response).write(to: responseURL, options: .atomic)
                idlePolls = 0
            } catch {
                DiagnosticLog.append("[RuntimeWorker] queued request failed: \(error.localizedDescription)")
            }
            try? fileManager.removeItem(at: claimURL)
        }
    }

    private static func handle(
        _ request: AppleMusicRuntimeAgentRequestEnvelope
    ) async -> AppleMusicRuntimeAgentResponseEnvelope {
        do {
            let store = try runtimeStore()
            DiagnosticLog.configure(store: store)
            let resourceRoot = request.resourceRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(
                container: store,
                resourceRoot: resourceRoot,
                gpacPackageURLOverride: request.gpacPackageURLOverride
            )
            let loginState = WrapperLoginState(container: store)

            switch request.command {
            case "status":
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case "install":
                _ = try await manager.installManagedRuntime()
                try await wrapperRuntime(manager: manager, store: store)
                    .finalizeManagedImageUpdate(resetAuthentication: true)
                loginState.publish(.init(phase: .notInitialized, message: "Apple Music 下载功能尚未初始化"))
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case "uninstall":
                try await manager.uninstallManagedRuntime()
                loginState.publish(.init(phase: .notInitialized, message: "Apple Music 下载功能尚未启用"))
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    statusReport: await statusReport(manager: manager)
                )
            case "download":
                guard let downloadRequest = request.downloadRequest else {
                    throw ProcessRunnerError.processFailed("download 请求缺少任务。")
                }
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, store: store)
                    .download(downloadRequest.jobs)
                persistShareDownloadNotificationIfNeeded(summary: summary, jobs: downloadRequest.jobs, store: store)
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "initialize":
                let initializeRequest: AppleMusicRuntimeAgentInitializeRequest = try credential(
                    for: request,
                    as: AppleMusicRuntimeAgentInitializeRequest.self,
                    message: "initialize 请求缺少凭据。"
                )
                loginState.publish(.init(phase: .starting, message: "正在启动登录容器"))
                let wrapper = wrapperRuntime(manager: manager, store: store)
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, store: store, wrapperRuntime: wrapper)
                    .initializeWrapper(
                        username: initializeRequest.username,
                        password: initializeRequest.password,
                        verificationCode: initializeRequest.verificationCode,
                        useSystemProxy: initializeRequest.useSystemProxy
                    )
                if summary.failureCount == 0 {
                    _ = await loginState.reconcile(runtime: wrapper)
                } else {
                    loginState.publish(.init(phase: .failed, message: "登录容器启动失败，可以重新初始化"))
                }
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "submit-code":
                let verificationRequest: AppleMusicRuntimeAgentVerificationRequest = try credential(
                    for: request,
                    as: AppleMusicRuntimeAgentVerificationRequest.self,
                    message: "submit-code 请求缺少验证码。"
                )
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, store: store)
                    .submitWrapperVerificationCode(verificationRequest.code)
                if summary.failureCount == 0 {
                    loginState.publish(.init(phase: .verificationCodeSubmitted, message: "验证码已写入，等待 wrapper 读取"))
                }
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "wrapper-status":
                let status = await loginState.reconcile(runtime: wrapperRuntime(manager: manager, store: store))
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, wrapperLoginStatus: status)
            case "stop-runtime":
                await ColimaDockerRuntime(runtimeManager: manager).stopIfRunning()
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id)
            default:
                throw ProcessRunnerError.processFailed("未知 Apple Music Runtime Helper 命令：\(request.command)")
            }
        } catch {
            return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, errorMessage: error.localizedDescription)
        }
    }

    private static func runtimeStore() throws -> AgentDataStore {
        try AgentDataStore.production()
    }

    private static func credential<T: Decodable>(
        for request: AppleMusicRuntimeAgentRequestEnvelope,
        as type: T.Type,
        message: String
    ) throws -> T {
        guard let pipePath = request.credentialPipePath else {
            throw ProcessRunnerError.processFailed(message)
        }
        let data = try AppleMusicRuntimeCredentialProvider.fetch(pipePath: pipePath)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func statusReport(manager: AppleMusicRuntimeManager) async -> AppleMusicRuntimeAgentStatusReport {
        let runtime = ColimaDockerRuntime(runtimeManager: manager)
        let images = DockerImageManager(runtime: runtime)
        let target = await images.check(.appleMusicWrapper, assumeAvailableWhenRuntimeStopped: manager.isEnabled)
        let legacy = target.isAvailable ? nil : await images.checkLegacyImage(for: .appleMusicWrapper)
        let statuses = manager.componentStatuses(wrapperStatus: legacy ?? target)
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
        store: AgentDataStore,
        wrapperRuntime: AppleMusicWrapperRuntime? = nil
    ) -> AppleMusicDownloadService {
        AppleMusicDownloadService(
            componentManager: BundledComponentManager(resourceRoot: resourceRoot),
            runtimeManager: manager,
            wrapperRuntime: wrapperRuntime,
            settingsStore: SettingsStore(container: store),
            agentClient: AppleMusicRuntimeAgentClient(container: store),
            useAgent: false
        )
    }

    private static func wrapperRuntime(manager: AppleMusicRuntimeManager, store: AgentDataStore) -> AppleMusicWrapperRuntime {
        AppleMusicWrapperRuntime(runtimeManager: manager, settingsStore: SettingsStore(container: store))
    }

    private static func persistShareDownloadNotificationIfNeeded(
        summary: ConversionSummary,
        jobs: [JobRequest],
        store: AgentDataStore
    ) {
        guard jobs.contains(where: { $0.source == .shareExtension }) else { return }
        do {
            try NotificationEventQueue(container: store).enqueueConversionFinished(summary: summary, jobs: jobs)
            NotificationDispatchWaker.wake(container: store)
        } catch {
            DiagnosticLog.append("[RuntimeWorker] notification enqueue failed: \(error.localizedDescription)")
        }
    }

    private static func write<T: Encodable>(_ value: T) throws {
        FileHandle.standardOutput.write(try JSONEncoder().encode(value))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private final class WrapperLoginState {
    private let snapshotStore: AppleMusicWrapperLoginSnapshotStore

    init(container: AgentDataStore) {
        snapshotStore = AppleMusicWrapperLoginSnapshotStore(container: container)
    }

    func publish(_ status: AppleMusicWrapperLoginStatus) {
        do {
            _ = try snapshotStore.saveIfChanged(status)
        } catch {
            DiagnosticLog.append("[RuntimeWorker] login snapshot write failed: \(error.localizedDescription)")
        }
    }

    func reconcile(runtime: AppleMusicWrapperRuntime) async -> AppleMusicWrapperLoginStatus {
        let observed = await runtime.loginStatus()
        if let snapshot = snapshotStore.snapshot(),
           snapshot.status.phase == .verificationCodeSubmitted,
           observed.phase == .waitingForVerificationCode {
            return snapshot.status
        }
        publish(observed)
        return observed
    }
}
