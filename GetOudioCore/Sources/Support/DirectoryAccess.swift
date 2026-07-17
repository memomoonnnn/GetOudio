import Foundation

public enum DirectoryAccessError: LocalizedError {
    case bookmarkMissing(String)
    case bookmarkUnavailable(String)
    case directoryUnavailable(String)
    case directoryNotWritable(String)

    public var errorDescription: String? {
        switch self {
        case .bookmarkMissing(let path):
            return "尚未授权访问目录：\(path)"
        case .bookmarkUnavailable(let path):
            return "无法恢复目录访问授权：\(path)"
        case .directoryUnavailable(let path):
            return "无法访问输出目录：\(path)"
        case .directoryNotWritable(let path):
            return "输出目录不可写：\(path)"
        }
    }
}

public final class SecurityScopedDirectoryAccess {
    public let directoryURL: URL
    private var isAccessing: Bool

    fileprivate init(directoryURL: URL, isAccessing: Bool) {
        self.directoryURL = directoryURL
        self.isAccessing = isAccessing
    }

    public func stopAccessing() {
        guard isAccessing else { return }
        directoryURL.stopAccessingSecurityScopedResource()
        isAccessing = false
    }

    deinit {
        stopAccessing()
    }
}

public enum DirectoryAccess {
    public static func bookmarkData(for directoryURL: URL) throws -> Data {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DirectoryAccessError.directoryUnavailable(directoryURL.path)
        }

        return try directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func beginAccess(bookmarkData: Data, expectedPath: String) throws -> SecurityScopedDirectoryAccess {
        var isStale = false
        let directoryURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale, directoryURL.startAccessingSecurityScopedResource() else {
            throw DirectoryAccessError.bookmarkUnavailable(expectedPath)
        }
        return SecurityScopedDirectoryAccess(directoryURL: directoryURL, isAccessing: true)
    }

    public static func ensureWritableDirectory(_ directoryURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DirectoryAccessError.directoryUnavailable(directoryURL.path)
        }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        } catch {
            throw DirectoryAccessError.directoryUnavailable(directoryURL.path)
        }
        guard fileManager.isWritableFile(atPath: directoryURL.path) else {
            throw DirectoryAccessError.directoryNotWritable(directoryURL.path)
        }
    }
}
