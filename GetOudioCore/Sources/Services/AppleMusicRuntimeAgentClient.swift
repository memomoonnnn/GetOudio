import Foundation

public struct AppleMusicRuntimeAgentStatusReport: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var rootPath: String
    public var message: String
    public var statuses: [AppleMusicRuntimeComponentStatus]

    public init(isEnabled: Bool, rootPath: String, message: String, statuses: [AppleMusicRuntimeComponentStatus]) {
        self.isEnabled = isEnabled
        self.rootPath = rootPath
        self.message = message
        self.statuses = statuses
    }
}

public enum AppleMusicWrapperLoginPhase: String, Codable, Equatable, Sendable {
    case notInitialized
    case starting
    case waitingForVerificationCode
    case verificationCodeSubmitted
    case authenticating
    case authenticated
    case failed
}

public struct AppleMusicWrapperLoginStatus: Codable, Equatable, Sendable {
    public var phase: AppleMusicWrapperLoginPhase
    public var message: String

    public init(phase: AppleMusicWrapperLoginPhase, message: String) {
        self.phase = phase
        self.message = message
    }

    public var isInProgress: Bool {
        [.starting, .waitingForVerificationCode, .verificationCodeSubmitted, .authenticating].contains(phase)
    }

    public var canSubmitVerificationCode: Bool {
        phase == .waitingForVerificationCode
    }

    public var isAuthenticated: Bool {
        phase == .authenticated
    }
}

public struct AppleMusicWrapperLoginSnapshot: Codable, Equatable, Sendable {
    public var revision: UInt64
    public var status: AppleMusicWrapperLoginStatus

    public init(revision: UInt64, status: AppleMusicWrapperLoginStatus) {
        self.revision = revision
        self.status = status
    }
}

public struct AppleMusicRuntimeProgress: Codable, Equatable, Sendable {
    public var message: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int
    public var isActive: Bool
    public var statuses: [AppleMusicRuntimeComponentStatus]?
    public var notificationVersion: String?

    public init(
        message: String,
        completedUnitCount: Int,
        totalUnitCount: Int,
        isActive: Bool,
        statuses: [AppleMusicRuntimeComponentStatus]? = nil,
        notificationVersion: String? = nil
    ) {
        self.message = message
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.isActive = isActive
        self.statuses = statuses
        self.notificationVersion = notificationVersion
    }

    public var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(1, max(0, Double(completedUnitCount) / Double(totalUnitCount)))
    }
}

public struct AppleMusicRuntimeAgentResponseEnvelope: Codable, Equatable, Sendable {
    public var id: UUID
    public var statusReport: AppleMusicRuntimeAgentStatusReport?
    public var summary: ConversionSummary?
    public var wrapperLoginStatus: AppleMusicWrapperLoginStatus?
    public var wrapperLoginSnapshot: AppleMusicWrapperLoginSnapshot?
    public var progress: AppleMusicRuntimeProgress?
    public var errorMessage: String?

    public init(
        id: UUID,
        statusReport: AppleMusicRuntimeAgentStatusReport? = nil,
        summary: ConversionSummary? = nil,
        wrapperLoginStatus: AppleMusicWrapperLoginStatus? = nil,
        wrapperLoginSnapshot: AppleMusicWrapperLoginSnapshot? = nil,
        progress: AppleMusicRuntimeProgress? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.statusReport = statusReport
        self.summary = summary
        self.wrapperLoginStatus = wrapperLoginStatus
        self.wrapperLoginSnapshot = wrapperLoginSnapshot
        self.progress = progress
        self.errorMessage = errorMessage
    }
}

public struct AppleMusicRuntimeAgentDownloadRequest: Codable, Equatable, Sendable {
    public var jobs: [JobRequest]

    public init(jobs: [JobRequest]) {
        self.jobs = jobs
    }
}

public struct AppleMusicRuntimeAgentInitializeRequest: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public var verificationCode: String?
    public var useSystemProxy: Bool

    public init(username: String, password: String, verificationCode: String?, useSystemProxy: Bool) {
        self.username = username
        self.password = password
        self.verificationCode = verificationCode
        self.useSystemProxy = useSystemProxy
    }
}

public struct AppleMusicRuntimeAgentVerificationRequest: Codable, Equatable, Sendable {
    public var code: String

