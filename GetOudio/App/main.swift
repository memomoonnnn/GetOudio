import AppKit
import GetOudioCore

// Headless detection
//
//   • Direct launch without marker → NormalLauncher shows the settings window.
//   • Finder/Share/Open With marker → HeadlessRunner drains JobQueue, notifies, exits.
//   • Transient Open With UI is menu-style and only enqueues work.

let isHeadless: Bool = {
    LaunchMarkerStore().activeSource() != nil
}()

if isHeadless {
    HeadlessRunner.main()
} else {
    NormalLauncher.main()
}
