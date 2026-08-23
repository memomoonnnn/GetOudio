import AppKit
import GetOudioCore
import SwiftUI

struct MainView: View {
    @StateObject private var settingsViewModel: SettingsViewModel
    @ObservedObject private var attentionState: SettingsAttentionState
    @State private var selection: MainSidebarItem? = .overview
    @State private var attentionPresentation = SettingsAttentionPresentation.none
    private let checkForUpdates: () -> Void

    init(
        container: SharedContainer,
        initialSettingsAttention: SettingsAttentionItem? = nil,
        checkForUpdates: @escaping () -> Void
    ) {
        let settingsViewModel = SettingsViewModel(container: container)
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _attentionState = ObservedObject(wrappedValue: settingsViewModel.attentionState)
        _selection = State(initialValue: Self.initialSelection(for: initialSettingsAttention))
        _attentionPresentation = State(initialValue: SettingsAttentionPresentation(
            items: initialSettingsAttention.map { [$0] } ?? [],
            highlightRequestID: initialSettingsAttention == nil ? 0 : 1,
            scrollTarget: initialSettingsAttention
        ))
        self.checkForUpdates = checkForUpdates
    }

    var body: some View {
        ZStack {
            SettingsRootBackground()

            HStack(alignment: .top, spacing: LayoutConstants.outerMargin) {
                sidebar
                    .frame(width: LayoutConstants.sidebarWidth)
                    .padding(.bottom, LayoutConstants.sidebarBottomMargin)

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, LayoutConstants.outerMargin)
            .padding(.top, LayoutConstants.sidebarTopMargin)
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.windowCornerRadius, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .getOudioPresentSettingsAttention)) { notification in
            guard let item = notification.object as? SettingsAttentionItem else { return }
            present(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .getOudioShowOverviewSettings)) { _ in
            select(.overview)
        }
        .onReceive(NotificationCenter.default.publisher(for: .getOudioRefreshRecordingMicrophonePermission)) { _ in
            settingsViewModel.recordingSettings.refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settingsViewModel.recordingSettings.refresh()
        }
        .onAppear {
            guard attentionPresentation.highlightRequestID == 0 else { return }
            select(selection ?? .overview)
        }
        .onChange(of: attentionState.outstandingItems) {
            guard let selection else { return }
            attentionPresentation = SettingsAttentionPresentation(
                items: attentionState.outstandingItems.filter { $0.sidebarItem == selection },
                highlightRequestID: attentionPresentation.highlightRequestID + 1,
                scrollTarget: nil
            )
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: LayoutConstants.sidebarCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutConstants.sidebarCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutConstants.sidebarCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: SidebarLayout.sectionSpacing) {
                SidebarWindowControls()
                    .padding(.horizontal, SidebarLayout.contentHorizontalInset)
                    .padding(.top, SidebarLayout.windowControlTopInset)

                HStack(spacing: 0) {
                    Text("Get Oudio ")
                    Text("Settings")
                        .opacity(0.30)
                }
                    .font(.custom("Urbanist-Bold", size: 22))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SidebarLayout.contentHorizontalInset + 1)

