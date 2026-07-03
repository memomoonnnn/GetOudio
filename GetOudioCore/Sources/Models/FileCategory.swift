import Foundation
import UniformTypeIdentifiers

public enum FileCategory: String, Codable, CaseIterable, Sendable {
    case audio
    case video
    case ncm
    case appleMusic
    case unsupported

    public var displayName: String {
        switch self {
        case .audio: return "音频"
        case .video: return "视频"
        case .ncm: return "NCM"
        case .appleMusic: return "Apple Music"
        case .unsupported: return "不支持"
        }
    }

    public static func classify(_ url: URL) -> FileCategory {
        if let scheme = url.scheme?.lowercased(), ["http", "https", "music"].contains(scheme) {
            return .appleMusic
        }

        let ext = url.pathExtension.lowercased()
        if ext == "ncm" {
            return .ncm
        }

        if Self.audioExtensionSet.contains(ext) {
            return .audio
        }

        if Self.videoExtensionSet.contains(ext) {
            return .video
        }

        guard let type = UTType(filenameExtension: ext) else {
            return .unsupported
        }

        if type.conforms(to: .audio) {
            return .audio
        }

        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }

        return .unsupported
    }

    /// Audio inputs accepted by conversion entry points.
    /// Keep this aligned with the embedded ffmpeg demuxers plus common extension aliases.
    public static let supportedAudioExtensions: [String] = [
        "aac", "ac3", "aif", "aifc", "aiff", "alac", "amr", "ape", "asf", "ast",
        "au", "caf", "dts", "dtshd", "eac3", "f32le", "flac", "loas",
        "m4a", "m4b", "mp2", "mp3", "mpa", "mpga", "ogg", "opus",
        "s16le", "s24le", "s32le", "shn", "tak", "truehd", "tta", "wav",
        "wma", "wv"
    ]

    public static let defaultOpenWithAudioExtensions: [String] = [
        "m4a", "aac", "mp3", "alac", "flac", "wav", "aiff", "aif", "ogg", "opus", "caf"
    ]

    public static let supportedVideoExtensions: [String] = [
        "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"
    ]

    private static let audioExtensionSet = Set(supportedAudioExtensions)
    private static let videoExtensionSet = Set(supportedVideoExtensions)
}
