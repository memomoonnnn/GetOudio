import CryptoKit
import Foundation

public enum ManagedRuntimeComponentUpdateState: String, Codable, Equatable, Sendable {
    case current
    case updateAvailable
    case legacy
    case missing

    public var displayName: String {
        switch self {
        case .current: return "已是目标版本"
        case .updateAvailable: return "可更新"
        case .legacy: return "需要更新"
        case .missing: return "未安装"
        }
    }
}

public struct ManagedRuntimeComponentSpec: Equatable, Sendable {
    public let component: AppleMusicRuntimeComponent
    public let targetVersion: String
    public let artifactURL: URL?
    public let artifactSHA256: String?

    public init(
        component: AppleMusicRuntimeComponent,
        targetVersion: String,
        artifactURL: URL? = nil,
        artifactSHA256: String? = nil
    ) {
        self.component = component
        self.targetVersion = targetVersion
        self.artifactURL = artifactURL
        self.artifactSHA256 = artifactSHA256
    }
}

public struct ManagedRuntimeComponentReceipt: Codable, Equatable, Sendable {
    public var component: AppleMusicRuntimeComponent
    public var version: String
    public var artifactSHA256: String?
    public var installedAt: Date
    public var activeImageID: String?

    public init(
        component: AppleMusicRuntimeComponent,
        version: String,
        artifactSHA256: String? = nil,
        installedAt: Date = Date(),
        activeImageID: String? = nil
    ) {
        self.component = component
        self.version = version
        self.artifactSHA256 = artifactSHA256
        self.installedAt = installedAt
        self.activeImageID = activeImageID
    }
}

public final class ManagedRuntimeComponentReceiptStore {
    private let fileManager: FileManager
    public let url: URL

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.url = rootURL.appendingPathComponent("component-receipts.json")
    }

    public func receipt(for component: AppleMusicRuntimeComponent) -> ManagedRuntimeComponentReceipt? {
        receipts()[component.rawValue]
    }

    public func save(_ receipt: ManagedRuntimeComponentReceipt) throws {
        var current = receipts()
        current[receipt.component.rawValue] = receipt
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(current).write(to: url, options: .atomic)
    }

    public func updateState(
        for spec: ManagedRuntimeComponentSpec,
        isInstalled: Bool
    ) -> ManagedRuntimeComponentUpdateState {
        guard isInstalled else { return .missing }
        guard let receipt = receipt(for: spec.component) else { return .legacy }
        return receipt.version == spec.targetVersion ? .current : .updateAvailable
    }

    private func receipts() -> [String: ManagedRuntimeComponentReceipt] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ManagedRuntimeComponentReceipt].self, from: data)) ?? [:]
    }
}

enum ManagedRuntimeArtifactVerifier {
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
