import Foundation

public enum NCMOutputMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case sourceDirectory
    case customDirectory

    public var id: String { rawValue }
}
