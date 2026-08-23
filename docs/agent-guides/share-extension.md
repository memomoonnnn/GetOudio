# Share Extension Guide

适用于 Share Extension 的激活规则、输入解析、下载入队和宿主可见性。修改前检查 `GetOudioShareExtension/Sources/ShareExtension.swift`、`AppleMusicShareURLParser`、共享事件、entitlements 与 `project.yml`。

Share Extension 依据 `NSExtensionActivationRule` 和分享内容类型显示，不能声明只针对 Safari 或 Apple Music，也不得使用 `TRUEPREDICATE` 或非标准 `NSExtensionVersion`。当前结构化规则支持附件、文件、图片、视频、文本和一个 Web URL。`ShareExtension` 在 `loadView()` 异步读取 `extensionContext`，同时检查附件中的 `public.url`、`public.plain-text` 和 `NSExtensionItem.attributedContentText`。

Extension 只能解析、写入共享事件或队列并唤醒后台；实际 Apple Music 下载由 Agent 执行。可见性用安装后的签名 App 验证，随后检查 `pluginkit -m -v -i com.shengjiacheng.GetOudio.ShareExtension`。Music 会缓存分享菜单；Safari 可见且插件已启用时，完整退出并重启 Music 后再判断，不能将宿主缓存误诊为激活规则失败。
