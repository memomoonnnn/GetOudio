import CFNetwork
import Foundation

public final class AppleMusicWrapperRuntime {
    public let image: ManagedDockerImage = .appleMusicWrapper
    static let loginContainerName = "get-oudio-wrapper-login"
    private let runner: ProcessRunner
    private let runtime: ColimaDockerRuntime
    private let dockerImageManager: DockerImageManager
    private let runtimeManager: AppleMusicRuntimeManager
    private let settingsStore: SettingsStore

    public init(
        runner: ProcessRunner = ProcessRunner(),
        runtimeManager: AppleMusicRuntimeManager = AppleMusicRuntimeManager(),
        settingsStore: SettingsStore = SettingsStore(),
        runtime: ColimaDockerRuntime? = nil,
        dockerImageManager: DockerImageManager? = nil
    ) {
        self.runner = runner
        self.runtimeManager = runtimeManager
        self.settingsStore = settingsStore
        self.runtime = runtime ?? ColimaDockerRuntime(runtimeManager: runtimeManager)
        self.dockerImageManager = dockerImageManager ?? DockerImageManager(runtime: self.runtime)
    }

    public func runtimeDirectory() throws -> URL {
        let directory = runtimeManager.wrapperDataDirectory
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
        DiagnosticLog.append("[WrapperLogin] 2FA code file written path=\(fileURL.path)")
    }

