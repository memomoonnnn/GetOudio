# AGENTS.md

本文件只定义项目结构、跨域边界和任务路由；具体约束按改动面查阅 `docs/agent-guides/`。以当前 `project.yml`、源码和脚本为真源，按任务需要检查关联实现与测试。

## 项目结构与复用

| 位置 | 职责 |
| --- | --- |
| `GetOudioCore/` | 跨进程模型、XPC 协议、设置、队列、路径和进程执行的唯一归属。 |
| `GetOudio/` | 普通 App UI、`BackgroundAgent`、后台任务协调和 `RecordingRunner`。 |
| `GetOudioBootstrapInstaller/` | 唯一的非沙盒短生命周期安装器，只安装或卸载用户 LaunchAgent，不访问业务数据。 |
| `GetOudioAMRuntimeWorker/` | 唯一的非沙盒 Runtime Worker，执行 Apple Music 组件管理、登录和下载。 |
| `GetOudioFinderExtension/`、`GetOudioShareExtension/`、`GetOudioRecordingWidget/` | 仅解析系统输入并调用 Background Agent XPC，不读写共享容器、不执行转换、下载或实时音频。 |
| `script/` 与 `project.yml` | 构建、安装和 target 定义；`project.yml` 是 XcodeGen 真源。 |

Core 的 `Models` 定义领域值和协议，`Services` 承担流程与副作用，`Support` 放共享基础设施；App 的 `App` 放生命周期和 runner，`Models` 放页面协调，`Views` 放展示与局部交互。View 不承担服务、队列或权限调用。

新增机制前先查找现有实现及关联测试，优先复用已有模型、服务和术语。跨 target 的状态、路径、协议、权限、队列和进程执行归 Core；单一入口的适配留在该入口。不得创建平行的设置、路径、队列、runner 或状态副本。

新增 UI 或交互时复用同类页面及 `SettingsUI.swift` 的现有模式；具体规则见设置指南。

## 全局边界

可修改源码主要位于上述目录及 `project.yml`。修改 target、sources、resources、Info.plist 注入、entitlements、签名或构建设置时，修改 `project.yml` 并运行 `xcodegen generate`；`GetOudio.xcodeproj/project.pbxproj` 和 `build/` 是生成或本地输出，不能反向作为真源。

不得修改 `.git/`、无关未提交改动、历史 App Group 数据、Apple Music 输出、Keychain 凭据或任务范围外的第三方二进制。项目不使用 App Group：App、Agent 和扩展的跨进程通信只经 Mach XPC；控制数据只经 `AgentDataStore.production()` 访问，非沙盒 Runtime Worker 才可经 `AgentDataStore.runtimeWorker()` 访问外部 managed runtime。账号、密码和验证码仅经 XPC 内存载荷及受控 QEMU 标准输入传递，不得落盘或进入命令参数。新增网络、虚拟化、文件访问或 Hardened Runtime 能力时，检查对应 target 的 entitlements，不得以关闭沙盒绕过权限。

凭据不得写入 UserDefaults、日志、配置文件或诊断输出。完成或失败类通知经 `NotificationEventQueue` 和唯一派发器处理，具体规则见下载与通知指南。

## 专项指南路由

按实际改动面查阅相应指南；跨域修改读取所涉及的指南。

| 改动面 | 必读指南 |
| --- | --- |
| 启动路由、Open With、Dock、无窗口执行或 runner | `docs/agent-guides/launch-and-execution.md` |
| 设置模型、设置页面、注意力引导、窗口或 SwiftUI/AppKit 布局 | `docs/agent-guides/settings-and-window-ui.md` |
| Audio Bridge、录音 Widget、WAV、缓存或录后处理 | `docs/agent-guides/recording.md` |
| Finder Sync、文件授权、格式分类或默认打开方式 | `docs/agent-guides/finder-and-open-with.md` |
| Share Extension 的激活、输入解析或宿主可见性 | `docs/agent-guides/share-extension.md` |
| Apple Music 组件安装、更新、卸载或 QEMU 运行时 | `docs/agent-guides/apple-music-runtime-components.md` |
| wrapper、登录、验证码、代理或 12340 就绪状态 | `docs/agent-guides/apple-music-wrapper-and-login.md` |
| Apple Music 下载、JSONL、Agent、通知派发或通知授权 | `docs/agent-guides/apple-music-download-and-notifications.md` |
| 转码预设、ffmpeg 或音频格式能力 | `docs/agent-guides/conversion-tools.md` |
| 内嵌 `apple-music-downloader` 构建或替换 | `docs/agent-guides/apple-music-downloader-build.md` |
| 主图标、Share 图标或 Icon Composer | `docs/agent-guides/icons.md` |
| 通用构建模式、日志机制或诊断环境 | `docs/agent-guides/validation.md` |

## 验证与提交

按改动风险选择验证：Core 行为改动运行 `xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test`；Finder Sync 改动构建该 target；安装、签名、Info.plist、entitlements、图标、URL scheme 或扩展嵌入使用 `bash script/build_and_run.sh --install` 并检查相关 `pluginkit` 注册。录音和 Apple Music runtime 的实际运行验收见对应专项指南。纯文档改动运行 `git diff --check`；不得将 `swift test`、`swift build` 或 `Package.swift` 当作默认入口。

提交前运行 `git status --short`，排除用户已有改动、`build/`、`.DS_Store` 和无关生成差异。除非用户明确要求，不要提交或暂存。

## AGENTS 文档维护

收到“更新 AGENTS.md”或同类指令时，先判断规则的最窄归属：跨仓库结构、复用、数据安全、任务路由或验证入口才更新本文件；领域实现约束更新相应专项指南。规则必须同时是已在当前源码、测试或已完成验收中证实的、可长期复用的、能改变后续实现或验证决策的内容；否则不写入，并说明无需形成持久规则。

不得记录一次性调试过程、临时环境状态、未验证推测、版本事件、故障复盘或与当前代码脱节的参数。每条规则只保留一个权威位置；迁移规则时先写入目标指南再删除旧副本，避免根级摘要与专项细节并存。文档修改后运行 `git diff --check`，并检查改动只覆盖必要内容。
