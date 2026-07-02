# Get Oudio Agent Guide

本文件是给 AI Agent 使用的项目工作指南。修改此仓库时先读这里，再读 `project.yml`、相关 Swift 源码和脚本；不要把本文当成产品说明书，也不要用猜测替代当前文件内容。

## 项目事实

Get Oudio 是 macOS 原生音频转换工具，主工程由 XcodeGen 的 `project.yml` 生成，真实入口不是 SwiftPM，也不是手写维护的 `.xcodeproj`。工程包含主 App `GetOudio`、共享框架 `GetOudioCore`、Apple Music 后台运行时 `GetOudioAMRuntimeAgent`、Finder Sync 扩展 `GetOudioFinderExtension` 和 Share 扩展 `GetOudioShareExtension`。主 App 负责前台 SwiftUI/AppKit 界面和任务分发，`GetOudioCore` 放置模型、服务、队列、共享容器、依赖检测和进程执行逻辑，两个扩展只负责接收 Finder/系统分享输入并写入 App Group 队列，Apple Music 重型运行时由独立 Agent 管理。

源码中的轻量组件位于 `GetOudio/Resources/ThirdParty/`，当前只应把精简 `ffmpeg`、`ncmdump` 和 `apple-music-downloader` 作为 App Bundle 资源处理。Docker CLI、Colima、Lima、GPAC/MP4Box 和 wrapper 镜像不应重新塞回 App Bundle，它们由 `GetOudioAMRuntimeAgent` 在用户启用 Apple Music 后安装并通过受控环境变量使用，不能回退到用户系统里的 Homebrew、Docker Desktop、Colima 或 GPAC。二进制、GPAC、下载缓存、Docker 配置和 wrapper 数据位于 App Group 的 `AppleMusicRuntime`，但 Colima/Lima 会创建受 `UNIX_PATH_MAX` 限制的 socket，因此 `COLIMA_HOME` 与 `LIMA_HOME` 必须使用较短的 `~/Library/Caches/GetOudio/Colima` 和 `~/Library/Caches/GetOudio/Lima`；`limactl` 还必须以 `com.apple.security.virtualization` entitlement 签名。GPAC 默认从官方 macOS `.pkg` 下载并解包其中自包含的 `GPAC.app/Contents/MacOS`；`GET_OUDIO_GPAC_PACKAGE_URL` 仅用于覆盖默认源，并继续支持项目生成的 tar.gz，主 App 必须通过 IPC 请求把该覆盖值传给不会继承其环境变量的 Agent。

当前 Apple Music 功能的默认状态是关闭。用户点击启用后，安装流程按 Colima、Lima/limactl、Docker CLI、GPAC/MP4Box、wrapper image 五个组件推进；每个组件都会先验证已有 managed 文件，验证通过则跳过下载，验证失败才重装。安装完成后会清空 `downloads` 中的安装包、`.part`、解包目录以及 `colima-cache/caches` 中可重新获取的 Colima 基础镜像缓存；安装中断时则保留仍可续传的下载缓存。卸载只清理 Apple Music managed runtime、短路径 VM 状态、容器和 wrapper 数据，不删除用户设置的 Apple Music 输出目录。

Apple Music 初始化已改为状态机驱动：`wrapper-status` 返回 `notInitialized`、`starting`、`waitingForVerificationCode`、`authenticating`、`authenticated`、`failed`，设置页轮询该状态而不是依赖本地瞬时 UI 状态。`authenticated` 以 `wrapper-data/.login-completed` 和 wrapper 数据目录为准；一旦日志出现 `response type 6`，Agent 要写入完成标记并停止 `get-oudio-wrapper-login`。验证码只能在 `waitingForVerificationCode` 阶段写入 `rootfs/data/2fa.txt`；登录进行中禁止再次点击“开始初始化”，登录完成后初始化板块应禁用并显示完成遮罩。系统代理默认关闭，只有用户显式启用“使用系统代理”时才把 macOS 代理转换为 wrapper 的 `-P` 参数，且 loopback host 必须改写为 Colima 可访问的 `host.lima.internal`。

