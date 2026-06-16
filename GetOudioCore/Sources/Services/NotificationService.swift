import Foundation
import UserNotifications

public final class NotificationService {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func notifyConversionFinished(summary: ConversionSummary, jobs: [JobRequest] = []) async {
        let content = UNMutableNotificationContent()
        let actionName = Self.actionName(for: jobs)

        if summary.totalCount == 0 {
            content.title = "没有文件被处理"
            content.body = "请确认选择了有效文件。"
        } else if summary.failureCount == 0 {
            content.title = "\(actionName)完成"
            content.body = "成功处理 \(summary.successCount) 个文件。"
        } else {
            content.title = "\(actionName)完成，但有错误"
            let detail = summary.messages.first.map { " \($0)" } ?? ""
            content.body = "共处理 \(summary.totalCount) 个文件，成功 \(summary.successCount) 个，失败 \(summary.failureCount) 个。\(detail)"
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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
}
