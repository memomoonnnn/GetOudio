import Foundation

public final class RecordingWAVWriter {
    public enum WriterError: Error {
        case invalidFormat
        case closed
    }

    public static let headerSize: UInt64 = 80

    public let url: URL
    public let sampleRate: Double
    public let channelCount: Int

    private let handle: FileHandle
    private var dataByteCount: UInt64 = 0
    private var randomState: UInt64 = 0x9E3779B97F4A7C15
    private var isClosed = false

    public init(url: URL, sampleRate: Double, channelCount: Int) throws {
        guard sampleRate > 0, channelCount > 0 else { throw WriterError.invalidFormat }
        self.url = url
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        FileManager.default.createFile(atPath: url.path, contents: Data(count: Int(Self.headerSize)))
        handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: Self.headerSize)
    }

    /// Writes non-interleaved Float32 PCM. This method is intended for a background writer queue.
    public func write(planarSamples: UnsafePointer<Float>, frameCount: Int, planeStride: Int) throws {
        guard !isClosed else { throw WriterError.closed }
        guard frameCount >= 0, planeStride >= frameCount else { throw WriterError.invalidFormat }

        var data = Data(capacity: frameCount * channelCount * 3)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let rawSample = planarSamples[channel * planeStride + frame]
                let sample = rawSample.isFinite ? rawSample : 0
                let dither = nextUnitRandom() - nextUnitRandom()
                let scaled = Double(sample) * 8_388_608.0 + dither
                let value = Int32(max(-8_388_608, min(8_388_607, Int64(scaled.rounded()))))
                data.append(UInt8(truncatingIfNeeded: value))
                data.append(UInt8(truncatingIfNeeded: value >> 8))
                data.append(UInt8(truncatingIfNeeded: value >> 16))
            }
        }
        try handle.write(contentsOf: data)
        dataByteCount += UInt64(data.count)
    }

    public func finalize() throws {
        guard !isClosed else { return }
        try handle.synchronize()
        try Self.patchHeader(
            handle: handle,
            dataByteCount: dataByteCount,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        try handle.close()
        isClosed = true
    }

    public static func recover(url: URL, sampleRate: Double, channelCount: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= headerSize else { throw WriterError.invalidFormat }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try patchHeader(
            handle: handle,
            dataByteCount: fileSize - headerSize,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        try handle.synchronize()
    }

    private static func patchHeader(
        handle: FileHandle,
        dataByteCount: UInt64,
        sampleRate: Double,
        channelCount: Int
    ) throws {
        let header = try headerData(
            dataByteCount: dataByteCount,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
    }

    static func headerData(
        dataByteCount: UInt64,
        sampleRate: Double,
        channelCount: Int
    ) throws -> Data {
        let frameSize = UInt64(channelCount * 3)
        let frameCount = frameSize == 0 ? 0 : dataByteCount / frameSize
        let needsRF64 = dataByteCount > UInt64(UInt32.max) - headerSize
        var header = Data()

        header.appendASCII(needsRF64 ? "RF64" : "RIFF")
        header.appendLE(needsRF64 ? UInt32.max : UInt32(dataByteCount + headerSize - 8))
        header.appendASCII("WAVE")
        header.appendASCII(needsRF64 ? "ds64" : "JUNK")
        header.appendLE(UInt32(28))
        if needsRF64 {
            header.appendLE(dataByteCount + headerSize - 8)
            header.appendLE(dataByteCount)
            header.appendLE(frameCount)
            header.appendLE(UInt32(0))
        } else {
            header.append(Data(count: 28))
        }
        header.appendASCII("fmt ")
        header.appendLE(UInt32(16))
        header.appendLE(UInt16(1))
        header.appendLE(UInt16(channelCount))
        header.appendLE(UInt32(sampleRate.rounded()))
        header.appendLE(UInt32(sampleRate.rounded()) * UInt32(channelCount * 3))
        header.appendLE(UInt16(channelCount * 3))
        header.appendLE(UInt16(24))
        header.appendASCII("data")
        header.appendLE(needsRF64 ? UInt32.max : UInt32(dataByteCount))
        guard header.count == Int(headerSize) else { throw WriterError.invalidFormat }
        return header
    }

    private func nextUnitRandom() -> Double {
        randomState ^= randomState << 13
        randomState ^= randomState >> 7
        randomState ^= randomState << 17
        return Double(randomState & 0x00FF_FFFF) / Double(0x0100_0000)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii) ?? Data())
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
