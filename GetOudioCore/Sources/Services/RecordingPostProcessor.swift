import Foundation

public struct RecordingPostProcessingOptions: Equatable, Sendable {
    public static let defaultSilenceThresholdDBFS = -50.0
    public static let defaultSilencePaddingMilliseconds = 150
    public static let normalizedPeakDBFS = -0.1

    public let trimsSilence: Bool
    public let normalizesPeak: Bool
    public let silenceThresholdDBFS: Double
    public let silencePaddingMilliseconds: Int

    public init(
        trimsSilence: Bool = false,
        normalizesPeak: Bool = false,
        silenceThresholdDBFS: Double = RecordingPostProcessingOptions.defaultSilenceThresholdDBFS,
        silencePaddingMilliseconds: Int = RecordingPostProcessingOptions.defaultSilencePaddingMilliseconds
    ) {
        self.trimsSilence = trimsSilence
        self.normalizesPeak = normalizesPeak
        self.silenceThresholdDBFS = min(max(silenceThresholdDBFS, -90), 0)
        self.silencePaddingMilliseconds = min(max(silencePaddingMilliseconds, 0), 1_000)
    }

    public var shouldProcess: Bool {
        trimsSilence || normalizesPeak
    }
}

public enum RecordingPostProcessingResult: Equatable, Sendable {
    case processed(stagingURL: URL)
    case keptOriginal(message: String?)
}

