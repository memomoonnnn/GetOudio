# Validation Guide

适用于所有构建、安装、日志与诊断任务。始终从与改动面一致的最窄验证开始，只有跨越 App bundle、签名或系统注册边界时才扩大范围；领域特定验收在对应专项指南中。

`bash script/build_and_run.sh` 构建 Debug App；`--verify` 验证启动。`--install` 默认以 Release 配置构建并安装自动签名 App，严禁设置诊断容器变量；`--clean-plugins` 清理插件注册缓存。脚本始终先运行 `xcodegen generate`，DerivedData 固定在 `build/DerivedData`。沙箱内 XCTest 若仅被 `com.apple.testmanagerd.control` 拒绝，应在非沙箱环境以同一命令复验。

构建和打包通过 `GET_OUDIO_ARCH` 选择单一架构，默认 `arm64`；保留架构参数不代表 Intel 支持已经完成，切换前必须补齐同架构内嵌工具并单独验收。`script/prepare_bundle_architecture.sh` 在主 App 签名前检查所有 Mach-O，仅裁剪产物内 Sparkle 的多架构切片并按由内到外的顺序重新签名，不得修改 `ThirdParty` 原始文件或依赖缓存。

完整 App 包只保留外层 `Contents/Frameworks/GetOudioCore.framework`。Runtime Worker 保留 Core 链接依赖但不重复嵌入，通过 `@executable_path/../../../../Frameworks` 加载外层 Core；调试必须使用完整 App 包中的 Worker，不能将其单独搬出运行或为独立运行恢复私有 Core 副本。上述构建检查同时验证 Core 唯一性和 Worker 加载路径；遇到旧副本残留应执行 clean build，不得跳过检查。共享的是磁盘上的 framework，Worker 的独立进程、权限和 XPC 边界保持不变。

`bash script/package_dmg.sh` 默认使用 `build/DistributionDerivedData` 做 Release clean build，并生成 `build/GetOudio.dmg`；包内代码采用 ad-hoc 签名，不含开发 provisioning profile，且未公证，不能与证书签名安装视为同一验证条件。修改嵌入布局或签名流程后，应分别检查开发签名产物和 DMG 内 App 的架构、动态库路径及 `codesign --verify --deep --strict`，并验证实际运行链路；磁盘签名有效不等于运行时身份检查或网络访问已通过。

诊断日志位于 Agent 沙盒控制根的 `conversion-log.txt`。新增诊断只能使用 `DiagnosticLog.configure(store:)` 和 `DiagnosticLog.append(_:level:)`；普通诊断为 `.debug`，仅汇总结果可为 `.info`。开关关闭时不得创建或追加文件；轮询、菜单刷新、进度/音频回调等高频路径不得逐次写日志，应记录状态转换、聚合结果或由非实时健康检查限频输出。系统日志可按进程使用 `log stream --predicate 'process == "Get Oudio"'`、`GetOudioBootstrapInstaller`、`GetOudioAMRuntimeWorker`、`GetOudioFinderExtension` 或 `GetOudioShareExtension`。

Bootstrap Installer 改动除 Core tests 外，必须验证内嵌 Installer 无 App Sandbox/App Group entitlement，首次静默安装后两个 plist 与 launchd job 存在，设置页卸载后两者均消失，再安装后 Agent XPC 恢复；整个流程不得启动 Terminal。

文档改动运行 `git diff --check`。`project.yml` 改动运行 `xcodegen generate` 并确认 `AppIcon.icon` 文件类型修补仍在；提交前用 `git status --short` 与定向 diff 排除用户改动、构建输出和无关生成差异。
