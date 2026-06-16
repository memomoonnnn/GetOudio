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
    @Published var dependencyStatuses: [DependencyStatus] = []
    @Published var bundledComponentStatuses: [BundledComponentStatus] = []
    @Published var dockerImageStatuses: [ManagedDockerImageStatus] = []
    @Published var dependencyMessage = "尚未检测"
    @Published var finderDirectoryMessage = ""
    @Published var isCheckingDependencies = false

    private let store = SettingsStore()
    private let dependencyManager = DependencyManager()
    private let bundledComponentManager = BundledComponentManager()
    private let dockerImageManager = DockerImageManager()

    init() {
        enabledPresets = store.enabledPresets
        finderDirectories = store.finderDirectoryURLs
        ncmOutputMode = store.ncmOutputMode
        ncmCustomOutputURL = store.ncmCustomOutputURL
        appleMusicOutputURL = store.appleMusicOutputURL
        appleMusicDownloadFormat = store.appleMusicDownloadFormat
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

    func refreshDependencies() async {
        isCheckingDependencies = true
        dependencyStatuses = await dependencyManager.checkAll()
        bundledComponentStatuses = bundledComponentManager.checkAll()
        dockerImageStatuses = await dockerImageManager.checkAll()
        let missingCount = dependencyStatuses.filter { !$0.isInstalled }.count
        let missingComponentCount = bundledComponentStatuses.filter { !$0.isEmbedded }.count
        let missingImageCount = dockerImageStatuses.filter { !$0.isAvailable }.count
        if missingCount == 0 && missingComponentCount == 0 && missingImageCount == 0 {
            dependencyMessage = "运行时工具、内嵌组件与 Colima 容器镜像已就绪"
        } else {
            dependencyMessage = "\(missingCount) 个运行时工具、\(missingComponentCount) 个内嵌组件、\(missingImageCount) 个 Colima 容器镜像未就绪"
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
        dockerImageStatuses = await dockerImageManager.checkAll()
        isCheckingDependencies = false
    }

    func isDependencyInstallDisabled(_ status: DependencyStatus) -> Bool {
        if isCheckingDependencies {
            return true
        }

        if status.dependency == .homebrew {
            return false
        }

        return !isHomebrewInstalled
    }

    func installHelp(for status: DependencyStatus) -> String {
        if status.dependency == .homebrew {
            return "执行 Homebrew 官方安装脚本"
        }

        if !isHomebrewInstalled {
            return "请先安装 Homebrew"
        }

        return status.dependency.installCommand
    }

    func pull(_ image: ManagedDockerImage) async {
        isCheckingDependencies = true
        dependencyMessage = "正在后台启动 Colima 并拉取 \(image.imageName)..."
        do {
            let result = try await dockerImageManager.pull(image)
            dependencyMessage = result.succeeded ? "\(image.displayName) 镜像已就绪" : "\(image.displayName) 拉取失败：\(result.standardError)"
        } catch {
            dependencyMessage = "\(image.displayName) 拉取失败：\(error.localizedDescription)"
        }
        dependencyStatuses = await dependencyManager.checkAll()
        bundledComponentStatuses = bundledComponentManager.checkAll()
        dockerImageStatuses = await dockerImageManager.checkAll()
        isCheckingDependencies = false
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

    private func saveFinderDirectories() {
        store.finderDirectoryURLs = finderDirectories
        finderDirectories = store.finderDirectoryURLs
        finderDirectoryMessage = "已保存 \(finderDirectories.count) 个 Finder 监听目录；重启 Finder 后生效。"
    }

    private var isHomebrewInstalled: Bool {
        dependencyStatuses.first { $0.dependency == .homebrew }?.isInstalled ?? false
    }
}
