import CFNetwork
import Darwin
import Foundation

/// The QEMU process is owned by the Runtime Worker. Only a PID plus its kernel
/// start time is persisted; credentials and guest serial output stay in memory.
final class AppleMusicQEMUProcess {
    private static let login = QEMULoginSession()
    private static let statusSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0
        ]
        return URLSession(configuration: configuration)
    }()
    private let runtimeManager: AppleMusicRuntimeManager
    private let fileManager = FileManager.default

    init(runtimeManager: AppleMusicRuntimeManager) {
        self.runtimeManager = runtimeManager
    }

    private var identityURL: URL { runtimeManager.rootURL.appendingPathComponent("qemu-process.json") }
    private var markerURL: URL { runtimeManager.wrapperDataDirectory.appendingPathComponent(".qemu-login-completed") }
    private var argsURL: URL { runtimeManager.rootURL.appendingPathComponent("qemu-guest-args.txt") }

    func initialize(username: String, password: String, verificationCode: String?, useSystemProxy: Bool) async throws -> ProcessResult {
        try runtimeManager.ensureEnabledAndInstalled()
        guard !username.isEmpty, !password.isEmpty,
              !username.contains("\n"), !username.contains("\r"),
              !password.contains("\n"), !password.contains("\r") else {
            throw ProcessRunnerError.processFailed("账号或密码格式无效。")
        }
        guard verificationCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            throw ProcessRunnerError.processFailed("请在出现验证码提示后单独提交验证码。")
        }
        guard !fileManager.fileExists(atPath: markerURL.path) else {
            throw ProcessRunnerError.processFailed("Apple Music 初始化已完成，无需重复初始化。")
        }
        guard !Self.login.isRunning else {
            throw ProcessRunnerError.processFailed("Apple Music 登录正在进行。")
        }
        try stopServer()
        let proxy = useSystemProxy ? Self.systemProxyURL() : nil
        try writeGuestArguments(login: true, proxy: proxy)

        let input = Pipe()
        let output = Pipe()
        let process = configuredProcess()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        Self.login.attach(process: process, input: input.fileHandleForWriting, output: output.fileHandleForReading, markerURL: markerURL)
        do {
            var ready = false
            for _ in 0..<450 {
                if Self.login.isReadyForCredentials { ready = true; break }
                if !Self.login.isRunning { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard ready else {
                throw ProcessRunnerError.processFailed("wrapper-lite QEMU 未进入账号输入状态。")
            }
            try input.fileHandleForWriting.write(contentsOf: Data("\(username)\n\(password)\n".utf8))
        } catch {
            Self.login.stop()
            throw error
        }
        return ProcessResult(executableURL: runtimeManager.qemuURL, arguments: [], exitCode: 0, standardOutput: "", standardError: "")
    }

    func writeVerificationCode(_ code: String) throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            throw ProcessRunnerError.processFailed("验证码无效。")
        }
        try Self.login.writeCode(trimmed)
    }

    func loginStatus() -> AppleMusicWrapperLoginStatus {
        if fileManager.fileExists(atPath: markerURL.path) {
            return .init(phase: .authenticated, message: "初始化已完成")
        }
        guard runtimeManager.isEnabled else {
            return .init(phase: .notInitialized, message: "Apple Music 下载功能尚未启用")
        }
        return Self.login.status
    }

    func stopLoginAttempt() { Self.login.stop() }

    func clearAuthenticationState() throws {
        if fileManager.fileExists(atPath: markerURL.path) { try fileManager.removeItem(at: markerURL) }
    }

    func ensureServerRunning(useSystemProxy: Bool) async throws {
        try runtimeManager.ensureEnabledAndInstalled()
        guard loginStatus().isAuthenticated else {
            throw ProcessRunnerError.processFailed("Apple Music 尚未完成初始化。")
        }
        if let identity = recordedIdentity(), ProcessIdentity.running(identity.pid) == identity,
           await serverIsReady() {
            return
        }
        try stopServer()
        if await serverIsReady() {
            throw ProcessRunnerError.processFailed("12340 端口已被其他进程占用。")
        }
        try writeGuestArguments(login: false, proxy: useSystemProxy ? Self.systemProxyURL() : nil)
        let process = configuredProcess()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        guard let identity = ProcessIdentity.running(process.processIdentifier) else {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGTERM) }
            throw ProcessRunnerError.processFailed("无法确认 wrapper-lite QEMU 子进程身份。")
        }
        try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
        for _ in 0..<35 {
            if await serverIsReady() { return }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        try stopServer()
        throw ProcessRunnerError.processFailed("wrapper-lite QEMU 启动后未在 12340 提供已登录服务。")
    }

    func stop() throws {
        Self.login.stop()
        try stopServer()
    }

    private func stopServer() throws {
        if let identity = recordedIdentity() { try identity.terminateIfStillRunning() }
        if fileManager.fileExists(atPath: identityURL.path) { try fileManager.removeItem(at: identityURL) }
    }

    private func recordedIdentity() -> ProcessIdentity? {
        guard let data = try? Data(contentsOf: identityURL) else { return nil }
        return try? JSONDecoder().decode(ProcessIdentity.self, from: data)
    }

    private func serverIsReady() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:12340/status")!)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await Self.statusSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return false }
        return Self.statusIsReady(data)
    }

    static func statusIsReady(_ data: Data) -> Bool {
        guard let status = try? JSONDecoder().decode(QEMUStatus.self, from: data) else { return false }
        return status.code == 0 && !status.data.regions.isEmpty
    }

    private struct QEMUStatus: Decodable {
        let code: Int
        let data: Regions
        struct Regions: Decodable { let regions: [String] }
    }

    private func writeGuestArguments(login: Bool, proxy: URL?) throws {
        var arguments = login ? ["--login-stdin"] : []
        if let proxy { arguments += ["--proxy", proxy.absoluteString] }
        arguments += ["--base-dir", "/data", "--host", "0.0.0.0", "--port", "12340"]
        try (arguments.joined(separator: "\n") + "\n").write(to: argsURL, atomically: true, encoding: .utf8)
    }

    private func configuredProcess() -> Process {
        let qemu = runtimeManager.qemuDirectory
        let process = Process()
        process.executableURL = runtimeManager.qemuURL
        process.currentDirectoryURL = runtimeManager.qemuPackageDirectory
        process.arguments = Self.arguments(qemu: qemu, dataImage: runtimeManager.qemuDataImageURL, guestArgs: argsURL)
        var environment = ProcessInfo.processInfo.environment
        environment["QEMU_MODULE_DIR"] = qemu.appendingPathComponent("bin").path
        process.environment = environment
        return process
    }

    static func arguments(qemu: URL, dataImage: URL, guestArgs: URL) -> [String] {
        [
            "-L", qemu.appendingPathComponent("bin").path,
            "-accel", "tcg", "-cpu", "max", "-m", "512", "-smp", "2",
            "-kernel", qemu.appendingPathComponent("vmlinuz-lite-qemu").path,
            "-initrd", qemu.appendingPathComponent("lite-initramfs.cpio.gz").path,
            "-append", "console=ttyS0 quiet net.ifnames=0 biosdevname=0",
            "-display", "none", "-serial", "stdio", "-no-reboot",
            "-nic", "user,model=e1000,hostfwd=tcp:127.0.0.1:12340-:12340",
            "-drive", "file=\(dataImage.path),format=raw,if=virtio",
            "-fw_cfg", "name=opt/lite_args,file=\(guestArgs.path)"
        ]
    }

    private static func systemProxyURL() -> URL? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        for (enabled, hostKey, portKey) in [
            (kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort),
            (kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort)
        ] {
            guard (settings[enabled as String] as? NSNumber)?.boolValue == true,
                  var host = settings[hostKey as String] as? String,
                  let port = settings[portKey as String] as? NSNumber
            else { continue }
            if ["localhost", "127.0.0.1", "::1"].contains(host) { host = "10.0.2.2" }
            return URL(string: "http://\(host):\(port.intValue)")
        }
        return nil
    }
}

