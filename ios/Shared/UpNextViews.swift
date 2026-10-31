import AppIntents
import SwiftUI
import WidgetKit

// Up next, on the Home Screen and the Lock Screen, in the desktop's words and marks (FLOWS.md, "widgets"): "Up next",
// the next class as its name marked with its highlighter, when in the desktop's Coming up words ("In 11 minutes",
// "Now, until 9:50 AM", "Tomorrow 9:00 AM"), where in muted ink; a Record pill (the one red, its dot) while the class
// is on or about to start; what's due as its name marked in its class's highlighter, when under it, "Missing" in the
// late red. The biggest is Home itself: the date, Home's sentence, Up next and Due. A tap anywhere else opens Home; on
// something due, it opens it. Here, not in the widget extension, so the app's widget gallery draws them too.

/// Up next in any of its sizes, for `glance` (nil: the app hasn't said anything yet) as it is at `now`.
struct UpNextView: View {
    var glance: Glance?
    var now: Date
    var family: WidgetFamily
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: UpNextInline(glance: glance, now: now)
            case .accessoryRectangular: UpNextRectangular(glance: glance, now: now)
            case .accessoryCircular: UpNextCircular(glance: glance, now: now)
            case .systemMedium: UpNextMedium(glance: glance, now: now)
            case .systemLarge, .systemExtraLarge: UpNextLarge(glance: glance, now: now)
            default: UpNextSmall(glance: glance, now: now)
            }
        }
        .foregroundStyle(Inks(full: full).ink)
    }
}

/// What the widgets say with nothing to say.
enum UpNextWords {
    /// Before the app has told the widgets anything.
    static let notYet = "Open Syft Notes to see what's next."
    static let nothingOn = "Nothing on your calendar today."
    static let nothingDue = "Nothing to hand in."
}

// MARK: - The pieces

/// A heading over a widget's list: "Up next", "Due" (the desktop's rail headings).
struct WidgetHeading: View {
    var text: String
    var body: some View {
        Text(text).textStyle(.railTitle).lineLimit(1).accessibilityAddTraits(.isHeader)
    }
}

/// An event's name: its class's name marked, once, when that's all it's called ("Calculus II"); else its title, with
/// its class marked under it (or beside it, where there's room).
struct EventName: View {
    var event: Glance.Event
    var titleLines = 1
    /// The class beside the title when it fits (a wide row), else under it.
    var beside = false
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        let hue = Highlighter(name: event.color)
        if event.isClass, let cls = event.className {
            WidgetHighlight(cls, hue: hue, style: .title)
        } else if beside, let cls = event.className {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title.fixedSize()
                    WidgetHighlight(cls, hue: hue).fixedSize()
                }
                stacked(cls, hue)
            }
        } else if let cls = event.className {
            stacked(cls, hue)
        } else {
            title
        }
    }

    private var title: some View {
        Text(event.title).textStyle(.title).lineLimit(titleLines).foregroundStyle(Inks(full: full).ink)
    }

    private func stacked(_ cls: String, _ hue: Highlighter?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            title
            WidgetHighlight(cls, hue: hue)
        }
    }
}

/// When an event is, in one line: "In 11 minutes" and "Now, until 9:50 AM" in ink, "Tomorrow 9:00 AM" muted.
struct EventWhenLine: View {
    var event: Glance.Event
    var now: Date
    @Environment(\.widgetFullColor) private var full
    var body: some View {
        let hot = event.isOn(at: now) || event.isSoon(at: now)
        let inks = Inks(full: full)
        Text(event.when(at: now)).textStyle(.when)
            .foregroundStyle(hot ? inks.ink : inks.muted)
            .lineLimit(1)
    }
}

