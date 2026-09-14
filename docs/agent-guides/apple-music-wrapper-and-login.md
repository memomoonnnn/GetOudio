# Apple Music Wrapper and Login Guide

适用于 wrapper 镜像、服务/登录容器、Apple Music 登录、验证码、代理、容器就绪与 40020。修改前检查 wrapper runtime 服务、Background Agent/Runtime Worker XPC、Core runtime 模型和凭据处理。

wrapper 状态必须区分镜像、服务容器 `get-oudio-wrapper`、临时登录容器 `get-oudio-wrapper-login` 和 Colima VM。daemon 能查询已存在但停止的容器，不能只以 `.State.Running` 判断服务“消失”；服务停止时先 `docker start`，仅启动失败或确实不存在时删除重建。登录容器完成登录后可停止或移除，其不存在不代表服务不可用；Colima 停止导致 Docker 查询失败只说明 VM 未运行。

Apple Silicon 通过 Agent 管理的 Colima VZ + Rosetta 运行受控 `linux/amd64` wrapper；不得改用用户 QEMU、Homebrew 或可变上游镜像标签。更新先停止并删除旧服务和旧镜像，不提供跨修订回滚；必须保留 `rootfs/data:/app/rootfs/data`，更新成功后仅删除 `wrapper-data/.login-completed` 初始化标记，不能删除认证数据。服务容器显式映射 10020、20020、30020、40020；仅在容器仍运行且 `http://127.0.0.1:40020/` 空请求返回 HTTP 400 后，才允许 downloader 调用。账号失效或 key server 未就绪时清除初始化标记并要求重新初始化。

账号、密码和验证码只允许存在于 App → Agent → Worker 的 XPC 请求内存中，不得写入队列、状态快照、UserDefaults 或日志。初始化保留 `rootfs/data:/app/rootfs/data` 挂载和 `args=-L username:password -F`，但日志必须隐藏含凭据命令行。验证码只能在 `waitingForVerificationCode` 阶段写入 host `rootfs/data/data/com.apple.android.music/files/2fa.txt`，写入前创建父目录；初始化前清除该文件和历史错误路径 `rootfs/data/2fa.txt`。登录成功须识别账号缓存完成并监听 40020；停止或移除登录容器的旧日志不能让状态永久停在“正在登录”。系统代理默认关闭，仅用户显式启用时转为 `-P`，loopback host 改写为 `host.lima.internal`。

Worker 在内存中维护登录快照，Agent 维护版本化可观察状态并通过长连接 XPC 事件主动发布；GUI 不得轮询 Worker 或读取 `progress.json`/`wrapper-login-status.json`。Worker 首次返回快照前必须以 wrapper 的只读登录状态校准进程内默认值，不能把新进程初始的 `notInitialized` 当作事实；校准仍须保留 `verificationCodeSubmitted` 不退回 `waitingForVerificationCode` 的保护。Agent 成功读取到空进度时必须发布 `nil`，清除已结束操作遗留的进度。

验证：运行 Core tests；登录或服务就绪改动后签名安装，以授权测试账号完成初始化、40020 空请求 HTTP 400 与一首测试曲下载。
