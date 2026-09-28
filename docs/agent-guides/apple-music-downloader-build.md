# Apple Music Downloader Build Guide

适用于内嵌 downloader、Temari 和 wrapper-lite 的发布组合。修改前检查 `script/build_apple_music_downloader.sh`、`config.yaml.template`、Core 测试及相邻 fork。

内嵌 downloader 必须由 `bash script/build_apple_music_downloader.sh` 从相邻 Get Oudio fork 构建；其他源码路径用 `APPLE_MUSIC_DOWNLOADER_SOURCE=/path/to/source`。脚本目标为 `darwin/arm64`、`CGO_ENABLED=0`，使用 `go build -trimpath -ldflags="-s -w"` 和专用 Go caches，并同步 `libtemari.dylib`。不得手工替换上游默认产物，不得提交 fork 源码、module cache 或中间产物。构建后检查 `go version -m`、`file`、`otool -L`，确认 downloader 与 Temari 均为目标架构；打包脚本须在签名 App 时签署这两个文件。

downloader 与固定 wrapper-lite QEMU 发布修订按同一组合验证。配置应指向 `lite-server: "http://127.0.0.1:12340"`；机器输出只使用 stdout-exclusive `--events=jsonl`，不可恢复旧 `--song` 或 40020 key-server 参数。Core tests 覆盖格式参数、事件解析和配置渲染；签名安装后以授权测试账号完成 QEMU 登录、非空 `/status` 与一首测试曲下载。