/// An event's time over its day ("9:00 AM" over "In 11 minutes"), as Home's Up next has it, in ink when it's on or
/// about to start.
struct EventWhen: View {
    var event: Glance.Event
    var now: Date
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        let hot = event.isOn(at: now) || event.isSoon(at: now)
        let inks = Inks(full: full)
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.time(event.start)).textStyle(.when)
                .foregroundStyle(hot ? inks.ink : inks.muted)
            Text(event.day(at: now)).textStyle(.micro)
                .fontWeight(hot ? .bold : .medium)
                .foregroundStyle(hot ? inks.ink : inks.subtle)
        }
        .lineLimit(1)
    }
}

/// The next event after the first, small, as the desktop sidebar's Coming up: its class's swatch and its title, when
/// under it.
struct ComingRow: View {
    var event: Glance.Event
    var now: Date
    @Environment(\.widgetFullColor) private var full
    var body: some View {
        let inks = Inks(full: full)
        let hot = event.isOn(at: now) || event.isSoon(at: now)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WidgetSwatch(Highlighter(name: event.color))
                Text(event.title).font(.atkinson(14, .bold, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(inks.ink)
            }
            Text(event.when(at: now)).textStyle(.micro)
                .fontWeight(hot ? .bold : .medium)
                .foregroundStyle(hot ? inks.ink : inks.subtle)
                .lineLimit(1)
                .padding(.leading, 17)
        }
    }
}

/// Something due: its name marked in its class's highlighter (as the calendar marks it), when under it ("Tomorrow,
/// 11:59 PM", in ink when it's today), "Missing" in the late red.
struct DueLine: View {
    var item: Glance.Due
    var now: Date
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        let inks = Inks(full: full)
        let soon = item.isSoon(at: now)
        VStack(alignment: .leading, spacing: 1) {
            WidgetHighlight(item.name, hue: Highlighter(name: item.color), style: .due)
            Text(item.overdue ? "Missing" : item.when(at: now)).textStyle(.micro)
                .fontWeight(soon || item.overdue ? .bold : .medium)
                .foregroundStyle(item.overdue ? inks.late : soon ? inks.ink : inks.subtle)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Record, as the desktop's pill: white, outlined, red only in its dot. It starts recording the class (opening the
/// app on the recording).
struct WidgetRecordPill: View {
    var className: String?
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        Button(intent: RecordClassIntent(className: className)) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(full ? Color.record : .primary)
                    Circle().fill(full ? Color.onRecord : Color.clear).frame(width: 8, height: 8)
                }
                .frame(width: 24, height: 24)
                .widgetAccentable()
                Text("Record").textStyle(.button).foregroundStyle(Inks(full: full).ink)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background(full ? AnyShapeStyle(Color.surface) : AnyShapeStyle(Color.primary.opacity(0.12)), in: .capsule)
            .overlay(Capsule().strokeBorder(full ? Color.line : .primary.opacity(0.25)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(className.map { "Record \($0)" } ?? "Record")
    }
}

/// Record a class from a widget: opens Syft Notes recording it (`studystash://record?class=`), as tapping it in Up
/// next does. Control Center, the Action button and Siri use `StartRecordingIntent`, for the class on now.
struct RecordClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Record"
    static let description = IntentDescription("Starts recording a class in Syft Notes.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Class") var className: String?

    init() {}
    init(className: String?) { self.className = className }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.record(className: className).url))
    }
}

/// A link on a part of a widget (medium and large; a small one is one tap).
private struct Tap<Content: View>: View {
    var link: WidgetLink
    @ViewBuilder var content: Content
    var body: some View {
        Link(destination: link.url) { content }
    }
}

/// Something due, opening it (or Due, from an app before the widgets knew its id).
private struct DueTap: View {
    var item: Glance.Due
    var now: Date
    var body: some View {
        if let id = item.id {
            Tap(link: .assignment(className: item.className, id: id)) { DueLine(item: item, now: now) }
        } else {
            Tap(link: .due) { DueLine(item: item, now: now) }
        }
    }
}

