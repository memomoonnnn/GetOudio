import Darwin
import Foundation

public enum AppleMusicRuntimeComponent: String, CaseIterable, Codable, Identifiable, Sendable {
    case colima
    case lima
    case docker
    case gpac
    case wrapperImage
    case appleMusicDownloader

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .colima: return "Colima"
        case .lima: return "Lima / limactl"
        case .docker: return "Docker CLI"
        case .gpac: return "GPAC / MP4Box"
        case .wrapperImage: return "Apple Music wrapper image"
        case .appleMusicDownloader: return "Apple-Music-Downloader"
        }
    }
}

public struct AppleMusicRuntimeComponentStatus: Codable, Identifiable, Equatable, Sendable {
    public var id: String { component.id }
    public var component: AppleMusicRuntimeComponent
    public var isReady: Bool
    public var resolvedPath: String?
    public var detail: String

    public init(component: AppleMusicRuntimeComponent, isReady: Bool, resolvedPath: String?, detail: String) {
        self.component = component
        self.isReady = isReady
        self.resolvedPath = resolvedPath
        self.detail = detail
    }
}

public struct AppleMusicRuntimeInstallResult: Codable, Equatable, Sendable {
    public var installedComponents: [AppleMusicRuntimeComponent]
    public var messages: [String]

    public init(installedComponents: [AppleMusicRuntimeComponent], messages: [String]) {
        self.installedComponents = installedComponents
        self.messages = messages
    }
}

public final class AppleMusicRuntimeManager {
    public typealias WrapperImageInstaller = (
        AppleMusicRuntimeManager
    ) async throws -> (status: ManagedDockerImageStatus, wasPulled: Bool)

