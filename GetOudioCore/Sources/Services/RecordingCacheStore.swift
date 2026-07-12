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
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Get Oudio Recording \(formatter.string(from: now)) \(id.uuidString.prefix(8)).wav.part"
        return directoryURL.appendingPathComponent(name)
    }

    public func completedURL(for temporaryURL: URL) -> URL {
        guard temporaryURL.lastPathComponent.hasSuffix(".part") else { return temporaryURL }
        return temporaryURL.deletingPathExtension()
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
