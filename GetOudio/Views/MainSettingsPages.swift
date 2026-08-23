import GetOudioCore
import SwiftUI

// MARK: - Audio Bridge Recording Settings

struct RecordingSettingsPage: View {
    private static let inputSectionID = "recording-input-section"

    @ObservedObject var viewModel: RecordingSettingsModel
    let attention: SettingsAttentionPresentation
    let markDocumentationOpened: (SettingsAttentionItem) -> Void

    var body: some View {
        SettingsForm(
            scrollTarget: attention.scrollTarget == .recordingInput ? Self.inputSectionID : nil,
            scrollRequestID: attention.highlightRequest(for: .recordingInput)
        ) {
            MarkdownDocumentView(
                .recording,
                attentionItem: .recordingDocumentation,
                highlightRequestID: attention.highlightRequest(for: .recordingDocumentation),
                markOpened: markDocumentationOpened
            )

            SettingsSection("输入", systemImage: "waveform.badge.mic") {
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

                        Button("刷新设备") { viewModel.refresh() }
                    }

                }
            } cardOverlay: {
                SettingsAttentionPulseOverlay(requestID: attention.highlightRequest(for: .recordingInput))
            }
            .id(Self.inputSectionID)

            SettingsSection("缓存", systemImage: "externaldrive") {
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
                        Button("在访达中显示") { viewModel.revealCacheDirectory() }
                    }

                    Divider()

                    Picker("缓存到", selection: Binding(
                        get: { viewModel.usesCustomCacheDirectory ? "customDirectory" : "defaultDirectory" },
                        set: { viewModel.setUsesCustomCacheDirectory($0 == "customDirectory") }
                    )) {
                        Text("默认缓存目录").tag("defaultDirectory")
                        Group {
                            if viewModel.usesCustomCacheDirectory {
                                HStack {
                                    Text(viewModel.cacheDirectoryPath)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        viewModel.chooseCacheDirectory()
                                    } label: {
                                        Label("选择", systemImage: "folder")
                                    }
                                }
                            } else {
                                Text("指定目录")
                            }
                        }
                        .tag("customDirectory")
                    }
                    .pickerStyle(.radioGroup)

                    Text(RecordingSettingsModel.customCacheDirectoryMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection("后处理", systemImage: "waveform.path.ecg") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("峰值标准化", isOn: Binding(
                        get: { viewModel.normalizesPeak },
                        set: { viewModel.setNormalizesPeak($0) }
                    ))
                    .toggleStyle(.switch)

                    Toggle("去除头尾的无声片段", isOn: Binding(
                        get: { viewModel.trimsSilence },
                        set: { viewModel.setTrimsSilence($0) }
                    ))
                    .toggleStyle(.switch)

                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("阈值")
                                Spacer()
                                Text("\(viewModel.silenceThresholdDBFS, format: .number.precision(.fractionLength(0...1))) dBFS")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { viewModel.silenceThresholdDBFS },
                                    set: { viewModel.setSilenceThresholdDBFS($0) }
                                ),
                                in: -90...0,
                                step: 1
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        Divider()
                            .padding(.leading, 12)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("额外垫付")
                                Spacer()
                                Text("\(viewModel.silencePaddingMilliseconds) ms")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.silencePaddingMilliseconds) },
                                    set: { viewModel.setSilencePaddingMilliseconds(Int($0.rounded())) }
                                ),
                                in: 0...1_000,
                                step: 10
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .settingsGroupedRowBackground()
                    .disabled(!viewModel.trimsSilence)
                    .opacity(viewModel.trimsSilence ? 1 : 0.45)
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

// MARK: - TranscodingSettingsPage

struct TranscodingSettingsPage: View {
    @ObservedObject var presetSettings: PresetSettingsModel
    @ObservedObject var defaultOpenWithSettings: DefaultOpenWithSettingsModel
    let attention: SettingsAttentionPresentation
    let markDocumentationOpened: (SettingsAttentionItem) -> Void

