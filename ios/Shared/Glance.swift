import Foundation

/// What the widgets show, written by the app whenever it has a fresh look at the library and read by the widgets:
/// the next few classes on the calendar and the next things due, each with its class's highlighter by name.
struct Glance: Codable, Sendable {
    struct Event: Codable, Hashable, Sendable {
        var title: String
        var className: String?
        var start: Date
        var end: Date
        var location: String?
        /// The class's highlighter by name ("yellow"), as `Highlighter(rawValue:)` reads it; nil for no class.
        var color: String?
    }
    struct Due: Codable, Hashable, Sendable {
        var name: String
        var className: String
        var due: Date
        /// The library says it's late (missing).
        var overdue: Bool
        /// The class's highlighter by name ("yellow"); nil for no class.
        var color: String?
        /// Canvas's id for it: a tap opens it. Nil from an app before the widgets opened things.
        var id: Int?
        /// "assignment", "quiz", "discussion" or "todo".
        var kind: String?
    }

    var library: String
    var events: [Event]
    var due: [Due]
    var toHandIn: Int
    var updated: Date
    /// Every class's highlighter by name ("Calculus II": "yellow"), for the recording's Live Activity.
    var hues: [String: String]? = nil

    static let group = "group.app.studystash.ios"
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appending(path: "glance.json")
    }

    static func load() -> Glance? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(Glance.self, from: data)
    }

    func save() {
        guard let file = Self.file else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(self).write(to: file, options: .atomic)
    }
}

// MARK: - What's coming, at a moment

extension Glance {
    /// A class's highlighter by name ("yellow"): from every class's, when the app wrote them, else from an event or a
    /// deadline of that class.
    func hue(of cls: String?) -> String? {
        guard let cls else { return nil }
        return hues?[cls] ?? events.first { $0.className == cls }?.color ?? due.first { $0.className == cls }?.color
    }

    /// The events not over by `now`, soonest first.
    func coming(at now: Date) -> [Event] {
        events.filter { $0.end > now }.sorted { $0.start < $1.start }
    }

    /// What's still to hand in at `now`: what's due next, soonest first, then what the library said is missing. A
    /// deadline that has passed since the library last said is left out (it was most likely handed in; the app's next
    /// look says).
    func open(at now: Date) -> (next: [Due], late: [Due]) {
        let late = due.filter(\.overdue).sorted { $0.due < $1.due }
        let next = due.filter { !$0.overdue && $0.due > now }.sorted { $0.due < $1.due }
        return (next, late)
    }

    /// The rows a list of `count` shows: what's due next, the last place kept for something missing when there is one.
    func dueRows(at now: Date, count: Int) -> [Due] {
        let (next, late) = open(at: now)
        guard count > 0 else { return [] }
        if late.isEmpty { return Array(next.prefix(count)) }
        let shown = Array(next.prefix(count - 1))
        return shown + late.prefix(count - shown.count)
    }

    /// How many things are still to hand in, missing ones included, as the library last counted (less what has since
    /// passed unmarked).
    func toHandIn(at now: Date) -> Int {
        let passed = due.filter { !$0.overdue && $0.due <= now }.count
        return max(0, toHandIn - passed)
    }
}

extension Glance.Event {
    /// On now.
    func isOn(at now: Date) -> Bool { start <= now && now < end }
    /// Starting within a quarter of an hour: said in ink, as the desktop's Up next does.
    func isSoon(at now: Date) -> Bool { !isOn(at: now) && start > now && start.timeIntervalSince(now) <= 15 * 60 }
    /// It's named for its class and nothing more ("Calculus II" in Calculus II): its name is shown once, marked.
    var isClass: Bool {
        guard let className else { return false }
        return Self.plain(title) == Self.plain(className)
    }
    static func plain(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Its day under its time, as the app's Up next says it: "Now", "In 11 minutes", "Today", "Tomorrow", "Mon 19 Oct".
    func day(at now: Date) -> String {
        if isOn(at: now) { return "Now" }
        if isSoon(at: now) { return Nouns.capital(Format.inMinutes(start.timeIntervalSince(now))) }
        return Format.day(start, now: now)
    }

    /// When, in one line (the desktop's Coming up): "Now, until 9:50 AM", "In 11 minutes", "9:00 AM", "Tomorrow
    /// 9:00 AM", "Mon 9:00 AM".
    func when(at now: Date) -> String {
        if isOn(at: now) { return "Now, until \(Format.time(end))" }
        if isSoon(at: now) { return Nouns.capital(Format.inMinutes(start.timeIntervalSince(now))) }
        switch Format.daysBetween(now, start) {
        case 0: return Format.time(start)
        case 1: return "Tomorrow \(Format.time(start))"
        default: return "\(Format.words(start, "EEE")) \(Format.time(start))"
        }
    }
}

extension Glance.Due {
    /// When, under its name (the desktop's rail): "Tomorrow, 11:59 PM", "Sun 18 Oct, in 6 days", "Was due Mon 5 Oct".
    func when(at now: Date) -> String {
        if overdue { return "Was due \(Format.date(due, now: now))" }
        let away = Format.daysBetween(now, due)
        if away <= 1 { return "\(Format.day(due, now: now)), \(Format.time(due))" }
        return away <= 14 ? "\(Format.day(due, now: now)), in \(away) days" : Format.day(due, now: now)
    }

