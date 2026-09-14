import CFNetwork
import Foundation

public final class AppleMusicWrapperRuntime {
    public let image: ManagedDockerImage = .appleMusicWrapper
    static let loginContainerName = "get-oudio-wrapper-login"
    static let serverContainerName = "get-oudio-wrapper"
    static let legacyServerContainerNames = ["get-oudio-wrapper-rollback"]
    static let verificationCodeRelativePath = "data/com.apple.android.music/files/2fa.txt"
    private let runner: ProcessRunner
    private let runtime: ColimaDockerRuntime
    private let dockerImageManager: DockerImageManager
    private let runtimeManager: AppleMusicRuntimeManager
    private let settingsStore: SettingsStore?
    private let systemProxyEnabled: Bool?

    public init(
        runner: ProcessRunner = ProcessRunner(),
        runtimeManager: AppleMusicRuntimeManager,
        settingsStore: SettingsStore? = nil,
        systemProxyEnabled: Bool? = nil,
        runtime: ColimaDockerRuntime? = nil,
        dockerImageManager: DockerImageManager? = nil
    ) {
        self.runner = runner
        self.runtimeManager = runtimeManager
        self.settingsStore = settingsStore
        self.systemProxyEnabled = systemProxyEnabled
        self.runtime = runtime ?? ColimaDockerRuntime(runtimeManager: runtimeManager)
        self.dockerImageManager = dockerImageManager ?? DockerImageManager(runtime: self.runtime)
    }

    public convenience init(container: AgentDataStore) {
        let manager = AppleMusicRuntimeManager(container: container)
        self.init(
            runtimeManager: manager,
            settingsStore: SettingsStore(container: container)
        )
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
        let fileURL = try verificationCodeURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        DiagnosticLog.append("[WrapperLogin] 2FA code file written path=\(fileURL.path)")
    }

    func clearVerificationCode() throws {
        let directory = try dataDirectory()
        let codeURLs = [
            directory.appendingPathComponent(Self.verificationCodeRelativePath),
            directory.appendingPathComponent("2fa.txt")
        ]
        for fileURL in codeURLs where FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func verificationCodeURL() throws -> URL {
        try dataDirectory().appendingPathComponent(Self.verificationCodeRelativePath)
    }

    public func ensureImageAvailable() async throws {
        let status = await dockerImageManager.check(image)
        guard status.isAvailable,
              runtimeManager.managedComponentUpdateState(.wrapperImage, isInstalled: true) == .current
        else {
            throw ProcessRunnerError.executableNotFound(
                "Apple Music wrapper 缺失或不是当前受控版本。请在 Apple Music 设置中点击“检查并更新”。"
            )
        }
    }

    public func finalizeManagedImageUpdate(resetAuthentication: Bool = false) async throws {
        try await ensureImageAvailable()
        let dockerPath = try await runtime.ensureRunning()
        let login = await loginStatus()
        guard !login.isInProgress else {
            DiagnosticLog.append("[WrapperServer] legacy image cleanup deferred while login is in progress")
            return
        }

        if resetAuthentication {
            try await removeWrapperServerContainer(dockerPath: dockerPath)
            await removeLegacyWrapperImages(dockerPath: dockerPath)
            try clearAuthenticationState()
            DiagnosticLog.append("[WrapperServer] runtime update reset initialization state; rootfs/data preserved")
            return
        }

        let existingImage = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["inspect", "-f", "{{.Config.Image}}", Self.serverContainerName]),
            environment: runtime.runtimeEnvironment
        )

