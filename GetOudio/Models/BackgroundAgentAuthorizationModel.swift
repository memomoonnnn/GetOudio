import Combine
import Foundation

@MainActor
final class BackgroundAgentAuthorizationModel: ObservableObject {
    enum State: Equatable {
        case enabled
        case unavailable
    }

    @Published private(set) var state: State = .unavailable
    @Published private(set) var message: String?
    @Published private(set) var isChangingRegistration = false

    init() {
        refresh()
    }

    func refresh() {
        guard !isChangingRegistration else { return }
        Task { [weak self] in
            guard let self else { return }
            let refreshedState: State = await Self.isAgentAvailable() ? .enabled : .unavailable
            guard !isChangingRegistration else { return }
            state = refreshedState
            message = nil
        }
    }

    func installBackgroundActivity() {
        changeRegistration(.install, automatic: false)
    }

    func uninstallBackgroundActivity() {
        changeRegistration(.uninstall, automatic: false)
    }

    func installOnFirstLaunchIfNeeded() {
        let key = "GetOudioV2.bootstrapInstallerRevision"
        let requiredRevision = 1
        guard UserDefaults.standard.integer(forKey: key) < requiredRevision else { return }
        changeRegistration(.install, automatic: true) { succeeded in
            if succeeded {
                UserDefaults.standard.set(requiredRevision, forKey: key)
            }
        }
    }

    private func changeRegistration(
        _ action: BackgroundAgentRegistration.Action,
        automatic: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !isChangingRegistration else { return }
        isChangingRegistration = true
        message = action == .install ? "正在安装后台活动..." : "正在卸载后台活动..."

        Task { [weak self] in
            guard let self else { return }
            if action == .install, await Self.isAgentAvailable() {
                state = .enabled
                message = automatic ? nil : "后台活动已安装。"
                isChangingRegistration = false
                completion?(true)
                return
            }

            do {
                try await BackgroundAgentRegistration.launch(action)
                let expectedState: State = action == .install ? .enabled : .unavailable
                guard await waitForState(expectedState) else {
                    throw RegistrationOperationError.timedOut
                }
                state = expectedState
                message = automatic
                    ? nil
                    : (action == .install ? "后台活动已安装。" : "后台活动已卸载。")
                isChangingRegistration = false
                completion?(true)
            } catch {
                state = await Self.isAgentAvailable() ? .enabled : .unavailable
                message = error.localizedDescription
                isChangingRegistration = false
                completion?(false)
            }
        }
    }

    private func waitForState(_ expectedState: State) async -> Bool {
        for _ in 0..<30 {
            let isAvailable = await Self.isAgentAvailable()
            if (expectedState == .enabled) == isAvailable {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private static func isAgentAvailable() async -> Bool {
        do {
            try await BackgroundAgentRegistration.ensureAvailable()
            return true
        } catch {
            return false
        }
    }
}

private enum RegistrationOperationError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "后台活动状态更新超时，请检查“登录项与扩展”设置后重试。"
    }
}
