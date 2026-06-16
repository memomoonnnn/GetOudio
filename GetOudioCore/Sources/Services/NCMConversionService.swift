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

    public func convert(
        _ jobs: [JobRequest],
        progressHandler: (@Sendable (JobRequest, JobProgressPhase, String?) -> Void)? = nil
    ) async -> ConversionSummary {
        let ncmJobs = jobs.filter { $0.category == .ncm }
        guard !ncmJobs.isEmpty else {
            return ConversionSummary(successCount: 0, failureCount: 0, messages: ["没有 NCM 文件需要转换。"])
        }

        var successCount = 0
        var failureCount = 0
        var messages: [String] = []

        do {
            let executableURL = try componentManager.executableURL(for: .ncmdump)

            for job in ncmJobs {
                progressHandler?(job, .running, nil)

                let access = job.startAccessingSecurityScopedResources()
                defer { access.stopAccessing() }

                let outputDirectory = try outputDirectory(for: job, access: access)
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

                let result = try await runner.run(
                    executablePath: executableURL.path,
                    arguments: ["-o", outputDirectory.path, access.fileURL.path]
                )

                if result.succeeded {
                    successCount += 1
                    progressHandler?(job, .succeeded, nil)
                } else {
                    failureCount += 1
                    let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
                    messages.append(message)
                    progressHandler?(job, .failed, message)
                }
            }

            return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
        } catch {
            ncmJobs.forEach { progressHandler?($0, .failed, error.localizedDescription) }
            return ConversionSummary(successCount: successCount, failureCount: ncmJobs.count - successCount, messages: [error.localizedDescription])
        }
    }

    private func outputDirectory(for job: JobRequest, access: ScopedJobAccess) throws -> URL {
        if settingsStore.ncmOutputMode == "customDirectory", let customURL = settingsStore.ncmCustomOutputURL {
            return customURL
        }

        if let directoryURL = access.directoryURL {
            return directoryURL
        }

        return job.fileURL.deletingLastPathComponent()
    }
}