        if existingImage.succeeded,
           existingImage.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) != image.imageName {
            guard (await loginStatus()).isAuthenticated else {
                DiagnosticLog.append("[WrapperServer] legacy container cleanup deferred because authentication is not confirmed")
                return
            }
            try await removeWrapperServerContainer(dockerPath: dockerPath)
            await removeLegacyWrapperImages(dockerPath: dockerPath)
            try await ensureServerRunning()
            return
        }

        await removeLegacyWrapperImages(dockerPath: dockerPath)
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
            let codeURL = try verificationCodeURL()
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

    public func stopLoginAttempt() async {
        do {
            let dockerPath = try await runtime.ensureRunning()
            _ = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments(["rm", "-f", Self.loginContainerName]),
                environment: runtime.runtimeEnvironment
            )
            DiagnosticLog.append("[WrapperLogin] stopped timed-out login container")
        } catch {
            DiagnosticLog.append("[WrapperLogin] failed to stop timed-out login container: \(error.localizedDescription)")
        }
    }

    static func loginStatus(
        logs: String,
        isRunning: Bool,
        hasCompletedMarker: Bool
    ) -> AppleMusicWrapperLoginStatus {
        let hasReadyKeyServer = logs.contains("[+] account info cached successfully")
            && logs.contains("[!] listening key request on 0.0.0.0:40020")
        if hasCompletedMarker || (isRunning && hasReadyKeyServer) {
            return AppleMusicWrapperLoginStatus(phase: .authenticated, message: "初始化已完成")
        }
        if logs.contains("login failed")
            || logs.contains("auth failed: response type")
            || logs.contains("auth error:")
            || logs.contains("Failed to get 2FA Code") {
            return AppleMusicWrapperLoginStatus(phase: .failed, message: "登录失败，可以重新初始化")
        }
        if isRunning, logs.contains("Code file detected! Logging in") {
            return AppleMusicWrapperLoginStatus(phase: .authenticating, message: "验证码已提交，正在验证")
        }
        if isRunning, logs.contains("2FA: true") || logs.contains("Waiting for input") {
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

    public func ensureServerRunning() async throws {
        try await ensureImageAvailable()
        guard (await loginStatus()).isAuthenticated else {
            throw ProcessRunnerError.processFailed("Apple Music 尚未完成初始化。")
        }
        let dockerPath = try await runtime.ensureRunning()
        let inspect = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments([
                "inspect",
                "-f",
                "{{.State.Status}}",
                Self.serverContainerName
            ]),
            environment: runtime.runtimeEnvironment
        )
        if inspect.succeeded {
            let status = inspect.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingImage = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments(["inspect", "-f", "{{.Config.Image}}", Self.serverContainerName]),
                environment: runtime.runtimeEnvironment
            )
            if existingImage.succeeded,
               existingImage.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == image.imageName {
                if status == "running" {
                    try await verifyServerReadiness(dockerPath: dockerPath)
                    await removeLegacyWrapperImages(dockerPath: dockerPath)
                    return
                }

                let start = try await runner.run(
                    executablePath: dockerPath,
                    arguments: runtime.dockerArguments(["start", Self.serverContainerName]),
                    environment: runtime.runtimeEnvironment
                )
                if start.succeeded {
                    try await verifyServerReadiness(dockerPath: dockerPath)
                    await removeLegacyWrapperImages(dockerPath: dockerPath)
                    DiagnosticLog.append("[WrapperServer] existing container started name=\(Self.serverContainerName) previousStatus=\(status)")
                    return
                }
                DiagnosticLog.append(
                    "[WrapperServer] existing container start failed name=\(Self.serverContainerName) "
                        + "previousStatus=\(status) stderr=\(sanitized(start.standardError))"
                )
            }
            try await removeWrapperServerContainer(dockerPath: dockerPath)
            await removeLegacyWrapperImages(dockerPath: dockerPath)
        }

        let runtimeDirectory = try runtimeDirectory()
        let mount = "\(runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true).path):/app/rootfs/data"
        do {
            let result = try await runner.run(
                executablePath: dockerPath,
                arguments: self.runtime.dockerArguments(
                    serverDockerArguments(
                        mount: mount,
                        proxy: (systemProxyEnabled ?? settingsStore?.appleMusicUseSystemProxy ?? false) ? systemProxyURL() : nil
                    )
                ),
                environment: self.runtime.runtimeEnvironment
            )
            guard result.succeeded else {
                throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? "Apple Music wrapper container 启动失败" : result.standardError)
            }
            try await verifyServerReadiness(dockerPath: dockerPath)
            await removeLegacyWrapperImages(dockerPath: dockerPath)
            DiagnosticLog.append("[WrapperServer] started managed image=\(image.imageName)")
        } catch {
            _ = try? await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments(["rm", "-f", Self.serverContainerName]),
                environment: runtime.runtimeEnvironment
            )
            throw error
        }
    }

    func serverDockerArguments(mount: String, proxy: URL? = nil) -> [String] {
        var arguments = [
            "run", "-d",
            "--privileged",
            "--platform", image.platform,
            "--name", Self.serverContainerName,
            "-v", mount,
            "-p", "10020:10020",
            "-p", "20020:20020",
            "-p", "30020:30020",
            "-p", "40020:40020",
            "--entrypoint", "./wrapper",
            image.imageName,
            "-H", "0.0.0.0"
        ]
        if let proxy {
            arguments.append(contentsOf: ["-P", proxy.absoluteString])
        }
        return arguments
    }

    func keyServerHealthCheckArguments() -> [String] {
        [
            "--silent",
            "--show-error",
            "--output", "/dev/null",
            "--write-out", "%{http_code}",
            "--max-time", "3",
            "http://127.0.0.1:40020/"
        ]
    }

    private func verifyServerReadiness(dockerPath: String) async throws {
        try await verifyServerPortMappings(dockerPath: dockerPath)
        var lastDetail = "40020 尚未开始监听"

        for attempt in 1...15 {
            let state = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments([
                    "inspect", "-f", "{{.State.Running}}", Self.serverContainerName
                ]),
                environment: runtime.runtimeEnvironment
            )
            let isRunning = state.succeeded
                && state.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            if isRunning {
                let health = try await runner.run(
                    executablePath: "/usr/bin/curl",
                    arguments: keyServerHealthCheckArguments()
                )
                let statusCode = health.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if health.succeeded, statusCode == "400" {
                    return
                }
                let detail = health.standardError.isEmpty ? statusCode : health.standardError
                lastDetail = detail.isEmpty ? "40020 返回非预期响应" : detail
            } else {
                lastDetail = "wrapper 容器未运行"
            }

            if attempt < 15 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        let logs = try? await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["logs", "--tail", "120", Self.serverContainerName]),
            environment: runtime.runtimeEnvironment
        )
        let logOutput = logs.map { $0.standardOutput + $0.standardError } ?? ""
        if logOutput.localizedCaseInsensitiveContains("Account must sign in")
            || logOutput.localizedCaseInsensitiveContains("token invalid or expired") {
            try? clearAuthenticationState()
            throw ProcessRunnerError.processFailed("Apple Music 登录已失效，请重新初始化。")
        }
        let logSummary = wrapperLogSummary(logOutput)
        let detail = logSummary.isEmpty ? lastDetail : logSummary
        throw ProcessRunnerError.processFailed("Apple Music wrapper 的 40020 key server 未就绪：\(sanitized(detail))")
    }

    private func verifyServerPortMappings(dockerPath: String) async throws {
        let result = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments([
                "inspect",
                "-f", "{{range $port, $_ := .NetworkSettings.Ports}}{{$port}} {{end}}",
                Self.serverContainerName
            ]),
            environment: runtime.runtimeEnvironment
        )
        let ports = result.standardOutput
        guard result.succeeded, ["10020/tcp", "20020/tcp", "30020/tcp", "40020/tcp"].allSatisfy(ports.contains) else {
            throw ProcessRunnerError.processFailed("Apple Music wrapper 服务端口映射不完整。")
        }
    }

    private func removeLegacyWrapperImages(dockerPath: String) async {
        for containerName in Self.legacyServerContainerNames {
            do {
                let result = try await runner.run(
                    executablePath: dockerPath,
                    arguments: runtime.dockerArguments(["rm", "-f", containerName]),
                    environment: runtime.runtimeEnvironment
                )
                if result.succeeded {
                    DiagnosticLog.append("[WrapperServer] removed legacy container=\(containerName)")
                }
            } catch {
                DiagnosticLog.append("[WrapperServer] legacy container cleanup failed container=\(containerName) error=\(error.localizedDescription)")
            }
        }

        for legacyImageName in image.legacyImageNames {
            do {
                let result = try await runner.run(
                    executablePath: dockerPath,
                    arguments: runtime.dockerArguments(["image", "rm", "-f", legacyImageName]),
                    environment: runtime.runtimeEnvironment
                )
                if result.succeeded {
                    DiagnosticLog.append("[WrapperServer] removed legacy image=\(legacyImageName)")
                }
            } catch {
                DiagnosticLog.append("[WrapperServer] legacy image cleanup failed image=\(legacyImageName) error=\(error.localizedDescription)")
            }
        }
    }

    private func removeWrapperServerContainer(dockerPath: String) async throws {
        let result = try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["rm", "-f", Self.serverContainerName]),
            environment: runtime.runtimeEnvironment
        )
        guard result.succeeded || result.standardError.localizedCaseInsensitiveContains("No such container") else {
            throw ProcessRunnerError.processFailed(
                result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
        DiagnosticLog.append("[WrapperServer] removed existing service container before managed image start")
    }

    private func dataDirectory(in runtimeDirectory: URL) -> URL {
        runtimeDirectory.appendingPathComponent("rootfs/data", isDirectory: true)
    }

    private var loginCompletedMarkerURL: URL {
        runtimeManager.wrapperDataDirectory.appendingPathComponent(".login-completed")
    }

    public func clearAuthenticationState() throws {
        if FileManager.default.fileExists(atPath: loginCompletedMarkerURL.path) {
            try FileManager.default.removeItem(at: loginCompletedMarkerURL)
        }
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
