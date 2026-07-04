import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsForm {
            SettingsSection("关于 Get Oudio", systemImage: "info.circle") {
                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Get! OOOOOOOOOOOOOOOOOudio")
                            .font(.title.weight(.bold))

                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                            Text("版本 \(version) (\(build))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MarkdownDocumentView(.overview)

            SettingsSection("系统拓展", systemImage: "switch.2") {
                Button {
                    viewModel.openExtensionSettings()
                } label: {
                    Label("打开拓展设置", systemImage: "switch.2")
                }
            }

            SettingsSection("监听目录", systemImage: "folder") {
                VStack(alignment: .leading, spacing: 8) {
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
                    .frame(minHeight: 120)

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
                }
            } footer: {
                if !viewModel.finderDirectoryMessage.isEmpty {
                    Text(viewModel.finderDirectoryMessage)
                }
            }
        }
    }
}
