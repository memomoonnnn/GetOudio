# Recording Guide

适用于 Pro Tools Audio Bridge、录音 Widget、实时音频、WAV、缓存和录后处理。修改前检查 `RecordingRunner.swift`、`RecordingControlCoordinator`、`RecordingControlStore`、`RecordingPostProcessor`、相关 Core 测试及 `project.yml`。

录音源只支持设置页选定的 `Pro Tools Audio Bridge 2-A` 或 `2-B`，持久化设备 UID，运行时重新解析 AudioDeviceID。开始录音只修改 `kAudioHardwarePropertyDefaultOutputDevice`，不得修改系统提醒音使用的 `kAudioHardwarePropertyDefaultSystemOutputDevice`；监听输出固定为切换前的默认媒体输出。源或监听设备断开、系统睡眠、磁盘写入失败和实时缓冲溢出均进入同一个幂等停止流程并恢复原输出。

Widget 只从 App Group 读取 `RecordingSessionSnapshot` 并打开 `getoudio://recording/toggle`，不能持有音频引擎。默认缓存为共享容器的 `Library/Caches/Recordings`；用户选定缓存位置时，以 security-scoped bookmark 直接访问该目录，缓存统计与清理会管理其中 WAV，设置页必须提示用户专门为 Get Oudio 新建缓存文件夹。指定位置不可用时回退默认缓存。剪贴板写文件 URL，不写 PCM 数据。

输入和监听回调不得分配内存、写磁盘或日志、调度主线程或等待信号量；实时错误只写预分配原子状态，由 Runner 健康检查停止和记录。监听环形缓冲欠载、丢帧及输入回调/PCM 静音必须保留为诊断；静音是合法信号，不能自动停止。若日志出现 `input health` 的“无回调”或“所有 PCM 块静音”，先在“音频 MIDI 设置”刷新该 Bridge 的输入/输出页，再判断路由或代码问题。

录后处理只适用于本录音器完成的 24-bit PCM WAV/RF64，由 Core `RecordingPostProcessor` 流式处理；不得在实时回调中处理，也不得改为 ffmpeg、AVFoundation 离线效果或通用解码。`RecordingPostProcessingOptions` 经 `SettingsStore` 持久化：任一裁切或标准化选项启用即处理，无总开关；阈值为 `-90...0 dBFS`、额外垫付 `0...1000 ms`，默认 `-50 dBFS`、`150 ms`，峰值固定 `-0.1 dBFS`。仅裁切两端所有声道均低于阈值的帧。WAV finalize 与默认媒体输出恢复后，先写缓存临时文件、验证、再原子替换；全程静音、非支持 WAV/RF64 或处理/替换失败时保留原始 WAV，并由 `RecordingRunner` 或异常恢复路径入队录音完成/失败事件，不能直接提交本地通知。

验证：运行 Core tests 并构建 `GetOudioRecordingWidget` target；录后处理覆盖首尾裁切、双声道判定、峰值不削波、全静音/损坏文件回退和原子替换。真实设备链路再签名安装，验证 2-A/2-B、麦克风权限、默认媒体输出恢复、原设备监听、剪贴板 URL 和 Runner 异常退出恢复；target build 不能替代真实设备验收。
