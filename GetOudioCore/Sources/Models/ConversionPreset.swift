import Foundation

public enum ConversionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac128
    case aac256
    case aac320
    case mp3128
    case mp3256
    case mp3320
    case alac24Bit48k
    case alac16Bit44_1k = "alac16Bit44_1k"
    case alacSource
    case flac24Bit48k
    case flac16Bit44_1k = "flac16Bit44_1k"
    case flacSource
    case pcm24Bit48k
    case pcm16Bit44_1k = "pcm16Bit44_1k"
    case pcmSource

    public var id: String { rawValue }

    public var group: ConversionPresetGroup {
        switch self {
        case .aac128, .aac256, .aac320:
            return .aac
        case .mp3128, .mp3256, .mp3320:
            return .mp3
        case .alac24Bit48k, .alac16Bit44_1k, .alacSource:
            return .alac
        case .flac24Bit48k, .flac16Bit44_1k, .flacSource:
            return .flac
        case .pcm24Bit48k, .pcm16Bit44_1k, .pcmSource:
            return .pcm
        }
    }

    /// 设置界面中的简短标题（已通过分组标题体现格式，无需重复格式前缀）
    public var title: String {
        switch self {
        case .aac128: return "128Kbps"
        case .aac256: return "256Kbps"
        case .aac320: return "320Kbps"
        case .mp3128: return "128Kbps"
        case .mp3256: return "256Kbps"
        case .mp3320: return "320Kbps"
        case .alac24Bit48k: return "24bit 48kHz"
        case .alac16Bit44_1k: return "16bit 44.1kHz"
        case .alacSource: return "Original"
        case .flac24Bit48k: return "24bit 48kHz"
        case .flac16Bit44_1k: return "16bit 44.1kHz"
        case .flacSource: return "Original"
        case .pcm24Bit48k: return "24bit 48kHz"
        case .pcm16Bit44_1k: return "16bit 44.1kHz"
        case .pcmSource: return "Original"
        }
    }

    public var outputExtension: String {
        switch self {
        case .aac128, .aac256, .aac320, .alac24Bit48k, .alac16Bit44_1k, .alacSource:
            return "m4a"
        case .mp3128, .mp3256, .mp3320:
            return "mp3"
        case .flac24Bit48k, .flac16Bit44_1k, .flacSource:
            return "flac"
        case .pcm24Bit48k, .pcm16Bit44_1k, .pcmSource:
            return "wav"
        }
    }

    /// Finder 右键菜单中的完整标题（无分组上下文，需包含格式名）
    public var finderMenuTitle: String {
        switch self {
        case .aac128: return "AAC 128Kbps"
        case .aac256: return "AAC 256Kbps"
        case .aac320: return "AAC 320Kbps"
        case .mp3128: return "MP3 128Kbps"
        case .mp3256: return "MP3 256Kbps"
        case .mp3320: return "MP3 320Kbps"
        case .alac24Bit48k: return "ALAC 24bit 48kHz"
        case .alac16Bit44_1k: return "ALAC 16bit 44.1kHz"
        case .alacSource: return "ALAC Original"
        case .flac24Bit48k: return "FLAC 24bit 48kHz"
        case .flac16Bit44_1k: return "FLAC 16bit 44.1kHz"
        case .flacSource: return "FLAC Original"
        case .pcm24Bit48k: return "PCM 24bit 48kHz"
        case .pcm16Bit44_1k: return "PCM 16bit 44.1kHz"
        case .pcmSource: return "PCM Original"
        }
    }

    public var outputNameSuffix: String {
        switch self {
        case .aac128: return "AAC 128Kbps"
        case .aac256: return "AAC 256Kbps"
        case .aac320: return "AAC 320Kbps"
        case .mp3128: return "MP3 128Kbps"
        case .mp3256: return "MP3 256Kbps"
        case .mp3320: return "MP3 320Kbps"
        case .alac24Bit48k: return "ALAC 24bit 48kHz"
        case .alac16Bit44_1k: return "ALAC 16bit 44.1kHz"
        case .alacSource: return "ALAC Original"
        case .flac24Bit48k: return "FLAC 24bit 48kHz"
        case .flac16Bit44_1k: return "FLAC 16bit 44.1kHz"
        case .flacSource: return "FLAC Original"
        case .pcm24Bit48k: return "PCM 24bit 48kHz"
        case .pcm16Bit44_1k: return "PCM 16bit 44.1kHz"
        case .pcmSource: return "PCM Original"
        }
    }

    public static var defaultEnabled: Set<ConversionPreset> {
        Set(allCases)
    }

    public func outputURL(for inputURL: URL) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName) [\(outputNameSuffix)]"
        return inputURL.deletingLastPathComponent().appendingPathComponent(outputName).appendingPathExtension(outputExtension)
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
        case .alac16Bit44_1k:
            arguments += ["-acodec", "alac", "-ar", "44100", "-sample_fmt", "s16p"]
        case .alacSource:
            arguments += ["-acodec", "alac"]
        case .flac24Bit48k:
            arguments += ["-acodec", "flac", "-ar", "48000", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        case .flac16Bit44_1k:
            arguments += ["-acodec", "flac", "-ar", "44100", "-sample_fmt", "s16"]
        case .flacSource:
            arguments += ["-acodec", "flac"]
        case .pcm24Bit48k:
            arguments += ["-acodec", "pcm_s24le", "-ar", "48000"]
        case .pcm16Bit44_1k:
            arguments += ["-acodec", "pcm_s16le", "-ar", "44100"]
        case .pcmSource:
            arguments += ["-acodec", "pcm_s16le"]
        }

        arguments += ["-map", "0:a:0", "-map_metadata", "0:g", "-map_chapters", "0", "-y", "-vn"]

        switch self {
        case .aac128, .aac256, .aac320, .alac24Bit48k, .alac16Bit44_1k, .alacSource:
            arguments += ["-movflags", "use_metadata_tags"]
        case .mp3128, .mp3256, .mp3320:
            arguments += ["-write_id3v2", "1", "-id3v2_version", "3"]
        default:
            break
        }

        arguments.append(outputURL.path)
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