    public init(code: String) {
        self.code = code
    }
}

public protocol AppleMusicRuntimeServing: AnyObject {
    func status() async throws -> AppleMusicRuntimeAgentStatusReport
    func download(_ jobs: [JobRequest]) async throws -> ConversionSummary
    func progress() async throws -> AppleMusicRuntimeProgress?
    func wrapperLoginStatus() async throws -> AppleMusicWrapperLoginStatus
}

public final class AppleMusicRuntimeWorkerClient: AppleMusicRuntimeServing {
    private let container: AgentDataStore
    private let resourceRoot: URL?
    private let transport: AppleMusicRuntimeWorkerXPCClient

    public init(
        container: AgentDataStore,
        resourceRoot: URL? = Bundle.main.resourceURL
    ) {
        self.container = container
        self.resourceRoot = resourceRoot
        transport = AppleMusicRuntimeWorkerXPCClient()
    }

    public func status() async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: .status)
        let report = try responseStatus(response)
        SettingsStore(container: container).isAppleMusicDownloadEnabled = report.isEnabled
        return report
    }

    public func serviceIdentity() async throws -> BackgroundServiceIdentity {
        let request = AppleMusicRuntimeWorkerRequest(
            id: UUID(),
            command: .healthCheck,
            resourceRootPath: resourceRoot?.path
        )
        let response = try await transport.send(request)
        guard let identity = response.serviceIdentity else {
            throw AppleMusicRuntimeWorkerXPCError.invalidFrame
        }
        return identity
    }

    public func install() async throws -> AppleMusicRuntimeAgentStatusReport {
        try await install(requestID: UUID())
    }

    public func install(requestID: UUID) async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: .install, requestID: requestID)
        let report = try responseStatus(response)
        SettingsStore(container: container).isAppleMusicDownloadEnabled = report.isEnabled
        return report
    }

    public func uninstall() async throws -> AppleMusicRuntimeAgentStatusReport {
        try await uninstall(requestID: UUID())
    }

    public func uninstall(requestID: UUID) async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: .uninstall, requestID: requestID)
        let report = try responseStatus(response)
        SettingsStore(container: container).isAppleMusicDownloadEnabled = report.isEnabled
        return report
    }

    public func download(_ jobs: [JobRequest]) async throws -> ConversionSummary {
        try await download(jobs, requestID: UUID())
    }

    public func download(_ jobs: [JobRequest], requestID: UUID) async throws -> ConversionSummary {
        let response = try await send(
            command: .download,
            requestID: requestID,
            downloadRequest: AppleMusicRuntimeAgentDownloadRequest(jobs: jobs)
        )
        return try responseSummary(response)
    }

    public func initializeWrapper(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool
    ) async throws -> ConversionSummary {
        try await initializeWrapper(
            username: username,
            password: password,
            verificationCode: verificationCode,
            useSystemProxy: useSystemProxy,
            requestID: UUID()
        )
    }

    public func initializeWrapper(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool,
        requestID: UUID
    ) async throws -> ConversionSummary {
        let response = try await send(
            command: .initialize,
            requestID: requestID,
            initializeRequest: AppleMusicRuntimeAgentInitializeRequest(
                username: username,
                password: password,
                verificationCode: verificationCode,
                useSystemProxy: useSystemProxy
            )
        )
        return try responseSummary(response)
    }

    public func submitVerificationCode(_ code: String) async throws -> ConversionSummary {
        try await submitVerificationCode(code, requestID: UUID())
    }

    public func submitVerificationCode(_ code: String, requestID: UUID) async throws -> ConversionSummary {
        let response = try await send(
            command: .submitCode,
            requestID: requestID,
            verificationRequest: AppleMusicRuntimeAgentVerificationRequest(code: code)
        )
        return try responseSummary(response)
    }

    public func wrapperLoginStatus() async throws -> AppleMusicWrapperLoginStatus {
        let response = try await send(command: .wrapperStatus)
        guard let status = response.wrapperLoginStatus else {
            throw ProcessRunnerError.processFailed("Runtime Worker 响应中没有登录状态。")
        }
        return status
    }

    public func progress() async throws -> AppleMusicRuntimeProgress? {
        try await send(command: .progress).progress
    }

    public func wrapperLoginSnapshot() async throws -> AppleMusicWrapperLoginSnapshot? {
        try await send(command: .snapshot).wrapperLoginSnapshot
    }

    public func requestDownloadCancellation() async throws {
        try await requestDownloadCancellation(requestID: UUID())
    }

    public func requestDownloadCancellation(requestID: UUID) async throws {
        let request = AppleMusicRuntimeWorkerRequest(
            id: requestID,
            command: .cancel,
            resourceRootPath: resourceRoot?.path
        )
        _ = try await transport.send(request)
    }

    private func send(
        command: AppleMusicRuntimeWorkerCommand,
        requestID: UUID = UUID(),
        downloadRequest: AppleMusicRuntimeAgentDownloadRequest? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil
    ) async throws -> AppleMusicRuntimeAgentResponseEnvelope {
        let request = AppleMusicRuntimeWorkerRequest(
            id: requestID,
            command: command,
            resourceRootPath: resourceRoot?.path,
            gpacPackageURLOverride: ProcessInfo.processInfo.environment[AppleMusicRuntimeManager.gpacPackageEnvironmentKey],
            downloadRequest: downloadRequest,
            initializeRequest: initializeRequest,
            verificationRequest: verificationRequest,
            executionSettings: executionSettings()
        )
        let response = try await dispatch(request)
        if let errorMessage = response.errorMessage {
            throw ProcessRunnerError.processFailed(errorMessage)
        }
        return response
    }

    private func dispatch(
        _ request: AppleMusicRuntimeWorkerRequest
    ) async throws -> AppleMusicRuntimeAgentResponseEnvelope {
        let accepted = try await transport.send(request)
        guard let response = accepted.response else {
            throw AppleMusicRuntimeWorkerXPCError.invalidFrame
        }
        return response
    }

    private func executionSettings() -> AppleMusicRuntimeExecutionSettings {
        let settings = SettingsStore(container: container)
        return AppleMusicRuntimeExecutionSettings(
            outputDirectoryURL: settings.appleMusicOutputURL,
            defaultFormat: settings.appleMusicDownloadFormat
        )
    }

    private func responseStatus(_ response: AppleMusicRuntimeAgentResponseEnvelope) throws -> AppleMusicRuntimeAgentStatusReport {
        guard let report = response.statusReport else {
            throw ProcessRunnerError.processFailed("Runtime Worker 响应中没有状态信息。")
        }
        return report
    }

    private func responseSummary(_ response: AppleMusicRuntimeAgentResponseEnvelope) throws -> ConversionSummary {
        guard let summary = response.summary else {
            throw ProcessRunnerError.processFailed("Runtime Worker 响应中没有执行摘要。")
        }
        return summary
    }

}

