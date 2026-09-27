import Foundation

public struct ConversionSummary: Codable, Equatable, Sendable {
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

    public func convert(
        _ jobs: [JobRequest],
        progressHandler: (@Sendable (JobRequest, JobProgressPhase, String?) -> Void)? = nil
    ) async -> ConversionSummary {
        var successCount = 0
        var failureCount = 0
        var messages: [String] = []

        let ffmpeg = await dependencyManager.check(.ffmpeg)
        guard let ffmpegPath = ffmpeg.resolvedPath else {
            jobs.forEach { progressHandler?($0, .failed, "未找到 ffmpeg") }
            return ConversionSummary(successCount: 0, failureCount: jobs.count, messages: ["未找到 ffmpeg，请先在组件设置中安装运行时工具。"])
        }

        for job in jobs {
            progressHandler?(job, .running, nil)

            guard case .transcode(let preset) = job.operation else {
                failureCount += 1
                let message = "跳过不支持的任务：\(job.fileURL.lastPathComponent)"
                messages.append(message)
                progressHandler?(job, .failed, message)
                continue
            }

            let access = job.startAccessingSecurityScopedResources()
            defer { access.stopAccessing() }

            let outputURL = preset.outputURL(for: access.fileURL)
            DiagnosticLog.append(
                "[AUDIO-DIAG] access file=\(access.fileURL.path) scopeDirectory=\(access.directoryURL?.path ?? "<none>") activeDirectoryScope=\(access.hasActiveDirectorySecurityScope) output=\(outputURL.path)"
            )
            let probe = (preset.needsInputAudioChannelCount || preset.supportsEmbeddedCover)
                ? await probeInput(ffmpegPath: ffmpegPath, fileURL: access.fileURL) : nil
            let inputAudioChannelCount = preset.needsInputAudioChannelCount
                ? probe.flatMap(Self.inputAudioChannelCount(from:)) : nil
            let arguments = preset.ffmpegArguments(
                inputURL: access.fileURL,
                outputURL: outputURL,
                inputAudioChannelCount: inputAudioChannelCount
            )

            do {
                try DirectoryAccess.ensureWritableDirectory(outputURL.deletingLastPathComponent())
                if preset.supportsEmbeddedCover, let probe {
                    let cover = Self.firstSupportedCover(from: probe)
                    if let cover {
                        do {
                            try await convertWithCover(
                                ffmpegPath: ffmpegPath, inputURL: access.fileURL, outputURL: outputURL,
                                preset: preset, inputAudioChannelCount: inputAudioChannelCount, cover: cover
                            )
                            successCount += 1
                            progressHandler?(job, .succeeded, nil)
                            continue
                        } catch {
                            DiagnosticLog.append("[AUDIO-DIAG] cover omitted output=\(outputURL.path) reason=\(diagnosticExcerpt(error.localizedDescription))")
                        }
                    } else if Self.hasAttachedPicture(in: probe) {
                        DiagnosticLog.append("[AUDIO-DIAG] cover omitted output=\(outputURL.path) reason=unsupported attached picture codec")
                    }
                }
                let result = try await runner.run(executablePath: ffmpegPath, arguments: arguments)
                DiagnosticLog.append(
                    "[AUDIO-DIAG] ffmpeg exit=\(result.exitCode) output=\(outputURL.path) stderr=\(diagnosticExcerpt(result.standardError))"
                )
                if result.succeeded {
                    successCount += 1
                    progressHandler?(job, .succeeded, nil)
                } else {
                    failureCount += 1
                    let message = result.standardError.isEmpty ? "转换失败：\(job.fileURL.lastPathComponent)" : result.standardError
                    messages.append(message)
                    progressHandler?(job, .failed, message)
                }
            } catch {
                failureCount += 1
                messages.append(error.localizedDescription)
                progressHandler?(job, .failed, error.localizedDescription)
            }
        }

        return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
    }

    private func probeInput(ffmpegPath: String, fileURL: URL) async -> String? {
        let result = try? await runner.run(executablePath: ffmpegPath, arguments: ["-hide_banner", "-i", fileURL.path])
        return result.map { $0.standardError + "\n" + $0.standardOutput }
    }

    struct Cover: Equatable {
        let streamIndex: Int
        let mimeType: String
    }

    static func hasAttachedPicture(in probe: String) -> Bool {
        probe.components(separatedBy: .newlines).contains { $0.contains("Video:") && $0.contains("attached pic") }
    }

