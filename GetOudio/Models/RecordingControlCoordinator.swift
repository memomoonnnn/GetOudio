import AVFoundation
import AppKit
import Darwin
import Foundation
import GetOudioCore
import WidgetKit

final class RecordingControlCoordinator {
    struct ConfigurationRequirements {
        let needsMicrophonePermission: Bool
        let needsInputDevice: Bool

        static let none = ConfigurationRequirements(
            needsMicrophonePermission: false,
            needsInputDevice: false
        )
    }

    enum ToggleResult {
        case launchedRunner
        case requestedStop
        case needsConfiguration(ConfigurationRequirements)
        case failed(String)
    }

    private let container: AgentDataStore
    private let store: SettingsStore
    private let controlStore: RecordingControlStore?
    private var supervisionTimer: Timer?
    private var supervisionSawActiveState = false
    private var supervisionStartedAt = Date.distantPast

    init(container: AgentDataStore) {
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
            return .failed("录音控制状态不可用，请重新启动 Get Oudio。")
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
            DiagnosticLog.append("[Recording] preflight failed: \(failure.message)")
            return .needsConfiguration(failure.requirements)
        }

        do {
            guard let reservation = try controlStore.reserveStart() else {
                try controlStore.enqueue(.stop)
                RecordingControlSignal.post()
                DiagnosticLog.append("[Recording] concurrent toggle converted to stop request")
                return .requestedStop
            }
            DiagnosticLog.append("[Recording] preflight passed; session reserved id=\(reservation.id.uuidString)")
            launchNewAppInstance(sessionID: reservation.id)
            beginSupervision(sessionID: reservation.id, onFinished: onRunnerFinished)
            return .launchedRunner
        } catch {
            DiagnosticLog.append("[Recording] start command setup failed error=\(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func preflightFailure() -> (
        message: String,
        requirements: ConfigurationRequirements
    )? {
        let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
        let needsMicrophonePermission = authorization != .authorized
        let bridgeUID = store.recordingBridgeDeviceUID
        let bridge = bridgeUID.flatMap(RecordingDeviceService.descriptor(uid:))
        let needsInputDevice = bridge.map { !$0.isSupportedProToolsAudioBridge } ?? true

        if needsMicrophonePermission || needsInputDevice {
            var reasons: [String] = []
            if needsMicrophonePermission {
                reasons.append("audio input permission status=\(authorization.rawValue)")
            }
            if needsInputDevice {
                switch (bridgeUID, bridge) {
                case (nil, _):
                    reasons.append("bridge UID is not configured")
                case let (.some(bridgeUID), nil):
                    reasons.append("configured bridge is unavailable uid=\(bridgeUID)")
                case let (.some(bridgeUID), .some):
                    reasons.append("configured bridge is unsupported uid=\(bridgeUID)")
                }
            }
            return (
                reasons.joined(separator: "; "),
                ConfigurationRequirements(
                    needsMicrophonePermission: needsMicrophonePermission,
                    needsInputDevice: needsInputDevice
                )
            )
        }

        guard let bridgeUID, let bridge else { return nil }

        let originalUID: String
        do {
            originalUID = try RecordingDeviceService.defaultOutputDeviceUID()
        } catch {
            return ("default output lookup failed error=\(error.localizedDescription)", .none)
        }
        guard originalUID != bridgeUID else {
            return ("default output already equals configured bridge uid=\(bridgeUID)", .none)
        }
        guard let original = RecordingDeviceService.descriptor(uid: originalUID) else {
            return ("default output descriptor is unavailable uid=\(originalUID)", .none)
        }
        guard original.outputChannelCount > 0 else {
            return (
                "default output has no output channels name=\(original.name) uid=\(original.uid)",
                .none
            )
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
        enqueueRecordingFinished(
                fileURL: recoveredURL,
                message: failed.errorMessage ?? "录音异常结束"
        )
    }

    private func launchNewAppInstance(sessionID: UUID) {
        guard let executableURL = Bundle.main.executableURL else {
            failPendingLaunch(sessionID: sessionID, message: "未找到录音后台可执行文件。")
            return
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--recording-runner"]
        do {
            try process.run()
            DiagnosticLog.append("[Recording] runner launched pid=\(process.processIdentifier)")
        } catch {
            DiagnosticLog.append("[Recording] runner launch failed error=\(error.localizedDescription)")
            failPendingLaunch(sessionID: sessionID, message: error.localizedDescription)
        }
    }

    private func failPendingLaunch(sessionID: UUID, message: String) {
        guard let controlStore else { return }
        let current = controlStore.snapshot()
        guard current.id == sessionID, current.phase == .starting else { return }
        _ = controlStore.drainCommands()
        var failed = current
        failed.phase = .failed
        failed.stopReason = .startupFailure
        failed.errorMessage = message
        try? controlStore.save(failed)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.recordingWidgetKind)
        enqueueRecordingFinished(fileURL: nil, message: message)
    }

    private func enqueueRecordingFinished(fileURL: URL?, message: String) {
        do {
            try NotificationService(container: container).enqueueAndWakeRecordingFinished(
                fileURL: fileURL,
                message: message
            )
        } catch {
            DiagnosticLog.append("[Recording] notification event enqueue failed: \(error.localizedDescription)")
        }
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
