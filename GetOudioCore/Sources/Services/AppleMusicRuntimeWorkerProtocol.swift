import Foundation

public enum AppleMusicRuntimeWorkerXPC {
    public static let machServiceName = "com.shengjiacheng.GetOudio.runtime-worker"
}

@objc public protocol AppleMusicRuntimeWorkerXPCProtocol {
    func handle(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

public enum AppleMusicRuntimeWorkerCommand: String, Codable, Sendable {
    case status
    case wrapperStatus = "wrapper-status"
    case install
    case uninstall
    case download
    case initialize
    case submitCode = "submit-code"
    case stopRuntime = "stop-runtime"
    case cancel
    case progress
    case snapshot
}

public struct AppleMusicRuntimeExecutionSettings: Codable, Equatable, Sendable {
    public var outputDirectoryPath: String
    public var defaultFormat: AppleMusicDownloadFormat

    public init(outputDirectoryURL: URL, defaultFormat: AppleMusicDownloadFormat) {
        outputDirectoryPath = outputDirectoryURL.path
        self.defaultFormat = defaultFormat
    }

    public var outputDirectoryURL: URL {
        URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
    }
}

public struct AppleMusicRuntimeWorkerRequest: Codable, Sendable {
    public var id: UUID
    public var command: AppleMusicRuntimeWorkerCommand
    public var resourceRootPath: String?
    public var gpacPackageURLOverride: String?
    public var downloadRequest: AppleMusicRuntimeAgentDownloadRequest?
    public var initializeRequest: AppleMusicRuntimeAgentInitializeRequest?
    public var verificationRequest: AppleMusicRuntimeAgentVerificationRequest?
    public var executionSettings: AppleMusicRuntimeExecutionSettings?

    public init(
        id: UUID,
        command: AppleMusicRuntimeWorkerCommand,
        resourceRootPath: String?,
        gpacPackageURLOverride: String? = nil,
        downloadRequest: AppleMusicRuntimeAgentDownloadRequest? = nil,
        initializeRequest: AppleMusicRuntimeAgentInitializeRequest? = nil,
        verificationRequest: AppleMusicRuntimeAgentVerificationRequest? = nil,
        executionSettings: AppleMusicRuntimeExecutionSettings? = nil
    ) {
        self.id = id
        self.command = command
        self.resourceRootPath = resourceRootPath
        self.gpacPackageURLOverride = gpacPackageURLOverride
        self.downloadRequest = downloadRequest
        self.initializeRequest = initializeRequest
        self.verificationRequest = verificationRequest
        self.executionSettings = executionSettings
    }
}

public struct AppleMusicRuntimeWorkerResponse: Codable, Sendable {
    public var id: UUID
    public var response: AppleMusicRuntimeAgentResponseEnvelope?
    public var errorMessage: String?

    public init(
        id: UUID,
        response: AppleMusicRuntimeAgentResponseEnvelope? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.response = response
        self.errorMessage = errorMessage
    }
}

/// Publishes login state while the detached wrapper advances through Apple's
/// authentication flow. The caller owns the lifetime and storage policy.
public enum AppleMusicWrapperLoginStatusPolling {
    public static func observe(
        intervalNanoseconds: UInt64 = 500_000_000,
        poll: @escaping @Sendable () async -> AppleMusicWrapperLoginStatus,
        publish: @escaping @Sendable (AppleMusicWrapperLoginStatus) async -> Void
    ) async {
        while !Task.isCancelled {
            let status = await poll()
            await publish(status)
            guard status.isInProgress else { return }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}

public enum AppleMusicRuntimeWorkerXPCError: LocalizedError {
    case unavailable
    case invalidFrame
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Music Runtime Worker 未连接。"
        case .invalidFrame: return "Apple Music Runtime Worker 返回了无效响应。"
        case .remote(let message): return message
        }
    }
}

private final class AppleMusicRuntimeWorkerReplyGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func succeed(_ data: Data) {
        finish(.success(data))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

public final class AppleMusicRuntimeWorkerXPCClient {
    public init() {}

    public func send(
        _ request: AppleMusicRuntimeWorkerRequest
    ) async throws -> AppleMusicRuntimeWorkerResponse {
        let requestData = try JSONEncoder().encode(request)
        let responseData = try await send(requestData)
        guard let response = try? JSONDecoder().decode(
            AppleMusicRuntimeWorkerResponse.self,
            from: responseData
        ), response.id == request.id else {
            throw AppleMusicRuntimeWorkerXPCError.invalidFrame
        }
        if let message = response.errorMessage {
            throw AppleMusicRuntimeWorkerXPCError.remote(message)
        }
        return response
    }

    private func send(_ data: Data) async throws -> Data {
        do {
            return try await sendOnce(data)
        } catch AppleMusicRuntimeWorkerXPCError.unavailable {
            try await Task.sleep(nanoseconds: 250_000_000)
            return try await sendOnce(data)
        }
    }

    private func sendOnce(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = AppleMusicRuntimeWorkerReplyGate()
            gate.install(continuation)
            let connection = NSXPCConnection(
                machServiceName: AppleMusicRuntimeWorkerXPC.machServiceName,
                options: []
            )
            connection.remoteObjectInterface = NSXPCInterface(
                with: AppleMusicRuntimeWorkerXPCProtocol.self
            )
            connection.invalidationHandler = {
                gate.fail(AppleMusicRuntimeWorkerXPCError.unavailable)
            }
            connection.interruptionHandler = {
                gate.fail(AppleMusicRuntimeWorkerXPCError.unavailable)
            }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                gate.fail(AppleMusicRuntimeWorkerXPCError.unavailable)
                connection.invalidate()
            }) as? AppleMusicRuntimeWorkerXPCProtocol else {
                connection.invalidate()
                gate.fail(AppleMusicRuntimeWorkerXPCError.unavailable)
                return
            }
            proxy.handle(data) { reply in
                gate.succeed(reply)
                connection.invalidate()
            }
        }
    }
}
