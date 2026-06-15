import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get Oudio")
                        .font(.largeTitle.weight(.semibold))
                    Text(appModel.statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
                GridRow {
                    StatusPanel(title: "打开方式入口", value: "已配置", systemImage: "doc.badge.gearshape")
                    StatusPanel(title: "Finder 右键菜单", value: "按目录启用", systemImage: "folder.badge.gearshape")
                    StatusPanel(title: "首个端到端功能", value: "音频重编码", systemImage: "waveform.path")
                }
            }

            if let summary = appModel.lastSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近一次转换")
                        .font(.headline)
                    Text("共处理 \(summary.totalCount) 个文件，成功 \(summary.successCount) 个，失败 \(summary.failureCount) 个。")
                    if !summary.messages.isEmpty {
                        Text(summary.messages.prefix(2).joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(28)
    }
}

private struct StatusPanel: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
