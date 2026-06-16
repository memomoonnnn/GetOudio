import XCTest
@testable import GetOudioCore

final class GetOudioCoreTests: XCTestCase {
    func testAACPresetBuildsExpectedOutputAndArguments() throws {
        let input = URL(fileURLWithPath: "/tmp/song.flac")
        let preset = ConversionPreset.aac320
        let output = preset.outputURL(for: input)
        let arguments = preset.ffmpegArguments(inputURL: input, outputURL: output)

        XCTAssertEqual(output.path, "/tmp/song [AAC 320Kbps].m4a")
        XCTAssertTrue(arguments.contains("aac"))
        XCTAssertTrue(arguments.contains("320k"))
        let mapIndex = try XCTUnwrap(arguments.firstIndex(of: "-map"))
        XCTAssertEqual(arguments[mapIndex + 1], "0:a:0")
        XCTAssertTrue(arguments.contains("-map_metadata"))
        XCTAssertTrue(arguments.contains("0:g"))
        XCTAssertTrue(arguments.contains("-movflags"))
        XCTAssertEqual(arguments.suffix(1), ["/tmp/song [AAC 320Kbps].m4a"])
    }

    func testPresetOutputDoesNotCollideWithSameExtensionInput() {
        let input = URL(fileURLWithPath: "/tmp/song.m4a")

        XCTAssertEqual(ConversionPreset.aac128.outputURL(for: input).path, "/tmp/song [AAC 128Kbps].m4a")
        XCTAssertNotEqual(ConversionPreset.aac128.outputURL(for: input), input)
    }

    func testPresetCatalogCoversPlannedFormats() {
        let extensions = Set(ConversionPreset.allCases.map(\.outputExtension))

        XCTAssertEqual(ConversionPreset.allCases.count, 15)
        XCTAssertTrue(extensions.isSuperset(of: ["m4a", "mp3", "flac", "wav"]))
    }

    func testPresetOriginalTitlesUseFinderFriendlySuffix() {
        XCTAssertEqual(ConversionPreset.alacSource.title, "ALAC Original")
        XCTAssertEqual(ConversionPreset.flacSource.title, "FLAC Original")
        XCTAssertEqual(ConversionPreset.pcmSource.title, "PCM Original")
    }

    func testPresetGroupsCoverAllPresets() {
        let groupedPresets = ConversionPresetGroup.allCases.flatMap(\.presets)

        XCTAssertEqual(Set(groupedPresets), Set(ConversionPreset.allCases))
        XCTAssertEqual(groupedPresets.count, ConversionPreset.allCases.count)
        XCTAssertEqual(ConversionPresetGroup.allCases.map(\.displayName), ["AAC", "MP3", "ALAC", "FLAC", "PCM"])
    }

    func testFileCategoryClassification() {
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.ncm")), .ncm)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.mp3")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.mov")), .video)
        XCTAssertEqual(FileCategory.classify(URL(string: "https://music.apple.com/us/album/example/123")!), .appleMusic)
    }

    func testJobQueueRoundTripsAndDrainsJobs() throws {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queued-jobs.json")
        let queue = try JobQueue(fileURL: queueURL)
        let job = JobRequest(
            fileURL: URL(fileURLWithPath: "/tmp/song.wav"),
            category: .audio,
            operation: .transcode(.mp3320),
            source: .finderSync
        )

        try queue.enqueue([job])
        XCTAssertEqual(try queue.read(), [job])
        XCTAssertEqual(try queue.drain(), [job])
        XCTAssertEqual(try queue.read(), [])
    }

    func testSettingsStorePersistsPresetsAndFinderDirectories() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.enabledPresets = [.aac128, .flacSource]
        store.finderDirectoryURLs = [
            URL(fileURLWithPath: "/tmp/Music", isDirectory: true),
            URL(fileURLWithPath: "/tmp/Desktop", isDirectory: true)
        ]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.enabledPresets, [.aac128, .flacSource])
        XCTAssertEqual(reloaded.finderDirectoryURLs.map(\.path).sorted(), ["/tmp/Desktop", "/tmp/Music"])
    }

    func testSettingsStoreDoesNotPersistEmptyPresetSelection() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.enabledPresets = []

        XCTAssertEqual(store.enabledPresets, ConversionPreset.defaultEnabled)
    }

    func testSettingsStoreResolvesFinderDirectoryAliases() throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let realDirectory = root.appendingPathComponent("RealDesktop", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasDirectory, withDestinationURL: realDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SettingsStore(defaults: defaults)
        store.finderDirectoryURLs = [aliasDirectory]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.finderDirectoryURLs.map(\.path), [realDirectory.path])
    }

    func testOutputSettingsPersistNCMAndAppleMusicChoices() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.ncmOutputMode = "customDirectory"
        store.ncmCustomOutputURL = URL(fileURLWithPath: "/tmp/NCM", isDirectory: true)
        store.appleMusicOutputURL = URL(fileURLWithPath: "/tmp/AppleMusic", isDirectory: true)
        store.appleMusicDownloadFormat = .atmos

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.ncmOutputMode, "customDirectory")
        XCTAssertEqual(reloaded.ncmCustomOutputURL?.path, "/tmp/NCM")
        XCTAssertEqual(reloaded.appleMusicOutputURL.path, "/tmp/AppleMusic")
        XCTAssertEqual(reloaded.appleMusicDownloadFormat, .atmos)
    }

    func testAppleMusicDownloadFormatArguments() {
        XCTAssertEqual(AppleMusicDownloadFormat.alac.downloaderArguments, [])
        XCTAssertEqual(AppleMusicDownloadFormat.aac.downloaderArguments, ["--aac"])
        XCTAssertEqual(AppleMusicDownloadFormat.atmos.downloaderArguments, ["--atmos"])
    }

    func testAppleMusicWrapperIsManagedDockerImage() {
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.imageName, "ghcr.io/itouakirai/wrapper:x86")
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.platform, "linux/amd64")
        XCTAssertFalse(BundledComponent.allCases.map(\.rawValue).contains("appleMusicWrapper"))
    }

    func testAppleMusicUsesDockerCLIWithColimaInsteadOfDockerDesktop() {
        XCTAssertEqual(RuntimeDependency.allCases.first, .homebrew)
        XCTAssertEqual(RuntimeDependency.homebrew.displayName, "Homebrew")
        XCTAssertEqual(RuntimeDependency.homebrew.executableName, "brew")
        XCTAssertTrue(RuntimeDependency.homebrew.installCommand.contains("raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"))
        XCTAssertEqual(RuntimeDependency.docker.displayName, "Docker CLI")
        XCTAssertEqual(RuntimeDependency.ffmpeg.installCommand, "brew install ffmpeg")
        XCTAssertEqual(RuntimeDependency.docker.installCommand, "brew install docker")
        XCTAssertEqual(RuntimeDependency.colima.installCommand, "brew install colima")
        XCTAssertEqual(RuntimeDependency.gpac.installCommand, "brew install gpac")
        XCTAssertEqual(RuntimeDependency.go.installCommand, "brew install go")
        XCTAssertTrue(RuntimeDependency.allCases.contains(.colima))
    }

    func testBundledComponentManagerResolvesExecutableInsideResourceRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = root.appendingPathComponent(BundledComponent.ncmdump.expectedRelativePath)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let manager = BundledComponentManager(resourceRoot: root)
        let status = manager.check(.ncmdump)

        XCTAssertTrue(status.isEmbedded)
        XCTAssertEqual(try manager.executableURL(for: .ncmdump), executable)
    }
}
