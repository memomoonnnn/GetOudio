import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public var succeeded: Bool { exitCode == 0 }
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

    public func run(executablePath: String, arguments: [String], currentDirectoryURL: URL? = nil) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                throw ProcessRunnerError.executableNotFound(executablePath)
            }

            let executableURL = URL(fileURLWithPath: executablePath)
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            return ProcessResult(
                executableURL: executableURL,
                arguments: arguments,
                exitCode: process.terminationStatus,
                standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                standardError: String(data: errorData, encoding: .utf8) ?? ""
            )
        }.value
    }

    public func runShell(_ command: String) async throws -> ProcessResult {
        try await run(executablePath: "/bin/zsh", arguments: ["-lc", command])
    }
}
