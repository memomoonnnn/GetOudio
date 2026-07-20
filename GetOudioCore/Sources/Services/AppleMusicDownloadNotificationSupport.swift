import Foundation

public enum AppleMusicDownloadNotificationFormatter {
    public static func progressMessage(
        content: AppleMusicDownloaderEvent.Content?,
        phase: String?,
        fraction: Double?,
        isSingleTrack: Bool
    ) -> String? {
        let trackName = [content?.artist, content?.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let subject = trackName.isEmpty ? "Apple Music" : trackName

        let action: String
        switch phase {
        case "downloading":
            guard let fraction else { return nil }
            let percentage = Int((min(1, max(0, fraction)) * 100).rounded())
            action = "下载\(percentage)%"
        case "decrypting":
            action = "正在解密"
        case "tagging":
            action = "正在写入元数据"
        default:
            return nil
        }

        guard !isSingleTrack else {
            return "\(action)：\(subject)"
        }

        let collectionName = [content?.playlistTitle, content?.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Apple Music"
        if let position = content?.position, position > 0,
           let total = content?.total, total > 0 {
            return "( \(position)/\(total) ) \(action)：《\(collectionName)》 \(subject)"
        }
        return "\(action)：《\(collectionName)》 \(subject)"
    }

    public static func completionMessage(successCount: Int, failureCount: Int) -> String {
        "下载完成：成功 \(successCount) 首，失败 \(failureCount) 首。"
    }
}

public struct AppleMusicDownloadNotificationGate: Sendable {
    private var lastNotificationVersion: String?

    public init(lastNotificationVersion: String? = nil) {
        self.lastNotificationVersion = lastNotificationVersion
    }

    public mutating func nextMessage(for progress: AppleMusicRuntimeProgress?) -> String? {
        guard let progress,
              progress.isActive,
              let version = progress.notificationVersion,
              version != lastNotificationVersion
        else {
            return nil
        }

        lastNotificationVersion = version
        let message = progress.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}
