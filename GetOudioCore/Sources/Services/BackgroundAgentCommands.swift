import Foundation

public enum BackgroundAgentCommand: String, Codable, Equatable, Sendable {
    case healthCheck
    case finderConfiguration
    case enqueueJobs
    case unsupportedShareURLs
    case recordingSnapshot
    case dispatchNotificationEvents
    case handlePendingAppleMusicDownload
    case appleMusicStatus
    case appleMusicInstall
    case appleMusicUninstall
    case appleMusicDownload
    case appleMusicInitialize
    case appleMusicSubmitCode
    case appleMusicWrapperStatus
    case appleMusicSnapshot
    case appleMusicProgress
    case appleMusicCancel
    case subscribeAppleMusicEvents

    public var requiresRequestDeduplication: Bool {
        switch self {
        case .healthCheck, .finderConfiguration, .recordingSnapshot,
             .appleMusicStatus, .appleMusicWrapperStatus, .appleMusicSnapshot,
             .appleMusicProgress, .subscribeAppleMusicEvents:
            return false
        case .enqueueJobs, .unsupportedShareURLs, .dispatchNotificationEvents,
             .handlePendingAppleMusicDownload, .appleMusicInstall,
             .appleMusicUninstall, .appleMusicDownload, .appleMusicInitialize,
             .appleMusicSubmitCode, .appleMusicCancel:
            return true
        }
    }
}

public struct BackgroundServiceIdentity: Codable, Equatable, Sendable {
    public enum Service: String, Codable, Sendable {
        case backgroundAgent
        case runtimeWorker
    }

    public static let backgroundAgentProtocolVersion = 1
    public static let runtimeWorkerProtocolVersion = 1

    public var service: Service
    public var protocolVersion: Int
    public var marketingVersion: String
    public var buildVersion: String

    public init(
        service: Service,
        protocolVersion: Int,
        marketingVersion: String,
        buildVersion: String
    ) {
        self.service = service
        self.protocolVersion = protocolVersion
        self.marketingVersion = marketingVersion
        self.buildVersion = buildVersion
    }

    public static func current(_ service: Service, bundle: Bundle = .main) -> Self {
        Self(
            service: service,
            protocolVersion: service == .backgroundAgent
                ? backgroundAgentProtocolVersion
                : runtimeWorkerProtocolVersion,
            marketingVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }
}

public struct BackgroundServicesStatus: Equatable, Sendable {
    public var backgroundAgent: BackgroundServiceIdentity?
    public var runtimeWorker: BackgroundServiceIdentity?

    public init(
        backgroundAgent: BackgroundServiceIdentity?,
        runtimeWorker: BackgroundServiceIdentity?
    ) {
        self.backgroundAgent = backgroundAgent
        self.runtimeWorker = runtimeWorker
    }

    public var isCurrent: Bool {
        backgroundAgent == .current(.backgroundAgent)
            && runtimeWorker == .current(.runtimeWorker)
    }
}

public struct BackgroundAgentCommandRequest: Codable, Sendable {
    public var id: UUID
    public var command: BackgroundAgentCommand
    public var jobs: [JobRequest]?
    public var urls: [URL]?
    public var appleMusicInitializeRequest: AppleMusicRuntimeAgentInitializeRequest?
    public var appleMusicVerificationRequest: AppleMusicRuntimeAgentVerificationRequest?
    public var appleMusicDownloadFormat: AppleMusicDownloadFormat?

    public init(
        id: UUID = UUID(),
        command: BackgroundAgentCommand,
        jobs: [JobRequest]? = nil,
        urls: [URL]? = nil,
        appleMusicInitializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        appleMusicVerificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil,
        appleMusicDownloadFormat: AppleMusicDownloadFormat? = nil
    ) {
        self.id = id
        self.command = command
        self.jobs = jobs
        self.urls = urls
        self.appleMusicInitializeRequest = appleMusicInitializeRequest
        self.appleMusicVerificationRequest = appleMusicVerificationRequest
        self.appleMusicDownloadFormat = appleMusicDownloadFormat
    }
}

public struct BackgroundAgentFinderConfiguration: Codable, Sendable {
    public var finderDirectories: [URL]
    public var enabledPresets: [ConversionPreset]

    public init(finderDirectories: [URL], enabledPresets: [ConversionPreset]) {
        self.finderDirectories = finderDirectories
        self.enabledPresets = enabledPresets
    }
}

public struct AppleMusicRuntimeAgentEvent: Codable, Equatable, Sendable {
    public var revision: UInt64
    public var progress: AppleMusicRuntimeProgress?
    public var loginSnapshot: AppleMusicWrapperLoginSnapshot?

