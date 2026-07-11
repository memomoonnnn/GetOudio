# System Integrations Guide

本指南适用于 Finder Sync、Share Extension、文件分类、默认打开方式和外置磁盘权限改动。相关行为必须从当前 `FileCategory`、`FinderSync.swift`、`ShareExtension`、`DefaultOpenWithService`、`SettingsStore` 和 `project.yml` 复核。

## Finder Sync

Finder Sync 的可见性首先由 `FIFinderSyncController.default().directoryURLs` 的监听目录决定，并不像 Share Extension 那样按内容类型精确激活；`menu(for:)` 是最终菜单可见性边界。选择项经 `FileCategory.classify(_:)` 过滤后若没有可处理的 audio、video 或 ncm 文件，必须返回 `nil`，不能返回带禁用项的 `NSMenu`。目录背景、侧边栏和其他非文件选择默认同样返回 `nil`；混选可仅处理支持文件，但不能扩大到目录、压缩包或普通文档。

监听目录只控制 Finder Sync 出现范围，不授予持久读写权限。默认打开方式可以绕开 Finder Sync 的显示副作用，但不会扩大 security-scoped bookmark 的权限边界；涉及外置磁盘时必须分别检查入口触发和文件授权。

## Conversion Support and Default Open With

转换能力和系统默认打开方式必须分开维护。`FileCategory.supportedAudioExtensions` 是 Finder Sync、Open With 与队列判断内嵌 ffmpeg 是否可转码的宽集合，应对齐 `ffmpeg -hide_banner -demuxers` 并保留 `UTType.conforms(to: .audio)` 兜底。`FileCategory.defaultOpenWithAudioExtensions`、`project.yml` 的 Audio File 文档类型和设置页是窄集合，仅含 `.m4a/.aac`、`.mp3`、`.alac`、`.flac`、`.wav`、`.aiff/.aif`、`.ogg`、`.opus` 与 `.caf`。

`.m4a/.aac` 和 `.aiff/.aif` 各自作为一组开关，组内扩展名同步更新。关闭格式组时使用用户在设置页指定的播放器；播放器候选以 `.wav` 的 `NSWorkspace.urlsForApplications(toOpen:)` 结果为基准，不得退回 `NSOpenPanel` 手选 App。Launch Services 按 UTType 设置默认处理器，确认弹窗可能显示 `.mpga` 等同族别名；这不表示窄集合已扩大，不得因此把 `.mpga`、`.m4b`、`.wma` 或其他冷门格式加入 UI 或文档类型声明。

## Share Extension

Share Extension 依据 `NSExtensionActivationRule` 和分享内容类型显示，不能声明只针对 Safari 或 Apple Music，也不得使用 `TRUEPREDICATE` 或非标准 `NSExtensionVersion`。当前结构化规则支持附件、文件、图片、视频、文本和一个 Web URL。`ShareExtension` 应在 `loadView()` 中异步读取 `extensionContext`，同时检查附件中的 `public.url`、`public.plain-text` 和 `NSExtensionItem.attributedContentText`。

可见性必须用安装后的签名 App 验证。Music 会缓存分享菜单；Safari 可见且 `pluginkit` 已启用时，应完整退出并重启 Music 后再判断，不得把宿主缓存误诊为激活规则失败。
