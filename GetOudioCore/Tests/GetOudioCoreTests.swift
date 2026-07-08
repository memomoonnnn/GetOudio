import CFNetwork
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

        XCTAssertEqual(ConversionPreset.allCases.count, 24)
        XCTAssertTrue(extensions.isSuperset(of: ["m4a", "mp3", "flac", "wav", "aiff", "ogg", "opus"]))
    }

    func testPresetOriginalTitlesUseFinderFriendlySuffix() {
        XCTAssertEqual(ConversionPreset.alacSource.title, "Original")
        XCTAssertEqual(ConversionPreset.flacSource.title, "Original")
        XCTAssertEqual(ConversionPreset.pcmSource.title, "Original")
        XCTAssertEqual(ConversionPreset.pcmAiffSource.title, "Original")
        XCTAssertEqual(ConversionPreset.alacSource.finderMenuTitle, "ALAC Original")
        XCTAssertEqual(ConversionPreset.flacSource.finderMenuTitle, "FLAC Original")
        XCTAssertEqual(ConversionPreset.pcmSource.finderMenuTitle, "PCM WAV Original")
        XCTAssertEqual(ConversionPreset.pcmAiffSource.finderMenuTitle, "PCM AIFF Original")
        XCTAssertEqual(ConversionPreset.vorbisQ3.finderMenuTitle, "Vorbis q3")
        XCTAssertEqual(ConversionPreset.opus64KbpsPerChannel.finderMenuTitle, "Opus 64kbps Per-Ch")
    }

    func testSixteenBitPresetsUse44100HzNamingAndArguments() throws {
        let input = URL(fileURLWithPath: "/tmp/song.aiff")
        let cases: [(ConversionPreset, String, String, String, String)] = [
            (.alac16Bit44_1k, "16bit 44.1kHz", "ALAC 16bit 44.1kHz", "m4a", "alac"),
            (.flac16Bit44_1k, "16bit 44.1kHz", "FLAC 16bit 44.1kHz", "flac", "flac"),
            (.pcm16Bit44_1k, "16bit 44.1kHz", "PCM WAV 16bit 44.1kHz", "wav", "pcm_s16le"),
            (.pcmAiff16Bit44_1k, "16bit 44.1kHz", "PCM AIFF 16bit 44.1kHz", "aiff", "pcm_s16be")
        ]

        for (preset, expectedTitle, expectedOutputTitle, expectedExtension, expectedCodec) in cases {
            let output = preset.outputURL(for: input)
            let arguments = preset.ffmpegArguments(inputURL: input, outputURL: output)

            XCTAssertEqual(preset.title, expectedTitle)
            XCTAssertEqual(preset.outputNameSuffix, expectedOutputTitle)
            XCTAssertEqual(output.path, "/tmp/song [\(expectedOutputTitle)].\(expectedExtension)")
            XCTAssertTrue(arguments.contains(expectedCodec))
            let sampleRateIndex = try XCTUnwrap(arguments.firstIndex(of: "-ar"))
            XCTAssertEqual(arguments[sampleRateIndex + 1], "44100")
            XCTAssertFalse(arguments.contains("48000"))
        }
    }

    func testPresetCatalogDoesNotExposeLegacy16Bit48kNames() {
        let rawValues = ConversionPreset.allCases.map(\.rawValue)
        let labels = ConversionPreset.allCases.flatMap { [$0.title, $0.outputNameSuffix, $0.finderMenuTitle] }

        XCTAssertFalse(rawValues.contains("alac16Bit48k"))
        XCTAssertFalse(rawValues.contains("flac16Bit48k"))
        XCTAssertFalse(rawValues.contains("pcm16Bit48k"))
        XCTAssertTrue(rawValues.contains("alac16Bit44_1k"))
        XCTAssertTrue(rawValues.contains("flac16Bit44_1k"))
        XCTAssertTrue(rawValues.contains("pcm16Bit44_1k"))
        XCTAssertTrue(labels.contains { $0.contains("PCM WAV") })
        XCTAssertTrue(labels.contains { $0.contains("PCM AIFF") })
        XCTAssertFalse(labels.contains { $0.contains("16bit 48kHz") || $0.contains("16bit 48KHz") })
    }

    func testPCMAiffPresetsUseAiffContainerCompatibleBigEndianCodecs() throws {
        let input = URL(fileURLWithPath: "/tmp/song.wav")
        let cases: [(ConversionPreset, String, String?)] = [
            (.pcmAiff24Bit48k, "pcm_s24be", "48000"),
            (.pcmAiff16Bit44_1k, "pcm_s16be", "44100"),
            (.pcmAiffSource, "pcm_s16be", nil)
        ]

        for (preset, expectedCodec, expectedSampleRate) in cases {
            let output = preset.outputURL(for: input)
            let arguments = preset.ffmpegArguments(inputURL: input, outputURL: output)

            XCTAssertEqual(output.pathExtension, "aiff")
            XCTAssertTrue(arguments.contains(expectedCodec))
            let muxerIndex = try XCTUnwrap(arguments.firstIndex(of: "-f"))
            XCTAssertEqual(arguments[muxerIndex + 1], "aiff")
            XCTAssertFalse(arguments.contains("pcm_s16le"))
            XCTAssertFalse(arguments.contains("pcm_s24le"))
            if let expectedSampleRate = expectedSampleRate {
                let sampleRateIndex = try XCTUnwrap(arguments.firstIndex(of: "-ar"))
                XCTAssertEqual(arguments[sampleRateIndex + 1], expectedSampleRate)
            } else {
                XCTAssertFalse(arguments.contains("-ar"))
            }
        }
    }

    func testVorbisPresetsUseOggContainerAndQualityScale() throws {
        let input = URL(fileURLWithPath: "/tmp/song.wav")
        let cases: [(ConversionPreset, String)] = [
            (.vorbisQ3, "3"),
            (.vorbisQ6, "6"),
            (.vorbisQ10, "10")
        ]

        for (preset, expectedQuality) in cases {
            let output = preset.outputURL(for: input)
            let arguments = preset.ffmpegArguments(inputURL: input, outputURL: output)

            XCTAssertEqual(output.pathExtension, "ogg")
            XCTAssertTrue(arguments.contains("libvorbis"))
            let qualityIndex = try XCTUnwrap(arguments.firstIndex(of: "-q:a"))
            XCTAssertEqual(arguments[qualityIndex + 1], expectedQuality)
            let muxerIndex = try XCTUnwrap(arguments.firstIndex(of: "-f"))
            XCTAssertEqual(arguments[muxerIndex + 1], "ogg")
            XCTAssertTrue(arguments.contains("-map_metadata"))
        }
    }

    func testOpusPresetsUseOggContainerVBRAndPerChannelBitrate() throws {
        let input = URL(fileURLWithPath: "/tmp/song.wav")
        let cases: [(ConversionPreset, String, String)] = [
            (.opus64KbpsPerChannel, "128k", "Opus 64kbps Per-Ch"),
            (.opus96KbpsPerChannel, "192k", "Opus 96kbps Per-Ch"),
            (.opus128KbpsPerChannel, "256k", "Opus 128kbps Per-Ch")
        ]

        for (preset, expectedStereoBitrate, expectedOutputTitle) in cases {
            let output = preset.outputURL(for: input)
            let arguments = preset.ffmpegArguments(inputURL: input, outputURL: output, inputAudioChannelCount: 2)

            XCTAssertEqual(output.path, "/tmp/song [\(expectedOutputTitle)].opus")
            XCTAssertEqual(output.pathExtension, "opus")
            XCTAssertTrue(arguments.contains("libopus"))
            let bitrateIndex = try XCTUnwrap(arguments.firstIndex(of: "-b:a"))
            XCTAssertEqual(arguments[bitrateIndex + 1], expectedStereoBitrate)
            let vbrIndex = try XCTUnwrap(arguments.firstIndex(of: "-vbr"))
            XCTAssertEqual(arguments[vbrIndex + 1], "on")
            let muxerIndex = try XCTUnwrap(arguments.firstIndex(of: "-f"))
            XCTAssertEqual(arguments[muxerIndex + 1], "ogg")
            XCTAssertTrue(arguments.contains("-map_metadata"))
        }

        let multichannelArguments = ConversionPreset.opus64KbpsPerChannel.ffmpegArguments(
            inputURL: input,
            outputURL: ConversionPreset.opus64KbpsPerChannel.outputURL(for: input),
            inputAudioChannelCount: 6
        )
        let bitrateIndex = try XCTUnwrap(multichannelArguments.firstIndex(of: "-b:a"))
        XCTAssertEqual(multichannelArguments[bitrateIndex + 1], "384k")
    }

    func testAudioConversionServiceParsesInputAudioChannelCount() {
        XCTAssertEqual(
            AudioConversionService.inputAudioChannelCount(from: "Stream #0:0: Audio: flac, 44100 Hz, stereo, s16"),
            2
        )
        XCTAssertEqual(
            AudioConversionService.inputAudioChannelCount(from: "Stream #0:0: Audio: opus, 48000 Hz, mono, fltp"),
            1
        )
        XCTAssertEqual(
            AudioConversionService.inputAudioChannelCount(from: "Stream #0:0: Audio: ac3, 48000 Hz, 5.1(side), fltp"),
            6
        )
        XCTAssertEqual(
            AudioConversionService.inputAudioChannelCount(from: "Stream #0:0: Audio: pcm_s24le, 96000 Hz, 8 channels, s32"),
            8
        )
    }

    func testPresetGroupsCoverAllPresets() {
        let groupedPresets = ConversionPresetGroup.allCases.flatMap(\.presets)

        XCTAssertEqual(Set(groupedPresets), Set(ConversionPreset.allCases))
        XCTAssertEqual(groupedPresets.count, ConversionPreset.allCases.count)
        XCTAssertEqual(ConversionPresetGroup.allCases.map(\.displayName), ["AAC", "MP3", "Vorbis", "Opus", "ALAC", "FLAC", "PCM WAV", "PCM AIFF"])
        XCTAssertLessThan(
            try XCTUnwrap(ConversionPreset.allCases.firstIndex(of: .vorbisQ3)),
            try XCTUnwrap(ConversionPreset.allCases.firstIndex(of: .alac24Bit48k))
        )
        XCTAssertLessThan(
            try XCTUnwrap(ConversionPreset.allCases.firstIndex(of: .opus64KbpsPerChannel)),
            try XCTUnwrap(ConversionPreset.allCases.firstIndex(of: .alac24Bit48k))
        )
    }

    func testFileCategoryClassification() {
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.ncm")), .ncm)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.mp3")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.ogg")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.caf")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.opus")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.wma")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.mpga")), .audio)
        XCTAssertEqual(FileCategory.classify(URL(fileURLWithPath: "/tmp/demo.mov")), .video)
        XCTAssertEqual(FileCategory.classify(URL(string: "https://music.apple.com/us/album/example/123")!), .appleMusic)
    }

    func testAudioConversionInputsStayBroaderThanDefaultOpenWithFormats() {
        XCTAssertTrue(FileCategory.supportedAudioExtensions.contains("mpga"))
        XCTAssertTrue(FileCategory.supportedAudioExtensions.contains("opus"))
        XCTAssertTrue(FileCategory.supportedAudioExtensions.contains("wma"))
        XCTAssertEqual(FileCategory.defaultOpenWithAudioExtensions, ["m4a", "aac", "mp3", "alac", "flac", "wav", "aiff", "aif", "ogg", "opus", "caf"])
    }

    func testConversionActionFactoryUsesEnabledPresetsAndDefaultFallback() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.enabledPresets = [.aac128, .flacSource]
        let factory = ConversionActionFactory(settingsStore: store)

        XCTAssertEqual(factory.enabledPresets(), [.aac128, .flacSource])

        store.enabledPresets = []
        XCTAssertEqual(Set(factory.enabledPresets()), ConversionPreset.defaultEnabled)
    }

    func testConversionActionFactoryBuildsAudioTranscodeJobs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = root.appendingPathComponent("song.mp3")
        let videoURL = root.appendingPathComponent("clip.mov")
        try Data("audio".utf8).write(to: audioURL)
        try Data("video".utf8).write(to: videoURL)

        let jobs = ConversionActionFactory().audioTranscodeJobs(
            for: [audioURL, videoURL],
            preset: .aac320,
            source: .openWith
        )

        XCTAssertEqual(jobs.count, 1)
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.fileURL, audioURL)
        XCTAssertEqual(job.category, .audio)
        XCTAssertEqual(job.operation, .transcode(.aac320))
        XCTAssertEqual(job.source, .openWith)
        XCTAssertNotNil(job.fileBookmarkData)
        XCTAssertNotNil(job.directoryBookmarkData)
    }

    func testJobQueueRoundTripsAndDrainsJobs() throws {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queued-jobs.json")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

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

    func testJobQueueClaimsAndAcknowledgesJobs() throws {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queued-jobs.json")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let queue = try JobQueue(fileURL: queueURL)
        let job = JobRequest(
            fileURL: URL(fileURLWithPath: "/tmp/song.wav"),
            category: .audio,
            operation: .transcode(.mp3320),
            source: .finderSync
        )

        try queue.enqueue([job])
        let claim = try XCTUnwrap(try queue.claimPending())

        XCTAssertEqual(claim.jobs, [job])
        XCTAssertEqual(try queue.read(), [])
        XCTAssertNil(try queue.claimPending())

        try queue.acknowledge(claim)
        XCTAssertNil(try queue.claimPending())
    }

    func testJobQueueRequeuesStaleClaim() throws {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queued-jobs.json")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let queue = try JobQueue(fileURL: queueURL)
        let job = JobRequest(
            fileURL: URL(fileURLWithPath: "/tmp/song.wav"),
            category: .audio,
            operation: .transcode(.mp3320),
            source: .finderSync
        )

        try queue.enqueue([job])
        XCTAssertEqual(try XCTUnwrap(try queue.claimPending()).jobs, [job])

        let reclaimed = try XCTUnwrap(try queue.claimPending(staleClaimMaxAge: -1))
        XCTAssertEqual(reclaimed.jobs, [job])
        try queue.acknowledge(reclaimed)
        XCTAssertNil(try queue.claimPending())
    }

    func testJobIntakeEnqueuesJobsAndMarksLaunchSource() throws {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queued-jobs.json")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let queue = try JobQueue(fileURL: queueURL)
        let markerStore = LaunchMarkerStore(defaults: defaults)
        let intake = JobIntake(queue: queue, markerStore: markerStore)
        let job = JobRequest(
            fileURL: URL(fileURLWithPath: "/tmp/song.wav"),
            category: .audio,
            operation: .transcode(.mp3320),
            source: .openWith
        )

        try intake.enqueue([job], launchSource: .openWithAudio)

        XCTAssertEqual(try queue.read(), [job])
        XCTAssertEqual(markerStore.activeSource(), .openWithAudio)
    }

    func testNotificationEventQueueClaimsAndAcknowledgesEvents() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let queue = try NotificationEventQueue(rootURL: rootURL)
        let job = JobRequest(
            fileURL: URL(fileURLWithPath: "/tmp/song.wav"),
            category: .audio,
            operation: .transcode(.mp3320),
            source: .finderSync
        )
        let summary = ConversionSummary(successCount: 1, failureCount: 0, messages: [])

        try queue.enqueueConversionFinished(summary: summary, jobs: [job])
        let claimed = try queue.claimPending()

        XCTAssertEqual(claimed.map(\.event.summary), [summary])
        XCTAssertEqual(claimed.first?.event.jobs, [job])
        XCTAssertTrue(try queue.claimPending().isEmpty)

        if let firstClaim = claimed.first {
            queue.acknowledge(firstClaim)
        }
        XCTAssertTrue(try queue.claimPending().isEmpty)
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

    func testSharedContainerDirectoryFallbackIsExplicit() throws {
        let fallbackRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fallbackRoot) }

        let resolution = try SharedContainer.resolvedDirectory(
            containerURL: nil,
            groupIdentifier: "group.test",
            fallbackBaseURL: fallbackRoot
        )

        XCTAssertEqual(resolution.url, fallbackRoot.appendingPathComponent("Get Oudio", isDirectory: true))
        XCTAssertEqual(resolution.accessMode, .diagnosticFallback("Application Support"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolution.url.path))
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
        store.isAppleMusicDownloadEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.ncmOutputMode, "customDirectory")
        XCTAssertEqual(reloaded.ncmCustomOutputURL?.path, "/tmp/NCM")
        XCTAssertEqual(reloaded.appleMusicOutputURL.path, "/tmp/AppleMusic")
        XCTAssertEqual(reloaded.appleMusicDownloadFormat, .atmos)
        XCTAssertTrue(reloaded.isAppleMusicDownloadEnabled)
    }

    func testAppleMusicDownloadIsDisabledByDefault() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.isAppleMusicDownloadEnabled)
    }

    func testAppleMusicSystemProxyIsDisabledByDefaultAndPersists() {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.appleMusicUseSystemProxy)

        store.appleMusicUseSystemProxy = true

        XCTAssertTrue(SettingsStore(defaults: defaults).appleMusicUseSystemProxy)
    }

    func testAppleMusicRuntimeDefaultRootIsAppGroupOrApplicationSupport() {
        let path = AppleMusicRuntimeManager.defaultRootURL.path

        XCTAssertTrue(path.contains("/Library/Group Containers/\(AppConstants.appGroupIdentifier)/AppleMusicRuntime"))
        XCTAssertFalse(path.hasSuffix("/Get Oudio"))
    }

    func testAppleMusicDownloadFormatArguments() {
        XCTAssertEqual(AppleMusicDownloadFormat.alac.downloaderArguments, [])
        XCTAssertEqual(AppleMusicDownloadFormat.aac.downloaderArguments, ["--aac", "--aac-type", "aac"])
        XCTAssertEqual(AppleMusicDownloadFormat.atmos.downloaderArguments, ["--atmos"])
    }

    func testAppleMusicDownloaderArgumentsUseSongFlagForAlbumURLWithSongID() {
        let job = JobRequest(
            fileURL: URL(string: "https://music.apple.com/jp/album/tell-me/1756723979?i=1756724104")!,
            category: .appleMusic,
            operation: .appleMusicDownload(.aac),
            source: .shareExtension
        )

        let arguments = AppleMusicDownloadService.downloaderArguments(for: job, format: .aac)

        XCTAssertEqual(arguments, ["--aac", "--aac-type", "aac", "--song", job.fileURL.absoluteString])
    }

    func testAppleMusicDownloaderArgumentsDoNotUseSongFlagForAlbumURL() {
        let job = JobRequest(
            fileURL: URL(string: "https://music.apple.com/jp/album/tell-me/1756723979")!,
            category: .appleMusic,
            operation: .appleMusicDownload(.alac),
            source: .shareExtension
        )

        let arguments = AppleMusicDownloadService.downloaderArguments(for: job, format: .alac)

        XCTAssertEqual(arguments, [job.fileURL.absoluteString])
    }

    func testAppleMusicShareURLParserAcceptsBroadAppleMusicLinks() {
        let urls = [
            URL(string: "https://music.apple.com/us/album/example/123")!,
            URL(string: "https://classical.music.apple.com/us/album/example/456?i=789")!,
            URL(string: "music://music.apple.com/us/song/example/789")!,
            URL(string: "https://music.example.com/apple/123")!
        ]

        XCTAssertEqual(AppleMusicShareURLParser.supportedURLs(from: urls), urls)
    }

    func testAppleMusicShareURLParserRejectsNonAppleMusicLinks() {
        let urls = [
            URL(string: "https://example.com/music/123")!,
            URL(string: "https://apple.com/iphone")!,
            URL(string: "https://example.com/audio/123")!
        ]

        XCTAssertTrue(AppleMusicShareURLParser.supportedURLs(from: urls).isEmpty)
    }

    func testShareEventQueuePersistsUnsupportedDownloadSourceEvents() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let queue = try ShareEventQueue(fileURL: fileURL)
        let url = URL(string: "https://example.com/not-supported")!
        try queue.enqueue([ShareEvent(kind: .unsupportedDownloadSource, urls: [url])])

        let events = try queue.drain()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .unsupportedDownloadSource)
        XCTAssertEqual(events.first?.urls, [url])
        XCTAssertTrue(try queue.read().isEmpty)
    }

    func testPendingAppleMusicDownloadStoreDrainsSavedJobs() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = try PendingAppleMusicDownloadStore(fileURL: fileURL)
        let job = JobRequest(
            fileURL: URL(string: "https://music.apple.com/us/album/example/123")!,
            category: .appleMusic,
            operation: .appleMusicDownload(nil),
            source: .shareExtension
        )

        _ = try store.save([job])
        let batch = try store.drain()

        XCTAssertEqual(batch?.jobs, [job])
        XCTAssertNil(try store.read())
    }

    func testAppleMusicDownloaderProgressParserExtractsLatestProgressLine() {
        let text = """
        Song: Example
        \rDownloading... 38% (12.0/31.5 MB, 1.2 MB/s)
        """

        let message = AppleMusicDownloaderProgressParser.progressMessage(from: text)

        XCTAssertEqual(message, "Downloading... 38% (12.0/31.5 MB, 1.2 MB/s)")
    }

    func testAppleMusicDownloaderProgressTrackerReturnsOnlyChangedMessages() {
        let tracker = AppleMusicDownloaderProgressTracker()

        XCTAssertEqual(tracker.observe("Song: Example\n"), "Song: Example")
        XCTAssertNil(tracker.observe("Song: Example\n"))
        XCTAssertEqual(tracker.observe("\rDownloading... 40%"), "Downloading... 40%")
    }

    func testAppleMusicDownloadMessageFormatterFiltersProgressLines() {
        let output = """
        Track 4 of 6: songs
        Downloading... 42% (23/54 MB, 112 kB/s) Downloaded
        Decrypting... 41% (22/54 MB, 13 MB/s) Failed to run v2: decode mdat pos 22473151: read box body length 167546 does not match expected length 3065138
        =======  [✔ ] Completed: 3/6  |  [⚠ ] Warnings: 0  |  [✖ ] Errors: 3  =======
        Error detected, exiting...
        """

        let message = AppleMusicDownloadMessageFormatter.coreMessage(from: output)

        XCTAssertFalse(message.contains("Downloading..."))
        XCTAssertFalse(message.contains("Decrypting..."))
        XCTAssertTrue(message.contains("Failed to run v2"))
        XCTAssertTrue(message.contains("Completed: 3/6"))
    }

    func testProcessRunnerDrainsLargeOutputBeforeProcessExit() async throws {
        let result = try await ProcessRunner().run(
            executablePath: "/usr/bin/perl",
            arguments: ["-e", "print \"x\" x 200000; print STDERR \"e\" x 100000;"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 200000)
        XCTAssertEqual(result.standardError.count, 100000)
    }

    func testProcessRunnerTerminatesWhenRequested() async throws {
        let start = Date()
        let result = try await ProcessRunner().run(
            executablePath: "/bin/zsh",
            arguments: ["-c", "while true; do echo tick; sleep 1; done"],
            shouldTerminate: {
                Date().timeIntervalSince(start) > 0.5
            }
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.standardOutput.contains("tick"))
    }

    func testAppleMusicWrapperInitializationMatchesUpstreamLoginFlow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(rootURL: root, resourceRoot: nil)
        let wrapper = AppleMusicWrapperRuntime(runtimeManager: manager)
        let mount = "\(root.path)/rootfs/data:/app/rootfs/data"
        let arguments = wrapper.initializationDockerArguments(
            username: "user@example.com",
            password: "password",
            mount: mount
        )

        XCTAssertEqual(arguments, [
            "run", "--detach",
            "--privileged",
            "--platform", ManagedDockerImage.appleMusicWrapper.platform,
            "--name", "get-oudio-wrapper-login",
            "-v", mount,
            "--entrypoint", "./wrapper",
            ManagedDockerImage.appleMusicWrapper.imageName,
            "-L", "user@example.com:password",
            "-F",
            "-H", "0.0.0.0"
        ])
        XCTAssertFalse(arguments.contains("--rm"))
    }

    func testAppleMusicWrapperRewritesLoopbackSystemProxyForColima() {
        let proxy = AppleMusicWrapperRuntime.proxyURL(from: [
            kCFNetworkProxiesHTTPSEnable as String: 1,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: 7897
        ])

        XCTAssertEqual(proxy?.absoluteString, "http://host.lima.internal:7897")
    }

    func testAppleMusicWrapperLogSummaryFiltersLinkerNoiseAndKeepsFailure() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wrapper = AppleMusicWrapperRuntime(
            runtimeManager: AppleMusicRuntimeManager(rootURL: root, resourceRoot: nil)
        )
        let summary = wrapper.wrapperLogSummary(
            "WARNING: linker: unused DT entry\n[+] starting...\n[!] login failed\n"
        )

        XCTAssertTrue(summary.contains("filtered 1 Android linker warnings"))
        XCTAssertFalse(summary.contains("unused DT entry"))
        XCTAssertTrue(summary.contains("[!] login failed"))
    }

    func testAppleMusicWrapperLoginStatusRecognizesWaitingForVerificationCode() {
        let status = AppleMusicWrapperRuntime.loginStatus(
            logs: "[.] credentialHandler: {2FA: true}\n[!] Waiting for input...",
            isRunning: true,
            hasCompletedMarker: false
        )

        XCTAssertEqual(status.phase, .waitingForVerificationCode)
        XCTAssertTrue(status.canSubmitVerificationCode)
        XCTAssertTrue(status.isInProgress)
    }

    func testAppleMusicWrapperLoginStatusRecognizesAuthenticationAndFailure() {
        let authenticated = AppleMusicWrapperRuntime.loginStatus(
            logs: "[.] response type 6",
            isRunning: true,
            hasCompletedMarker: false
        )
        let failed = AppleMusicWrapperRuntime.loginStatus(
            logs: "[.] response type 4\n[!] login failed",
            isRunning: false,
            hasCompletedMarker: false
        )

        XCTAssertTrue(authenticated.isAuthenticated)
        XCTAssertFalse(authenticated.canSubmitVerificationCode)
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertFalse(failed.isInProgress)
    }

    func testAppleMusicWrapperLoginStatusPrefersPersistedCompletionMarker() {
        let status = AppleMusicWrapperRuntime.loginStatus(
            logs: "",
            isRunning: false,
            hasCompletedMarker: true
        )

        XCTAssertEqual(status.phase, .authenticated)
        XCTAssertEqual(status.message, "初始化已完成")
    }

    func testAppleMusicWrapperClearsStaleVerificationCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(rootURL: root, resourceRoot: nil)
        let wrapper = AppleMusicWrapperRuntime(runtimeManager: manager)
        try wrapper.writeVerificationCode("123456")
        let codeURL = try wrapper.dataDirectory().appendingPathComponent("2fa.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: codeURL.path))

        try wrapper.clearVerificationCode()

        XCTAssertFalse(FileManager.default.fileExists(atPath: codeURL.path))
    }

    func testAppleMusicWrapperIsManagedDockerImage() {
        #if arch(arm64)
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.imageName, "ghcr.io/itouakirai/wrapper:arm")
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.platform, "linux/arm64")
        #else
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.imageName, "ghcr.io/itouakirai/wrapper:x86")
        XCTAssertEqual(ManagedDockerImage.appleMusicWrapper.platform, "linux/amd64")
        #endif
        XCTAssertEqual(
            ManagedDockerImage.appleMusicWrapper.upstreamURL.absoluteString,
            "https://github.com/itouakirai/wrapper"
        )
        XCTAssertFalse(BundledComponent.allCases.map(\.rawValue).contains("appleMusicWrapper"))
    }

    func testGenericRuntimeDependenciesDoNotIncludeAppleMusicRuntime() {
        XCTAssertEqual(RuntimeDependency.allCases, [.ffmpeg])
        XCTAssertEqual(RuntimeDependency.ffmpeg.displayName, "ffmpeg")
        XCTAssertEqual(RuntimeDependency.ffmpeg.bundledRelativePath, "ffmpeg/ffmpeg")
    }

    func testColimaRuntimeStatusDistinguishesStoppedRuntimeFromMissingRuntime() {
        let stoppedRuntime = ColimaRuntimeStatus(
            dockerPath: "/managed/bin/docker",
            colimaPath: "/managed/bin/colima",
            isRunning: false,
            detail: "Colima 未运行，使用 Apple Music 时会在后台启动"
        )
        let missingRuntime = ColimaRuntimeStatus(
            dockerPath: "/managed/bin/docker",
            colimaPath: nil,
            isRunning: false,
            detail: "未安装 Colima"
        )

        XCTAssertTrue(stoppedRuntime.canStartOnDemand)
        XCTAssertFalse(missingRuntime.canStartOnDemand)
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

    func testAppleMusicRuntimeManagedPathsAndEnvironment() throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            settingsStore: SettingsStore(defaults: defaults),
            resourceRoot: nil
        )
        let environment = manager.runtimeEnvironment()

        XCTAssertEqual(manager.binDirectory.path, root.appendingPathComponent("bin").path)
        XCTAssertEqual(manager.colimaHomeDirectory.path, root.appendingPathComponent("colima-home").path)
        XCTAssertEqual(environment["COLIMA_HOME"], root.appendingPathComponent("colima-home").path)
        XCTAssertEqual(environment["COLIMA_CACHE_HOME"], root.appendingPathComponent("colima-cache").path)
        XCTAssertEqual(environment["LIMA_HOME"], root.appendingPathComponent("lima-home").path)
        XCTAssertEqual(environment["DOCKER_CONFIG"], root.appendingPathComponent("docker-config").path)
        XCTAssertTrue(environment["PATH"]?.contains(root.appendingPathComponent("bin").path) == true)
        XCTAssertTrue(environment["PATH"]?.contains(root.appendingPathComponent("gpac").path) == true)
    }

    func testAppleMusicRuntimeAcceptsShortVMStatePaths() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vmRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let colimaHome = vmRoot.appendingPathComponent("Colima", isDirectory: true)
        let limaHome = vmRoot.appendingPathComponent("Lima", isDirectory: true)
        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            colimaHomeDirectory: colimaHome,
            limaHomeDirectory: limaHome,
            resourceRoot: nil
        )

        XCTAssertEqual(manager.runtimeEnvironment()["COLIMA_HOME"], colimaHome.path)
        XCTAssertEqual(manager.runtimeEnvironment()["LIMA_HOME"], limaHome.path)
    }

    func testAppleMusicRuntimeHasOfficialDefaultGPACPackage() {
        XCTAssertEqual(
            AppleMusicRuntimeManager.gpacDefaultPackageURL.absoluteString,
            "https://download.tsi.telecom-paristech.fr/gpac/new_builds/gpac_latest_head_macos.pkg"
        )
        XCTAssertEqual(AppleMusicRuntimeManager.gpacDefaultPackageURL.pathExtension, "pkg")
    }

    func testAppleMusicRuntimeDownloadArgumentsPreservePartialFileAcrossRetries() {
        let partial = URL(fileURLWithPath: "/tmp/gpac-runtime.pkg.part")
        let arguments = AppleMusicRuntimeManager.downloadArguments(
            url: AppleMusicRuntimeManager.gpacDefaultPackageURL,
            partial: partial
        )

        XCTAssertTrue(arguments.contains("--continue-at"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--continue-at")! + 1], "-")
        XCTAssertFalse(arguments.contains("--retry"))
        XCTAssertFalse(arguments.contains("--retry-all-errors"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--speed-limit")! + 1], "1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--speed-time")! + 1], "120")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--output")! + 1], partial.path)
        XCTAssertEqual(AppleMusicRuntimeManager.downloadAttemptCount, 9)
    }

    func testAppleMusicRuntimeAgentRequestCarriesGPACOverride() throws {
        let request = AppleMusicRuntimeAgentRequestEnvelope(
            id: UUID(),
            command: "install",
            resourceRootPath: "/tmp/resources",
            gpacPackageURLOverride: "https://example.com/gpac-runtime.pkg"
        )
        let decoded = try JSONDecoder().decode(
            AppleMusicRuntimeAgentRequestEnvelope.self,
            from: JSONEncoder().encode(request)
        )

        XCTAssertEqual(decoded.gpacPackageURLOverride, "https://example.com/gpac-runtime.pkg")
    }

    func testAppleMusicRuntimePrefersOfficialGPACModulesDirectory() throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            settingsStore: SettingsStore(defaults: defaults),
            resourceRoot: nil
        )
        let modules = manager.gpacDirectory.appendingPathComponent("modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)

        XCTAssertEqual(manager.runtimeEnvironment()["GPAC_MODULES_PATH"], modules.path)
    }

    func testAppleMusicRuntimeInstallSkipsVerifiedComponents() async throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SettingsStore(defaults: defaults)
        let wrapperStatus = ManagedDockerImageStatus(
            image: .appleMusicWrapper,
            isAvailable: true,
            detail: "test wrapper"
        )
        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            settingsStore: store,
            resourceRoot: nil,
            wrapperImageInstaller: { _ in (wrapperStatus, false) }
        )
        let executable = Data("#!/bin/sh\nexit 0\n".utf8)
        for url in [manager.colimaURL, manager.limaURL, manager.limactlURL, manager.dockerURL, manager.mp4BoxURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("share/lima", isDirectory: true),
            withIntermediateDirectories: true
        )
        let downloads = manager.downloadsDirectory
        try FileManager.default.createDirectory(
            at: downloads.appendingPathComponent("gpac-stale/expanded", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("archive".utf8).write(to: downloads.appendingPathComponent("gpac-runtime.pkg"))
        try Data("partial".utf8).write(to: downloads.appendingPathComponent("gpac-runtime.pkg.part"))
        let colimaCaches = manager.colimaCacheDirectory.appendingPathComponent("caches", isDirectory: true)
        try FileManager.default.createDirectory(at: colimaCaches, withIntermediateDirectories: true)
        try Data("base-image".utf8).write(to: colimaCaches.appendingPathComponent("cached-image"))

        let result = try await manager.installManagedRuntime()

        XCTAssertTrue(result.installedComponents.isEmpty)
        XCTAssertEqual(result.messages.filter { $0.contains("跳过") }.count, 5)
        XCTAssertTrue(store.isAppleMusicDownloadEnabled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: downloads.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: colimaCaches.path), [])
    }

    func testAppleMusicRuntimeProgressCarriesLiveStatuses() throws {
        let status = AppleMusicRuntimeComponentStatus(
            component: .docker,
            isReady: true,
            resolvedPath: "/tmp/docker",
            detail: "/tmp/docker"
        )
        let progress = AppleMusicRuntimeProgress(
            message: "Docker CLI 已就绪",
            completedUnitCount: 3,
            totalUnitCount: 5,
            isActive: true,
            statuses: [status]
        )
        let decoded = try JSONDecoder().decode(
            AppleMusicRuntimeProgress.self,
            from: JSONEncoder().encode(progress)
        )

        XCTAssertEqual(decoded.statuses, [status])
        XCTAssertEqual(decoded.fractionCompleted, 0.6)
    }

    func testAppleMusicRuntimeStatusesPreferManagedExecutables() throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            settingsStore: SettingsStore(defaults: defaults),
            resourceRoot: nil
        )
        for url in [manager.dockerURL, manager.colimaURL, manager.limaURL, manager.limactlURL, manager.mp4BoxURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("share/lima", isDirectory: true),
            withIntermediateDirectories: true
        )

        let statuses = manager.componentStatuses()
        let readyIDs = Set(statuses.filter(\.isReady).map(\.component))

        XCTAssertTrue(readyIDs.contains(.docker))
        XCTAssertTrue(readyIDs.contains(.colima))
        XCTAssertTrue(readyIDs.contains(.lima))
        XCTAssertTrue(readyIDs.contains(.gpac))
        XCTAssertEqual(statuses.first { $0.component == .gpac }?.resolvedPath, manager.mp4BoxURL.path)
    }

    func testAppleMusicRuntimeStatusRejectsDirectoryNamedDocker() throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = AppleMusicRuntimeManager(
            rootURL: root,
            settingsStore: SettingsStore(defaults: defaults),
            resourceRoot: nil
        )
        try FileManager.default.createDirectory(
            at: manager.dockerURL.appendingPathComponent("_CodeSignature", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "placeholder".write(
            to: manager.dockerURL.appendingPathComponent("_CodeSignature/CodeResources"),
            atomically: true,
            encoding: .utf8
        )

        let dockerStatus = manager.componentStatuses().first { $0.component == .docker }

        XCTAssertEqual(dockerStatus?.isReady, false)
        XCTAssertNil(dockerStatus?.resolvedPath)
        XCTAssertTrue(dockerStatus?.detail.contains("是目录，不是可执行文件") == true)
    }

    func testAppleMusicDownloadServiceRejectsJobsWhenDisabled() async {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SettingsStore(defaults: defaults)
        let manager = AppleMusicRuntimeManager(rootURL: root, settingsStore: store, resourceRoot: nil)
        let service = AppleMusicDownloadService(runtimeManager: manager, settingsStore: store, useAgent: false)
        let job = JobRequest(
            fileURL: URL(string: "https://music.apple.com/us/album/example/123")!,
            category: .appleMusic,
            operation: .appleMusicDownload(.alac),
            source: .shareExtension
        )

        let summary = await service.download([job])

        XCTAssertEqual(summary.successCount, 0)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertTrue(summary.messages.first?.contains("尚未启用") == true)
    }

    func testAppleMusicRuntimeUninstallDoesNotRemoveDownloadOutputDirectory() async throws {
        let suiteName = "GetOudioCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }

        let store = SettingsStore(defaults: defaults)
        store.appleMusicOutputURL = output
        store.isAppleMusicDownloadEnabled = true
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let manager = AppleMusicRuntimeManager(rootURL: root, settingsStore: store, resourceRoot: nil)
        try await manager.uninstallManagedRuntime()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(store.isAppleMusicDownloadEnabled)
    }

    func testAppleMusicRuntimeAgentClientUsesBundledHelperCandidate() {
        let applicationURL = AppleMusicRuntimeAgentClient.defaultApplicationURL(
            bundle: Bundle(for: GetOudioCoreTests.self)
        )

        XCTAssertNotNil(applicationURL)
        XCTAssertEqual(applicationURL?.lastPathComponent, AppleMusicRuntimeAgentClient.applicationBundleName)
    }
}
