import Foundation
import UserNotifications

public protocol NotificationCenterClient: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

public final class SystemNotificationCenterClient: NotificationCenterClient {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}

public final class NotificationService {
    public enum AuthorizationState: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
    }

    private static let retryDelays: [TimeInterval] = [2, 10, 60]
    public static let foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .sound]
    public enum AppleMusicNotification {
        public static let formatCategoryIdentifier = "APPLE_MUSIC_DOWNLOAD_FORMAT"
        public static let alacActionIdentifier = "APPLE_MUSIC_DOWNLOAD_ALAC"
        public static let aacActionIdentifier = "APPLE_MUSIC_DOWNLOAD_AAC"
        public static let atmosActionIdentifier = "APPLE_MUSIC_DOWNLOAD_ATMOS"
        public static let completionCategoryIdentifier = "GET_OUDIO_COMPLETION"
        public static let copyInfoActionIdentifier = "GET_OUDIO_COPY_INFO"
        public static let appleMusicFailureCategoryIdentifier = "APPLE_MUSIC_DOWNLOAD_FAILURE"
        public static let copyErrorInfoActionIdentifier = "APPLE_MUSIC_COPY_ERROR_INFO"
        public static let copyInfoUserInfoKey = "copyInfo"
    }

    private let container: SharedContainer
    private let notificationCenter: any NotificationCenterClient

    public init(
        container: SharedContainer,
        notificationCenter: any NotificationCenterClient = SystemNotificationCenterClient()
    ) {
        self.container = container
        self.notificationCenter = notificationCenter
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        registerAppleMusicNotificationCategories()
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            DiagnosticLog.append("notification authorization requested granted=\(granted)")
            return granted
        } catch {
            DiagnosticLog.append("notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    public func authorizationState() async -> AuthorizationState {
        switch await notificationCenter.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
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
        let copyErrorAction = UNNotificationAction(
            identifier: AppleMusicNotification.copyErrorInfoActionIdentifier,
            title: "复制错误信息",
            options: []
        )
        let appleMusicFailureCategory = UNNotificationCategory(
            identifier: AppleMusicNotification.appleMusicFailureCategoryIdentifier,
            actions: [copyErrorAction],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([
            formatCategory,
            completionCategory,
            appleMusicFailureCategory
        ])
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
        guard [
            AppleMusicNotification.copyInfoActionIdentifier,
            AppleMusicNotification.copyErrorInfoActionIdentifier
        ].contains(response.actionIdentifier) else {
            return nil
        }
        return response.notification.request.content.userInfo[AppleMusicNotification.copyInfoUserInfoKey] as? String
    }

    public func notifyAppleMusicUnavailable() async {
        await notify(body: "Apple Music 下载暂时不可用", sound: nil)
    }

    public func notifyAppleMusicDownloadStarted() async {
        await notify(body: "下载Start！", sound: nil)
    }

    public func notifyRecordingStarted() async {
        await notify(body: "录音Start！", sound: nil)
    }

    public func notifyRecordingFinished(fileURL: URL?, message: String? = nil) async {
        _ = await send(
            recordingFinishedRequest(fileName: fileURL?.lastPathComponent, message: message),
            context: "recording finished"
        )
    }

    public func notifyUnsupportedDownloadSource(urls: [URL]) async {
        let suffix = urls.first.map { " \($0.absoluteString)" } ?? ""
        await notify(body: "不支持的下载源...\(suffix)", sound: nil)
    }

    public func notifyAppleMusicFormatSelection(jobCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Get Oudio"
        content.body = jobCount > 1
            ? "选择这 \(jobCount) 个项目的下载格式..."
            : "选择这次的下载格式..."
        content.sound = .default
        content.categoryIdentifier = AppleMusicNotification.formatCategoryIdentifier
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        await send(request, context: "Apple Music format selection count=\(jobCount)")
    }

    public func notifyAppleMusicDownloadInProgress(progress: String) async {
        await notify(body: progress, sound: nil)
    }

    public func notifyAppleMusicDownloadFinished(summary: ConversionSummary, jobs: [JobRequest]) async {
        await notifyConversionFinished(summary: summary, jobs: jobs)
    }

    @discardableResult
    public func dispatchPendingNotificationEvents(limit: Int = 20) async -> Int {
        do {
            let queue = try NotificationEventQueue(container: container)
            let claimedEvents = try queue.claimPending(limit: limit)
            let authorization = await authorizationState()
            for claimed in claimedEvents {
                guard authorization != .denied else {
                    queue.suppress(claimed, reason: "authorization denied")
                    continue
                }

                let accepted: Bool
                switch claimed.event.kind {
                case .conversionFinished:
                    guard let summary = claimed.event.summary else {
                        queue.suppress(claimed, reason: "missing conversion summary")
                        continue
                    }
                    accepted = await send(
                        conversionFinishedRequest(summary: summary, jobs: claimed.event.jobs, identifier: claimed.event.id.uuidString),
                        context: "conversion finished id=\(claimed.event.id.uuidString)"
                    )
                case .recordingFinished:
                    guard let recording = claimed.event.recording else {
                        queue.suppress(claimed, reason: "missing recording payload")
                        continue
                    }
                    accepted = await send(
                        recordingFinishedRequest(
                            fileName: recording.fileName,
                            message: recording.message,
                            identifier: claimed.event.id.uuidString
                        ),
                        context: "recording finished id=\(claimed.event.id.uuidString)"
                    )
                }

                if accepted {
                    queue.acknowledge(claimed)
                } else if claimed.event.attemptCount < Self.retryDelays.count {
                    queue.retry(claimed, after: Self.retryDelays[claimed.event.attemptCount])
                } else {
                    queue.suppress(claimed, reason: "schedule failed after retries")
                }
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
        }
    }

    public func enqueueRecordingFinished(fileURL: URL?, message: String? = nil) throws {
        try NotificationEventQueue(container: container).enqueueRecordingFinished(fileURL: fileURL, message: message)
    }

    public func enqueueAndWakeRecordingFinished(fileURL: URL?, message: String? = nil) throws {
        try enqueueRecordingFinished(fileURL: fileURL, message: message)
        NotificationDispatchWaker.wake(container: container)
    }

    public func nextPendingNotificationRetryDate() -> Date? {
        do {
            return try NotificationEventQueue(container: container).nextAttemptDate()
        } catch {
            DiagnosticLog.append("notification retry lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    public func notifyConversionFinished(summary: ConversionSummary, jobs: [JobRequest] = []) async {
        _ = await send(
            conversionFinishedRequest(summary: summary, jobs: jobs, identifier: UUID().uuidString),
            context: "conversion finished"
        )
    }

    private func conversionFinishedRequest(
        summary: ConversionSummary,
        jobs: [JobRequest],
        identifier: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let actionName = Self.actionName(for: jobs)
        let isAppleMusicDownload = Self.isAppleMusicDownload(jobs)
        content.title = "Get Oudio"
        content.sound = .default

        if isAppleMusicDownload {
            content.body = AppleMusicDownloadNotificationFormatter.completionMessage(
                successCount: summary.successCount,
                failureCount: summary.failureCount
            )
            if summary.failureCount > 0 {
                content.categoryIdentifier = AppleMusicNotification.appleMusicFailureCategoryIdentifier
                content.userInfo = [
                    AppleMusicNotification.copyInfoUserInfoKey: Self.copyInfo(summary: summary, jobs: jobs)
                ]
            }
        } else if summary.totalCount == 0 {
            content.categoryIdentifier = AppleMusicNotification.completionCategoryIdentifier
            content.userInfo = [
                AppleMusicNotification.copyInfoUserInfoKey: Self.copyInfo(summary: summary, jobs: jobs)
            ]
            content.body = "没有文件被处理，请确认选择了有效文件。"
        } else if summary.failureCount == 0 {
            content.categoryIdentifier = AppleMusicNotification.completionCategoryIdentifier
            content.userInfo = [
                AppleMusicNotification.copyInfoUserInfoKey: Self.copyInfo(summary: summary, jobs: jobs)
            ]
            content.body = "\(actionName)完成，处理了 \(summary.successCount) 个文件。"
        } else {
            content.categoryIdentifier = AppleMusicNotification.completionCategoryIdentifier
            content.userInfo = [
                AppleMusicNotification.copyInfoUserInfoKey: Self.copyInfo(summary: summary, jobs: jobs)
            ]
            let detail = Self.displayError(summary: summary).map { " \($0)" } ?? ""
            content.body = "\(actionName)基本完成，处理了 \(summary.totalCount) 个文件，成功 \(summary.successCount) 个，失败 \(summary.failureCount) 个。\(detail)"
        }

        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    private func notify(body: String, sound: UNNotificationSound? = .default) async {
        let content = UNMutableNotificationContent()
        content.title = "Get Oudio"
        content.body = body
        content.sound = sound
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        _ = await send(request, context: "notification title=Get Oudio")
    }

    private func recordingFinishedRequest(
        fileName: String?,
        message: String?,
        identifier: String = UUID().uuidString
    ) -> UNNotificationRequest {
        let result = fileName == nil ? "录音失败" : "录音已结束"
        let fallback = fileName.map { "复制了 \($0) 到剪贴板。" } ?? "没有生成可用的录音文件。"
        let detail = message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let content = UNMutableNotificationContent()
        content.title = "Get Oudio"
        content.body = "\(result)。\(detail)"
        content.sound = .default
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    @discardableResult
    private func send(_ request: UNNotificationRequest, context: String) async -> Bool {
        do {
            try await notificationCenter.add(request)
            DiagnosticLog.append("notification scheduled id=\(request.identifier) context=\(context)")
            return true
        } catch {
            DiagnosticLog.append("notification schedule failed context=\(context): \(error.localizedDescription)")
            return false
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

    private static func isAppleMusicDownload(_ jobs: [JobRequest]) -> Bool {
        guard !jobs.isEmpty else { return false }
        return jobs.allSatisfy { job in
            if case .appleMusicDownload = job.operation {
                return true
            }
            return false
        }
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
