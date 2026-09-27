# wrapper-lite 与上游 downloader 迁移评估

首次调查：2026-09-16；复查日期：2026-09-27。本文将先前的 [`wrapper-lite` 调查报告](../../../apple-music-downloader-get-oudio/docs/research/wrapper-lite-updates.md) 作为线索，结论均重新对照已刷新的官方 Git 提交、源码、GitHub Actions 制品元数据以及 Get Oudio 当前源码。

## 结论

迁移在技术上可行。wrapper-lite 这轮开发截至 2026-09-27 已明显进入静止期：最后一次提交是 2026-09-20，当前没有以 `lite` 为 base 的开放 PR，仓库默认分支也已从旧 `main` 转为 `lite`。这说明上游已把 lite 视为主线，但不能证明它已形成正式稳定版本：上游没有 lite Release、不可变版本标签或完成公告，最新制品仍是 90 天后过期的 Actions artifact。历史提交 `8dd64c9` 虽命名为 “Release wrapper-lite 1.0.0”，但没有对应 tag 或 GitHub Release。

因此建议把 `b7058ec5` 视为可固定和验证的候选基线，而不是可直接引用的发布版。迁移仍应作为 wrapper 制品、登录协议、健康检查、downloader 协议和媒体处理的联合迁移：保留 Get Oudio 的 Colima VZ + Rosetta 和 `linux/amd64` Docker 边界，自行生成不可变制品，在 trimmed fork 中移植单端口 HTTP 适配，并保留 `--events=jsonl`、非交互契约和现有纯 Go 模板解密。

不建议直接基于 downloader 上游 `4c8b1328` 交付。它仍缺少 `--events=jsonl`、`--song`、`utils/contract` 和相关契约测试，stdout 仍混有人类文本；Temari 动态库加载方式也仍与 Get Oudio 的 `-trimpath` 单二进制交付契约不兼容。

## 本次复查变化

