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
        [.starting, .waitingForVerificationCode, .authenticating].contains(phase)
    }

    public var canSubmitVerificationCode: Bool {
        phase == .waitingForVerificationCode
    }

    public var isAuthenticated: Bool {
        phase == .authenticated
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

    public init(
        id: UUID,
        command: String,
        resourceRootPath: String?,
        gpacPackageURLOverride: String? = nil,
        downloadRequest: AppleMusicRuntimeAgentDownloadRequest? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil
    ) {
        self.id = id
        self.command = command
        self.resourceRootPath = resourceRootPath
        self.gpacPackageURLOverride = gpacPackageURLOverride
        self.downloadRequest = downloadRequest
        self.initializeRequest = initializeRequest
        self.verificationRequest = verificationRequest
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
    public static let executableName = "GetOudioAMRuntimeAgent"
    public static let applicationBundleName = "GetOudioAMRuntimeAgent.app"
    public static let executablePathEnvironmentKey = "GET_OUDIO_AM_RUNTIME_AGENT"

    private let resourceRoot: URL?
    private let ipcDirectory: URL
    private let fileManager: FileManager
    private let timeout: TimeInterval

    public init(
        container: SharedContainer,
        resourceRoot: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default,
        timeout: TimeInterval = 3_600
    ) {
        self.ipcDirectory = container.url(for: .appleMusicRuntimeIPC)
        self.resourceRoot = resourceRoot
        self.fileManager = fileManager
        self.timeout = timeout
    }

    public var isAvailable: Bool {
        true
    }

    public static func defaultApplicationURL(bundle: Bundle = .main) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment[executablePathEnvironmentKey], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "app" {
                return url
            }
            if url.lastPathComponent == executableName,
               url.deletingLastPathComponent().lastPathComponent == "MacOS",
               url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents" {
                return url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            }
            return nil
        }

        let bundleURL = bundle.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Library/LoginItems/\(applicationBundleName)"),
            bundleURL.appendingPathComponent("Contents/Helpers/\(applicationBundleName)"),
            bundle.resourceURL?.deletingLastPathComponent().appendingPathComponent("Library/LoginItems/\(applicationBundleName)"),
            bundle.resourceURL?.deletingLastPathComponent().appendingPathComponent("Helpers/\(applicationBundleName)")
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.first
    }

    public static func defaultExecutableURL(bundle: Bundle = .main) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment[executablePathEnvironmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        if let appURL = defaultApplicationURL(bundle: bundle) {
            return appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        }

        let bundleURL = bundle.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Helpers/\(executableName)"),
            bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)"),
            bundle.resourceURL?.deletingLastPathComponent().appendingPathComponent("Helpers/\(executableName)"),
            bundle.resourceURL?.appendingPathComponent(executableName)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.first
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
        let directory = try requestDirectory()
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
        let requestURL = directory.appendingPathComponent("\(id.uuidString).request.json")
        let responseURL = directory.appendingPathComponent("\(id.uuidString).response.json")
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        defer {
            try? fileManager.removeItem(at: requestURL)
            try? fileManager.removeItem(at: responseURL)
        }

        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if fileManager.fileExists(atPath: responseURL.path) {
                let data = try Data(contentsOf: responseURL)
                let response = try JSONDecoder().decode(AppleMusicRuntimeAgentResponseEnvelope.self, from: data)
                if let errorMessage = response.errorMessage {
                    throw ProcessRunnerError.processFailed(errorMessage)
                }
                return response
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw ProcessRunnerError.processFailed("Downloader Runtime Agent 没有在限定时间内返回响应。")
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

    public func requestDirectory() throws -> URL {
        let directory = ipcDirectory.appendingPathComponent("requests", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func progressURL() -> URL {
        ipcDirectory.appendingPathComponent("progress.json")
    }

    public func downloadCancellationURL() -> URL {
        ipcDirectory.appendingPathComponent("download-cancel.flag")
    }
}
