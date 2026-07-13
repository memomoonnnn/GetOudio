import AVFoundation
import AppKit
import GetOudioCore
import UserNotifications
import WidgetKit

final class RecordingRunner: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let container: SharedContainer
    private let settings: SettingsStore
    private let controlStore: RecordingControlStore
    private let cacheStore: RecordingCacheStore
    private let notificationService: NotificationService
    private let postProcessor = RecordingPostProcessor()
    private var session: RecordingAudioSession?
    private var controlSignal: RecordingControlSignal?
    private var stopStarted = false
    private var sleepObserver: NSObjectProtocol?
    private var healthTimer: Timer?
    private var recordingStartedAt: Date?
    private var reportedNoInputCallbacks = false
    private var reportedSilentInput = false

    init(container: SharedContainer) throws {
        self.container = container
        settings = SettingsStore(container: container)
        controlStore = try RecordingControlStore(container: container)
        cacheStore = try RecordingCacheStore(container: container)
        notificationService = NotificationService(container: container)
        super.init()
    }

    static func main(container: SharedContainer) {
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let runner = try RecordingRunner(container: container)
            app.delegate = runner
            app.run()
        } catch {
            DiagnosticLog.append("recording runner init failed: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        for window in NSApp.windows { window.close() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.append("[Recording] runner did finish launching pid=\(ProcessInfo.processInfo.processIdentifier)")
        UNUserNotificationCenter.current().delegate = self
        controlSignal = RecordingControlSignal { [weak self] in
            DispatchQueue.main.async { self?.consumeCommands() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop(reason: .systemSleep, message: "系统即将睡眠")
        }
        LaunchMarkerStore(container: container).clear()
        Task {
            await notificationService.requestAuthorization()
            await startIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        healthTimer?.invalidate()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        stop(reason: .user, message: nil)
    }

    private func startIfRequested() async {
        let commands = controlStore.drainCommands()
        DiagnosticLog.append("[Recording] runner drained commands count=\(commands.count) latest=\(commands.last?.kind.rawValue ?? "none")")
        if commands.contains(where: { $0.kind == .stop }) {
            var snapshot = controlStore.snapshot()
            if snapshot.phase == .starting {
                snapshot.phase = .idle
                snapshot.runnerPID = nil
                snapshot.stopReason = .user
                snapshot.errorMessage = nil
                try? controlStore.save(snapshot)
            }
            reloadWidget()
            await MainActor.run { NSApp.terminate(nil) }
            return
        }
        guard let latestCommand = commands.last, latestCommand.kind == .start else {
            var snapshot = controlStore.snapshot()
            if snapshot.phase == .starting {
                snapshot.phase = .idle
                snapshot.runnerPID = nil
                try? controlStore.save(snapshot)
            }
            reloadWidget()
            await MainActor.run { NSApp.terminate(nil) }
            return
        }
        do {
            try await startRecording()
        } catch {
            await failStartup(error)
        }
    }

    private func startRecording() async throws {
        DiagnosticLog.append("[Recording] runner start preflight begin")
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingDeviceError.deviceNotFound("未获得音频输入权限")
        }
        guard let bridgeUID = settings.recordingBridgeDeviceUID,
              let bridge = RecordingDeviceService.descriptor(uid: bridgeUID),
              bridge.isSupportedProToolsAudioBridge else {
            throw RecordingDeviceError.deviceNotFound("Pro Tools Audio Bridge 2-A/2-B")
        }
        let originalUID = try RecordingDeviceService.defaultOutputDeviceUID()
        guard originalUID != bridgeUID,
              RecordingDeviceService.descriptor(uid: originalUID)?.outputChannelCount ?? 0 > 0 else {
            throw RecordingDeviceError.deviceNotFound("原播放设备")
        }
        DiagnosticLog.append(
            "[Recording] runner devices bridge=\(bridge.name) inputChannels=\(bridge.inputChannelCount) " +
            "monitorUID=\(originalUID)"
        )

        cacheStore.enforceLimit(settings.recordingCacheLimitBytes)
        var snapshot = controlStore.snapshot()
        guard snapshot.phase == .starting else {
            throw RecordingDeviceError.deviceNotFound("录音会话预约")
        }
        let temporaryURL = cacheStore.makeTemporaryFileURL(id: snapshot.id)
        snapshot.runnerPID = ProcessInfo.processInfo.processIdentifier
        snapshot.bridgeDeviceUID = bridgeUID
        snapshot.originalOutputDeviceUID = originalUID
        snapshot.temporaryFileURL = temporaryURL
        snapshot.startedAt = snapshot.startedAt ?? Date()
        try controlStore.save(snapshot)
        reloadWidget()
        DiagnosticLog.append("[Recording] runner snapshot phase=starting temporaryFile=\(temporaryURL.lastPathComponent)")

        let audioSession = try RecordingAudioSession(
            bridgeUID: bridgeUID,
            monitorUID: originalUID,
            outputURL: temporaryURL
        ) { [weak self] reason, message in
            DispatchQueue.main.async { self?.stop(reason: reason, message: message) }
        }
        session = audioSession
        snapshot.sampleRate = audioSession.sampleRate
        snapshot.channelCount = audioSession.channelCount
        try controlStore.save(snapshot)
        try audioSession.start()
        DiagnosticLog.append("[Recording] audio session started; switching default output")
        try RecordingDeviceService.setDefaultOutputDevice(uid: bridgeUID)
        try audioSession.verifyMonitorDevice()
        snapshot.phase = .recording
        try controlStore.save(snapshot)
        reloadWidget()
        beginHealthChecks()
        DiagnosticLog.append("[Recording] recording started bridge=\(bridge.name) sampleRate=\(audioSession.sampleRate) channels=\(audioSession.channelCount)")
    }

    private func consumeCommands() {
        guard controlStore.drainCommands().contains(where: { $0.kind == .stop }) else { return }
        stop(reason: .user, message: nil)
    }

    private func stop(reason: RecordingStopReason, message: String?) {
        guard !stopStarted else { return }
        stopStarted = true
        healthTimer?.invalidate()
        healthTimer = nil
        DiagnosticLog.append("[Recording] stop begin reason=\(reason.rawValue) message=\(message ?? "none")")
        var snapshot = controlStore.snapshot()
        snapshot.phase = .stopping
        snapshot.stopReason = reason
        snapshot.errorMessage = message
        try? controlStore.save(snapshot)
        reloadWidget()

        session?.stopCapture()
        RecordingDeviceService.restoreDefaultOutput(
            preferredUID: snapshot.originalOutputDeviceUID,
            excluding: snapshot.bridgeDeviceUID
        )

        Task.detached { [weak self] in
            guard let self else { return }
            var finalURL: URL?
            var finalMessage = message
            do {
                try self.session?.finalize()
                if let temporaryURL = snapshot.temporaryFileURL {
                    let cachedURL = self.cacheStore.completedURL(for: temporaryURL)
                    try FileManager.default.moveItem(at: temporaryURL, to: cachedURL)
                    let processedURL = self.processCompletedRecording(cachedURL, message: &finalMessage)
                    finalURL = self.moveToCustomDirectoryIfNeeded(processedURL)
                }
            } catch {
                finalMessage = error.localizedDescription
            }

            if let finalURL {
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([finalURL as NSURL])
                }
            }
            var completed = snapshot
            completed.phase = finalURL == nil ? .failed : .idle
            completed.runnerPID = nil
            completed.temporaryFileURL = finalURL
            completed.errorMessage = finalMessage
            try? self.controlStore.save(completed)
            self.reloadWidget()
            await self.notificationService.notifyRecordingFinished(fileURL: finalURL, message: finalMessage)
            await MainActor.run { NSApp.terminate(nil) }
        }
    }

    private func moveToCustomDirectoryIfNeeded(_ cachedURL: URL) -> URL {
        guard settings.recordingUsesCustomOutputDirectory,
              let bookmark = settings.recordingCustomOutputBookmarkData else { return cachedURL }
        do {
            var stale = false
            let directory = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard directory.startAccessingSecurityScopedResource() else { return cachedURL }
            defer { directory.stopAccessingSecurityScopedResource() }
            let destination = directory.appendingPathComponent(cachedURL.lastPathComponent)
            let staging = destination.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.copyItem(at: cachedURL, to: staging)
            try FileManager.default.moveItem(at: staging, to: destination)
            try FileManager.default.removeItem(at: cachedURL)
            return destination
        } catch {
            DiagnosticLog.append("recording custom output fallback: \(error.localizedDescription)")
            return cachedURL
        }
    }

    private func processCompletedRecording(_ cachedURL: URL, message: inout String?) -> URL {
        switch postProcessor.process(recordingURL: cachedURL, options: settings.recordingPostProcessingOptions) {
        case .processed(let stagingURL):
            do {
                return try cacheStore.replaceCompletedFile(at: cachedURL, with: stagingURL)
            } catch {
                try? FileManager.default.removeItem(at: stagingURL)
                appendPostProcessingMessage("录后处理成品替换失败，已保留原始录音：\(error.localizedDescription)", to: &message)
                return cachedURL
            }
        case .keptOriginal(let processingMessage):
            if let processingMessage {
                appendPostProcessingMessage(processingMessage, to: &message)
            }
            return cachedURL
        }
    }

    private func appendPostProcessingMessage(_ newMessage: String, to message: inout String?) {
        if let existingMessage = message, !existingMessage.isEmpty {
            message = "\(existingMessage)；\(newMessage)"
        } else {
            message = newMessage
        }
    }

    private func failStartup(_ error: Error) async {
        DiagnosticLog.append("[Recording] startup failed error=\(error.localizedDescription)")
        healthTimer?.invalidate()
        healthTimer = nil
        let snapshot = controlStore.snapshot()
        session?.stopCapture()
        try? session?.finalize()
        if let temporaryURL = snapshot.temporaryFileURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        RecordingDeviceService.restoreDefaultOutput(
            preferredUID: snapshot.originalOutputDeviceUID,
            excluding: snapshot.bridgeDeviceUID
        )
        var failed = snapshot
        failed.phase = .failed
        failed.runnerPID = nil
        failed.stopReason = .startupFailure
        failed.errorMessage = error.localizedDescription
        try? controlStore.save(failed)
        reloadWidget()
        await notificationService.notifyRecordingFinished(fileURL: nil, message: error.localizedDescription)
        await MainActor.run { NSApp.terminate(nil) }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.recordingWidgetKind)
    }

    private func beginHealthChecks() {
        healthTimer?.invalidate()
        recordingStartedAt = Date()
        reportedNoInputCallbacks = false
        reportedSilentInput = false
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkRecordingHealth()
        }
    }

    private func checkRecordingHealth() {
        guard let session else { return }
        if let issue = session.takeRealtimeIssue() {
            DiagnosticLog.append("[Recording] deferred realtime issue reason=\(issue.reason.rawValue) message=\(issue.message)")
            stop(reason: issue.reason, message: issue.message)
            return
        }
        guard let recordingStartedAt,
              Date().timeIntervalSince(recordingStartedAt) >= 3 else { return }
        let diagnostics = session.inputDiagnosticSnapshot()
        if diagnostics.callbackCount == 0, !reportedNoInputCallbacks {
            reportedNoInputCallbacks = true
            DiagnosticLog.append("[Recording] input health: no callbacks after 3s; Audio Bridge may be stalled. Refresh its Input/Output page in Audio MIDI Setup. lastSampleTime=\(diagnostics.lastSampleTime) lastHostTime=\(diagnostics.lastHostTime)")
        } else if diagnostics.callbackCount > 0,
                  diagnostics.writtenFrameCount > 0,
                  diagnostics.nonSilentBlockCount == 0,
                  !reportedSilentInput {
            reportedSilentInput = true
            DiagnosticLog.append("[Recording] input health: callbacks and PCM writes are active but every block is silent; keeping recording active because silence can be valid. Audio Bridge may require a refresh. callbacks=\(diagnostics.callbackCount) writtenFrames=\(diagnostics.writtenFrameCount) lastSampleTime=\(diagnostics.lastSampleTime) lastHostTime=\(diagnostics.lastHostTime)")
        }
    }
}
