import Foundation

public final class MediaExtractionService {
    private let runner: ProcessRunner
    private let dependencyManager: DependencyManager

    public init(runner: ProcessRunner = ProcessRunner(), dependencyManager: DependencyManager = DependencyManager()) {
        self.runner = runner
        self.dependencyManager = dependencyManager
    }

    public func extractAudio(from jobs: [JobRequest]) async -> ConversionSummary {
        var successCount = 0
        var failureCount = 0
        var messages: [String] = []

        let ffmpeg = await dependencyManager.check(.ffmpeg)
        guard let ffmpegPath = ffmpeg.resolvedPath else {
            return ConversionSummary(successCount: 0, failureCount: jobs.count, messages: ["未找到 ffmpeg，请先在组件设置中安装运行时工具。"])
        }

        for job in jobs {
            guard job.category == .video else {
                failureCount += 1
                messages.append("跳过非视频文件：\(job.fileURL.lastPathComponent)")
                continue
            }

            do {
                guard let codec = try await detectAudioCodec(ffmpegPath: ffmpegPath, inputURL: job.fileURL) else {
                    failureCount += 1
                    messages.append("未能识别音频编码：\(job.fileURL.lastPathComponent)")
                    continue
                }

                guard let outputURL = outputURL(for: job.fileURL, codec: codec) else {
                    failureCount += 1
                    messages.append("未能识别音频编码：\(job.fileURL.lastPathComponent)")
                    continue
                }

                let result = try await runner.run(
                    executablePath: ffmpegPath,
                    arguments: ["-i", job.fileURL.path, "-c:a", "copy", "-map_metadata", "0", "-vn", "-y", outputURL.path]
                )

                if result.succeeded {
                    successCount += 1
                } else {
                    failureCount += 1
                    messages.append(result.standardError.isEmpty ? "提取失败：\(job.fileURL.lastPathComponent)" : result.standardError)
                }
            } catch {
                failureCount += 1
                messages.append(error.localizedDescription)
            }
        }

        return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
    }

    private func detectAudioCodec(ffmpegPath: String, inputURL: URL) async throws -> String? {
        let result = try await runner.run(executablePath: ffmpegPath, arguments: ["-i", inputURL.path])
        let probeText = result.standardError + "\n" + result.standardOutput
        guard let audioRange = probeText.range(of: #"Audio:\s*([^,\s]+)"#, options: .regularExpression) else {
            return nil
        }

        let match = String(probeText[audioRange])
        return match
            .replacingOccurrences(of: "Audio:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first
    }

    private func outputURL(for inputURL: URL, codec: String) -> URL? {
        let normalized = codec.lowercased()
        let outputExtension: String

        switch normalized {
        case "aac":
            outputExtension = "m4a"
        case "vorbis", "opus":
            outputExtension = "ogg"
        case "mp3":
            outputExtension = "mp3"
        case "flac":
            outputExtension = "flac"
        case "ac-3", "ac3":
            outputExtension = "ac3"
        default:
            outputExtension = normalized
        }

        guard !outputExtension.isEmpty else {
            return nil
        }

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let name = ["aac", "vorbis", "opus", "mp3", "flac", "ac-3", "ac3"].contains(normalized) ? baseName : "\(baseName)_audio"
        return inputURL.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(outputExtension)
    }
}