    func clearVerificationCode() throws {
        let fileURL = try dataDirectory().appendingPathComponent("2fa.txt")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
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

    public func initialize(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool
    ) async throws -> ProcessResult {
        let currentStatus = await loginStatus()
        if currentStatus.isAuthenticated {
            throw ProcessRunnerError.processFailed("Apple Music 初始化已完成，无需重复初始化。")
        }
        if currentStatus.isInProgress {
            throw ProcessRunnerError.processFailed("Apple Music 登录正在进行，请勿重复启动。")
        }

        try clearVerificationCode()
        if let verificationCode, !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try writeVerificationCode(verificationCode)
        }

        try await ensureImageAvailable()
        let dockerPath = try await runtime.ensureRunning()
        let runtimeDirectory = try runtimeDirectory()
        let mount = "\(runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true).path):/app/rootfs/data"
        _ = try? await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["rm", "-f", Self.loginContainerName]),
            environment: runtime.runtimeEnvironment
        )

        let result = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(
                initializationDockerArguments(
                    username: username,
                    password: password,
                    mount: mount,
                    proxy: useSystemProxy ? systemProxyURL() : nil
                )
            ),
            environment: runtime.runtimeEnvironment
        )
        guard result.succeeded else {
            DiagnosticLog.append(
                "[WrapperLogin] container start failed exit=\(result.exitCode) "
                    + "stderr=\(sanitized(result.standardError))"
            )
            return result
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let startupState = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments([
                "inspect", "--format", "{{.State.Running}}", Self.loginContainerName
            ]),
            environment: runtime.runtimeEnvironment
        )
        guard startupState.succeeded,
              startupState.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            let exitState = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "inspect",
                    "--format",
                    "status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} error={{.State.Error}} finished={{.State.FinishedAt}}",
                    Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let logs = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "logs", "--timestamps", "--tail", "500", Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let stateDetail = sanitized(exitState.standardOutput + exitState.standardError)
            let detail = wrapperLogSummary(logs.standardOutput + logs.standardError)
            DiagnosticLog.append(
                "[WrapperLogin] container exited during startup state=\(stateDetail) logs=\(detail)"
            )
            _ = try? await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments(["rm", "-f", Self.loginContainerName]),
                environment: runtime.runtimeEnvironment
            )
            throw ProcessRunnerError.processFailed(
                detail.isEmpty
                    ? "Apple Music 登录容器启动后立即退出：\(stateDetail)"
                    : "Apple Music 登录失败：\(detail)"
            )
        }

        DiagnosticLog.append(
                "[WrapperLogin] container started name=\(Self.loginContainerName) "
                + "mount=\(mount) image=\(image.imageName) "
                + "proxy=\(useSystemProxy ? (systemProxyURL()?.absoluteString ?? "unavailable") : "direct")"
        )
        startLoginDiagnosticsMonitor()
        startLoginCompletionMonitor()
        return result
    }

    func initializationDockerArguments(
        username: String,
        password: String,
        mount: String,
        proxy: URL? = nil
    ) -> [String] {
        var arguments = [
            "run", "--detach",
            "--privileged",
            "--platform", image.platform,
            "--name", Self.loginContainerName,
            "-v", mount,
            "--entrypoint", "./wrapper",
            image.imageName,
            "-L", "\(username):\(password)",
            "-F",
            "-H", "0.0.0.0"
        ]
        if let proxy {
            arguments.append(contentsOf: ["-P", proxy.absoluteString])
        }
        return arguments
    }

    public func logLoginDiagnostics(stage: String) async {
        do {
            let dockerPath = try await runtime.ensureRunning()
            let state = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "inspect",
                    "--format",
                    "status={{.State.Status}} running={{.State.Running}} exit={{.State.ExitCode}} error={{.State.Error}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}",
                    Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let logs = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "logs", "--timestamps", "--tail", "120", Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let imageInfo = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "image", "inspect",
                    "--format",
                    "id={{.Id}} created={{.Created}} arch={{.Architecture}}",
                    image.imageName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let codeURL = try dataDirectory().appendingPathComponent("2fa.txt")
            DiagnosticLog.append(
                "[WrapperLogin][\(stage)] state=\(sanitized(state.standardOutput + state.standardError)) "
                    + "2faExists=\(FileManager.default.fileExists(atPath: codeURL.path)) "
                    + "image=\(sanitized(imageInfo.standardOutput + imageInfo.standardError)) "
                    + "logs=\(wrapperLogSummary(logs.standardOutput + logs.standardError))"
            )
        } catch {
            DiagnosticLog.append("[WrapperLogin][\(stage)] diagnostics failed: \(error.localizedDescription)")
        }
    }

    public func loginStatus() async -> AppleMusicWrapperLoginStatus {
        if FileManager.default.fileExists(atPath: loginCompletedMarkerURL.path) {
            return AppleMusicWrapperLoginStatus(phase: .authenticated, message: "初始化已完成")
        }
        guard runtimeManager.isEnabled else {
            return AppleMusicWrapperLoginStatus(phase: .notInitialized, message: "Apple Music 下载功能尚未启用")
        }

        do {
            let dockerPath = try await runtime.ensureRunning()
            let inspect = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "inspect", "--format", "{{.State.Running}}", Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            guard inspect.succeeded else {
                return AppleMusicWrapperLoginStatus(phase: .notInitialized, message: "尚未初始化")
            }

            let isRunning = inspect.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            let logs = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "logs", "--tail", "160", Self.loginContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let status = Self.loginStatus(
                logs: logs.standardOutput + logs.standardError,
                isRunning: isRunning,
                hasCompletedMarker: false
            )
            if status.isAuthenticated {
                try markAuthenticationCompleted()
                _ = try? await runner.run(
                    executablePath: dockerPath,
                    arguments: runtime.dockerArguments(["rm", "-f", Self.loginContainerName]),
                    environment: runtime.runtimeEnvironment
                )
                DiagnosticLog.append("[WrapperLogin] authentication persisted; login container stopped")
            }
            return status
        } catch {
            return AppleMusicWrapperLoginStatus(
                phase: .notInitialized,
                message: "无法检查初始化状态：\(error.localizedDescription)"
            )
        }
    }

    static func loginStatus(
        logs: String,
        isRunning: Bool,
        hasCompletedMarker: Bool
    ) -> AppleMusicWrapperLoginStatus {
        if hasCompletedMarker || logs.contains("response type 6") {
            return AppleMusicWrapperLoginStatus(phase: .authenticated, message: "初始化已完成")
        }
        if logs.contains("login failed") || logs.contains("response type 4") {
            return AppleMusicWrapperLoginStatus(phase: .failed, message: "登录失败，可以重新初始化")
        }
        if logs.contains("Code file detected! Logging in") {
            return AppleMusicWrapperLoginStatus(phase: .authenticating, message: "验证码已提交，正在验证")
        }
        if logs.contains("2FA: true") || logs.contains("Waiting for input") {
            return AppleMusicWrapperLoginStatus(
                phase: .waitingForVerificationCode,
                message: "已发送验证码，请输入后提交"
            )
        }
        if isRunning {
            return AppleMusicWrapperLoginStatus(phase: .starting, message: "正在登录并等待 Apple 响应")
        }
        return AppleMusicWrapperLoginStatus(phase: .failed, message: "登录容器已停止，可以重新初始化")
    }

    private func startLoginDiagnosticsMonitor() {
        Task {
            var previousDelay: UInt64 = 0
            for delay: UInt64 in [2, 10, 30, 60] {
                try? await Task.sleep(nanoseconds: (delay - previousDelay) * 1_000_000_000)
                await logLoginDiagnostics(stage: "\(delay)s")
                previousDelay = delay
            }
        }
    }

    private func startLoginCompletionMonitor() {
        Task {
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let status = await loginStatus()
                if status.isAuthenticated || status.phase == .failed {
                    return
                }
            }
        }
    }

    public func ensureServerRunning() async throws {
        try await ensureImageAvailable()
        guard (await loginStatus()).isAuthenticated else {
            throw ProcessRunnerError.processFailed("Apple Music 尚未完成初始化。")
        }
        let dockerPath = try await runtime.ensureRunning()
        let inspect = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["inspect", "-f", "{{.State.Running}}", "get-oudio-wrapper"]),
            environment: runtime.runtimeEnvironment
        )
        if inspect.succeeded && inspect.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return
        }

        _ = try? await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["rm", "-f", "get-oudio-wrapper"]),
            environment: runtime.runtimeEnvironment
        )
        let runtimeDirectory = try runtimeDirectory()
        let mount = "\(runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true).path):/app/rootfs/data"
        var wrapperArguments = ["-H", "0.0.0.0"]
        if settingsStore.appleMusicUseSystemProxy, let proxy = systemProxyURL() {
            wrapperArguments.append(contentsOf: ["-P", proxy.absoluteString])
        }
        let result = try await runner.run(
            executablePath: dockerPath,
            arguments: self.runtime.dockerArguments([
                "run", "-d",
                "--privileged",
                "--platform", image.platform,
                "--name", "get-oudio-wrapper",
                "-v", mount,
                "-p", "10020:10020",
                "-p", "20020:20020",
                "-p", "30020:30020",
                "--entrypoint", "./wrapper",
                image.imageName
            ] + wrapperArguments),
            environment: self.runtime.runtimeEnvironment
        )

        guard result.succeeded else {
            throw ProcessRunnerError.executableNotFound(result.standardError.isEmpty ? "Apple Music wrapper container" : result.standardError)
        }
    }

    private func dataDirectory(in runtimeDirectory: URL) -> URL {
        runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true)
    }

    private var loginCompletedMarkerURL: URL {
        runtimeManager.wrapperDataDirectory.appendingPathComponent(".login-completed")
    }

    private func markAuthenticationCompleted() throws {
        try FileManager.default.createDirectory(
            at: runtimeManager.wrapperDataDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: loginCompletedMarkerURL, options: .atomic)
    }

    private func systemProxyURL() -> URL? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return Self.proxyURL(from: settings)
    }

    static func proxyURL(from settings: [String: Any]) -> URL? {
        let candidates: [(enabled: CFString, host: CFString, port: CFString)] = [
            (kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort),
            (kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort)
        ]

        for candidate in candidates {
            guard (settings[candidate.enabled as String] as? NSNumber)?.boolValue == true,
                  var host = settings[candidate.host as String] as? String,
                  !host.isEmpty,
                  let port = settings[candidate.port as String] as? NSNumber
            else {
                continue
            }
            if host == "127.0.0.1" || host == "::1" || host == "localhost" {
                host = "host.lima.internal"
            }
            return URL(string: "http://\(host):\(port.intValue)")
        }
        return nil
    }

    private func sanitized(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let sanitizedLines = lines.map { line -> String in
            let value = String(line)
            if value.contains("args=-L") || value.contains(" -L ") {
                return "<redacted credential-bearing line>"
            }
            return value
        }
        let joined = sanitizedLines.joined(separator: "\\n")
        return joined.count > 4_000 ? String(joined.prefix(4_000)) + "...<truncated>" : joined
    }

    func wrapperLogSummary(_ text: String) -> String {
        var filteredCount = 0
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            let value = String(line)
            if value.contains("WARNING: linker:") {
                filteredCount += 1
                return nil
            }
            if value.contains("args=-L") || value.contains(" -L ") {
                return "<redacted credential-bearing line>"
            }
            return value
        }
        var joined = lines.joined(separator: "\\n")
        if filteredCount > 0 {
            joined = "[filtered \(filteredCount) Android linker warnings]\\n" + joined
        }
        if joined.count > 8_000 {
            joined = "...<truncated-prefix>" + String(joined.suffix(8_000))
        }
        return joined
    }
}