/// The next class and when, where, and Record while it's on or about to start.
private struct NextClass: View {
    var event: Glance.Event
    var now: Date
    var titleLines = 1
    @Environment(\.widgetFullColor) private var full
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventName(event: event, titleLines: titleLines)
            EventWhenLine(event: event, now: now).padding(.top, 5)
            if let place = event.location, !place.isEmpty {
                Text(place).textStyle(.micro).foregroundStyle(Inks(full: full).subtle).lineLimit(1).padding(.top, 1)
            }
        }
    }
}

extension Glance.Event {
    /// The widget offers Record: it's on, or starts within a quarter of an hour.
    func offersRecord(at now: Date) -> Bool { isOn(at: now) || isSoon(at: now) }
}

// MARK: - Small: the next class

struct UpNextSmall: View {
    var glance: Glance?
    var now: Date
    @Environment(\.widgetFullColor) private var full

    var body: some View {
        let inks = Inks(full: full)
        let coming = glance?.coming(at: now) ?? []
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(text: "Up next")
            if let e = coming.first {
                NextClass(event: e, now: now, titleLines: 2).padding(.top, 6)
                Spacer(minLength: 6)
                if e.offersRecord(at: now) {
                    WidgetRecordPill(className: e.className)
                } else if coming.count > 1 {
                    ComingRow(event: coming[1], now: now)
                }
            } else {
                Text(glance == nil ? UpNextWords.notYet : UpNextWords.nothingOn)
                    .textStyle(.meta).foregroundStyle(inks.muted).padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home.url)
    }
}

// MARK: - Medium: Up next beside Due

