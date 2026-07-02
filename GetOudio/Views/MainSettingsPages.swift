import GetOudioCore
import SwiftUI

// MARK: - SettingsSection (Reusable Card Component)

struct SettingsSection<Content: View, Footer: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    let footer: Footer

    init(
        _ title: String,
        systemImage: String = "gearshape",
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)

            if !(footer is EmptyView) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    footer
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}

// MARK: - SettingsForm (Scrollable Container)

struct SettingsForm<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(24)
        }
        .background(.windowBackground)
    }
}

// MARK: - TranscodingSettingsPage

struct TranscodingSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsForm {
            // 系统拓展板块
            SettingsSection("系统拓展", systemImage: "switch.2") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("若Finder Sync 与共享拓展没有被启用。请在系统设置的拓展页面手动打开 Get Oudio 的“共享”和“文件提供程序”。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        viewModel.openExtensionSettings()
                    } label: {
                        Label("打开拓展设置", systemImage: "switch.2")
                    }
                }
            }

            // 监听目录板块
            SettingsSection("监听目录", systemImage: "folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("由于 MacOS 的限制，右键拓展仅在以下设定的目录中生效。不推荐将外置硬盘置入监听目录中，因为受限于Finder的规矩，这会让硬盘图标变为「Get Oudio」的图标，非常丑陋。")
                        .font(.callout)
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

            // 重编码预设板块 — 每个编码格式独立一块
            SettingsSection("Re-Encoding预设", systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("在右键菜单中启用的预设，至少保留一项。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(ConversionPresetGroup.allCases) { group in
                        presetGroupBoard(group)
                    }
                }
            }
        }
    }

    /// 单个编码格式板块（AAC / MP3 / ALAC / FLAC / PCM）
    @ViewBuilder
    private func presetGroupBoard(_ group: ConversionPresetGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack {
                        Text(preset.title)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.enabledPresets.contains(preset) },
                            set: { viewModel.toggle(preset, isEnabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    if index < group.presets.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - NCMSettingsPage

struct NCMSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsForm {
            SettingsSection("输出设置", systemImage: "music.note") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("设定 NCM 转码后的输出位置。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("输出到", selection: Binding(
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
        }
    }
}

// MARK: - AppleMusicSettingsPage

struct AppleMusicSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var selectedTab = "settings"
    private let keychain = KeychainService()

    var body: some View {
        SettingsForm {
            SettingsSection("Apple Music 下载", systemImage: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        statusBadge
                        Text(viewModel.appleMusicRuntimeMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }

                    if viewModel.isManagingAppleMusicRuntime || viewModel.appleMusicRuntimeProgress?.isActive == true {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: viewModel.appleMusicRuntimeProgress?.fractionCompleted ?? 0)
                                .progressViewStyle(.linear)
                            Text(viewModel.appleMusicRuntimeProgress?.message ?? viewModel.appleMusicRuntimeMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await viewModel.enableAppleMusicRuntime() }
                        } label: {
                            Label(viewModel.isAppleMusicDownloadEnabled ? "检查并修复" : "启用", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isManagingAppleMusicRuntime)

                        Button {
                            Task { await viewModel.refreshAppleMusicRuntimeStatus() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isManagingAppleMusicRuntime)

                        Button(role: .destructive) {
                            Task { await viewModel.uninstallAppleMusicRuntime() }
                        } label: {
                            Label("卸载", systemImage: "trash")
                        }
                        .disabled(viewModel.isManagingAppleMusicRuntime || !viewModel.isAppleMusicDownloadEnabled)

                        Button(role: .destructive) {
                            viewModel.stopAppleMusicDownload()
                        } label: {
                            Label("急停", systemImage: "stop.circle")
                        }
                        .disabled(!viewModel.canStopAppleMusicDownload)
                    }
                }
            }

            Picker("", selection: $selectedTab) {
                Text("下载设置").tag("settings")
                Text("依赖状态").tag("runtime")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedTab == "settings" {
                accountAndDownloadSettings
            } else {
                runtimeStatusSettings
            }
        }
        .task {
            await viewModel.refreshAppleMusicRuntimeStatus()
        }
        .task {
            await viewModel.monitorAppleMusicWrapperLoginStatus()
        }
        .task {
            await viewModel.monitorAppleMusicRuntimeProgress()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(
            viewModel.isAppleMusicDownloadEnabled ? "已启用" : "未启用",
            systemImage: viewModel.isAppleMusicDownloadEnabled ? "checkmark.circle.fill" : "pause.circle"
        )
        .font(.callout.weight(.medium))
        .foregroundStyle(viewModel.isAppleMusicDownloadEnabled ? .green : .secondary)
    }

    private var accountAndDownloadSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("初始化", systemImage: "person.badge.key") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入 Apple ID 凭据以初始化 Apple Music 下载功能。凭据将安全存储在 Keychain 中。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    LabeledContent("Apple ID") {
                        TextField("example@icloud.com", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }

                    LabeledContent("密码") {
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }

                    Toggle("使用系统代理", isOn: Binding(
                        get: { viewModel.appleMusicUseSystemProxy },
                        set: { viewModel.setAppleMusicUseSystemProxy($0) }
                    ))
                    .toggleStyle(.switch)

                    HStack(spacing: 12) {
                        Button {
                            saveCredentials()
                        } label: {
                            Label("保存凭据", systemImage: "key")
                        }
                        .disabled(!viewModel.isAppleMusicDownloadEnabled || viewModel.appleMusicWrapperLoginStatus.isInProgress)

                        Button {
                            Task { await initializeWrapper() }
                        } label: {
                            Label("开始初始化", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            !viewModel.isAppleMusicDownloadEnabled
                                || viewModel.isInitializingAppleMusicWrapper
                                || viewModel.appleMusicWrapperLoginStatus.isInProgress
                                || viewModel.appleMusicWrapperLoginStatus.isAuthenticated
                                || username.isEmpty
                                || password.isEmpty
                        )
                    }

                    LabeledContent("验证码") {
                        HStack(spacing: 8) {
                            TextField("123456", text: $verificationCode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .disabled(!viewModel.appleMusicWrapperLoginStatus.canSubmitVerificationCode)

                            Button {
                                Task { await submitVerificationCode() }
                            } label: {
                                Label("提交验证码", systemImage: "number")
                            }
                            .disabled(
                                !viewModel.isAppleMusicDownloadEnabled
                                    || !viewModel.appleMusicWrapperLoginStatus.canSubmitVerificationCode
                                    || viewModel.isSubmittingAppleMusicVerificationCode
                                    || verificationCode.isEmpty
                            )
                        }
                    }

                    if viewModel.appleMusicWrapperLoginStatus.isInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !viewModel.appleMusicActionMessage.isEmpty {
                        Text(viewModel.appleMusicActionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    }
                }
            }
            .disabled(viewModel.appleMusicWrapperLoginStatus.isAuthenticated)
            .overlay {
                if viewModel.appleMusicWrapperLoginStatus.isAuthenticated {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                        Label("初始化已完成", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            SettingsSection("下载设置", systemImage: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("输出到") {
                        HStack {
                            Text(viewModel.appleMusicOutputURL.path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                viewModel.chooseAppleMusicOutputDirectory()
                            } label: {
                                Label("选择", systemImage: "folder")
                            }
                        }
                    }

                    Divider()

                    Picker("下载格式", selection: Binding(
                        get: { viewModel.appleMusicDownloadFormat },
                        set: { viewModel.setAppleMusicDownloadFormat($0) }
                    )) {
                        ForEach(AppleMusicDownloadFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!viewModel.isAppleMusicDownloadEnabled)
                }
            }
        }
    }

    private var runtimeStatusSettings: some View {
        SettingsSection("依赖状态", systemImage: "list.bullet.rectangle") {
            VStack(spacing: 0) {
                ForEach(viewModel.appleMusicRuntimeStatuses) { status in
                    HStack(spacing: 12) {
                        Image(systemName: status.isReady ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(status.isReady ? .green : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.component.displayName)
                                .font(.callout.weight(.medium))
                            Text(status.resolvedPath ?? status.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)

                    if status.id != viewModel.appleMusicRuntimeStatuses.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func saveCredentials() {
        do {
            try keychain.save(username, account: "apple-id")
            try keychain.save(password, account: "apple-id-password")
            viewModel.appleMusicActionMessage = "凭据已保存到 Keychain"
        } catch {
            viewModel.appleMusicActionMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func initializeWrapper() async {
        await viewModel.initializeAppleMusicWrapper(
            username: username,
            password: password
        )
    }

    private func submitVerificationCode() async {
        await viewModel.submitAppleMusicVerificationCode(verificationCode)
    }
}
