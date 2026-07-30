import Foundation

public enum SettingsGuidanceTarget: String, Codable, Sendable {
    case recordingInput
    case appleMusicDependencies
    case appleMusicInitialization
}

public struct SettingsGuidanceStore {
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

    public func request(_ target: SettingsGuidanceTarget, at date: Date = Date()) {
        defaults.set(target.rawValue, forKey: Keys.target)
        defaults.set(date.timeIntervalSince1970, forKey: Keys.timestamp)
        defaults.synchronize()
    }

    public func consume(
        now: Date = Date(),
        ttl: TimeInterval = Self.defaultTTL
    ) -> SettingsGuidanceTarget? {
        defer { clear() }
        guard let rawValue = defaults.string(forKey: Keys.target),
              let target = SettingsGuidanceTarget(rawValue: rawValue),
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