    public enum InstallError: Error, LocalizedError {
        case unsupportedArchitecture(String)
        case missingDownloadURL(String)
        case missingInstalledFile(String)
        case invalidPackage(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedArchitecture(let arch):
                return "暂不支持当前架构：\(arch)"
            case .missingDownloadURL(let component):
                return "缺少 \(component) 的可下载运行时包。"
            case .missingInstalledFile(let path):
                return "安装完成后未找到文件：\(path)"
            case .invalidPackage(let message):
                return message
            }
        }
    }

    public static let colimaVersion = "v0.10.3"
    public static let limaVersion = "2.1.2"
    public static let dockerVersion = "29.5.3"
    public static let gpacPackageEnvironmentKey = "GET_OUDIO_GPAC_PACKAGE_URL"
    public static let gpacDefaultPackageURL = URL(
        string: "https://download.tsi.telecom-paristech.fr/gpac/new_builds/gpac_latest_head_macos.pkg"
    )!
    static let downloadAttemptCount = 9

    public static var defaultVMStateRootURL: URL {
        SettingsStore.realUserHomeDirectory()
            .appendingPathComponent("Library/Application Support/GetOudio/AM", isDirectory: true)
    }

    private let fileManager: FileManager
    private let runner: ProcessRunner
    private let settingsStore: SettingsStore
    private let resourceRoot: URL?
    private let gpacPackageURLOverride: String?
    private let wrapperImageInstaller: WrapperImageInstaller?
    private let progressURL: URL?

    public let rootURL: URL
    public let colimaHomeDirectory: URL
    public let limaHomeDirectory: URL

    public init(
        rootURL: URL,
        colimaHomeDirectory: URL? = nil,
        limaHomeDirectory: URL? = nil,
        runner: ProcessRunner = ProcessRunner(),
        settingsStore: SettingsStore,
        resourceRoot: URL? = Bundle.main.resourceURL,
        gpacPackageURLOverride: String? = nil,
        wrapperImageInstaller: WrapperImageInstaller? = nil,
        progressURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        let usesManagedVMState = progressURL != nil
        self.progressURL = progressURL
        self.colimaHomeDirectory = colimaHomeDirectory
            ?? (usesManagedVMState
                ? Self.defaultVMStateRootURL.appendingPathComponent("Colima", isDirectory: true)
                : rootURL.appendingPathComponent("colima-home", isDirectory: true))
        self.limaHomeDirectory = limaHomeDirectory
            ?? (usesManagedVMState
                ? Self.defaultVMStateRootURL.appendingPathComponent("Lima", isDirectory: true)
                : rootURL.appendingPathComponent("lima-home", isDirectory: true))
        self.runner = runner
        self.settingsStore = settingsStore
        self.resourceRoot = resourceRoot
        self.gpacPackageURLOverride = gpacPackageURLOverride
        self.wrapperImageInstaller = wrapperImageInstaller
        self.fileManager = fileManager
    }

    public convenience init(
        container: SharedContainer,
        runner: ProcessRunner = ProcessRunner(),
        resourceRoot: URL? = Bundle.main.resourceURL,
        gpacPackageURLOverride: String? = nil,
        wrapperImageInstaller: WrapperImageInstaller? = nil,
        fileManager: FileManager = .default
    ) {
        self.init(
            rootURL: container.url(for: .appleMusicRuntime),
            runner: runner,
            settingsStore: SettingsStore(container: container),
            resourceRoot: resourceRoot,
            gpacPackageURLOverride: gpacPackageURLOverride,
            wrapperImageInstaller: wrapperImageInstaller,
            progressURL: container.url(for: .appleMusicRuntimeIPC).appendingPathComponent("progress.json"),
            fileManager: fileManager
        )
    }

    public var binDirectory: URL { rootURL.appendingPathComponent("bin", isDirectory: true) }
    public var downloadsDirectory: URL { rootURL.appendingPathComponent("downloads", isDirectory: true) }
    public var colimaCacheDirectory: URL { rootURL.appendingPathComponent("colima-cache", isDirectory: true) }
    public var dockerConfigDirectory: URL { rootURL.appendingPathComponent("docker-config", isDirectory: true) }
    public var gpacDirectory: URL { rootURL.appendingPathComponent("gpac", isDirectory: true) }
    public var wrapperDataDirectory: URL { rootURL.appendingPathComponent("wrapper-data", isDirectory: true) }
    public var downloaderWorkDirectory: URL { rootURL.appendingPathComponent("downloader-work", isDirectory: true) }

    public var dockerURL: URL { binDirectory.appendingPathComponent("docker") }
    public var colimaURL: URL { binDirectory.appendingPathComponent("colima") }
    public var limaURL: URL { binDirectory.appendingPathComponent("lima") }
    public var limactlURL: URL { binDirectory.appendingPathComponent("limactl") }
    public var mp4BoxURL: URL { gpacDirectory.appendingPathComponent("MP4Box") }

    public var isEnabled: Bool {
        get { settingsStore.isAppleMusicDownloadEnabled }
        set { settingsStore.isAppleMusicDownloadEnabled = newValue }
    }

    public func runtimeEnvironment() -> [String: String] {
        var pathEntries = [
            binDirectory.path,
            gpacDirectory.path,
            ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        ]
        let officialModulePath = gpacDirectory.appendingPathComponent("modules", isDirectory: true)
        let packagedModulePath = gpacDirectory.appendingPathComponent("gpac", isDirectory: true)
        let gpacModulePath = fileManager.fileExists(atPath: officialModulePath.path)
            ? officialModulePath
            : packagedModulePath
        if fileManager.fileExists(atPath: gpacModulePath.path) {
            pathEntries.insert(gpacModulePath.path, at: 2)
        }

        return [
            "PATH": pathEntries.joined(separator: ":"),
            "COLIMA_HOME": colimaHomeDirectory.path,
            "COLIMA_CACHE_HOME": colimaCacheDirectory.path,
            "LIMA_HOME": limaHomeDirectory.path,
            "DOCKER_CONFIG": dockerConfigDirectory.path,
            "GPAC_MODULES_PATH": gpacModulePath.path
        ]
    }

    public func componentStatuses(wrapperStatus: ManagedDockerImageStatus? = nil) -> [AppleMusicRuntimeComponentStatus] {
        let downloaderStatus = BundledComponentManager(resourceRoot: resourceRoot).check(.appleMusicDownloader)
        let wrapper = wrapperStatus.map {
            AppleMusicRuntimeComponentStatus(
                component: .wrapperImage,
                isReady: $0.isAvailable,
                resolvedPath: nil,
                detail: $0.detail
            )
        } ?? AppleMusicRuntimeComponentStatus(
            component: .wrapperImage,
            isReady: false,
            resolvedPath: nil,
            detail: "启用并初始化 Apple Music 后拉取"
        )

        return [
            executableStatus(.colima, url: colimaURL),
            limaStatus(),
            executableStatus(.docker, url: dockerURL),
            executableStatus(.gpac, url: mp4BoxURL),
            wrapper,
            AppleMusicRuntimeComponentStatus(
                component: .appleMusicDownloader,
                isReady: downloaderStatus.isEmbedded,
                resolvedPath: downloaderStatus.resolvedURL?.path,
                detail: downloaderStatus.detail
            )
        ]
    }

    public func installManagedRuntime() async throws -> AppleMusicRuntimeInstallResult {
        DiagnosticLog.append("[Install] 开始安装 Apple Music 运行时 → \(rootURL.path)")
        writeProgress("准备安装 Apple Music 运行时...", completed: 0, total: 5, isActive: true)
        try createManagedDirectories()
        var installed: [AppleMusicRuntimeComponent] = []
        var messages: [String] = []
        var completed = 0

        do {
            if await validateExistingExecutable(colimaURL, arguments: ["version"], component: "Colima") {
                messages.append("Colima 已就绪，跳过下载")
            } else {
                DiagnosticLog.append("[Install] 安装 Colima...")
                writeProgress("正在安装 Colima...", completed: completed, total: 5, isActive: true)
                try await installColima()
                installed.append(.colima)
                messages.append("Colima 已安装到 \(colimaURL.path)")
            }
            completed += 1
            writeProgress("Colima 已就绪", completed: completed, total: 5, isActive: true)

            let limaShare = rootURL.appendingPathComponent("share/lima", isDirectory: true)
            if isRegularExecutable(limaURL),
               fileManager.fileExists(atPath: limaShare.path),
               await validateExistingExecutable(limaURL, arguments: ["--version"], component: "Lima CLI"),
               await validateExistingExecutable(limactlURL, arguments: ["--version"], component: "Lima") {
                try await ensureLimaVirtualizationEntitlement()
                messages.append("Lima 已就绪，跳过下载")
            } else {
                DiagnosticLog.append("[Install] Lima 组件不完整，将从发布包补装")
                DiagnosticLog.append("[Install] 安装 Lima...")
                writeProgress("正在安装 Lima / limactl...", completed: completed, total: 5, isActive: true)
                try await installLima()
                installed.append(.lima)
                messages.append("Lima 已安装到 \(limactlURL.path)")
            }
            completed += 1
            writeProgress("Lima 已就绪", completed: completed, total: 5, isActive: true)

            if await validateExistingExecutable(dockerURL, arguments: ["--version"], component: "Docker") {
                messages.append("Docker CLI 已就绪，跳过下载")
            } else {
                DiagnosticLog.append("[Install] 安装 Docker...")
                writeProgress("正在安装 Docker CLI...", completed: completed, total: 5, isActive: true)
                try await installDocker()
                installed.append(.docker)
                messages.append("Docker CLI 已安装到 \(dockerURL.path)")
            }
            completed += 1
            writeProgress("Docker CLI 已就绪", completed: completed, total: 5, isActive: true)

            if await validateExistingExecutable(mp4BoxURL, arguments: ["-version"], component: "GPAC") {
                messages.append("GPAC / MP4Box 已就绪，跳过下载")
            } else {
                DiagnosticLog.append("[Install] 安装 GPAC...")
                writeProgress("正在安装 GPAC / MP4Box...", completed: completed, total: 5, isActive: true)
                try await installGPAC()
                installed.append(.gpac)
                messages.append("GPAC / MP4Box 已安装到 \(mp4BoxURL.path)")
            }
            completed += 1
            writeProgress("GPAC / MP4Box 已就绪", completed: completed, total: 5, isActive: true)

            isEnabled = true
            writeProgress("正在启动 Colima 并检查 wrapper 镜像...", completed: completed, total: 5, isActive: true)
            let wrapperResult = try await ensureWrapperImageAvailable()
            if wrapperResult.wasPulled {
                installed.append(.wrapperImage)
                messages.append("Apple Music wrapper image 已拉取")
            } else {
                messages.append("Apple Music wrapper image 已就绪，跳过拉取")
            }
            completed += 1
            writeProgress(
                "Apple Music wrapper image 已就绪",
                completed: completed,
                total: 5,
                isActive: true,
                wrapperStatus: wrapperResult.status
            )

            let removedCount = cleanupDownloadedSources()
            messages.append("已清理 \(removedCount) 个下载和解包缓存项")
            let removedColimaCacheCount = cleanupDirectoryContents(
                colimaCacheDirectory.appendingPathComponent("caches", isDirectory: true),
                context: "Colima 基础镜像缓存"
            )
            messages.append("已清理 \(removedColimaCacheCount) 个 Colima 基础镜像缓存项")
            DiagnosticLog.append("[Install] 全部安装完成")
            writeProgress(
                "Apple Music 运行时安装完成",
                completed: 5,
                total: 5,
                isActive: false,
                wrapperStatus: wrapperResult.status
            )
            return AppleMusicRuntimeInstallResult(installedComponents: installed, messages: messages)
        } catch {
            isEnabled = false
            DiagnosticLog.append("[Install] 安装中断 completed=\(completed) error=\(error.localizedDescription)")
            writeProgress(
                "安装中断：\(error.localizedDescription)",
                completed: completed,
                total: 5,
                isActive: false
            )
            throw error
        }
    }

    public func uninstallManagedRuntime() async throws {
        writeProgress("正在卸载 Apple Music 运行时...", completed: 0, total: 2, isActive: true)
        let env = runtimeEnvironment()
        if isRegularExecutable(dockerURL) {
            _ = try? await runner.run(executablePath: dockerURL.path, arguments: ["--context", "colima", "rm", "-f", "get-oudio-wrapper"], environment: env)
        }
        if isRegularExecutable(colimaURL) {
            _ = try? await runner.run(executablePath: colimaURL.path, arguments: ["stop"], environment: env)
            _ = try? await runner.run(executablePath: colimaURL.path, arguments: ["delete", "--force", "--data"], environment: env)
        }
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        for directory in [colimaHomeDirectory, limaHomeDirectory]
        where !directory.path.hasPrefix(rootURL.path + "/") && fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        isEnabled = false
        writeProgress("Apple Music 运行时已卸载", completed: 2, total: 2, isActive: false)
    }

    public func ensureEnabledAndInstalled() throws {
        guard isEnabled else {
            throw ProcessRunnerError.processFailed("Apple Music 下载功能尚未启用。请先在 Apple Music Downloader 设置中启用并安装运行时。")
        }
        for url in [dockerURL, colimaURL, limaURL, limactlURL, mp4BoxURL] where !isRegularExecutable(url) {
            throw ProcessRunnerError.executableNotFound(url.path)
        }
    }

    public static func hostArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }

    public static func releaseArchitecture() throws -> String {
        switch hostArchitecture() {
        case "arm64": return "arm64"
        case "x86_64": return "x86_64"
        default: throw InstallError.unsupportedArchitecture(hostArchitecture())
        }
    }

    public static func colimaDownloadURL(architecture: String) -> URL {
        URL(string: "https://github.com/abiosoft/colima/releases/download/\(colimaVersion)/colima-Darwin-\(architecture)")!
    }

    public static func limaDownloadURL(architecture: String) -> URL {
        URL(string: "https://github.com/lima-vm/lima/releases/download/v\(limaVersion)/lima-\(limaVersion)-Darwin-\(architecture).tar.gz")!
    }

    public static func dockerDownloadURL(architecture: String) -> URL {
        let dockerArch = architecture == "arm64" ? "aarch64" : "x86_64"
        return URL(string: "https://download.docker.com/mac/static/stable/\(dockerArch)/docker-\(dockerVersion).tgz")!
    }

    private func createManagedDirectories() throws {
        cleanupLegacyVMStateIfUnused()
        for directory in [
            binDirectory,
            downloadsDirectory,
            colimaHomeDirectory,
            colimaCacheDirectory,
            limaHomeDirectory,
            dockerConfigDirectory,
            gpacDirectory,
            wrapperDataDirectory,
            downloaderWorkDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func cleanupLegacyVMStateIfUnused() {
        let legacyLimaHome = rootURL.appendingPathComponent("lima-home", isDirectory: true)
        guard legacyLimaHome.standardizedFileURL != limaHomeDirectory.standardizedFileURL,
              !fileManager.fileExists(atPath: legacyLimaHome.appendingPathComponent("colima").path)
        else {
            return
        }

        for directory in [
            rootURL.appendingPathComponent("colima-home", isDirectory: true),
            legacyLimaHome
        ] where fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
                DiagnosticLog.append("[Install] 已清理旧的长路径 VM 状态：\(directory.path)")
            } catch {
                DiagnosticLog.append("[Install] 清理旧 VM 状态失败：\(directory.path) \(error.localizedDescription)")
            }
        }
    }

    private func installColima() async throws {
        let arch = try Self.releaseArchitecture()
        let downloaded = try await download(Self.colimaDownloadURL(architecture: arch), named: "colima-Darwin-\(arch)")
        do {
            try replaceItem(at: colimaURL, with: downloaded)
            try await prepareDownloadedExecutable(colimaURL)
            try await verifyExecutable(colimaURL, arguments: ["version"])
        } catch {
            discardCachedDownload(downloaded)
            try? fileManager.removeItem(at: colimaURL)
            throw error
        }
    }

    private func installLima() async throws {
        let arch = try Self.releaseArchitecture()
        let archive = try await download(Self.limaDownloadURL(architecture: arch), named: "lima-\(Self.limaVersion)-Darwin-\(arch).tar.gz")
        let extractURL = downloadsDirectory.appendingPathComponent("lima-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractURL) }

        do {
            let result = try await runner.run(executablePath: "/usr/bin/tar", arguments: ["-xzf", archive.path, "-C", extractURL.path])
            guard result.succeeded else {
                throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? result.standardOutput : result.standardError)
            }

            let lima = try findFile(named: "lima", under: extractURL)
            let limactl = try findFile(named: "limactl", under: extractURL)
            try replaceItem(at: limaURL, with: lima)
            try replaceItem(at: limactlURL, with: limactl)
            try await prepareDownloadedExecutable(limaURL)
            try await prepareDownloadedExecutable(limactlURL, requiresVirtualization: true)

            if let share = try? findDirectory(pathSuffix: "share/lima", under: extractURL) {
                let destination = rootURL.appendingPathComponent("share/lima", isDirectory: true)
                try replaceDirectory(at: destination, with: share)
            }

            try await verifyExecutable(limaURL, arguments: ["--version"])
            try await verifyExecutable(limactlURL, arguments: ["--version"])
        } catch {
            discardCachedDownload(archive)
            try? fileManager.removeItem(at: limaURL)
            try? fileManager.removeItem(at: limactlURL)
            try? fileManager.removeItem(at: rootURL.appendingPathComponent("share/lima", isDirectory: true))
            throw error
        }
    }

    private func installDocker() async throws {
        let arch = try Self.releaseArchitecture()
        let downloadURL = Self.dockerDownloadURL(architecture: arch)
        DiagnosticLog.append("[Install][Docker] arch=\(arch) url=\(downloadURL.absoluteString)")
        let archive = try await download(downloadURL, named: "docker-\(Self.dockerVersion).tgz")
        DiagnosticLog.append("[Install][Docker] archive=\(describeFile(at: archive))")
        let extractURL = downloadsDirectory.appendingPathComponent("docker-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractURL) }
        DiagnosticLog.append("[Install][Docker] extractURL=\(extractURL.path)")

        do {
            let result = try await runner.run(executablePath: "/usr/bin/tar", arguments: ["-xzf", archive.path, "-C", extractURL.path])
            guard result.succeeded else {
                throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? result.standardOutput : result.standardError)
            }
            DiagnosticLog.append("[Install][Docker] tar 解包完成 stdout=\(trimForLog(result.standardOutput)) stderr=\(trimForLog(result.standardError))")
            logCandidates(named: "docker", under: extractURL, context: "Docker")

            let found = try findFile(named: "docker", under: extractURL)
            DiagnosticLog.append("[Install][Docker] selected=\(describeFile(at: found))")
            await logFileCommand(found, context: "Docker selected")
            try replaceItem(at: dockerURL, with: found)
            DiagnosticLog.append("[Install][Docker] copied=\(describeFile(at: dockerURL))")
            await logFileCommand(dockerURL, context: "Docker destination")
            try await prepareDownloadedExecutable(dockerURL)
            DiagnosticLog.append("[Install][Docker] prepared=\(describeFile(at: dockerURL))")
            try await verifyExecutable(dockerURL, arguments: ["--version"])
        } catch {
            discardCachedDownload(archive)
            try? fileManager.removeItem(at: dockerURL)
            throw error
        }
    }

    private func installGPAC() async throws {
        let package = try await gpacPackageURL()
        let extractRoot = downloadsDirectory.appendingPathComponent("gpac-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractRoot) }

        do {
            let packageRoot: URL
            if package.pathExtension.lowercased() == "pkg" {
                let expandedURL = extractRoot.appendingPathComponent("expanded", isDirectory: true)
                DiagnosticLog.append("[Install][GPAC] 解包官方 pkg：\(package.path)")
                let result = try await runner.run(
                    executablePath: "/usr/sbin/pkgutil",
                    arguments: ["--expand-full", package.path, expandedURL.path]
                )
                guard result.succeeded else {
                    throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? result.standardOutput : result.standardError)
                }
                packageRoot = try findDirectory(pathSuffix: "GPAC.app/Contents/MacOS", under: expandedURL)
            } else {
                DiagnosticLog.append("[Install][GPAC] 解包自定义 tar.gz：\(package.path)")
                let result = try await runner.run(
                    executablePath: "/usr/bin/tar",
                    arguments: ["-xzf", package.path, "-C", extractRoot.path]
                )
                guard result.succeeded else {
                    throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? result.standardOutput : result.standardError)
                }
                guard let found = try firstDirectory(containing: "MP4Box", under: extractRoot) else {
                    throw InstallError.invalidPackage("GPAC 运行时包中未找到 MP4Box。")
                }
                packageRoot = found
            }

            DiagnosticLog.append("[Install][GPAC] runtime root=\(packageRoot.path)")
            try replaceDirectory(at: gpacDirectory, with: packageRoot)
            try await prepareDownloadedExecutable(mp4BoxURL)
            try await verifyExecutable(mp4BoxURL, arguments: ["-version"])
        } catch {
            discardCachedDownload(package)
            try? fileManager.removeItem(at: gpacDirectory)
            throw error
        }
    }

    private func gpacPackageURL() async throws -> URL {
        if let value = gpacPackageURLOverride ?? ProcessInfo.processInfo.environment[Self.gpacPackageEnvironmentKey],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let url: URL
            if trimmed.hasPrefix("/") {
                url = URL(fileURLWithPath: trimmed)
            } else if let parsed = URL(string: trimmed), parsed.scheme != nil {
                url = parsed
            } else {
                url = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
            }
            if url.isFileURL { return url }
            let name = url.pathExtension.lowercased() == "pkg" ? "gpac-runtime.pkg" : "gpac-runtime.tar.gz"
            return try await download(url, named: name)
        }

        for name in ["gpac-runtime.pkg", "gpac-runtime.tar.gz"] {
            let localPackage = downloadsDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: localPackage.path) {
                return localPackage
            }
        }

        DiagnosticLog.append("[Install][GPAC] 使用官方默认包：\(Self.gpacDefaultPackageURL.absoluteString)")
        return try await download(Self.gpacDefaultPackageURL, named: "gpac-runtime.pkg")
    }

    private func download(_ url: URL, named name: String) async throws -> URL {
        if url.isFileURL {
            DiagnosticLog.append("[Install] 使用本地文件：\(url.path)")
            return url
        }

        let destination = downloadsDirectory.appendingPathComponent(name)
        let partial = downloadsDirectory.appendingPathComponent("\(name).part")
        DiagnosticLog.append("[Install] 开始下载：\(url.absoluteString) → \(destination.path)")
        if fileManager.fileExists(atPath: destination.path) {
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 0 {
                DiagnosticLog.append("[Install] 使用已下载缓存：\(destination.path) (\(size) bytes)")
                return destination
            }
            try fileManager.removeItem(at: destination)
        }

        let existingBytes = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if existingBytes > 0 {
            DiagnosticLog.append("[Install] 从 \(existingBytes) bytes 继续下载：\(partial.path)")
        }

        var lastError = "下载中断：\(url.absoluteString)"
        for attempt in 1...Self.downloadAttemptCount {
            let bytesBeforeAttempt = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let result = try await runner.run(
                executablePath: "/usr/bin/curl",
                arguments: Self.downloadArguments(url: url, partial: partial)
            )
            let bytesAfterAttempt = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            guard bytesAfterAttempt >= bytesBeforeAttempt else {
                throw ProcessRunnerError.processFailed(
                    "下载缓存异常缩小：\(bytesBeforeAttempt) → \(bytesAfterAttempt) bytes"
                )
            }
            if result.succeeded {
                break
            }

            lastError = result.standardError.isEmpty ? lastError : result.standardError
            DiagnosticLog.append(
                "[Install] 下载中断 attempt=\(attempt)/\(Self.downloadAttemptCount) "
                    + "exit=\(result.exitCode) partial=\(bytesAfterAttempt) "
                    + "advanced=\(bytesAfterAttempt - bytesBeforeAttempt) "
                    + "stderr=\(trimForLog(result.standardError))"
            )
            guard attempt < Self.downloadAttemptCount else {
                throw ProcessRunnerError.processFailed(lastError)
            }
            try await Task.sleep(for: .seconds(2))
        }

        let fileSize = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            throw ProcessRunnerError.processFailed("下载完成但文件为空：\(url.absoluteString)")
        }
        removeQuarantine(from: partial)
        try fileManager.moveItem(at: partial, to: destination)
        DiagnosticLog.append("[Install] 下载完成：\(name) (\(fileSize) bytes)")
        return destination
    }

    static func downloadArguments(url: URL, partial: URL) -> [String] {
        [
            "--location",
            "--fail",
            "--silent",
            "--show-error",
            "--continue-at", "-",
            "--connect-timeout", "30",
            "--speed-limit", "1",
            "--speed-time", "120",
            "--output", partial.path,
            url.absoluteString
        ]
    }

    private func verifyExecutable(_ url: URL, arguments: [String]) async throws {
        DiagnosticLog.append("[Install] 验证可执行文件（直接执行）：\(url.path)")
        if let directError = await tryDirectExecute(url, arguments: arguments) {
            // Direct execution failed — log the error for diagnosis
            DiagnosticLog.append("[Install] 直接执行失败：\(directError)")

            // Fallback: try executing via /bin/sh as a trampoline.
            // Some macOS security policies treat shell-mediated execution
            // differently from direct posix_spawn.
            DiagnosticLog.append("[Install] 尝试通过 /bin/sh 执行...")
            let shellCmd = "'\(url.path)' \(arguments.joined(separator: " "))"
            let result = try await runner.runShell(shellCmd)
            guard result.succeeded else {
                DiagnosticLog.append("[Install] shell 执行也失败 exitCode=\(result.exitCode) stderr=\(result.standardError)")
                throw ProcessRunnerError.processFailed(result.standardError.isEmpty ? result.standardOutput : result.standardError)
            }
            DiagnosticLog.append("[Install] shell 执行成功：\(url.lastPathComponent)")
        } else {
            DiagnosticLog.append("[Install] 验证成功：\(url.lastPathComponent)")
        }
    }

    /// Attempts to run the binary directly. Returns an error description on
    /// failure, or `nil` on success.
    private func tryDirectExecute(_ url: URL, arguments: [String]) async -> String? {
        do {
            let result = try await runner.run(executablePath: url.path, arguments: arguments, environment: runtimeEnvironment())
            if result.succeeded { return nil }
            return "exitCode=\(result.exitCode) stderr=\(result.standardError)"
        } catch {
            return "\(error.localizedDescription)"
        }
    }

    private func validateExistingExecutable(
        _ url: URL,
        arguments: [String],
        component: String
    ) async -> Bool {
        guard isRegularExecutable(url) else {
            DiagnosticLog.append("[Install] \(component) 未安装或不是常规可执行文件")
            return false
        }
        DiagnosticLog.append("[Install] 检验已安装组件：\(component) → \(url.path)")
        guard await tryDirectExecute(url, arguments: arguments) == nil else {
            DiagnosticLog.append("[Install] 已安装的 \(component) 检验失败，将重新安装")
            try? fileManager.removeItem(at: url)
            return false
        }
        DiagnosticLog.append("[Install] 已安装的 \(component) 检验通过，跳过下载")
        return true
    }

    private func ensureWrapperImageAvailable() async throws -> (
        status: ManagedDockerImageStatus,
        wasPulled: Bool
    ) {
        if let wrapperImageInstaller {
            return try await wrapperImageInstaller(self)
        }

        let runtime = ColimaDockerRuntime(runtimeManager: self)
        _ = try await runtime.ensureRunning()
        let imageManager = DockerImageManager(runtime: runtime)
        let current = await imageManager.check(.appleMusicWrapper)
        if current.isAvailable {
            DiagnosticLog.append("[Install] wrapper 镜像已存在，跳过拉取")
            return (current, false)
        }

        DiagnosticLog.append("[Install] 开始拉取 wrapper 镜像：\(ManagedDockerImage.appleMusicWrapper.imageName)")
        let pull = try await imageManager.pull(.appleMusicWrapper)
        guard pull.succeeded else {
            let detail = pull.standardError.isEmpty ? pull.standardOutput : pull.standardError
            throw ProcessRunnerError.processFailed("wrapper 镜像拉取失败：\(detail)")
        }
        let status = await imageManager.check(.appleMusicWrapper)
        guard status.isAvailable else {
            throw ProcessRunnerError.processFailed("wrapper 镜像拉取完成，但 Docker 未能检验该镜像。")
        }
        DiagnosticLog.append("[Install] wrapper 镜像拉取并检验完成")
        return (status, true)
    }

    @discardableResult
    private func cleanupDownloadedSources() -> Int {
        cleanupDirectoryContents(downloadsDirectory, context: "下载缓存")
    }

    @discardableResult
    private func cleanupDirectoryContents(_ directory: URL, context: String) -> Int {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        var removedCount = 0
        for item in items {
            do {
                try fileManager.removeItem(at: item)
                removedCount += 1
                DiagnosticLog.append("[Install] 已清理\(context)：\(item.path)")
            } catch {
                DiagnosticLog.append("[Install] 清理\(context)失败：\(item.path) \(error.localizedDescription)")
            }
        }
        return removedCount
    }

    private func discardCachedDownload(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == downloadsDirectory.standardizedFileURL else {
            return
        }
        DiagnosticLog.append("[Install] 删除未通过检验的缓存：\(url.path)")
        try? fileManager.removeItem(at: url)
    }

    private func executableStatus(_ component: AppleMusicRuntimeComponent, url: URL) -> AppleMusicRuntimeComponentStatus {
        let isReady = isRegularExecutable(url)
        return AppleMusicRuntimeComponentStatus(
            component: component,
            isReady: isReady,
            resolvedPath: isReady ? url.path : nil,
            detail: isReady ? url.path : unavailableExecutableDetail(url)
        )
    }

    private func limaStatus() -> AppleMusicRuntimeComponentStatus {
        let shareURL = rootURL.appendingPathComponent("share/lima", isDirectory: true)
        let isReady = isRegularExecutable(limaURL)
            && isRegularExecutable(limactlURL)
            && fileManager.fileExists(atPath: shareURL.path)
        let detail: String
        if isReady {
            detail = "\(limaURL.path), \(limactlURL.path)"
        } else {
            var missing: [String] = []
            if !isRegularExecutable(limaURL) { missing.append(limaURL.path) }
            if !isRegularExecutable(limactlURL) { missing.append(limactlURL.path) }
            if !fileManager.fileExists(atPath: shareURL.path) { missing.append(shareURL.path) }
            detail = "缺少：" + missing.joined(separator: "，")
        }
        return AppleMusicRuntimeComponentStatus(
            component: .lima,
            isReady: isReady,
            resolvedPath: isReady ? limaURL.path : nil,
            detail: detail
        )
    }

    private func writeProgress(
        _ message: String,
        completed: Int,
        total: Int,
        isActive: Bool,
        wrapperStatus: ManagedDockerImageStatus? = nil
    ) {
        guard let url = progressURL else {
            return
        }

        let progress = AppleMusicRuntimeProgress(
            message: message,
            completedUnitCount: completed,
            totalUnitCount: total,
            isActive: isActive,
            statuses: componentStatuses(wrapperStatus: wrapperStatus)
        )
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(progress).write(to: url, options: .atomic)
        } catch {
            DiagnosticLog.append("[Install] 写入进度失败：\(error.localizedDescription)")
        }
    }

    private func makeExecutable(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    public func ensureLimaVirtualizationEntitlement() async throws {
        let inspection = try await runner.run(
            executablePath: "/usr/bin/codesign",
            arguments: ["-d", "--entitlements", "-", limactlURL.path]
        )
        let existingEntitlements = inspection.standardOutput + inspection.standardError
        if inspection.succeeded,
           existingEntitlements.contains("com.apple.security.virtualization") {
            return
        }
        try await prepareDownloadedExecutable(limactlURL, requiresVirtualization: true)
    }

    public func limaHostAgentError() -> String {
        let logURL = limaHomeDirectory
            .appendingPathComponent("colima", isDirectory: true)
            .appendingPathComponent("ha.stderr.log")
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return trimForLog(text, limit: 2_000)
    }

    /// Ad-hoc code-signs a downloaded binary so that macOS allows its execution.
    private func prepareDownloadedExecutable(
        _ url: URL,
        requiresVirtualization: Bool = false
    ) async throws {
        // Ensure execute permission (belt-and-suspenders; download() already
        // set 755, but tar-extracted files may have come through with the
        // permissions stored in the archive).
        try makeExecutable(url)

        // Ad-hoc signing — gives the binary a valid (identity-less) signature
        // so Gatekeeper / AMFI allow execution.
        DiagnosticLog.append("[Install] 开始签名：\(url.path)")
        var arguments = ["--force", "--sign", "-"]
        var entitlementsURL: URL?
        if requiresVirtualization {
            let url = downloadsDirectory.appendingPathComponent("limactl-entitlements.plist")
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["com.apple.security.virtualization": true],
                format: .xml,
                options: 0
            )
            try data.write(to: url, options: .atomic)
            entitlementsURL = url
            arguments += ["--entitlements", url.path]
        }
        defer {
            if let entitlementsURL {
                try? fileManager.removeItem(at: entitlementsURL)
            }
        }
        arguments.append(url.path)
        let signResult = try await runner.run(
            executablePath: "/usr/bin/codesign",
            arguments: arguments
        )
        if !signResult.succeeded {
            DiagnosticLog.append("[Install] 签名失败 stdout=\(signResult.standardOutput) stderr=\(signResult.standardError)")
            throw ProcessRunnerError.processFailed(
                "无法对 \(url.lastPathComponent) 进行代码签名：\(signResult.standardError)"
            )
        }
        DiagnosticLog.append("[Install] 签名完成：\(url.path)")
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        DiagnosticLog.append("[Install] replaceItem source=\(describeFile(at: source)) destination=\(destination.path)")
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            DiagnosticLog.append("[Install] replaceItem removing existing destination=\(describeFile(at: destination))")
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        DiagnosticLog.append("[Install] replaceItem copied destination=\(describeFile(at: destination))")
    }

    private func replaceDirectory(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Removes all extended attributes (including `com.apple.quarantine`) from a
    /// file by reading its raw data and writing it back to a brand-new inode.
    ///
    /// The App Sandbox blocks `removexattr` / `/usr/bin/xattr -d` **everywhere**
    /// (including the app's own container).  However, macOS only tags a file with
    /// quarantine when it is *created* by a network-accessing process.  Files
    /// created by a plain `Data.write` are local and get no quarantine.
    private func removeQuarantine(from url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else {
            DiagnosticLog.append("[Install] 无法读取文件以重建：\(url.path)")
            return
        }

        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).clean")

        do {
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
            DiagnosticLog.append("[Install] 已重建（无 quarantine）：\(url.path)")
        } catch {
            DiagnosticLog.append("[Install] 重建文件失败：\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private func findFile(named name: String, under root: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw InstallError.missingInstalledFile(name)
        }

        for case let url as URL in enumerator where url.lastPathComponent == name {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            DiagnosticLog.append("[Install] findFile candidate name=\(name) regular=\(values.isRegularFile == true) \(describeFile(at: url))")
            if values.isRegularFile == true {
                return url
            }
        }

        throw InstallError.missingInstalledFile(name)
    }

    private func logCandidates(named name: String, under root: URL, context: String) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            DiagnosticLog.append("[Install][\(context)] 无法枚举 \(root.path)")
            return
        }

        var count = 0
        for case let url as URL in enumerator where url.lastPathComponent == name {
            count += 1
            DiagnosticLog.append("[Install][\(context)] candidate[\(count)] \(describeFile(at: url))")
        }
        if count == 0 {
            DiagnosticLog.append("[Install][\(context)] 未找到名为 \(name) 的候选项 under=\(root.path)")
        }
    }

    private func describeFile(at url: URL) -> String {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let attrs = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber).map { String($0.int64Value) } ?? "?"
        let permissions = (attrs[.posixPermissions] as? NSNumber).map { String($0.intValue, radix: 8) } ?? "?"
        let owner = attrs[.ownerAccountName] as? String ?? "?"
        return "path=\(url.path) exists=\(exists) directory=\(isDirectory.boolValue) regular=\(values?.isRegularFile == true) symlink=\(values?.isSymbolicLink == true) executable=\(fileManager.isExecutableFile(atPath: url.path)) size=\(size) permissions=\(permissions) owner=\(owner)"
    }

    private func logFileCommand(_ url: URL, context: String) async {
        do {
            let result = try await runner.run(executablePath: "/usr/bin/file", arguments: [url.path])
            DiagnosticLog.append("[Install][\(context)] /usr/bin/file exit=\(result.exitCode) stdout=\(trimForLog(result.standardOutput)) stderr=\(trimForLog(result.standardError))")
        } catch {
            DiagnosticLog.append("[Install][\(context)] /usr/bin/file failed: \(error.localizedDescription)")
        }
    }

    private func trimForLog(_ text: String, limit: Int = 600) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "...<truncated>"
    }

    private func isRegularExecutable(_ url: URL) -> Bool {
        guard fileManager.isExecutableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        else {
            return false
        }
        return values.isRegularFile == true
    }

    private func unavailableExecutableDetail(_ url: URL) -> String {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "\(url.path) 是目录，不是可执行文件；请重新安装 Apple Music 运行时。"
        }
        return "未安装到 \(url.path)"
    }

    private func findDirectory(pathSuffix: String, under root: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            throw InstallError.missingInstalledFile(pathSuffix)
        }

        for case let url as URL in enumerator where url.path.hasSuffix(pathSuffix) {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                return url
            }
        }

        throw InstallError.missingInstalledFile(pathSuffix)
    }

    private func firstDirectory(containing fileName: String, under root: URL) throws -> URL? {
        let file = try findFile(named: fileName, under: root)
        return file.deletingLastPathComponent()
    }
}
