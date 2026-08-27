import Foundation

public enum BackgroundAgentXPC {
    public static let machServiceName = "com.shengjiacheng.GetOudio.agent"
}

public actor XPCRequestRegistry<Response: Sendable> {
    private enum Entry {
        case inFlight(Task<Response, Never>)
        case completed(Response)
    }

    private let maximumCompletedResponseCount: Int
    private var entries: [UUID: Entry] = [:]
    private var completedRequestIDs: [UUID] = []

    public init(maximumCompletedResponseCount: Int = 128) {
        self.maximumCompletedResponseCount = max(1, maximumCompletedResponseCount)
    }

    public func response(
        for requestID: UUID,
        operation: @escaping @Sendable () async -> Response
    ) async -> Response {
        if let entry = entries[requestID] {
            switch entry {
            case .inFlight(let task):
                return await task.value
            case .completed(let response):
                return response
            }
        }

        let task = Task { await operation() }
        entries[requestID] = .inFlight(task)
        let response = await task.value
        entries[requestID] = .completed(response)
        completedRequestIDs.append(requestID)
        trimCompletedResponses()
        return response
    }

    private func trimCompletedResponses() {
        while completedRequestIDs.count > maximumCompletedResponseCount {
            let requestID = completedRequestIDs.removeFirst()
            if case .completed = entries[requestID] {
                entries.removeValue(forKey: requestID)
            }
        }
    }
}

@objc public protocol BackgroundAgentXPCProtocol {
    func handle(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

public enum BackgroundAgentXPCError: LocalizedError {
    case unavailable
    case invalidResponse
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Get Oudio 后台服务不可用。请先在设置中安装后台活动后重试。"
        case .invalidResponse: return "Get Oudio 后台服务返回了无效响应。"
        case .remote(let message): return message
        }
    }
}

private final class BackgroundAgentReplyGate {
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

/// A small Codable transport boundary.  The server owns persistence and all
/// side effects; clients never receive a storage URL.
public final class BackgroundAgentXPCClient {
    public init() {}

    public func send<Request: Encodable, Response: Decodable>(
        _ request: Request,
        response: Response.Type,
        retryOnUnavailable: Bool = true
    ) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        let reply = try await send(data, retryOnUnavailable: retryOnUnavailable)
        do {
            return try JSONDecoder().decode(Response.self, from: reply)
        } catch {
            throw BackgroundAgentXPCError.invalidResponse
        }
    }

    public func send(_ data: Data, retryOnUnavailable: Bool = true) async throws -> Data {
        do {
            return try await sendOnce(data)
        } catch BackgroundAgentXPCError.unavailable {
            guard retryOnUnavailable else { throw BackgroundAgentXPCError.unavailable }
            // launchd may still be creating the service after registration.
            try await Task.sleep(nanoseconds: 250_000_000)
            return try await sendOnce(data)
        }
    }

    private func sendOnce(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BackgroundAgentReplyGate()
            gate.install(continuation)
            let connection = NSXPCConnection(machServiceName: BackgroundAgentXPC.machServiceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: BackgroundAgentXPCProtocol.self)
            connection.invalidationHandler = {
                gate.fail(BackgroundAgentXPCError.unavailable)
            }
            connection.interruptionHandler = {
                gate.fail(BackgroundAgentXPCError.unavailable)
            }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                gate.fail(BackgroundAgentXPCError.unavailable)
                connection.invalidate()
            }) as? BackgroundAgentXPCProtocol else {
                connection.invalidate()
                gate.fail(BackgroundAgentXPCError.unavailable)
                return
            }
            proxy.handle(data) { reply in
                gate.succeed(reply)
                connection.invalidate()
            }
        }
    }
}
