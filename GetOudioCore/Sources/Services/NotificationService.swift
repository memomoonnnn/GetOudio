import Foundation
import UserNotifications

public final class NotificationService {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func notifyConversionFinished(summary: ConversionSummary) async {
        let content = UNMutableNotificationContent()

        if summary.totalCount == 0 {
            content.title = "没有文件被处理"
            content.body = "请确认选择了有效文件。"
        } else if summary.failureCount == 0 {
            content.title = "所有文件转换完成"
            content.body = "成功转换 \(summary.successCount) 个文件。"
        } else {
            content.title = "转换完成，但有错误"
            content.body = "共处理 \(summary.totalCount) 个文件，成功 \(summary.successCount) 个，失败 \(summary.failureCount) 个。"
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

