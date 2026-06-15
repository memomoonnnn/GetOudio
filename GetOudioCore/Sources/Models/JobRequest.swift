import Foundation

public enum JobEntrySource: String, Codable, Sendable {
    case openWith
    case finderSync
    case shareExtension
    case manual
}

public enum JobOperation: Codable, Equatable, Sendable {
    case transcode(ConversionPreset)
    case extractAudio
    case convertNCM
    case appleMusicDownload(AppleMusicDownloadFormat?)

    private enum CodingKeys: String, CodingKey {
        case type
        case preset
        case format
    }

    private enum OperationType: String, Codable {
        case transcode
        case extractAudio
        case convertNCM
        case appleMusicDownload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(OperationType.self, forKey: .type)
        switch type {
        case .transcode:
            let preset = try container.decode(ConversionPreset.self, forKey: .preset)
            self = .transcode(preset)
        case .extractAudio:
            self = .extractAudio
        case .convertNCM:
            self = .convertNCM
        case .appleMusicDownload:
            let format = try container.decodeIfPresent(AppleMusicDownloadFormat.self, forKey: .format)
            self = .appleMusicDownload(format)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transcode(let preset):
            try container.encode(OperationType.transcode, forKey: .type)
            try container.encode(preset, forKey: .preset)
        case .extractAudio:
            try container.encode(OperationType.extractAudio, forKey: .type)
        case .convertNCM:
            try container.encode(OperationType.convertNCM, forKey: .type)
        case .appleMusicDownload(let format):
            try container.encode(OperationType.appleMusicDownload, forKey: .type)
            try container.encodeIfPresent(format, forKey: .format)
        }
    }
}

public enum AppleMusicDownloadFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case askEveryTime
    case alac
    case aac
    case atmos

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .askEveryTime: return "每次询问"
        case .alac: return "ALAC"
        case .aac: return "AAC"
        case .atmos: return "Atmos"
        }
    }

    public var downloaderArguments: [String] {
        switch self {
        case .askEveryTime, .alac:
            return []
        case .aac:
            return ["--aac"]
        case .atmos:
            return ["--atmos"]
        }
    }
}

public struct JobRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fileURL: URL
    public var category: FileCategory
    public var operation: JobOperation
    public var source: JobEntrySource
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        category: FileCategory = .unsupported,
        operation: JobOperation,
        source: JobEntrySource,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.category = category == .unsupported ? FileCategory.classify(fileURL) : category
        self.operation = operation
        self.source = source
        self.createdAt = createdAt
    }
}
