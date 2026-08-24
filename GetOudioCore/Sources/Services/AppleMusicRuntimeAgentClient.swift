import Foundation
import Darwin

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

public final class AppleMusicWrapperLoginSnapshotStore {
    private let snapshotURL: URL
    private let fileManager: FileManager

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) {
        snapshotURL = rootURL.appendingPathComponent("wrapper-login-status.json")
        self.fileManager = fileManager
    }

    public convenience init(
        container: AgentDataStore,
        fileManager: FileManager = .default
    ) {
        self.init(rootURL: container.url(for: .appleMusicRuntimeIPC), fileManager: fileManager)
    }

    public func snapshot() -> AppleMusicWrapperLoginSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(AppleMusicWrapperLoginSnapshot.self, from: data)
    }

    @discardableResult
    public func saveIfChanged(_ status: AppleMusicWrapperLoginStatus) throws -> AppleMusicWrapperLoginSnapshot {
        let current = snapshot()
        if let current, current.status == status {
            return current
        }
        let snapshot = AppleMusicWrapperLoginSnapshot(
            revision: (current?.revision ?? 0) + 1,
            status: status
        )
        try fileManager.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
        return snapshot
    }

    public func remove() throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        try fileManager.removeItem(at: snapshotURL)
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

public struct AppleMusicRuntimeAgentRequestEnvelope: Codable, Equatable, Sendable {
    public var id: UUID
    public var command: String
    public var resourceRootPath: String?
    public var gpacPackageURLOverride: String?
    public var downloadRequest: AppleMusicRuntimeAgentDownloadRequest?
    public var initializeRequest: AppleMusicRuntimeAgentInitializeRequest?
    public var verificationRequest: AppleMusicRuntimeAgentVerificationRequest?
    /// 一次性命名管道的路径；请求文件中不包含凭据。
    public var credentialPipePath: String?

    public init(
        id: UUID,
        command: String,
        resourceRootPath: String?,
        gpacPackageURLOverride: String? = nil,
        downloadRequest: AppleMusicRuntimeAgentDownloadRequest? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil,
        credentialPipePath: String? = nil
    ) {
        self.id = id
        self.command = command
        self.resourceRootPath = resourceRootPath
        self.gpacPackageURLOverride = gpacPackageURLOverride
        self.downloadRequest = downloadRequest
        self.initializeRequest = initializeRequest
        self.verificationRequest = verificationRequest
        self.credentialPipePath = credentialPipePath
    }

    public func workerRequest(credentialPipePath: String?) -> AppleMusicRuntimeAgentRequestEnvelope {
        var request = self
        request.initializeRequest = nil
        request.verificationRequest = nil
        request.credentialPipePath = credentialPipePath
        return request
    }
}

/// 通过受控目录内的一次性 FIFO 在运行时交付凭据。
/// 请求文件只记录 FIFO 路径；凭据只在内核管道缓冲区中经过，永不写入常规文件。
public final class AppleMusicRuntimeCredentialProvider: @unchecked Sendable {
    private let pipeURL: URL
    private let credentialData: Data
    private let lock = NSLock()
    private var isValid = true

    public init(requestID: UUID, credentialData: Data, directoryURL: URL) throws {
        pipeURL = directoryURL.appendingPathComponent("\(requestID.uuidString).runtime-credential.fifo")
        self.credentialData = credentialData
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        _ = unlink(pipeURL.path)
        guard mkfifo(pipeURL.path, S_IRUSR | S_IWUSR) == 0 else {
            throw Self.error("无法创建凭据通道。")
        }
    }

    deinit { invalidate() }

    public var pipePath: String { pipeURL.path }

    public func invalidate() {
        lock.lock()
        isValid = false
        lock.unlock()
        _ = unlink(pipeURL.path)
    }

    /// 等待 Worker 打开 FIFO 读取端；调用方应放入独立 Task。
    public func serveOnce() throws {
        let descriptor = try openWriter()
        defer { _ = close(descriptor) }
        try Self.writeAll(credentialData, to: descriptor)
    }

    public static func fetch(pipePath: String) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: pipePath) else {
            throw error("Worker 无法读取凭据。")
        }
        defer { try? handle.close() }
        return try handle.readToEnd() ?? Data()
    }

    private func openWriter() throws -> Int32 {
        while true {
            lock.lock()
            let valid = isValid
            lock.unlock()
            guard valid else { throw Self.error("凭据通道已关闭。") }

            let descriptor = open(pipeURL.path, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 { return descriptor }
            guard errno == ENXIO else { throw Self.error("Worker 未连接凭据通道。") }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw error("写入凭据失败。") }
                offset += count
            }
        }
    }

    private static func error(_ message: String) -> Error {
        ProcessRunnerError.processFailed("Apple Music Runtime Helper \(message)")
    }
}

