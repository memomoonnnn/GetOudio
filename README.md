<p align="center">
  <img src="assets/群组@2x.png" width="256" />
</p>

<h1 align="center">Get! OOOOOOOOOudio</h1>

Get Oudio 是为音频工作者们开发的实用性工具。软件做了一些微小的工作，集成了一些优秀的开源项目，并使它们可以在 macOS 上被方便地调用，感谢这些开发者的无私奉献！

过去类似 Permute、Downie 这样的软件，你需要先打开窗口、拖放文件、设定参数再启动进程，完成任务后还要手动退出，这种交互设计在我看来非常愚蠢。于是 Get Oudio 参考了一众解压缩软件的设计逻辑，将操作入口全集成在 macOS 本身的组件中；所有功能预制化，不需要任何临时的额外设置；全程也没有任何窗口干扰，只有右上角的横幅通知告知你进程状态，就好像 Mac 天生就自带这个功能一般。

## 功能

- 对音频文件进行重编码，包含音频行业惯用的所有制式。
- 提取视频文件的音频轨，保留原始编码。
- 剥离`.ncm`文件的加密。
- 从Apple Music下载无损音源。

## 特性

Get Oudio 最早源于我为了解决日常工作生活中的痛点而搭建的一些AutoMator和Shortcuts流程，后来萌生了集成为单一软件的想法，希望这能让更多人获得如此便捷的交互体验：



软件的设置窗口内还附有更多说明：

![Get Oudio 设置窗口](assets/2026-07-12%2005.07.08.png)

## 使用到的项目

- [FFmpeg](https://github.com/FFmpeg/FFmpeg)
- [ncmdump](https://github.com/taurusxin/ncmdump)
- [wrapper](https://github.com/WorldObservationLog/wrapper)
- [apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE.txt) 许可证。
