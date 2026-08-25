# Apple Music Download and Notification Dispatch Guide

适用于 Apple Music 下载、JSONL 事件、Background Agent、Runtime Worker、通知派发、通知授权和通知队列。修改前检查 `BackgroundAgent.swift`、`BackgroundTaskCoordinator.swift`、`GetOudioAMRuntimeWorker/Sources/`、XPC 协议、`AppleMusicDownloadService`、进度解析、`NotificationEventQueue`、`NotificationService`、`NotificationDispatchWaker`、`NotificationAuthorizationModel` 和 Share 下载协调逻辑。

Background Agent 与 Runtime Worker 由用户 LaunchAgent 注册，不使用 `SMAppService`。两者是独立常驻进程，只重建或替换主 App 不会更新内存中的旧 Agent。通过 `script/build_and_run.sh` 启动或安装会终止旧主 App 与 Agent，并校验 Build/Products 和 App 内嵌 Worker 与 LaunchAgent 资源一致；Xcode 手工运行前先终止旧 Agent。用 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本确认实际处理请求的构建。

完成或失败事件只能进入 Agent 沙盒控制根的 `NotificationEventQueue`，并由 Background Agent 派发。Runtime Worker 不得提交系统通知或读写通知队列。由于通知由常驻 Agent 进程提交，格式选择和复制信息等通知动作也必须由 Agent 注册 `UNUserNotificationCenterDelegate` 并直接消费；不得依赖系统另行启动普通 App，普通 App 的 delegate 只作为非 Agent 投递路径的兼容入口。`NotificationService.dispatchPendingNotificationEvents()` 是唯一可认领、渲染、提交和确认删除的入口：仅 `UNUserNotificationCenter.add` 成功后确认；提交失败按 2、10、60 秒重试，授权拒绝或耗尽重试后转入 `suppressed`，不得在以后补发过期完成通知。改动协议至少覆盖旧转换事件兼容解码、写入、claim-by-move、确认、重试、抑制、超时回队与重复 wake 幂等性，并检查 `notification event enqueue`、`notification event claim`、`notification scheduled`、`agent Apple Music format action received` 和 `notification dispatch wake requested` 日志。

通知状态由独立的 `NotificationAuthorizationModel` 读取 `UNUserNotificationCenter` 的实时授权设置，不得混入录音模型或持久化为完成状态。Dashboard 的通知权限与麦克风权限共用授权卡片、滚动和高亮；未决定时请求 `.alert` 与 `.sound`，被拒绝时只打开系统“通知”设置页，App 重新激活后刷新状态。开始和进度通知保持即时派发；完成通知的标题、文案、声音、类别和操作 identifier 不得因 Outbox 改造改变。

downloader 的机器协议为 stdout-exclusive 的 `--events=jsonl`。Core 只以结构化事件更新状态，未知总量不得伪造百分比；`item_started` 和阶段切换不得自行生成进度横幅，只有真实 `progress` 心跳可推进并转发共享进度。下载阶段显示百分比，解密和元数据阶段使用状态文案，`run_completed` 的成功/失败曲数是完成汇总真源。Apple Music 的格式选择和完成通知播放提醒音，其余通知静音；失败完成通知仅显示汇总和“复制错误信息”操作，报告由通知响应写入剪贴板。

验证：运行 Core tests；协议改动覆盖队列写入、claim、确认和空 drain，签名安装后以授权测试账号下载一首曲目。
