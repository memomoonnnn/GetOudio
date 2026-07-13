import SwiftUI

struct DashboardView: View {
    @ObservedObject var finderSettings: FinderDirectorySettingsModel
    @ObservedObject var systemExtensionSettings: SystemExtensionSettingsModel
    @ObservedObject var recordingSettings: RecordingSettingsModel

    var body: some View {
        SettingsForm {
            SettingsSection("授权", systemImage: "checkmark.shield") {
                VStack(alignment: .leading, spacing: 18) {
                    Label("拓展", systemImage: "puzzlepiece.extension")
                        .font(.headline)

                    Text("你需要启用以下拓展：“文件提供程序”使你可以在访达的右键菜单中找到「Get Oudio」；“共享”则使你可以在 Apple Music 中分享 URL 到「Get Oudio」")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            systemExtensionSettings.openFileProviderExtensionSettings()
                        } label: {
                            Label("前往“文件提供程序”设置", systemImage: "externaldrive")
                        }

                        Button {
                            systemExtensionSettings.openShareExtensionSettings()
                        } label: {
                            Label("前往“共享”设置", systemImage: "square.and.arrow.up")
                        }

                        Spacer()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("监听目录", systemImage: "folder")
                            .font(.headline)

                        Text("只有处于监听目录列表下的文件才可以被访问；右键菜单也只会出现在监听列表以下的目录中，这是 MacOS 的限制所致。此外，还不推荐将外置硬盘添加到监听列表中，这会改变你的外置硬盘图标......")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        finderDirectoryContent

                        if !finderSettings.finderDirectoryMessage.isEmpty {
                            Text(finderSettings.finderDirectoryMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    HStack(spacing: 14) {
                        Button {
                            systemExtensionSettings.restartFinder()
                        } label: {
                            Label(
                                systemExtensionSettings.isRestartingFinder ? "正在重启…" : "重启访达",
                                systemImage: "arrow.clockwise"
                            )
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(systemExtensionSettings.isRestartingFinder)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("上述所有更改均在重启访达后生效")
                                .font(.callout.weight(.medium))
                            if !systemExtensionSettings.finderRestartMessage.isEmpty {
                                Text(systemExtensionSettings.finderRestartMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("权限", systemImage: "lock.shield")
                            .font(.headline)

                        Text("你需要批准麦克风访问权限，这使你可以使用「Get Oudio」的录音功能")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack {
                            Label(
                                recordingSettings.microphoneAuthorized ? "音频输入权限已启用" : "需要音频输入权限",
                                systemImage: recordingSettings.microphoneAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(recordingSettings.microphoneAuthorized ? .green : .secondary)
                            Spacer()
                            if !recordingSettings.microphoneAuthorized {
                                Button("授权") { recordingSettings.requestMicrophonePermission() }
                            }
                        }
                    }
                }
            }

            SettingsSection("关于 Get Oudio", systemImage: "info.circle") {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Get! OOOOOOOOOudio")
                            .font(.title2.weight(.semibold))

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
        }
    }

    private var finderDirectoryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(finderSettings.finderDirectories, id: \.self) { url in
                    HStack(spacing: 10) {
                        Label {
                            Text(url.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .lineLimit(1)

                        Spacer()

                        Button {
                            finderSettings.revealFinderDirectory(url)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中显示")

                        Button {
                            finderSettings.removeFinderDirectory(url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                    }
                }
                .onDelete(perform: finderSettings.removeFinderDirectories)
            }
            .frame(minHeight: 120)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .settingsGroupedRowBackground()

            HStack {
                Button {
                    finderSettings.addFinderDirectory()
                } label: {
                    Label("添加目录", systemImage: "plus")
                }

                Button {
                    finderSettings.restoreDefaultFinderDirectories()
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }
        }
    }
}
