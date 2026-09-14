# Launch and Execution Guide

适用于启动路由、Open With、Dock、无窗口入口和 runner。修改前检查 `NormalLauncher.swift`、`BackgroundAgent.swift`、`BackgroundTaskCoordinator.swift`、`RecordingRunner.swift`、Core XPC/队列及 `project.yml`。

Finder Sync、Share Extension、Widget 和 Open With 只解析输入并调用 `BackgroundAgentClient`；不得直接打开队列文件、共享 defaults、Runtime Worker 或 Docker。`BackgroundAgent` 是队列、日常转换、通知派发和可观察状态的唯一所有者；`JobQueueScheduler` 串行认领普通任务，`BackgroundTaskCoordinator` 只执行已领取的批次，不得再增加平行 headless runner。

忙碌时新提交保存在同一 `JobQueue` 的待选择状态，用户确认排队后才可领取；撤回只影响该次提交。批次结束必须继续领取已确认任务，不能依赖后续外部 wake。Agent 开放 XPC 监听前清理上一实例的未完成队列和待选格式任务，不按文件年龄恢复执行；先停止 PID、用户和启动时间均匹配的已记录转换子进程，再记录中断通知并清除任务状态，不删除源文件或输出。进程身份记录仅作用于队列执行期间的 `ProcessRunner` 调用，不能用于终止无关进程。

`GetOudioBootstrapInstaller` 是独立、非沙盒、短生命周期的 `LSUIElement` App，只允许校验 `/Applications/Get Oudio.app`、生成两个用户 LaunchAgent plist、执行 `launchctl bootstrap/bootout` 及删除对应 plist；不得访问 App 容器、Runtime、下载数据或承担后台任务。普通 App 通过 `NSWorkspace` 向内嵌 Installer 发送专用 URL 事件，不得依赖沙盒调用方会被忽略的启动参数。首次启动仅在 Agent 不可用时自动安装；设置页必须同时提供安装、卸载和检查连接入口，不得打开 Terminal 或恢复 `.command` 安装器。

Background Agent 和 Runtime Worker 的 LaunchAgent `ProcessType` 必须为 `Interactive`；两者执行的是用户触发的转换、下载或 runtime 操作，子进程会继承 launchd 调度类型，不得改为会节流 ffmpeg、Colima 或 Docker 的 `Background`。构建和 DMG 脚本必须校验两个 plist 的该字段；修改安装或 plist 后以签名安装产物确认 `launchctl print` 显示 `spawn type = interactive`。

`NormalLauncher` 默认保持 accessory，只有确认显示设置窗口时才升为 regular。Open With 菜单和 URL wake 必须保持无 Dock、无设置窗口；`NormalLauncher` 生成任务后通过 Agent XPC 提交，不执行日常转换。

Audio Bridge 录音由 `getoudio://recording/toggle` 触发。`NormalLauncher` 只校验配置、写共享录音命令、启动新的 `RecordingRunner` 并监督 PID；实时采集、设备切换、WAV 写入、剪贴板和完成通知由无窗口 `RecordingRunner` 执行。异常退出时监督实例依据共享快照恢复原输出并修复临时 WAV，不得把实时音频处理放入设置窗口或 Widget。

Open With 音频使用一次性 `NSMenu`；`OpenWithJobDispatcher` 生成 jobs 并等待 Agent 确认。混合、视频或不支持输入应 `reply(.failure)` 并记录诊断，不得打开设置窗口；不得改回 `NSPanel`、SwiftUI 浮窗或 `WindowGroup`，也不得移除 `LSUIElement = true`。
