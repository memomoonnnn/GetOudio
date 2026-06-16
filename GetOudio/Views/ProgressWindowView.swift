import GetOudioCore
import SwiftUI

struct ProgressWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(appModel.progressItems) { item in
                    progressRow(item)
                }
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: scheduleCloseIfFinished)
        .onChange(of: appModel.progressItems) { _, _ in
            scheduleCloseIfFinished()
        }
        .onChange(of: appModel.isRunning) { _, _ in
            scheduleCloseIfFinished()
        }
    }

    @ViewBuilder
    private func progressRow(_ item: ConversionProgressItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.fileName)
                .font(.callout)
                .lineLimit(1)

            if let value = item.progressValue {
                ProgressView(value: value)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func scheduleCloseIfFinished() {
        closeTask?.cancel()
        guard !appModel.isRunning, !appModel.progressItems.isEmpty else {
            return
        }

        let hasFailures = appModel.progressItems.contains { $0.phase == .failed }
        let delay: UInt64 = hasFailures ? 3_500_000_000 : 1_200_000_000
        closeTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let shouldResetMainWindow = appModel.showsProgressInMainWindow
                dismiss()
                if shouldResetMainWindow {
                    appModel.finishProgressWindowDismissal()
                }
            }
        }
    }
}
