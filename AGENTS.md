# AGENTS.md

本文件是 AI Agent 修改本仓库时必须先读的根级操作指南。它只保留全仓库护栏、任务路由和验证入口；专项实现约束位于 `docs/agent-guides/`，开始相关任务前必须读取对应文件，并以当前 `project.yml`、源码和脚本为最终真源，不得用本文或历史经验替代现场检查。

## Project Overview

Get Oudio 是 XcodeGen 驱动的 macOS 原生音频工具。`GetOudioCore` 承载模型、服务、队列、共享容器和进程执行；Finder Sync、Share Extension、Open With 与录音 Widget 只接收系统输入并转交后台；`HeadlessRunner` 负责日常转换，`RecordingRunner` 负责 Pro Tools Audio Bridge 实时录音，独立的 `GetOudioAMRuntimeAgent` 管理 Apple Music runtime。直接启动 App 才显示设置窗口，其他入口应保持无窗口、无 Dock 干扰。

## Source of Truth and Boundaries

可修改源码主要位于 `GetOudio/`、`GetOudioCore/`、`GetOudioAMRuntimeAgent/`、`GetOudioFinderExtension/`、`GetOudioShareExtension/`、`GetOudioRecordingWidget/`、`script/` 和 `project.yml`。涉及 target、sources、resources、Info.plist 注入、entitlements、签名或构建设置时，`project.yml` 是真源，修改后运行 `xcodegen generate`；`GetOudio.xcodeproj/project.pbxproj` 和 `build/` 是生成或本地输出，不能反向当作源码真源。

不得碰触 `.git/`、与当前任务无关的未提交改动、用户 App Group 数据、Apple Music 输出目录、Keychain 凭据或任务范围外的第三方二进制。文件系统和共享设置统一经 `SharedContainer` 与基于其 suite defaults 构造的 `SettingsStore`，不得在调用点创建 `UserDefaults(suiteName:)`、拼接 `Library/Group Containers` 路径、以 `.standard` 或普通 Application Support 静默降级。新增网络、虚拟化、App Group、文件访问或 Hardened Runtime 能力时必须同步检查对应 target 的 entitlements，不能通过关闭沙盒或移除安全作用域访问绕过权限。

代码改动保持小范围且按职责落位：业务行为优先进入 Core 的 Models/Services 或对应入口源码，进程执行复用 `ProcessRunner` 或现有 runtime 服务，跨进程常量和共享路径进入 Core Support。Extension 只分类、入队、写共享事件和唤醒后台；设置窗口只负责设置；转换、通知派发、下载和 Docker 操作必须由后台 runner 或 Agent 执行。不要为了拆文件增加只转发属性或方法的浅层包装，也不要把 UI 状态、队列消费、权限和进程调用重新揉进一个视图或大 view model。

App Bundle 只携带精简 `ffmpeg`、`ncmdump` 和 `apple-music-downloader`。Docker CLI、Colima、Lima、GPAC/MP4Box 与 wrapper 镜像必须由 AM Runtime Agent 安装到 managed runtime，不得塞回 App Bundle，也不得改用用户系统里的 Homebrew、Docker Desktop、Colima 或 GPAC。内嵌 downloader 的源码由相邻专用 fork `../apple-music-downloader-get-oudio` 维护，本仓库只保存构建产物与 `config.yaml.template`。

## Audio Bridge Recording

录音 Widget 只打开 `getoudio://recording/toggle`；`RecordingControlCoordinator` 经 `RecordingControlStore` 原子预约会话、写命令并监督独立的 `RecordingRunner`，不得让 Widget、设置窗口或普通启动实例持有音频单元。录音 Runner 使用用户保存的设备 UID 绑定输入 AUHAL，将 `DefaultOutputDevice` 暂时切到所选 `Pro Tools Audio Bridge 2-A/2-B`，同时把监听 AUHAL 绑定到切换前的播放设备；不得修改 `DefaultSystemOutputDevice`。macOS 输出和 DAW 输入使用同一 2-A 或 2-B 是 Pro Tools Audio Bridge 的正常用法，不能因为这一拓扑而强制改为双 Bridge。

输入回调、监听回调不得分配内存、写磁盘、写日志、调度主线程或等待信号量；实时错误只写入预分配的原子状态，由 Runner 健康检查统一停止和记录。监听环形缓冲的欠载、丢帧及输入回调/PCM 静音状态必须保留为诊断数据；静音是合法信号，不能自动停止录音。若日志出现 `input health` 的“无回调”或“所有 PCM 块静音”，即使设备仍显示可用，也应先在“音频 MIDI 设置”打开并刷新该 Bridge 的输入/输出页，再判断路由或代码是否有问题。

