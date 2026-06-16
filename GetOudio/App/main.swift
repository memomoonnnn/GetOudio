import AppKit
import GetOudioCore

// ── Headless detection ──────────────────────────────────────────────
// When launched from Finder Sync / Share Extension, the extension sets
// `ExtensionLaunchSource` + `ExtensionLaunchTimestamp` in shared
// UserDefaults BEFORE calling open(url).  If those markers are present
// and recent, this launch should run headless (no UI, notify on completion).

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
    GetOudioApp.main()
}
