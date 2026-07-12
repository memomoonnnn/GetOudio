import Foundation

public struct AudioDeviceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { uid }
    public let uid: String
    public let name: String
    public let inputChannelCount: Int
    public let outputChannelCount: Int
    public let nominalSampleRate: Double

    public init(
        uid: String,
        name: String,
        inputChannelCount: Int,
        outputChannelCount: Int,
        nominalSampleRate: Double
    ) {
        self.uid = uid
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.nominalSampleRate = nominalSampleRate
    }

    public var isSupportedProToolsAudioBridge: Bool {
        inputChannelCount == 2 && Self.supportedBridgeNames.contains(name)
    }

    public static let supportedBridgeNames = [
        "Pro Tools Audio Bridge 2-A",
        "Pro Tools Audio Bridge 2-B"
    ]
}

public enum RecordingPhase: String, Codable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case failed

    public var isActive: Bool {
        self == .starting || self == .recording || self == .stopping
    }
}

public enum RecordingStopReason: String, Codable, Sendable {
    case user
    case sourceDeviceUnavailable
    case monitorDeviceUnavailable
    case systemSleep
    case writerFailure
    case bufferOverflow
    case runnerCrashed
    case startupFailure
}

public struct RecordingSessionSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var phase: RecordingPhase
    public var runnerPID: Int32?
    public var bridgeDeviceUID: String?
    public var originalOutputDeviceUID: String?
    public var temporaryFileURL: URL?
    public var sampleRate: Double?
    public var channelCount: Int?
    public var startedAt: Date?
    public var stopReason: RecordingStopReason?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        phase: RecordingPhase = .idle,
        runnerPID: Int32? = nil,
        bridgeDeviceUID: String? = nil,
        originalOutputDeviceUID: String? = nil,
        temporaryFileURL: URL? = nil,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        startedAt: Date? = nil,
        stopReason: RecordingStopReason? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.runnerPID = runnerPID
        self.bridgeDeviceUID = bridgeDeviceUID
        self.originalOutputDeviceUID = originalOutputDeviceUID
        self.temporaryFileURL = temporaryFileURL
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.startedAt = startedAt
        self.stopReason = stopReason
        self.errorMessage = errorMessage
    }

    public static let idle = RecordingSessionSnapshot()
}

public enum RecordingCommandKind: String, Codable, Sendable {
    case start
    case stop
}

public struct RecordingCommand: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: RecordingCommandKind
    public let createdAt: Date

    public init(id: UUID = UUID(), kind: RecordingCommandKind, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}