wrapper-lite 从 `927ecfd5` 前进 5 个提交到 `b7058ec5`。其中一个提交为登录后 token 获取增加最多 5 次重试，其余四个提交修复 QEMU 包错误捆绑 glibc、artifact 丢失执行位和运行库搜索路径，并新增 Ubuntu 22.04/24.04 启动 `/status` 的包级验证。最新 [Actions run 35492251958](https://github.com/WorldObservationLog/wrapper/actions/runs/35492251958) 全部成功，表明 QEMU 分发质量改善；HTTP API、登录参数、2FA 路径和 response envelope 没有变化。

downloader 从 `22a35ee` 前进 3 个提交到 `4c8b1328`：wrapper-lite 调用已集中到 `internal/wrapper` 并新增 283 行 client 测试，另修复 progressive M4A 的 CMAF conformance 错误。这降低了从上游选择性移植 HTTP client 的成本，但没有改变 Get Oudio 的 CLI、JSONL 和 Temari 阻断。

## 当前版本与变更范围

| 对象 | 现场结果 | 证据 |
| --- | --- | --- |
| Get Oudio wrapper | 固定 `4d83f2feb396ca26847530ff7010ac6a4877f136`，下载旧 `Wrapper.x86_64.latest.zip` 并校验 SHA-256 | [`AppleMusicRuntimeManager.swift`](../../GetOudioCore/Sources/Services/AppleMusicRuntimeManager.swift#L92-L104) |
| wrapper `lite` | HEAD `b7058ec529156335cc7141319f3ca9d0e9baa95e`（2026-09-20），相对旧 `main` 的 `4d83f2fe` 增加 50 个提交；当前仓库默认分支为 `lite` | [commit](https://github.com/WorldObservationLog/wrapper/commit/b7058ec529156335cc7141319f3ca9d0e9baa95e)、[compare](https://github.com/WorldObservationLog/wrapper/compare/main...lite) |
| downloader fork | HEAD `2b363b8ab11146c640ce1f889c5af542111f9678`，含 Get Oudio 专用 runv4/JSONL | [fork commit](https://github.com/memomoonnnn/apple-music-downloader/commit/2b363b8ab11146c640ce1f889c5af542111f9678) |
| downloader upstream | HEAD `4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e`（2026-09-19）；相对 fork 为 fork 独有 4、上游独有 50 | [upstream commit](https://github.com/zhaarey/apple-music-downloader/commit/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e) |

两个 downloader 分支的 merge-base 仍是 `9dd6dede39c8b5ea42d5a741fee903003ee72690`。当前 fork 独有 4 个提交、上游独有 50 个提交，仍不是适合整体同步的小型提交集。

## wrapper-lite 的必要改造

`wrapper-lite` 把 10020/20020/30020/40020 四个服务收口到默认 `12340` 的 HTTP API，提供 `/m3u8`、`/key`、`/lyrics`、`/webplayback`、`/license` 和 `/status`；响应是 `{code,msg,data}` envelope，业务错误通常仍是 HTTP 200。`/license` 支持可选 `drm-type=wv/pr`，为 Widevine 和 PlayReady 共用入口。本轮最后 5 个提交未改变这些接口。路由和 envelope 实现见 [`lite_main.cpp`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/lite/lite_main.cpp)。

Get Oudio 当前登录命令是 `./wrapper -L user:password -F -H 0.0.0.0`，并依赖旧日志标记；服务命令显式映射四个端口，以 40020 空请求返回 HTTP 400 作为就绪条件。见 [`AppleMusicWrapperRuntime.swift` 登录参数](../../GetOudioCore/Sources/Services/AppleMusicWrapperRuntime.swift#L228-L249)、[旧日志判定](../../GetOudioCore/Sources/Services/AppleMusicWrapperRuntime.swift#L360-L383) 和 [服务/健康检查](../../GetOudioCore/Sources/Services/AppleMusicWrapperRuntime.swift#L471-L566)。迁移必须同步完成以下变更：

| 改动面 | 必要改动 | 风险或护栏 |
| --- | --- | --- |
| 制品 | 从 `b7058ec5` 生成可重复的 `linux/amd64` native/Docker 制品，使用自有的不可变 URL 和 SHA-256 固定 | 官方 Releases 仍只有旧 `main` 的 `wrapper.x86_64.latest`/`arm64.latest`。`b7058ec5` 的 [Actions run 35492251958](https://github.com/WorldObservationLog/wrapper/actions/runs/35492251958) 只提供临时 artifact：Linux native 约 50 MB、macOS QEMU 约 86 MB，2026-12-19 过期，不能做生产固定源。 |
| 运行方式 | 继续在 Colima `linux/amd64` VM 内原生运行 wrapper-lite Docker 镜像，只映射 `127.0.0.1:12340:12340` | 不建议在已有 Colima VM 外再引入 macOS QEMU launcher；它对 x86_64 guest 默认 TCG，见 [`wrapper-lite-qemu.cpp`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/wrapper-lite-qemu.cpp)。HTTP API 没有客户端认证，宿主端口不得暴露到非 loopback 接口。 |
| QEMU 凭据 | 不采用上游 QEMU 登录路径；若将来采用，必须先改为不把登录参数写入持久盘 | launcher 会把完整 `--login user:password` 写入参数文件，guest 再复制到持久 `data.img` 内的 `/data/.lite-qemu-args`，且只在下次启动开头删除；登录关机后密码仍留在磁盘镜像中，直接违反 Get Oudio 的凭据只存在于 XPC 内存载荷的边界。[launcher 写入](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/wrapper-lite-qemu.cpp#L408-L418)、[guest 持久化](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/qemu/init#L37-L61) |
| 登录 | 适配 `--login user:pass --code-from-file --base-dir /data`，识别退出码、`login complete, exiting` 和新错误日志 | lite 登录是一次性进程，成功后主动退出；现有“1.5 秒后必须仍在运行”检查会把快速成功误判为失败。新重试只缓解登录成功后 token 获取的瞬时失败，不改变生命周期。[`a6ce3b0f`](https://github.com/WorldObservationLog/wrapper/commit/a6ce3b0fad05fae5e4951d560a411d7daf6e1105) |
| 退出状态 | 不能把 rootless launcher 的退出码作为登录成功证据，必须结合 token 文件和后续 `/status` | `wrapper-lite-rootless` 对子进程 `wait(NULL)` 后固定返回 0，会掩盖 lite 的非零退出状态；upstream CI 只验证未登录 `/status` 可访问，没有覆盖真实登录或 2FA。[`wrapper-lite-rootless.c`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/wrapper-lite-rootless.c#L89-L98) |
| 2FA | 将验证码写到挂载数据根的 `2fa.txt` | 新路径仍是 `<base-dir>/2fa.txt`，而当前 Get Oudio 使用 `data/com.apple.android.music/files/2fa.txt`。[`auth.cpp`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/lite/auth.cpp)、[当前路径](../../GetOudioCore/Sources/Services/AppleMusicWrapperRuntime.swift#L4-L75) |
| 就绪/失效 | 请求 `/status`，解析 envelope `code == 0`；可下载状态还必须要求 `regions` 非空 | 只看 HTTP 200 会把业务错误当成成功；只看容器 running 会把未登录服务当成可下载。 |
| 状态迁移 | 保留整个 `rootfs/data` 挂载，更新后清除 Get Oudio 自身的 `.login-completed`，要求一次重新初始化 | lite 增加 `ANDROID_ID`、`DEV_TOKEN`、`MUSIC_TOKEN`、`STOREFRONT_ID` 和 `token_cache.json`；不应假定旧数据库会在无重新登录时完整生成这些状态。 |
| 日志 | 在受控 wrapper 源码中删除 token 前缀日志，再生成制品 | `b7058ec5` 仍会输出 dev/music token 前 16 位、回退 token 前 14 位及 debug WebPlay token 前 30 位，与 Get Oudio 凭据不得记录的契约冲突。[`apple_api.cpp`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/lite/apple_api.cpp)、[`tokens.cpp`](https://github.com/WorldObservationLog/wrapper/blob/b7058ec529156335cc7141319f3ca9d0e9baa95e/lite/tokens.cpp) |

## downloader 上游的收益与阻断项

上游 `9aaf0f9` 将原本近 3000 行的 `main.go` 拆分到 `internal/app`、`internal/download`、`internal/model`、`internal/fairplay-rip`、`internal/widevine-rip` 和 `internal/media`，并全面改用 wrapper-lite。后续 `6785417`、`64c07b7`、`facad1d` 将常规 fMP4 defragment、MV mux 和 station tag 改为纯 Go，在关闭可选转换/动态封面时已无 `MP4Box` 子进程；`54a1a8bd` 又把 wrapper-lite 调用集中为带 envelope 校验的独立 client，`8980de13` 修复 progressive M4A 的 CMAF conformance 错误。这些变更提高了选择性移植价值，但不解除 Get Oudio 的 CLI、JSONL 和 Temari 阻断。证据见 [`9aaf0f9`](https://github.com/zhaarey/apple-music-downloader/commit/9aaf0f9f7226f1c795715cf708513f3d3e78e934)、[`54a1a8bd`](https://github.com/zhaarey/apple-music-downloader/commit/54a1a8bd75dcd801af8260ab4b3eec9fa1c0bc49) 和 [`8980de13`](https://github.com/zhaarey/apple-music-downloader/commit/8980de13ea40b4a33ad2aac70ece56107acba84f)。

| 项目 | 上游状态 | 对 Get Oudio 的影响 |
| --- | --- | --- |
| wrapper-lite 客户端 | `lite-server` 为单一 base URL；ALAC/Atmos 用 `/key`，AAC-LC/MV 用 `/webplayback` + `/license`，歌词用 `/lyrics` | `internal/wrapper` 现已集中处理 HTTP、body 上限和非零业务 `code`，可作为移植参考，但仍应经 trimmed fork 的 JSONL 事件层输出。[`client.go`](https://github.com/zhaarey/apple-music-downloader/blob/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e/internal/wrapper/client.go) |
| 下载稳定性 | 引入单流式读取修复 4 MiB 停滞，大文件先写 `.part` 并成功后 rename | 是可选择移植的健壮性改进，但需保留现有取消、重试和 progress 心跳。[`b10ddc8`](https://github.com/zhaarey/apple-music-downloader/commit/b10ddc8a6dc7ce32d733c448d36c7887b1f4fd36)、[`runv4.go`](https://github.com/zhaarey/apple-music-downloader/blob/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e/internal/fairplay-rip/runv4.go) |
| CLI 契约 | 仅有 `--atmos`、`--aac`、`--select`、`--all-album`、`--debug`、`--json`、`--save-m3u8-playlist`、`--lite-server` 及质量参数 | `4c8b1328` 仍缺少 `--events=jsonl` 和 `--song`。Get Oudio 每次调用都传前者，带 `?i=` 的单曲还传后者，因此原样 upstream 不可调用。[`run.go`](https://github.com/zhaarey/apple-music-downloader/blob/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e/internal/app/run.go)、[当前 Get Oudio 参数](../../GetOudioCore/Sources/Services/AppleMusicDownloadService.swift#L310-L327) |
| 机器输出 | 普通 `fmt.Print*` 和 progress bar 直接写 stdout，`--json` 只在结尾输出已添加曲目数组 | 不能提供 Get Oudio 需要的 `run_started/item_started/progress/item_completed/item_failed/run_completed`，也无法作为成功汇总真源。[上游 `run.go`](https://github.com/zhaarey/apple-music-downloader/blob/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e/internal/app/run.go)、[Get Oudio 事件消费](../../GetOudioCore/Sources/Services/AppleMusicDownloadService.swift#L150-L200) |
| Temari | `fairplay-rip` 启动时调用 `temari.LoadDefault()`，通过 purego `dlopen` 动态库 | 不是单二进制。复查现场以 `CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath` 编译成功，但产物启动时仍报 `no bundled cdylib for darwin-arm64`，且返回退出码 0。这同时违反 Get Oudio 的单可执行文件、`-trimpath`、错误退出码和成功事件契约。[`runv4.go`](https://github.com/zhaarey/apple-music-downloader/blob/4c8b1328ee1650bcd4be4f67ccb3f1afa977a10e/internal/fairplay-rip/runv4.go)、[当前构建脚本](../../script/build_apple_music_downloader.sh#L20-L48) |
| 测试 | `go test ./...` 在 `4c8b1328` 临时 upstream 副本通过 | 新增 wrapper client 测试是实质改善，但仍未覆盖 packaged binary 定位 Temari 或 Get Oudio 契约，因此不能解除上述阻断。 |

Temari 问题不建议在第一阶段解决。Get Oudio fork 当前的 runv4 是 `CGO_ENABLED=0`、无外部动态库的纯 Go 实现，只需要把 `http://<server>/?...` 改为 `<lite-server>/key?...` 并解析 `data` envelope；这比同时新增 Temari dylib 的定位、嵌入、签名、加载和版本收据更简单。当前 fetch 路径见 [`utils/runv4/amtd.go`](https://github.com/memomoonnnn/apple-music-downloader/blob/2b363b8ab11146c640ce1f889c5af542111f9678/utils/runv4/amtd.go#L45-L113)。

## 建议的分阶段迁移

### 阶段 0：固化制品与安全基线

从 `wrapper-lite@b7058ec5` 构建受控 `linux/amd64` 制品，删除 token 前缀日志，记录源提交、构建配方和 SHA-256；使用可长期下载的自有 Release 或对象存储，不依赖 Actions artifact 或可变 tag。这一阶段不改变 Get Oudio 用户的已安装 runtime。

### 阶段 1：适配 trimmed downloader，不同步大量上游结构

在相邻 fork 增加 `lite-server` 配置和可测试 HTTP client；将 20020 M3U8 查询改为 `/m3u8`，将 40020 模板查询改为 `/key` 并解包 envelope；保留现有纯 Go runv4、`utils/contract`、`utils/events`、`--events=jsonl`、`--song`、敏感文本脱敏、取消和非交互退出。这是能够独立审查的最小 downloader 切片。

### 阶段 2：适配 Get Oudio runtime 并作为同一发布组合验收

更新 wrapper revision/URL/SHA，将容器改为 loopback 12340 单端口，适配新登录命令、2FA 路径、退出码和日志状态机，以 `/status` envelope + 非空 `regions` 替代 40020 HTTP 400 健康检查，修改 `config.yaml.template` 为 `lite-server: "http://127.0.0.1:12340"`。受控 wrapper、downloader 二进制和配置模板必须以同一版本组合验收和发布；更新后保留用户 `rootfs/data`，但清除 `.login-completed` 并明确要求重新初始化。

### 阶段 3：按功能选择上游收益

在第二阶段稳定后，再分别评估 wrapper-lite 的 `/lyrics`、`/webplayback`、`/license`，下载 `.part` 原子完成，以及纯 Go defragment/tag/MV mux。每一项都必须接入现有 JSONL 事件，不得把上游交互输出或转换功能一并带回。只有确认所有 Get Oudio 格式和 MV 路径不再执行 `MP4Box` 后，才能在单独变更中移除 GPAC 组件。

### 阶段 4：可选的模块化重构与 Temari

上游 `internal/` 结构值得作为长期重构参考，但应在已完成协议迁移后独立进行，先将 Get Oudio 的 contract/events 设计为模块边界，再移动业务代码。只有 Temari 能够以已固定、arm64、签名且可由 Runtime Worker 稳定定位的 dylib 交付，并且 packaged-binary 测试覆盖 `-trimpath`、缺失/错版动态库和非零退出码后，才应替换现有纯 Go 解密。

## 验证门槛

每一阶段先在 downloader fork 运行 `go test ./...`、`bash script/verify_get_oudio_build.sh`和 JSONL stdout-exclusive 契约测试；HTTP fixture 至少覆盖成功 envelope、HTTP 200 的非零业务 `code`、缺失字段、超时、`/key` 的 `state >= 0x2004` 和预取 URI 约束。

Get Oudio 端运行 Core tests，覆盖新的容器命令、loopback 端口、2FA 路径、登录快速退出、业务错误、空 `regions`、配置渲染和 JSONL 解析；随后必须通过 `bash script/build_and_run.sh --install` 用授权测试账号执行一次初始化、2FA、`/status` 非空、至少一首 ALAC 和当前 UI 对外提供的每种格式、取消/重试、Agent/Worker 重启和更新后重新初始化。同时检查 wrapper 日志、Docker inspect 和 Get Oudio 诊断日志不含密码、验证码或 token，并从宿主网络状态确认 12340 仅绑定 loopback。

## 最终判断

重新评估后，迁移建议从“等待上游继续收敛”调整为“可以固定 `b7058ec5` 开始受控适配”。默认分支切换、7 天无新提交、无开放 lite PR、最后一次 Actions 全绿，足以说明本轮功能开发已基本收尾；没有 lite Release、制品会过期，且 token 日志、rootless 退出码和 QEMU 凭据落盘问题仍存在，则意味着发布工程与 Get Oudio 安全适配尚未完成。第一步仍应是自建 wrapper 制品、删除 token 日志并适配现有 trimmed fork，而不是整体合并 downloader 上游；官方 QEMU 登录路径不能直接采用。上游 downloader 的 wrapper client、模块化、稳定下载和纯 Go 媒体处理有明确价值，但其 CLI/输出契约和 Temari 打包使原样接入仍不可行。
