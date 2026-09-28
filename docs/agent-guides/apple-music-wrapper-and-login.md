# Apple Music Wrapper and Login Guide

适用于 wrapper-lite QEMU、登录、验证码、代理和服务就绪。修改前检查 `AppleMusicQEMUProcess`、`AppleMusicWrapperRuntime`、Runtime Worker、XPC 模型与 downloader 配置。

新路径使用固定版本的本地 QEMU 包、独立可写 `wrapper-data/data.img` 和单一 `127.0.0.1:12340` HTTP API；不得恢复 Docker 容器、40020 端口或将账号数据放回版本化包。安装和更新保留旧 Colima 数据以供回退，且不将旧 `.login-completed` 标记误认作 QEMU 登录。服务只在 `/status` 返回 `code=0` 且 `regions` 非空时可供 downloader 使用；同端口的未登记进程不能作为受控服务使用。

来宾明确等待账号输入后，Worker 才按行写入用户名和密码；验证码只能在 `waitingForVerificationCode` 阶段另行写入同一标准输入，不创建 `2fa.txt`。输入中的换行必须拒绝。登录串口只在内存中识别阶段和成功标记，不记录原文、令牌前缀或凭据。Worker 空闲退出后，成功标记仅表示登录已完成；实际下载前仍需重新验证服务状态。系统代理默认关闭；用户启用时，将 host loopback 代理地址改写为 QEMU 来宾可访问的 `10.0.2.2`。

Worker 在内存中维护登录快照，Agent 通过版本化 XPC 事件向 GUI 发布；GUI 不轮询 Worker，也不读取状态文件。首次返回快照前从 wrapper 只读状态校准，已提交验证码不能退回“等待验证码”。

验证：Core tests 后签名安装，以授权测试账号完成登录与 2FA，确认再次启动缓存后 `/status` 为非空 `regions`，并下载一首测试曲。
