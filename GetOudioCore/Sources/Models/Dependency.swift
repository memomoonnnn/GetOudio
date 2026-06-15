import Foundation

public enum RuntimeDependency: String, CaseIterable, Identifiable, Codable, Sendable {
    case ffmpeg
    case docker
    case colima
    case gpac
    case go

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .docker: return "Docker CLI"
        case .colima: return "Colima"
        case .gpac: return "GPAC / MP4Box"
        case .go: return "Go"
        }
    }

    public var executableName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .docker: return "docker"
        case .colima: return "colima"
        case .gpac: return "MP4Box"
        case .go: return "go"
        }
    }

    public var installCommand: String {
        switch self {
        case .ffmpeg:
            return "brew install ffmpeg"
        case .docker:
            return "brew install docker"
        case .colima:
            return "brew install colima"
        case .gpac:
            return "brew install gpac"
        case .go:
            return "brew install go"
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
            return "ThirdParty/ncmdump/bin/ncmdump"
        case .appleMusicDownloader:
            return "ThirdParty/apple-music-downloader/apple-music-downloader"
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
        case .appleMusicWrapper: return "ghcr.io/itouakirai/wrapper:x86"
        }
    }

    public var platform: String {
        switch self {
        case .appleMusicWrapper: return "linux/amd64"
        }
    }

    public var upstreamURL: URL {
        switch self {
        case .appleMusicWrapper:
            return URL(string: "https://github.com/WorldObservationLog/wrapper")!
        }
    }
}

public struct ManagedDockerImageStatus: Identifiable, Equatable, Sendable {
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
