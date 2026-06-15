import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    DashboardView()
                } label: {
                    Label("概览", systemImage: "waveform")
                }

                NavigationLink {
                    AppleMusicSetupView()
                } label: {
                    Label("Apple Music 初始化", systemImage: "music.note")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DashboardView()
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

