import Foundation

enum OpenFileNotificationKey {
    static let urls = "urls"
}

extension Notification.Name {
    static let getOudioOpenFiles = Notification.Name("GetOudioOpenFiles")
}

