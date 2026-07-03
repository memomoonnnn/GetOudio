import Foundation

public enum AppConstants {
    public static let appGroupIdentifier = "group.com.shengjiacheng.GetOudio"
    public static let appURLScheme = "getoudio"
    public static let bundleIdentifier = "com.shengjiacheng.GetOudio"
    public static let telemetrySubsystem = "com.shengjiacheng.GetOudio"

    /// Shared UserDefaults key: set by extensions before launching the main app.
    /// Indicates the main app was launched by an extension (Finder Sync / Share).
    public static let extensionLaunchSourceKey = "ExtensionLaunchSource"
    /// Shared UserDefaults key: timestamp of the extension launch request.
    public static let extensionLaunchTimestampKey = "ExtensionLaunchTimestamp"
}

/// How the main app was launched.
public enum LaunchSource: String, Sendable {
    /// User launched the app directly (e.g., double-clicked in Finder / Dock).
    case direct
    /// System opened audio files with Get Oudio ("Open With").
    case openWithAudio
    /// System opened .ncm files with Get Oudio ("Open With").
    case openWithNCM
    /// Launched from Finder Sync extension.
    case finderSync
    /// Launched from Share extension (Apple Music, reserved).
    case shareExtension
    /// Launched only to dispatch pending notification events.
    case notificationDispatch
}
