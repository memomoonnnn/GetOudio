# Apple Music Runtime Components Guide

适用于 Apple Music runtime 组件安装、更新、卸载、下载恢复、Colima/Lima 与 component receipt。修改前检查 `GetOudioAMRuntimeWorker/Sources/`、`AppleMusicRuntimeWorkerProtocol.swift`、Core runtime 服务、LaunchAgent plist、`project.yml` 与安装脚本。

重型工具链必须由非沙盒 `GetOudioAMRuntimeWorker` 管理。App 和扩展只调用 Background Agent，Background Agent 再通过 `com.shengjiacheng.GetOudio.runtime-worker` Mach XPC 调用 Worker；不得恢复 Unix Socket、请求文件、任务快照或凭据落盘。状态刷新只比较本地 receipt/版本，不联网、不安装；安装、更新和卸载必须由用户发起，且在登录或下载运行时拒绝。

App Bundle 只携带 `ffmpeg`、`ncmdump` 和 `apple-music-downloader`。Docker CLI、Colima、Lima、GPAC/MP4Box 与 wrapper 镜像安装到 managed runtime，不得使用用户 Homebrew、Docker Desktop、Colima 或 GPAC。外部 managed runtime 固定位于 `~/Library/Application Support/GetOudioV2`，只能由 `AgentDataStore.runtimeWorker()` 解析；App/Agent 控制数据位于沙盒 Application Support，不得为 Runtime 恢复 home-relative 例外、虚拟化或 network-server entitlement。

下载使用 `downloads/*.part` 断点续传；curl 不使用 `--retry` 或 `--retry-all-errors`，重试由 Swift 控制。`COLIMA_HOME` 与 `LIMA_HOME` 使用 `~/Library/Application Support/GetOudioV2/AM/Colima` 和 `~/Library/Application Support/GetOudioV2/AM/Lima`；`limactl` 由 Worker 准备 virtualization entitlement。卸载只清理 managed runtime、VM 状态、容器及 wrapper 数据，不得删除用户输出。

验证：运行 Core tests；修改受控组件或服务就绪行为后，签名安装并以授权测试账号验证初始化、40020 空请求 HTTP 400 与一首测试曲下载。
