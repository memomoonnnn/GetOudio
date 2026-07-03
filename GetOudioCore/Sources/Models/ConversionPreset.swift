import Foundation

public enum ConversionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac128
    case aac256
    case aac320
    case mp3128
    case mp3256
    case mp3320
    case vorbisQ3
    case vorbisQ6
    case vorbisQ10
    case opus64KbpsPerChannel
    case opus96KbpsPerChannel
    case opus128KbpsPerChannel
    case alac24Bit48k
    case alac16Bit44_1k = "alac16Bit44_1k"
    case alacSource
    case flac24Bit48k
    case flac16Bit44_1k = "flac16Bit44_1k"
    case flacSource
    case pcm24Bit48k
    case pcm16Bit44_1k = "pcm16Bit44_1k"
    case pcmSource
    case pcmAiff24Bit48k
    case pcmAiff16Bit44_1k = "pcmAiff16Bit44_1k"
    case pcmAiffSource

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
            return .pcmWav
        case .pcmAiff24Bit48k, .pcmAiff16Bit44_1k, .pcmAiffSource:
            return .pcmAiff
        case .vorbisQ3, .vorbisQ6, .vorbisQ10:
            return .vorbis
        case .opus64KbpsPerChannel, .opus96KbpsPerChannel, .opus128KbpsPerChannel:
            return .opus
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
        case .pcm24Bit48k, .pcmAiff24Bit48k: return "24bit 48kHz"
        case .pcm16Bit44_1k, .pcmAiff16Bit44_1k: return "16bit 44.1kHz"
        case .pcmSource, .pcmAiffSource: return "Original"
        case .vorbisQ3: return "q3"
        case .vorbisQ6: return "q6"
        case .vorbisQ10: return "q10"
        case .opus64KbpsPerChannel: return "64kbps Per-Ch"
        case .opus96KbpsPerChannel: return "96kbps Per-Ch"
        case .opus128KbpsPerChannel: return "128kbps Per-Ch"
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
        case .pcmAiff24Bit48k, .pcmAiff16Bit44_1k, .pcmAiffSource:
            return "aiff"
        case .vorbisQ3, .vorbisQ6, .vorbisQ10:
            return "ogg"
        case .opus64KbpsPerChannel, .opus96KbpsPerChannel, .opus128KbpsPerChannel:
            return "opus"
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
        case .pcm24Bit48k: return "PCM WAV 24bit 48kHz"
        case .pcm16Bit44_1k: return "PCM WAV 16bit 44.1kHz"
        case .pcmSource: return "PCM WAV Original"
        case .pcmAiff24Bit48k: return "PCM AIFF 24bit 48kHz"
        case .pcmAiff16Bit44_1k: return "PCM AIFF 16bit 44.1kHz"
        case .pcmAiffSource: return "PCM AIFF Original"
        case .vorbisQ3: return "Vorbis q3"
        case .vorbisQ6: return "Vorbis q6"
        case .vorbisQ10: return "Vorbis q10"
        case .opus64KbpsPerChannel: return "Opus 64kbps Per-Ch"
        case .opus96KbpsPerChannel: return "Opus 96kbps Per-Ch"
        case .opus128KbpsPerChannel: return "Opus 128kbps Per-Ch"
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
        case .pcm24Bit48k: return "PCM WAV 24bit 48kHz"
        case .pcm16Bit44_1k: return "PCM WAV 16bit 44.1kHz"
        case .pcmSource: return "PCM WAV Original"
        case .pcmAiff24Bit48k: return "PCM AIFF 24bit 48kHz"
        case .pcmAiff16Bit44_1k: return "PCM AIFF 16bit 44.1kHz"
        case .pcmAiffSource: return "PCM AIFF Original"
        case .vorbisQ3: return "Vorbis q3"
        case .vorbisQ6: return "Vorbis q6"
        case .vorbisQ10: return "Vorbis q10"
        case .opus64KbpsPerChannel: return "Opus 64kbps Per-Ch"
        case .opus96KbpsPerChannel: return "Opus 96kbps Per-Ch"
        case .opus128KbpsPerChannel: return "Opus 128kbps Per-Ch"
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

    public var needsInputAudioChannelCount: Bool {
        switch self {
        case .opus64KbpsPerChannel, .opus96KbpsPerChannel, .opus128KbpsPerChannel:
            return true
        default:
            return false
        }
    }

    public func ffmpegArguments(inputURL: URL, outputURL: URL, inputAudioChannelCount: Int? = nil) -> [String] {
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
        case .pcmAiff24Bit48k:
            arguments += ["-acodec", "pcm_s24be", "-ar", "48000", "-f", "aiff"]
        case .pcmAiff16Bit44_1k:
            arguments += ["-acodec", "pcm_s16be", "-ar", "44100", "-f", "aiff"]
        case .pcmAiffSource:
            arguments += ["-acodec", "pcm_s16be", "-f", "aiff"]
        case .vorbisQ3:
            arguments += ["-acodec", "libvorbis", "-q:a", "3", "-f", "ogg"]
        case .vorbisQ6:
            arguments += ["-acodec", "libvorbis", "-q:a", "6", "-f", "ogg"]
        case .vorbisQ10:
            arguments += ["-acodec", "libvorbis", "-q:a", "10", "-f", "ogg"]
        case .opus64KbpsPerChannel:
            arguments += opusArguments(targetKbpsPerChannel: 64, inputAudioChannelCount: inputAudioChannelCount)
        case .opus96KbpsPerChannel:
            arguments += opusArguments(targetKbpsPerChannel: 96, inputAudioChannelCount: inputAudioChannelCount)
        case .opus128KbpsPerChannel:
            arguments += opusArguments(targetKbpsPerChannel: 128, inputAudioChannelCount: inputAudioChannelCount)
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

    private func opusArguments(targetKbpsPerChannel: Int, inputAudioChannelCount: Int?) -> [String] {
        let channelCount = max(inputAudioChannelCount ?? 2, 1)
        let totalBitrateKbps = targetKbpsPerChannel * channelCount
        return ["-acodec", "libopus", "-b:a", "\(totalBitrateKbps)k", "-vbr", "on", "-application", "audio", "-f", "ogg"]
    }
}

public enum ConversionPresetGroup: String, CaseIterable, Identifiable, Sendable {
    case aac
    case mp3
    case vorbis
    case opus
    case alac
    case flac
    case pcmWav
    case pcmAiff

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .alac: return "ALAC"
        case .flac: return "FLAC"
        case .pcmWav: return "PCM WAV"
        case .pcmAiff: return "PCM AIFF"
        case .vorbis: return "Vorbis"
        case .opus: return "Opus"
        }
    }

    public var presets: [ConversionPreset] {
        ConversionPreset.allCases.filter { $0.group == self }
    }
}
