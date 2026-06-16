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
    private let notificationService = NotificationService()

    // MARK: - Entry point

    static func main() {
        let app = NSApplication.shared
        let runner = HeadlessRunner()
        app.delegate = runner
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task {
            await processAndNotify()
            // Give the notification a moment to be delivered, then exit
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { NSApp.terminate(nil) }
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

    // MARK: - Job processing

    private func processAndNotify() async {
        // Clear extension launch markers so a subsequent direct launch isn't misidentified
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            defaults.removeObject(forKey: AppConstants.extensionLaunchSourceKey)
            defaults.removeObject(forKey: AppConstants.extensionLaunchTimestampKey)
            defaults.synchronize()
        }

        let jobs: [JobRequest]
        do {
            let queue = try JobQueue()
            jobs = try queue.drain()
        } catch {
            DiagnosticLog.append("headless queue drain failed: \(error.localizedDescription)")
            return
        }

        guard !jobs.isEmpty else {
            DiagnosticLog.append("headless no pending jobs")
            return
        }

        DiagnosticLog.append("headless processing \(jobs.count) jobs")
        let summary = await execute(jobs)
        DiagnosticLog.append("headless done success=\(summary.successCount) fail=\(summary.failureCount)")

        // Write conversion log
        writeConversionLog(summary: summary, jobs: jobs)

        // Notify
        let content = UNMutableNotificationContent()
        content.title = "Get Oudio"
        if summary.failureCount == 0 {
            content.body = "全部完成：\(summary.successCount) 个任务"
        } else {
            content.body = "完成 \(summary.successCount) 个，失败 \(summary.failureCount) 个"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            DiagnosticLog.append("headless notification failed: \(error.localizedDescription)")
        }
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
