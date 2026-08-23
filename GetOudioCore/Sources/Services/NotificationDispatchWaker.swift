import Foundation

public enum NotificationDispatchWaker {
    public static func wake(container: SharedContainer) {
        LaunchMarkerStore(container: container).mark(.notificationDispatch)

        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments: [String] = []
#if DEBUG
        if container.accessMode == .diagnostic {
            arguments.append(contentsOf: [
                "--env",
                "\(SharedContainer.diagnosticRootEnvironmentKey)=\(container.directoryURL.path)"
            ])
        }
#endif
        arguments.append(url.absoluteString)
        process.arguments = arguments

        do {
            try process.run()
            DiagnosticLog.append("notification dispatch wake requested")
        } catch {
            DiagnosticLog.append("notification dispatch wake failed: \(error.localizedDescription)")
        }
    }
}
