import Foundation

public enum RuntimeDependency: String, CaseIterable, Identifiable, Codable, Sendable {
    case ffmpeg

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        }
    }

    public var executableName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        }
    }

    public var installCommand: String {
        switch self {
        case .ffmpeg:
            return "内嵌精简版 ffmpeg 由构建脚本生成，不在应用内安装"
        }
    }

    /// 内嵌在 App Bundle Resources 中的相对路径。
    public var bundledRelativePath: String? {
        switch self {
        case .ffmpeg:
            return "ffmpeg/ffmpeg"
        }
    }

    public var sortPriority: Int {
        switch self {
        case .ffmpeg: return 10
        }
    }
}

public struct DependencyStatus: Identifiable, Equatable, Sendable {
    public var id: String { dependency.id }
    public var dependency: RuntimeDependency
    public var isInstalled: Bool
    public var resolvedPath: String?
    public var detail: String

    public init(dependency: RuntimeDependency, isInstalled: Bool, resolvedPath: String?, detail: String) {
        self.dependency = dependency
        self.isInstalled = isInstalled
        self.resolvedPath = resolvedPath
        self.detail = detail
    }
}

public enum BundledComponent: String, CaseIterable, Identifiable, Codable, Sendable {
    case ncmdump
    case appleMusicDownloader

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ncmdump: return "ncmdump"
        case .appleMusicDownloader: return "apple-music-downloader"
        }
    }

    public var expectedRelativePath: String {
        switch self {
        case .ncmdump:
            return "ncmdump/bin/ncmdump"
        case .appleMusicDownloader:
            return "apple-music-downloader/apple-music-downloader"
        }
    }

    public var upstreamURL: URL {
        switch self {
        case .ncmdump:
            return URL(string: "https://github.com/taurusxin/ncmdump")!
        case .appleMusicDownloader:
            return URL(string: "https://github.com/zhaarey/apple-music-downloader")!
        }
    }
}

public struct BundledComponentStatus: Identifiable, Equatable, Sendable {
    public var id: String { component.id }
    public var component: BundledComponent
    public var isEmbedded: Bool
    public var resolvedURL: URL?
    public var detail: String

    public init(component: BundledComponent, isEmbedded: Bool, resolvedURL: URL?, detail: String) {
        self.component = component
        self.isEmbedded = isEmbedded
        self.resolvedURL = resolvedURL
        self.detail = detail
    }
}

public enum ManagedDockerImage: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleMusicWrapper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleMusicWrapper: return "Apple Music wrapper"
        }
    }

    public var imageName: String {
        switch self {
        case .appleMusicWrapper:
            #if arch(arm64)
            return "ghcr.io/itouakirai/wrapper:arm"
            #else
            return "ghcr.io/itouakirai/wrapper:x86"
            #endif
        }
    }

    public var platform: String {
        switch self {
        case .appleMusicWrapper:
            #if arch(arm64)
            return "linux/arm64"
            #else
            return "linux/amd64"
            #endif
        }
    }

    public var upstreamURL: URL {
        switch self {
        case .appleMusicWrapper:
            return URL(string: "https://github.com/itouakirai/wrapper")!
        }
    }
}

public struct ManagedDockerImageStatus: Codable, Identifiable, Equatable, Sendable {
    public var id: String { image.id }
    public var image: ManagedDockerImage
    public var isAvailable: Bool
    public var detail: String

    public init(image: ManagedDockerImage, isAvailable: Bool, detail: String) {
        self.image = image
        self.isAvailable = isAvailable
        self.detail = detail
    }
}
