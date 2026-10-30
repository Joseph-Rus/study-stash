import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct StudyStashWidgets: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        RecordingLiveActivity()
        RecordControl()
    }
}

/// Recording, on the lock screen and in the Dynamic Island: the views are in Shared/RecordingActivity.swift. A tap
/// opens the recording.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenRecording(attributes: context.attributes, state: context.state)
                .widgetURL(WidgetLink.recording.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { RecordingIsland.Leading(state: context.state) }
                DynamicIslandExpandedRegion(.trailing) { RecordingIsland.Trailing(state: context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    RecordingIsland.Bottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                RecordingIsland.CompactLeading(state: context.state)
            } compactTrailing: {
                RecordingIsland.CompactTrailing(state: context.state)
            } minimal: {
                RecordingIsland.CompactLeading(state: context.state)
            }
            .widgetURL(WidgetLink.recording.url)
            .keylineTint(.record)
        }
    }
}

/// The Lock Screen's banner on the page's colour, light or dark as the phone is (the system paints the background
/// itself, so it's given the token as it is in that appearance).
private struct LockScreenRecording: View {
    var attributes: RecordingAttributes
    var state: RecordingAttributes.ContentState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RecordingLockScreenView(attributes: attributes, state: state)
            .activityBackgroundTint(Color.resolved(Palette.surface, dark: scheme == .dark))
            .activitySystemActionForegroundColor(Color.resolved(Palette.ink, dark: scheme == .dark))
    }
}

/// Record, in Control Center and on the Action button. The system draws controls, and takes only its own symbols.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.studystash.ios.record") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Record", systemImage: "record.circle")
            }
        }
        .displayName("Record")
        .description("Starts recording in Syft Notes, into the class on your calendar now.")
    }
}
