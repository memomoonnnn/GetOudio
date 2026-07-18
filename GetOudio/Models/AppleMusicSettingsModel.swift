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
    @Published var appleMusicActionMessage = "尚未初始化"
    @Published var isInitializingAppleMusicWrapper = false
    @Published var isSubmittingAppleMusicVerificationCode = false
    @Published var appleMusicWrapperLoginStatus = AppleMusicWrapperLoginStatus(
        phase: .notInitialized,
        message: "尚未初始化"
    )
    @Published var isManagingAppleMusicRuntime = false
    @Published var isRefreshingAppleMusicRuntimeStatus = false

    private let store: SettingsStore
    private let appleMusicAgentClient: AppleMusicRuntimeAgentClient
    private let appleMusicDownloadService: AppleMusicDownloadService
    private let appleMusicAgentLauncher = AppleMusicRuntimeAgentLauncher.shared
    private var runtimeProgressTask: Task<Void, Never>?

    init(container: SharedContainer, store: SettingsStore) {
        self.store = store
        appleMusicAgentClient = AppleMusicRuntimeAgentClient(container: container)
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
        do {
            try appleMusicAgentClient.requestDownloadCancellation()
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

    func refreshAppleMusicRuntimeStatus() async {
        guard !isAppleMusicRuntimeBusy else {
            return
        }

        isRefreshingAppleMusicRuntimeStatus = true
        defer {
            isRefreshingAppleMusicRuntimeStatus = false
        }

        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.status()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            isAppleMusicDownloadEnabled = store.isAppleMusicDownloadEnabled
            appleMusicRuntimeMessage = "Downloader Runtime Agent 不可用：\(error.localizedDescription)"
        }
    }

    func enableAppleMusicRuntime() async {
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = "正在通过 Downloader Runtime Agent 安装 Runtime..."
        startRuntimeProgressPolling()
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.install()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Downloader Runtime 安装失败：\(error.localizedDescription)"
        }
        stopRuntimeProgressPolling()
        isManagingAppleMusicRuntime = false
    }

    func uninstallAppleMusicRuntime() async {
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = "正在卸载 Downloader Runtime..."
        startRuntimeProgressPolling()
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.uninstall()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = "Downloader Runtime 已卸载"
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Downloader Runtime 卸载失败：\(error.localizedDescription)"
        }
        stopRuntimeProgressPolling()
        isManagingAppleMusicRuntime = false
    }

    func initializeAppleMusicWrapper(username: String, password: String) async {
        guard !appleMusicWrapperLoginStatus.isInProgress,
              !appleMusicWrapperLoginStatus.isAuthenticated
        else {
            return
        }
        isInitializingAppleMusicWrapper = true
        appleMusicActionMessage = "正在启动 Downloader Runtime Agent 并初始化 wrapper..."
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let summary = await appleMusicDownloadService.initializeWrapper(
                username: username,
                password: password,
                verificationCode: nil,
                useSystemProxy: appleMusicUseSystemProxy
            )
            appleMusicActionMessage = summary.failureCount == 0
                ? (summary.messages.first ?? "登录容器已启动")
                : (summary.messages.first ?? "初始化失败")
            await refreshAppleMusicWrapperLoginStatus()
        } catch {
            appleMusicActionMessage = "初始化失败：\(error.localizedDescription)"
            isInitializingAppleMusicWrapper = false
        }
        isInitializingAppleMusicWrapper = appleMusicWrapperLoginStatus.isInProgress
    }

    func submitAppleMusicVerificationCode(_ code: String) async {
        guard appleMusicWrapperLoginStatus.canSubmitVerificationCode else {
            appleMusicActionMessage = "当前登录流程尚未等待验证码"
            return
        }
        isSubmittingAppleMusicVerificationCode = true
        appleMusicActionMessage = "验证码已提交，正在验证..."
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let summary = await appleMusicDownloadService.submitWrapperVerificationCode(code)
            appleMusicActionMessage = summary.failureCount == 0
                ? "验证码已写入，正在等待 Apple 验证"
                : (summary.messages.first ?? "验证码提交失败")
            await refreshAppleMusicWrapperLoginStatus()
        } catch {
            appleMusicActionMessage = "验证码提交失败：\(error.localizedDescription)"
        }
        isSubmittingAppleMusicVerificationCode = false
    }

    func monitorAppleMusicWrapperLoginStatus() async {
        while !Task.isCancelled {
            await refreshAppleMusicWrapperLoginStatus()
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    func monitorAppleMusicRuntimeProgress() async {
        while !Task.isCancelled {
            let progress = appleMusicAgentClient.progress()
            appleMusicRuntimeProgress = progress
            if progress?.isActive == true, let statuses = progress?.statuses {
                appleMusicRuntimeStatuses = statuses
            }
            if let progress, progress.isActive {
                appleMusicRuntimeMessage = progress.message
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func refreshAppleMusicWrapperLoginStatus() async {
        guard isAppleMusicDownloadEnabled else {
            appleMusicWrapperLoginStatus = AppleMusicWrapperLoginStatus(
                phase: .notInitialized,
                message: "Apple Music 下载功能尚未启用"
            )
            return
        }

        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let status = try await appleMusicAgentClient.wrapperLoginStatus()
            appleMusicWrapperLoginStatus = status
            appleMusicActionMessage = status.message
            isInitializingAppleMusicWrapper = status.isInProgress
            if status.isAuthenticated || status.phase == .failed {
                isSubmittingAppleMusicVerificationCode = false
            }
        } catch {
            appleMusicActionMessage = "初始化状态检查失败：\(error.localizedDescription)"
        }
    }

    private func startRuntimeProgressPolling() {
        runtimeProgressTask?.cancel()
        runtimeProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let appleMusicAgentClient = self?.appleMusicAgentClient else {
                    return
                }
                let progress = await Task.detached {
                    appleMusicAgentClient.progress()
                }.value
                await MainActor.run {
                    self?.appleMusicRuntimeProgress = progress
                    if progress?.isActive == true, let statuses = progress?.statuses {
                        self?.appleMusicRuntimeStatuses = statuses
                    }
                    if let progress, progress.isActive {
                        self?.appleMusicRuntimeMessage = progress.message
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopRuntimeProgressPolling() {
        runtimeProgressTask?.cancel()
        runtimeProgressTask = nil
        appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        if appleMusicRuntimeProgress?.isActive == true, let statuses = appleMusicRuntimeProgress?.statuses {
            appleMusicRuntimeStatuses = statuses
        }
    }
}
