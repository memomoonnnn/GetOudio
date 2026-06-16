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

        if Self.audioExtensions.contains(ext) {
            return .audio
        }

        if Self.videoExtensions.contains(ext) {
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

    private static let audioExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "ape", "caf", "flac", "m4a", "m4b", "mp3", "ogg", "opus", "wav", "wma"
    ]

    private static let videoExtensions: Set<String> = [
        "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"
    ]
}
