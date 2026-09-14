import Foundation

public enum AppConstants {
    public static let backgroundAgentMachServiceName = BackgroundAgentXPC.machServiceName
    public static let appURLScheme = "getoudio"
    public static let bundleIdentifier = "com.shengjiacheng.GetOudio"
    public static let telemetrySubsystem = "com.shengjiacheng.GetOudio"
    public static let recordingWidgetKind = "GetOudioRecordingWidget"
    public static let recordingControlNotification = "com.shengjiacheng.GetOudio.recording-control"
}

/// The Open With entry that submitted a batch to the Agent.
public enum LaunchSource: String, Sendable {
    /// System opened audio files with Get Oudio ("Open With").
    case openWithAudio
    /// System opened .ncm files with Get Oudio ("Open With").
    case openWithNCM
}
