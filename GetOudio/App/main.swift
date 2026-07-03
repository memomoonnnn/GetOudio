import AppKit
import GetOudioCore

// Headless detection
//
//   • Direct launch without marker → NormalLauncher shows the settings window.
//   • Finder/Share/Open With marker → HeadlessRunner drains JobQueue, notifies, exits.
//   • Transient Open With UI is menu-style and only enqueues work.

private let extensionLaunchMarkerTTL: TimeInterval = 120

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
    return timestamp > 0 && (now - timestamp) < extensionLaunchMarkerTTL
}()

if isHeadless {
    HeadlessRunner.main()
} else {
    NormalLauncher.main()
}