/// The only Apple Music runtime client exposed to App and extension code.
/// Runtime execution remains behind the ordinary Background Agent seam.
public final class AppleMusicRuntimeAgentClient: AppleMusicRuntimeServing {
    private let agent: BackgroundAgentClient

    public init(
        transport: BackgroundAgentXPCClient = BackgroundAgentXPCClient()
    ) {
        agent = BackgroundAgentClient(transport: transport)
    }

    public func status() async throws -> AppleMusicRuntimeAgentStatusReport {
        try await response(for: .appleMusicStatus).statusReport.required("后台 Agent 响应中没有状态信息。")
    }

    public func install() async throws -> AppleMusicRuntimeAgentStatusReport {
        try await response(for: .appleMusicInstall).statusReport.required("后台 Agent 响应中没有状态信息。")
    }

    public func uninstall() async throws -> AppleMusicRuntimeAgentStatusReport {
        try await response(for: .appleMusicUninstall).statusReport.required("后台 Agent 响应中没有状态信息。")
    }

    public func download(_ jobs: [JobRequest]) async throws -> ConversionSummary {
        try await response(for: .appleMusicDownload, jobs: jobs).summary.required("后台 Agent 响应中没有执行摘要。")
    }

    public func initializeWrapper(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool
    ) async throws -> ConversionSummary {
        try await response(
            for: .appleMusicInitialize,
            initializeRequest: .init(
                username: username,
                password: password,
                verificationCode: verificationCode,
                useSystemProxy: useSystemProxy
            )
        ).summary.required("后台 Agent 响应中没有执行摘要。")
    }

