import SwiftUI

/// A calendar event, as the desktop's Up next (`.event`): its time over its day, then its title and its class as a
/// highlight (an event that's just its class's name shows the name once, as the highlight). The whole row is the
/// button: a tap records it, into its class. One starting within a quarter of an hour says "In 11 minutes" in ink.
/// When the library didn't match a class but the title looks like one, a link offers to file every one like it; a
/// long press (or a swipe) files them in any class.
struct EventRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    var event: UpcomingEvent
    /// Offer the class it looks like (only on the first of a run of same-titled events).
    var suggest = true
    var onFiled: () -> Void = {}
    @State private var filing = false
    @State private var filed: String?

    var body: some View {
        let cls = filed ?? app.className(ofEvent: event)
        let start = Format.parse(event.start) ?? .now
        let end = Format.parse(event.end) ?? start
        let on = start <= .now && .now < end
        let soon = !on && start.timeIntervalSinceNow <= 15 * 60 && start > .now
        let day = on ? "Now" : soon ? Nouns.capital(Format.inMinutes(start.timeIntervalSinceNow)) : Format.day(start)
        let titleIsClass = cls.map { ClassMatch.normalized($0) == ClassMatch.normalized(event.title) } ?? false

        VStack(alignment: .leading, spacing: 6) {
            Button { app.record(for: cls, title: "\(titleIsClass ? cls ?? event.title : event.title), \(Format.words(start, "EEE d MMM"))") } label: {
                HStack(alignment: .center, spacing: sizeClass == .regular ? 20 : 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.allDay ? "All day" : Format.time(start)).textStyle(.when)
                            .foregroundStyle(soon || on ? Color.ink : .inkMuted)
                        Text(day).textStyle(.micro)
                            .foregroundStyle(soon || on ? Color.ink : .inkSubtle)
                    }
                    .frame(width: sizeClass == .regular ? 108 : 84, alignment: .leading)
                    FlowLayout(spacing: 8) {
                        if titleIsClass, let cls {
                            Highlight(cls, hue: app.hue(of: cls), style: .title)
                        } else {
                            Text(event.title).textStyle(.title).foregroundStyle(.ink)
                            if let cls { Highlight(cls, hue: app.hue(of: cls)) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if filing { StudyLoader(.inline, color: .inkSubtle) }
                }
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.row)
            .accessibilityLabel(said(cls, start: start, on: on, soon: soon))
            .accessibilityHint("Starts recording")

            if suggest, filed == nil, event.class == nil, let s = app.suggestion(forEvent: event) {
                Button("File every one in \(s)") { Task { await file(in: s) } }
                    .buttonStyle(.textLink)
                    .padding(.leading, sizeClass == .regular ? 128 : 98)
                    .padding(.bottom, 6)
            }
        }
        .contextMenu { menu }
        .swipeActions(edge: .trailing) {
            Menu { menu } label: { Label("File", icon: "drive_file_move") }.tint(.inkMuted)
        }
    }

    /// "Record Capstone team sync as a lecture, starts in 11 minutes".
    private func said(_ cls: String?, start: Date, on: Bool, soon: Bool) -> String {
        let day = Format.day(start)
        let when = on ? "on now" : soon ? "starts \(Format.inMinutes(start.timeIntervalSinceNow))"
            : "\(["Today", "Tomorrow"].contains(day) ? day.lowercased() : "on \(day)") at \(Format.time(start))"
        return "Record \(event.title) as a \(app.noun(of: cls)), \(when)"
    }

    @ViewBuilder private var menu: some View {
        Section("Every “\(event.title)” goes in") {
            ForEach(app.classes) { c in
                Button { Task { await file(in: c.name) } } label: {
                    if (filed ?? app.className(ofEvent: event)) == c.name { Label(c.name, icon: "check") } else { Text(c.name) }
                }
            }
        }
        Button { app.record(for: filed ?? app.className(ofEvent: event)) } label: { Label("Record it", icon: "mic") }
    }

    private func file(in cls: String) async {
        filing = true
        defer { filing = false }
        do {
            try await app.file(event: event, in: cls)
            filed = cls
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFiled()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
