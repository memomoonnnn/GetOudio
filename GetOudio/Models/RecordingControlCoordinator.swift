import AVFoundation
import AppKit
import Darwin
import Foundation
import GetOudioCore
import WidgetKit

final class RecordingControlCoordinator {
    enum ToggleResult {
        case launchedRunner
        case requestedStop
        case needsConfiguration
        case failed(String)
    }

    private let container: SharedContainer
    private let store: SettingsStore
    private let controlStore: RecordingControlStore?
    private var supervisionTimer: Timer?
    private var supervisionSawActiveState = false
    private var supervisionStartedAt = Date.distantPast

    init(container: SharedContainer) {
        self.container = container
        store = SettingsStore(container: container)
        do {
            controlStore = try RecordingControlStore(container: container)
        } catch {
            controlStore = nil
            DiagnosticLog.append("[Recording] control store unavailable error=\(error.localizedDescription)")
        }
    }

    func toggle(onRunnerFinished: @escaping () -> Void) -> ToggleResult {
        guard let controlStore else {
            return .failed("录音共享状态不可用，请检查 App Group 配置。")
        }
        let snapshot = controlStore.snapshot()
        DiagnosticLog.append("[Recording] toggle coordinator phase=\(snapshot.phase.rawValue) runnerPID=\(snapshot.runnerPID.map(String.init) ?? "none")")
        if snapshot.phase.isActive {
            do {
                try controlStore.enqueue(.stop)
                RecordingControlSignal.post()
                DiagnosticLog.append("[Recording] stop command enqueued and signal posted")
                return .requestedStop
            } catch {
                DiagnosticLog.append("[Recording] stop command enqueue failed error=\(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
        }

        if let failure = preflightFailure() {
            DiagnosticLog.append("[Recording] preflight failed: \(failure)")
            return .needsConfiguration
        }

        do {
            guard let reservation = try controlStore.reserveStart() else {
                try controlStore.enqueue(.stop)
                RecordingControlSignal.post()
                DiagnosticLog.append("[Recording] concurrent toggle converted to stop request")
                return .requestedStop
            }
            LaunchMarkerStore(container: container).mark(.recording)
            DiagnosticLog.append("[Recording] preflight passed; session reserved id=\(reservation.id.uuidString) and launch marker written")
            launchNewAppInstance(sessionID: reservation.id)
            beginSupervision(sessionID: reservation.id, onFinished: onRunnerFinished)
            return .launchedRunner
        } catch {
            DiagnosticLog.append("[Recording] start command setup failed error=\(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func preflightFailure() -> String? {
        let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authorization == .authorized else {
            return "audio input permission status=\(authorization.rawValue)"
        }
        guard let bridgeUID = store.recordingBridgeDeviceUID else {
            return "bridge UID is not configured"
        }
        guard let bridge = RecordingDeviceService.descriptor(uid: bridgeUID) else {
            return "configured bridge is unavailable uid=\(bridgeUID)"
        }
        guard bridge.isSupportedProToolsAudioBridge else {
            return "configured bridge is unsupported name=\(bridge.name) inputChannels=\(bridge.inputChannelCount) outputChannels=\(bridge.outputChannelCount) uid=\(bridge.uid)"
        }

        let originalUID: String
        do {
            originalUID = try RecordingDeviceService.defaultOutputDeviceUID()
        } catch {
            return "default output lookup failed error=\(error.localizedDescription)"
        }
        guard originalUID != bridgeUID else {
            return "default output already equals configured bridge uid=\(bridgeUID)"
        }
        guard let original = RecordingDeviceService.descriptor(uid: originalUID) else {
            return "default output descriptor is unavailable uid=\(originalUID)"
        }
        guard original.outputChannelCount > 0 else {
            return "default output has no output channels name=\(original.name) uid=\(original.uid)"
        }

        DiagnosticLog.append(
            "[Recording] preflight devices bridge=\(bridge.name) inputChannels=\(bridge.inputChannelCount) " +
            "monitor=\(original.name) outputChannels=\(original.outputChannelCount)"
        )
        return nil
    }

    func recoverStaleSessionIfNeeded() {
        guard let controlStore else { return }
        let snapshot = controlStore.snapshot()
        guard snapshot.phase.isActive,
              let pid = snapshot.runnerPID,
              !Self.isProcessAlive(pid) else { return }
        recover(snapshot, reason: .runnerCrashed)
    }

    private func beginSupervision(sessionID: UUID, onFinished: @escaping () -> Void) {
        guard let controlStore else { return }
        supervisionTimer?.invalidate()
        supervisionSawActiveState = false
        supervisionStartedAt = Date()
        supervisionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let snapshot = controlStore.snapshot()
            guard snapshot.id == sessionID else {
                timer.invalidate()
                self.supervisionTimer = nil
                return
            }
            if snapshot.phase.isActive {
                self.supervisionSawActiveState = true
            }
            if snapshot.phase == .failed || snapshot.phase == .idle {
                timer.invalidate()
                self.supervisionTimer = nil
                onFinished()
                return
            }
            if !self.supervisionSawActiveState, Date().timeIntervalSince(self.supervisionStartedAt) > 10 {
                timer.invalidate()
                self.supervisionTimer = nil
                self.failPendingLaunch(sessionID: sessionID, message: "录音后台进程未能及时启动。")
                onFinished()
                return
            }
            if let pid = snapshot.runnerPID, !Self.isProcessAlive(pid) {
                timer.invalidate()
                self.supervisionTimer = nil
                self.recover(snapshot, reason: .runnerCrashed)
                onFinished()
            }
        }
    }

    private func recover(_ snapshot: RecordingSessionSnapshot, reason: RecordingStopReason) {
        guard let controlStore else { return }
        RecordingDeviceService.restoreDefaultOutput(
            preferredUID: snapshot.originalOutputDeviceUID,
            excluding: snapshot.bridgeDeviceUID
        )
        var recoveredURL: URL?
        if let temporaryURL = snapshot.temporaryFileURL,
           let sampleRate = snapshot.sampleRate,
           let channelCount = snapshot.channelCount,
           FileManager.default.fileExists(atPath: temporaryURL.path) {
            try? RecordingWAVWriter.recover(url: temporaryURL, sampleRate: sampleRate, channelCount: channelCount)
            let completedURL = temporaryURL.deletingPathExtension()
            try? FileManager.default.moveItem(at: temporaryURL, to: completedURL)
            recoveredURL = completedURL
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([completedURL as NSURL])
        }
        var failed = snapshot
        failed.phase = .failed
        failed.runnerPID = nil
        failed.stopReason = reason
        failed.errorMessage = "录音进程异常退出，已恢复播放设备并修复可用音频。"
        try? controlStore.save(failed)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.recordingWidgetKind)
        Task {
            await NotificationService(container: container).notifyRecordingFinished(
                fileURL: recoveredURL,
                message: failed.errorMessage ?? "录音异常结束"
            )
        }
    }

    private func launchNewAppInstance(sessionID: UUID) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        if let diagnosticRoot = ProcessInfo.processInfo.environment[SharedContainer.diagnosticRootEnvironmentKey] {
            configuration.environment = [SharedContainer.diagnosticRootEnvironmentKey: diagnosticRoot]
        }
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            if let error {
                DiagnosticLog.append("[Recording] runner launch failed error=\(error.localizedDescription)")
                guard let self else { return }
                self.failPendingLaunch(sessionID: sessionID, message: error.localizedDescription)
            } else {
                DiagnosticLog.append("[Recording] runner launch request completed")
            }
        }
    }

    private func failPendingLaunch(sessionID: UUID, message: String) {
        guard let controlStore else { return }
        let current = controlStore.snapshot()
        guard current.id == sessionID, current.phase == .starting else { return }
        _ = controlStore.drainCommands()
        LaunchMarkerStore(container: container).clear()
        var failed = current
        failed.phase = .failed
        failed.stopReason = .startupFailure
        failed.errorMessage = message
        try? controlStore.save(failed)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.recordingWidgetKind)
        Task {
            await NotificationService(container: container).notifyRecordingFinished(
                fileURL: nil,
                message: message
            )
        }
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
