import Foundation
import UserNotifications

public final class NotificationService {
    public enum AppleMusicNotification {
        public static let formatCategoryIdentifier = "APPLE_MUSIC_DOWNLOAD_FORMAT"
        public static let alacActionIdentifier = "APPLE_MUSIC_DOWNLOAD_ALAC"
        public static let aacActionIdentifier = "APPLE_MUSIC_DOWNLOAD_AAC"
        public static let atmosActionIdentifier = "APPLE_MUSIC_DOWNLOAD_ATMOS"
        public static let completionCategoryIdentifier = "GET_OUDIO_COMPLETION"
        public static let copyInfoActionIdentifier = "GET_OUDIO_COPY_INFO"
        public static let copyInfoUserInfoKey = "copyInfo"
    }

    private let container: SharedContainer

    public init(container: SharedContainer) {
        self.container = container
    }

    public func requestAuthorization() async {
        registerAppleMusicNotificationCategories()
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            DiagnosticLog.append("notification authorization requested granted=\(granted)")
        } catch {
            DiagnosticLog.append("notification authorization failed: \(error.localizedDescription)")
        }
    }

    public func registerAppleMusicNotificationCategories() {
        let actions = [
            UNNotificationAction(
                identifier: AppleMusicNotification.alacActionIdentifier,
                title: AppleMusicDownloadFormat.alac.displayName,
                options: []
            ),
            UNNotificationAction(
                identifier: AppleMusicNotification.aacActionIdentifier,
                title: AppleMusicDownloadFormat.aac.displayName,
                options: []
            ),
            UNNotificationAction(
                identifier: AppleMusicNotification.atmosActionIdentifier,
                title: AppleMusicDownloadFormat.atmos.displayName,
                options: []
            )
        ]
        let formatCategory = UNNotificationCategory(
            identifier: AppleMusicNotification.formatCategoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        let copyAction = UNNotificationAction(
            identifier: AppleMusicNotification.copyInfoActionIdentifier,
            title: "复制信息",
            options: []
        )
        let completionCategory = UNNotificationCategory(
            identifier: AppleMusicNotification.completionCategoryIdentifier,
            actions: [copyAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([formatCategory, completionCategory])
    }

    public func appleMusicFormat(for actionIdentifier: String) -> AppleMusicDownloadFormat? {
        switch actionIdentifier {
        case AppleMusicNotification.alacActionIdentifier:
            return .alac
        case AppleMusicNotification.aacActionIdentifier:
            return .aac
        case AppleMusicNotification.atmosActionIdentifier:
            return .atmos
        default:
            return nil
        }
    }

    public func copyInfo(for response: UNNotificationResponse) -> String? {
        guard response.actionIdentifier == AppleMusicNotification.copyInfoActionIdentifier else {
            return nil
        }
        return response.notification.request.content.userInfo[AppleMusicNotification.copyInfoUserInfoKey] as? String
    }

    public func notifyAppleMusicInactive() async {
        await notify(title: "Get Oudio", body: "该功能尚未激活")
    }

    public func notifyRecordingFinished(fileURL: URL?, message: String? = nil) async {
        let title = fileURL == nil ? "录音未完成" : "录音完成"
        let fallback = fileURL.map { "已复制 \($0.lastPathComponent) 到剪贴板。" } ?? "没有生成可用的录音文件。"
        let body = message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        await notify(title: title, body: body)
    }

    public func notifyUnsupportedDownloadSource(urls: [URL]) async {
        let suffix = urls.first.map { " \($0.absoluteString)" } ?? ""
        await notify(title: "Get Oudio", body: "不支持的下载源...\(suffix)")
    }

    public func notifyAppleMusicFormatSelection(jobCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "选择 Apple Music 下载格式"
        content.body = jobCount > 1 ? "请选择这 \(jobCount) 个项目的下载格式。" : "请选择这次的下载格式。"
        content.sound = .default
        content.categoryIdentifier = AppleMusicNotification.formatCategoryIdentifier
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        await send(request, context: "Apple Music format selection count=\(jobCount)")
    }

    public func notifyAppleMusicDownloadInProgress(elapsed: TimeInterval, progress: String? = nil) async {
        let seconds = max(0, Int(elapsed.rounded()))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        let elapsedText = minutes > 0 ? "\(minutes)分\(remainingSeconds)秒" : "\(remainingSeconds)秒"
        let detail = progress?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            await notify(title: "Get Oudio", body: "下载中... \(detail)（已用 \(elapsedText)）")
        } else {
            await notify(title: "Get Oudio", body: "下载中... 已经过 \(elapsedText)")
        }
    }

    public func notifyAppleMusicDownloadFinished(summary: ConversionSummary, jobs: [JobRequest]) async {
        await notifyConversionFinished(summary: summary, jobs: jobs)
    }

    @discardableResult
    public func dispatchPendingNotificationEvents(limit: Int = 20) async -> Int {
        do {
            let queue = try NotificationEventQueue(container: container)
            let claimedEvents = try queue.claimPending(limit: limit)
            for claimed in claimedEvents {
                switch claimed.event.kind {
                case .conversionFinished:
                    await notifyConversionFinished(summary: claimed.event.summary, jobs: claimed.event.jobs)
                }
                queue.acknowledge(claimed)
            }
            return claimedEvents.count
        } catch {
            DiagnosticLog.append("notification event dispatch failed: \(error.localizedDescription)")
            return 0
        }
    }

    public func enqueueAndDispatchConversionFinished(summary: ConversionSummary, jobs: [JobRequest]) async {
        do {
            try NotificationEventQueue(container: container).enqueueConversionFinished(summary: summary, jobs: jobs)
            await dispatchPendingNotificationEvents()
        } catch {
            DiagnosticLog.append("notification event enqueue failed: \(error.localizedDescription)")
            await notifyConversionFinished(summary: summary, jobs: jobs)
        }
    }

    public func notifyConversionFinished(summary: ConversionSummary, jobs: [JobRequest] = []) async {
        let content = UNMutableNotificationContent()
        let actionName = Self.actionName(for: jobs)
        content.categoryIdentifier = AppleMusicNotification.completionCategoryIdentifier
        content.sound = .default
        content.userInfo = [
            AppleMusicNotification.copyInfoUserInfoKey: Self.copyInfo(summary: summary, jobs: jobs)
        ]

        if summary.totalCount == 0 {
            content.title = "没有文件被处理"
            content.body = "请确认选择了有效文件。"
        } else if summary.failureCount == 0 {
            content.title = "\(actionName)完成"
            content.body = "成功处理 \(summary.successCount) 个文件。"
        } else {
            content.title = "\(actionName)完成，但有错误"
            let detail = Self.displayError(summary: summary).map { " \($0)" } ?? ""
            content.body = "共处理 \(summary.totalCount) 个文件，成功 \(summary.successCount) 个，失败 \(summary.failureCount) 个。\(detail)"
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        await send(
            request,
            context: "conversion finished action=\(actionName) success=\(summary.successCount) failure=\(summary.failureCount)"
        )
    }

    private func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        await send(request, context: "notification title=\(title)")
    }

    private func send(_ request: UNNotificationRequest, context: String) async {
        do {
            try await UNUserNotificationCenter.current().add(request)
            DiagnosticLog.append("notification scheduled id=\(request.identifier) context=\(context)")
        } catch {
            DiagnosticLog.append("notification schedule failed context=\(context): \(error.localizedDescription)")
        }
    }

    private static func actionName(for jobs: [JobRequest]) -> String {
        guard !jobs.isEmpty else {
            return "转换"
        }

        var hasTranscode = false
        var hasExtractAudio = false
        var hasNCM = false
        var hasAppleMusic = false

        for job in jobs {
            switch job.operation {
            case .transcode:
                hasTranscode = true
            case .extractAudio:
                hasExtractAudio = true
            case .convertNCM:
                hasNCM = true
            case .appleMusicDownload:
                hasAppleMusic = true
            }
        }

        let operationCount = [hasTranscode, hasExtractAudio, hasNCM, hasAppleMusic].filter { $0 }.count
        guard operationCount == 1 else {
            return "处理"
        }

        if hasTranscode {
            return "音频转换"
        }
        if hasExtractAudio {
            return "视频音频提取"
        }
        if hasNCM {
            return "NCM 转换"
        }
        return "Apple Music 下载"
    }

    private static func displayError(summary: ConversionSummary) -> String? {
        summary.messages.lazy.compactMap {
            AppleMusicDownloadMessageFormatter.displayMessage(from: $0)
        }.first
    }

    private static func copyInfo(summary: ConversionSummary, jobs: [JobRequest]) -> String {
        var lines = [
            "Result: success=\(summary.successCount) failure=\(summary.failureCount) total=\(summary.totalCount)"
        ]
        if !jobs.isEmpty {
            lines.append("Jobs:")
            lines.append(contentsOf: jobs.map { $0.fileURL.absoluteString })
        }
        if !summary.messages.isEmpty {
            lines.append("Messages:")
            for message in summary.messages {
                let core = AppleMusicDownloadMessageFormatter.coreMessage(from: message, maxLines: 20)
                lines.append(core.isEmpty ? message : core)
            }
        }
        return lines.joined(separator: "\n")
    }
}
