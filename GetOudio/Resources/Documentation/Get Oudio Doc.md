# 概览

「Get Oudio」是为音频工作者们开发的实用性工具。软件做了一些微小的工作，集成了一些优秀的开源项目，并使它们可以在MacOS上被方便地调用，感谢这些开发者的无私奉献！

过去类似Permute、Downie这样的软件，你需要先打开窗口、拖放文件、设定参数再启动进程，完成任务后还要手动退出，这种交互设计在我看来非常愚蠢。于是「Get Oudio」参考了一众解压缩软件的设计逻辑，将操作入口集成在MacOS本身的组件中，全程没有任何窗口干扰，只有右上角的横幅通知告知你进程状态，就好像Mac天生就自带这个功能一般。

![300](attachments/Get%20Oudio%20Doc/file-20260704034608541.webp)

关于各个功能的使用教程，请切换左侧边栏，在不同的设置页中一一查看。必须先完成的通用设置在下方：

- 「Get Oudio」提供的拓展包括“共享”和“文件提供程序”，“共享使你可以在Apple Music”中分享URL到「Get Oudio」；文件提供程序则使你可以在访达的右键菜单中找到「Get Oudio」。
- 「Get Oudio」的菜单拓展只能访问被监听目录列表下的文件，监听列表以外的目录中不会出现菜单，这是MacOS的限制所致。此外，不推荐将外置硬盘添加到监听列表中，这会让你的外置硬盘图标变成丑陋的「Get Oudio」图标。

另外，这个设置窗口的背景是透明的，请不要把窗口放在白色背景上，这会使GUI变得难以辨别。

![500](attachments/Get%20Oudio%20Doc/file-20260704104612639.jpeg)

# Re-Encoding

依靠[FFmpeg](https://github.com/FFmpeg/FFmpeg)，现在仅需在访达中右键支持的音频文件（支持多个），并选择Get Oudio子菜单中的预制，即可重编码到当前目录：

![500](attachments/Get%20Oudio%20Doc/file-20260704034734987.webp)

如果是视频文件，则可以遵循原始编码提取其音频轨，遵循原始格式：

![300](attachments/Get%20Oudio%20Doc/file-20260704034835540.webp)

你还可以将特定音频格式文件的打开方式设为「Get Oudio」，这样当你双击音频文件，光标位置就会浮现目标编码列表，选择后即可开始进程。

![200](attachments/Get%20Oudio%20Doc/file-20260704035014628.webp)

一定程度上，这并不影响你播放并聆听音频，因为QuickTime的空格预览仍然生效，这操作远比双击打开一个新的QuickTime窗口要常用得多：

![400](attachments/Get%20Oudio%20Doc/file-20260704035158344.webp)

受支持的编码包括AAC、MP3、Vorbis、Opus、ALAC/FLAC和PCM。需要说明：

- AAC和MP3的输出预设只包含不同的码率。即便它们本来支持不同的采样率，但我们往往不会在意它；并且由于DAW在导入这类有损压缩音频时，会自动解码成当前工程采样率的PCM编码，所以它们的采样率并不会带来不便。
- Vorbis使用ogg封装。由于Vorbis设计上倾向于可变码率（VBR），因此预设围绕q值展开。
- Opus遵循官方规范使用ogg封装，但文件后缀使用opus。它的设计同样倾向可变码率，而且由于支持多声道，预设指定的是每个声道单独的目标码率——如128kbps，对立体声音轨来说合并后的码率等效为256kbps。另外，由于Opus的压缩质量很高，更高码率的Opus已经背离了有损压缩的初衷，边际收益过低，所以不加预设。
- AAC与ALAC遵循Apple规范，均使用m4a封装。
- PCM的输出提供wav和使用率相对较低的aiff。aiff相比于wav的优势是可以存储元数据，其余并无差异。
- 额外添加了caf作为支持的输入格式。caf可以封装任意编码、无限长度、无限大小的音频流，甚至可以嵌入MIDI数据、Warp标记、波形概览和SMPTE。这种丰富度使得将其作为输出缺乏目的性；而且由于只受苹果生态支持，几乎不会出现在DAW之外需要特地转换为caf的场景。故仅支持作为输入。

# NCM Transcoder

依靠[ncmdump](https://github.com/taurusxin/ncmdump)，你能以同样的操作剥离网易云ncm格式的加密，遵循原始格式，并支持统一输出到设定的文件夹以便于管理。

![200](attachments/Get%20Oudio%20Doc/file-20260704035713581.webp)

若将ncm的默认打开方式设为「Get Oudio」，双击文件即可输出到当前目录或你指定的目录，同时还能欣赏我为ncm文件设计的神金图标。

# Apple Music Downloader

依靠[Apple-Music-Downloader](https://github.com/zhaarey/apple-music-downloader)，现在可以在Apple Music中分享任意歌曲、播放列表或专辑到「Get Oudio」以下载到目标文件夹，支持ALAC、AAC与Atoms。

![500](attachments/Get%20Oudio%20Doc/file-20260704055235156.webp)

下载进程在选择横幅通知的格式Action后即刻开始：

![300](attachments/Get%20Oudio%20Doc/file-20260704055429493.webp)

当然你也可以固定每次下载的格式，这样就不需要多点一次按钮了。

指定的输出目录下，歌曲将以「歌手-专辑」的层级进行分类，同时保存专辑封面：

![|200](attachments/Get%20Oudio%20Doc/file-20260704055718733.webp)

按下方流程完成依赖安装与初始化，需要说明：

- 完成依赖安装和初始化后，「Get Oudio」将在你的电脑上占用超过1GB的空间，这是因为源项目是通过在一个虚拟的Android环境中靠Wrapper爬取数据实现的，「Get Oudio」需要搭一个虚拟机，目前采用的Colima+Docker CLI已经是体积最小的方案了。
- 依赖项从官方地址安装，期间需要开启科学上网的TUN（虚拟网卡）模式。各依赖项不支持寻找本地已有的复用，因为倘若你电脑上已经有Docker，那么我只能假定你有足够的动手能力，于是更加建议你获取源项目并搭建Shortcuts的自动化脚本，这比该软件更加稳定也更易于维护，与Mac的集成也更加舒适，可以[在这里参考我搭建的流程](https://www.icloud.com/shortcuts/f8ec294188db497fa9e6a2cf023a1d44)。
- 填写帐密并通过登录验证是必要的，「Get Oudio」不会私自获取你的用户信息。
- 下载时，「Get Oudio」每30秒会发出横幅通知指示当前的进度，若发现长时间没有反应，可以在设置页里急停。