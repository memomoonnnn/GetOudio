# Validation and Troubleshooting Guide

本指南补充根 `AGENTS.md` 的验证矩阵。始终从最窄、与改动面一致的验证开始，只有改动跨越 App bundle、签名或系统注册边界时才扩大范围。

## Build and Install

`bash script/build_and_run.sh` 构建 unsigned Debug App，并通过 `GET_OUDIO_DIAGNOSTIC_SHARED_CONTAINER_ROOT` 使用 `build/DiagnosticSharedContainer`；`--verify` 验证启动。`--install` 构建并安装签名 App、注册 Finder/Share Extension，严禁设置诊断容器变量；`--clean-plugins` 清理插件注册缓存。缺少工程时脚本会先运行 `xcodegen generate`，DerivedData 固定在 `build/DerivedData`。

Finder Extension 注册检查使用 `pluginkit -m -v -i com.shengjiacheng.GetOudio.FinderExtension`，Share Extension 使用 `pluginkit -m -v -i com.shengjiacheng.GetOudio.ShareExtension`。涉及安装、签名、Info.plist、entitlements、URL scheme、图标或扩展嵌入的改动必须进行签名安装或等价验收，不能用 target-only build 代替系统集成验证。

## Logs

优先查看 App Group 下的 `conversion-log.txt`。Open With 音频/NCM 正常链路先出现 `open with enqueue ...` 和 `open with launch headless ...`，随后是 `headless processing ...`、转换结果及通知事件，不应出现设置窗口路径直接执行的 `app run start ...`。系统日志可按进程使用 `log stream --predicate 'process == "Get Oudio"'`、`GetOudioAMRuntimeAgent`、`GetOudioFinderExtension` 或 `GetOudioShareExtension`。

## Known Diagnostic Traps

沙箱内 unsigned 完整 App 构建或临时 DerivedData 若出现 actool 的 `attempt to insert nil object` 或 `The file “AppIcon” couldn’t be opened`，先判断是否只是验证面过宽触发 Icon Composer 编译；当 Core tests 或 target-only build 已覆盖改动时，不得把无关图标噪声误判为代码回归。

Finder Sync 出现在不支持项上时，同时检查监听目录和 `menu(for:)` 是否在无 actionable 选择时返回 `nil`。Share Extension 在 Safari 可见但 Music 不可见时，先检查签名安装、`pluginkit` 状态并完整重启 Music。AM Runtime 行为仍像旧代码时，先根据 `[Agent] started` 的 PID 和 bundle/executable 路径确认是否仍由常驻旧 Agent 处理。wrapper “消失”时先区分 Colima VM、镜像、停止的服务容器和临时登录容器，不得仅检查 running 状态。

## Final Checks

任何文档改动至少运行 `git diff --check`。修改 `project.yml` 后运行 `xcodegen generate` 并确认 `AppIcon.icon` 文件类型修补仍存在。提交前使用 `git status --short` 与定向 diff 排除用户已有修改、构建输出和无关生成差异。