## 修改原则

优先改源文件而不是生成物。涉及 target、资源、签名、Entitlements、Info.plist 注入或构建设置时，先改 `project.yml`，再运行 `xcodegen generate` 生成项目；不要手工把 `GetOudio.xcodeproj/project.pbxproj` 当作唯一真源修改。涉及业务行为时，优先在 `GetOudioCore/Sources/Services/`、`GetOudioCore/Sources/Models/` 或对应 App/Extension 源码中做小范围变更，并保持现有服务分层，不要把进程执行、文件系统权限、队列消费或 UI 状态混在同一层。

Finder 扩展和 Share 扩展不能执行耗时转换任务，它们只应分类输入并写入 `JobQueue`。两个扩展都通过 `getoudio://run-queued` 唤醒主 App，并在唤醒前写入 App Group 中的启动来源与时间戳；不要为 Share Extension 单独引入直接 `NSWorkspace.openApplication` 的分支，除非有可复现证据证明 URL scheme 在已安装签名 App 中无法拉起主 App。主 App 收到队列任务后由 `AppModel` 调度，后台路径由 `HeadlessRunner` 无窗口执行，前台路径由 `NormalLauncher` 手动创建 `NSWindow` 和 `NSHostingController`。`LSUIElement = true` 是消除 Finder/Share 触发时窗口闪现的关键配置，不能为了让 SwiftUI `WindowGroup` 更方便而移除。

App Group 是跨进程通信边界，标识为 `group.com.shengjiacheng.GetOudio`。任务队列、共享设置、转换诊断日志和 Apple Music runtime 都应通过 `SharedContainer` 或 `UserDefaults(suiteName:)` 访问。扩展、主 App 和 AM Runtime Agent 的沙盒/权限约束不同，新增共享数据时必须确认相应 target 的 entitlements 与访问路径，不要假设扩展能访问主 App 的普通容器目录。

通知链路同样属于 App Group 边界内的跨进程协议。完成类通知不应只依赖某个正在等待的窗口或客户端进程，而应优先写入 `NotificationEventQueue`；该队列位于 App Group 的 `notification-events` 目录，每个事件一个 JSON 文件，派发方通过从 `pending` 原子移动到 `processing` 来认领，通知成功调度后再确认删除。`NotificationService.dispatchPendingNotificationEvents()` 是统一派发入口，`HeadlessRunner`、`NormalLauncher` 和 `AppModel` 在处理 URL scheme 或启动时都应先 drain 积压通知事件；本地 Finder/NCM/转换任务可以在执行进程结束后通过 `enqueueAndDispatchConversionFinished` 写入并立即派发。Apple Music Share 下载的真实执行者是 `GetOudioAMRuntimeAgent`，因此 Share Extension 来源的 Apple Music 下载完成后应由 Agent 写入完成事件，再用 `LaunchSource.notificationDispatch` 和 `getoudio://run-queued` 唤醒主 App/headless 做通知派发；主 App 同步等待 Agent response 只应作为加速路径，不能成为完成横幅的唯一来源。

普通主 App 已经运行时，Finder Sync 或 Share Extension 的 URL scheme 会进入 `NormalLauncher` 而不是重新经过 `main.swift` 的 headless 判定，因此 `applicationShouldTerminateAfterLastWindowClosed` 必须同时考虑通知 action 和 `AppModel.hasActiveBackgroundWork`，避免用户关闭主窗口时中断后台队列任务。Finder Sync 和 Share Extension 的扩展侧入口仍保持轻量：只分类输入、写入 `JobQueue` 或共享事件、设置 launch marker 并打开 URL scheme；不要把通知派发、下载执行、Docker 操作或 AM Runtime Agent 请求塞进扩展进程。

## 图标和资源约束

