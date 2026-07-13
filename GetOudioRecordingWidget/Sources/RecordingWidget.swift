import GetOudioCore
import SwiftUI
import WidgetKit

private struct RecordingWidgetEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
}

private struct RecordingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordingWidgetEntry {
        RecordingWidgetEntry(date: Date(), isRecording: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordingWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordingWidgetEntry>) -> Void) {
        let entry = entry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
    }

    private func entry() -> RecordingWidgetEntry {
        guard let container = try? SharedContainer.production(),
              let store = try? RecordingControlStore(container: container) else {
            return RecordingWidgetEntry(date: Date(), isRecording: false)
        }
        return RecordingWidgetEntry(date: Date(), isRecording: store.snapshot().phase.isActive)
    }
}

private struct RecordingWidgetView: View {
    let entry: RecordingWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    private var cardFill: LinearGradient {
        let colors: [Color]
        if entry.isRecording {
            colors = [
                Color(red: 1, green: 0.24, blue: 0.25),
                Color(red: 0.68, green: 0.04, blue: 0.08)
            ]
        } else if colorScheme == .dark {
            colors = [Color(white: 0.16), .black]
        } else {
            colors = [.white, Color(white: 0.9)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var labelFill: LinearGradient {
        let colors: [Color] = entry.isRecording
            ? [.white, Color(white: 0.82)]
            : [
                Color(red: 0.64, green: 0.02, blue: 0.07),
                Color(red: 0.98, green: 0.2, blue: 0.23)
            ]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var cardShadow: Color {
        .black.opacity(colorScheme == .dark ? 0.45 : 0.18)
    }

    var body: some View {
        Link(destination: URL(string: "getoudio://recording/toggle")!) {
            ZStack(alignment: .bottomLeading) {
                ContainerRelativeShape()
                    .fill(.ultraThinMaterial)

                ContainerRelativeShape()
                    .fill(cardFill)
                    .shadow(color: cardShadow, radius: 3, x: 0, y: 1)
                    .padding(8)

                Text(entry.isRecording ? "结束录音..." : "录音开始！")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(labelFill)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .padding(22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerBackground(.clear, for: .widget)
    }
}

private struct GetOudioRecordingWidget: Widget {
    let kind = AppConstants.recordingWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecordingWidgetProvider()) { entry in
            RecordingWidgetView(entry: entry)
        }
        .configurationDisplayName("Recorder")
        .description("开始或停止录音。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct GetOudioRecordingWidgetBundle: WidgetBundle {
    var body: some Widget {
        GetOudioRecordingWidget()
    }
}
