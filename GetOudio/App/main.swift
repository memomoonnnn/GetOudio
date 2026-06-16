import AppKit
import GetOudioCore

// ── Headless detection ──────────────────────────────────────────────
// LSUIElement=true in Info.plist means the app ALWAYS starts as a
// background agent (no Dock icon, no window).  This completely
// eliminates the window flash that would otherwise occur when the
// app is launched by a Finder/Share extension.
//
// For normal (direct) launches we explicitly promote to .regular.
// For extension-triggered launches we stay background → process → notify → exit.

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
    // Stay as background agent (LSUIElement default) — no UI ever
    HeadlessRunner.main()
} else {
    // Promote to full GUI app so SwiftUI windows & Dock icon appear
    NSApp.setActivationPolicy(.regular)
    GetOudioApp.main()
}