/// Offline processing for the recorder's own 24-bit PCM WAV/RF64 output.
/// It deliberately does not accept arbitrary media files or run in a realtime audio callback.
public final class RecordingPostProcessor {
    private static let headerSize = Int(RecordingWAVWriter.headerSize)
    private static let fullScale = 8_388_608.0
    private static let maximumSample = Int32(8_388_607)
    private static let minimumSample = Int32(-8_388_608)
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func process(
        recordingURL: URL,
        options: RecordingPostProcessingOptions
    ) -> RecordingPostProcessingResult {
        guard options.shouldProcess else {
            return .keptOriginal(message: nil)
        }

        let stagingURL = recordingURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(recordingURL.lastPathComponent).\(UUID().uuidString).processing")

        do {
            let format = try readFormat(at: recordingURL)
            let scan = try scan(recordingURL: recordingURL, format: format, thresholdDBFS: options.silenceThresholdDBFS)
            guard scan.peakSample > 0 else {
                return .keptOriginal(message: "检测到全程静音，已保留原始录音。")
            }

            let firstAudibleFrame: UInt64
            let lastAudibleFrame: UInt64
            if options.trimsSilence {
                guard let first = scan.firstAudibleFrame, let last = scan.lastAudibleFrame else {
                    return .keptOriginal(message: "检测到开头和末尾均低于静音阈值，已保留原始录音。")
                }
                firstAudibleFrame = first
                lastAudibleFrame = last
            } else {
                firstAudibleFrame = 0
                lastAudibleFrame = format.frameCount - 1
            }

            let paddingFrames = UInt64((Double(options.silencePaddingMilliseconds) * format.sampleRate / 1_000).rounded())
            let startFrame = options.trimsSilence ? firstAudibleFrame > paddingFrames ? firstAudibleFrame - paddingFrames : 0 : 0
            let endFrame: UInt64
            if options.trimsSilence {
                let exclusiveAudibleEnd = lastAudibleFrame + 1
                endFrame = min(format.frameCount, exclusiveAudibleEnd.addingReportingOverflow(paddingFrames).overflow ? format.frameCount : exclusiveAudibleEnd + paddingFrames)
            } else {
                endFrame = format.frameCount
            }

            let gain = options.normalizesPeak ? Self.normalizationGain(for: scan.peakSample) : 1
            try writeProcessedRecording(
                sourceURL: recordingURL,
                stagingURL: stagingURL,
                format: format,
                startFrame: startFrame,
                endFrame: endFrame,
                gain: gain
            )
            return .processed(stagingURL: stagingURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            return .keptOriginal(message: "录后处理失败，已保留原始录音：\(error.localizedDescription)")
        }
    }

    private func readFormat(at url: URL) throws -> RecordingFormat {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try readExactly(from: handle, count: Self.headerSize)

        let container = try header.ascii(at: 0, count: 4)
        guard (container == "RIFF" || container == "RF64"),
              try header.ascii(at: 8, count: 4) == "WAVE",
              try header.ascii(at: 48, count: 4) == "fmt ",
              header.uint32LE(at: 52) == 16,
              header.uint16LE(at: 56) == 1,
              try header.ascii(at: 72, count: 4) == "data",
              header.uint16LE(at: 70) == 24 else {
            throw ProcessingError.unsupportedRecording
        }

        let channelCount = Int(header.uint16LE(at: 58))
        let sampleRate = Double(header.uint32LE(at: 60))
        let frameByteCount = channelCount * 3
        let dataByteCount: UInt64
        if container == "RF64" {
            guard try header.ascii(at: 12, count: 4) == "ds64" else {
                throw ProcessingError.unsupportedRecording
            }
            dataByteCount = header.uint64LE(at: 28)
        } else {
            dataByteCount = UInt64(header.uint32LE(at: 76))
        }
        let fileSize = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard channelCount > 0,
              sampleRate > 0,
              frameByteCount > 0,
              dataByteCount % UInt64(frameByteCount) == 0,
              let fileSize,
              fileSize.uint64Value >= UInt64(Self.headerSize) + dataByteCount else {
            throw ProcessingError.unsupportedRecording
        }

        return RecordingFormat(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameByteCount: frameByteCount,
            dataByteCount: dataByteCount
        )
    }

    private func scan(
        recordingURL: URL,
        format: RecordingFormat,
        thresholdDBFS: Double
    ) throws -> RecordingScan {
        let threshold = Int32((pow(10, thresholdDBFS / 20) * Double(Self.maximumSample)).rounded())
        let handle = try FileHandle(forReadingFrom: recordingURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(Self.headerSize))

        var firstAudibleFrame: UInt64?
        var lastAudibleFrame: UInt64?
        var peakSample: Int32 = 0
        var frameIndex: UInt64 = 0
        let chunkByteCount = max(format.frameByteCount, 65_536 / format.frameByteCount * format.frameByteCount)

        while frameIndex < format.frameCount {
            let remainingFrames = format.frameCount - frameIndex
            let byteCount = min(UInt64(chunkByteCount), remainingFrames * UInt64(format.frameByteCount))
            let data = try readExactly(from: handle, count: Int(byteCount))

            for byteOffset in stride(from: 0, to: data.count, by: format.frameByteCount) {
                var frameIsSilent = true
                for channel in 0..<format.channelCount {
                    let sample = data.signed24LE(at: byteOffset + channel * 3)
                    let magnitude = Self.absoluteSample(sample)
                    peakSample = max(peakSample, magnitude)
                    if magnitude >= threshold {
                        frameIsSilent = false
                    }
                }
                if !frameIsSilent {
                    firstAudibleFrame = firstAudibleFrame ?? frameIndex
                    lastAudibleFrame = frameIndex
                }
                frameIndex += 1
            }
        }
        return RecordingScan(firstAudibleFrame: firstAudibleFrame, lastAudibleFrame: lastAudibleFrame, peakSample: peakSample)
    }

    private func writeProcessedRecording(
        sourceURL: URL,
        stagingURL: URL,
        format: RecordingFormat,
        startFrame: UInt64,
        endFrame: UInt64,
        gain: Double
    ) throws {
        guard startFrame < endFrame, endFrame <= format.frameCount else {
            throw ProcessingError.emptyOutput
        }
        let outputDataByteCount = (endFrame - startFrame) * UInt64(format.frameByteCount)
        let header = try RecordingWAVWriter.headerData(
            dataByteCount: outputDataByteCount,
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
        fileManager.createFile(atPath: stagingURL.path, contents: nil)
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle = try FileHandle(forWritingTo: stagingURL)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        try destinationHandle.write(contentsOf: header)
        try sourceHandle.seek(toOffset: UInt64(Self.headerSize) + startFrame * UInt64(format.frameByteCount))
        var remainingBytes = outputDataByteCount
        let chunkByteCount = max(format.frameByteCount, 65_536 / format.frameByteCount * format.frameByteCount)

        while remainingBytes > 0 {
            let byteCount = Int(min(UInt64(chunkByteCount), remainingBytes))
            var data = try readExactly(from: sourceHandle, count: byteCount)
            if gain != 1 {
                scale(&data, gain: gain)
            }
            try destinationHandle.write(contentsOf: data)
            remainingBytes -= UInt64(byteCount)
        }
        try destinationHandle.synchronize()

        let outputSize = try fileManager.attributesOfItem(atPath: stagingURL.path)[.size] as? NSNumber
        guard outputSize?.uint64Value == UInt64(Self.headerSize) + outputDataByteCount else {
            throw ProcessingError.outputVerificationFailed
        }
    }

    private func scale(_ data: inout Data, gain: Double) {
        for byteOffset in stride(from: 0, to: data.count, by: 3) {
            let sample = data.signed24LE(at: byteOffset)
            let scaled = Int64((Double(sample) * gain).rounded())
            let clamped = Int32(min(Int64(Self.maximumSample), max(Int64(Self.minimumSample), scaled)))
            data[byteOffset] = UInt8(truncatingIfNeeded: clamped)
            data[byteOffset + 1] = UInt8(truncatingIfNeeded: clamped >> 8)
            data[byteOffset + 2] = UInt8(truncatingIfNeeded: clamped >> 16)
        }
    }

    private static func normalizationGain(for peakSample: Int32) -> Double {
        let targetPeak = pow(10, RecordingPostProcessingOptions.normalizedPeakDBFS / 20) * fullScale
        return targetPeak / Double(peakSample)
    }

    private static func absoluteSample(_ sample: Int32) -> Int32 {
        sample == minimumSample ? maximumSample + 1 : abs(sample)
    }

    private func readExactly(from handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let next = try handle.read(upToCount: count - result.count), !next.isEmpty else {
                throw ProcessingError.truncatedRecording
            }
            result.append(next)
        }
        return result
    }
}

private struct RecordingFormat {
    let sampleRate: Double
    let channelCount: Int
    let frameByteCount: Int
    let dataByteCount: UInt64

