import GetOudioCore
import SwiftUI

struct ConvertWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPreset: ConversionPreset = .aac320
    private let settingsStore = SettingsStore()

    private var enabledPresets: [ConversionPreset] {
        ConversionPreset.allCases.filter { settingsStore.enabledPresets.contains($0) }
    }

    private var groupedItems: [(FileCategory, [OpenFileItem])] {
        let groups = Dictionary(grouping: appModel.openItems, by: \.category)
        return FileCategory.allCases.compactMap { category in
            guard let items = groups[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("转换选单")
                        .font(.title2.weight(.semibold))
                    Text(appModel.statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if groupedItems.isEmpty {
                ContentUnavailableView("没有待处理文件", systemImage: "tray")
            } else {
                fileList
                actionPanel
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 460)
    }

    private var fileList: some View {
        List {
            ForEach(groupedItems, id: \.0) { category, items in
                Section(category.displayName) {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: iconName(for: category))
                                .foregroundStyle(.secondary)
                            Text(item.url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 220)
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("音频重编码", selection: $selectedPreset) {
                ForEach(enabledPresets) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(!appModel.hasConvertibleAudioItems || appModel.isRunning)

            HStack(alignment: .firstTextBaseline) {
                Button {
                    Task { await appModel.runTranscode(preset: selectedPreset) }
                } label: {
                    Label("开始重编码", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.hasConvertibleAudioItems || appModel.isRunning)

                Button {
                    Task { await appModel.runExtractAudio() }
                } label: {
                    Label("提取视频音频", systemImage: "film")
                }
                .disabled(!appModel.hasVideoItems || appModel.isRunning)

                Button {
                    Task { await appModel.runNCMConversion() }
                } label: {
                    Label("转换 NCM", systemImage: "music.note")
                }
                .disabled(!appModel.hasNCMItems || appModel.isRunning)

                Button {
                    Task { await appModel.runAppleMusicDownload(format: nil) }
                } label: {
                    Label("下载 Apple Music", systemImage: "arrow.down.circle")
                }
                .disabled(!appModel.hasAppleMusicItems || appModel.isRunning)
            }

            HStack {
                Button {
                    Task { await appModel.runQueuedJobs() }
                } label: {
                    Label("执行 Finder 任务", systemImage: "folder.badge.gearshape")
                }
                .disabled(appModel.queuedJobs.isEmpty || appModel.isRunning)

                Spacer()

                Text(secondaryActionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var secondaryActionText: String {
        let categories = Set(appModel.openItems.map(\.category))
        if categories.contains(.video) {
            return "视频音频会按原音轨编码复制并封装到源目录。"
        }
        if categories.contains(.ncm) {
            return "NCM 会使用 App 内嵌 ncmdump，输出位置遵循设置。"
        }
        if categories.contains(.appleMusic) {
            return "Apple Music 下载会使用 App 内嵌下载器与 Colima 后台 wrapper 容器。"
        }
        return "输出文件将写入源文件所在目录。"
    }

    private func iconName(for category: FileCategory) -> String {
        switch category {
        case .audio: return "waveform"
        case .video: return "film"
        case .ncm: return "music.note"
        case .appleMusic: return "link"
        case .unsupported: return "questionmark.diamond"
        }
    }
}
