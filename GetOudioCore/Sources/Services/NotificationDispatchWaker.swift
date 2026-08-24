import Foundation

public enum NotificationDispatchWaker {
    /// Completion producers have no notification ownership. They ask the
    /// persistent Agent to claim and submit the durable Outbox event instead.
    public static func wake(container _: AgentDataStore) {
        Task {
            await dispatchPendingEvents()
        }
    }

    public static func dispatchPendingEvents() async {
        do {
            try await BackgroundAgentClient().dispatchNotificationEvents()
        } catch {
            DiagnosticLog.append("notification dispatch request failed: \(error.localizedDescription)")
        }
    }
}