    public init(
        revision: UInt64,
        progress: AppleMusicRuntimeProgress?,
        loginSnapshot: AppleMusicWrapperLoginSnapshot?
    ) {
        self.revision = revision
        self.progress = progress
        self.loginSnapshot = loginSnapshot
    }
}

@objc public protocol BackgroundAgentEventXPCProtocol {
    func handleEvent(_ eventData: Data)
}

public struct BackgroundAgentCommandResponse: Codable, Sendable {
    public var id: UUID
    public var finderConfiguration: BackgroundAgentFinderConfiguration?
    public var recordingSnapshot: RecordingSessionSnapshot?
    public var appleMusicResponse: AppleMusicRuntimeAgentResponseEnvelope?
    public var appleMusicLoginSnapshot: AppleMusicWrapperLoginSnapshot?
    public var appleMusicProgress: AppleMusicRuntimeProgress?
    public var appleMusicEvent: AppleMusicRuntimeAgentEvent?
    public var settingsAttention: SettingsAttentionItem?
    public var backgroundAgentIdentity: BackgroundServiceIdentity?
    public var runtimeWorkerIdentity: BackgroundServiceIdentity?
    public var errorMessage: String?

    public init(
        id: UUID,
        finderConfiguration: BackgroundAgentFinderConfiguration? = nil,
        recordingSnapshot: RecordingSessionSnapshot? = nil,
        appleMusicResponse: AppleMusicRuntimeAgentResponseEnvelope? = nil,
        appleMusicLoginSnapshot: AppleMusicWrapperLoginSnapshot? = nil,
        appleMusicProgress: AppleMusicRuntimeProgress? = nil,
        appleMusicEvent: AppleMusicRuntimeAgentEvent? = nil,
        settingsAttention: SettingsAttentionItem? = nil,
        backgroundAgentIdentity: BackgroundServiceIdentity? = nil,
        runtimeWorkerIdentity: BackgroundServiceIdentity? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.finderConfiguration = finderConfiguration
        self.recordingSnapshot = recordingSnapshot
        self.appleMusicResponse = appleMusicResponse
        self.appleMusicLoginSnapshot = appleMusicLoginSnapshot
        self.appleMusicProgress = appleMusicProgress
        self.appleMusicEvent = appleMusicEvent
        self.settingsAttention = settingsAttention
        self.backgroundAgentIdentity = backgroundAgentIdentity
        self.runtimeWorkerIdentity = runtimeWorkerIdentity
        self.errorMessage = errorMessage
    }
}

public final class BackgroundAgentClient {
    private let transport: BackgroundAgentXPCClient

    public init(transport: BackgroundAgentXPCClient = BackgroundAgentXPCClient()) {
        self.transport = transport
    }

    public func finderConfiguration() async throws -> BackgroundAgentFinderConfiguration {
        let response: BackgroundAgentCommandResponse = try await send(.init(command: .finderConfiguration))
        guard let configuration = response.finderConfiguration else {
            throw BackgroundAgentXPCError.invalidResponse
        }
        return configuration
    }

    /// Confirms that launchd has started the agent and that its XPC listener is
    /// accepting requests. This is the only availability signal shown to UI.
    public func checkAvailability() async throws {
        _ = try await send(.init(command: .healthCheck)) as BackgroundAgentCommandResponse
    }

    public func servicesStatus() async throws -> BackgroundServicesStatus {
        let response: BackgroundAgentCommandResponse = try await send(.init(command: .healthCheck))
        return BackgroundServicesStatus(
            backgroundAgent: response.backgroundAgentIdentity,
            runtimeWorker: response.runtimeWorkerIdentity
        )
    }

    public func enqueue(_ jobs: [JobRequest]) async throws {
        _ = try await send(.init(command: .enqueueJobs, jobs: jobs)) as BackgroundAgentCommandResponse
    }

    public func reportUnsupportedShareURLs(_ urls: [URL]) async throws {
        _ = try await send(.init(command: .unsupportedShareURLs, urls: urls)) as BackgroundAgentCommandResponse
    }

    public func recordingSnapshot() async throws -> RecordingSessionSnapshot {
        let response: BackgroundAgentCommandResponse = try await send(.init(command: .recordingSnapshot))
        guard let snapshot = response.recordingSnapshot else {
            throw BackgroundAgentXPCError.invalidResponse
        }
        return snapshot
    }

    public func dispatchNotificationEvents() async throws {
        _ = try await send(.init(command: .dispatchNotificationEvents)) as BackgroundAgentCommandResponse
    }

    public func handlePendingAppleMusicDownload(
        format: AppleMusicDownloadFormat
    ) async throws -> SettingsAttentionItem? {
        let response: BackgroundAgentCommandResponse = try await send(.init(
            command: .handlePendingAppleMusicDownload,
            appleMusicDownloadFormat: format
        ))
        return response.settingsAttention
    }

    public func performAppleMusic(
        _ command: BackgroundAgentCommand,
        jobs: [JobRequest]? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil
    ) async throws -> BackgroundAgentCommandResponse {
        try await send(.init(
            command: command,
            jobs: jobs,
            appleMusicInitializeRequest: initializeRequest,
            appleMusicVerificationRequest: verificationRequest
        ))
    }

    private func send(_ request: BackgroundAgentCommandRequest) async throws -> BackgroundAgentCommandResponse {
        let response: BackgroundAgentCommandResponse = try await transport.send(
            request,
            response: BackgroundAgentCommandResponse.self,
            retryOnUnavailable: !request.command.requiresRequestDeduplication
        )
        if let message = response.errorMessage {
            throw BackgroundAgentXPCError.remote(message)
        }
        return response
    }
}