private final class QEMULoginSession {
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var phase: AppleMusicWrapperLoginPhase = .notInitialized
    private var tail = ""
    private var hasSubmittedCode = false
    private var readyForCredentials = false
    private var generation = 0

    var isRunning: Bool { lock.withLock { process?.isRunning == true } }
    var isReadyForCredentials: Bool { lock.withLock { readyForCredentials } }

    var status: AppleMusicWrapperLoginStatus {
        lock.withLock {
            if process?.isRunning == true {
                switch phase {
                case .waitingForVerificationCode: return .init(phase: phase, message: "已发送验证码，请输入后提交")
                case .verificationCodeSubmitted: return .init(phase: phase, message: "验证码已提交，正在验证")
                case .failed: return .init(phase: phase, message: "登录失败，可以重新初始化")
                default: return .init(phase: .starting, message: "正在登录并等待 Apple 响应")
                }
            }
            if phase == .notInitialized { return .init(phase: phase, message: "尚未初始化") }
            if phase == .authenticated { return .init(phase: phase, message: "初始化已完成") }
            return .init(phase: .failed, message: "登录失败，可以重新初始化")
        }
    }

    func attach(process: Process, input: FileHandle, output: FileHandle, markerURL: URL) {
        lock.withLock {
            self.process = process
            self.input = input
            self.phase = .starting
            self.tail = ""
            self.hasSubmittedCode = false
            self.readyForCredentials = false
            self.generation += 1
        }
        let currentGeneration = lock.withLock { generation }
        output.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.observe(String(decoding: data, as: UTF8.self), markerURL: markerURL, generation: currentGeneration)
        }
    }

    func writeCode(_ code: String) throws {
        let handle = try lock.withLock { () throws -> FileHandle in
            guard process?.isRunning == true, phase == .waitingForVerificationCode,
                  !hasSubmittedCode, let input else {
                throw ProcessRunnerError.processFailed("当前登录流程尚未等待验证码。")
            }
            hasSubmittedCode = true
            phase = .verificationCodeSubmitted
            return input
        }
        do {
            try handle.write(contentsOf: Data("\(code)\n".utf8))
        } catch {
            lock.withLock {
                hasSubmittedCode = false
                phase = .waitingForVerificationCode
            }
            throw error
        }
    }

    func stop() {
        let active = lock.withLock { () -> Process? in
            let active = process
            process = nil
            input = nil
            phase = .notInitialized
            tail = ""
            readyForCredentials = false
            generation += 1
            return active
        }
        if let active, active.isRunning { Darwin.kill(active.processIdentifier, SIGTERM) }
    }

    private func observe(_ chunk: String, markerURL: URL, generation: Int) {
        lock.lock()
        guard self.generation == generation else { lock.unlock(); return }
        let visible = tail + chunk
        tail = String(visible.suffix(128))
        if visible.contains("waiting for username and password on stdin") {
            readyForCredentials = true
        }
        if visible.contains("waiting for 2FA code on stdin") || visible.contains("2FA: true") {
            phase = hasSubmittedCode ? .verificationCodeSubmitted : .waitingForVerificationCode
        }
        if visible.contains("login failed") || visible.contains("auth error:") {
            phase = .failed
        }
        let completed = visible.contains("login complete, exiting")
        if completed {
            do {
                try Data().write(to: markerURL, options: .atomic)
                phase = .authenticated
            } catch {
                phase = .failed
            }
        }
        lock.unlock()
    }
}
