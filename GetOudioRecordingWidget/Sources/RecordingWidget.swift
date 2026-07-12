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

    var body: some View {
        Link(destination: URL(string: "getoudio://recording/toggle")!) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(entry.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 62, height: 62)
                    Image(systemName: entry.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(entry.isRecording ? "正在录音" : "开始录音")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct GetOudioRecordingWidget: Widget {
    let kind = AppConstants.recordingWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecordingWidgetProvider()) { entry in
            RecordingWidgetView(entry: entry)
        }
        .configurationDisplayName("Audio Bridge Recorder")
        .description("开始或停止 Pro Tools Audio Bridge 录音。")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct GetOudioRecordingWidgetBundle: WidgetBundle {
    var body: some Widget {
        GetOudioRecordingWidget()
    }
}

