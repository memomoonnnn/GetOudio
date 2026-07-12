import AppKit
import GetOudioCore
import SwiftUI

struct MainView: View {
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var selection: MainSidebarItem? = .overview

    init(container: SharedContainer) {
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(container: container))
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
                            selection = item
                        } label: {
                            MainSidebarRow(item: item, isSelected: (selection ?? .overview) == item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SidebarLayout.contentHorizontalInset)

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
                systemExtensionSettings: settingsViewModel.systemExtensionSettings
            )
        case .transcoding:
            TranscodingSettingsPage(
                presetSettings: settingsViewModel.presetSettings,
                defaultOpenWithSettings: settingsViewModel.defaultOpenWithSettings
            )
        case .ncm:
            NCMSettingsPage(
                ncmSettings: settingsViewModel.ncmSettings,
                defaultOpenWithSettings: settingsViewModel.defaultOpenWithSettings
            )
        case .appleMusic:
            AppleMusicSettingsPage(viewModel: settingsViewModel.appleMusicSettings)
        }
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
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private enum SidebarLayout {
    static let contentHorizontalInset: CGFloat = 18
    static let windowControlTopInset: CGFloat = 16
    static let windowControlSize: CGFloat = 14
    static let windowControlSymbolSize: CGFloat = 8
    static let sectionSpacing: CGFloat = 26
    static let navigationRowSpacing: CGFloat = 6
    static let iconColumnWidth: CGFloat = 30
    static let navigationIconSize: CGFloat = 16
    static let iconVisualLeadingInset: CGFloat = contentHorizontalInset
        + (iconColumnWidth - navigationIconSize) / 2
}

private enum MainSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case transcoding
    case ncm
    case appleMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "授权/关于"
        case .transcoding: return "音频重编码"
        case .ncm: return "NCM解密"
        case .appleMusic: return "Apple Music 下载"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "waveform"
        case .transcoding: return "slider.horizontal.3"
        case .ncm: return "music.note"
        case .appleMusic: return "arrow.down.circle"
        }
    }
}
