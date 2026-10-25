import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity while a lecture records: on the lock screen and in the Dynamic Island, the class, the time
/// (counting while it records, held while paused) and Pause and Stop.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the clock would have started, had it never paused: the timer counts from here.
        var countingFrom: Date
        var paused: Bool
        /// The time when paused.
        var elapsed: Double
        /// "Saving…" after Stop.
        var finishing: Bool = false
    }

    var title: String
    var className: String?
    /// The class's highlighter by name ("yellow"), as `Highlighter(rawValue:)` reads it; nil for none.
    var highlighter: String?

    init(title: String, className: String?, highlighter: String?) {
        self.title = title
        self.className = className
        self.highlighter = highlighter
    }

    /// For the recorder, which knows the class and not its highlighter: it's the one the widgets were last told for
    /// that class. `colorHex` is from before highlighters, and unused.
    init(title: String, className: String?, colorHex: String? = nil) {
        self.init(title: title, className: className, highlighter: Glance.load()?.hue(of: className))
    }
}

/// Stop the recording (and send it to the library) from the lock screen.
struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let description = IntentDescription("Stops the lecture recording and sends it to your library.")

    func perform() async throws -> some IntentResult {
        await RecordingControl.stop?()
        // One left by a recording the app didn't finish (closed, or it crashed) goes too.
        await RecordingControl.endLeftovers()
        return .result()
    }
}

/// Pause or carry on recording from the lock screen.
struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume recording"

    func perform() async throws -> some IntentResult {
        if await RecordingControl.isRecording?() == true {
            await RecordingControl.togglePause?()
        } else {
            // Nothing is recording: it's one left by a recording the app didn't finish.
            await RecordingControl.endLeftovers()
        }
        return .result()
    }
}

/// Record: opens Study Stash recording, into the class on now (Control Center, the Action button, Siri). A widget's
/// Record, for its class, is `RecordClassIntent`.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record"
    static let description = IntentDescription("Starts recording in Study Stash, into the class on your calendar now.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await RecordingControl.start?()
        return .result()
    }
}

/// What the intents do, set by the app (the intents run in its process; the widget only shows them).
@MainActor
enum RecordingControl {
    static var stop: (@MainActor () async -> Void)?
    static var togglePause: (@MainActor () -> Void)?
    static var start: (@MainActor () -> Void)?
    /// Something is recording (or paused) in this app right now.
    static var isRecording: (@MainActor () -> Bool)?

