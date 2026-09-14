import AppKit
import Darwin
import GetOudioCore

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--background-agent") {
    BackgroundAgent.main()
} else {
    do {
        let store = try AgentDataStore.production()
        DiagnosticLog.configure(store: store)
        if arguments.contains("--recording-runner") {
            RecordingRunner.main(container: store)
        } else {
            NormalLauncher.main(container: store)
        }
    } catch {
        NSLog("Get Oudio v2 data root unavailable: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}
