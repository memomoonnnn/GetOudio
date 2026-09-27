# Conversion Tools Guide

适用于转码预设、ffmpeg、编码器、muxer、demuxer 和音频格式能力。修改前检查 `ConversionPreset.swift`、`AudioConversionService`、`FinderSync.swift`、相关 Core tests 和 `script/build_minimal_ffmpeg.sh`。

预设真源为 `GetOudioCore/Sources/Models/ConversionPreset.swift`。新增或调整预设时同步维护 enum case、`ConversionPresetGroup`、`title`、`finderMenuTitle`、`outputNameSuffix`、`outputExtension` 和 `ffmpegArguments`，并补齐 Core tests。Finder Sync 的新预设还须在 `FinderSync.swift` 增加显式 `@objc` selector。`allCases` 顺序保持 AAC、MP3、Vorbis、Opus、ALAC、FLAC、PCM WAV、PCM AIFF。

Vorbis 使用 `libvorbis`、Ogg、`.ogg` 与 `-q:a 3/6/10`。Opus 使用 `libopus`、Ogg、`.opus`，菜单 `64/96/128kbps Per-Ch` 是每声道码率；`AudioConversionService` 探测声道数后换算 `-b:a`，失败才按立体声兜底。两者复制全局元数据，不得丢失 `-map_metadata 0:g`。

精简 ffmpeg 用 `bash script/build_minimal_ffmpeg.sh` 构建。修改 encoder、decoder、muxer、demuxer 或预设依赖后，重编 `GetOudio/Resources/ThirdParty/ffmpeg/ffmpeg`，检查 `-encoders`、`-decoders`、`-muxers` 和 `otool -L`。Vorbis/Opus 静态链接 `libvorbis`、`libvorbisenc`、`libogg`、`libopus`，不得引入 Homebrew dylib 或动态库资源。

M4A（AAC、ALAC）、MP3 和 FLAC 复制输入中第一张 JPEG/PNG `attached_pic`，Ogg Vorbis 和 Opus 用 `METADATA_BLOCK_PICTURE` 写入同一图片；显式映射第一条音轨和所选封面，不得把普通视频流写入音频文件。WAV、AIFF 和非 JPEG/PNG 封面维持纯音频输出。封面准备或复用失败时清理临时输出并按原参数重试音频转码，原因只写调试日志，不进入任务结果或通知。

复制内嵌 JPEG/PNG 时，精简 ffmpeg 仍需 `mjpeg`、`png` decoder 及 PNG 所需的 zlib 来探测尺寸；缺少尺寸会让 MP3 等 muxer 拒绝封面。构建脚本须验证这两个 decoder 实际启用。验收至少覆盖带真实 JPEG 封面的 M4A、带 PNG 封面的输入、无封面输入和不支持的封面编码，并重新探测输出的音轨、封面、文字元数据及动态库依赖。
