import SwiftUI
import WidgetKit

struct GlanceEntry: TimelineEntry {
    var date: Date
    var glance: Glance?
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry { GlanceEntry(date: .now, glance: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: .now, glance: Glance.load() ?? .sample))
    }
    /// An entry now and one as each class ends, so the next one moves up without the app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let g = Glance.load()
        var dates = [Date.now]
        dates += (g?.events ?? []).map(\.end).filter { $0 > .now }.prefix(5)
        completion(Timeline(entries: dates.map { GlanceEntry(date: $0, glance: g) }, policy: .after(.now.addingTimeInterval(3600))))
    }
}

/// The next class and what's due next, on the Home Screen and the Lock Screen.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.studystash.ios.upnext", provider: GlanceProvider()) { entry in
            UpNextView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up next")
        .description("Your next class and what's due.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GlanceEntry

    private var event: Glance.Event? { entry.glance?.events.first { $0.end > entry.date } }
    private var due: [Glance.Due] { (entry.glance?.due ?? []).filter { $0.due > entry.date.addingTimeInterval(-86_400 * 30) } }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let d = due.first { Text("\(d.name) · \(d.due, style: .relative)") } else if let e = event { Text("\(e.title) \(e.start, style: .time)") } else { Text("Nothing due") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let e = event {
                    Text(e.title).font(.headline).lineLimit(1)
                    Text(e.start, style: .time).font(.caption)
                }
                if let d = due.first {
                    Text(d.name).font(event == nil ? .headline : .caption).lineLimit(1)
                    Text("due \(d.due, style: .relative)").font(.caption2)
                }
                if event == nil && due.isEmpty { Text("Nothing coming up").font(.headline) }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                nextClass.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                dueList.frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                nextClass
                if let d = due.first { dueRow(d) }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var nextClass: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if let e = event {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: e.color) ?? .accentColor).frame(width: 7, height: 7)
                    Text(e.title).font(.headline).lineLimit(2)
                }
                Text(e.start <= entry.date ? "Now · until \(e.end.formatted(date: .omitted, time: .shortened))" : e.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
                if let l = e.location { Text(l).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            } else {
                Text("No more classes").font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private var dueList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DUE · \(entry.glance?.toHandIn ?? 0)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            ForEach(due.prefix(3), id: \.self) { dueRow($0) }
            if due.isEmpty { Text("Nothing due").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func dueRow(_ d: Glance.Due) -> some View {
        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: d.color) ?? .secondary).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text(d.due, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(d.overdue ? .red : .secondary)
            }
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
