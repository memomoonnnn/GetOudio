# Icons Guide

适用于主图标、Share 图标、Icon Composer 和图标相关生成工程。主图标源是 `GetOudio/Resources/AppIcon.icon`；源码 Info.plist 只维护 `CFBundleIconName = AppIcon`，构建产物的 `CFBundleIconFile = AppIcon` 是 actool 补全，不得写回源码。`project.yml` 的 `postGenCommand` 必须保留该资源的 `folder.iconcomposer.icon` 文件类型修补。Share Extension 使用自己的 `icon.icns` 与 `CFBundleIconFile = icon`。

图标、Info.plist、target 或资源改动后运行 `xcodegen generate`，再签名安装验证；不要以沙箱 unsigned 完整 App 构建中 AppIcon 的 actool 噪声判断代码回归。
