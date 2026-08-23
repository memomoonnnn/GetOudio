import Foundation

public enum AppleMusicRuntimeOperationAvailability: Equatable, Sendable {
    case available
    case runtimeOperationInProgress
    case downloadInProgress
    case loginInProgress

    public init(
        isManagingRuntime: Bool,
        isRefreshingRuntimeStatus: Bool,
        progress: AppleMusicRuntimeProgress?,
        loginStatus: AppleMusicWrapperLoginStatus
    ) {
        if isManagingRuntime || isRefreshingRuntimeStatus {
            self = .runtimeOperationInProgress
        } else if progress?.isActive == true, progress?.statuses == nil {
            self = .downloadInProgress
        } else if loginStatus.isInProgress {
            self = .loginInProgress
        } else {
            self = .available
        }
    }

    public var isAvailable: Bool {
        self == .available
    }

    public var blockedMessage: String {
        switch self {
        case .available:
            return ""
        case .runtimeOperationInProgress:
            return "当前正在处理 Apple Music Runtime，请等待完成后再操作。"
        case .downloadInProgress:
            return "请先完成当前 Apple Music 下载，再操作 Runtime。"
        case .loginInProgress:
            return "请先完成当前 Apple Music 登录，再操作 Runtime。"
        }
    }
}
