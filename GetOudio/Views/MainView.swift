import AppKit
import SwiftUI

private enum MainLayoutMetrics {
    static let windowCornerRadius: CGFloat = 28
    static let outerMargin: CGFloat = 22
    static let sidebarWidth: CGFloat = 272
}

struct MainView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var selection: MainSidebarItem? = .overview

    var body: some View {
        ZStack {
            SettingsRootBackground()

            HStack(alignment: .top, spacing: MainLayoutMetrics.outerMargin) {
                sidebar
                    .frame(width: MainLayoutMetrics.sidebarWidth)
                    .padding(.bottom, MainLayoutMetrics.outerMargin)

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, MainLayoutMetrics.outerMargin)
            .padding(.top, MainLayoutMetrics.outerMargin)
        }
        .clipShape(RoundedRectangle(cornerRadius: MainLayoutMetrics.windowCornerRadius, style: .continuous))
    }

    private var sidebar: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: MainLayoutMetrics.windowCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: MainLayoutMetrics.windowCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MainLayoutMetrics.windowCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 16) {
                SidebarWindowControls()
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Get Oudio")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Settings")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                VStack(spacing: 8) {
                    ForEach(MainSidebarItem.allCases) { item in
                        Button {
                            selection = item
                        } label: {
                            MainSidebarRow(item: item, isSelected: (selection ?? .overview) == item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            DashboardView(viewModel: settingsViewModel.finderSettings)
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
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(isHovering ? 0.55 : 0))
            }
            .frame(width: 12, height: 12)
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

private struct MainSidebarRow: View {
    let item: MainSidebarItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 18, alignment: .center)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.92)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum MainSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case transcoding
    case ncm
    case appleMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .transcoding: return "Re-Encoding"
        case .ncm: return "NCM Transcoder"
        case .appleMusic: return "Apple Music Downloader"
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
