# apple-music-downloader 二进制体积调查

调查日期：2026-07-04。对象是本仓库嵌入的 `GetOudio/Resources/ThirdParty/apple-music-downloader/apple-music-downloader`，以及上游 `zhaarey/apple-music-downloader` 的 `903f1925eb434e1057f8a763e6e272db9561763a` 提交；本地实验使用 Go `go1.26.4 darwin/arm64`，临时源码位于 `/private/tmp/apple-music-downloader-src`。

## 结论

当前 18 MB 体积不是因为把所有 Go module 源码或外部动态库原样打包进二进制。Go 链接器只链接 import 图中实际可达的包代码，但这个 CLI 的单一 `main.go` 同时 import 了下载、解密、歌词、搜索、交互选择、表格输出、MP4 tag、MV/Widevine/protobuf 等功能路径，因此依赖图本身较宽；此外默认构建没有去掉 Go 符号表和 DWARF 调试信息。低风险瘦身是用 `go build -trimpath -ldflags="-s -w"` 重编，实验中从 `18,445,362` 字节降到 `12,753,922` 字节，约减少 31%。进一步变小需要维护 Get Oudio 专用 fork，按实际调用面裁掉交互搜索、表格显示、部分 MV/歌词/转换/tag 功能，属于功能取舍和回归测试问题，不是简单改编译参数。

## 证据

本仓库现有二进制为 arm64 Mach-O，大小 `18M`，`go version -m` 显示它来自模块 `main`、Go `1.26.4`，依赖包括 `survey/v2`、`go-mp4tag`、`resty/v2`、`mp4ff`、`protobuf`、`progressbar`、`tablewriter`、`yaml.v2` 等；`otool -L` 只显示 macOS 系统库依赖，如 `libSystem`、`libresolv`、`CoreFoundation` 和 `Security`，没有第三方 dylib 被塞入或动态引用。上游 `go.mod` 声明的直接依赖覆盖 CLI flag、交互选择、进度条、HLS/m3u8、protobuf、MP4 处理、YAML 和 HTTP 客户端；上游 Dockerfile 的构建命令是 `CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /bin/apple-music-dl main.go`，GitHub Actions 里 macOS/Linux/Windows 也只是 `go build -o main -v ./main.go`，均未使用 `-ldflags="-s -w"`。

复现实验在上游提交 `903f1925eb434e1057f8a763e6e272db9561763a` 上执行：默认 `go build -trimpath -o /private/tmp/amd-default main.go` 产物为 `18,445,362` 字节；`CGO_ENABLED=0` 对 darwin/arm64 产物大小没有明显影响；`go build -trimpath -ldflags="-s -w"` 产物为 `12,753,922` 字节。Go 官方 `cmd/link` 文档说明 `-s` 会省略符号表和调试信息，并隐含 `-w`，而 `-w` 会省略 DWARF 符号表；这与 `size -m` 中默认产物存在约 `4.4 MB` `__DWARF` 段、`-s -w` 产物移除该段的观察一致。

Get Oudio 当前调用 `AppleMusicDownloadService.downloaderArguments` 时只会传 ALAC 默认空参数、`--aac`、`--atmos`，并在单曲 URL 上追加 `--song`；它不调用上游 `--search`、`--select` 或 `--all-album` 等交互入口。上游 `main.go` 仍直接 import `github.com/AlecAivazis/survey/v2` 用于交互搜索质量选择、`github.com/olekukonko/tablewriter` 用于 artist/质量列表表格、`github.com/zhaarey/go-mp4tag` 用于 MP4 tag 写入，并引入 `main/utils/runv3`，后者再引入 `resty`、`protobuf`、`mp4ff` 和 Widevine 相关生成代码。`go list -deps` 验证最终依赖图确实包含这些包；`go mod why -m` 显示 `survey` 与 `tablewriter` 由 `main` 直接引入，`go-mp4tag` 由 `main` 直接引入，`resty` 和 `protobuf` 经 `main/utils/runv3` 引入，`mp4ff` 与 `progressbar` 经 `runv2/runv3` 引入。

## 可行路径

第一步可以只重编并替换二进制，使用 `go build -trimpath -ldflags="-s -w" -o apple-music-downloader main.go`，再验证 ALAC、AAC、Atmos、单曲 URL、专辑 URL、失败重试和进度解析。这条路径不会改变功能，预期节省约 5.7 MB，风险最低。`strip` 对 Go 默认产物的实验只降到 `17,228,720` 字节，明显不如链接期 `-s -w`。

第二步若要继续压缩，应维护 Get Oudio 专用上游 fork 或补丁集，把 CLI 拆成 build tags 或新 `cmd/get-oudio-amd` 入口，只保留当前 App 需要的非交互下载路径。优先评估裁掉 `survey`、`tablewriter`、artist 交互选择和 `--search`，这些与 Get Oudio 当前调用面无关；再评估是否真的需要歌词、MV、下载后转换、MP4 tag 写入和 `alacfix`。其中歌词与 tag 由当前模板默认开启或影响输出质量，不能无声移除；MV 与 Widevine/protobuf/`mp4decrypt` 路径如果 Get Oudio 不支持分享 Music Video，则可能是较大的候选裁剪面，但需要先明确产品范围。

第三步可以考虑 UPX 这类可执行压缩，但本机未安装，且 macOS 签名、Gatekeeper、杀软误报、启动时解压开销和 notarization 兼容性都要单独验证；对要随 `.app` 分发的工具，优先级低于 `-s -w` 和功能级裁剪。

## 主要来源

- 上游仓库：https://github.com/zhaarey/apple-music-downloader
- 上游 `go.mod`：https://raw.githubusercontent.com/zhaarey/apple-music-downloader/main/go.mod
- 上游 `Dockerfile`：https://raw.githubusercontent.com/zhaarey/apple-music-downloader/main/Dockerfile
- 上游 `main.go`：https://raw.githubusercontent.com/zhaarey/apple-music-downloader/main/main.go
- Go `go build` 文档：https://pkg.go.dev/cmd/go#hdr-Compile_packages_and_dependencies
- Go linker `-s/-w` 文档：https://pkg.go.dev/cmd/link
