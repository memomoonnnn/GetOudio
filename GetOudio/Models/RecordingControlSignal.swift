import CoreFoundation
import Foundation
import GetOudioCore

final class RecordingControlSignal {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            recordingSignalCallback,
            AppConstants.recordingControlNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(AppConstants.recordingControlNotification as CFString),
            nil
        )
    }

    func receive() {
        handler()
    }

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppConstants.recordingControlNotification as CFString),
            nil,
            nil,
            true
        )
    }
}

private func recordingSignalCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    Unmanaged<RecordingControlSignal>.fromOpaque(observer).takeUnretainedValue().receive()
}

