import SwiftUI

struct DashboardView: View {
    @ObservedObject var finderSettings: FinderDirectorySettingsModel
    @ObservedObject var systemExtensionSettings: SystemExtensionSettingsModel
    @ObservedObject var recordingSettings: RecordingSettingsModel
    @ObservedObject var diagnosticSettings: DiagnosticSettingsModel
    let checkForUpdates: () -> Void

    var body: some View {
        SettingsForm {
            SettingsSection("授权", systemImage: "checkmark.shield") {
                VStack(alignment: .leading, spacing: 18) {
                        Label("扩展", systemImage: "puzzlepiece.extension")
                            .font(.headline)

                        Text("你需要启用以下扩展，这使你可在访达右键菜单中使用「Get Oudio」，也可从 Apple Music 将 URL 分享给它。")
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
                        Label("文件/文件夹访问权限", systemImage: "folder.badge.gearshape")
                            .font(.headline)

                        Text("于此授权「Get Oudio」可以访问的文件夹。访达菜单拓展只会出现在这些目录下，转换程序也只能据此将转换结果写回源文件夹。另外受访达显示机制影响，不建议选择外置硬盘————这会改变你的外置硬盘图标显示。")
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
                            Text("更改扩展或文件/文件夹访问权限后，请重启访达")
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

            SettingsSection("关于", systemImage: "info.circle") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(verbatim: "Get! OOOOOOOOOudio")
                                .font(.custom("Pally-Bold", size: 32))
                            Text(verbatim: versionText)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2) //视觉对齐
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Get Oudio，\(versionText)")

                        HStack(spacing: 10) {
                            Button {
                                checkForUpdates()
                            } label: {
                                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)

                            Link(destination: URL(string: "https://github.com/memomoonnnn/GetOudio")!) {
                                Label("在Github上查看", systemImage: "link")
                            }
                            .buttonStyle(.bordered)

                            Text(verbatim: "@紙葉 Shiyō")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("作者：紙葉 Shiyō")
                        }
                    }

                    Spacer(minLength: 0)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 128, height: 128)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .top], 12)

                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 4) //补偿Doc布局原始的12pt padding

                MarkdownDocumentContent(.overview)
            }

            SettingsSection("高级", systemImage: "slider.horizontal.3") {
                Toggle(
                    "记录调试日志",
                    isOn: Binding(
                        get: { diagnosticSettings.isDebugLoggingEnabled },
                        set: { diagnosticSettings.setDebugLoggingEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Spacer()

                Button("在访达中显示") {
                    diagnosticSettings.revealLogLocation()
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), .none):
            return "Version \(version)"
        default:
            return "Version —"
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
                    Label("添加文件夹", systemImage: "plus")
                }

                Button {
                    finderSettings.resetFinderDirectories()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }
        }
    }
}
