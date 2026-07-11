# Bundled Tools and Assets Guide

本指南适用于转换预设、精简 ffmpeg、内嵌 downloader 和图标资源。第三方二进制不得在无明确任务要求时改动。

## Conversion Presets and ffmpeg

转码预设真源是 `GetOudioCore/Sources/Models/ConversionPreset.swift`。新增或调整预设时同步维护 enum case、`ConversionPresetGroup`、`title`、`finderMenuTitle`、`outputNameSuffix`、`outputExtension` 和 `ffmpegArguments`，并补齐 Core tests。Finder Sync 还需为每个新预设在 `FinderSync.swift` 增加显式 `@objc` selector。`allCases` 顺序必须保持 AAC、MP3、Vorbis、Opus、ALAC、FLAC、PCM WAV、PCM AIFF。

Vorbis 使用 `libvorbis`、Ogg muxer、`.ogg` 和 `-q:a 3/6/10`。Opus 使用 `libopus`、Ogg muxer、`.opus`，菜单中的 `64/96/128kbps Per-Ch` 是每声道码率；`AudioConversionService` 探测声道数后换算 ffmpeg `-b:a`，失败才按立体声兜底。两者均须复制全局元数据，不能丢掉 `-map_metadata 0:g`。

精简 ffmpeg 使用 `bash script/build_minimal_ffmpeg.sh` 构建。修改 encoder、muxer、demuxer 或预设依赖后，重编 `GetOudio/Resources/ThirdParty/ffmpeg/ffmpeg`，并检查 `-encoders`、`-muxers` 和 `otool -L`。Vorbis/Opus 依赖 `libvorbis`、`libvorbisenc`、`libogg`、`libopus` 静态链接，不得重新引入 Homebrew dylib 或把 `libmp3lame.0.dylib` 等动态库作为随包资源。

## apple-music-downloader

内嵌 downloader 必须通过 `bash script/build_apple_music_downloader.sh` 从相邻 fork 构建同步；需要其他源码路径时使用 `APPLE_MUSIC_DOWNLOADER_SOURCE=/path/to/source`。脚本目标为 `darwin/arm64`、`CGO_ENABLED=0`，使用 `go build -trimpath -ldflags="-s -w"`，并使用 `build/apple-music-downloader/` 下的专用 Go caches。不得用上游默认产物手工替换，也不得提交 fork 源码、module cache 或中间产物。

替换后二进制至少检查 `go version -m`、`otool -L` 和文件体积，确认来源、目标架构、无 CGO 依赖且仅依赖 macOS 系统库；随后运行 Core tests，重点覆盖 `AppleMusicDownloadFormat`、`AppleMusicDownloadService.downloaderArguments` 和进度解析。

## Icons

主图标源是 `GetOudio/Resources/AppIcon.icon`；源码 Info.plist 只维护 `CFBundleIconName = AppIcon`，构建产物中的 `CFBundleIconFile = AppIcon` 是 actool 补全，不得写回源码。`project.yml` 的 `postGenCommand` 必须继续把该资源的 `lastKnownFileType` 修补为 `folder.iconcomposer.icon`。Share Extension 使用自己的 `icon.icns` 和 `CFBundleIconFile = icon`。
