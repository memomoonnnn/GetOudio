# Apple Music Runtime Components Guide

适用于 Apple Music runtime 组件安装、更新、卸载、下载恢复、Colima/Lima 与 component receipt。修改前检查 `GetOudioAMRuntimeAgent/Sources/`、Core runtime 服务、entitlements、`project.yml` 与安装脚本。

重型工具链必须由 `GetOudioAMRuntimeAgent` 管理。启用流程按 Colima、Lima/limactl、Docker CLI、Docker Buildx、GPAC/MP4Box、wrapper image 推进；每个组件先验证 managed 文件，失败才重装。状态刷新只比较本地 receipt/版本，不联网、不安装；安装和更新只由用户发起的“检查并更新”执行，且登录或下载运行时必须拒绝更新。安装完成可清理安装包、`.part`、解包目录和可重新获取的 Colima 基础镜像缓存；卸载只清理 managed runtime、短路径 VM 状态、容器及 wrapper 数据，绝不删除用户输出。

App Bundle 仅携带 `ffmpeg`、`ncmdump` 和 `apple-music-downloader`。Docker CLI、Colima、Lima、GPAC/MP4Box 与 wrapper 镜像安装到 managed runtime，不得改用用户 Homebrew、Docker Desktop、Colima 或 GPAC。外部组件的目标修订、制品哈希、安装方式和 receipt 以 Core 规格为真源；下载、登录或本地 Runtime 操作进行时，安装、更新和卸载由 UI 与模型方法的同一门禁拒绝，并说明原因。

下载使用 `downloads/*.part` 断点续传。curl 只承担单次传输，不使用 `--retry` 或 `--retry-all-errors`；重试由 Swift 控制，并确认 `.part` 没有异常缩小。`COLIMA_HOME` 与 `LIMA_HOME` 必须使用短且持久的 `~/Library/Application Support/GetOudio/AM/Colima` 和 `~/Library/Application Support/GetOudio/AM/Lima`，不能改回 Caches；`limactl` 必须带 `com.apple.security.virtualization` entitlement。Docker 静态包有同名 `docker` 目录，查找可执行文件时确认候选为常规文件，不能只检查名称或 `isExecutableFile`。

验证：运行 Core tests；修改受控组件或服务就绪行为后，签名安装并以授权测试账号验证初始化、40020 空请求 HTTP 400 与一首测试曲下载。
