import Foundation
import GetOudioCore
import Darwin

@main
enum GetOudioAMRuntimeAgent {
    static func main() async {
        do {
            let container = try SharedContainer.forCurrentProcess()
            DiagnosticLog.configure(container: container)
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty {
                try await runDaemon(container: container)
                return
            }

            let options = ParsedArguments(arguments)
            guard let command = options.command else {
                throw ProcessRunnerError.processFailed("缺少 Downloader Runtime Agent 命令。")
            }

            let resourceRoot = options.value(for: "--resource-root").map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(container: container, resourceRoot: resourceRoot)

            switch command {
            case "status":
                try await writeStatus(manager: manager)
            case "install":
                _ = try await manager.installManagedRuntime()
                try await writeStatus(manager: manager)
            case "uninstall":
                try await manager.uninstallManagedRuntime()
                try await writeStatus(manager: manager)
            case "download":
                let request: AppleMusicRuntimeAgentDownloadRequest = try readRequest(options)
                let service = AppleMusicDownloadService(
                    componentManager: BundledComponentManager(resourceRoot: resourceRoot),
                    runtimeManager: manager,
                    settingsStore: SettingsStore(container: container),
                    agentClient: AppleMusicRuntimeAgentClient(container: container),
                    useAgent: false
                )
                let summary = await service.download(request.jobs)
                persistShareDownloadNotificationIfNeeded(summary: summary, jobs: request.jobs, container: container)
                try write(summary)
            case "initialize":
                let request: AppleMusicRuntimeAgentInitializeRequest = try readRequest(options)
                let service = AppleMusicDownloadService(
                    componentManager: BundledComponentManager(resourceRoot: resourceRoot),
                    runtimeManager: manager,
                    settingsStore: SettingsStore(container: container),
                    agentClient: AppleMusicRuntimeAgentClient(container: container),
                    useAgent: false
                )
                try write(await service.initializeWrapper(
                    username: request.username,
                    password: request.password,
                    verificationCode: request.verificationCode,
                    useSystemProxy: request.useSystemProxy
                ))
            case "submit-code":
                let request: AppleMusicRuntimeAgentVerificationRequest = try readRequest(options)
                let service = AppleMusicDownloadService(
                    componentManager: BundledComponentManager(resourceRoot: resourceRoot),
                    runtimeManager: manager,
                    settingsStore: SettingsStore(container: container),
                    agentClient: AppleMusicRuntimeAgentClient(container: container),
                    useAgent: false
                )
                try write(await service.submitWrapperVerificationCode(request.code))
            case "wrapper-status":
                try write(await wrapperRuntime(manager: manager, container: container).loginStatus())
            default:
                throw ProcessRunnerError.processFailed("未知 Downloader Runtime Agent 命令：\(command)")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Darwin.exit(1)
        }
    }

    private static func runDaemon(container: SharedContainer) async throws {
        let client = AppleMusicRuntimeAgentClient(container: container)
        DiagnosticLog.append(
            "[Agent] started pid=\(ProcessInfo.processInfo.processIdentifier) "
                + "bundle=\(Bundle.main.bundleURL.path) "
                + "executable=\(URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path) "
                + "diagnostics=wrapper-login-state-v16"
        )
        while true {
            do {
                try await processPendingRequests(container: container, client: client)
            } catch {
                DiagnosticLog.append("[Agent] request loop failed: \(error.localizedDescription)")
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private static func processPendingRequests(
        container: SharedContainer,
        client: AppleMusicRuntimeAgentClient
    ) async throws {
        let directory = try client.requestDirectory()
        let requestURLs = (try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))
        .filter { $0.lastPathComponent.hasSuffix(".request.json") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for requestURL in requestURLs {
            let data = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(AppleMusicRuntimeAgentRequestEnvelope.self, from: data)
            let response = await handle(request, container: container)
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response.json")
            try JSONEncoder().encode(response).write(to: responseURL, options: .atomic)
            try? FileManager.default.removeItem(at: requestURL)
        }
    }

    private static func handle(
        _ request: AppleMusicRuntimeAgentRequestEnvelope,
        container: SharedContainer
    ) async -> AppleMusicRuntimeAgentResponseEnvelope {
        do {
            let resourceRoot = request.resourceRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(
                container: container,
                resourceRoot: resourceRoot,
                gpacPackageURLOverride: request.gpacPackageURLOverride
            )

            switch request.command {
            case "status":
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, statusReport: try await statusReport(manager: manager))
            case "install":
                _ = try await manager.installManagedRuntime()
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, statusReport: try await statusReport(manager: manager))
            case "uninstall":
                try await manager.uninstallManagedRuntime()
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, statusReport: try await statusReport(manager: manager))
            case "download":
                guard let downloadRequest = request.downloadRequest else {
                    throw ProcessRunnerError.processFailed("download 请求缺少任务。")
                }
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, container: container).download(downloadRequest.jobs)
                persistShareDownloadNotificationIfNeeded(summary: summary, jobs: downloadRequest.jobs, container: container)
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    summary: summary
                )
            case "initialize":
                guard let initializeRequest = request.initializeRequest else {
                    throw ProcessRunnerError.processFailed("initialize 请求缺少凭据。")
                }
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, container: container).initializeWrapper(
                    username: initializeRequest.username,
                    password: initializeRequest.password,
                    verificationCode: initializeRequest.verificationCode,
                    useSystemProxy: initializeRequest.useSystemProxy
                )
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "submit-code":
                guard let verificationRequest = request.verificationRequest else {
                    throw ProcessRunnerError.processFailed("submit-code 请求缺少验证码。")
                }
                let summary = await worker(resourceRoot: resourceRoot, manager: manager, container: container).submitWrapperVerificationCode(verificationRequest.code)
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "wrapper-status":
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    wrapperLoginStatus: await wrapperRuntime(manager: manager, container: container).loginStatus()
                )
            default:
                throw ProcessRunnerError.processFailed("未知 Downloader Runtime Agent 命令：\(request.command)")
            }
        } catch {
            return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, errorMessage: error.localizedDescription)
        }
    }

    private static func writeStatus(manager: AppleMusicRuntimeManager) async throws {
        try write(await statusReport(manager: manager))
    }

    private static func statusReport(manager: AppleMusicRuntimeManager) async throws -> AppleMusicRuntimeAgentStatusReport {
        let runtime = ColimaDockerRuntime(runtimeManager: manager)
        let imageStatus = await DockerImageManager(runtime: runtime).check(
            .appleMusicWrapper,
            assumeAvailableWhenRuntimeStopped: manager.isEnabled
        )
        let statuses = manager.componentStatuses(wrapperStatus: imageStatus)
        let missingCount = statuses.filter { !$0.isReady }.count
        let message = missingCount == 0 && manager.isEnabled
            ? "Downloader Runtime 已就绪，位置：\(manager.rootURL.path)"
            : "\(missingCount) 个 Downloader Runtime 组件未就绪"

        return AppleMusicRuntimeAgentStatusReport(
            isEnabled: manager.isEnabled,
            rootPath: manager.rootURL.path,
            message: message,
            statuses: statuses
        )
    }

    private static func worker(
        resourceRoot: URL?,
        manager: AppleMusicRuntimeManager,
        container: SharedContainer
    ) -> AppleMusicDownloadService {
        AppleMusicDownloadService(
            componentManager: BundledComponentManager(resourceRoot: resourceRoot),
            runtimeManager: manager,
            settingsStore: SettingsStore(container: container),
            agentClient: AppleMusicRuntimeAgentClient(container: container),
            useAgent: false
        )
    }

    private static func wrapperRuntime(
        manager: AppleMusicRuntimeManager,
        container: SharedContainer
    ) -> AppleMusicWrapperRuntime {
        AppleMusicWrapperRuntime(
            runtimeManager: manager,
            settingsStore: SettingsStore(container: container)
        )
    }

    private static func persistShareDownloadNotificationIfNeeded(
        summary: ConversionSummary,
        jobs: [JobRequest],
        container: SharedContainer
    ) {
        guard jobs.contains(where: { job in
            guard job.source == .shareExtension else {
                return false
            }
            if case .appleMusicDownload = job.operation {
                return true
            }
            return false
        }) else {
            return
        }

        do {
            try NotificationEventQueue(container: container).enqueueConversionFinished(summary: summary, jobs: jobs)
            wakeMainAppForNotificationDispatch(container: container)
        } catch {
            DiagnosticLog.append("[Agent] notification event enqueue failed: \(error.localizedDescription)")
        }
    }

    private static func wakeMainAppForNotificationDispatch(container: SharedContainer) {
        LaunchMarkerStore(container: container).mark(.notificationDispatch)

        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments: [String] = []
#if DEBUG
        if container.accessMode == .diagnostic {
            arguments.append(contentsOf: [
                "--env",
                "\(SharedContainer.diagnosticRootEnvironmentKey)=\(container.directoryURL.path)"
            ])
        }
#endif
        arguments.append(url.absoluteString)
        process.arguments = arguments
        do {
            try process.run()
            DiagnosticLog.append("[Agent] notification dispatch wake requested")
        } catch {
            DiagnosticLog.append("[Agent] notification dispatch wake failed: \(error.localizedDescription)")
        }
    }

    private static func readRequest<T: Decodable>(_ options: ParsedArguments) throws -> T {
        guard let path = options.value(for: "--request") else {
            throw ProcessRunnerError.processFailed("缺少 --request JSON 文件。")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private struct ParsedArguments {
    let command: String?
    private let values: [String: String]

    init(_ arguments: [String]) {
        command = arguments.first
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            if key.hasPrefix("--"), index + 1 < arguments.count {
                values[key] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        self.values = values
    }

    func value(for key: String) -> String? {
        values[key]
    }
}