`GetOudio/Resources/AppIcon.icon` 是 Icon Composer 源文件，应作为动态 `.icon` 封装保留。不要把它替换成手工 `.icns`、静态 `AppIcon.appiconset` 或二次加工位图方案。`project.yml` 通过 `postGenCommand` 将生成的 `project.pbxproj` 中 `AppIcon.icon` 的 `lastKnownFileType` 修补为 `folder.iconcomposer.icon`，并依赖 `ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = default`。源码 `Info.plist` 只维护 `CFBundleIconName = AppIcon`；构建产物中出现 `CFBundleIconFile = AppIcon` 是 `actool` 补全，不要反向写回源码。

如果某次沙箱内、unsigned diagnostic build 或临时 DerivedData 构建出现 `actool` 的 `attempt to insert nil object`、`The file “AppIcon” couldn’t be opened` 等错误，先判断是否只是测试入口触发了完整 App 图标编译。普通业务、模型、服务和队列改动优先跑 `GetOudioCoreTests` 或目标级构建，只有验证图标、签名、扩展嵌入、URL scheme 或安装包时才用完整签名 Release 构建；真实验收标准是最终 App Bundle 中存在 `Contents/Resources/AppIcon.icns`、`Contents/Resources/Assets.car`，且 `Info.plist` 中 `CFBundleIconName` 为 `AppIcon`。

Share Extension 需要独立的 `GetOudioShareExtension/Resources/icon.icns` 和 `CFBundleIconFile = icon`。这是从主 App 的 Icon Composer 构建结果派生的扩展资源，不取代 `AppIcon.icon` 的源资产地位；直接把 `.icon` 加入 `.appex` 目标会使 `actool` 报 `The file “AppIcon” couldn’t be opened` 和 `attempt to insert nil object`，因此不要让 Share Extension 自己编译 Icon Composer 文件。主图标设计发生变化时，应先签名构建主 App，再用生成的 `AppIcon.icns` 更新扩展的 `icon.icns`。

## Share Extension 约束

系统分享扩展不需要也不能声明只针对 Safari 或 Apple Music 等目标应用，宿主依据 `NSExtensionActivationRule` 与分享内容类型决定是否显示。`GetOudioShareExtension` 当前采用与 LocalSend macOS 扩展一致的 Version 2 结构化激活字典，明确支持附件、文件、图片、视频、文本和一个 Web URL；不要退回 `TRUEPREDICATE`，也不要重新加入非标准的 `NSExtensionVersion`。扩展目标必须保留 `com.apple.share-services`、`$(PRODUCT_MODULE_NAME).ShareExtension`、独立图标和 Hardened Runtime。

`ShareExtension` 是 `NSViewController`，应在 `loadView()` 中立即开始异步读取 `extensionContext`，不要等待 `viewDidAppear()`，因为不同宿主不保证以相同方式展示扩展视图。输入既要检查附件中的 `public.url` 和 `public.plain-text`，也要检查 `NSExtensionItem.attributedContentText`，再从文本中提取 URL；扩展只能把识别为 Apple Music 的 URL 写入 App Group 队列，不能在扩展进程中执行下载。修改这一流程时保留附件 UTI 与提取结果的诊断日志，以便确认新系统或宿主实际传入的数据。

Share Extension 的可见性必须使用安装后的签名 App 验证。运行 `bash script/build_and_run.sh --install` 后，脚本会注册并启用 `com.shengjiacheng.GetOudio.ShareExtension`，应再用 `pluginkit -m -v -i com.shengjiacheng.GetOudio.ShareExtension` 确认记录指向 `/Applications/Get Oudio.app`。Safari 通常会动态刷新分享服务，但 Music 会在进程内缓存分享菜单；如果 Get Oudio 已能在 Safari 中显示、`pluginkit` 也显示为启用，而 Music 中只有 LocalSend 等旧服务，先完整退出并重新启动 Music，再判断配置是否仍有问题。仅凭已运行 Music 的旧菜单不能得出扩展不支持 Apple Music 的结论。

## 关键代码路径

