# AGENTS.md

本文件是修改本仓库前必须阅读的根级指南。它只定义项目结构、跨域护栏、复用规则、任务路由和验证入口；具体行为约束在 `docs/agent-guides/`。始终以当前 `project.yml`、源码和脚本为真源，不得以本文或历史记录替代现场检查。

## 项目结构与复用

| 位置 | 职责 |
| --- | --- |
| `GetOudioCore/` | 跨进程模型、服务、共享容器、设置、队列、路径和进程执行的唯一归属。 |
| `GetOudio/` | 普通 App 的启动路由、设置模型和 SwiftUI 视图；日常转换由 `HeadlessRunner`，录音由 `RecordingRunner`。 |
| `GetOudioAMRuntimeAgent/` | 受控 Apple Music runtime 及其下载任务。 |
| `GetOudioFinderExtension/`、`GetOudioShareExtension/`、`GetOudioRecordingWidget/` | 仅接收系统输入、写共享状态并唤醒后台，不执行转换、下载或实时音频。 |
| `script/` 与 `project.yml` | 构建、安装和 target 定义；`project.yml` 是 XcodeGen 真源。 |

Core 的 `Models` 定义领域值和协议，`Services` 承担流程与副作用，`Support` 放共享基础设施；App 的 `App` 放生命周期和 runner，`Models` 放页面协调，`Views` 放展示与局部交互。跨页面 UI 原语放在既有 `SettingsUI.swift` 等共享视图文件，不能把服务、队列或权限调用塞进 View。

新增内容前先搜索上述目录和关联测试，优先扩展现有模型、服务、共享机制、组件、交互和术语。跨 target 的状态、路径、协议、权限、队列和进程执行必须进入 Core；仅属于单一入口的适配留在该入口。不得创建平行的 `UserDefaults`、文件路径、任务队列、runner、状态副本或只转发属性/方法的包装层。

新增 UI 或交互前先检查同类设置页、`SettingsUI.swift`、`SettingsDocumentationView.swift` 和 `MainView.swift`。重复使用卡片、间距、说明、侧栏、注意力高亮和交互状态的既有模式；只有行为会被多个页面或入口复用时，才抽到共享 View/Modifier/模型。不得为局部页面重新定义已有视觉语言、完成状态或导航机制。

## 全局边界

可修改源码主要位于上述目录及 `project.yml`。修改 target、sources、resources、Info.plist 注入、entitlements、签名或构建设置时，修改 `project.yml` 并运行 `xcodegen generate`；`GetOudio.xcodeproj/project.pbxproj` 和 `build/` 是生成或本地输出，不能反向作为真源。

不得修改 `.git/`、无关未提交改动、用户 App Group 数据、Apple Music 输出、Keychain 凭据或任务范围外的第三方二进制。App Group 固定为 `group.com.shengjiacheng.GetOudio`；文件系统和共享设置只能经 `SharedContainer` 及其 suite defaults 构造的 `SettingsStore` 访问。`SharedContainer.production()` 失败必须作为可观察错误终止当前入口；`diagnostic(rootURL:defaults:)` 仅用于测试或显式 Debug，Release 不得响应其环境变量，容器解析失败时只写系统日志。新增网络、虚拟化、App Group、文件访问或 Hardened Runtime 能力时，必须同步检查对应 target 的 entitlements，不能以关闭沙盒或移除安全作用域绕过权限。

凭据不得写入 UserDefaults、日志、配置文件或命令诊断输出。完成或失败类通知必须写入 `NotificationEventQueue`，由 `NotificationService.dispatchPendingNotificationEvents()` 的唯一派发器在系统接受请求后确认删除；被拒绝或耗尽重试的事件进入抑制记录。所有本地通知标题固定为 `Get Oudio`，差异写入正文。

## 专项指南路由

开始任务前按改动面阅读下列指南；跨多个改动面时全部阅读。

| 改动面 | 必读指南 |
| --- | --- |
| 启动路由、Open With、Dock、无窗口执行或 runner | `docs/agent-guides/launch-and-execution.md` |
| 设置模型、设置页面、注意力引导、窗口或 SwiftUI/AppKit 布局 | `docs/agent-guides/settings-and-window-ui.md` |
| Audio Bridge、录音 Widget、WAV、缓存或录后处理 | `docs/agent-guides/recording.md` |
| Finder Sync、文件授权、格式分类或默认打开方式 | `docs/agent-guides/finder-and-open-with.md` |
| Share Extension 的激活、输入解析或宿主可见性 | `docs/agent-guides/share-extension.md` |
| Apple Music 组件安装、更新、卸载或 Colima/Lima | `docs/agent-guides/apple-music-runtime-components.md` |
| wrapper、登录、验证码、代理、容器或 40020 就绪状态 | `docs/agent-guides/apple-music-wrapper-and-login.md` |
| Apple Music 下载、JSONL、Agent、通知派发或通知授权 | `docs/agent-guides/apple-music-download-and-notifications.md` |
| 转码预设、ffmpeg 或音频格式能力 | `docs/agent-guides/conversion-tools.md` |
| 内嵌 `apple-music-downloader` 构建或替换 | `docs/agent-guides/apple-music-downloader-build.md` |
| 主图标、Share 图标或 Icon Composer | `docs/agent-guides/icons.md` |
| 通用构建模式、日志机制或诊断环境 | `docs/agent-guides/validation.md` |

## 验证与提交

验证必须匹配改动面：Core 服务、模型、队列、预设、通知协议或 Apple Music 参数运行 `xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test`；Finder Sync 改动构建该 target；安装、签名、Info.plist、entitlements、图标、URL scheme 或扩展嵌入使用 `bash script/build_and_run.sh --install` 并检查相关 `pluginkit` 注册。录音和 Apple Music runtime 的额外验收要求见对应专项指南。不得将 `swift test`、`swift build` 或 `Package.swift` 当作默认入口。

提交前运行 `git status --short`，排除用户已有改动、`build/`、`.DS_Store` 和无关生成差异。除非用户明确要求，不要提交或暂存。

## AGENTS 文档维护

收到“更新 AGENTS.md”或同类指令时，先判断规则的最窄归属：跨仓库结构、复用、数据安全、任务路由或验证入口才更新本文件；领域实现约束更新相应专项指南。规则必须同时是已在当前源码、测试或已完成验收中证实的、可长期复用的、能改变后续实现或验证决策的内容；否则不写入，并说明无需形成持久规则。

不得记录一次性调试过程、临时环境状态、未验证推测、版本事件、故障复盘或与当前代码脱节的参数。每条规则只保留一个权威位置；迁移规则时先写入目标指南再删除旧副本，避免根级摘要与专项细节并存。文档修改后运行 `git diff --check`，并检查改动只覆盖必要内容。