    /// Due within the day, or missing: said in ink (or the late red).
    func isSoon(at now: Date) -> Bool { !overdue && Format.daysBetween(now, due) <= 0 }

    /// The Lock Screen's line, what matters first (a long name is cut at its end): "Due tomorrow · Problem Set 6",
    /// "Missing · Reading quiz 4".
    func sentence(at now: Date) -> String {
        if overdue { return "Missing · \(name)" }
        return "Due \(Glance.dueDay(due, now: now)) · \(name)"
    }
}

// MARK: - Home's sentence

extension Glance {
    /// The desktop's Home sentence (OverviewModel.HomeLede), from what the widgets know: what's on or about to start
    /// ("Calculus II starts in 11 minutes."), then what's due ("Problem Set 6 is due tomorrow."); with neither, that
    /// nothing's due this week.
    func lede(at now: Date) -> String {
        let soon = eventSentence(at: now)
        let due = dueSentence(at: now, missing: soon.isEmpty)
        if !soon.isEmpty || !due.isEmpty { return [soon, due].filter { !$0.isEmpty }.joined(separator: " ") }
        if !self.due.isEmpty { return "Nothing due this week." }
        return coming(at: now).isEmpty ? "Nothing on your calendar." : "Nothing else on today."
    }

    /// What's on, or next today: "Calculus II starts in 11 minutes." (within the hour), "Calculus II is on now.",
    /// "Calculus II is at 2:00 PM."; "" with nothing left today.
    func eventSentence(at now: Date) -> String {
        guard let next = coming(at: now).first(where: { Format.daysBetween(now, $0.start) <= 0 }) else { return "" }
        if next.start <= now { return "\(next.title) is on now." }
        let until = next.start.timeIntervalSince(now)
        return until <= 3600 ? "\(next.title) starts \(Format.inMinutes(until))." : "\(next.title) is at \(Format.time(next.start))."
    }

    /// What's to hand in, the most pressing first: "Problem Set 6 is due tomorrow", "Two assignments due Wednesday",
    /// then what's missing ("…, and Essay 2 is still missing."); "" with nothing due this week and nothing missing.
    func dueSentence(at now: Date, missing: Bool = true) -> String {
        let (next, late) = open(at: now)
        let weekEnd = Format.calendar.date(byAdding: .day, value: 7, to: Format.weekStart(now)) ?? now
        let week = next.filter { $0.due < weekEnd }
        var first = ""
        if let soonest = week.first {
            let same = week.filter { Format.daysBetween(soonest.due, $0.due) == 0 }
            if same.count == 1 {
                let c = Format.calendar.dateComponents([.hour, .minute], from: soonest.due)
                let day = Self.dueDay(soonest.due, now: now)
                // The end of the day is when most things are due, so it goes unsaid.
                first = c.hour == 23 && c.minute == 59 ? "\(soonest.name) is due \(day)" : "\(soonest.name) is due \(day) at \(Format.time(soonest.due))"
            } else {
                first = "\(Self.count(same.count)) \(Self.kind(same, plural: true)) due \(Self.weekday(soonest.due, now: now))"
            }
        }
        let then: String = if !missing && !first.isEmpty { "" } else {
            switch late.count {
            case 0: ""
            case 1: first.isEmpty ? "\(late[0].name) is still missing" : "and \(late[0].name) is still missing"
            default: first.isEmpty ? "\(Self.count(late.count)) \(Self.kind(late, plural: true)) are still missing"
                : "and \(Self.count(late.count).lowercased()) are still missing"
            }
        }
        if first.isEmpty && then.isEmpty { return "" }
        return !first.isEmpty && !then.isEmpty ? "\(first), \(then)." : "\(first)\(then)."
    }

    /// "tonight" (today after 5 PM), "today", "tomorrow", "Wednesday", then "on Mon 26 Oct".
    static func dueDay(_ d: Date, now: Date) -> String {
        switch Format.daysBetween(now, d) {
        case 0: Format.calendar.component(.hour, from: d) >= 17 ? "tonight" : "today"
        default: weekday(d, now: now)
        }
    }

    /// "today", "tomorrow", "Wednesday" within the week, then "on Mon 26 Oct".
    static func weekday(_ d: Date, now: Date) -> String {
        switch Format.daysBetween(now, d) {
        case 0: "today"
        case 1: "tomorrow"
        case 2...6: Format.words(d, "EEEE")
        default: "on \(Format.date(d, now: now))"
        }
    }

    static let counts = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
    /// "Two", and 11 as "11": a count as a sentence starts with it.
    static func count(_ n: Int) -> String { counts.indices.contains(n) ? counts[n] : "\(n)" }