public struct AppleMusicRuntimeAgentResponseEnvelope: Codable, Equatable, Sendable {
    public var id: UUID
    public var statusReport: AppleMusicRuntimeAgentStatusReport?
    public var summary: ConversionSummary?
    public var wrapperLoginStatus: AppleMusicWrapperLoginStatus?
    public var errorMessage: String?

    public init(
        id: UUID,
        statusReport: AppleMusicRuntimeAgentStatusReport? = nil,
        summary: ConversionSummary? = nil,
        wrapperLoginStatus: AppleMusicWrapperLoginStatus? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.statusReport = statusReport
        self.summary = summary
        self.wrapperLoginStatus = wrapperLoginStatus
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

public final class AppleMusicRuntimeAgentClient {
    private let resourceRoot: URL?
    private let ipcDirectory: URL
    private let fileManager: FileManager
    private let runner: ProcessRunner
    private let timeout: TimeInterval
    private let workerApplicationURL: URL?
    private let injectedWorkerExecutableURL: URL?

    public init(
        container: AgentDataStore,
        resourceRoot: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default,
        timeout: TimeInterval = 3_600,
        transport _: BackgroundAgentXPCClient = BackgroundAgentXPCClient(),
        runner: ProcessRunner = ProcessRunner(),
        workerApplicationURL: URL? = nil,
        workerExecutableURL: URL? = nil
    ) {
        self.ipcDirectory = container.url(for: .appleMusicRuntimeIPC)
        self.resourceRoot = resourceRoot
        self.fileManager = fileManager
        self.runner = runner
        self.timeout = timeout
        self.workerApplicationURL = workerApplicationURL
        self.injectedWorkerExecutableURL = workerExecutableURL
    }

    public var isAvailable: Bool {
        injectedWorkerExecutableURL != nil || workerApplicationURL != nil || Self.embeddedWorkerApplicationURL() != nil
    }

    public func status() async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: "status")
        return try responseStatus(response)
    }

