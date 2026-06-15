import GetOudioCore
import SwiftUI

struct TranscodingSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("监听目录") {
                Text("由于MacOS的限制，右键拓展仅在设定的目录下生效。")
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
                .frame(minHeight: 140)

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

            Section("Finder Sync 中启用的预设") {
                ForEach(ConversionPresetGroup.allCases) { group in
                    DisclosureGroup(group.displayName) {
                        ForEach(group.presets) { preset in
                            Toggle(preset.title, isOn: Binding(
                                get: { viewModel.enabledPresets.contains(preset) },
                                set: { viewModel.toggle(preset, isEnabled: $0) }
                            ))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}

struct NCMSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
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
        }
        .formStyle(.grouped)
        .padding(24)
    }
}

struct AppleMusicSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var status = "尚未初始化"
    @State private var isInitializing = false
    private let keychain = KeychainService()
    private let downloadService = AppleMusicDownloadService()

    var body: some View {
        Form {
            Section("初始化") {
                TextField("Apple ID", text: $username)
                SecureField("密码", text: $password)
                TextField("验证码", text: $verificationCode)
                Text(status)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        saveCredentials()
                    } label: {
                        Label("保存凭据", systemImage: "key")
                    }

                    Button {
                        Task { await initializeWrapper() }
                    } label: {
                        Label("开始初始化", systemImage: "play")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInitializing || username.isEmpty || password.isEmpty)

                    Button {
                        submitVerificationCode()
                    } label: {
                        Label("提交验证码", systemImage: "number")
                    }
                    .disabled(verificationCode.isEmpty)
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
        .padding(24)
    }

    private func saveCredentials() {
        do {
            try keychain.save(username, account: "apple-id")
            try keychain.save(password, account: "apple-id-password")
            status = "凭据已保存到 Keychain"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    private func initializeWrapper() async {
        isInitializing = true
        status = "正在后台启动 Colima 并运行 wrapper 镜像。收到 Apple 验证码后，在此输入并点击提交验证码。"
        let summary = await downloadService.initializeWrapper(username: username, password: password, verificationCode: verificationCode)
        isInitializing = false

        if summary.failureCount == 0 {
            status = "初始化完成"
        } else {
            status = summary.messages.first ?? "初始化失败"
        }
    }

    private func submitVerificationCode() {
        let summary = downloadService.submitWrapperVerificationCode(verificationCode)
        if summary.failureCount == 0 {
            status = "验证码已写入 wrapper 运行目录"
        } else {
            status = summary.messages.first ?? "验证码写入失败"
        }
    }
}

struct DependencySettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
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
                                Label(status.installActionTitle, systemImage: "square.and.arrow.down")
                            }
                            .disabled(viewModel.isDependencyInstallDisabled(status))
                            .help(viewModel.installHelp(for: status))
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
        .padding(24)
    }
}

private extension DependencyStatus {
    var installActionTitle: String {
        if dependency == .homebrew {
            return isInstalled ? "重新安装" : "安装"
        }
        return isInstalled ? "更新" : "安装"
    }
}
