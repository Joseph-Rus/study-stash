import SwiftUI
import WidgetKit

struct GlanceEntry: TimelineEntry {
    var date: Date
    var glance: Glance?
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry { GlanceEntry(date: .now, glance: .sample(at: .now)) }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        // The gallery's preview shows the demo week; on the Home Screen, what the app last saw.
        completion(GlanceEntry(date: .now, glance: context.isPreview ? .sample(at: .now) : Glance.load() ?? .sample(at: .now)))
    }

    /// An entry now and one at each moment the words change ("starts in 11 minutes" each minute of the hour before a
    /// class, each start and end, each deadline, each midnight), so it keeps itself right without the app. The app
    /// writes a fresh Glance and reloads it whenever it has a fresh look at the library.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let g = Glance.load()
        let now = Date.now
        let dates = [now] + (g?.changes(after: now) ?? [])
        completion(Timeline(entries: dates.map { GlanceEntry(date: $0, glance: g) }, policy: .after(now.addingTimeInterval(3600))))
    }
}

/// The next class and what's due, on the Home Screen and the Lock Screen.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.studystash.ios.upnext", provider: GlanceProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up next")
        .description("Your next class and what's due.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

private struct UpNextWidgetView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        UpNextView(glance: entry.glance, now: entry.date, family: family)
            .environment(\.widgetFullColor, mode == .fullColor)
            // Sizes that can't grow have a ceiling on Dynamic Type, as the system's own widgets do.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline: Color.clear
                default: Color.surface
                }
            }
    }
}
