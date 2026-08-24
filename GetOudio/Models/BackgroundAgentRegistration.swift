import AppKit
import GetOudioCore

enum BackgroundAgentRegistration {
    private static let installerName = "InstallBackgroundAgent"

    @MainActor
    static func openInstaller() -> Bool {
        guard let installerURL = Bundle.main.url(
            forResource: installerName,
            withExtension: "command",
            subdirectory: "LaunchAgents"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(installerURL)
    }

    static func ensureAvailable() async throws {
        try await BackgroundAgentClient().checkAvailability()
    }
}
