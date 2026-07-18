import Foundation

public final class AppleMusicDownloadService {
    private static let maxDownloadAttempts = 3

    private let runner: ProcessRunner
    private let componentManager: BundledComponentManager
    private let wrapperRuntime: AppleMusicWrapperRuntime
    private let runtimeManager: AppleMusicRuntimeManager
    private let settingsStore: SettingsStore
    private let agentClient: AppleMusicRuntimeAgentClient?
    private let useAgent: Bool

    public init(
        runner: ProcessRunner = ProcessRunner(),
        componentManager: BundledComponentManager = BundledComponentManager(),
        runtimeManager: AppleMusicRuntimeManager,
        wrapperRuntime: AppleMusicWrapperRuntime? = nil,
        settingsStore: SettingsStore,
        agentClient: AppleMusicRuntimeAgentClient? = nil,
        useAgent: Bool = true
    ) {
        self.runner = runner
        self.componentManager = componentManager
        self.runtimeManager = runtimeManager
        self.wrapperRuntime = wrapperRuntime ?? AppleMusicWrapperRuntime(
            runtimeManager: runtimeManager,
            settingsStore: settingsStore
        )
        self.settingsStore = settingsStore
        self.agentClient = agentClient
        self.useAgent = useAgent
    }

    public convenience init(
        container: SharedContainer,
        runner: ProcessRunner = ProcessRunner(),
        componentManager: BundledComponentManager = BundledComponentManager(),
        useAgent: Bool = true
    ) {
        let settingsStore = SettingsStore(container: container)
        let runtimeManager = AppleMusicRuntimeManager(container: container)
        self.init(
            runner: runner,
            componentManager: componentManager,
            runtimeManager: runtimeManager,
            settingsStore: settingsStore,
            agentClient: AppleMusicRuntimeAgentClient(container: container),
            useAgent: useAgent
        )
    }

    public func download(_ jobs: [JobRequest]) async -> ConversionSummary {
        if useAgent {
            do {
                guard let agentClient else {
                    throw ProcessRunnerError.processFailed("Downloader Runtime Agent client is not configured.")
                }
                return try await agentClient.download(jobs)
            } catch {
                return ConversionSummary(successCount: 0, failureCount: jobs.count, messages: [error.localizedDescription])
            }
        }

        return await downloadDirect(jobs)
    }

    public func initializeWrapper(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool
    ) async -> ConversionSummary {
        if useAgent {
            do {
                guard let agentClient else {
                    throw ProcessRunnerError.processFailed("Downloader Runtime Agent client is not configured.")
                }
                return try await agentClient.initializeWrapper(
                    username: username,
                    password: password,
                    verificationCode: verificationCode,
                    useSystemProxy: useSystemProxy
                )
            } catch {
                return ConversionSummary(successCount: 0, failureCount: 1, messages: [error.localizedDescription])
            }
        }

        return await initializeWrapperDirect(
            username: username,
            password: password,
            verificationCode: verificationCode,
            useSystemProxy: useSystemProxy
        )
    }

    public func submitWrapperVerificationCode(_ code: String) async -> ConversionSummary {
        if useAgent {
            do {
                guard let agentClient else {
                    throw ProcessRunnerError.processFailed("Downloader Runtime Agent client is not configured.")
                }
                return try await agentClient.submitVerificationCode(code)
            } catch {
                return ConversionSummary(successCount: 0, failureCount: 1, messages: [error.localizedDescription])
            }
        }

        return await submitWrapperVerificationCodeDirect(code)
    }

