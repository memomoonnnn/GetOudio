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
                            Text("Get! OOOOOOOOOOOOOOOOOudio")
                                .font(.title.weight(.bold))
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                                Text("版本 \(version) (\(build))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("包装了几个开源项目的脚本执行器。")
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
                        title: "Transcode NCM",
                        description: "对 .ncm 文件在 Finder 右键菜单中选择「Get Oudio」，或使用打开方式选择 Get Oudio。"
                    )
                    Divider()
                    quickStartRow(
                        icon: "slider.horizontal.3",
                        title: "Re-Encoding",
                        description: "对音频文件在 Finder 右键菜单中选择「Get Oudio」预设，还可以提取视频中的音频轨。"
                    )
                    Divider()
                    quickStartRow(
                        icon: "arrow.down.circle",
                        title: "从 Apple Music 下载",
                        description: "在设置中启用并初始化，随后在Apple Music中分享至「Get Oudio」。"
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
