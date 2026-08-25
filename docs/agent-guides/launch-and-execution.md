# Launch and Execution Guide

适用于启动路由、Open With、Dock、无窗口入口和 runner。修改前检查 `NormalLauncher.swift`、`BackgroundAgent.swift`、`BackgroundTaskCoordinator.swift`、`RecordingRunner.swift`、Core XPC/队列及 `project.yml`。

Finder Sync、Share Extension、Widget 和 Open With 只解析输入并调用 `BackgroundAgentClient`；不得直接打开队列文件、共享 defaults、Runtime Worker 或 Docker。`BackgroundAgent` 是队列、日常转换、通知派发和可观察状态的唯一所有者；`BackgroundTaskCoordinator` 使任务串行认领，不得再增加平行 headless runner。

`NormalLauncher` 默认保持 accessory，只有确认显示设置窗口时才升为 regular。Open With 菜单和 URL wake 必须保持无 Dock、无设置窗口；`NormalLauncher` 生成任务后通过 Agent XPC 提交，不执行日常转换。

Audio Bridge 录音由 `getoudio://recording/toggle` 触发。`NormalLauncher` 只校验配置、写共享录音命令、启动新的 `RecordingRunner` 并监督 PID；实时采集、设备切换、WAV 写入、剪贴板和完成通知由无窗口 `RecordingRunner` 执行。异常退出时监督实例依据共享快照恢复原输出并修复临时 WAV，不得把实时音频处理放入设置窗口或 Widget。

Open With 音频使用一次性 `NSMenu`；`OpenWithJobDispatcher` 生成 jobs 并等待 Agent 确认。混合、视频或不支持输入应 `reply(.failure)` 并记录诊断，不得打开设置窗口；不得改回 `NSPanel`、SwiftUI 浮窗或 `WindowGroup`，也不得移除 `LSUIElement = true`。