    private func downloadDirect(_ jobs: [JobRequest]) async -> ConversionSummary {
        let downloadJobs = jobs.filter {
            if case .appleMusicDownload = $0.operation { return true }
            return false
        }

        guard !downloadJobs.isEmpty else {
            return ConversionSummary(successCount: 0, failureCount: 0, messages: ["没有 Apple Music 下载任务。"])
        }

        do {
            try runtimeManager.ensureEnabledAndInstalled()
        } catch {
            return ConversionSummary(successCount: 0, failureCount: downloadJobs.count, messages: [error.localizedDescription])
        }

        do {
            try await wrapperRuntime.ensureServerRunning()
            let executableURL = try componentManager.executableURL(for: .appleMusicDownloader)
            let outputDirectory = settingsStore.appleMusicOutputURL
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let workingDirectory = try prepareDownloaderWorkingDirectory(
                executableURL: executableURL,
                outputDirectory: outputDirectory
            )

            var successCount = 0
            var failureCount = 0
            var messages: [String] = []
            agentClient?.clearDownloadCancellation()
            defer { agentClient?.clearDownloadCancellation() }

            for job in downloadJobs {
                let format = resolvedFormat(for: job)
                let arguments = Self.downloaderArguments(for: job, format: format)
                var lastFailureMessage = ""
                var completed = false

                for attempt in 1...Self.maxDownloadAttempts {
                    if agentClient?.isDownloadCancellationRequested() == true {
                        lastFailureMessage = "Apple Music 下载已由用户停止。"
                        break
                    }

                    let prefix = attempt == 1
                        ? "正在准备 Apple Music 下载..."
                        : "检测到下载流中断，正在重试 \(attempt - 1)/\(Self.maxDownloadAttempts - 1)..."
                    writeDownloadProgress(prefix, active: true)
                    let progressTracker = AppleMusicDownloaderProgressTracker()
                    let result = try await runner.run(
                        executablePath: executableURL.path,
                        arguments: arguments,
                        currentDirectoryURL: workingDirectory,
                        environment: runtimeManager.runtimeEnvironment(),
                        outputHandler: { _, chunk in
                            guard let message = progressTracker.observe(chunk) else { return }
                            self.writeDownloadProgress(message, active: true)
                        },
                        shouldTerminate: {
                            self.agentClient?.isDownloadCancellationRequested() == true
                        }
                    )

                    let rawMessage = result.standardError.isEmpty ? result.standardOutput : result.standardError
                    if result.succeeded {
                        successCount += 1
                        writeDownloadProgress("Apple Music 下载完成", completed: 1, active: false)
                        completed = true
                        break
                    }

                    if agentClient?.isDownloadCancellationRequested() == true {
                        lastFailureMessage = AppleMusicDownloadMessageFormatter.coreMessage(from: rawMessage)
                        if lastFailureMessage.isEmpty {
                            lastFailureMessage = "Apple Music 下载已由用户停止。"
                        } else {
                            lastFailureMessage = "Apple Music 下载已由用户停止。\n\(lastFailureMessage)"
                        }
                        break
                    }

                    lastFailureMessage = AppleMusicDownloadMessageFormatter.coreMessage(from: rawMessage)
                    if Self.shouldRetryDownload(after: rawMessage), attempt < Self.maxDownloadAttempts {
                        DiagnosticLog.append("Apple Music download retry \(attempt) for \(job.fileURL.absoluteString): \(lastFailureMessage)")
                        continue
                    }
                    break
                }

                if !completed {
                    failureCount += 1
                    messages.append(lastFailureMessage.isEmpty ? "Apple Music 下载失败。" : lastFailureMessage)
                    let finalMessage = agentClient?.isDownloadCancellationRequested() == true
                        ? "Apple Music 下载已停止"
                        : "Apple Music 下载失败"
                    writeDownloadProgress(finalMessage, completed: 1, active: false)
                }
            }

            return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
        } catch {
            writeDownloadProgress("Apple Music 下载失败：\(error.localizedDescription)", completed: 1, active: false)
            return ConversionSummary(successCount: 0, failureCount: downloadJobs.count, messages: [error.localizedDescription])
        }
    }

