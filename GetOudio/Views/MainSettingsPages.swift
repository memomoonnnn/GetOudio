import GetOudioCore
import SwiftUI

private enum SettingsMetrics {
    static let sectionCornerRadius: CGFloat = 20
    static let rowCornerRadius: CGFloat = 14
    static let sectionPadding: CGFloat = 16
    static let contentMaxWidth: CGFloat = 760
    static let contentTopInset: CGFloat = 54
    static let contentBottomInset: CGFloat = 96
    static let sectionTitleFont = Font.system(size: 12, weight: .semibold)
    static let groupTitleFont = Font.system(size: 12.5, weight: .semibold)
}

// MARK: - Audio Bridge Recording Settings

struct RecordingSettingsPage: View {
    @ObservedObject var viewModel: RecordingSettingsModel

    var body: some View {
        SettingsForm {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Bridge Recorder")
                    .font(.system(size: 26, weight: .bold))
                Text("桌面组件会把默认媒体输出切换到 Pro Tools Audio Bridge，并从切换前的播放设备实时监听。系统提醒音不会进入录音。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection("输入与权限", systemImage: "waveform.badge.mic") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Audio Bridge")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.selectedBridgeUID },
                            set: { viewModel.selectBridge($0) }
                        )) {
                            Text("未选择").tag(String?.none)
                            ForEach(viewModel.bridgeDevices) { device in
                                Text("\(device.name) · \(Int(device.nominalSampleRate)) Hz")
                                    .tag(Optional(device.uid))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }

                    HStack {
                        Label(
                            viewModel.microphoneAuthorized ? "音频输入权限已启用" : "需要音频输入权限",
                            systemImage: viewModel.microphoneAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(viewModel.microphoneAuthorized ? .green : .secondary)
                        Spacer()
                        if !viewModel.microphoneAuthorized {
                            Button("授权") { viewModel.requestMicrophonePermission() }
                        }
                        Button("刷新设备") { viewModel.refresh() }
                    }
                }
            }

            SettingsSection("文件与缓存", systemImage: "externaldrive") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("缓存上限")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.cacheLimitBytes },
                            set: { viewModel.setCacheLimit($0) }
                        )) {
                            ForEach(RecordingSettingsModel.cacheLimitOptions) { option in
                                Text(option.title).tag(option.bytes)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("当前缓存")
                            .foregroundStyle(.secondary)
                        Text(viewModel.cacheSizeText)
                            .font(.body.monospacedDigit())
                        Spacer()
                        Button("清理") { viewModel.clearCache() }
                    }

                    Divider()

                    Toggle("完成后移动到指定目录", isOn: Binding(
                        get: { viewModel.usesCustomOutputDirectory },
                        set: { viewModel.setUsesCustomOutputDirectory($0) }
                    ))

                    HStack {
                        Text(viewModel.customOutputDirectoryName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("选择目录") { viewModel.chooseOutputDirectory() }
                    }
                    .disabled(!viewModel.usesCustomOutputDirectory)
                }
            }

            if !viewModel.message.isEmpty {
                Label(viewModel.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum SettingsSurface {
    static func pageTint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.025) : Color.white.opacity(0.035)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.72) : Color.white.opacity(0.075)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.045) : Color.white.opacity(0.07)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.095) : Color.white.opacity(0.105)
    }
}

struct SettingsRootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
            Rectangle()
                .fill(SettingsSurface.pageTint(for: colorScheme))
        }
        .ignoresSafeArea()
    }
}

private struct SettingsCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                    .fill(SettingsSurface.cardFill(for: colorScheme))
            }
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                    .strokeBorder(SettingsSurface.border(for: colorScheme), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(colorScheme == .light ? 0.05 : 0.18), radius: 16, x: 0, y: 8)
    }
}

private struct SettingsGroupedRowBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous)
                    .fill(SettingsSurface.controlFill(for: colorScheme))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(SettingsSurface.border(for: colorScheme), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func settingsGroupedRowBackground() -> some View {
        modifier(SettingsGroupedRowBackgroundModifier())
    }
}

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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 15, alignment: .center)
                Text(title)
                    .font(SettingsMetrics.sectionTitleFont)
            }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(SettingsMetrics.sectionPadding)

                if !(footer is EmptyView) {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        footer
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsMetrics.sectionPadding)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsCardBackground())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SettingsForm (Scrollable Container)

struct SettingsForm<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 30, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: SettingsMetrics.contentTopInset)

                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .leading)

                Color.clear
                    .frame(height: SettingsMetrics.contentBottomInset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
        .scrollContentBackground(.hidden)
    }
}

// MARK: - TranscodingSettingsPage

struct TranscodingSettingsPage: View {
    @ObservedObject var presetSettings: PresetSettingsModel
    @ObservedObject var defaultOpenWithSettings: DefaultOpenWithSettingsModel

