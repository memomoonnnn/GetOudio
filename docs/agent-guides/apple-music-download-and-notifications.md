# Apple Music Download and Notification Dispatch Guide

适用于 Apple Music 下载、JSONL 事件、Background Agent、Runtime Worker、通知派发、通知授权和通知队列。修改前检查 `BackgroundAgent.swift`、`BackgroundTaskCoordinator.swift`、`GetOudioAMRuntimeWorker/Sources/`、XPC 协议、`AppleMusicDownloadService`、进度解析、`NotificationEventQueue`、`NotificationService`、`NotificationDispatchWaker`、`NotificationAuthorizationModel` 和 Share 下载协调逻辑。

Background Agent 与 Runtime Worker 由用户 LaunchAgent 注册，不使用 `SMAppService`。Background Agent 常驻，Runtime Worker 按 Mach XPC 请求启动并在空闲后退出。主 App 启动后必须校验 Agent 与 Worker 的协议版本、App 版本和构建号；已注册进程与当前 App 不一致时，通过 Bootstrap Installer 重新注册两个 LaunchAgent，但不得恢复用户主动卸载的后台活动。通过 `script/build_and_run.sh` 启动或安装会终止旧主 App 与 Agent，并校验 Build/Products 和 App 内嵌 Worker 与 LaunchAgent 资源一致；Xcode 手工运行前先终止旧 Agent。用 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本确认实际处理请求的构建。

完成或失败事件只能进入 Agent 沙盒控制根的 `NotificationEventQueue`，并由 Background Agent 派发。Runtime Worker 不得提交系统通知或读写通知队列。由于通知由常驻 Agent 进程提交，格式选择和复制信息等通知动作也必须由 Agent 注册 `UNUserNotificationCenterDelegate` 并直接消费；不得依赖系统另行启动普通 App，普通 App 的 delegate 只作为非 Agent 投递路径的兼容入口。`NotificationService.dispatchPendingNotificationEvents()` 是唯一可认领、渲染、提交和确认删除的入口：仅 `UNUserNotificationCenter.add` 成功后确认；提交失败按 2、10、60 秒重试，授权拒绝或耗尽重试后转入 `suppressed`，不得在以后补发过期完成通知。改动协议至少覆盖旧转换事件兼容解码、写入、claim-by-move、确认、重试、抑制、超时回队与重复 wake 幂等性，并检查 `notification event enqueue`、`notification event claim`、`notification scheduled`、`agent Apple Music format action received` 和 `notification dispatch wake requested` 日志。

通知状态由独立的 `NotificationAuthorizationModel` 读取 `UNUserNotificationCenter` 的实时授权设置，不得混入录音模型或持久化为完成状态。Dashboard 的通知权限与麦克风权限共用授权卡片、滚动和高亮；未决定时请求 `.alert` 与 `.sound`，被拒绝时只打开系统“通知”设置页，App 重新激活后刷新状态。开始和进度通知保持即时派发；完成通知的标题、文案、声音、类别和操作 identifier 不得因 Outbox 改造改变。

downloader 的机器协议为 stdout-exclusive 的 `--events=jsonl`。Core 只以结构化事件更新状态，未知总量不得伪造百分比；`item_started` 和阶段切换不得自行生成进度横幅，只有真实 `progress` 心跳可推进并转发共享进度。下载阶段显示百分比，解密和元数据阶段使用状态文案，`run_completed` 的成功/失败曲数是完成汇总真源。Apple Music 的格式选择和完成通知播放提醒音，其余通知静音；失败完成通知仅显示汇总和“复制错误信息”操作，报告由通知响应写入剪贴板。

Agent 和 Worker 的有副作用 XPC 请求必须按 request ID 合并同一进程内的并发重试并复用已完成结果；Agent 转发 Runtime 操作时必须沿用外层 request ID。传输层只能自动重试只读请求，不得在进程失效后自动重放安装、卸载、下载、登录或取消等副作用。凭据仍只能存在于 XPC 内存载荷，不得为跨进程去重落盘完整请求。

忙碌提交的选择通知正文为 `有正在处理的任务...`，操作固定为 `撤回新的任务` 和 `排队处理`，按提交 ID 隔离并保持静音；未选择不执行，通知提醒不可用或提交失败时拒绝该次新提交并向调用入口返回错误。Agent 直接消费操作，普通 App 只经 XPC 转发；重复或过期操作不得重新创建任务。启动时移除旧任务选择和格式选择通知，确有遗留任务才通过 Outbox 派发 `任务异常中断，请重试。`，不得承诺崩溃瞬间送达。Runtime Worker 下载请求的连接失效应进入既有取消路径，不能继续无人持有的下载，也不能取消其他请求的操作。

验证：运行 Core tests；协议改动覆盖队列写入、claim、确认和空 drain，签名安装后以授权测试账号下载一首曲目。
