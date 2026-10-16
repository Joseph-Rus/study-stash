import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct StudyStashWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        RecordControl()
    }
}

/// Recording, on the lock screen and in the Dynamic Island.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenRecording(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.attributes.className ?? "Recording").lineLimit(1) } icon: { RecDot(paused: context.state.paused) }
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(state: context.state).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Controls(state: context.state)
                    }
                }
            } compactLeading: {
                RecDot(paused: context.state.paused)
            } compactTrailing: {
                Clock(state: context.state).monospacedDigit().foregroundStyle(.red).frame(maxWidth: 52)
            } minimal: {
                RecDot(paused: context.state.paused)
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenRecording: View {
    var context: ActivityViewContext<RecordingAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.red.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: context.state.paused ? "pause.fill" : "mic.fill").font(.title3).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.className ?? "Recording a lecture").font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(context.state.finishing ? "Saving…" : context.state.paused ? "Paused" : "Writing down what's said")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Clock(state: context.state).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            Controls(state: context.state)
        }
        .padding(16)
    }
}

private struct Clock: View {
    var state: RecordingAttributes.ContentState
    var body: some View {
        if state.paused || state.finishing {
            let s = Int(state.elapsed)
            Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60))
        } else {
            Text(timerInterval: state.countingFrom...Date.distantFuture, countsDown: false)
        }
    }
}

private struct RecDot: View {
    var paused: Bool
    var body: some View {
        Image(systemName: paused ? "pause.circle.fill" : "record.circle").foregroundStyle(.red)
    }
}

private struct Controls: View {
    var state: RecordingAttributes.ContentState
    var body: some View {
        if !state.finishing {
            HStack(spacing: 8) {
                Button(intent: PauseRecordingIntent()) {
                    Image(systemName: state.paused ? "play.fill" : "pause.fill").frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.15), in: .circle)
                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill").frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.red, in: .circle)
            }
            .foregroundStyle(.white)
        }
    }
}

/// Record, in Control Center and on the Action button.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.studystash.ios.record") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Record lecture", systemImage: "mic.fill")
            }
        }
        .displayName("Record a lecture")
        .description("Starts recording a lecture in Study Stash.")
    }
}
