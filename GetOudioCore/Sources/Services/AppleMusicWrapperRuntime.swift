import Foundation

public final class AppleMusicWrapperRuntime {
    public let image: ManagedDockerImage = .appleMusicWrapper
    private let runner: ProcessRunner
    private let runtime: ColimaDockerRuntime
    private let dockerImageManager: DockerImageManager

    public init(
        runner: ProcessRunner = ProcessRunner(),
        runtime: ColimaDockerRuntime = ColimaDockerRuntime(),
        dockerImageManager: DockerImageManager = DockerImageManager()
    ) {
        self.runner = runner
        self.runtime = runtime
        self.dockerImageManager = dockerImageManager
    }

    public func runtimeDirectory() throws -> URL {
        let directory = try SharedContainer.directory()
            .appendingPathComponent("AppleMusicWrapper", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory(in: directory), withIntermediateDirectories: true)
        return directory
    }

    public func dataDirectory() throws -> URL {
        try dataDirectory(in: runtimeDirectory())
    }

    public func writeVerificationCode(_ code: String) throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let fileURL = try dataDirectory().appendingPathComponent("2fa.txt")
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func ensureImageAvailable() async throws {
        let status = await dockerImageManager.check(image)
        guard !status.isAvailable else {
            return
        }
        let result = try await dockerImageManager.pull(image)
        guard result.succeeded else {
            throw ProcessRunnerError.executableNotFound(result.standardError.isEmpty ? image.imageName : result.standardError)
        }
    }

    public func initialize(username: String, password: String, verificationCode: String?) async throws -> ProcessResult {
        if let verificationCode, !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try writeVerificationCode(verificationCode)
        }

        try await ensureImageAvailable()
        let dockerPath = try await runtime.ensureRunning()
        let runtime = try runtimeDirectory()
        let mount = "\(runtime.appendingPathComponent("rootfs/data", isDirectory: true).path):/app/rootfs/data"
        let args = "-L \(username):\(password) -F"

        return try await runner.run(
            executablePath: dockerPath,
            arguments: self.runtime.dockerArguments(["run", "--platform", image.platform, "-v", mount, "-e", "args=\(args)", "--rm", image.imageName])
        )
    }

    public func ensureServerRunning() async throws {
        try await ensureImageAvailable()
        let dockerPath = try await runtime.ensureRunning()
        let inspect = try await runner.run(executablePath: dockerPath, arguments: runtime.dockerArguments(["inspect", "-f", "{{.State.Running}}", "get-oudio-wrapper"]))
        if inspect.succeeded && inspect.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return
        }

        _ = try? await runner.run(executablePath: dockerPath, arguments: runtime.dockerArguments(["rm", "-f", "get-oudio-wrapper"]))
        let runtime = try runtimeDirectory()
        let mount = "\(runtime.appendingPathComponent("rootfs/data", isDirectory: true).path):/app/rootfs/data"
        let result = try await runner.run(
            executablePath: dockerPath,
            arguments: self.runtime.dockerArguments([
                "run", "-d",
                "--platform", image.platform,
                "--name", "get-oudio-wrapper",
                "-v", mount,
                "-p", "10020:10020",
                "-p", "20020:20020",
                "-p", "30020:30020",
                "-e", "args=-H 0.0.0.0",
                image.imageName
            ])
        )

        guard result.succeeded else {
            throw ProcessRunnerError.executableNotFound(result.standardError.isEmpty ? "Apple Music wrapper container" : result.standardError)
        }
    }

    private func dataDirectory(in runtimeDirectory: URL) -> URL {
        runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true)
    }
}