    private func initializeWrapperDirect(
        username: String,
        password: String,
        verificationCode: String?,
        useSystemProxy: Bool
    ) async -> ConversionSummary {
        do {
            try runtimeManager.ensureEnabledAndInstalled()
            let result = try await wrapperRuntime.initialize(
                username: username,
                password: password,
                verificationCode: verificationCode,
                useSystemProxy: useSystemProxy
            )
            if result.succeeded {
                return ConversionSummary(
                    successCount: 1,
                    failureCount: 0,
                    messages: ["登录容器已启动；收到双重认证验证码后请立即提交。"]
                )
            }

            return ConversionSummary(successCount: 0, failureCount: 1, messages: [result.standardError.isEmpty ? result.standardOutput : result.standardError])
        } catch {
            return ConversionSummary(successCount: 0, failureCount: 1, messages: [error.localizedDescription])
        }
    }

    private func submitWrapperVerificationCodeDirect(_ code: String) async -> ConversionSummary {
        do {
            try runtimeManager.ensureEnabledAndInstalled()
            let status = await wrapperRuntime.loginStatus()
            guard status.canSubmitVerificationCode else {
                throw ProcessRunnerError.processFailed(
                    status.isAuthenticated ? "Apple Music 初始化已完成。" : "当前登录流程尚未等待验证码。"
                )
            }
            try wrapperRuntime.writeVerificationCode(code)
            Task {
                await wrapperRuntime.logLoginDiagnostics(stage: "2fa-submitted")
            }
            return ConversionSummary(successCount: 1, failureCount: 0, messages: ["验证码已写入 2fa.txt"])
        } catch {
            return ConversionSummary(successCount: 0, failureCount: 1, messages: [error.localizedDescription])
        }
    }

    private func resolvedFormat(for job: JobRequest) -> AppleMusicDownloadFormat {
        if case .appleMusicDownload(let format) = job.operation, let format, format != .askEveryTime {
            return format
        }

        let stored = settingsStore.appleMusicDownloadFormat
        return stored == .askEveryTime ? .alac : stored
    }

    static func downloaderArguments(for job: JobRequest, format: AppleMusicDownloadFormat) -> [String] {
        var arguments = format.downloaderArguments
        if shouldDownloadAsSingleSong(job.fileURL) {
            arguments.append("--song")
        }
        arguments.append(job.fileURL.absoluteString)
        return arguments
    }

    static func shouldDownloadAsSingleSong(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains {
            $0.name == "i" && ($0.value?.isEmpty == false)
        } == true
    }

    private static func shouldRetryDownload(after message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("decode mdat")
            || lowercased.contains("read box body length")
            || lowercased.contains("unexpected eof")
            || lowercased.contains("connection reset")
            || lowercased.contains("response timed out")
    }

    private func prepareDownloaderWorkingDirectory(executableURL: URL, outputDirectory: URL) throws -> URL {
        let workingDirectory = runtimeManager.downloaderWorkDirectory
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let templateURL = executableURL.deletingLastPathComponent().appendingPathComponent("config.yaml.template")
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        let config = renderDownloaderConfig(template: template, outputDirectory: outputDirectory)
        try config.write(
            to: workingDirectory.appendingPathComponent("config.yaml"),
            atomically: true,
            encoding: .utf8
        )

        return workingDirectory
    }

    private func renderDownloaderConfig(template: String, outputDirectory: URL) -> String {
        let outputPath = yamlQuoted(outputDirectory.path)
        let replacements = [
            "alac-save-folder": outputPath,
            "atmos-save-folder": outputPath,
            "aac-save-folder": outputPath,
            "mv-save-folder": outputPath,
            "exit-on-error": "true"
        ]

        let lines = template.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let key = replacements.keys.first(where: { trimmed.hasPrefix("\($0):") }) else {
                return line
            }
            return "\(key): \(replacements[key]!)"
        }.joined(separator: "\n")
    }

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func writeDownloadProgress(
        _ message: String,
        completed: Int = 0,
        active: Bool
    ) {
        do {
            let progress = AppleMusicRuntimeProgress(
                message: message,
                completedUnitCount: completed,
                totalUnitCount: 1,
                isActive: active
            )
            guard let progressURL = agentClient?.progressURL() else { return }
            let directory = progressURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(progress).write(
                to: progressURL,
                options: .atomic
            )
        } catch {
            DiagnosticLog.append("Apple Music download progress write failed: \(error.localizedDescription)")
        }
    }
}
