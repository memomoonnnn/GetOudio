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

    init() {
        refresh()
    }

    func refresh() {
        Task { [weak self] in
            do {
                try await BackgroundAgentRegistration.ensureAvailable()
                guard !Task.isCancelled else { return }
                self?.state = .enabled
                self?.message = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .unavailable
            }
        }
    }

    func installBackgroundActivity() {
        guard BackgroundAgentRegistration.openInstaller() else {
            message = "未找到内嵌后台活动安装器。请重新安装 Get Oudio。"
            return
        }
        message = "已在 Terminal 中打开安装器。完成后点击“检查连接”。"
    }

    func installOnFirstSettingsPresentationIfNeeded() {
        let key = "GetOudioV2.legacyBackgroundServiceInstallerRevision"
        let requiredRevision = 2
        guard UserDefaults.standard.integer(forKey: key) < requiredRevision else { return }
        UserDefaults.standard.set(requiredRevision, forKey: key)
        installBackgroundActivity()
    }
}