    /// Ends every recording Live Activity: one left on the lock screen, its clock still counting, by a recording the
    /// app didn't finish (the app was closed or crashed while it recorded).
    static func endLeftovers() async {
        for activity in Activity<RecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

// MARK: - How it looks

// The desktop's recording bar and mini recorder (the note page while it records, mac-02-recorder): the red dot and
// what it's doing ("Recording", "Paused", "Saving…"), the time; the class as its swatch and name, the title; Pause a
// plain pill, Stop the ink one. Red is only the dot (and the island's rim). A tap opens the recording. Here, not in
// the widget extension, so the app's widget gallery draws them too.

extension RecordingAttributes.ContentState {
    /// What it's doing: "Recording", "Paused", "Saving…".
    var status: String { finishing ? "Saving…" : paused ? "Paused" : "Recording" }
    /// The dot is still: paused, or saving.
    var still: Bool { paused || finishing }
}

extension RecordingAttributes {
    /// A title of the student's own (not the one it goes by until it has one: "Calculus II, Fri 16 Oct").
    var ownTitle: String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let cls = className, t.hasPrefix("\(cls), ") || t == cls { return nil }
        return t
    }
}

/// The time: counting while it records, held while paused or saving ("12:04", "1:02:03").
struct RecordingClock: View {
    var state: RecordingAttributes.ContentState
    var body: some View {
        if state.still {
            Text(Format.clock(state.elapsed))
        } else {
            Text(timerInterval: state.countingFrom...Date.distantFuture, countsDown: false)
        }
    }
}

/// What's recording: its class's swatch and name, then its title when the student gave it one (muted); with no
/// class, its title ("Recording, Fri 16 Oct at 9:41 AM").
struct RecordingName: View {
    var attributes: RecordingAttributes
    var body: some View {
        HStack(spacing: 8) {
            if let cls = attributes.className {
                WidgetSwatch(Highlighter(name: attributes.highlighter), small: false)
                Text(cls).font(.atkinson(15, .bold, relativeTo: .body)).foregroundStyle(.ink).lineLimit(1)
                    .layoutPriority(1)
                if let own = attributes.ownTitle {
                    Text(own).textStyle(.crumb).foregroundStyle(.inkMuted).lineLimit(1)
                }
            } else {
                Text(attributes.title.isEmpty ? "Recording" : attributes.title)
                    .font(.atkinson(15, .bold, relativeTo: .body)).foregroundStyle(.ink).lineLimit(1)
            }
        }
    }
}

/// Pause (or Resume) and Stop, as the desktop's bar has them: a plain pill and the ink one. Nothing while it saves.
struct RecordingControls: View {
    var state: RecordingAttributes.ContentState
    var body: some View {
        if !state.finishing {
            HStack(spacing: 8) {
                Button(intent: PauseRecordingIntent()) {
                    pill(state.paused ? "Resume" : "Pause", icon: state.paused ? "play_arrow" : "pause", filled: state.paused)
                        .foregroundStyle(.ink)
                        .background(Capsule().fill(.surface))
                        .overlay(Capsule().strokeBorder(.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.paused ? "Resume recording" : "Pause recording")
                Button(intent: StopRecordingIntent()) {
                    pill("Stop", icon: "stop", filled: true)
                        .foregroundStyle(.surface)
                        .background(Capsule().fill(.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
        }
    }

    private func pill(_ words: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(icon: icon, filled: filled).resizable().frame(width: 14, height: 14)
            Text(words).textStyle(.buttonSmall).lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
        .fixedSize()
    }
}

/// The dot and what it's doing, then the time, as the desktop's bar starts.
private struct RecordingStatus: View {
    var state: RecordingAttributes.ContentState
    var clock: Font
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LiveDot(paused: state.still, size: 10).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(state.status).textStyle(.button).foregroundStyle(.ink).lineLimit(1)
            RecordingClock(state: state)
                .font(clock)
                .foregroundStyle(state.still ? Color.inkMuted : .ink)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// On the Lock Screen: the dot, what it's doing and the time; what's recording; Pause and Stop. On the page's
/// colour, light or dark as the phone is.
struct RecordingLockScreenView: View {
    var attributes: RecordingAttributes
    var state: RecordingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                RecordingStatus(state: state, clock: .atkinson(15, .medium, relativeTo: .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                RecordingControls(state: state)
            }
            RecordingName(attributes: attributes)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }
}

/// The Dynamic Island's pieces. The island is always black: its words take the dark inks.
enum RecordingIsland {
    /// Beside the camera, closed: the red dot.
    struct CompactLeading: View {
        var state: RecordingAttributes.ContentState
        var body: some View {
            LiveDot(paused: state.still, size: 10)
                .padding(.leading, 4)
        }
    }

    /// The other side: the time.
    struct CompactTrailing: View {
        var state: RecordingAttributes.ContentState
        var body: some View {
            RecordingClock(state: state)
                .font(.atkinson(15, .bold, relativeTo: .body))
                .foregroundStyle(Color.resolved(Palette.ink, dark: true))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 52, alignment: .trailing)
        }
    }

    /// Opened, top left: the dot and what it's doing.
    struct Leading: View {
        var state: RecordingAttributes.ContentState
        var body: some View {
            HStack(spacing: 8) {
                LiveDot(paused: state.still, size: 10)
                Text(state.status).textStyle(.button).foregroundStyle(.ink).lineLimit(1)
            }
            .padding(.leading, 6)
            .frame(maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Opened, top right: the time.
    struct Trailing: View {
        var state: RecordingAttributes.ContentState
        var body: some View {
            RecordingClock(state: state)
                .font(.atkinson(17, .bold, relativeTo: .headline))
                .foregroundStyle(state.still ? Color.inkMuted : .ink)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
                .environment(\.colorScheme, .dark)
        }
    }

    /// Opened, under it: what's recording, Pause and Stop.
    struct Bottom: View {
        var attributes: RecordingAttributes
        var state: RecordingAttributes.ContentState
        var body: some View {
            HStack(spacing: 10) {
                RecordingName(attributes: attributes).frame(maxWidth: .infinity, alignment: .leading)
                RecordingControls(state: state)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .environment(\.colorScheme, .dark)
        }
    }
}
