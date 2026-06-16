import Foundation

public enum JobProgressPhase: String, Codable, Equatable, Sendable {
    case pending
    case running
    case succeeded
    case failed
}
