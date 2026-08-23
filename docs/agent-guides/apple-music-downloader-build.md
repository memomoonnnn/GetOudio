# Apple Music Downloader Build Guide

适用于内嵌 `apple-music-downloader` 的构建、替换和与 wrapper 的发布组合。修改前检查 `script/build_apple_music_downloader.sh`、`config.yaml.template`、相关 Core 测试及相邻 fork。

内嵌 downloader 必须通过 `bash script/build_apple_music_downloader.sh` 从相邻 fork 构建同步；需要其他源码路径时使用 `APPLE_MUSIC_DOWNLOADER_SOURCE=/path/to/source`。脚本目标为 `darwin/arm64`、`CGO_ENABLED=0`，使用 `go build -trimpath -ldflags="-s -w"` 与 `build/apple-music-downloader/` 专用 Go caches。不得手工替换为上游默认产物，也不得提交 fork 源码、module cache 或中间产物。

替换后二进制检查 `go version -m`、`otool -L` 和文件体积，确认来源、目标架构、无 CGO 依赖且仅依赖 macOS 系统库；随后运行 Core tests，覆盖 `AppleMusicDownloadFormat`、`AppleMusicDownloadService.downloaderArguments` 和进度解析。涉及 `runv4` 或模板解密时，内嵌二进制、`config.yaml.template` 与受控 wrapper 修订作为同一发布组合验证：模板启用 `template-decrypt` 并指向 40020 key server，签名安装后以授权测试账号完成初始化、40020 空请求 HTTP 400 与一首测试曲下载。