主要 UI 和入口位于 `GetOudio/App/`、`GetOudio/Models/` 和 `GetOudio/Views/`。`main.swift` 决定进入无窗口 `HeadlessRunner` 还是前台 `NormalLauncher`；`AppModel` 是 `@MainActor` 状态中心；`SettingsViewModel` 管理设置页状态；`AppleMusicSetupView` 处理 Apple Music 初始化交互。核心服务在 `GetOudioCore/Sources/Services/`，其中 `AudioConversionService`、`MediaExtractionService`、`NCMConversionService`、`AppleMusicDownloadService` 分别处理重编码、视频提取、NCM 转换和 Apple Music 下载，`ProcessRunner` 统一封装进程执行，`DependencyManager` 负责内嵌轻量依赖检测，`AppleMusicRuntimeAgentClient`、`AppleMusicRuntimeManager`、`AppleMusicWrapperRuntime` 和 `ColimaDockerRuntime` 负责 Apple Music managed runtime 链路。共享模型在 `GetOudioCore/Sources/Models/`，跨进程支持在 `GetOudioCore/Sources/Support/`。

转换预设由 `ConversionPreset` 生成 ffmpeg 参数和输出路径，输出文件名使用 `原文件名 [预设名].扩展名` 以避免覆盖。音频重编码显式选择第一条音频流并复制全局元数据，视频提取默认无损复制音频流，NCM 转换通过内嵌 `ncmdump` 逐项处理。Apple Music 下载必须经 AM Runtime Agent 和 managed Docker/Colima 链路，不要让主 App 直接依赖系统 PATH 中的运行时工具。wrapper 初始化必须保持原项目的 `rootfs/data:/app/rootfs/data` 挂载和 `args=-L username:password -F` 参数，但登录容器要以 `get-oudio-wrapper-login` 后台容器运行，不能带 `--rm`，使 Agent 能在登录过程中继续处理验证码 IPC；验证码写入同一挂载目录下的 `2fa.txt`，每次初始化前应删除旧验证码。正式下载服务容器为 `get-oudio-wrapper`，端口映射为 `10020`、`20020`、`30020`，启动前必须确认登录状态已持久化。Colima 当前使用 1GiB 数据盘和 6GiB 根盘；两者的文件逻辑大小不等于实际占用，但根镜像解压后约 3.5GiB，不能按 wrapper 镜像大小把整个 VM 限制到数百 MB。

## 构建和验证

常用命令在仓库根目录执行。`script/build_and_run.sh` 会把 DerivedData 固定写入 `build/DerivedData`，因此 `build/` 体积增长是预期现象，通常是可删除的本地构建缓存，不是源码资产。

```bash
xcodegen generate
bash script/build_and_run.sh
bash script/build_and_run.sh --verify
bash script/build_and_run.sh --install
bash script/build_and_run.sh --clean-plugins
xcodebuild -project GetOudio.xcodeproj -scheme GetOudioCoreTests -configuration Debug -derivedDataPath build/DerivedData test
```

修改核心服务、模型、队列或通知事件协议时优先跑 `GetOudioCoreTests`；涉及 `NotificationEventQueue` 时至少覆盖事件写入、认领、确认删除和重复 drain 为空的行为。修改 App 启动、窗口行为、扩展嵌入、Info.plist、URL scheme、entitlements、图标或安装注册时，再跑 `script/build_and_run.sh --install` 或等价签名构建，并检查 Finder/Share 扩展注册。调试日志优先看 App Group 下的 `conversion-log.txt`，通知链路还应关注 `notification event enqueue`、`notification event claim`、`notification scheduled`、`[Agent] notification dispatch wake requested` 等日志，再按进程使用 `log stream --predicate 'process == "Get Oudio"'`、`process == "GetOudioAMRuntimeAgent"`、`process == "GetOudioFinderExtension"` 或 `process == "GetOudioShareExtension"`。

`GetOudioAMRuntimeAgent` 是常驻进程，只重建主 App 或替换 `.app` 不会自动替换已经运行在内存中的旧 Agent。统一通过 `script/build_and_run.sh` 启动或安装，它会先结束主 App 与旧 Agent，并校验 `Build/Products` 中的 Agent 和主 App `Contents/Library/LoginItems` 内嵌副本一致；若手工从 Xcode 运行，在验证新 Agent 行为前也必须先结束 `GetOudioAMRuntimeAgent`。Agent 启动后会在 `conversion-log.txt` 写入 `[Agent] started`、PID、bundle 路径、可执行路径和诊断版本，用它判断当前请求究竟由哪个构建处理。

