import SwiftUI

struct MainView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var selection: MainSidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MainSidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            DashboardView()
        case .transcoding:
            TranscodingSettingsPage(viewModel: settingsViewModel)
        case .ncm:
            NCMSettingsPage(viewModel: settingsViewModel)
        case .appleMusic:
            AppleMusicSettingsPage(viewModel: settingsViewModel)
        }
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
