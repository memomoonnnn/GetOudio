# Apple Music Runtime Guide

本指南适用于 AM Runtime Agent、Colima/Docker、wrapper、下载恢复、代理、凭据和 Apple Music 通知链路。修改前检查 `GetOudioAMRuntimeAgent/Sources/`、Core 中相关 runtime/service/model、Share Extension、entitlements 与 `project.yml`。

## Managed Runtime

Apple Music 重型工具链必须由 `GetOudioAMRuntimeAgent` 管理。启用流程按 Colima、Lima/limactl、Docker CLI、GPAC/MP4Box、wrapper image 五个组件推进；每个组件先验证 managed 文件，失败才重装。安装完成可清理安装包、`.part`、解包目录和可重新获取的 Colima 基础镜像缓存；卸载只清理 managed runtime、短路径 VM 状态、容器及 wrapper 数据，绝不删除用户输出目录。

下载使用 `downloads/*.part` 断点续传。curl 只承担单次传输，不使用 `--retry` 或 `--retry-all-errors`；重试由 Swift 控制，并确认 `.part` 没有异常缩小。Colima/Lima socket 受 `UNIX_PATH_MAX` 限制，`COLIMA_HOME` 与 `LIMA_HOME` 必须使用既持久又短的 `~/Library/Application Support/GetOudio/AM/Colima` 和 `~/Library/Application Support/GetOudio/AM/Lima`，不得改回可被清理的 `Caches`；`limactl` 必须带 `com.apple.security.virtualization` entitlement。Docker 静态包顶层存在同名 `docker` 目录，查找可执行文件时必须验证候选是常规文件，不能只检查名称或 `isExecutableFile`。

## Wrapper State and Credentials

wrapper 状态必须区分镜像、服务容器 `get-oudio-wrapper`、临时登录容器 `get-oudio-wrapper-login` 和 Colima VM。daemon 可查询已存在但停止的容器，因此不能只以 `.State.Running` 判断服务“消失”；服务容器停止时先 `docker start`，仅在启动失败或确实不存在时删除重建。登录容器完成登录后可停止或移除，其不存在不代表服务不可用；Colima 停止导致 `docker ps -a` 或 inspect 无法连接，只说明 VM 未运行。

wrapper 初始化必须保留 `rootfs/data:/app/rootfs/data` 挂载和 `args=-L username:password -F`，但任何日志都必须隐藏含凭据的命令行。验证码只能在 `waitingForVerificationCode` 阶段写入 `rootfs/data/2fa.txt`，初始化前删除旧验证码。系统代理默认关闭；仅用户显式启用时把 macOS 代理转换为 `-P`，loopback host 改写为 Colima 可访问的 `host.lima.internal`。

## Agent Lifecycle and Notifications

AM Runtime Agent 是常驻进程，只重建或替换主 App 不会更新内存中的旧 Agent。统一通过 `script/build_and_run.sh` 启动或安装，它会终止旧主 App 与 Agent，并校验 Build/Products 和 App `Contents/Library/LoginItems` 内嵌副本一致；若从 Xcode 手工运行，验证前必须先终止旧 Agent。启动日志中的 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本用于确认实际处理请求的构建。

Apple Music Share 下载由 Agent 实际执行。完成后 Agent 写入 App Group 的 `NotificationEventQueue`，再唤醒主 App/headless；统一由 `NotificationService.dispatchPendingNotificationEvents()` 认领、派发并确认删除事件。改动通知协议时至少覆盖写入、claim-by-move、确认删除和重复 drain 为空，并检查 `notification event enqueue`、`notification event claim`、`notification scheduled` 与 `[Agent] notification dispatch wake requested` 日志。
