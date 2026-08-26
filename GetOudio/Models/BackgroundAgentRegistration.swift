import AppKit
import GetOudioCore

enum BackgroundAgentRegistration {
    enum Action: String, Equatable {
        case install
        case uninstall
    }

    @MainActor
    static func launch(_ action: Action) async throws {
        let appURL = Bundle.main.bundleURL.standardizedFileURL
        guard appURL.deletingLastPathComponent().path == "/Applications" else {
            throw RegistrationError.invalidApplicationLocation
        }
        let installerURL = appURL.appendingPathComponent(
            "Contents/Helpers/GetOudioBootstrapInstaller.app",
            isDirectory: true
        )
        guard FileManager.default.isExecutableFile(
            atPath: installerURL.appendingPathComponent(
                "Contents/MacOS/GetOudioBootstrapInstaller"
            ).path
        ) else {
            throw RegistrationError.missingInstaller
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        guard let operationURL = URL(string: "getoudio-bootstrap://\(action.rawValue)") else {
            throw RegistrationError.invalidOperationURL
        }
        let application = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<NSRunningApplication, Error>) in
            NSWorkspace.shared.open(
                [operationURL],
                withApplicationAt: installerURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(throwing: RegistrationError.installerDidNotLaunch)
                }
            }
        }
        for _ in 0..<300 where !application.isTerminated {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard application.isTerminated else {
            throw RegistrationError.installerTimedOut
        }
    }

    static func ensureAvailable() async throws {
        try await BackgroundAgentClient().checkAvailability()
    }
}

private enum RegistrationError: LocalizedError {
    case invalidApplicationLocation
    case missingInstaller
    case invalidOperationURL
    case installerDidNotLaunch
    case installerTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidApplicationLocation:
            return "请先将 Get Oudio.app 移入“应用程序”文件夹。"
        case .missingInstaller:
            return "未找到内嵌 Bootstrap Installer，请重新安装 Get Oudio。"
        case .invalidOperationURL:
            return "无法构造 Bootstrap Installer 操作。"
        case .installerDidNotLaunch:
            return "Bootstrap Installer 未能启动。"
        case .installerTimedOut:
            return "Bootstrap Installer 执行超时。"
        }
    }
}
