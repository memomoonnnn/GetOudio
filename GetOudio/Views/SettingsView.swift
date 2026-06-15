import GetOudioCore
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            presetSettings
                .tabItem { Label("重编码", systemImage: "slider.horizontal.3") }

            finderSettings
                .tabItem { Label("Finder", systemImage: "folder") }

            outputSettings
                .tabItem { Label("输出", systemImage: "arrow.down.doc") }

            dependencySettings
                .tabItem { Label("组件", systemImage: "shippingbox") }
        }
        .frame(width: 680, height: 520)
        .padding(20)
        .task {
            if viewModel.dependencyStatuses.isEmpty {
                await viewModel.refreshDependencies()
            }
        }
    }

    private var presetSettings: some View {
        Form {
            Section("右键菜单与转换窗口中显示的预设") {
                ForEach(ConversionPreset.allCases) { preset in
                    Toggle(preset.title, isOn: Binding(
                        get: { viewModel.enabledPresets.contains(preset) },
                        set: { viewModel.toggle(preset, isEnabled: $0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var finderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finder 原生右键菜单只会出现在下列目录及其子目录中。")
                .foregroundStyle(.secondary)

            List {
                ForEach(viewModel.finderDirectories, id: \.self) { url in
                    HStack(spacing: 10) {
                        Label(url.path, systemImage: "folder")
                            .lineLimit(1)

                        Spacer()

                        Button {
                            viewModel.revealFinderDirectory(url)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中显示")

                        Button {
                            viewModel.removeFinderDirectory(url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                    }
                }
                .onDelete(perform: viewModel.removeFinderDirectories)
            }

            HStack {
                Button {
                    viewModel.addFinderDirectory()
                } label: {
                    Label("添加目录", systemImage: "plus")
                }

                Button {
                    viewModel.restoreDefaultFinderDirectories()
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }

            if !viewModel.finderDirectoryMessage.isEmpty {
                Text(viewModel.finderDirectoryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var outputSettings: some View {
        Form {
            Section("NCM 转换输出") {
                Picker("输出位置", selection: Binding(
                    get: { viewModel.ncmOutputMode },
                    set: { viewModel.setNCMOutputMode($0) }
                )) {
                    Text("源文件所在目录").tag("sourceDirectory")
                    Text("指定目录").tag("customDirectory")
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Text(viewModel.ncmCustomOutputURL?.path ?? "未选择指定目录")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.chooseNCMOutputDirectory()
                    } label: {
                        Label("选择目录", systemImage: "folder")
                    }
                }
            }

            Section("Apple Music 下载") {
                HStack {
                    Text(viewModel.appleMusicOutputURL.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.chooseAppleMusicOutputDirectory()
                    } label: {
                        Label("选择输出目录", systemImage: "folder")
                    }
                }

                Picker("下载类型", selection: Binding(
                    get: { viewModel.appleMusicDownloadFormat },
                    set: { viewModel.setAppleMusicDownloadFormat($0) }
                )) {
                    ForEach(AppleMusicDownloadFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dependencySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.dependencyMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.refreshDependencies() }
                } label: {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isCheckingDependencies)
            }

            List {
                Section("运行时工具") {
                    ForEach(viewModel.dependencyStatuses) { status in
                        HStack(spacing: 12) {
                            Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(status.isInstalled ? .green : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.dependency.displayName)
                                    .font(.headline)
                                Text(status.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Button {
                                Task { await viewModel.install(status.dependency) }
                            } label: {
                                Label(status.isInstalled ? "更新" : "安装", systemImage: "square.and.arrow.down")
                            }
                            .disabled(viewModel.isCheckingDependencies)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("App 内嵌组件") {
                    ForEach(viewModel.bundledComponentStatuses) { status in
                        HStack(spacing: 12) {
                            Image(systemName: status.isEmbedded ? "checkmark.circle.fill" : "archivebox.fill")
                                .foregroundStyle(status.isEmbedded ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.component.displayName)
                                    .font(.headline)
                                Text(status.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Colima 托管容器镜像") {
                    ForEach(viewModel.dockerImageStatuses) { status in
                        HStack(spacing: 12) {
                            Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "externaldrive.badge.exclamationmark")
                                .foregroundStyle(status.isAvailable ? .green : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.image.displayName)
                                    .font(.headline)
                                Text(status.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Button {
                                Task { await viewModel.pull(status.image) }
                            } label: {
                                Label(status.isAvailable ? "重新拉取" : "启动并拉取", systemImage: "arrow.down.circle")
                            }
                            .disabled(viewModel.isCheckingDependencies)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
