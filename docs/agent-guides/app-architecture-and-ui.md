# App Architecture and UI Guide

本指南适用于启动路由、Open With、设置状态、设置窗口、Dock 行为和 SwiftUI/AppKit 布局改动。开始修改前检查 `GetOudio/App/NormalLauncher.swift`、相关 Views、设置模型以及当前 `project.yml`。

## Launch and Execution Boundaries

架构边界是 Extension 轻、设置窗口轻、Core 复用、后台 runner/Agent 执行。Finder Sync、Share Extension 和 Open With 只能分类输入、写入 `JobQueue` 或共享事件、设置 launch marker，并通过 `getoudio://run-queued` 或新的 headless App 实例唤醒处理；它们不能执行转换、通知派发、下载、Docker 操作或 AM Runtime Agent 请求。

`NormalLauncher` 默认保持 accessory，只有确认显示直接启动的设置窗口时才升为 regular，使设置窗口在 Dock 中出现。Open With 音频菜单、NCM 入队、URL wake、notification dispatch 和 `HeadlessRunner` 应保持无 Dock、无设置窗口。`NormalLauncher` 只处理直接启动设置窗口、Open With 音频菜单式预设选择、NCM Open With 入队和向 `HeadlessRunner` 转交任务，不能承接日常转换。

Open With 音频不是常规窗口。`application(_:openFiles:)` 对全音频选择应显示 `OpenWithPresetMenuController` 的一次性 `NSMenu`，选择后由 `OpenWithJobDispatcher` 生成 `.transcode(preset)` jobs、入队、设置 `LaunchSource.openWithAudio` marker 并启动新的 headless 实例；全 NCM 选择生成 `.convertNCM` jobs 并使用 `LaunchSource.openWithNCM`。混合、视频或 unsupported 输入应 `reply(.failure)` 并记录诊断日志，不得打开设置窗口。不得把菜单退回 `NSPanel`、SwiftUI 浮窗或 `WindowGroup`，也不得移除维持这条边界的 `LSUIElement = true`。

## Settings Models

设置状态按职责拆分为 `PresetSettingsModel`、`FinderDirectorySettingsModel`、`NCMSettingsModel`、`DefaultOpenWithSettingsModel` 和 `AppleMusicSettingsModel`；`SettingsViewModel` 只是共享 `SettingsStore` 的组合入口，具体页面观察所需窄模型，目录选择统一使用 `DirectoryChooser`。新增状态进入最接近业务职责的模型，不得重新汇总异步状态、系统集成、目录权限与 Apple Music 生命周期。

## Window Contract

设置窗口采用自定义 SwiftUI 视觉层与窄 AppKit 窗口控制，不得退回 `NavigationSplitView` 默认侧栏或可见系统标题栏。`NormalLauncher.showSettingsWindow()` 负责 `.fullSizeContentView`、透明 titlebar/窗口背景、内容圆角裁剪、自定义窗口按钮和尺寸限制；`MainView` 负责根背景、悬浮半透明边栏、自定义三点按钮和等距布局；`SettingsForm` 负责内容最大宽度、滚动留白及 `.scrollClipDisabled()`。

当前布局常量为外边距 `22pt`、边栏宽度 `272pt`、设置内容最大宽度 `760pt`、窗口圆角 `28pt`，最大内容宽度为 `22 + 272 + 22 + 760 + 22 = 1098pt`。调整任一常量时必须同步检查 `MainView.swift` 与 `NormalLauncher.swift`，保持边栏左/上/下边距、边栏到内容距离和内容到右边界距离相等。最低部署目标为 macOS 14.0；不得引入 macOS 26 专属 API。低版本出现轻微安全区或最大宽度偏差时，优先调整常量或 `window.maxSize`，不要重写窗口架构。
