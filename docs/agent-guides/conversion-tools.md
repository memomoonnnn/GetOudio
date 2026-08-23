# Conversion Tools Guide

适用于转码预设、ffmpeg、编码器、muxer、demuxer 和音频格式能力。修改前检查 `ConversionPreset.swift`、`AudioConversionService`、`FinderSync.swift`、相关 Core tests 和 `script/build_minimal_ffmpeg.sh`。

预设真源为 `GetOudioCore/Sources/Models/ConversionPreset.swift`。新增或调整预设时同步维护 enum case、`ConversionPresetGroup`、`title`、`finderMenuTitle`、`outputNameSuffix`、`outputExtension` 和 `ffmpegArguments`，并补齐 Core tests。Finder Sync 的新预设还须在 `FinderSync.swift` 增加显式 `@objc` selector。`allCases` 顺序保持 AAC、MP3、Vorbis、Opus、ALAC、FLAC、PCM WAV、PCM AIFF。

Vorbis 使用 `libvorbis`、Ogg、`.ogg` 与 `-q:a 3/6/10`。Opus 使用 `libopus`、Ogg、`.opus`，菜单 `64/96/128kbps Per-Ch` 是每声道码率；`AudioConversionService` 探测声道数后换算 `-b:a`，失败才按立体声兜底。两者复制全局元数据，不得丢失 `-map_metadata 0:g`。

精简 ffmpeg 用 `bash script/build_minimal_ffmpeg.sh` 构建。修改 encoder、muxer、demuxer 或预设依赖后，重编 `GetOudio/Resources/ThirdParty/ffmpeg/ffmpeg`，检查 `-encoders`、`-muxers` 和 `otool -L`。Vorbis/Opus 静态链接 `libvorbis`、`libvorbisenc`、`libogg`、`libopus`，不得引入 Homebrew dylib 或动态库资源。
