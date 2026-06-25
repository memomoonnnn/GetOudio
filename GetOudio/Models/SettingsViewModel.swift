import AppKit
import Foundation
import GetOudioCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var enabledPresets: Set<ConversionPreset>
    @Published var finderDirectories: [URL]
    @Published var ncmOutputMode: String
    @Published var ncmCustomOutputURL: URL?
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
    @Published var dependencyStatuses: [DependencyStatus] = []
    @Published var bundledComponentStatuses: [BundledComponentStatus] = []
    @Published var dockerImageStatuses: [ManagedDockerImageStatus] = []
    @Published var dependencyMessage = "尚未检测"
    @Published var finderDirectoryMessage = ""
    @Published var isCheckingDependencies = false

    private let store = SettingsStore()
    private let dependencyManager = DependencyManager()
    private let bundledComponentManager = BundledComponentManager()
    private let appleMusicAgentClient = AppleMusicRuntimeAgentClient()
    private let appleMusicDownloadService = AppleMusicDownloadService()
    private let appleMusicAgentLauncher = AppleMusicRuntimeAgentLauncher.shared
    private var runtimeProgressTask: Task<Void, Never>?

    init() {
        enabledPresets = store.enabledPresets
        finderDirectories = store.finderDirectoryURLs
        ncmOutputMode = store.ncmOutputMode
        ncmCustomOutputURL = store.ncmCustomOutputURL
        appleMusicOutputURL = store.appleMusicOutputURL
        appleMusicDownloadFormat = store.appleMusicDownloadFormat
        isAppleMusicDownloadEnabled = store.isAppleMusicDownloadEnabled
        appleMusicUseSystemProxy = store.appleMusicUseSystemProxy
    }

    func toggle(_ preset: ConversionPreset, isEnabled: Bool) {
        if isEnabled {
            enabledPresets.insert(preset)
        } else {
            guard enabledPresets.count > 1 else {
                enabledPresets = store.enabledPresets
                return
            }
            enabledPresets.remove(preset)
        }
        store.enabledPresets = enabledPresets
        enabledPresets = store.enabledPresets
    }

    func addFinderDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        panel.message = "选择要启用 Get Oudio Finder 菜单的目录"
        panel.directoryURL = SettingsStore.realUserHomeDirectory()

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                Task { @MainActor in
                    self?.appendFinderDirectories(panel.urls)
                }
            }
        } else if panel.runModal() == .OK {
            appendFinderDirectories(panel.urls)
        }
    }

    func removeFinderDirectories(at offsets: IndexSet) {
        finderDirectories.remove(atOffsets: offsets)
        saveFinderDirectories()
    }

    func removeFinderDirectory(_ url: URL) {
        finderDirectories.removeAll { $0 == url }
        saveFinderDirectories()
    }

    func revealFinderDirectory(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func restoreDefaultFinderDirectories() {
        finderDirectories = SettingsStore.defaultFinderDirectories()
        saveFinderDirectories()
    }

    func setNCMOutputMode(_ mode: String) {
        ncmOutputMode = mode
        store.ncmOutputMode = mode
    }

    func chooseNCMOutputDirectory() {
        guard let url = chooseDirectory(prompt: "选择") else { return }
        ncmCustomOutputURL = url
        store.ncmCustomOutputURL = url
        setNCMOutputMode("customDirectory")
    }

    func chooseAppleMusicOutputDirectory() {
        guard let url = chooseDirectory(prompt: "选择") else { return }
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

    func refreshAppleMusicRuntimeStatus() async {
        isManagingAppleMusicRuntime = true
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.status()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            dockerImageStatuses = []
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeStatuses = []
            dockerImageStatuses = []
            isAppleMusicDownloadEnabled = store.isAppleMusicDownloadEnabled
            appleMusicRuntimeMessage = "Apple Music Runtime Agent 不可用：\(error.localizedDescription)"
        }
        isManagingAppleMusicRuntime = false
    }

    func enableAppleMusicRuntime() async {
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = "正在通过 Apple Music Runtime Agent 安装运行时..."
        startRuntimeProgressPolling()
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.install()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = report.message
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Apple Music 运行时安装失败：\(error.localizedDescription)"
        }
        stopRuntimeProgressPolling()
        isManagingAppleMusicRuntime = false
    }

    func uninstallAppleMusicRuntime() async {
        isManagingAppleMusicRuntime = true
        appleMusicRuntimeMessage = "正在卸载 Apple Music 运行时..."
        startRuntimeProgressPolling()
        do {
            try await appleMusicAgentLauncher.ensureRunning()
            let report = try await appleMusicAgentClient.uninstall()
            appleMusicRuntimeStatuses = report.statuses
            isAppleMusicDownloadEnabled = report.isEnabled
            appleMusicRuntimeMessage = "Apple Music 运行时已卸载"
            appleMusicRuntimeProgress = appleMusicAgentClient.progress()
        } catch {
            appleMusicRuntimeMessage = "Apple Music 运行时卸载失败：\(error.localizedDescription)"
        }
        stopRuntimeProgressPolling()
        dockerImageStatuses = []
        isManagingAppleMusicRuntime = false
    }

    func initializeAppleMusicWrapper(username: String, password: String) async {
        guard !appleMusicWrapperLoginStatus.isInProgress,
              !appleMusicWrapperLoginStatus.isAuthenticated
        else {
            return
        }
        isInitializingAppleMusicWrapper = true
        appleMusicActionMessage = "正在启动 Apple Music Runtime Agent 并初始化 wrapper..."
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

    func refreshDependencies() async {
        isCheckingDependencies = true
        dependencyStatuses = await dependencyManager.checkAll()
        bundledComponentStatuses = bundledComponentManager.checkAll()
        dockerImageStatuses = []
        let missingCount = dependencyStatuses.filter { !$0.isInstalled }.count
        let missingComponentCount = bundledComponentStatuses.filter { !$0.isEmbedded }.count
        if missingCount == 0 && missingComponentCount == 0 {
            dependencyMessage = "运行时工具与内嵌组件已就绪"
        } else {
            dependencyMessage = "\(missingCount) 个运行时工具、\(missingComponentCount) 个内嵌组件未就绪"
        }
        isCheckingDependencies = false
    }

    func install(_ dependency: RuntimeDependency) async {
        isCheckingDependencies = true
        dependencyMessage = "正在安装 \(dependency.displayName)..."
        do {
            let result = try await dependencyManager.install(dependency)
            dependencyMessage = result.succeeded ? "\(dependency.displayName) 安装命令已完成" : "\(dependency.displayName) 安装失败：\(result.standardError)"
        } catch {
            dependencyMessage = "\(dependency.displayName) 安装失败：\(error.localizedDescription)"
        }
        dependencyStatuses = await dependencyManager.checkAll()
        bundledComponentStatuses = bundledComponentManager.checkAll()
        dockerImageStatuses = []
        isCheckingDependencies = false
    }

    func isDependencyInstallDisabled(_ status: DependencyStatus) -> Bool {
        true
    }

    func installHelp(for status: DependencyStatus) -> String {
        return status.dependency.installCommand
    }

    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func appendFinderDirectories(_ urls: [URL]) {
        let merged = finderDirectories + urls
        finderDirectories = Array(Set(merged.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        saveFinderDirectories()
    }

    private func startRuntimeProgressPolling() {
        runtimeProgressTask?.cancel()
        runtimeProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                let progress = await Task.detached {
                    AppleMusicRuntimeAgentClient().progress()
                }.value
                await MainActor.run {
                    self?.appleMusicRuntimeProgress = progress
                    if let statuses = progress?.statuses {
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
        if let statuses = appleMusicRuntimeProgress?.statuses {
            appleMusicRuntimeStatuses = statuses
        }
    }

    private func saveFinderDirectories() {
        store.finderDirectoryURLs = finderDirectories
        finderDirectories = store.finderDirectoryURLs
        finderDirectoryMessage = "已保存 \(finderDirectories.count) 个 Finder 监听目录；重启 Finder 后生效。"
    }

}