    /// "assignments", or "quizzes" when every one is a quiz.
    static func kind(_ items: [Due], plural: Bool) -> String {
        let quizzes = !items.isEmpty && items.allSatisfy { $0.kind == "quiz" }
        return quizzes ? (plural ? "quizzes" : "quiz") : (plural ? "assignments" : "assignment")
    }
}

// MARK: - When the words change

extension Glance {
    /// The moments a widget's words change, from `now`: each minute of the hour before an event starts ("starts in 11
    /// minutes"), each start and end, each deadline, and each midnight ("Tomorrow" becomes "Today"). At most `limit`.
    func changes(after now: Date, limit: Int = 180) -> [Date] {
        var out: Set<Date> = []
        let horizon = now.addingTimeInterval(36 * 3600)
        for e in coming(at: now) where e.start < horizon {
            let from = max(now, e.start.addingTimeInterval(-3600))
            var t = Format.calendar.date(bySetting: .second, value: 0, of: from) ?? from
            if t <= now { t = t.addingTimeInterval(60) }
            while t < e.start {
                out.insert(t)
                t = t.addingTimeInterval(60)
            }
            out.insert(e.start)
            out.insert(e.end)
        }
        for d in due where d.due > now && d.due < horizon { out.insert(d.due) }
        var midnight = Format.calendar.startOfDay(for: now)
        for _ in 0..<2 {
            midnight = Format.calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
            out.insert(midnight)
        }
        return out.filter { $0 > now && $0 < horizon }.sorted().prefix(limit).map { $0 }
    }
}

// MARK: - Where a tap goes

/// A widget's or the Live Activity's tap, as the app's link (`studystash://…`, FLOWS.md "Shared changes" 6): the
/// widgets make them, the app's `onOpenURL` follows them.
enum WidgetLink: Hashable, Sendable {
    /// Home: `studystash://home`.
    case home
    /// Due: `studystash://due`.
    case due
    /// Record, into a class (or the one on now), as tapping it in Up next does: `studystash://record?class=<name>`.
    case record(className: String?)
    /// What's recording, its page: `studystash://recording`.
    case recording
    /// An assignment's page: `studystash://assignment/<class>/<id>`.
    case assignment(className: String, id: Int)

    static let scheme = "studystash"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .home: c.host = "home"
        case .due: c.host = "due"
        case .recording: c.host = "recording"
        case .record(let cls):
            c.host = "record"
            if let cls, !cls.isEmpty { c.queryItems = [URLQueryItem(name: "class", value: cls)] }
        case let .assignment(cls, id):
            c.host = "assignment"
            // A "/" in a class's name is escaped, so the class stays one part of the path.
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove("/")
            c.percentEncodedPath = "/\(cls.addingPercentEncoding(withAllowedCharacters: allowed) ?? cls)/\(id)"
        }
        return c.url ?? URL(string: "studystash://home")!
    }
}

// MARK: - The sample

extension Glance {
    /// The demo library's week (its classes in their highlighters: Calculus II yellow, Intro to Psychology green,
    /// Organic Chemistry orange), as at `now`: Calculus II in 11 minutes, Psychology this afternoon, the chemistry lab
    /// tomorrow; three things to hand in. The widget gallery shows it, and a widget before the app has said anything.
    static func sample(at now: Date = .now) -> Glance {
        let cal = Format.calendar
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let calc = now.addingTimeInterval(11 * 60)
        let calcStart = cal.date(bySetting: .second, value: 0, of: calc) ?? calc
        return Glance(
            library: "Demo library",
            events: [
                Event(title: "Calculus II", className: "Calculus II", start: calcStart, end: calcStart.addingTimeInterval(50 * 60),
                      location: "Science Hall 204", color: "yellow"),
                Event(title: "Memory and the brain", className: "Intro to Psychology", start: calcStart.addingTimeInterval(3 * 3600),
                      end: calcStart.addingTimeInterval(3 * 3600 + 75 * 60), location: "Lecture Hall B", color: "green"),
                Event(title: "Organic Chemistry Lab", className: "Organic Chemistry", start: at(1, 13), end: at(1, 15, 50),
                      location: "Chem 110", color: "orange"),
            ],
            due: [
                Due(name: "Problem Set 6: Integration by Parts", className: "Calculus II", due: at(1, 23, 59), overdue: false, color: "yellow", id: 1, kind: "assignment"),
                Due(name: "Lab Report: Acid–Base Titration", className: "Organic Chemistry", due: at(4, 23, 59), overdue: false, color: "orange", id: 2, kind: "assignment"),
                Due(name: "Reading quiz 4", className: "Intro to Psychology", due: at(-2, 23, 59), overdue: true, color: "green", id: 3, kind: "quiz"),
            ],
            toHandIn: 3, updated: now,
            hues: ["Calculus II": "yellow", "Intro to Psychology": "green", "Organic Chemistry": "orange"])
    }

    /// The same, for what has no clock of its own (the system's placeholder).
    static var sample: Glance { sample() }
}
