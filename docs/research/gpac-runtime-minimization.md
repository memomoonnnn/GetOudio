# GPAC / MP4Box 最小 macOS Runtime 研究

## 结论

项目只调用 MP4Box，但不能把现有动态包直接裁成一个 `MP4Box` 文件。`-itags` 是 ISO BMFF 文件编辑能力；`-add ... -new` 在当前 GPAC 架构中通过 filter session 完成导入和 ISOBMFF mux。动态构建仍需 `libgpac`、其递归 dylib 闭包，以及该构建实际加载的模块或资源。

有可行的缩减路径：固定 GPAC 源码修订并改建为 MP4Box 专用包。官方 macOS 指南把 `./configure --static-bin` 列为“MP4Box only”构建；当前 `configure` 将其定义为 MP4Box/gpac 的静态构建，并同时启用静态模块。`--static-mp4box` 已被标记为兼容别名。这样可消除对独立 `modules/` 目录的运行时依赖，但 macOS 上能否得到单文件仍取决于各第三方库是否可静态链接，不能据此承诺零 dylib。

## 与当前调用的对应关系

GPAC 文档明确把 `-tags` / `-itags` 定义为写入 iTunes tags。文档也说明 MP4Box 的媒体导入、导出已经改由 filter session 驱动，`MP4Box -add source.avc -new test.mp4` 是对应示例。因此，现有音频写 tag 和音视频合成均不能仅以“可启动 MP4Box”为验收。

`--isomedia-only` 是较合适的起点：官方 `configure` 保留 parsers、import、export、`isoff` 与 `isoff-write` 等 ISO BMFF 读写能力，并关闭其他功能；`isoff-write` 的定义就是 ISOBMFF 编辑/写入。它不是本项目所需输入格式的充分证明：具体的音频、视频样本仍可能需要额外 parser 或 filter，必须以真实样本验证。

## 本机临时副本验证（2026-08-22）

未修改 managed runtime。当前官方包目录为 139 MB：`MP4Box` 472 KB、`lib/` 130 MB、`modules/` 3.6 MB、`share/` 4.2 MB。以临时目录复制 `MP4Box` 和完整 `lib/`，完全不复制 `modules/`、`share/`，并将 `GPAC_MODULES_PATH` 指向不存在目录后，以下命令均成功：`MP4Box -version`、对 AAC/M4A 样本的 `-itags`，以及对 H.264 视频和 AAC 音频的 `-add ... -new`。后者产物与完整包产物同为 11,908 bytes；tag 可被 ffprobe 读回。

这个副本仍为 131 MB，只比完整包少约 8 MB。动态加载日志显示该 `MP4Box -version` 实际加载 92 个受控 dylib；这解释了为什么只删除模块和资源不能带来实质缩减。验证样本覆盖当前下载器的两类调用形态，但不包含用户真实 Apple Music 成品，故它只能证明当前构建的 `modules/`、`share/` 对这些路径不是必需项，不能证明任意输入编码都安全。

## 建议的候选构建与验收

先固定一个 GPAC revision，在干净构建目录试验 `./configure --static-bin --isomedia-only`，并只在实测缺失时增加功能或库。若静态链接不完整，则打包 `MP4Box`、`libgpac` 和 `otool -L` 得到的递归非系统 dylib 闭包；不得把宿主机 Homebrew 库作为运行时依赖。

候选包必须从不含原 GPAC 目录、`GPAC_MODULES_PATH` 和 Homebrew 路径的环境运行以下检查：`MP4Box -version`；对真实 Apple Music 音频运行现有 `-itags`；以当前视频和音频输入运行现有 `-add ... -new`；确认产物存在、可再次读取且 tag/轨道完整。现有构建的 `modules/`、`share/` 已通过上述两类临时样本检查；任何新的专用构建仍必须重新验证，且不能仅凭目录名称删除 dylib。

## 不确定性

官方资料确认了构建开关和功能边界，但未承诺任意 macOS SDK、CPU 架构和输入编码下的最终体积。特别是 Apple Music 视频/音频的实际编码与 GPAC revision 会决定最小 filter 集合；应以受控 `linux/amd64` wrapper 之外、当前 macOS Runtime 的真实 MP4Box 调用样本作为最终真源。

## 官方来源

- [GPAC macOS Build Guide](https://github.com/gpac/gpac/wiki/GPAC-Build-Guide-for-OSX)：MP4Box-only 的 `--static-bin` 方式，以及完整构建会引入的依赖。
- [GPAC configure](https://github.com/gpac/gpac/blob/master/configure)：`--static-bin`、`--static-modules`、`--isomedia-only`、`--use-FOO=no` 的当前定义。
- [MP4Box 选项文档](https://github.com/gpac/gpac/wiki/mp4box-gen-opts)：`-tags` / `-itags` 的定义。
- [GPAC rearchitecture](https://github.com/gpac/gpac/wiki/Rearchitecture)：`-add ... -new` 使用 filter session 的运行模型。
