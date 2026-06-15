import Foundation

public struct ColimaRuntimeStatus: Equatable, Sendable {
    public var dockerPath: String?
    public var colimaPath: String?
    public var isRunning: Bool
    public var detail: String

    public init(dockerPath: String?, colimaPath: String?, isRunning: Bool, detail: String) {
        self.dockerPath = dockerPath
        self.colimaPath = colimaPath
        self.isRunning = isRunning
        self.detail = detail
    }
}

public final class ColimaDockerRuntime {
    public let dockerContext = "colima"
    private let runner: ProcessRunner
    private let dependencyManager: DependencyManager

    public init(runner: ProcessRunner = ProcessRunner(), dependencyManager: DependencyManager = DependencyManager()) {
        self.runner = runner
        self.dependencyManager = dependencyManager
    }

    public func check() async -> ColimaRuntimeStatus {
        let docker = await dependencyManager.check(.docker)
        guard let dockerPath = docker.resolvedPath else {
            return ColimaRuntimeStatus(dockerPath: nil, colimaPath: nil, isRunning: false, detail: "未安装 Docker CLI")
        }

        let colima = await dependencyManager.check(.colima)
        guard let colimaPath = colima.resolvedPath else {
            return ColimaRuntimeStatus(dockerPath: dockerPath, colimaPath: nil, isRunning: false, detail: "未安装 Colima")
        }

        do {
            let status = try await runner.run(executablePath: colimaPath, arguments: ["status"])
            guard status.succeeded, status.standardOutput.localizedCaseInsensitiveContains("running") else {
                return ColimaRuntimeStatus(
                    dockerPath: dockerPath,
                    colimaPath: colimaPath,
                    isRunning: false,
                    detail: "Colima 未运行，使用 Apple Music 时会在后台启动"
                )
            }

            let dockerInfo = try await runner.run(executablePath: dockerPath, arguments: dockerArguments(["info"]))
            if dockerInfo.succeeded {
                return ColimaRuntimeStatus(dockerPath: dockerPath, colimaPath: colimaPath, isRunning: true, detail: "Colima Docker engine 正在后台运行")
            }

            return ColimaRuntimeStatus(
                dockerPath: dockerPath,
                colimaPath: colimaPath,
                isRunning: false,
                detail: dockerInfo.standardError.isEmpty ? "Docker context colima 不可用" : dockerInfo.standardError
            )
        } catch {
            return ColimaRuntimeStatus(dockerPath: dockerPath, colimaPath: colimaPath, isRunning: false, detail: error.localizedDescription)
        }
    }

    public func ensureRunning() async throws -> String {
        let docker = await dependencyManager.check(.docker)
        guard let dockerPath = docker.resolvedPath else {
            throw ProcessRunnerError.executableNotFound("docker")
        }

        let colima = await dependencyManager.check(.colima)
        guard let colimaPath = colima.resolvedPath else {
            throw ProcessRunnerError.executableNotFound("colima")
        }

        let currentStatus = try? await runner.run(executablePath: colimaPath, arguments: ["status"])
        if currentStatus?.succeeded != true || currentStatus?.standardOutput.localizedCaseInsensitiveContains("running") != true {
            let start = try await runner.run(executablePath: colimaPath, arguments: ["start", "--runtime", "docker"])
            guard start.succeeded else {
                let detail = start.standardError.isEmpty ? start.standardOutput : start.standardError
                throw ProcessRunnerError.processFailed("Colima 启动失败：\(detail)")
            }
        }

        let dockerInfo = try await runner.run(executablePath: dockerPath, arguments: dockerArguments(["info"]))
        guard dockerInfo.succeeded else {
            let detail = dockerInfo.standardError.isEmpty ? dockerInfo.standardOutput : dockerInfo.standardError
            throw ProcessRunnerError.processFailed("无法连接 Colima Docker engine：\(detail)")
        }

        return dockerPath
    }

    public func dockerArguments(_ arguments: [String]) -> [String] {
        ["--context", dockerContext] + arguments
    }
}
