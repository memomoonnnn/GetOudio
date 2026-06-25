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
    private let runtimeManager: AppleMusicRuntimeManager

    public init(
        runner: ProcessRunner = ProcessRunner(),
        runtimeManager: AppleMusicRuntimeManager = AppleMusicRuntimeManager()
    ) {
        self.runner = runner
        self.runtimeManager = runtimeManager
    }

    public var runtimeEnvironment: [String: String] { runtimeManager.runtimeEnvironment() }

    public func check() async -> ColimaRuntimeStatus {
        guard runtimeManager.isEnabled else {
            return ColimaRuntimeStatus(dockerPath: nil, colimaPath: nil, isRunning: false, detail: "Apple Music 下载功能尚未启用")
        }

        let dockerPath = runtimeManager.dockerURL.path
        guard Self.isRegularExecutable(runtimeManager.dockerURL) else {
            return ColimaRuntimeStatus(dockerPath: nil, colimaPath: nil, isRunning: false, detail: "未安装 Docker CLI")
        }

        let colimaPath = runtimeManager.colimaURL.path
        guard Self.isRegularExecutable(runtimeManager.colimaURL) else {
            return ColimaRuntimeStatus(dockerPath: dockerPath, colimaPath: nil, isRunning: false, detail: "未安装 Colima")
        }

        let env = runtimeManager.runtimeEnvironment()

        do {
            let status = try await runner.run(executablePath: colimaPath, arguments: ["status"], environment: env)
            let statusOutput = status.standardOutput + status.standardError
            guard status.succeeded, statusOutput.localizedCaseInsensitiveContains("running") else {
                return ColimaRuntimeStatus(
                    dockerPath: dockerPath,
                    colimaPath: colimaPath,
                    isRunning: false,
                    detail: "Colima 未运行，使用 Apple Music 时会在后台启动"
                )
            }

            let dockerInfo = try await runner.run(executablePath: dockerPath, arguments: dockerArguments(["info"]), environment: env)
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
        try runtimeManager.ensureEnabledAndInstalled()
        let dockerPath = runtimeManager.dockerURL.path
        let colimaPath = runtimeManager.colimaURL.path
        let env = runtimeManager.runtimeEnvironment()
        try await runtimeManager.ensureLimaVirtualizationEntitlement()

        let currentStatus = try? await runner.run(executablePath: colimaPath, arguments: ["status"], environment: env)
        let currentStatusOutput = (currentStatus?.standardOutput ?? "") + (currentStatus?.standardError ?? "")
        if currentStatus?.succeeded != true || !currentStatusOutput.localizedCaseInsensitiveContains("running") {
            let start = try await runner.run(
                executablePath: colimaPath,
                arguments: [
                    "start",
                    "--runtime", "docker",
                    "--disk", "1",
                    "--root-disk", "6",
                    "--downloader", "curl",
                    "--very-verbose"
                ],
                environment: env
            )
            guard start.succeeded else {
                let processDetail = start.standardError.isEmpty ? start.standardOutput : start.standardError
                let limaDetail = runtimeManager.limaHostAgentError()
                let detail = limaDetail.isEmpty ? processDetail : "\(processDetail)\nLima: \(limaDetail)"
                throw ProcessRunnerError.processFailed("Colima 启动失败：\(detail)")
            }
        }

        let dockerInfo = try await runner.run(executablePath: dockerPath, arguments: dockerArguments(["info"]), environment: env)
        guard dockerInfo.succeeded else {
            let detail = dockerInfo.standardError.isEmpty ? dockerInfo.standardOutput : dockerInfo.standardError
            throw ProcessRunnerError.processFailed("无法连接 Colima Docker engine：\(detail)")
        }

        return dockerPath
    }

    public func dockerArguments(_ arguments: [String]) -> [String] {
        ["--context", dockerContext] + arguments
    }

    private static func isRegularExecutable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        else {
            return false
        }
        return values.isRegularFile == true
    }
}
