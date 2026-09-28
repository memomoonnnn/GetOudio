# Apple Music Runtime Components Guide

适用于 Apple Music runtime 安装、更新、卸载、下载恢复与组件收据。修改前检查 Runtime Worker、`AppleMusicRuntimeManager`、`AppleMusicQEMUProcess`、XPC 协议、LaunchAgent、`project.yml` 和安装脚本。

重型运行时只由非沙盒 Runtime Worker 管理；App 和扩展经 Background Agent、Runtime Worker 的 Mach XPC 调用。设置页状态只读本地文件和 receipt，不启动虚拟机、不联网。安装、更新、卸载由用户发起，运行中的登录或下载不得被并发覆盖。凭据与验证码只经 XPC 内存和 QEMU 标准输入传递，不得落盘、写入命令参数或诊断日志。

当前生产路径为固定 SHA-256 的 macOS arm64 wrapper-lite QEMU 发布包，不依赖用户安装的 QEMU、Homebrew、Docker、Colima、Lima 或 GPAC。包与 receipt 位于 `AgentDataStore.runtimeWorker()` 的外部 managed runtime；可写 `wrapper-data/data.img` 独立于版本化程序目录。更新不能覆盖该镜像，不能清理旧 Colima VM 或 `rootfs/data`；旧路径仅供回退，不能参与新路径的就绪判定。下载使用 `downloads/*.part` 断点续传，校验包后才解压和切换目录；损坏的缓存不得重复使用。

QEMU 子进程由 Worker 启动，持久运行时只记录 PID、用户 ID 和内核启动时间；停止前必须复查身份，不能只凭 PID 杀进程。来宾仅向主机 `127.0.0.1:12340` 转发服务，未登录的 `/status` 即使 HTTP 200 也不算就绪，必须同时确认 `code=0` 和非空 `regions`。原始串口输出不能持久化。

验证：运行 Core tests、构建 App/Worker、检查包校验和签名；签名安装后以授权测试账号完成登录、验证码、缓存重启及一首测试曲下载。无账号空 `regions` 启动测试不能替代该验收。
