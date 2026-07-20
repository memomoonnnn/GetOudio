import Darwin
import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessOutputStream: Sendable {
    case standardOutput
    case standardError
}

public enum ProcessRunnerError: Error, LocalizedError {
    case executableNotFound(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "未找到可执行文件：\(path)"
        case .processFailed(let message):
            return message
        }
    }
}

public final class ProcessRunner {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)? = nil,
        shouldTerminate: (@Sendable () -> Bool)? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default

            // Resolve symlinks so the kernel sees the canonical path (sandbox
            // may reject paths that traverse firmlinks or symlinks).
            let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
            let resolvedPath = executableURL.path

            guard fileManager.fileExists(atPath: resolvedPath) else {
                DiagnosticLog.append("[ProcessRunner] 文件不存在：\(resolvedPath)")
                throw ProcessRunnerError.executableNotFound(resolvedPath)
            }

            // Log file attributes for diagnostics
            let attrs = (try? fileManager.attributesOfItem(atPath: resolvedPath)) ?? [:]
            let fileSize = (attrs[.size] as? Int64) ?? 0
            let permissions = (attrs[.posixPermissions] as? Int16).map { String($0, radix: 8) } ?? "?"
            let owner = attrs[.ownerAccountName] as? String ?? "?"
            let isExec = fileManager.isExecutableFile(atPath: resolvedPath)
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
            let isRegularFile = (try? executableURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            DiagnosticLog.append("[ProcessRunner] 准备执行：\(resolvedPath) | 大小=\(fileSize) | 权限=\(permissions) | 属主=\(owner) | isExecutable=\(isExec) | isDirectory=\(isDirectory.boolValue) | isRegularFile=\(isRegularFile)")

            if !isExec {
                DiagnosticLog.append("[ProcessRunner] isExecutable 返回 false，尝试修复权限...")
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolvedPath)
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let process = Process()
            process.launchPath = resolvedPath
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            if let env = environment {
                var merged = ProcessInfo.processInfo.environment
                for (key, value) in env { merged[key] = value }
                process.environment = merged
            }
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                let nsError = error as NSError
                DiagnosticLog.append("[ProcessRunner] process.run() 失败：domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) path=\(resolvedPath)")
                throw error
            }

            let outputData = LockedData()
            let errorData = LockedData()
            let outputDecoder = UTF8ChunkDecoder()
            let errorDecoder = UTF8ChunkDecoder()
            let readGroup = DispatchGroup()
            let terminationState = LockedTerminationState()
            let terminationTimer = Self.makeTerminationTimer(
                process: process,
                executablePath: resolvedPath,
                shouldTerminate: shouldTerminate,
                state: terminationState
            )
            defer { terminationTimer?.cancel() }

            readGroup.enter()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let text = outputDecoder.finish(), !text.isEmpty {
                        outputHandler?(.standardOutput, text)
                    }
                    readGroup.leave()
                    return
                }
                outputData.append(data)
                if let text = outputDecoder.append(data), !text.isEmpty {
                    outputHandler?(.standardOutput, text)
                }
            }

            readGroup.enter()
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let text = errorDecoder.finish(), !text.isEmpty {
                        outputHandler?(.standardError, text)
                    }
                    readGroup.leave()
                    return
                }
                errorData.append(data)
                if let text = errorDecoder.append(data), !text.isEmpty {
                    outputHandler?(.standardError, text)
                }
            }

            process.waitUntilExit()
            readGroup.wait()

            return ProcessResult(
                executableURL: executableURL,
                arguments: arguments,
                exitCode: process.terminationStatus,
                standardOutput: outputData.stringValue,
                standardError: errorData.stringValue
            )
        }.value
    }

    public func runShell(_ command: String) async throws -> ProcessResult {
        try await run(executablePath: "/bin/zsh", arguments: ["-lc", command])
    }

    private static func makeTerminationTimer(
        process: Process,
        executablePath: String,
        shouldTerminate: (@Sendable () -> Bool)?,
        state: LockedTerminationState
    ) -> DispatchSourceTimer? {
        guard let shouldTerminate else { return nil }

        let queue = DispatchQueue(label: "com.shengjiacheng.GetOudio.process-termination")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(300))
        timer.setEventHandler {
            guard shouldTerminate() else { return }
            if let elapsed = state.elapsedSinceFirstSignal, elapsed > 5 {
                Darwin.kill(process.processIdentifier, SIGKILL)
                return
            }
            guard state.markFirstSignalIfNeeded() else { return }
            DiagnosticLog.append("[ProcessRunner] 收到终止请求，正在停止：\(executablePath)")
            process.terminate()
        }
        timer.resume()
        return timer
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var stringValue: String {
        lock.lock()
        let value = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
        return value
    }
}

final class UTF8ChunkDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var bufferedData = Data()

    func append(_ data: Data) -> String? {
        lock.lock()
        bufferedData.append(data)
        let text = consumeCompleteScalars()
        lock.unlock()
        return text
    }

    func finish() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !bufferedData.isEmpty else { return nil }
        defer { bufferedData.removeAll(keepingCapacity: false) }
        return String(data: bufferedData, encoding: .utf8)
    }

    private func consumeCompleteScalars() -> String? {
        let incompleteSuffixLength = Self.incompleteUTF8SuffixLength(in: bufferedData)
        let completeLength = bufferedData.count - incompleteSuffixLength
        guard completeLength > 0 else { return nil }

        let completeData = bufferedData.prefix(completeLength)
        guard let text = String(data: completeData, encoding: .utf8) else { return nil }
        bufferedData.removeFirst(completeLength)
        return text
    }

    private static func incompleteUTF8SuffixLength(in data: Data) -> Int {
        guard let lastIndex = data.indices.last else { return 0 }

        var leadingIndex = lastIndex
        var continuationCount = 0
        while leadingIndex > data.startIndex, data[leadingIndex] & 0b1100_0000 == 0b1000_0000 {
            continuationCount += 1
            leadingIndex = data.index(before: leadingIndex)
        }

        let leadingByte = data[leadingIndex]
        let expectedLength: Int
        switch leadingByte {
        case 0b1100_0010...0b1101_1111:
            expectedLength = 2
        case 0b1110_0000...0b1110_1111:
            expectedLength = 3
        case 0b1111_0000...0b1111_0100:
            expectedLength = 4
        default:
            return 0
        }

        let availableLength = continuationCount + 1
        return availableLength < expectedLength ? availableLength : 0
    }
}

private final class LockedTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var firstSignalDate: Date?

    var elapsedSinceFirstSignal: TimeInterval? {
        lock.lock()
        let elapsed = firstSignalDate.map { Date().timeIntervalSince($0) }
        lock.unlock()
        return elapsed
    }

    func markFirstSignalIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard firstSignalDate == nil else { return false }
        firstSignalDate = Date()
        return true
    }
}
