import Foundation

public struct ConversionSummary: Equatable, Sendable {
    public var successCount: Int
    public var failureCount: Int
    public var messages: [String]

    public var totalCount: Int { successCount + failureCount }

    public init(successCount: Int, failureCount: Int, messages: [String]) {
        self.successCount = successCount
        self.failureCount = failureCount
        self.messages = messages
    }
}

public final class AudioConversionService {
    private let runner: ProcessRunner
    private let dependencyManager: DependencyManager

    public init(runner: ProcessRunner = ProcessRunner(), dependencyManager: DependencyManager = DependencyManager()) {
        self.runner = runner
        self.dependencyManager = dependencyManager
    }

    public func convert(_ jobs: [JobRequest]) async -> ConversionSummary {
        var successCount = 0
        var failureCount = 0
        var messages: [String] = []

        let ffmpeg = await dependencyManager.check(.ffmpeg)
        guard let ffmpegPath = ffmpeg.resolvedPath else {
            return ConversionSummary(successCount: 0, failureCount: jobs.count, messages: ["未找到 ffmpeg，请先在组件设置中安装运行时工具。"])
        }

        for job in jobs {
            guard case .transcode(let preset) = job.operation else {
                failureCount += 1
                messages.append("跳过不支持的任务：\(job.fileURL.lastPathComponent)")
                continue
            }

            let access = job.startAccessingSecurityScopedResources()
            defer { access.stopAccessing() }

            let outputURL = preset.outputURL(for: access.fileURL)
            let arguments = preset.ffmpegArguments(inputURL: access.fileURL, outputURL: outputURL)

            do {
                let result = try await runner.run(executablePath: ffmpegPath, arguments: arguments)
                if result.succeeded {
                    successCount += 1
                } else {
                    failureCount += 1
                    messages.append(result.standardError.isEmpty ? "转换失败：\(job.fileURL.lastPathComponent)" : result.standardError)
                }
            } catch {
                failureCount += 1
                messages.append(error.localizedDescription)
            }
        }

        return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
    }
}
