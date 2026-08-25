# Validation Guide

适用于所有构建、安装、日志与诊断任务。始终从与改动面一致的最窄验证开始，只有跨越 App bundle、签名或系统注册边界时才扩大范围；领域特定验收在对应专项指南中。

`bash script/build_and_run.sh` 构建 Debug App；`--verify` 验证启动。`--install` 构建并安装签名 App，严禁设置诊断容器变量；`--clean-plugins` 清理插件注册缓存。缺少工程时脚本会运行 `xcodegen generate`，DerivedData 固定在 `build/DerivedData`。沙箱内 XCTest 若仅被 `com.apple.testmanagerd.control` 拒绝，应在非沙箱环境以同一命令复验。

诊断日志位于 Agent 沙盒控制根的 `conversion-log.txt`。新增诊断只能使用 `DiagnosticLog.configure(store:)` 和 `DiagnosticLog.append(_:level:)`；普通诊断为 `.debug`，仅汇总结果可为 `.info`。开关关闭时不得创建或追加文件；轮询、菜单刷新、进度/音频回调等高频路径不得逐次写日志，应记录状态转换、聚合结果或由非实时健康检查限频输出。系统日志可按进程使用 `log stream --predicate 'process == "Get Oudio"'`、`GetOudioAMRuntimeWorker`、`GetOudioFinderExtension` 或 `GetOudioShareExtension`。

文档改动运行 `git diff --check`。`project.yml` 改动运行 `xcodegen generate` 并确认 `AppIcon.icon` 文件类型修补仍在；提交前用 `git status --short` 与定向 diff 排除用户改动、构建输出和无关生成差异。
