import Foundation

public final class RecordingCacheStore {
    public let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public convenience init(container: SharedContainer, fileManager: FileManager = .default) throws {
        try self.init(directoryURL: container.url(for: .recordingCache), fileManager: fileManager)
    }

    public func makeTemporaryFileURL(now: Date = Date(), id: UUID = UUID()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd-HHmmss"
        let name = "\(formatter.string(from: now)) [GetOudioRec. \(id.uuidString.prefix(8))].wav.part"
        return directoryURL.appendingPathComponent(name)
    }

    public func completedURL(for temporaryURL: URL) -> URL {
        guard temporaryURL.lastPathComponent.hasSuffix(".part") else { return temporaryURL }
        return temporaryURL.deletingPathExtension()
    }

    @discardableResult
    public func replaceCompletedFile(at originalURL: URL, with stagingURL: URL) throws -> URL {
        let backupName = ".\(originalURL.lastPathComponent).\(UUID().uuidString).raw-backup"
        let replacedURL = try fileManager.replaceItemAt(
            originalURL,
            withItemAt: stagingURL,
            backupItemName: backupName,
            options: [.usingNewMetadataOnly]
        ) ?? originalURL
        let backupURL = originalURL.deletingLastPathComponent().appendingPathComponent(backupName)
        try? fileManager.removeItem(at: backupURL)
        return replacedURL
    }

    @discardableResult
    public func enforceLimit(_ limitBytes: Int64, protecting protectedURL: URL? = nil) -> [URL] {
        guard limitBytes > 0 else { return [] }
        let entries = completedEntries().filter { $0.url != protectedURL }
        var total = completedEntries().reduce(Int64(0)) { $0 + $1.size }
        var removed: [URL] = []

        for entry in entries.sorted(by: { $0.date < $1.date }) where total > limitBytes {
            do {
                try fileManager.removeItem(at: entry.url)
                total -= entry.size
                removed.append(entry.url)
            } catch {
                continue
            }
        }
        return removed
    }

    @discardableResult
    public func clearCompletedFiles() -> [URL] {
        var removed: [URL] = []
        for entry in completedEntries() {
            guard (try? fileManager.removeItem(at: entry.url)) != nil else { continue }
            removed.append(entry.url)
        }
        return removed
    }

    public func completedSize() -> Int64 {
        completedEntries().reduce(0) { $0 + $1.size }
    }

    private func completedEntries() -> [(url: URL, size: Int64, date: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        return ((try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: Array(keys))) ?? [])
            .filter { $0.pathExtension == "wav" }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
    }
}

public final class RecordingCacheDirectoryAccess {
    public let store: RecordingCacheStore
    public let fallbackMessage: String?
    private let securityScopedParentDirectory: URL?

    public init(
        container: SharedContainer,
        settings: SettingsStore,
        fileManager: FileManager = .default
    ) throws {
        guard settings.recordingUsesCustomCacheDirectory,
              let bookmarkData = settings.recordingCustomCacheBookmarkData else {
            store = try RecordingCacheStore(container: container, fileManager: fileManager)
            fallbackMessage = nil
            securityScopedParentDirectory = nil
            return
        }

        do {
            var isStale = false
            let parentDirectory = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard parentDirectory.startAccessingSecurityScopedResource() else {
                throw RecordingCacheDirectoryAccessError.accessDenied(parentDirectory)
            }
            do {
                store = try RecordingCacheStore(
                    directoryURL: parentDirectory,
                    fileManager: fileManager
                )
                fallbackMessage = nil
                securityScopedParentDirectory = parentDirectory
            } catch {
                parentDirectory.stopAccessingSecurityScopedResource()
                throw error
            }
        } catch {
            store = try RecordingCacheStore(container: container, fileManager: fileManager)
            fallbackMessage = "指定缓存目录不可用，已使用默认缓存目录：\(error.localizedDescription)"
            securityScopedParentDirectory = nil
        }
    }

    deinit {
        securityScopedParentDirectory?.stopAccessingSecurityScopedResource()
    }
}

public enum RecordingCacheDirectoryAccessError: LocalizedError {
    case accessDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let directory):
            return "无法访问缓存位置 \(directory.path)"
        }
    }
}