    public func install() async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: "install")
        return try responseStatus(response)
    }

    public func uninstall() async throws -> AppleMusicRuntimeAgentStatusReport {
        let response = try await send(command: "uninstall")
        return try responseStatus(response)
    }

    public func download(_ jobs: [JobRequest]) async throws -> ConversionSummary {
        let response = try await send(
            command: "download",
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
        let response = try await send(
            command: "initialize",
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
        let response = try await send(
            command: "submit-code",
            verificationRequest: AppleMusicRuntimeAgentVerificationRequest(code: code)
        )
        return try responseSummary(response)
    }

    public func wrapperLoginStatus() async throws -> AppleMusicWrapperLoginStatus {
        let response = try await send(command: "wrapper-status")
        guard let status = response.wrapperLoginStatus else {
            throw ProcessRunnerError.processFailed("Downloader Runtime Agent 响应中没有登录状态。")
        }
        return status
    }

    public func progress() -> AppleMusicRuntimeProgress? {
        guard let data = try? Data(contentsOf: progressURL()) else { return nil }
        return try? JSONDecoder().decode(AppleMusicRuntimeProgress.self, from: data)
    }

    public func wrapperLoginSnapshot() -> AppleMusicWrapperLoginSnapshot? {
        AppleMusicWrapperLoginSnapshotStore(rootURL: ipcDirectory, fileManager: fileManager).snapshot()
    }

    public func requestDownloadCancellation() throws {
        let url = downloadCancellationURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let message = ISO8601DateFormatter().string(from: Date())
        try Data(message.utf8).write(to: url, options: .atomic)
    }

    public func clearDownloadCancellation() {
        try? fileManager.removeItem(at: downloadCancellationURL())
    }

    public func isDownloadCancellationRequested() -> Bool {
        fileManager.fileExists(atPath: downloadCancellationURL().path)
    }

    private func send(
        command: String,
        downloadRequest: AppleMusicRuntimeAgentDownloadRequest? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil
    ) async throws -> AppleMusicRuntimeAgentResponseEnvelope {
        let id = UUID()
        let request = AppleMusicRuntimeAgentRequestEnvelope(
            id: id,
            command: command,
            resourceRootPath: resourceRoot?.path,
            gpacPackageURLOverride: ProcessInfo.processInfo.environment[AppleMusicRuntimeManager.gpacPackageEnvironmentKey],
            downloadRequest: downloadRequest,
            initializeRequest: initializeRequest,
            verificationRequest: verificationRequest
        )
        let response = try await dispatch(request)
        if let errorMessage = response.errorMessage {
            throw ProcessRunnerError.processFailed(errorMessage)
        }
        if ["install", "download", "initialize", "submit-code"].contains(command) {
            scheduleRuntimeIdleStop()
        }
        return response
    }

    private func dispatch(
        _ request: AppleMusicRuntimeAgentRequestEnvelope
    ) async throws -> AppleMusicRuntimeAgentResponseEnvelope {
        guard let applicationURL = workerApplicationURL ?? Self.embeddedWorkerApplicationURL() else {
            throw ProcessRunnerError.executableNotFound(
                "GetOudioAMRuntimeWorker.app"
            )
        }

        let credentialPayload: Data?
        if let initializeRequest = request.initializeRequest {
            credentialPayload = try JSONEncoder().encode(initializeRequest)
        } else if let verificationRequest = request.verificationRequest {
            credentialPayload = try JSONEncoder().encode(verificationRequest)
        } else {
            credentialPayload = nil
        }
        try fileManager.createDirectory(at: ipcDirectory, withIntermediateDirectories: true)
        let credentialProvider = try credentialPayload.map {
            try AppleMusicRuntimeCredentialProvider(
                requestID: request.id,
                credentialData: $0,
                directoryURL: ipcDirectory
            )
        }
        defer { credentialProvider?.invalidate() }
        let workerRequest = request.workerRequest(credentialPipePath: credentialProvider?.pipePath)

        let requestURL = ipcDirectory.appendingPathComponent("\(request.id.uuidString).runtime-request.json")
        let responseURL = ipcDirectory.appendingPathComponent("\(request.id.uuidString).runtime-response.json")
        try JSONEncoder().encode(workerRequest).write(to: requestURL, options: .atomic)
        defer {
            try? fileManager.removeItem(at: requestURL)
            try? fileManager.removeItem(at: responseURL)
        }

        let launch = try await runner.run(
            executablePath: "/usr/bin/open",
            arguments: ["-g", "-j", applicationURL.path]
        )
        guard launch.succeeded else {
            let detail = launch.standardError.isEmpty ? launch.standardOutput : launch.standardError
            throw ProcessRunnerError.processFailed(
                detail.isEmpty ? "无法通过 Launch Services 启动 Apple Music Runtime Helper。" : detail
            )
        }
        let credentialTask = credentialProvider.map { provider in
            Task.detached { try provider.serveOnce() }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fileManager.fileExists(atPath: responseURL.path) {
                let data = try Data(contentsOf: responseURL)
                let response = try JSONDecoder().decode(AppleMusicRuntimeAgentResponseEnvelope.self, from: data)
                guard response.id == request.id else {
                    throw ProcessRunnerError.processFailed("Apple Music Runtime Helper 响应标识不匹配。")
                }
                // Worker can report a setup error before opening the FIFO.
                // Do not wait for its writer task in that case; `defer` closes
                // the one-time channel and returns the actionable error.
                if response.errorMessage == nil, let credentialTask {
                    try await credentialTask.value
                }
                return response
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ProcessRunnerError.processFailed("Apple Music Runtime Helper 没有在限定时间内返回响应。")
    }

    private func scheduleRuntimeIdleStop() {
        let tokenURL = ipcDirectory.appendingPathComponent("runtime-idle-token")
        let token = UUID().uuidString
        try? fileManager.createDirectory(at: ipcDirectory, withIntermediateDirectories: true)
        try? Data(token.utf8).write(to: tokenURL, options: .atomic)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard let self,
                  (try? String(contentsOf: tokenURL, encoding: .utf8)) == token
            else { return }
            let request = AppleMusicRuntimeAgentRequestEnvelope(
                id: UUID(),
                command: "stop-runtime",
                resourceRootPath: self.resourceRoot?.path
            )
            _ = try? await self.dispatch(request)
        }
    }

    private static func embeddedWorkerApplicationURL() -> URL? {
        var bundleURL = Bundle.main.bundleURL
        let fileManager = FileManager.default
        while bundleURL.path != "/" {
            if bundleURL.pathExtension == "app" {
                let applicationURL = bundleURL
                    .appendingPathComponent("Contents/Helpers/GetOudioAMRuntimeWorker.app", isDirectory: true)
                if fileManager.fileExists(atPath: applicationURL.path) {
                    return applicationURL
                }
            }
            bundleURL.deleteLastPathComponent()
        }
        return nil
    }

    private func responseStatus(_ response: AppleMusicRuntimeAgentResponseEnvelope) throws -> AppleMusicRuntimeAgentStatusReport {
        guard let report = response.statusReport else {
            throw ProcessRunnerError.processFailed("Downloader Runtime Agent 响应中没有状态信息。")
        }
        return report
    }

    private func responseSummary(_ response: AppleMusicRuntimeAgentResponseEnvelope) throws -> ConversionSummary {
        guard let summary = response.summary else {
            throw ProcessRunnerError.processFailed("Downloader Runtime Agent 响应中没有执行摘要。")
        }
        return summary
    }

    public func progressURL() -> URL {
        ipcDirectory.appendingPathComponent("progress.json")
    }

    public func downloadCancellationURL() -> URL {
        ipcDirectory.appendingPathComponent("download-cancel.flag")
    }
}
