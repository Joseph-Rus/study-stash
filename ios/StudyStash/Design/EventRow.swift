import SwiftUI

/// A calendar event: its class's colour, title, when and where; when the library didn't match a class but the title
/// looks like one, that class as a suggestion to confirm; and a menu to file every event with this title in a class.
struct EventRow: View {
    @Environment(AppModel.self) private var app
    var event: UpcomingEvent
    /// Offer the class it looks like (only on the first of a run of same-titled events).
    var suggest = true
    var onFiled: () -> Void = {}
    @State private var filing = false
    @State private var filed: String?

    var body: some View {
        let cls = filed ?? app.className(ofEvent: event)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill((cls.map { app.color(of: $0) } ?? .secondary).gradient).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium)).lineLimit(1)
                Text([Format.dayLabel(Format.parse(event.start) ?? .now), Format.timeRange(event.start, event.end, allDay: event.allDay), event.location]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if suggest, filed == nil, event.class == nil, let s = app.suggestion(forEvent: event) {
                    Button { Task { await file(in: s) } } label: {
                        Label("File every one in \(s)?", systemImage: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(app.color(of: s))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if filing { ProgressView() }
        }
        .contextMenu { menu }
        .swipeActions(edge: .trailing) {
            Menu { menu } label: { Label("File", systemImage: "folder") }.tint(.accentColor)
        }
    }

    @ViewBuilder private var menu: some View {
        Section("Every “\(event.title)” goes in") {
            ForEach(app.classes) { c in
                Button { Task { await file(in: c.name) } } label: {
                    if (filed ?? app.className(ofEvent: event)) == c.name { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
        }
        Button { app.record(for: filed ?? app.className(ofEvent: event)) } label: { Label("Record it", systemImage: "mic.fill") }
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
