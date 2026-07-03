# AGENTS.md

本文件是给 AI Agent 使用的项目工作指南。修改此仓库时先读这里，再读 `project.yml`、相关 Swift 源码和脚本；不要把本文当成产品说明书，也不要用猜测替代当前文件内容。

## Project Overview

Get Oudio 是一个 XcodeGen 驱动的 macOS 原生音频转换工具，主 App 负责 SwiftUI/AppKit 界面和任务调度，`GetOudioCore` 承载模型、服务、队列、共享容器和进程执行逻辑，Finder Sync 与 Share 扩展只负责接收系统输入并写入 App Group 队列，Apple Music 的重型 Docker/Colima/wrapper 运行时由独立 `GetOudioAMRuntimeAgent` 管理。

---

## Repository Layout

可以修改的源目录主要是 `GetOudio/App/`、`GetOudio/Models/`、`GetOudio/Views/`、`GetOudioCore/Sources/`、`GetOudioCore/Tests/`、`GetOudioAMRuntimeAgent/Sources/`、`GetOudioFinderExtension/Sources/`、`GetOudioShareExtension/Sources/`、各 target 的 `Info.plist` 与 entitlements、`script/` 和 `project.yml`。涉及 target、资源、签名、Info.plist 注入、entitlements 或构建设置时，`project.yml` 是真源，先改它，再运行 `xcodegen generate`。

自动生成或本地输出目录包括 `GetOudio.xcodeproj/` 和 `build/`。`GetOudio.xcodeproj/project.pbxproj` 由 XcodeGen 生成，除非是在验证生成结果，否则不要把它当作唯一真源手工维护；`build/DerivedData`、`build/TestDerivedData`、`build/IconVerify`、`build/Icon*`、`build/Agent*` 等都是本机构建、测试或图标诊断产物，通常可以删除，不能反向当成源码资产。

不要碰的边界包括 `.git/`、与本任务无关的已有未提交改动、用户本地 App Group 数据、用户配置的 Apple Music 输出目录、Keychain 中的账号凭据，以及 `GetOudio/Resources/ThirdParty/` 中未经明确任务要求的二进制依赖。当前 App Bundle 只应携带精简 `ffmpeg`、`ncmdump` 和 `apple-music-downloader`；Docker CLI、Colima、Lima、GPAC/MP4Box 和 wrapper 镜像必须由 AM Runtime Agent 安装到受控 runtime，不要塞回 App Bundle 或改为使用用户系统里的 Homebrew、Docker Desktop、Colima 或 GPAC。

---

## Development Rules

代码改动保持小范围、分层清晰。业务行为优先落在 `GetOudioCore/Sources/Services/`、`GetOudioCore/Sources/Models/` 或对应 App/Extension 源码中；进程执行放在 `ProcessRunner` 或现有 runtime 服务层，文件系统与 App Group 访问走 `SharedContainer`、`SettingsStore` 或 `UserDefaults(suiteName:)`，不要把 UI 状态、队列消费、权限处理和底层进程调用揉进同一个视图或扩展控制器。

命名沿用现有 Swift 风格：类型用 UpperCamelCase，方法、属性和局部变量用 lowerCamelCase，服务以职责命名为 `*Service`、`*Runtime`、`*Queue`、`*Store` 或 `*Client`，状态枚举和模型放在 `GetOudioCore/Sources/Models/`，跨进程常量和共享路径放在 `GetOudioCore/Sources/Support/`。新增文件应放入与职责一致的目录，并通过 `project.yml` 的 sources 自动纳入 target，而不是临时在 Xcode 工程里拖文件。

依赖规则是“轻量内嵌、重型托管”。App Bundle 内的第三方资源只限当前精简工具链；Apple Music 下载必须经 `GetOudioAMRuntimeAgent`、managed Colima/Docker、GPAC/MP4Box 和 wrapper 链路，主 App 不能直接依赖系统 PATH 中的运行时工具。新增网络、虚拟化、App Group、文件访问或 Hardened Runtime 需求时，必须同步检查对应 target 的 entitlements，不能通过关闭沙盒、移除安全作用域访问或写入普通容器目录来绕过权限。

架构规则是扩展轻、主 App 调度、Core 复用、Agent 执行。Finder Sync 和 Share Extension 只能分类输入、写入 `JobQueue` 或共享事件、设置 launch marker，并通过 `getoudio://run-queued` 唤醒主 App；它们不能执行转换、通知派发、下载、Docker 操作或 AM Runtime Agent 请求。主 App 已运行时 URL scheme 会进入 `NormalLauncher`，后台无窗口路径由 `HeadlessRunner` 处理，`LSUIElement = true` 是避免 Finder/Share 触发窗口闪现的关键配置，不要为了使用 SwiftUI `WindowGroup` 而移除。

