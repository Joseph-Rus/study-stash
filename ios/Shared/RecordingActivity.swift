import ActivityKit
import AppIntents
import Foundation

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
    /// The class's colour, "#rrggbb".
    var colorHex: String?
}

/// Stop the recording (and send it to the library) from the lock screen.
struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let description = IntentDescription("Stops the lecture recording and sends it to your library.")

    func perform() async throws -> some IntentResult {
        await RecordingControl.stop?()
        return .result()
    }
}

/// Pause or carry on recording from the lock screen.
struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume recording"

    func perform() async throws -> some IntentResult {
        await RecordingControl.togglePause?()
        return .result()
    }
}

/// Start recording a lecture: opens Study Stash on the recording screen (Control Center, the Action button, Siri).
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a lecture"
    static let description = IntentDescription("Starts recording a lecture in Study Stash.")
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
}
