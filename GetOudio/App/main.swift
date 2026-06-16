import AppKit
import GetOudioCore

// ── Headless detection ──────────────────────────────────────────────
// The floating-panel window configuration (level=.floating,
// collectionBehavior=.stationary) is what enables dual foreground/background
// behaviour — NOT LSUIElement or TransformProcessType.
//
//   • Normal launch → floating panel window appears
//   • Extension trigger → no window, jobs run silently → notification → exit

let isHeadless: Bool = {
    guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
        return false
    }
    guard let rawSource = defaults.string(forKey: AppConstants.extensionLaunchSourceKey),
          let source = LaunchSource(rawValue: rawSource),
          source != .direct else {
        return false
    }
    let timestamp = defaults.double(forKey: AppConstants.extensionLaunchTimestampKey)
    let now = Date().timeIntervalSince1970
    return timestamp > 0 && (now - timestamp) < 10
}()

if isHeadless {
    HeadlessRunner.main()
} else {
    NormalLauncher.main()
}