    var body: some View {
        SettingsForm {
            MarkdownDocumentView(.transcoding)

            SettingsSection("默认打开方式", systemImage: "doc.badge.gearshape") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("关闭时使用")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            if defaultOpenWithSettings.defaultAudioPlayerOptions.isEmpty {
                                Text("没有找到可打开 .wav 的应用")
                            } else {
                                ForEach(defaultOpenWithSettings.defaultAudioPlayerOptions) { option in
                                    Button {
                                        defaultOpenWithSettings.selectDefaultAudioPlayer(option)
                                    } label: {
                                        if option.url == defaultOpenWithSettings.defaultAudioPlayerURL {
                                            Label(option.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(option.displayName)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(defaultOpenWithSettings.defaultAudioPlayerName, systemImage: "play.rectangle")
                        }
                        .disabled(defaultOpenWithSettings.defaultAudioPlayerOptions.isEmpty)
                    }

                    VStack(spacing: 0) {
                        ForEach(defaultOpenWithSettings.audioDefaultOpenWithRows) { row in
                            HStack(spacing: 10) {
                                Text(row.group.displayName)
                                    .font(.body.monospaced())
                                    .frame(width: 108, alignment: .leading)

                                Spacer()

                                if defaultOpenWithSettings.audioDefaultOpenWithBusyGroupIDs.contains(row.group.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                }

                                Toggle("", isOn: Binding(
                                    get: { row.isGetOudioDefault },
                                    set: { isEnabled in
                                        Task {
                                            await defaultOpenWithSettings.setAudioDefaultOpenWith(row, isEnabled: isEnabled)
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(defaultOpenWithSettings.audioDefaultOpenWithBusyGroupIDs.contains(row.group.id))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)

                            if row.id != defaultOpenWithSettings.audioDefaultOpenWithRows.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .settingsGroupedRowBackground()

                    Label(
                        defaultOpenWithSettings.audioDefaultOpenWithMessage,
                        systemImage: defaultOpenWithSettings.audioDefaultOpenWithStatus.isFullyConfigured ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(defaultOpenWithSettings.audioDefaultOpenWithStatus.isFullyConfigured ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection("Re-Encoding预设", systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ConversionPresetGroup.allCases) { group in
                        presetGroupBoard(group)
                    }
                }
            }
        }
    }

    /// 单个编码格式板块（AAC / MP3 / ALAC / FLAC / PCM WAV / PCM AIFF）
    @ViewBuilder
    private func presetGroupBoard(_ group: ConversionPresetGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.displayName)
                .font(SettingsMetrics.groupTitleFont)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack {
                        Text(preset.title)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { presetSettings.enabledPresets.contains(preset) },
                            set: { presetSettings.toggle(preset, isEnabled: $0) }
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
            .settingsGroupedRowBackground()
        }
    }
}

// MARK: - NCMSettingsPage

struct NCMSettingsPage: View {
    @ObservedObject var ncmSettings: NCMSettingsModel
    @ObservedObject var defaultOpenWithSettings: DefaultOpenWithSettingsModel

    var body: some View {
        SettingsForm {
            MarkdownDocumentView(.ncm)

            SettingsSection("输出设置", systemImage: "music.note") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("输出到", selection: Binding(
                        get: { ncmSettings.ncmOutputMode },
                        set: { ncmSettings.setNCMOutputMode($0) }
                    )) {
                        Text("源文件所在目录").tag("sourceDirectory")
                        Text("指定目录").tag("customDirectory")
                    }
                    .pickerStyle(.radioGroup)

                    HStack {
                        Text(ncmSettings.ncmCustomOutputURL?.path ?? "未选择指定目录")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            ncmSettings.chooseNCMOutputDirectory()
                        } label: {
                            Label("选择目录", systemImage: "folder")
                        }
                    }
                }
            }

            SettingsSection("默认打开方式", systemImage: "doc.badge.gearshape") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await defaultOpenWithSettings.setNCMDefaultOpenWith()
                            }
                        } label: {
                            if defaultOpenWithSettings.isSettingNCMDefaultOpenWith {
                                Label("正在设置", systemImage: "hourglass")
                            } else {
                                Label("设为默认打开方式", systemImage: "doc.badge.gearshape")
                            }
                        }
                        .disabled(defaultOpenWithSettings.isSettingNCMDefaultOpenWith)

                        Button {
                            defaultOpenWithSettings.refreshDefaultOpenWithStatus()
                        } label: {
                            Label("刷新状态", systemImage: "arrow.clockwise")
                        }
                        .disabled(defaultOpenWithSettings.isSettingNCMDefaultOpenWith)

                        Spacer()
                    }

                    Label(
                        defaultOpenWithSettings.ncmDefaultOpenWithMessage,
                        systemImage: defaultOpenWithSettings.ncmDefaultOpenWithStatus.isFullyConfigured ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(defaultOpenWithSettings.ncmDefaultOpenWithStatus.isFullyConfigured ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - AppleMusicSettingsPage

struct AppleMusicSettingsPage: View {
    @ObservedObject var viewModel: AppleMusicSettingsModel
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var selectedTab = "settings"
    private let keychain = KeychainService()

    var body: some View {
        SettingsForm {
            MarkdownDocumentView(.appleMusic)

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
                        RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
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
