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

    public func run(executablePath: String, arguments: [String], currentDirectoryURL: URL? = nil, environment: [String: String]? = nil) async throws -> ProcessResult {
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