Apple Music runtime 安装必须支持恢复：每次启动安装时先用轻量版本命令验证现有 Colima、Lima、Docker CLI 和 MP4Box，验证通过的组件直接跳过；Lima 组件必须同时包含 `bin/lima`、`bin/limactl` 和 `share/lima`，因为 Colima 的依赖检查直接查找 `lima`。下载文件使用 `downloads/*.part` 断点续传，curl 只负责单次传输，不使用 `--retry` 或 `--retry-all-errors`；重试循环由 Swift 控制，目前最多 9 次，每次失败后必须确认 `.part` 没有异常缩小。只有传输完成后才移动为正式缓存，解包或执行检验失败时删除正式缓存。每个组件完成、跳过或失败后都要把进度和 `componentStatuses` 原子写入 IPC 进度文件，设置页轮询时同步刷新依赖状态，不能只更新进度文案。

wrapper 镜像是启用流程的第五个组件，不应延迟到账号初始化时才首次拉取。四个本地运行时验证完成后，Agent 启动 managed Colima；Apple Silicon 按 `linux/arm64` 拉取 `ghcr.io/itouakirai/wrapper:arm`，Intel 按 `linux/amd64` 拉取 `ghcr.io/itouakirai/wrapper:x86`。只有对应架构镜像也验证可用后才能写入启用状态并清空 `downloads` 中的安装包、`.part` 和残留解包目录。任一步骤失败时保留下载缓存以支持续传。wrapper 诊断日志可以记录容器状态、镜像架构和过滤后的 wrapper 日志，但必须过滤 Android linker 噪声并隐藏包含 `-L username:password` 的凭据行。

wrapper 状态判断必须区分镜像、服务容器、登录容器和 Colima VM 运行态。Docker/Colima 能在 daemon 启动后查询已存在但未运行的容器，因此不要只用 `.State.Running` 判断 wrapper 是否“消失”；服务容器 `get-oudio-wrapper` 应先 `docker inspect -f {{.State.Status}}`，状态为 `running` 时直接复用，状态为 `created`、`exited`、`stopped` 等非运行态时优先 `docker start get-oudio-wrapper`，只有启动失败或容器确实不存在时才删除并重建。登录容器 `get-oudio-wrapper-login` 是初始化过程的临时容器，完成登录后可停止或移除，不能把它不存在误判为 wrapper 服务不可用；持久登录态以 `.login-completed` 和 wrapper 数据目录为准。若 Colima 当前未运行，`docker ps -a`/`inspect` 无法连接 daemon，这只能说明 VM 停止，不能等同于镜像或容器缺失；已启用且 managed Docker/Colima 均存在时，状态 UI 应显示为可按需启动，并在实际下载前通过 `ColimaDockerRuntime.ensureRunning()` 启动后复查。

## 常见风险

不要把 `build/`、`DerivedData`、IconVerify、TestDerivedData 等本地产物当成源文件；真正图标源是 `GetOudio/Resources/AppIcon.icon`。不要因为 `.xcodeproj` 有变更就自动覆盖用户改动，当前工作区可能存在未提交的人工或其他 Agent 变更，修改前后都要用 `git status --short` 确认范围。不要在 Finder/Share 扩展中引入长任务、网络下载或 Docker 操作；不要让 Apple Music runtime 使用用户全局工具；不要移除沙盒、App Group 或安全作用域访问逻辑来绕过权限问题；不要把 Keychain 中的 Apple ID/密码迁移到 `UserDefaults`、日志或配置文件。Docker 官方静态包顶层本身有一个名为 `docker` 的目录，查找解包产物时必须验证候选项是常规文件，不能只按文件名或 `isExecutableFile` 判断；日志中若 `bin/docker` 的大小接近目录项、包含 `_CodeSignature` 或显示 `isDirectory=true`，说明运行的仍是旧安装逻辑或旧 Agent。
