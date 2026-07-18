import AppKit
import Foundation
import GetOudioCore

final class AppleMusicRuntimeAgentLauncher {
    static let shared = AppleMusicRuntimeAgentLauncher()

    private init() {}

    func ensureRunning() async throws {
        guard let bundleURL = AppleMusicRuntimeAgentClient.defaultApplicationURL() else {
            throw NSError(
                domain: "GetOudioAMRuntimeAgentLauncher",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未找到 GetOudioAMRuntimeAgent.app。请重新构建应用。"]
            )
        }
        if await isRunning() {
            return
        }

        do {
            try await launchWithOpen(bundleURL)
            return
        } catch {
            try await launchWithNSWorkspace(bundleURL, openError: error)
        }
    }

    @MainActor
    private func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.shengjiacheng.GetOudio.AMRuntimeAgent").isEmpty
    }

    private func launchWithOpen(_ bundleURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var arguments = ["-g", "-j"]
            if let diagnosticRoot = ProcessInfo.processInfo.environment[SharedContainer.diagnosticRootEnvironmentKey] {
                arguments.append(contentsOf: [
                    "--env",
                    "\(SharedContainer.diagnosticRootEnvironmentKey)=\(diagnosticRoot)"
                ])
            }
            arguments.append(bundleURL.path)
            process.arguments = arguments

            let standardError = Pipe()
            process.standardError = standardError

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = standardError.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "GetOudioAMRuntimeAgentLauncher",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "/usr/bin/open 启动 GetOudioAMRuntimeAgent.app 失败。"]
                )
            }
        }.value
    }

    @MainActor
    private func launchWithNSWorkspace(_ bundleURL: URL, openError: Error) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        if let diagnosticRoot = ProcessInfo.processInfo.environment[SharedContainer.diagnosticRootEnvironmentKey] {
            configuration.environment = [SharedContainer.diagnosticRootEnvironmentKey: diagnosticRoot]
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        } catch {
            throw NSError(
                domain: "GetOudioAMRuntimeAgentLauncher",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法启动 Downloader Runtime Agent。open: \(openError.localizedDescription)；NSWorkspace: \(error.localizedDescription)"]
            )
        }
    }
}
