import Foundation

public final class NCMConversionService {
    private let runner: ProcessRunner
    private let componentManager: BundledComponentManager
    private let settingsStore: SettingsStore

    public init(
        runner: ProcessRunner = ProcessRunner(),
        componentManager: BundledComponentManager = BundledComponentManager(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.runner = runner
        self.componentManager = componentManager
        self.settingsStore = settingsStore
    }

    public func convert(_ jobs: [JobRequest]) async -> ConversionSummary {
        let ncmJobs = jobs.filter { $0.category == .ncm }
        guard !ncmJobs.isEmpty else {
            return ConversionSummary(successCount: 0, failureCount: 0, messages: ["没有 NCM 文件需要转换。"])
        }

        do {
            let executableURL = try componentManager.executableURL(for: .ncmdump)
            let outputDirectory = try outputDirectory(for: ncmJobs)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            var arguments = ncmJobs.map(\.fileURL.path)
            arguments += ["-o", outputDirectory.path]

            let result = try await runner.run(executablePath: executableURL.path, arguments: arguments)
            if result.succeeded {
                return ConversionSummary(successCount: ncmJobs.count, failureCount: 0, messages: [])
            }

            return ConversionSummary(
                successCount: 0,
                failureCount: ncmJobs.count,
                messages: [result.standardError.isEmpty ? result.standardOutput : result.standardError]
            )
        } catch {
            return ConversionSummary(successCount: 0, failureCount: ncmJobs.count, messages: [error.localizedDescription])
        }
    }

    private func outputDirectory(for jobs: [JobRequest]) throws -> URL {
        if settingsStore.ncmOutputMode == "customDirectory", let customURL = settingsStore.ncmCustomOutputURL {
            return customURL
        }

        guard let first = jobs.first else {
            throw ProcessRunnerError.executableNotFound("NCM input")
        }

        return first.fileURL.deletingLastPathComponent()
    }
}

