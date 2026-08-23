# Launch and Execution Guide

适用于启动路由、Open With、Dock、无窗口入口和 runner。修改前检查 `GetOudio/App/NormalLauncher.swift`、`HeadlessRunner.swift`、`RecordingRunner.swift`、相关 Core 队列及 `project.yml`。

Extension 轻、设置窗口轻、Core 复用、后台 runner/Agent 执行。Finder Sync、Share Extension 和 Open With 只能分类输入、写入 `JobQueue` 或共享事件、设置 launch marker，并通过 `getoudio://run-queued` 或新的 headless App 实例唤醒处理；它们不能执行转换、通知派发、下载、Docker 操作或 AM Runtime Agent 请求。

`NormalLauncher` 默认保持 accessory，只有确认显示直接启动的设置窗口时才升为 regular。Open With 音频菜单、NCM 入队、URL wake、notification dispatch 和 `HeadlessRunner` 必须保持无 Dock、无设置窗口。`NormalLauncher` 只处理直接启动设置窗口、Open With 预设选择、NCM Open With 入队和向 `HeadlessRunner` 转交任务，不能承接日常转换。

Audio Bridge 录音由 `getoudio://recording/toggle` 触发。`NormalLauncher` 只校验配置、写共享录音命令、启动新的 `RecordingRunner` 并监督 PID；实时采集、设备切换、WAV 写入、剪贴板和完成通知由无窗口 `RecordingRunner` 执行。异常退出时监督实例依据共享快照恢复原输出并修复临时 WAV，不得把实时音频处理放入设置窗口或 Widget。

Open With 音频不是常规窗口。`application(_:openFiles:)` 对全音频选择显示 `OpenWithPresetMenuController` 的一次性 `NSMenu`，选择后由 `OpenWithJobDispatcher` 生成 `.transcode(preset)` jobs、入队、设置 `LaunchSource.openWithAudio` 并启动 headless；全 NCM 使用 `.convertNCM` 与 `LaunchSource.openWithNCM`。混合、视频或不支持输入应 `reply(.failure)` 并记录诊断，不得打开设置窗口；不得改回 `NSPanel`、SwiftUI 浮窗或 `WindowGroup`，也不得移除 `LSUIElement = true`。
