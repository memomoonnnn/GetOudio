import Foundation

public struct LaunchMarkerStore {
    public static let defaultTTL: TimeInterval = 120

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupIdentifier)) {
        self.defaults = defaults
    }

    @discardableResult
    public func mark(_ source: LaunchSource, at date: Date = Date()) -> Bool {
        guard let defaults else {
            DiagnosticLog.append("launch marker unavailable source=\(source.rawValue)")
            return false
        }

        defaults.set(source.rawValue, forKey: AppConstants.extensionLaunchSourceKey)
        defaults.set(date.timeIntervalSince1970, forKey: AppConstants.extensionLaunchTimestampKey)
        defaults.synchronize()
        return true
    }

    public func activeSource(now: Date = Date(), ttl: TimeInterval = Self.defaultTTL) -> LaunchSource? {
        guard let defaults,
              let rawSource = defaults.string(forKey: AppConstants.extensionLaunchSourceKey),
              let source = LaunchSource(rawValue: rawSource),
              source != .direct else {
            return nil
        }

        let timestamp = defaults.double(forKey: AppConstants.extensionLaunchTimestampKey)
        guard timestamp > 0, now.timeIntervalSince1970 - timestamp < ttl else {
            return nil
        }
        return source
    }

    public func clear() {
        guard let defaults else {
            return
        }

        defaults.removeObject(forKey: AppConstants.extensionLaunchSourceKey)
        defaults.removeObject(forKey: AppConstants.extensionLaunchTimestampKey)
        defaults.synchronize()
    }
}