    var frameCount: UInt64 {
        dataByteCount / UInt64(frameByteCount)
    }
}

private struct RecordingScan {
    let firstAudibleFrame: UInt64?
    let lastAudibleFrame: UInt64?
    let peakSample: Int32
}

private enum ProcessingError: LocalizedError {
    case unsupportedRecording
    case truncatedRecording
    case emptyOutput
    case outputVerificationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedRecording: return "录音文件不是受支持的 24-bit PCM WAV"
        case .truncatedRecording: return "录音文件不完整"
        case .emptyOutput: return "录后处理没有生成音频帧"
        case .outputVerificationFailed: return "录后处理成品校验失败"
        }
    }
}

private extension Data {
    func ascii(at offset: Int, count: Int) throws -> String {
        guard offset >= 0, count >= 0, offset + count <= self.count,
              let value = String(data: self[offset..<(offset + count)], encoding: .ascii) else {
            throw ProcessingError.unsupportedRecording
        }
        return value
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }

    func uint64LE(at offset: Int) -> UInt64 {
        UInt64(self[offset]) | UInt64(self[offset + 1]) << 8 | UInt64(self[offset + 2]) << 16 | UInt64(self[offset + 3]) << 24 |
            UInt64(self[offset + 4]) << 32 | UInt64(self[offset + 5]) << 40 | UInt64(self[offset + 6]) << 48 | UInt64(self[offset + 7]) << 56
    }

    func signed24LE(at offset: Int) -> Int32 {
        let value = Int32(self[offset]) | Int32(self[offset + 1]) << 8 | Int32(self[offset + 2]) << 16
        return value & 0x80_0000 == 0 ? value : value | ~0xFF_FFFF
    }
}
