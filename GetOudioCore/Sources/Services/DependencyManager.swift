import Foundation

public final class DependencyManager {
    private let runner: ProcessRunner
    private let resourceRoot: URL?

    public init(runner: ProcessRunner = ProcessRunner(), resourceRoot: URL? = Bundle.main.resourceURL) {
        self.runner = runner
        self.resourceRoot = resourceRoot
    }

    public func checkAll() async -> [DependencyStatus] {
        await withTaskGroup(of: DependencyStatus.self) { group in
            for dependency in RuntimeDependency.allCases {
                group.addTask { await self.check(dependency) }
            }

            var statuses: [DependencyStatus] = []
            for await status in group {
                statuses.append(status)
            }
            return statuses.sorted { lhs, rhs in
                if lhs.dependency.sortPriority == rhs.dependency.sortPriority {
                    return lhs.dependency.displayName < rhs.dependency.displayName
                }
                return lhs.dependency.sortPriority < rhs.dependency.sortPriority
            }
        }
    }

    public func check(_ dependency: RuntimeDependency) async -> DependencyStatus {
        // 优先检查内嵌二进制
        if let bundledPath = dependency.bundledRelativePath,
           let resourceRoot = resourceRoot {
            let bundledURL = resourceRoot.appendingPathComponent(bundledPath)
            if FileManager.default.isExecutableFile(atPath: bundledURL.path) {
                return DependencyStatus(
                    dependency: dependency,
                    isInstalled: true,
                    resolvedPath: bundledURL.path,
                    detail: "内嵌 (\(bundledURL.path))"
                )
            }
        }

        // 回退到系统 PATH
        do {
            let result = try await runner.run(executablePath: "/usr/bin/which", arguments: [dependency.executableName])
            let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let installed = result.succeeded && !path.isEmpty
            let detail = installed ? path : "未安装或不在 PATH 中"
            return DependencyStatus(dependency: dependency, isInstalled: installed, resolvedPath: installed ? path : nil, detail: detail)
        } catch {
            return DependencyStatus(dependency: dependency, isInstalled: false, resolvedPath: nil, detail: error.localizedDescription)
        }
    }

    public func install(_ dependency: RuntimeDependency) async throws -> ProcessResult {
        try await runner.runShell(dependency.installCommand)
    }
}

public final class BundledComponentManager {
    private let resourceRoot: URL?

    public init(resourceRoot: URL? = Bundle.main.resourceURL) {
        self.resourceRoot = resourceRoot
    }

    public func checkAll() -> [BundledComponentStatus] {
        BundledComponent.allCases.map(check(_:))
    }

    public func check(_ component: BundledComponent) -> BundledComponentStatus {
        guard let resourceRoot else {
            return BundledComponentStatus(
                component: component,
                isEmbedded: false,
                resolvedURL: nil,
                detail: "无法定位 App 资源目录"
            )
        }

        let url = resourceRoot.appendingPathComponent(component.expectedRelativePath)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let executable = FileManager.default.isExecutableFile(atPath: url.path)

        if exists && executable {
            return BundledComponentStatus(component: component, isEmbedded: true, resolvedURL: url, detail: url.path)
        }

        if exists {
            return BundledComponentStatus(component: component, isEmbedded: false, resolvedURL: url, detail: "文件存在但不可执行：\(url.path)")
        }

        return BundledComponentStatus(
            component: component,
            isEmbedded: false,
            resolvedURL: nil,
            detail: "待嵌入：\(component.expectedRelativePath)"
        )
    }

    public func executableURL(for component: BundledComponent) throws -> URL {
        let status = check(component)
        guard status.isEmbedded, let url = status.resolvedURL else {
            throw ProcessRunnerError.executableNotFound(component.expectedRelativePath)
        }
        return url
    }
}

public final class DockerImageManager {
    private let runner: ProcessRunner
    private let runtime: ColimaDockerRuntime

    public init(runner: ProcessRunner = ProcessRunner(), runtime: ColimaDockerRuntime = ColimaDockerRuntime()) {
        self.runner = runner
        self.runtime = runtime
    }

    public func checkAll() async -> [ManagedDockerImageStatus] {
        var statuses: [ManagedDockerImageStatus] = []
        for image in ManagedDockerImage.allCases {
            statuses.append(await check(image))
        }
        return statuses
    }

    public func check(_ image: ManagedDockerImage) async -> ManagedDockerImageStatus {
        let runtimeStatus = await runtime.check()
        guard runtimeStatus.isRunning, let dockerPath = runtimeStatus.dockerPath else {
            return ManagedDockerImageStatus(image: image, isAvailable: false, detail: runtimeStatus.detail)
        }

        do {
            let result = try await runner.run(
                executablePath: dockerPath,
                arguments: runtime.dockerArguments(["image", "inspect", image.imageName]),
                environment: runtime.runtimeEnvironment
            )
            if result.succeeded {
                return ManagedDockerImageStatus(image: image, isAvailable: true, detail: "\(image.imageName) (\(image.platform), Colima)")
            }
            return ManagedDockerImageStatus(image: image, isAvailable: false, detail: "未拉取：\(image.imageName)")
        } catch {
            return ManagedDockerImageStatus(image: image, isAvailable: false, detail: error.localizedDescription)
        }
    }

    public func pull(_ image: ManagedDockerImage) async throws -> ProcessResult {
        let dockerPath = try await runtime.ensureRunning()
        return try await runner.run(
            executablePath: dockerPath,
            arguments: runtime.dockerArguments(["pull", "--platform", image.platform, image.imageName]),
            environment: runtime.runtimeEnvironment
        )
    }
}
