# Settings and Window UI Guide

适用于设置状态、设置页面、注意力引导、窗口、Dock 视觉与 SwiftUI/AppKit 布局。修改前检查相关 Views、设置模型、`NormalLauncher.swift`、`MainView.swift`、`SettingsUI.swift` 与 `project.yml`。

设置状态按职责拆分为 `PresetSettingsModel`、`FinderDirectorySettingsModel`、`NCMSettingsModel`、`DefaultOpenWithSettingsModel` 和 `AppleMusicSettingsModel`；`SettingsViewModel` 只组合共享 `SettingsStore`，页面观察所需窄模型，目录选择统一使用 `DirectoryChooser`。新增状态进入最接近业务职责的模型，不得重新汇总异步状态、系统集成、目录权限与 Apple Music 生命周期。

需要用户完成设置时，统一以 Core 的 `SettingsAttentionItem` 标识。完成状态保留在所属设置的真源中，`SettingsAttentionState.outstandingItems` 只派生侧栏红点和当前页待高亮项，不得另存红点状态。新增项同时定义完成判定、`MainSidebarItem` 映射和目标卡片的 `SettingsAttentionPulseOverlay`；说明项还须列入说明集合，并仅在用户首次展开 `MarkdownDocumentView` 时由 `SettingsStore.openedSettingsDocumentationItems` 持久化，不能把显示或滚动到说明视为已查看。

跨进程定向使用 `SettingsAttentionRequestStore` 的 120 秒、消费一次请求。无窗口入口经 `SettingsAttentionLauncher` 启动普通 App，再由 `NormalLauncher`、`MainView` 和目标卡片完成定位；它不保存完成状态。不得由 `BackgroundAgent` 或 Extension 直接创建设置窗口，也不得用无关通知替代配置引导；系统权限请求仍由对应入口直接发起。Apple Music Share 缺少 runtime 时引导至“依赖安装”，runtime 就绪但未完成登录时引导至“初始化”，其他运行故障才发送中性不可用通知。

`SettingsAttentionPulseOverlay` 必须执行有限的显式亮起/熄灭阶段；结束、任务取消或视图消失时均无动画清除，不能以重复动画叠加独立结束计时。新增设置 UI 前复用 `SettingsSection`、`SettingsForm`、`MarkdownDocumentView`、`MainSidebarRow` 和既有状态模型；只有多个页面确实共享的样式或行为才抽成公共组件。

设置窗口使用自定义 SwiftUI 视觉层与窄 AppKit 窗口控制，不得退回 `NavigationSplitView` 默认侧栏或可见系统标题栏。`NormalLauncher.showSettingsWindow()` 负责 `.fullSizeContentView`、透明 titlebar/背景、内容圆角裁剪、自定义窗口按钮和尺寸限制；`MainView` 负责根背景、悬浮半透明边栏、三点按钮和等距布局；`SettingsForm` 负责内容最大宽度、滚动留白和 `.scrollClipDisabled()`。

布局常量为水平外边距 `22pt`、边栏上/下 `20pt/21pt`、宽度 `272pt`、设置内容最大宽度 `760pt`、窗口圆角 `26pt`、最大内容宽度 `1098pt`。调整时同步检查 `MainView.swift` 与 `NormalLauncher.swift`，保持三处水平间距 `22pt`。创建 `NSHostingController` 后将 `safeAreaRegions` 设为空；`MainView` 使用普通 `HStack` 的上 `20pt`、侧栏下 `21pt` padding，不得以 `.ignoresSafeArea()` 或无界 frame 补偿。背景可单独忽略安全区。最低部署目标 macOS 14.0，不得使用 macOS 26 专属 API；低版本偏差优先调整常量或 `window.maxSize`。
