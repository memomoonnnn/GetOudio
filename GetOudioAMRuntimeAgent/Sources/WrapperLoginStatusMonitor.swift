import Foundation
import GetOudioCore

actor WrapperLoginStatusMonitor {
    private static let pollingIntervalNanoseconds: UInt64 = 500_000_000
    private static let maximumPollingCount = 180

    private let snapshotStore: AppleMusicWrapperLoginSnapshotStore
    private var monitorTask: Task<Void, Never>?
    private var lastPublishedStatus: AppleMusicWrapperLoginStatus?
    private var verificationCodeSubmissionPending = false

    init(container: SharedContainer) {
        snapshotStore = AppleMusicWrapperLoginSnapshotStore(container: container)
        lastPublishedStatus = snapshotStore.snapshot()?.status
        verificationCodeSubmissionPending = lastPublishedStatus?.phase == .verificationCodeSubmitted
    }

    func prepareForInitialization() {
        monitorTask?.cancel()
        monitorTask = nil
        verificationCodeSubmissionPending = false
        publish(AppleMusicWrapperLoginStatus(
            phase: .starting,
            message: "正在启动登录容器"
        ))
    }

    func recordInitializationFailure() {
        verificationCodeSubmissionPending = false
        publish(AppleMusicWrapperLoginStatus(
            phase: .failed,
            message: "登录容器启动失败，可以重新初始化"
        ))
    }

    func recordVerificationCodeSubmitted() {
        verificationCodeSubmissionPending = true
        publish(AppleMusicWrapperLoginStatus(
            phase: .verificationCodeSubmitted,
            message: "验证码已写入，等待 wrapper 读取"
        ))
    }

    func reconcile(runtime: AppleMusicWrapperRuntime) async -> AppleMusicWrapperLoginStatus {
        let status = await runtime.loginStatus()
        let isTerminal = recordObserved(status)
        if !isTerminal {
            beginMonitoring(runtime: runtime)
        }
        return lastPublishedStatus ?? status
    }

    func beginMonitoring(runtime: AppleMusicWrapperRuntime) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            for _ in 0..<Self.maximumPollingCount {
                guard !Task.isCancelled else { return }
                let status = await runtime.loginStatus()
                guard let self else { return }
                if await self.recordObserved(status) {
                    return
                }
                try? await Task.sleep(nanoseconds: Self.pollingIntervalNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.handleMonitoringTimeout(runtime: runtime)
        }
    }

    func recordNotInitialized(message: String) {
        monitorTask?.cancel()
        monitorTask = nil
        verificationCodeSubmissionPending = false
        publish(AppleMusicWrapperLoginStatus(phase: .notInitialized, message: message))
    }

    private func recordObserved(_ status: AppleMusicWrapperLoginStatus) -> Bool {
        if verificationCodeSubmissionPending,
           status.phase == .waitingForVerificationCode {
            return false
        }
        if status.phase != .waitingForVerificationCode {
            verificationCodeSubmissionPending = false
        }
        publish(status)
        return status.isAuthenticated || status.phase == .failed
    }

    private func handleMonitoringTimeout(runtime: AppleMusicWrapperRuntime) async {
        let finalStatus = await runtime.loginStatus()
        if recordObserved(finalStatus) {
            return
        }
        verificationCodeSubmissionPending = false
        await runtime.stopLoginAttempt()
        publish(AppleMusicWrapperLoginStatus(
            phase: .failed,
            message: "初始化等待超过 90 秒，已停止登录容器，可以重新初始化"
        ))
    }

    private func publish(_ status: AppleMusicWrapperLoginStatus) {
        guard lastPublishedStatus != status else { return }
        do {
            let snapshot = try snapshotStore.saveIfChanged(status)
            lastPublishedStatus = snapshot.status
            DiagnosticLog.append(
                "[WrapperLoginMonitor] revision=\(snapshot.revision) phase=\(status.phase.rawValue)"
            )
        } catch {
            DiagnosticLog.append("[WrapperLoginMonitor] snapshot write failed: \(error.localizedDescription)")
        }
    }
}