---

## Common Tasks

常用命令都在仓库根目录执行。启动开发构建使用 `bash script/build_and_run.sh`，它会在缺少 `GetOudio.xcodeproj` 时先跑 `xcodegen generate`，把 DerivedData 固定写入 `build/DerivedData`，构建 unsigned Debug app 后启动；验证 app 能启动使用 `bash script/build_and_run.sh --verify`；需要安装签名 App 并注册 Finder/Share 扩展时使用 `bash script/build_and_run.sh --install`；清理系统插件注册缓存使用 `bash script/build_and_run.sh --clean-plugins`。

核心测试使用 `xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test`。修改核心服务、模型、队列、转换预设、Apple Music 下载参数、通知事件协议或 App Group 队列时优先跑这条命令；涉及 `NotificationEventQueue` 时至少覆盖事件写入、认领、确认删除和重复 drain 为空的行为。只修改 Finder Sync 菜单生成、分类入口或扩展侧轻量逻辑时，优先跑 `xcodebuild -project GetOudio.xcodeproj -target GetOudioFinderExtension -configuration Debug build CODE_SIGNING_ALLOWED=NO`，避免把无关的主 App 图标、签名或安装链路混入判断。

本仓库没有单独的格式化命令，也不是 SwiftPM 项目；不要把 `swift test`、`swift build` 或 `Package.swift` 当成默认入口。需要重新生成工程时运行 `xcodegen generate`，并检查 `project.yml` 的 `postGenCommand` 是否仍把 `AppIcon.icon` 的 `lastKnownFileType` 修补为 `folder.iconcomposer.icon`。调试日志优先看 App Group 下的 `conversion-log.txt`，通知链路重点关注 `notification event enqueue`、`notification event claim`、`notification scheduled` 和 `[Agent] notification dispatch wake requested`，系统日志按进程使用 `log stream --predicate 'process == "Get Oudio"'`、`process == "GetOudioAMRuntimeAgent"`、`process == "GetOudioFinderExtension"` 或 `process == "GetOudioShareExtension"`。

---

## Constraints

必须遵守 App Group 边界，标识为 `group.com.shengjiacheng.GetOudio`。任务队列、共享设置、转换诊断日志、通知事件和 Apple Music runtime 都应通过共享容器或 suite defaults 访问；扩展、主 App 和 AM Runtime Agent 的沙盒权限不同，新增共享数据时必须确认每个 target 的 entitlements 与可访问路径。完成类通知不能只依赖正在等待的窗口或客户端进程，应优先写入 `NotificationEventQueue`，再由 `NotificationService.dispatchPendingNotificationEvents()` 统一派发；Apple Music Share 下载的实际执行者是 Agent，完成后应由 Agent 写入通知事件并唤醒主 App/headless 做派发。

必须保留 Icon Composer 源资产。`GetOudio/Resources/AppIcon.icon` 是主图标源文件，不能替换成手工 `.icns`、静态 `AppIcon.appiconset` 或构建产物位图；源码 `Info.plist` 只维护 `CFBundleIconName = AppIcon`，构建产物中出现 `CFBundleIconFile = AppIcon` 是 `actool` 补全，不要反向写回源码。Share Extension 使用独立的 `GetOudioShareExtension/Resources/icon.icns` 和 `CFBundleIconFile = icon`，不要让 Share Extension 自己编译 `AppIcon.icon`。

Apple Music runtime 必须可恢复、可验证、可清理。启用流程按 Colima、Lima/limactl、Docker CLI、GPAC/MP4Box、wrapper image 五个组件推进，每个组件先验证 managed 文件，失败才重装；下载使用 `downloads/*.part` 断点续传，curl 只做单次传输，不使用 `--retry` 或 `--retry-all-errors`，重试由 Swift 控制并确认 `.part` 没有异常缩小。安装完成后可清理安装包、`.part`、解包目录和可重新获取的 Colima 基础镜像缓存；卸载只清理 Apple Music managed runtime、短路径 VM 状态、容器和 wrapper 数据，不删除用户 Apple Music 输出目录。

禁止把凭据写入 `UserDefaults`、日志、配置文件或命令诊断输出。wrapper 初始化必须保持 `rootfs/data:/app/rootfs/data` 挂载和 `args=-L username:password -F` 参数，但日志必须隐藏包含 `-L username:password` 的凭据行；验证码只能在 `waitingForVerificationCode` 阶段写入 `rootfs/data/2fa.txt`，每次初始化前应删除旧验证码。系统代理默认关闭，只有用户显式启用时才把 macOS 代理转换为 wrapper 的 `-P` 参数，loopback host 必须改写为 Colima 可访问的 `host.lima.internal`。

---

## Common Pitfalls

