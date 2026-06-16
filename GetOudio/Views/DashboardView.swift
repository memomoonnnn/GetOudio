import SwiftUI

struct DashboardView: View {
    var body: some View {
        SettingsForm {
            // 应用信息
            SettingsSection("关于 Get Oudio", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Get Oudio")
                                .font(.title.weight(.bold))
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                                Text("版本 \(version) (\(build))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("一款原生 macOS 音频转换工具，支持 NCM 解密、音频重编码与 Apple Music 下载。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 快速开始
            SettingsSection("快速开始", systemImage: "arrow.forward.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    quickStartRow(
                        icon: "music.note",
                        title: "转换 NCM 文件",
                        description: "在 Finder 中右键点击 .ncm 文件，或使用打开方式选择 Get Oudio"
                    )
                    Divider()
                    quickStartRow(
                        icon: "slider.horizontal.3",
                        title: "音频重编码",
                        description: "将音频文件拖入转换窗口，选择预设格式后开始转码"
                    )
                    Divider()
                    quickStartRow(
                        icon: "arrow.down.circle",
                        title: "Apple Music 下载",
                        description: "在 AM 下载设置中启用并初始化后即可使用"
                    )
                }
            }
        }
    }

    private func quickStartRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