                VStack(spacing: SidebarLayout.navigationRowSpacing) {
                    ForEach(MainSidebarItem.allCases) { item in
                        Button {
                            select(item)
                        } label: {
                            MainSidebarRow(
                                item: item,
                                isSelected: (selection ?? .overview) == item,
                                hasAttention: attentionState.outstandingItems.contains { $0.sidebarItem == item }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SidebarLayout.navigationHorizontalInset)

                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            DashboardView(
                finderSettings: settingsViewModel.finderSettings,
                systemExtensionSettings: settingsViewModel.systemExtensionSettings,
                recordingSettings: settingsViewModel.recordingSettings,
                diagnosticSettings: settingsViewModel.diagnosticSettings,
                attention: attentionPresentation,
                checkForUpdates: checkForUpdates
            )
        case .transcoding:
            TranscodingSettingsPage(
                presetSettings: settingsViewModel.presetSettings,
                defaultOpenWithSettings: settingsViewModel.defaultOpenWithSettings,
                attention: attentionPresentation,
                markDocumentationOpened: attentionState.markDocumentationOpened
            )
        case .ncm:
            NCMSettingsPage(
                ncmSettings: settingsViewModel.ncmSettings,
                defaultOpenWithSettings: settingsViewModel.defaultOpenWithSettings,
                attention: attentionPresentation,
                markDocumentationOpened: attentionState.markDocumentationOpened
            )
        case .appleMusic:
            AppleMusicSettingsPage(
                viewModel: settingsViewModel.appleMusicSettings,
                attention: attentionPresentation,
                markDocumentationOpened: attentionState.markDocumentationOpened
            )
        case .recording:
            RecordingSettingsPage(
                viewModel: settingsViewModel.recordingSettings,
                attention: attentionPresentation,
                markDocumentationOpened: attentionState.markDocumentationOpened
            )
        }
    }

    private func select(_ item: MainSidebarItem) {
        selection = item
        attentionPresentation = SettingsAttentionPresentation(
            items: attentionState.outstandingItems.filter { $0.sidebarItem == item },
            highlightRequestID: attentionPresentation.highlightRequestID + 1,
            scrollTarget: nil
        )
    }

    private func present(_ item: SettingsAttentionItem) {
        selection = item.sidebarItem
        attentionPresentation = SettingsAttentionPresentation(
            items: [item],
            highlightRequestID: attentionPresentation.highlightRequestID + 1,
            scrollTarget: item
        )
    }

    private static func initialSelection(for item: SettingsAttentionItem?) -> MainSidebarItem {
        item?.sidebarItem ?? .overview
    }
}

/// 红绿灯

private struct SidebarWindowControls: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            WindowControlButton(color: Color(red: 1.0, green: 0.36, blue: 0.34), symbol: "xmark") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
            }
            WindowControlButton(color: Color(red: 1.0, green: 0.76, blue: 0.18), symbol: "minus") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performMiniaturize(nil)
            }
            WindowControlButton(color: Color(red: 0.21, green: 0.78, blue: 0.35), symbol: "plus") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performZoom(nil)
            }
        }
        .environment(\.windowControlHovering, isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct WindowControlButton: View {
    @Environment(\.windowControlHovering) private var isHovering
    let color: Color
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                Image(systemName: symbol)
                    .font(.system(size: SidebarLayout.windowControlSymbolSize, weight: .bold))
                    .foregroundStyle(.black.opacity(isHovering ? 0.55 : 0))
            }
            .frame(width: SidebarLayout.windowControlSize, height: SidebarLayout.windowControlSize)
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.12), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WindowControlHoveringKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var windowControlHovering: Bool {
        get { self[WindowControlHoveringKey.self] }
        set { self[WindowControlHoveringKey.self] = newValue }
    }
}

/// 导航项

private struct MainSidebarRow: View {
    let item: MainSidebarItem
    let isSelected: Bool
    let hasAttention: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: item.systemImage)
                .font(.system(size: SidebarLayout.navigationIconSize, weight: .medium))
                .frame(width: SidebarLayout.iconColumnWidth, alignment: .center)
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.92)
            Spacer(minLength: 0)
            if hasAttention {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .padding(.trailing, SidebarLayout.navigationIconVisualInset)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(backgroundColor)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityValue(hasAttention ? "有待完成设置" : "")
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor
        }

        return isHovering ? Color.primary.opacity(0.08) : .clear
    }
}

private enum SidebarLayout {
    static let contentHorizontalInset: CGFloat = 18
    static let navigationHorizontalInset: CGFloat = 16
    static let windowControlTopInset: CGFloat = 16
    static let windowControlSize: CGFloat = 14
    static let windowControlSymbolSize: CGFloat = 8
    static let sectionSpacing: CGFloat = 26
    static let navigationRowSpacing: CGFloat = 6
    static let iconColumnWidth: CGFloat = 30
    static let navigationIconSize: CGFloat = 16
    static let navigationIconVisualInset: CGFloat = (iconColumnWidth - navigationIconSize) / 2
}

private enum MainSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case transcoding
    case ncm
    case appleMusic
    case recording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "授权/关于"
        case .transcoding: return "音频重编码"
        case .ncm: return "NCM 解密"
        case .appleMusic: return "Apple Music 下载"
        case .recording: return "录音"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gear"
        case .transcoding: return "waveform"
        case .ncm: return "music.note"
        case .appleMusic: return "square.and.arrow.down"
        case .recording: return "record.circle"
        }
    }
}

private extension SettingsAttentionItem {
    var sidebarItem: MainSidebarItem {
        switch self {
        case .microphonePermission:
            .overview
        case .transcodingDocumentation:
            .transcoding
        case .ncmDocumentation:
            .ncm
        case .appleMusicDocumentation, .appleMusicDependencies, .appleMusicInitialization:
            .appleMusic
        case .recordingDocumentation, .recordingInput:
            .recording
        }
    }
}

extension Notification.Name {
    static let getOudioPresentSettingsAttention = Notification.Name("GetOudioPresentSettingsAttention")
    static let getOudioShowOverviewSettings = Notification.Name("GetOudioShowOverviewSettings")
    static let getOudioRefreshRecordingMicrophonePermission = Notification.Name("GetOudioRefreshRecordingMicrophonePermission")
}
