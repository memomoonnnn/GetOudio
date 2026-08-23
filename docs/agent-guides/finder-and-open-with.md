# Finder and Open With Guide

适用于 Finder Sync、文件授权、文件分类、系统默认打开方式和外置磁盘。修改前检查 `FileCategory`、`FinderSync.swift`、`DefaultOpenWithService`、`SettingsStore` 与 `project.yml`。

Finder Sync 可见性先由 `FIFinderSyncController.default().directoryURLs` 决定，`menu(for:)` 是最终边界。选择项经 `FileCategory.classify(_:)` 过滤后，没有可处理的 audio、video 或 ncm 必须返回 `nil`，不能返回禁用菜单；目录背景、侧边栏和其他非文件选择默认也返回 `nil`。混选可处理支持文件，但不能扩大到目录、压缩包或普通文档。

监听目录只控制 Finder Sync 出现范围，不授予持久读写权限。新建 Finder 授权由 `SettingsStore.finderDirectoryAuthorizations` 保存授权根及其覆盖目录；移除目录时只撤销 Finder 来源关联，最后一个关联移除后才删除授权根。`directoryBookmarks` 是默认打开方式和既有安装的兼容来源，不得删除或改写为 Finder 授权；`finderDirectoryURLs` 只保存界面路径。只有 `DirectoryChooser` 或等价用户文件选择结果能由 `FinderDirectorySettingsModel` 写入授权，不得以旧路径、默认目录或持久化路径伪造授权。

设置页称为“文件/文件夹访问权限”。添加文件夹保存所选 bookmark；“重置”要求用户在原生面板确认覆盖默认桌面、文稿、下载、影片和音乐目录的祖先目录，再恢复默认列表并保存该祖先 bookmark。`DirectoryAccessAuthorizer` 同样只能要求用户选择源文件夹或祖先；`ScopedJobAccess` 可持有祖先作用域，但 `outputDirectoryURL` 始终是输入文件父目录。NCM 自定义输出只恢复 `ncmCustomOutputBookmarkData`；所有 NCM、音频转码和媒体提取在调用工具前检查实际输出目录可访问且可写，`ncmdump` 退出码为 0 后仍须确认匹配输出音频已新增或更新。

转换能力和系统默认打开方式分开维护。`FileCategory.supportedAudioExtensions` 是 Finder Sync、Open With 与队列判断内嵌 ffmpeg 的宽集合，对齐 `ffmpeg -hide_banner -demuxers` 并保留 `UTType.conforms(to: .audio)` 兜底。`FileCategory.defaultOpenWithAudioExtensions`、`project.yml` Audio File 文档类型和设置页是窄集合，仅含 `.m4a/.aac`、`.mp3`、`.alac`、`.flac`、`.wav`、`.aiff/.aif`、`.ogg`、`.opus`、`.caf`。`.m4a/.aac` 和 `.aiff/.aif` 各为一组开关；关闭时使用用户指定播放器，候选以 `.wav` 的 `NSWorkspace.urlsForApplications(toOpen:)` 为基准，不得退回 `NSOpenPanel`。Launch Services 可能显示 `.mpga` 等别名，不得因此把 `.mpga`、`.m4b`、`.wma` 或其他格式加入 UI 或文档类型。

验证：Finder 改动构建 `GetOudioFinderExtension` target；涉及安装、文档类型、权限或注册时签名安装，并用 `pluginkit -m -v -i com.shengjiacheng.GetOudio.FinderExtension` 检查。外置磁盘同时验证入口触发与 bookmark 文件访问。
