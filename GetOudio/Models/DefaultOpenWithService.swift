import AppKit
import Foundation
import GetOudioCore
import UniformTypeIdentifiers

struct DefaultOpenWithFormat: Identifiable, Equatable {
    let fileExtension: String
    let contentType: UTType

    var id: String { fileExtension }
    var displayName: String { ".\(fileExtension)" }
}

struct DefaultOpenWithFormatGroup: Identifiable, Equatable {
    let formats: [DefaultOpenWithFormat]

    var id: String {
        formats.map(\.fileExtension).joined(separator: "+")
    }

    var displayName: String {
        formats.map(\.displayName).joined(separator: " / ")
    }
}

struct DefaultOpenWithFormatStatus: Identifiable, Equatable {
    let group: DefaultOpenWithFormatGroup
    let isGetOudioDefault: Bool

    var id: String { group.id }
}

struct DefaultAudioPlayerOption: Identifiable, Equatable {
    let url: URL
    let displayName: String

    var id: String { url.path }
}

struct DefaultOpenWithStatus: Equatable {
    let configuredCount: Int
    let totalCount: Int

    var isFullyConfigured: Bool {
        totalCount > 0 && configuredCount == totalCount
    }
}

@MainActor
final class DefaultOpenWithService {
    private let workspace: NSWorkspace
    private let bundleIdentifier: String
    private let applicationURL: URL

    init(
        workspace: NSWorkspace = .shared,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.shengjiacheng.GetOudio",
        applicationURL: URL = Bundle.main.bundleURL
    ) {
        self.workspace = workspace
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
    }

    var supportedAudioGroups: [DefaultOpenWithFormatGroup] {
        [
            ["m4a", "aac"],
            ["mp3"],
            ["alac"],
            ["flac"],
            ["wav"],
            ["aiff", "aif"],
            ["ogg"],
            ["opus"],
            ["caf"]
        ].compactMap { fileExtensions in
            let allowedExtensions = Set(FileCategory.defaultOpenWithAudioExtensions)
            let formats = fileExtensions
                .filter { allowedExtensions.contains($0) }
                .compactMap { format(forAudioExtension: $0) }
            return formats.isEmpty ? nil : DefaultOpenWithFormatGroup(formats: formats)
        }
    }

    var supportedAudioGroupLabels: [String] {
        supportedAudioGroups.map(\.displayName)
    }

    func defaultAudioPlayerOptions() -> [DefaultAudioPlayerOption] {
        guard let wavType = UTType(filenameExtension: "wav", conformingTo: .audio) else {
            return []
        }

        let uniqueURLs = Dictionary(grouping: workspace.urlsForApplications(toOpen: wavType)) { url in
            Bundle(url: url)?.bundleIdentifier ?? url.path
        }
        .compactMap { _, urls in urls.first }
        .filter { Bundle(url: $0)?.bundleIdentifier != bundleIdentifier }

        return uniqueURLs
            .map {
                DefaultAudioPlayerOption(
                    url: $0,
                    displayName: $0.deletingPathExtension().lastPathComponent
                )
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    func audioStatuses() -> [DefaultOpenWithFormatStatus] {
        supportedAudioGroups.map { status(for: $0) }
    }

    func audioSummaryStatus() -> DefaultOpenWithStatus {
        let statuses = audioStatuses()
        return DefaultOpenWithStatus(
            configuredCount: statuses.filter(\.isGetOudioDefault).count,
            totalCount: statuses.count
        )
    }

    func ncmStatus() -> DefaultOpenWithStatus {
        let isConfigured = isGetOudioDefault(for: ncmFormat.contentType)
        return DefaultOpenWithStatus(configuredCount: isConfigured ? 1 : 0, totalCount: 1)
    }

    func setGetOudioDefault(for group: DefaultOpenWithFormatGroup) async throws {
        for format in group.formats {
            try await setDefaultApplication(applicationURL, for: format.contentType)
        }
    }

    func setFallbackPlayerDefault(for group: DefaultOpenWithFormatGroup, playerURL: URL) async throws {
        for format in group.formats {
            try await setDefaultApplication(playerURL, for: format.contentType)
        }
    }

    func setNCMDefault() async throws -> DefaultOpenWithStatus {
        try await setDefaultApplication(applicationURL, for: ncmFormat.contentType)
        return ncmStatus()
    }

    private var ncmFormat: DefaultOpenWithFormat {
        DefaultOpenWithFormat(
            fileExtension: "ncm",
            contentType: UTType(exportedAs: "com.shengjiacheng.getoudio.ncm", conformingTo: .data)
        )
    }

    private func format(forAudioExtension fileExtension: String) -> DefaultOpenWithFormat? {
        guard let contentType = UTType(filenameExtension: fileExtension, conformingTo: .audio) else {
            return nil
        }

        return DefaultOpenWithFormat(fileExtension: fileExtension, contentType: contentType)
    }

    private func status(for group: DefaultOpenWithFormatGroup) -> DefaultOpenWithFormatStatus {
        let defaultBundleIdentifiers = group.formats.map { format in
            let defaultApplicationURL = workspace.urlForApplication(toOpen: format.contentType)
            return defaultApplicationURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        }

        return DefaultOpenWithFormatStatus(
            group: group,
            isGetOudioDefault: defaultBundleIdentifiers.allSatisfy { $0 == bundleIdentifier }
        )
    }

    private func isGetOudioDefault(for contentType: UTType) -> Bool {
        guard let defaultApplicationURL = workspace.urlForApplication(toOpen: contentType),
              let defaultBundleIdentifier = Bundle(url: defaultApplicationURL)?.bundleIdentifier
        else {
            return false
        }

        return defaultBundleIdentifier == bundleIdentifier
    }

    private func setDefaultApplication(_ applicationURL: URL, for contentType: UTType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.setDefaultApplication(at: applicationURL, toOpen: contentType) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