    public func submitVerificationCode(_ code: String) async throws -> ConversionSummary {
        try await response(
            for: .appleMusicSubmitCode,
            verificationRequest: .init(code: code)
        ).summary.required("后台 Agent 响应中没有执行摘要。")
    }

    public func wrapperLoginStatus() async throws -> AppleMusicWrapperLoginStatus {
        try await response(for: .appleMusicWrapperStatus).wrapperLoginStatus.required("后台 Agent 响应中没有登录状态。")
    }

    public func progress() async throws -> AppleMusicRuntimeProgress? {
        try await agent.performAppleMusic(.appleMusicProgress).appleMusicProgress
    }

    public func wrapperLoginSnapshot() async throws -> AppleMusicWrapperLoginSnapshot? {
        try await agent.performAppleMusic(.appleMusicSnapshot).appleMusicLoginSnapshot
    }

    public func requestDownloadCancellation() async throws {
        _ = try await agent.performAppleMusic(.appleMusicCancel)
    }

    public func events() -> AsyncStream<AppleMusicRuntimeAgentEvent> {
        BackgroundAgentAppleMusicEventStream.make()
    }

    private func response(
        for command: BackgroundAgentCommand,
        jobs: [JobRequest]? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil
    ) async throws -> AppleMusicRuntimeAgentResponseEnvelope {
        let response = try await agent.performAppleMusic(
            command,
            jobs: jobs,
            initializeRequest: initializeRequest,
            verificationRequest: verificationRequest
        )
        guard let value = response.appleMusicResponse else {
            throw BackgroundAgentXPCError.invalidResponse
        }
        if let message = value.errorMessage {
            throw BackgroundAgentXPCError.remote(message)
        }
        return value
    }
}

private final class BackgroundAgentAppleMusicEventSink: NSObject, BackgroundAgentEventXPCProtocol {
    let receive: (Data) -> Void

    init(receive: @escaping (Data) -> Void) {
        self.receive = receive
    }

    func handleEvent(_ eventData: Data) {
        receive(eventData)
    }
}

private final class BackgroundAgentAppleMusicEventLifetime: @unchecked Sendable {
    let connection: NSXPCConnection
    let sink: BackgroundAgentAppleMusicEventSink

    init(connection: NSXPCConnection, sink: BackgroundAgentAppleMusicEventSink) {
        self.connection = connection
        self.sink = sink
    }
}

private enum BackgroundAgentAppleMusicEventStream {
    static func make() -> AsyncStream<AppleMusicRuntimeAgentEvent> {
        AsyncStream { continuation in
            let connection = NSXPCConnection(
                machServiceName: BackgroundAgentXPC.machServiceName,
                options: []
            )
            let sink = BackgroundAgentAppleMusicEventSink { data in
                guard let event = try? JSONDecoder().decode(
                    AppleMusicRuntimeAgentEvent.self,
                    from: data
                ) else { return }
                continuation.yield(event)
            }
            let lifetime = BackgroundAgentAppleMusicEventLifetime(
                connection: connection,
                sink: sink
            )
            connection.remoteObjectInterface = NSXPCInterface(with: BackgroundAgentXPCProtocol.self)
            connection.exportedInterface = NSXPCInterface(with: BackgroundAgentEventXPCProtocol.self)
            connection.exportedObject = sink
            connection.invalidationHandler = { continuation.finish() }
            connection.interruptionHandler = { continuation.finish() }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                continuation.finish()
                lifetime.connection.invalidate()
            }) as? BackgroundAgentXPCProtocol,
            let requestData = try? JSONEncoder().encode(
                BackgroundAgentCommandRequest(command: .subscribeAppleMusicEvents)
            ) else {
                continuation.finish()
                connection.invalidate()
                return
            }
            proxy.handle(requestData) { responseData in
                guard let response = try? JSONDecoder().decode(
                    BackgroundAgentCommandResponse.self,
                    from: responseData
                ), let event = response.appleMusicEvent else { return }
                continuation.yield(event)
            }
            continuation.onTermination = { _ in
                _ = lifetime.sink
                lifetime.connection.invalidate()
            }
        }
    }
}

private extension Optional {
    func required(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw ProcessRunnerError.processFailed(message)
        }
        return value
    }
}