    static func firstSupportedCover(from probe: String) -> Cover? {
        let pattern = #"Stream #0:(\d+).*Video: (mjpeg|png)(?:[,\s]|$).*attached pic"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in probe.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let indexRange = Range(match.range(at: 1), in: line),
                  let codecRange = Range(match.range(at: 2), in: line),
                  let index = Int(line[indexRange]) else { continue }
            return Cover(streamIndex: index, mimeType: line[codecRange] == "png" ? "image/png" : "image/jpeg")
        }
        return nil
    }

    private func convertWithCover(
        ffmpegPath: String, inputURL: URL, outputURL: URL, preset: ConversionPreset,
        inputAudioChannelCount: Int?, cover: Cover
    ) async throws {
        let temporaryOutput = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(preset.outputExtension)")
        let metadataURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).ffmeta")
        let imageURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).img")
        defer {
            try? FileManager.default.removeItem(at: temporaryOutput)
            try? FileManager.default.removeItem(at: metadataURL)
            try? FileManager.default.removeItem(at: imageURL)
        }

        if preset.storesCoverAsPictureMetadata {
            let imageResult = try await runner.run(executablePath: ffmpegPath, arguments: [
                "-i", inputURL.path, "-map", "0:\(cover.streamIndex)", "-c:v", "copy",
                "-f", "image2pipe", "-y", imageURL.path
            ])
            guard imageResult.succeeded else { throw CoverError.stepFailed("image extraction", imageResult.standardError) }
            let image = try Data(contentsOf: imageURL)
            guard Self.isExpectedImage(image, mimeType: cover.mimeType) else { throw CoverError.invalidImage }
            let metadataResult = try await runner.run(executablePath: ffmpegPath, arguments: [
                "-i", inputURL.path, "-f", "ffmetadata", "-y", metadataURL.path
            ])
            guard metadataResult.succeeded else { throw CoverError.stepFailed("metadata extraction", metadataResult.standardError) }
            let sourceMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
            guard sourceMetadata.hasPrefix(";FFMETADATA1\n") else { throw CoverError.invalidMetadata }
            let picture = Self.pictureBlock(image: image, mimeType: cover.mimeType).base64EncodedString()
            let metadata = ";FFMETADATA1\nMETADATA_BLOCK_PICTURE=\(picture)\n" + sourceMetadata.dropFirst(";FFMETADATA1\n".count)
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        }

        let arguments = preset.ffmpegArguments(
            inputURL: inputURL, outputURL: temporaryOutput, inputAudioChannelCount: inputAudioChannelCount,
            coverStreamIndex: preset.storesCoverAsPictureMetadata ? nil : cover.streamIndex,
            pictureMetadataURL: preset.storesCoverAsPictureMetadata ? metadataURL : nil
        )
        let result = try await runner.run(executablePath: ffmpegPath, arguments: arguments)
        guard result.succeeded else { throw CoverError.stepFailed("mux", result.standardError) }
        if !preset.storesCoverAsPictureMetadata {
            guard let outputProbe = await probeInput(ffmpegPath: ffmpegPath, fileURL: temporaryOutput),
                  Self.hasAttachedPicture(in: outputProbe) else { throw CoverError.missingOutputCover }
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryOutput)
        } else {
            try FileManager.default.moveItem(at: temporaryOutput, to: outputURL)
        }
    }

    private static func isExpectedImage(_ image: Data, mimeType: String) -> Bool {
        if mimeType == "image/png" { return image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) }
        return image.starts(with: [0xFF, 0xD8, 0xFF])
    }

    static func pictureBlock(image: Data, mimeType: String) -> Data {
        var block = Data()
        func append(_ value: UInt32) {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { block.append(contentsOf: $0) }
        }
        let mime = Data(mimeType.utf8)
        append(3)
        append(UInt32(mime.count)); block.append(mime)
        append(0) // description
        for _ in 0..<4 { append(0) } // width, height, depth, colors
        append(UInt32(image.count)); block.append(image)
        return block
    }

    private enum CoverError: LocalizedError {
        case stepFailed(String, String)
        case invalidImage
        case invalidMetadata
        case missingOutputCover

        var errorDescription: String? {
            switch self {
            case .stepFailed(let step, let detail): return "\(step): \(detail)"
            case .invalidImage: return "extracted image signature does not match its codec"
            case .invalidMetadata: return "ffmetadata header is missing"
            case .missingOutputCover: return "muxer did not retain the attached picture"
            }
        }
    }

    static func inputAudioChannelCount(from probeOutput: String) -> Int? {
        guard let audioLine = probeOutput
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("Audio:") })
        else {
            return nil
        }

        let lowercasedLine = audioLine.lowercased()
        if lowercasedLine.contains(", mono,") { return 1 }
        if lowercasedLine.contains(", stereo,") { return 2 }

        let patterns = [
            #",\s*(\d+)\.(\d)(?:\([^)]+\))?\s*,"#,
            #",\s*(\d+)\s+channels\s*,"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lowercasedLine, range: NSRange(lowercasedLine.startIndex..., in: lowercasedLine)),
                  let mainRange = Range(match.range(at: 1), in: lowercasedLine),
                  let mainChannels = Int(lowercasedLine[mainRange])
            else {
                continue
            }

            if match.numberOfRanges > 2,
               let subRange = Range(match.range(at: 2), in: lowercasedLine),
               let subChannels = Int(lowercasedLine[subRange]) {
                return mainChannels + subChannels
            }
            return mainChannels
        }

        return nil
    }

    private func diagnosticExcerpt(_ value: String, limit: Int = 800) -> String {
        guard !value.isEmpty else { return "<empty>" }
        let normalized = value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count > limit ? "…\(normalized.suffix(limit))" : normalized
    }
}
