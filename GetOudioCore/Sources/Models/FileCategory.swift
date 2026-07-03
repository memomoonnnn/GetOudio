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

        if Self.unsupportedAudioExtensionSet.contains(ext) {
            return .unsupported
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

        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }

        return .unsupported
    }

    public static let supportedAudioExtensions: [String] = [
        "m4a", "aac", "mp3", "alac", "flac", "wav", "aiff", "aif", "ogg", "caf"
    ]

    public static let supportedVideoExtensions: [String] = [
        "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"
    ]

    private static let audioExtensionSet = Set(supportedAudioExtensions)
    private static let videoExtensionSet = Set(supportedVideoExtensions)
    private static let unsupportedAudioExtensionSet: Set<String> = ["ape", "m4b", "opus", "wma"]
}
