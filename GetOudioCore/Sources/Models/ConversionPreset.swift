import Foundation

public enum ConversionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac128
    case aac256
    case aac320
    case mp3128
    case mp3256
    case mp3320
    case alac24Bit48k
    case alac16Bit48k
    case alacSource
    case flac24Bit48k
    case flac16Bit48k
    case flacSource
    case pcm24Bit48k
    case pcm16Bit48k
    case pcmSource

    public var id: String { rawValue }

    public var group: ConversionPresetGroup {
        switch self {
        case .aac128, .aac256, .aac320:
            return .aac
        case .mp3128, .mp3256, .mp3320:
            return .mp3
        case .alac24Bit48k, .alac16Bit48k, .alacSource:
            return .alac
        case .flac24Bit48k, .flac16Bit48k, .flacSource:
            return .flac
        case .pcm24Bit48k, .pcm16Bit48k, .pcmSource:
            return .pcm
        }
    }

    public var title: String {
        switch self {
        case .aac128: return "AAC 128Kbps"
        case .aac256: return "AAC 256Kbps"
        case .aac320: return "AAC 320Kbps"
        case .mp3128: return "MP3 128Kbps"
        case .mp3256: return "MP3 256Kbps"
        case .mp3320: return "MP3 320Kbps"
        case .alac24Bit48k: return "ALAC 24bit 48KHz"
        case .alac16Bit48k: return "ALAC 16bit 48KHz"
        case .alacSource: return "ALAC Original"
        case .flac24Bit48k: return "FLAC 24bit 48KHz"
        case .flac16Bit48k: return "FLAC 16bit 48KHz"
        case .flacSource: return "FLAC Original"
        case .pcm24Bit48k: return "PCM WAV 24bit 48KHz"
        case .pcm16Bit48k: return "PCM WAV 16bit 48KHz"
        case .pcmSource: return "PCM Original"
        }
    }

    public var outputExtension: String {
        switch self {
        case .aac128, .aac256, .aac320, .alac24Bit48k, .alac16Bit48k, .alacSource:
            return "m4a"
        case .mp3128, .mp3256, .mp3320:
            return "mp3"
        case .flac24Bit48k, .flac16Bit48k, .flacSource:
            return "flac"
        case .pcm24Bit48k, .pcm16Bit48k, .pcmSource:
            return "wav"
        }
    }

    public var finderMenuTitle: String { title }

    public static var defaultEnabled: Set<ConversionPreset> {
        Set(allCases)
    }

    public func outputURL(for inputURL: URL) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return inputURL.deletingLastPathComponent().appendingPathComponent(baseName).appendingPathExtension(outputExtension)
    }

    public func ffmpegArguments(inputURL: URL, outputURL: URL) -> [String] {
        var arguments = ["-i", inputURL.path]

        switch self {
        case .aac128:
            arguments += ["-acodec", "aac", "-b:a", "128k"]
        case .aac256:
            arguments += ["-acodec", "aac", "-b:a", "256k"]
        case .aac320:
            arguments += ["-acodec", "aac", "-b:a", "320k"]
        case .mp3128:
            arguments += ["-acodec", "libmp3lame", "-b:a", "128k"]
        case .mp3256:
            arguments += ["-acodec", "libmp3lame", "-b:a", "256k"]
        case .mp3320:
            arguments += ["-acodec", "libmp3lame", "-b:a", "320k"]
        case .alac24Bit48k:
            arguments += ["-acodec", "alac", "-ar", "48000", "-sample_fmt", "s32p"]
        case .alac16Bit48k:
            arguments += ["-acodec", "alac", "-ar", "48000", "-sample_fmt", "s16p"]
        case .alacSource:
            arguments += ["-acodec", "alac"]
        case .flac24Bit48k:
            arguments += ["-acodec", "flac", "-ar", "48000", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        case .flac16Bit48k:
            arguments += ["-acodec", "flac", "-ar", "48000", "-sample_fmt", "s16"]
        case .flacSource:
            arguments += ["-acodec", "flac"]
        case .pcm24Bit48k:
            arguments += ["-acodec", "pcm_s24le", "-ar", "48000"]
        case .pcm16Bit48k:
            arguments += ["-acodec", "pcm_s16le", "-ar", "48000"]
        case .pcmSource:
            arguments += ["-acodec", "pcm_s16le"]
        }

        arguments += ["-map_metadata", "0", "-y", "-vn", outputURL.path]
        return arguments
    }
}

public enum ConversionPresetGroup: String, CaseIterable, Identifiable, Sendable {
    case aac
    case mp3
    case alac
    case flac
    case pcm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .alac: return "ALAC"
        case .flac: return "FLAC"
        case .pcm: return "PCM"
        }
    }

    public var presets: [ConversionPreset] {
        ConversionPreset.allCases.filter { $0.group == self }
    }
}