录后处理只适用于本录音器已完成的 24-bit PCM WAV/RF64 成品，由 Core 的 `RecordingPostProcessor` 流式扫描和写入；不得在实时回调中处理，也不得改用 ffmpeg、AVFoundation 离线效果或任意格式的通用解码路径。`RecordingPostProcessingOptions` 经 `SettingsStore` 的 suite defaults 持久化：开启“去除头尾的无声片段”或“峰值标准化”任一项即处理，无总开关；静音阈值限定 `-90...0 dBFS`、额外垫付限定 `0...1000 ms`，默认分别为 `-50 dBFS` 与 `150 ms`，标准化峰值固定为 `-0.1 dBFS`。裁切仅移除两端所有声道均低于阈值的帧，不得触碰中间静音；处理必须在 WAV finalize、默认媒体输出恢复后、迁移到自定义目录前执行，先写同目录暂存文件并验证后再原子替换缓存成品。全程静音、非受支持 WAV/RF64 或任何处理/替换失败时必须保留原始 WAV，并把回退原因带入完成通知。

## Required Task Guides

开始任务前按改动面读取下列指南；跨多个改动面时读取所有相关文件。

| 改动面 | 必读指南 |
| --- | --- |
| 启动路由、Open With、设置模型、设置窗口、Dock 或 SwiftUI/AppKit 布局 | `docs/agent-guides/app-architecture-and-ui.md` |
| Finder Sync、Share Extension、格式分类、默认打开方式或外置磁盘权限 | `docs/agent-guides/system-integrations.md` |
| Apple Music runtime、Agent、Colima/Docker、wrapper、下载、代理、凭据或通知事件 | `docs/agent-guides/apple-music-runtime.md` |
| ffmpeg、转码预设、图标或内嵌 apple-music-downloader 构建 | `docs/agent-guides/bundled-tools-and-assets.md` |
| 构建、测试、安装、日志、插件注册或已知诊断陷阱 | `docs/agent-guides/validation-and-troubleshooting.md` |

## Global Constraints

App Group 标识固定为 `group.com.shengjiacheng.GetOudio`。任务队列、共享设置、launch marker、诊断日志、通知事件和 Apple Music runtime 必须通过共享容器或 suite defaults 访问。`SharedContainer.production()` 缺少 App Group URL 或 suite defaults 时应抛出可观察错误并关闭当前入口；`diagnostic(rootURL:defaults:)` 只用于测试或显式 Debug 诊断，Release 不得响应 `GET_OUDIO_DIAGNOSTIC_SHARED_CONTAINER_ROOT`。容器解析失败时先写系统日志，不得调用依赖同一容器的 `DiagnosticLog`。

凭据不得写入 UserDefaults、日志、配置文件或命令诊断输出。完成类通知不得依赖正在等待的窗口或客户端进程，应写入 `NotificationEventQueue`，再由 `NotificationService.dispatchPendingNotificationEvents()` 统一派发；Apple Music Share 下载由 Agent 执行，完成后由 Agent 写事件并唤醒主 App/headless 路径。

必须保留 `GetOudio/Resources/AppIcon.icon` 这一 Icon Composer 源资产。不得替换成手工 `.icns`、静态 `AppIcon.appiconset` 或构建位图；源码 Info.plist 只维护 `CFBundleIconName = AppIcon`。Share Extension 独立使用 `GetOudioShareExtension/Resources/icon.icns`，不得让它编译主 App 图标源。

## Validation Matrix

验证范围必须与改动面匹配；不要默认运行沙箱内 unsigned 完整 App 构建，因为它容易把 AppIcon、签名和安装噪声混入无关判断。

| 改动面 | 最低验证 |
| --- | --- |
| 纯文档 | `git diff --check` 与目标文档 diff |
| Core 服务、模型、队列、预设、通知协议、Apple Music 参数 | `xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test` |
| Audio Bridge 录音控制、缓存、WAV、录后处理或实时管线 | Core tests、`GetOudioRecordingWidget` target build；录后处理至少覆盖首尾裁切、双声道判定、峰值不削波、全静音/损坏文件回退与原子替换；涉及真实设备链路时再进行签名安装验证 |
| Finder Sync 菜单或分类入口 | `xcodebuild -project GetOudio.xcodeproj -target GetOudioFinderExtension -configuration Debug build CODE_SIGNING_ALLOWED=NO` |
| App 启动、窗口、扩展嵌入、Info.plist、URL scheme、entitlements、图标或注册 | `bash script/build_and_run.sh --install` 或等价签名构建，并检查相关 `pluginkit` 注册 |
| 本地 unsigned 启动诊断 | `bash script/build_and_run.sh`；启动验证使用 `bash script/build_and_run.sh --verify` |

本仓库不是 SwiftPM 项目，没有统一格式化命令；不得把 `swift test`、`swift build` 或 `Package.swift` 当作默认入口。沙箱内 XCTest 若仅因 `com.apple.testmanagerd.control` 被拒绝而失败，应在非沙箱环境用同一命令复验后再判断代码失败。更具体的命令、日志和验收条件见专项指南。

## Before Commit

提交前运行 `git status --short`，确认只有本任务改动；尤其不要带入用户已有更改、`build/`、`.DS_Store` 或无关生成工程差异。修改 `project.yml` 后运行 `xcodegen generate` 并核对生成结果；替换二进制、修改通知协议或安装相关行为时，必须完成对应专项指南中的附加验证。除非用户明确要求，不要提交或暂存改动。