struct UpNextMedium: View {
    var glance: Glance?
    var now: Date
    @Environment(\.widgetFullColor) private var full
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let inks = Inks(full: full)
        let coming = glance?.coming(at: now) ?? []
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(text: "Up next")
                if let e = coming.first {
                    NextClass(event: e, now: now).padding(.top, 6)
                    Spacer(minLength: 6)
                    if e.offersRecord(at: now) {
                        WidgetRecordPill(className: e.className)
                    } else if coming.count > 1 {
                        ComingRow(event: coming[1], now: now)
                    }
                } else {
                    Text(glance == nil ? UpNextWords.notYet : UpNextWords.nothingOn)
                        .textStyle(.meta).foregroundStyle(inks.muted).padding(.top, 4)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(text: "Due")
                if let glance {
                    let rows = glance.dueRows(at: now, count: typeSize > .large ? 2 : 3)
                    if rows.isEmpty {
                        Text(UpNextWords.nothingDue).textStyle(.meta).foregroundStyle(inks.muted).padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(rows, id: \.self) { DueTap(item: $0, now: now) }
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(WidgetLink.home.url)
    }
}

// MARK: - Large: Home, in a widget

struct UpNextLarge: View {
    var glance: Glance?
    var now: Date
    @Environment(\.widgetFullColor) private var full
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let inks = Inks(full: full)
        let big = typeSize > .large
        let coming = Array((glance?.coming(at: now) ?? []).prefix(big ? 2 : 3))
        let due = glance?.dueRows(at: now, count: big ? 2 : 3) ?? []
        let hot = coming.first.flatMap { $0.offersRecord(at: now) ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            // Home's title and sentence: the date (Record beside it while a class is on or about to start), then
            // what's most pressing.
            HStack(alignment: .center, spacing: 10) {
                Text(Format.longDate(now))
                    .font(.atkinson(22, .heavy, relativeTo: .title2)).tracking(-0.44)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(inks.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let hot { WidgetRecordPill(className: hot.className) }
            }
            Text(glance?.lede(at: now) ?? UpNextWords.notYet)
                .textStyle(.meta).fontWeight(.regular)
                .foregroundStyle(inks.muted)
                .lineLimit(2)
                .padding(.top, hot == nil ? 3 : 1)

            WidgetHeading(text: "Up next").padding(.top, 12)
            if coming.isEmpty {
                Text(glance == nil ? UpNextWords.notYet : UpNextWords.nothingOn).textStyle(.meta).foregroundStyle(inks.muted).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(coming, id: \.self) { e in
                    HStack(alignment: .center, spacing: 12) {
                        EventWhen(event: e, now: now).frame(width: 84, alignment: .leading)
                        EventName(event: e, beside: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 4)

            if glance != nil {
                WidgetHeading(text: "Due").padding(.top, 12)
                if due.isEmpty {
                    Text(UpNextWords.nothingDue).textStyle(.meta).foregroundStyle(inks.muted).padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(due, id: \.self) { DueTap(item: $0, now: now) }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home.url)
    }
}

// MARK: - The Lock Screen

/// Under the clock: the next class and when (and where), and what's due next; with no class, the next deadline.
struct UpNextRectangular: View {
    var glance: Glance?
    var now: Date

    var body: some View {
        let next = glance?.coming(at: now).first
        let due = glance?.dueRows(at: now, count: 1).first
        let line = Font.atkinson(13, .medium, relativeTo: .footnote)
        VStack(alignment: .leading, spacing: 0) {
            if let e = next {
                Text(e.title).font(.atkinson(15, .bold, relativeTo: .headline)).lineLimit(1).widgetAccentable()
                Text([e.when(at: now), e.location ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")).font(line).lineLimit(1)
                if let d = due {
                    Text(d.sentence(at: now)).font(line).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if let d = due {
                Text(d.name).font(.atkinson(15, .bold, relativeTo: .headline)).lineLimit(1).widgetAccentable()
                Text(d.overdue ? "Missing" : "Due \(d.when(at: now))").font(line).lineLimit(1)
                Text(UpNextWords.nothingOn).font(line).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Up next").font(.atkinson(15, .bold, relativeTo: .headline)).widgetAccentable()
                Text(glance == nil ? UpNextWords.notYet : UpNextWords.nothingOn).font(line).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLink.home.url)
    }
}

/// Over the clock, one line: "Calculus II at 9:00 AM", or what's due next.
struct UpNextInline: View {
    var glance: Glance?
    var now: Date
    var body: some View {
        if let e = glance?.coming(at: now).first {
            Text(e.inline(at: now))
        } else if let d = glance?.dueRows(at: now, count: 1).first {
            Text(d.sentence(at: now))
        } else {
            Text(glance == nil ? "Syft Notes" : "Nothing on today")
        }
    }
}

/// A round one: how many things are still to hand in. A tap opens Due.
struct UpNextCircular: View {
    var glance: Glance?
    var now: Date
    /// In the app's gallery there's no Lock Screen to draw the round backing: it draws its own.
    var gallery = false

    var body: some View {
        let n = glance?.toHandIn(at: now) ?? 0
        ZStack {
            if gallery {
                Circle().fill(Color.primary.opacity(0.14))
            } else {
                AccessoryWidgetBackground()
            }
            VStack(spacing: 1) {
                Image(icon: "event_upcoming").resizable().frame(width: 15, height: 15).widgetAccentable()
                Text("\(n)").font(.atkinson(22, .heavy, relativeTo: .title2)).minimumScaleFactor(0.6).lineLimit(1)
            }
            .padding(6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) to hand in")
        .widgetURL(WidgetLink.due.url)
    }
}

extension Glance.Event {
    /// One short line over the Lock Screen's clock: "Calculus II now", "Calculus II in 11 minutes", "Calculus II at
    /// 2:00 PM", "Calculus II tomorrow 9:00 AM", "Calculus II Mon 9:00 AM".
    func inline(at now: Date) -> String {
        if isOn(at: now) { return "\(title) now" }
        let until = start.timeIntervalSince(now)
        if until <= 3600 { return "\(title) \(Format.inMinutes(until))" }
        switch Format.daysBetween(now, start) {
        case 0: return "\(title) at \(Format.time(start))"
        case 1: return "\(title) tomorrow \(Format.time(start))"
        default: return "\(title) \(Format.words(start, "EEE")) \(Format.time(start))"
        }
    }
}
