# Apple Music Download and Notifications Guide

适用于 Apple Music 下载、JSONL 事件、常驻 Agent、完成通知和通知队列。修改前检查 `GetOudioAMRuntimeAgent/Sources/`、`AppleMusicDownloadService`、进度解析、`NotificationEventQueue`、`NotificationService` 和 Share 下载协调逻辑。

AM Runtime Agent 是常驻进程，只重建或替换主 App 不会更新内存中的旧 Agent。通过 `script/build_and_run.sh` 启动或安装会终止旧主 App 与 Agent，并校验 Build/Products 和 App `Contents/Library/LoginItems` 内嵌副本一致；Xcode 手工运行前先终止旧 Agent。用 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本确认实际处理请求的构建。

Apple Music Share 下载由 Agent 执行。完成后 Agent 写入 App Group `NotificationEventQueue` 并唤醒主 App/headless；`NotificationService.dispatchPendingNotificationEvents()` 统一认领、派发并确认删除。改动协议至少覆盖写入、claim-by-move、确认删除和重复 drain 为空，并检查 `notification event enqueue`、`notification event claim`、`notification scheduled` 和 `[Agent] notification dispatch wake requested` 日志。

downloader 的机器协议为 stdout-exclusive 的 `--events=jsonl`。Core 只以结构化事件更新状态，未知总量不得伪造百分比；`item_started` 和阶段切换不得自行生成进度横幅，只有真实 `progress` 心跳可推进并转发共享进度。下载阶段显示百分比，解密和元数据阶段使用状态文案，`run_completed` 的成功/失败曲数是完成汇总真源。Apple Music 的格式选择和完成通知播放提醒音，其余通知静音；失败完成通知仅显示汇总和“复制错误信息”操作，报告由通知响应写入剪贴板。

验证：运行 Core tests；协议改动覆盖队列写入、claim、确认和空 drain，签名安装后以授权测试账号下载一首曲目。