Finder Sync 的可见性首先受监听目录控制，不像 Share Extension 那样由内容类型激活规则精确控制。`GetOudioFinderExtension/Sources/FinderSync.swift` 的 `menu(for:)` 是最终决定右键菜单是否显示的路径：选中项经过 `FileCategory.classify(_:)` 过滤后，如果没有可处理的 audio、video 或 ncm 文件，必须直接返回 `nil`，不能返回一个包含禁用项的 `NSMenu`，否则 Finder 仍会在不支持的文件或文件夹上显示 Get Oudio；目录背景、侧边栏等非文件选择默认也应保持 `nil`，混选场景可以只对受支持文件生成动作，但不要扩大到目录、压缩包或普通文档。

Share Extension 的显示与宿主缓存容易误判。系统分享扩展不需要也不能声明只针对 Safari 或 Apple Music，宿主依据 `NSExtensionActivationRule` 与分享内容类型决定是否显示；当前结构化激活字典支持附件、文件、图片、视频、文本和一个 Web URL，不要退回 `TRUEPREDICATE` 或重新加入非标准 `NSExtensionVersion`。`ShareExtension` 应在 `loadView()` 中异步读取 `extensionContext`，同时检查附件中的 `public.url`、`public.plain-text` 和 `NSExtensionItem.attributedContentText`；可见性要用安装后的签名 App 验证，Music 会缓存分享菜单，Safari 可见且 `pluginkit` 启用时应先完整重启 Music 再判断。

AM Runtime Agent 是常驻进程，只重建主 App 或替换 `.app` 不会自动替换已经运行在内存中的旧 Agent。统一通过 `script/build_and_run.sh` 启动或安装，它会先结束主 App 与旧 Agent，并校验 `Build/Products` 中的 Agent 和主 App `Contents/Library/LoginItems` 内嵌副本一致；若手工从 Xcode 运行，在验证新 Agent 行为前也必须先结束 `GetOudioAMRuntimeAgent`。Agent 启动后会在 `conversion-log.txt` 写入 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本，用它判断当前请求究竟由哪个构建处理。

wrapper 状态判断必须区分镜像、服务容器、登录容器和 Colima VM 运行态。Docker/Colima 能在 daemon 启动后查询已存在但未运行的容器，所以不要只用 `.State.Running` 判断 wrapper 是否“消失”；服务容器 `get-oudio-wrapper` 非运行态时优先 `docker start get-oudio-wrapper`，只有启动失败或容器确实不存在时才删除并重建。登录容器 `get-oudio-wrapper-login` 是初始化过程的临时容器，完成登录后可以停止或移除，不能把它不存在误判为 wrapper 服务不可用；若 Colima 当前未运行，`docker ps -a` 或 `inspect` 无法连接 daemon 只说明 VM 停止，不等于镜像或容器缺失。

路径、图标和下载缓存也有历史坑。Colima/Lima socket 受 `UNIX_PATH_MAX` 限制，`COLIMA_HOME` 与 `LIMA_HOME` 必须使用较短的 `~/Library/Caches/GetOudio/Colima` 和 `~/Library/Caches/GetOudio/Lima`；`limactl` 必须带 `com.apple.security.virtualization` entitlement。沙箱内、unsigned diagnostic build 或临时 DerivedData 构建若出现 `actool` 的 `attempt to insert nil object`、`The file “AppIcon” couldn’t be opened`，先判断是否只是验证面过宽触发完整 App 图标编译。Docker 官方静态包顶层本身有名为 `docker` 的目录，查找解包产物时必须验证候选项是常规文件，不能只按文件名或 `isExecutableFile` 判断。

---

## Before Commit

提交前先运行 `git status --short`，确认只包含本任务相关改动，尤其不要因为 `xcodegen generate`、构建验证或用户已有工作把无关 `.xcodeproj`、`build/`、`.DS_Store` 或其他源码变更一起提交。文档或注释改动至少检查 `git diff -- AGENTS.md`；修改 `project.yml` 后应运行 `xcodegen generate` 并检查生成差异是否符合预期。

需要通过的验证取决于改动面。纯文档改动不需要跑完整 Xcode 构建；核心服务、模型、队列、通知事件和 Apple Music 下载逻辑改动必须优先通过 `xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test`；Finder Sync 菜单或分类入口改动至少通过 `xcodebuild -project GetOudio.xcodeproj -target GetOudioFinderExtension -configuration Debug build CODE_SIGNING_ALLOWED=NO`；App 启动、窗口行为、扩展嵌入、Info.plist、URL scheme、entitlements、图标或安装注册改动应通过 `bash script/build_and_run.sh --install` 或等价签名构建，并用 `pluginkit -m -v -i com.shengjiacheng.GetOudio.FinderExtension` 与 `pluginkit -m -v -i com.shengjiacheng.GetOudio.ShareExtension` 确认注册结果。
