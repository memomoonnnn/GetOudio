import AppKit
import GetOudioCore
import UserNotifications

/// Runs in headless mode: drains the shared job queue, processes every job
/// in the background, posts a UserNotification, then terminates.
/// No windows are ever created — the user only sees the notification banner.
final class HeadlessRunner: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private let audioService = AudioConversionService()
    private let mediaService = MediaExtractionService()
    private let ncmService = NCMConversionService()
    private let amService = AppleMusicDownloadService()
    private let appleMusicAgentLauncher = AppleMusicRuntimeAgentLauncher.shared
    private let notificationService = NotificationService()
    private let appleMusicShareCoordinator = AppleMusicShareDownloadCoordinator()
    private let lifecycleLock = NSLock()
    private var launchProcessingFinished = false
    private var activeNotificationResponses = 0
    private var terminationTask: Task<Void, Never>?

    // MARK: - Entry point

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = HeadlessRunner()
        app.delegate = runner
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Belt and suspenders: close any phantom window the system may have created
        for window in NSApp.windows {
            window.close()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Double-check no windows survived
        for window in NSApp.windows {
            window.close()
        }

        UNUserNotificationCenter.current().delegate = self

        Task {
            await notificationService.requestAuthorization()
            await processAndNotify()
            markLaunchProcessingFinished()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let copyInfo = notificationService.copyInfo(for: response) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyInfo, forType: .string)
            completionHandler()
            return
        }

        guard let format = notificationService.appleMusicFormat(for: response.actionIdentifier) else {
            completionHandler()
            return
        }

        beginNotificationResponse()
        Task {
            await appleMusicShareCoordinator.handlePendingAppleMusicDownload(format: format)
            completionHandler()
            endNotificationResponse()
        }
    }

    private func beginNotificationResponse() {
        lifecycleLock.lock()
        activeNotificationResponses += 1
        terminationTask?.cancel()
        terminationTask = nil
        let activeCount = activeNotificationResponses
        lifecycleLock.unlock()
        DiagnosticLog.append("headless notification response started active=\(activeCount)")
    }

    private func endNotificationResponse() {
        lifecycleLock.lock()
        activeNotificationResponses = max(0, activeNotificationResponses - 1)
        let shouldScheduleTermination = launchProcessingFinished
        let activeCount = activeNotificationResponses
        lifecycleLock.unlock()

        DiagnosticLog.append("headless notification response finished active=\(activeCount)")
        if shouldScheduleTermination {
            scheduleTerminationWhenIdle(reason: "notification response")
        }
    }

    private func markLaunchProcessingFinished() {
        lifecycleLock.lock()
        launchProcessingFinished = true
        lifecycleLock.unlock()
        scheduleTerminationWhenIdle(reason: "launch processing")
    }

    private func scheduleTerminationWhenIdle(reason: String) {
        lifecycleLock.lock()
        guard activeNotificationResponses == 0 else {
            let activeCount = activeNotificationResponses
            lifecycleLock.unlock()
            DiagnosticLog.append("headless termination deferred reason=\(reason) active=\(activeCount)")
            return
        }

        terminationTask?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.canTerminateNow() else { return }
            DiagnosticLog.append("headless terminating reason=\(reason)")
            await MainActor.run { NSApp.terminate(nil) }
        }
        terminationTask = task
        lifecycleLock.unlock()
    }

    private func canTerminateNow() -> Bool {
        lifecycleLock.lock()
        let canTerminate = activeNotificationResponses == 0
        lifecycleLock.unlock()
        return canTerminate
    }

    // MARK: - Job processing

    private func processAndNotify() async {
        // Clear extension launch markers so a subsequent direct launch isn't misidentified
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            defaults.removeObject(forKey: AppConstants.extensionLaunchSourceKey)
            defaults.removeObject(forKey: AppConstants.extensionLaunchTimestampKey)
            defaults.synchronize()
        }

        await notificationService.dispatchPendingNotificationEvents()

        let shareEvents: [ShareEvent]
        let jobs: [JobRequest]
        do {
            let eventQueue = try ShareEventQueue()
            shareEvents = try eventQueue.drain()
            await appleMusicShareCoordinator.notifyShareEvents(shareEvents)

            let queue = try JobQueue()
            jobs = try queue.drain()
        } catch {
            DiagnosticLog.append("headless queue drain failed: \(error.localizedDescription)")
            return
        }

        let remainingJobs = await appleMusicShareCoordinator.handleShareAppleMusicJobs(jobs)
        guard !jobs.isEmpty else {
            DiagnosticLog.append(shareEvents.isEmpty ? "headless no pending jobs" : "headless processed share events")
            return
        }
        guard !remainingJobs.isEmpty else {
            DiagnosticLog.append("headless processed share Apple Music jobs")
            return
        }

        DiagnosticLog.append("headless processing \(remainingJobs.count) jobs")
        let summary = await execute(remainingJobs)
        DiagnosticLog.append("headless done success=\(summary.successCount) fail=\(summary.failureCount)")

        // Write conversion log
        writeConversionLog(summary: summary, jobs: remainingJobs)

        await notificationService.enqueueAndDispatchConversionFinished(summary: summary, jobs: remainingJobs)
    }

    // MARK: - Job execution (same logic as AppModel)

    private func execute(_ jobs: [JobRequest]) async -> ConversionSummary {
        var totalSuccess = 0
        var totalFailure = 0
        var messages: [String] = []

        let transcodeJobs = jobs.filter { if case .transcode = $0.operation { true } else { false } }
        let extractJobs = jobs.filter { $0.operation == .extractAudio }
        let ncmJobs = jobs.filter { $0.operation == .convertNCM }
        let amJobs = jobs.filter { if case .appleMusicDownload = $0.operation { true } else { false } }

        let onProgress: @Sendable (JobRequest, JobProgressPhase, String?) -> Void = { job, phase, msg in
            DiagnosticLog.append("headless progress \(job.fileURL.lastPathComponent) → \(phase.rawValue)\(msg.map { " | \($0)" } ?? "")")
        }

        if !transcodeJobs.isEmpty {
            let s = await audioService.convert(transcodeJobs, progressHandler: onProgress)
            totalSuccess += s.successCount; totalFailure += s.failureCount; messages += s.messages
        }
        if !extractJobs.isEmpty {
            let s = await mediaService.extractAudio(from: extractJobs, progressHandler: onProgress)
            totalSuccess += s.successCount; totalFailure += s.failureCount; messages += s.messages
        }
        if !ncmJobs.isEmpty {
            let s = await ncmService.convert(ncmJobs, progressHandler: onProgress)
            totalSuccess += s.successCount; totalFailure += s.failureCount; messages += s.messages
        }
        if !amJobs.isEmpty {
            try? await appleMusicAgentLauncher.ensureRunning()
            let s = await amService.download(amJobs)
            totalSuccess += s.successCount; totalFailure += s.failureCount; messages += s.messages
        }

        return ConversionSummary(successCount: totalSuccess, failureCount: totalFailure, messages: messages)
    }

    private func writeConversionLog(summary: ConversionSummary, jobs: [JobRequest]) {
        do {
            let logURL = try SharedContainer.conversionLogFileURL()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var lines = [
                "===== \(timestamp) (headless) =====",
                "Result: success=\(summary.successCount) failure=\(summary.failureCount)"
            ]
            for job in jobs {
                lines.append("Job: \(job.fileURL.path)")
            }
            if summary.messages.isEmpty {
                lines.append("Messages: <none>")
            } else {
                lines.append("Messages:")
                lines.append(contentsOf: summary.messages)
            }
            lines.append("")
            let data = (lines.joined(separator: "\n")).data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            DiagnosticLog.append("headless log write failed: \(error.localizedDescription)")
        }
    }
}
