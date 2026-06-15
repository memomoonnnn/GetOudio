import Foundation

public final class AppleMusicDownloadService {
    private let runner: ProcessRunner
    private let componentManager: BundledComponentManager
    private let dependencyManager: DependencyManager
    private let wrapperRuntime: AppleMusicWrapperRuntime
    private let settingsStore: SettingsStore

    public init(
        runner: ProcessRunner = ProcessRunner(),
        componentManager: BundledComponentManager = BundledComponentManager(),
        dependencyManager: DependencyManager = DependencyManager(),
        wrapperRuntime: AppleMusicWrapperRuntime = AppleMusicWrapperRuntime(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.runner = runner
        self.componentManager = componentManager
        self.dependencyManager = dependencyManager
        self.wrapperRuntime = wrapperRuntime
        self.settingsStore = settingsStore
    }

    public func download(_ jobs: [JobRequest]) async -> ConversionSummary {
        let downloadJobs = jobs.filter {
            if case .appleMusicDownload = $0.operation { return true }
            return false
        }

        guard !downloadJobs.isEmpty else {
            return ConversionSummary(successCount: 0, failureCount: 0, messages: ["没有 Apple Music 下载任务。"])
        }

        let gpac = await dependencyManager.check(.gpac)
        guard gpac.isInstalled else {
            return ConversionSummary(successCount: 0, failureCount: downloadJobs.count, messages: ["未找到 GPAC / MP4Box，请先在组件设置中安装运行时工具。"])
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

            for job in downloadJobs {
                let format = resolvedFormat(for: job)
                var arguments = format.downloaderArguments
                arguments += [job.fileURL.absoluteString]
                let result = try await runner.run(
                    executablePath: executableURL.path,
                    arguments: arguments,
                    currentDirectoryURL: workingDirectory
                )

                if result.succeeded {
                    successCount += 1
                } else {
                    failureCount += 1
                    messages.append(result.standardError.isEmpty ? result.standardOutput : result.standardError)
                }
            }

            return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
        } catch {
            return ConversionSummary(successCount: 0, failureCount: downloadJobs.count, messages: [error.localizedDescription])
        }
    }

    public func initializeWrapper(username: String, password: String, verificationCode: String?) async -> ConversionSummary {
        do {
            let result = try await wrapperRuntime.initialize(username: username, password: password, verificationCode: verificationCode)
            if result.succeeded {
                return ConversionSummary(successCount: 1, failureCount: 0, messages: [result.standardOutput])
            }

            return ConversionSummary(successCount: 0, failureCount: 1, messages: [result.standardError.isEmpty ? result.standardOutput : result.standardError])
        } catch {
            return ConversionSummary(successCount: 0, failureCount: 1, messages: [error.localizedDescription])
        }
    }

    public func submitWrapperVerificationCode(_ code: String) -> ConversionSummary {
        do {
            try wrapperRuntime.writeVerificationCode(code)
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

    private func prepareDownloaderWorkingDirectory(executableURL: URL, outputDirectory: URL) throws -> URL {
        let workingDirectory = try SharedContainer.directory()
            .appendingPathComponent("AppleMusicDownloader", isDirectory: true)
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
}
