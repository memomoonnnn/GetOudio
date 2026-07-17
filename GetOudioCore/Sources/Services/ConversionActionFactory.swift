import Foundation

public struct ConversionActionFactory {
    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    public init(container: SharedContainer) {
        self.init(settingsStore: SettingsStore(container: container))
    }

    public func enabledPresets() -> [ConversionPreset] {
        let presets = ConversionPreset.allCases.filter { settingsStore.enabledPresets.contains($0) }
        return presets.isEmpty ? ConversionPreset.allCases : presets
    }

    public func audioTranscodeJobs(
        for urls: [URL],
        preset: ConversionPreset,
        source: JobEntrySource
    ) -> [JobRequest] {
        urls
            .filter { FileCategory.classify($0) == .audio }
            .map {
                let directoryURL = $0.deletingLastPathComponent()
                return JobRequest(
                    fileURL: $0,
                    fileBookmarkData: JobRequest.securityScopedBookmarkData(for: $0),
                    directoryBookmarkData: settingsStore.directoryBookmarkData(for: directoryURL)
                        ?? JobRequest.securityScopedBookmarkData(for: directoryURL),
                    category: .audio,
                    operation: .transcode(preset),
                    source: source
                )
            }
    }
}
