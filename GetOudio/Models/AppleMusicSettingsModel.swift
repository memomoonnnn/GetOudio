import Combine
import Foundation
import GetOudioCore

@MainActor
final class AppleMusicSettingsModel: ObservableObject {
    @Published var appleMusicOutputURL: URL
    @Published var appleMusicDownloadFormat: AppleMusicDownloadFormat
    @Published var isAppleMusicDownloadEnabled: Bool
    @Published var appleMusicUseSystemProxy: Bool
    @Published var appleMusicRuntimeStatuses: [AppleMusicRuntimeComponentStatus] = []
    @Published var appleMusicRuntimeMessage = "尚未检测"
    @Published var appleMusicRuntimeProgress: AppleMusicRuntimeProgress?
    @Published private var appleMusicInitializationRequestMessage: String?
    @Published var isSendingAppleMusicInitializationRequest = false
    @Published var isSubmittingAppleMusicVerificationCode = false
    @Published var appleMusicWrapperLoginStatus = AppleMusicWrapperLoginStatus(
        phase: .notInitialized,
        message: "尚未初始化"
    )
    @Published var isManagingAppleMusicRuntime = false
    @Published var isRefreshingAppleMusicRuntimeStatus = false
    @Published private(set) var hasLoadedAppleMusicRuntimeStatus = false

    private let store: SettingsStore
    private let appleMusicAgentClient: AppleMusicRuntimeAgentClient
    private let appleMusicDownloadService: AppleMusicDownloadService
    private var latestAppleMusicWrapperLoginSnapshotRevision: UInt64 = 0

    init(container: AgentDataStore, store: SettingsStore) {
        self.store = store
        appleMusicAgentClient = AppleMusicRuntimeAgentClient()
        appleMusicDownloadService = AppleMusicDownloadService(container: container)
        appleMusicOutputURL = store.appleMusicOutputURL
        appleMusicDownloadFormat = store.appleMusicDownloadFormat
        isAppleMusicDownloadEnabled = store.isAppleMusicDownloadEnabled
        appleMusicUseSystemProxy = store.appleMusicUseSystemProxy
    }

    var canStopAppleMusicDownload: Bool {
        appleMusicRuntimeProgress?.isActive == true
            && appleMusicRuntimeProgress?.statuses == nil
    }

    var isAppleMusicRuntimeBusy: Bool {
        isManagingAppleMusicRuntime || isRefreshingAppleMusicRuntimeStatus
    }

    var isAppleMusicRuntimeUpdateBlocked: Bool {
        !appleMusicRuntimeOperationAvailability.isAvailable
    }

    var appleMusicRuntimeOperationBlockedMessage: String {
        appleMusicRuntimeOperationAvailability.blockedMessage
    }

    var appleMusicInitializationMessage: String {
        appleMusicInitializationRequestMessage ?? appleMusicWrapperLoginStatus.message
    }

    func chooseAppleMusicOutputDirectory() {
        guard let url = DirectoryChooser.chooseDirectory(prompt: "选择") else { return }
        appleMusicOutputURL = url
        store.appleMusicOutputURL = url
    }

    func setAppleMusicDownloadFormat(_ format: AppleMusicDownloadFormat) {
        appleMusicDownloadFormat = format
        store.appleMusicDownloadFormat = format
    }

    func setAppleMusicUseSystemProxy(_ isEnabled: Bool) {
        appleMusicUseSystemProxy = isEnabled
        store.appleMusicUseSystemProxy = isEnabled
    }

