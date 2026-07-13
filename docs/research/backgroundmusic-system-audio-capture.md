# BackgroundMusic 系统音频采集架构调研

调研对象为 `kyleneideck/BackgroundMusic` 的 `master` 分支提交 `8c25450e9b0d3867417c4872018b03fb30c0c85c`（2026-07-10 取得）。本说明只用于定位 Get Oudio 的 Pro Tools Audio Bridge 录音与监听问题，不引入该项目的驱动代码。

## 结论

BackgroundMusic 不是通过普通 App API 从 macOS 的默认输出设备“偷听”系统混音。它随 App 提供一个 AudioServerPlugIn 虚拟设备：音频客户端向该设备的输出端写入混音，驱动在 `WriteMix` 回调中把交错的双声道 Float32 写进自己的环形缓冲；录音客户端从同一设备的输入端读取时，驱动在 `ReadInput` 回调按样本时间取回该缓冲。它的 README 要求录音软件把 `Background Music` 选为输入设备，也印证了这一点。[README 54-61](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/README.md#L54-L61)；[BGM_Device.cpp 1408-1531](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMDriver/BGMDriver/BGM_Device.cpp#L1408-L1531)；[BGM_Device.cpp 1546-1605](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMDriver/BGMDriver/BGM_Device.cpp#L1546-L1605)。

因此，Get Oudio 不应移植或依赖 BackgroundMusic 的 driver。Avid 的“每个设备只能用作输入或输出”是 Pro Tools Aux I/O 配置约束，不能外推为“macOS 向 `2-A` 输出时，另一个 Core Audio 客户端永远无法从 `2-A` 读取”。正常手动工作流正是 `macOS 输出 -> 2-A -> Pro Tools Aux I/O Input`。[Pro Tools Reference Guide 2025.6，Pro Tools Audio Bridge](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_2025.6.pdf)；[Avid Aux I/O FAQ](https://kb.avid.com/pkb/articles/en_US/Knowledge/Auxiliary-IO-Frequently-Asked-Questions?popup=true&retURL=%2Fpkb%2Farticles%2Fen_US%2Ffaq%2Fen422991)。

当前机器的设备级实测表明：直接向 `2-A` 输出 48 kHz 正弦波时，`AudioDeviceIOProc` 会收到输入回调但全部样本为零。这与 Pro Tools 未运行、或未将 `2-A` 激活为 Aux I/O Input 的状态一致，而不足以否定用户已在 Pro Tools 内手动验证的同一实例工作流。当需要录制 Pro Tools 内部与系统声之后的返回信号时，可以使用 `2-B` 作为 Pro Tools Aux I/O Output，但这是另一个可选路由，而不是录制系统声所必需的双 Bridge 前提。

## BackgroundMusic 如何跨设备监听

它为虚拟输入设备和真实输出设备各创建一个 `AudioDeviceIOProcID`，输入回调只采集、输出回调只播放，并显式关闭每一侧不用的流。[BGMPlayThrough.cpp 252-318](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/BGMApp/BGMPlayThrough.cpp#L252-L318)。开始时会把虚拟设备的采样率和 I/O buffer size 对齐真实输出设备；该项目也把这条路径限定为其自有虚拟设备。[BGMPlayThrough.cpp 116-161](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/BGMApp/BGMPlayThrough.cpp#L116-L161)。

两个 IOProc 不假设回调在同一线程或同步发生。输入回调用输入时间戳将数据写入预分配的 `CARingBuffer`；输出回调用输出时间戳和首个输入数据计算读写头偏移，并在时钟漂移、设备重启或读头越界时重新定位，取不到数据则输出静音而不是重复旧缓冲。[BGMPlayThrough.cpp 798-865](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/BGMApp/BGMPlayThrough.cpp#L798-L865)；[BGMPlayThrough.cpp 867-1006](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/BGMApp/BGMPlayThrough.cpp#L867-L1006)。环形缓冲按帧时间而非简单生产/消费计数保存有效范围，使用发布计数取得一致快照。[CARingBuffer.h 75-121](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/PublicUtility/CARingBuffer.h#L75-L121)；[CARingBuffer.cpp 156-240](https://github.com/kyleneideck/BackgroundMusic/blob/8c25450e9b0d3867417c4872018b03fb30c0c85c/BGMApp/PublicUtility/CARingBuffer.cpp#L156-L240)。

## 对 Get Oudio 的直接约束

当前任务的采集端应只把 Audio Bridge 明确当作输入设备读取；若真实 Pro Tools 信号仍为零，问题首先在 Bridge 的输入流是否真的被 Pro Tools 填充、设备方向/stream format 是否正确，而不在 WAV 封装。必须分别记录采集回调的帧数、峰值/RMS、`AudioTimeStamp.mSampleTime` 和 `mHostTime`，以区分“回调未触发”“回调触发但设备给零”和“写盘后变零”。

监听端是独立设备时，不能只用固定大小 FIFO 把 Bridge 的回调块直接交给原物理输出。两设备可有不同 I/O 周期、采样时间重置和时钟漂移；应以各自回调时间戳建立读头关系，预分配足以覆盖启动与时钟差的帧时间环形缓冲，欠载时填零并记录一次欠载，不能回放上一次数据。BackgroundMusic 为它自己可控的虚拟输入设备同步采样率和 buffer size；Get Oudio 不能假定 Pro Tools Audio Bridge 和任意物理监听设备支持同一客户端格式，若格式或标称采样率不一致，还需要明确的实时采样率转换。

BackgroundMusic 也说明了一个边界：它把自己驱动的输出混音回环到同一驱动的输入端；它的跨设备 play-through 是另一个 App 组件。Get Oudio 监听必须从采集流的只读副本输出到原物理设备，绝不能写回当前被采集的 Bridge 实例，否则会构成反馈环。
