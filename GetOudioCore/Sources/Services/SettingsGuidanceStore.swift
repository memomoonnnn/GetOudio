import Foundation

public enum SettingsAttentionItem: String, Codable, Hashable, Sendable {
    case microphonePermission
    case transcodingDocumentation
    case ncmDocumentation
    case appleMusicDocumentation
    case recordingInput
    case recordingDocumentation
    case appleMusicDependencies
    case appleMusicInitialization
}

/// Carries one short-lived settings location request between processes.
/// Persistent completion state belongs to the setting that defines it.
public struct SettingsAttentionRequestStore {
    public static let defaultTTL: TimeInterval = 120

    private enum Keys {
        static let target = "SettingsGuidanceTarget"
        static let timestamp = "SettingsGuidanceTimestamp"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public init(container: SharedContainer) {
        self.init(defaults: container.defaults)
    }

    public func request(_ item: SettingsAttentionItem, at date: Date = Date()) {
        defaults.set(item.rawValue, forKey: Keys.target)
        defaults.set(date.timeIntervalSince1970, forKey: Keys.timestamp)
        defaults.synchronize()
    }

    public func consume(
        now: Date = Date(),
        ttl: TimeInterval = Self.defaultTTL
    ) -> SettingsAttentionItem? {
        defer { clear() }
        guard let rawValue = defaults.string(forKey: Keys.target),
              let target = SettingsAttentionItem(rawValue: rawValue),
              now.timeIntervalSince1970 - defaults.double(forKey: Keys.timestamp) < ttl
        else {
            return nil
        }
        return target
    }

    public func clear() {
        defaults.removeObject(forKey: Keys.target)
        defaults.removeObject(forKey: Keys.timestamp)
        defaults.synchronize()
    }
}
