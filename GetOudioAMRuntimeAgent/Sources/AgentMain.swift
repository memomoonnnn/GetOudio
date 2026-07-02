import Foundation
import GetOudioCore
import Darwin

@main
enum GetOudioAMRuntimeAgent {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty {
                try await runDaemon()
                return
            }

            let options = ParsedArguments(arguments)
            guard let command = options.command else {
                throw ProcessRunnerError.processFailed("缺少 Apple Music Runtime Agent 命令。")
            }

            let resourceRoot = options.value(for: "--resource-root").map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(resourceRoot: resourceRoot)

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
                    settingsStore: SettingsStore(),
                    useAgent: false
                )
                let summary = await service.download(request.jobs)
                persistShareDownloadNotificationIfNeeded(summary: summary, jobs: request.jobs)
                try write(summary)
            case "initialize":
                let request: AppleMusicRuntimeAgentInitializeRequest = try readRequest(options)
                let service = AppleMusicDownloadService(
                    componentManager: BundledComponentManager(resourceRoot: resourceRoot),
                    runtimeManager: manager,
                    settingsStore: SettingsStore(),
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
                    settingsStore: SettingsStore(),
                    useAgent: false
                )
                try write(await service.submitWrapperVerificationCode(request.code))
            case "wrapper-status":
                try write(await wrapperRuntime(manager: manager).loginStatus())
            default:
                throw ProcessRunnerError.processFailed("未知 Apple Music Runtime Agent 命令：\(command)")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Darwin.exit(1)
        }
    }

    private static func runDaemon() async throws {
        DiagnosticLog.append(
            "[Agent] started pid=\(ProcessInfo.processInfo.processIdentifier) "
                + "bundle=\(Bundle.main.bundleURL.path) "
                + "executable=\(URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path) "
                + "diagnostics=wrapper-login-state-v16"
        )
        while true {
            do {
                try await processPendingRequests()
            } catch {
                DiagnosticLog.append("[Agent] request loop failed: \(error.localizedDescription)")
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private static func processPendingRequests() async throws {
        let directory = try AppleMusicRuntimeAgentClient.requestDirectory()
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
            let response = await handle(request)
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response.json")
            try JSONEncoder().encode(response).write(to: responseURL, options: .atomic)
            try? FileManager.default.removeItem(at: requestURL)
        }
    }

    private static func handle(_ request: AppleMusicRuntimeAgentRequestEnvelope) async -> AppleMusicRuntimeAgentResponseEnvelope {
        do {
            let resourceRoot = request.resourceRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manager = AppleMusicRuntimeManager(
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
                let summary = await worker(resourceRoot: resourceRoot, manager: manager).download(downloadRequest.jobs)
                persistShareDownloadNotificationIfNeeded(summary: summary, jobs: downloadRequest.jobs)
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    summary: summary
                )
            case "initialize":
                guard let initializeRequest = request.initializeRequest else {
                    throw ProcessRunnerError.processFailed("initialize 请求缺少凭据。")
                }
                let summary = await worker(resourceRoot: resourceRoot, manager: manager).initializeWrapper(
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
                let summary = await worker(resourceRoot: resourceRoot, manager: manager).submitWrapperVerificationCode(verificationRequest.code)
                return AppleMusicRuntimeAgentResponseEnvelope(id: request.id, summary: summary)
            case "wrapper-status":
                return AppleMusicRuntimeAgentResponseEnvelope(
                    id: request.id,
                    wrapperLoginStatus: await wrapperRuntime(manager: manager).loginStatus()
                )
            default:
                throw ProcessRunnerError.processFailed("未知 Apple Music Runtime Agent 命令：\(request.command)")
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
            ? "Apple Music 运行时已就绪，位置：\(manager.rootURL.path)"
            : "\(missingCount) 个 Apple Music 运行时组件未就绪"

        return AppleMusicRuntimeAgentStatusReport(
            isEnabled: manager.isEnabled,
            rootPath: manager.rootURL.path,
            message: message,
            statuses: statuses
        )
    }

    private static func worker(resourceRoot: URL?, manager: AppleMusicRuntimeManager) -> AppleMusicDownloadService {
        AppleMusicDownloadService(
            componentManager: BundledComponentManager(resourceRoot: resourceRoot),
            runtimeManager: manager,
            settingsStore: SettingsStore(),
            useAgent: false
        )
    }

    private static func wrapperRuntime(manager: AppleMusicRuntimeManager) -> AppleMusicWrapperRuntime {
        AppleMusicWrapperRuntime(
            runtimeManager: manager,
            settingsStore: SettingsStore()
        )
    }

    private static func persistShareDownloadNotificationIfNeeded(summary: ConversionSummary, jobs: [JobRequest]) {
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
            try NotificationEventQueue().enqueueConversionFinished(summary: summary, jobs: jobs)
            wakeMainAppForNotificationDispatch()
        } catch {
            DiagnosticLog.append("[Agent] notification event enqueue failed: \(error.localizedDescription)")
        }
    }

    private static func wakeMainAppForNotificationDispatch() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
            DiagnosticLog.append("[Agent] notification dispatch marker unavailable")
            return
        }
        defaults.set(LaunchSource.notificationDispatch.rawValue, forKey: AppConstants.extensionLaunchSourceKey)
        defaults.set(Date().timeIntervalSince1970, forKey: AppConstants.extensionLaunchTimestampKey)
        defaults.synchronize()

        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
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