    var body: some View {
        SettingsForm {
            MarkdownDocumentView(
                .transcoding,
                attentionItem: .transcodingDocumentation,
                highlightRequestID: attention.highlightRequest(for: .transcodingDocumentation),
                markOpened: markDocumentationOpened
            )

            SettingsSection("默认打开方式", systemImage: "doc.badge.gearshape") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用下方的Toggle快速改变对应文件的默认打开方式")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 8) {
                        Text("关闭时使用")
                            .foregroundStyle(.secondary)
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

            SettingsSection("预设配置", systemImage: "slider.horizontal.3") {
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
    let attention: SettingsAttentionPresentation
    let markDocumentationOpened: (SettingsAttentionItem) -> Void

    var body: some View {
        SettingsForm {
            MarkdownDocumentView(
                .ncm,
                attentionItem: .ncmDocumentation,
                highlightRequestID: attention.highlightRequest(for: .ncmDocumentation),
                markOpened: markDocumentationOpened
            )

            SettingsSection("输出设置", systemImage: "music.note") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("输出到", selection: Binding(
                        get: { ncmSettings.ncmOutputMode },
                        set: { ncmSettings.setNCMOutputMode($0) }
                    )) {
                        Text("源文件所在目录").tag(NCMOutputMode.sourceDirectory)
                        Group {
                            if ncmSettings.ncmOutputMode == .customDirectory {
                                HStack {
                                    Text(ncmSettings.ncmCustomOutputURL?.path ?? "未选择目录")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        ncmSettings.chooseNCMOutputDirectory()
                                    } label: {
                                        Label("选择", systemImage: "folder")
                                    }
                                }
                            } else {
                                Text("指定目录")
                            }
                        }
                        .tag(NCMOutputMode.customDirectory)
                    }
                    .pickerStyle(.radioGroup)
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
    private static let dependencyInstallationSectionID = "apple-music-dependency-installation-section"
    private static let initializationSectionID = "apple-music-initialization-section"

    @ObservedObject var viewModel: AppleMusicSettingsModel
    let attention: SettingsAttentionPresentation
    let markDocumentationOpened: (SettingsAttentionItem) -> Void
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""

    var body: some View {
        SettingsForm(
            scrollTarget: scrollTarget,
            scrollRequestID: scrollRequestID
        ) {
            MarkdownDocumentView(
                .appleMusic,
                attentionItem: .appleMusicDocumentation,
                highlightRequestID: attention.highlightRequest(for: .appleMusicDocumentation),
                markOpened: markDocumentationOpened
            )
            dependencyInstallationSettings
            runtimeStatusSettings
            initializationSettings
            downloadSettings
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

    private var dependencyInstallationSettings: some View {
        SettingsSection("依赖安装", systemImage: "arrow.down.circle") {
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
                        Label(viewModel.isAppleMusicDownloadEnabled ? "检查并更新" : "启用", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAppleMusicRuntimeUpdateBlocked)

                    Button {
                        Task { await viewModel.refreshAppleMusicRuntimeStatus() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isAppleMusicRuntimeBusy)

                    Button(role: .destructive) {
                        Task { await viewModel.uninstallAppleMusicRuntime() }
                    } label: {
                        Label("卸载", systemImage: "trash")
                    }
                    .disabled(viewModel.isAppleMusicRuntimeUpdateBlocked || !viewModel.isAppleMusicDownloadEnabled)

                    Button(role: .destructive) {
                        viewModel.stopAppleMusicDownload()
                    } label: {
                        Label("急停", systemImage: "stop.circle")
                    }
                    .disabled(!viewModel.canStopAppleMusicDownload)
                }

                if viewModel.isAppleMusicRuntimeUpdateBlocked {
                    Text(viewModel.appleMusicRuntimeOperationBlockedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } cardOverlay: {
            SettingsAttentionPulseOverlay(requestID: attention.highlightRequest(for: .appleMusicDependencies))
        }
        .id(Self.dependencyInstallationSectionID)
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

    private var initializationSettings: some View {
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
                        Task { await initializeWrapper() }
                    } label: {
                        Label("开始初始化", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !viewModel.isAppleMusicDownloadEnabled
                            || viewModel.isSendingAppleMusicInitializationRequest
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

                if !viewModel.appleMusicInitializationMessage.isEmpty {
                    Text(viewModel.appleMusicInitializationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }
        } cardOverlay: {
            ZStack {
                if viewModel.appleMusicWrapperLoginStatus.isAuthenticated {
                    RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(0.5)
                    Label("初始化已完成", systemImage: "checkmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.green)
                }
                SettingsAttentionPulseOverlay(requestID: attention.highlightRequest(for: .appleMusicInitialization))
            }
            .allowsHitTesting(false)
        }
        .id(Self.initializationSectionID)
        .disabled(!areAppleMusicDependenciesReady || viewModel.appleMusicWrapperLoginStatus.isAuthenticated)
    }

    private var downloadSettings: some View {
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

    private var areAppleMusicDependenciesReady: Bool {
        viewModel.isAppleMusicDownloadEnabled
            && !viewModel.appleMusicRuntimeStatuses.isEmpty
            && viewModel.appleMusicRuntimeStatuses.allSatisfy(\.isReady)
    }

    private var scrollRequestID: Int {
        attention.highlightRequestID
    }

    private var scrollTarget: String? {
        if attention.scrollTarget == .appleMusicInitialization {
            Self.initializationSectionID
        } else if attention.scrollTarget == .appleMusicDependencies {
            Self.dependencyInstallationSectionID
        } else {
            nil
        }
    }

    private var runtimeStatusSettings: some View {
        SettingsSection("依赖状态", systemImage: "list.bullet.rectangle") {
            VStack(spacing: 0) {
                if viewModel.appleMusicRuntimeStatuses.isEmpty {
                    Label(
                        viewModel.isRefreshingAppleMusicRuntimeStatus ? "正在检测依赖..." : "暂无依赖状态",
                        systemImage: viewModel.isRefreshingAppleMusicRuntimeStatus ? "arrow.triangle.2.circlepath" : "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    ForEach(viewModel.appleMusicRuntimeStatuses) { status in
                        HStack(spacing: 12) {
                            Image(systemName: status.updateState == .updateAvailable || status.updateState == .legacy ? "arrow.triangle.2.circlepath.circle.fill" : (status.isReady ? "checkmark.circle.fill" : "xmark.circle"))
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
                                if let updateState = status.updateState, updateState != .current {
                                    Text("\(updateState.displayName) · 目标 \(status.targetVersion ?? "")")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
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
