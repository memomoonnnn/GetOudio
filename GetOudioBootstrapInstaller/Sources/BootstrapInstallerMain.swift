import AppKit
import Darwin
import Foundation
import OSLog

@main
final class GetOudioBootstrapInstaller: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "com.shengjiacheng.GetOudio.BootstrapInstaller",
        category: "registration"
    )
    private static let agentLabel = "com.shengjiacheng.GetOudio.agent"
    private static let runtimeWorkerLabel = "com.shengjiacheng.GetOudio.runtime-worker"
    private var didHandleInvocation = false

    static func main() {
        let delegate = GetOudioBootstrapInstaller()
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.didHandleInvocation else { return }
                self.finish(with: InstallerError.invalidArguments)
            }
            return
        }
        perform(Invocation.result(arguments: arguments))
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else {
            finish(with: InstallerError.invalidArguments)
            return
        }
        perform(Invocation.result(url: url))
    }

    private func perform(_ result: Result<Invocation, Error>) {
        guard !didHandleInvocation else { return }
        didHandleInvocation = true
        do {
            let invocation = try result.get()
            try Self.validateApplicationLocation(invocation.appURL)
            Self.logger.info("Starting \(invocation.action.rawValue, privacy: .public)")
            switch invocation.action {
            case .install:
                try Self.install(appURL: invocation.appURL)
            case .uninstall:
                try Self.uninstall()
            }
            Self.logger.info("Finished \(invocation.action.rawValue, privacy: .public)")
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            finish(with: error)
        }
    }

    private func finish(with error: Error) {
        didHandleInvocation = true
        Self.logger.error("Bootstrap operation failed: \(error.localizedDescription, privacy: .public)")
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        Darwin.exit(EXIT_FAILURE)
    }

    private static func install(appURL: URL) throws {
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/Get Oudio")
        let runtimeWorkerURL = appURL.appendingPathComponent(
            "Contents/Helpers/GetOudioAMRuntimeWorker.app/Contents/MacOS/GetOudioAMRuntimeWorker"
        )
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources/LaunchAgents", isDirectory: true)
        let agentTemplateURL = resourcesURL.appendingPathComponent("\(agentLabel).plist")
        let runtimeWorkerTemplateURL = resourcesURL.appendingPathComponent("\(runtimeWorkerLabel).plist")

        try requireExecutable(executableURL)
        try requireExecutable(runtimeWorkerURL)

        let launchAgentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: launchAgentsURL,
            withIntermediateDirectories: true
        )

        let agentPlistURL = launchAgentsURL.appendingPathComponent("\(agentLabel).plist")
        let runtimeWorkerPlistURL = launchAgentsURL.appendingPathComponent("\(runtimeWorkerLabel).plist")
        let agentData = try configuredPlist(
            templateURL: agentTemplateURL,
            executablePath: executableURL.path
        )
        let runtimeWorkerData = try configuredPlist(
            templateURL: runtimeWorkerTemplateURL,
            executablePath: runtimeWorkerURL.path
        )

        bootout(agentLabel)
        bootout(runtimeWorkerLabel)
        try agentData.write(to: agentPlistURL, options: .atomic)
        try runtimeWorkerData.write(to: runtimeWorkerPlistURL, options: .atomic)

        do {
            try launchctl(["bootstrap", userDomain, agentPlistURL.path])
            try launchctl(["bootstrap", userDomain, runtimeWorkerPlistURL.path])
            try launchctl(["kickstart", "-k", "\(userDomain)/\(agentLabel)"])
        } catch {
            bootout(agentLabel)
            bootout(runtimeWorkerLabel)
            try? FileManager.default.removeItem(at: agentPlistURL)
            try? FileManager.default.removeItem(at: runtimeWorkerPlistURL)
            throw error
        }
    }

    private static func validateApplicationLocation(_ appURL: URL) throws {
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard appURL.lastPathComponent == "Get Oudio.app",
              appURL.deletingLastPathComponent().standardizedFileURL == applicationsURL
        else {
            throw InstallerError.invalidApplicationLocation
        }
    }

    private static func uninstall() throws {
        bootout(agentLabel)
        bootout(runtimeWorkerLabel)
        let launchAgentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        for label in [agentLabel, runtimeWorkerLabel] {
            let plistURL = launchAgentsURL.appendingPathComponent("\(label).plist")
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        }
    }

    private static func configuredPlist(
        templateURL: URL,
        executablePath: String
    ) throws -> Data {
        let data = try Data(contentsOf: templateURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw InstallerError.invalidTemplate(templateURL.lastPathComponent)
        }
        var arguments = plist["ProgramArguments"] as? [String] ?? []
        guard !arguments.isEmpty else {
            throw InstallerError.invalidTemplate(templateURL.lastPathComponent)
        }
        arguments[0] = executablePath
        plist["ProgramArguments"] = arguments
        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }

    private static func requireExecutable(_ url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw InstallerError.missingExecutable(url.path)
        }
    }

    private static func bootout(_ label: String) {
        try? launchctl(["bootout", "\(userDomain)/\(label)"])
    }

    private static func launchctl(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.launchctlFailed(
                detail.flatMap { $0.isEmpty ? nil : $0 } ?? arguments.joined(separator: " ")
            )
        }
    }

    private static var userDomain: String {
        "gui/\(getuid())"
    }
}

private struct Invocation {
    enum Action: String {
        case install
        case uninstall
    }

    let action: Action
    let appURL: URL

    static func result(arguments: [String]) -> Result<Self, Error> {
        Result { try Invocation(arguments: arguments) }
    }

    static func result(url: URL) -> Result<Self, Error> {
        Result { try Invocation(url: url) }
    }

    private init(arguments: [String]) throws {
        guard let rawAction = arguments.first,
              let action = Action(rawValue: rawAction),
              let appIndex = arguments.firstIndex(of: "--app"),
              arguments.indices.contains(appIndex + 1)
        else {
            throw InstallerError.invalidArguments
        }
        self.action = action
        appURL = URL(fileURLWithPath: arguments[appIndex + 1], isDirectory: true)
    }

    private init(url: URL) throws {
        guard url.scheme == "getoudio-bootstrap",
              let rawAction = url.host,
              let action = Action(rawValue: rawAction)
        else {
            throw InstallerError.invalidArguments
        }
        self.action = action
        appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum InstallerError: LocalizedError {
    case invalidArguments
    case invalidApplicationLocation
    case invalidTemplate(String)
    case missingExecutable(String)
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "用法：GetOudioBootstrapInstaller <install|uninstall> --app <Get Oudio.app>"
        case .invalidApplicationLocation:
            return "Get Oudio 必须位于 /Applications。"
        case .invalidTemplate(let name):
            return "LaunchAgent 模板无效：\(name)"
        case .missingExecutable(let path):
            return "找不到可执行文件：\(path)"
        case .launchctlFailed(let detail):
            return "后台活动注册失败：\(detail)"
        }
    }
}