    func stopAppleMusicDownload() {
        Task {
            do {
                try await appleMusicAgentClient.requestDownloadCancellation()
                appleMusicRuntimeMessage = "正在停止 Apple Music 下载..."
                appleMusicRuntimeProgress = AppleMusicRuntimeProgress(
                    message: "正在停止 Apple Music 下载...",
                    completedUnitCount: 0,
                    totalUnitCount: 1,
                    isActive: true
                )
            } catch {
                appleMusicRuntimeMessage = "停止请求失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshAppleMusicRuntimeStatus() async {
        guard !isAppleMusicRuntimeBusy else {
            return
        }

        isRefreshingAppleMusicRuntimeStatus = true
        defer {
            isRefreshingAppleMusicRuntimeStatus = false
        }

        do {
            let report = try await appleMusicAgentClient.status()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = try await appleMusicAgentClient.progress()
            hasLoadedAppleMusicRuntimeStatus = true
        } catch {
            isAppleMusicDownloadEnabled = store.isAppleMusicDownloadEnabled
            appleMusicRuntimeMessage = "后台 Agent 不可用：\(error.localizedDescription)"
        }
    }

    func enableAppleMusicRuntime() async {
        guard !isAppleMusicRuntimeUpdateBlocked else {
            appleMusicRuntimeMessage = appleMusicRuntimeOperationBlockedMessage
            return
        }
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = isAppleMusicDownloadEnabled
            ? "正在通过后台 Agent 检查并更新 Runtime..."
            : "正在通过后台 Agent 安装 Runtime..."
        do {
            let report = try await appleMusicAgentClient.install()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = try await appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Downloader Runtime 安装失败：\(error.localizedDescription)"
        }
        isManagingAppleMusicRuntime = false
    }

    func uninstallAppleMusicRuntime() async {
        guard !isAppleMusicRuntimeUpdateBlocked else {
            appleMusicRuntimeMessage = appleMusicRuntimeOperationBlockedMessage
            return
        }
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = "正在卸载 Downloader Runtime..."
        do {
            let report = try await appleMusicAgentClient.uninstall()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = "Downloader Runtime 已卸载"
            appleMusicRuntimeProgress = try await appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Downloader Runtime 卸载失败：\(error.localizedDescription)"
        }
        isManagingAppleMusicRuntime = false
    }

    func initializeAppleMusicWrapper(username: String, password: String) async {
        guard !appleMusicWrapperLoginStatus.isInProgress,
              !appleMusicWrapperLoginStatus.isAuthenticated
        else {
            return
        }
        isSendingAppleMusicInitializationRequest = true
        appleMusicInitializationRequestMessage = "正在提交初始化请求..."
        defer { isSendingAppleMusicInitializationRequest = false }
        let summary = await appleMusicDownloadService.initializeWrapper(
            username: username,
            password: password,
            verificationCode: nil,
            useSystemProxy: appleMusicUseSystemProxy
        )
        if summary.failureCount == 0 {
            appleMusicInitializationRequestMessage = nil
        } else {
            appleMusicInitializationRequestMessage = summary.messages.first ?? "初始化失败"
        }
    }

    func submitAppleMusicVerificationCode(_ code: String) async {
        guard appleMusicWrapperLoginStatus.canSubmitVerificationCode else {
            appleMusicInitializationRequestMessage = "当前登录流程尚未等待验证码"
            return
        }
        isSubmittingAppleMusicVerificationCode = true
        appleMusicInitializationRequestMessage = "正在提交验证码..."
        defer { isSubmittingAppleMusicVerificationCode = false }
        let summary = await appleMusicDownloadService.submitWrapperVerificationCode(code)
        appleMusicInitializationRequestMessage = summary.failureCount == 0
            ? nil
            : (summary.messages.first ?? "验证码提交失败")
    }

    func monitorAppleMusicRuntimeEvents() async {
        while !Task.isCancelled {
            for await event in appleMusicAgentClient.events() {
                guard !Task.isCancelled else { return }
                if let snapshot = event.loginSnapshot {
                    applyAppleMusicWrapperLoginSnapshot(snapshot)
                }
                applyAppleMusicRuntimeProgress(event.progress)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func refreshAppleMusicWrapperLoginStatus() async {
        guard isAppleMusicDownloadEnabled else {
            applyAppleMusicWrapperLoginStatus(AppleMusicWrapperLoginStatus(
                phase: .notInitialized,
                message: "Apple Music 下载功能尚未启用"
            ))
            return
        }

        do {
            let status = try await appleMusicAgentClient.wrapperLoginStatus()
            applyAppleMusicWrapperLoginStatus(status)
        } catch {
            appleMusicInitializationRequestMessage = "初始化状态检查失败：\(error.localizedDescription)"
        }
    }

    private func applyAppleMusicWrapperLoginSnapshot(_ snapshot: AppleMusicWrapperLoginSnapshot) {
        guard snapshot.revision > latestAppleMusicWrapperLoginSnapshotRevision else { return }
        latestAppleMusicWrapperLoginSnapshotRevision = snapshot.revision
        applyAppleMusicWrapperLoginStatus(snapshot.status)
    }

    private func applyAppleMusicRuntimeProgress(_ progress: AppleMusicRuntimeProgress?) {
        appleMusicRuntimeProgress = progress
        if let statuses = progress?.statuses {
            appleMusicRuntimeStatuses = statuses
        }
        if let progress {
            appleMusicRuntimeMessage = progress.message
        }
    }

    private func applyAppleMusicWrapperLoginStatus(_ status: AppleMusicWrapperLoginStatus) {
        appleMusicWrapperLoginStatus = status
        if status.isInProgress || status.isAuthenticated || status.phase == .failed {
            appleMusicInitializationRequestMessage = nil
        }
    }

    private var appleMusicRuntimeOperationAvailability: AppleMusicRuntimeOperationAvailability {
        AppleMusicRuntimeOperationAvailability(
            isManagingRuntime: isManagingAppleMusicRuntime,
            isRefreshingRuntimeStatus: isRefreshingAppleMusicRuntimeStatus,
            progress: appleMusicRuntimeProgress,
            loginStatus: appleMusicWrapperLoginStatus
        )
    }
}
