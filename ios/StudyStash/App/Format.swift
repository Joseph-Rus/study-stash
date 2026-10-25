import Foundation

/// Dates, times and lengths in the app's words, exactly as the desktop writes them (OverviewModel.Day, Date, Time,
/// GroupOf and Rail, Shell.Library's NoteWhen, TimedText.Length): "Today", "Yesterday", then "Wed 7 Oct" within the
/// year and "7 Oct 2025" after; "9:30 AM"; "13 min", "1 h 12 min". Always in these words, whatever the phone's region
/// (the desktop's are fixed too), and never "10/5/2026".
enum Format {
    static var calendar: Calendar { .current }

    /// A date the library sent: "2026-09-23" is that day here; "2026-10-02T23:59:00" (no offset) is that time here;
    /// anything with an offset or Z is that moment.
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for pattern in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = pattern
            if let d = local.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // .NET's "o" has seven fractional digits, more than ISO8601DateFormatter reads: trim them to three.
        if let r = s.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            return parse(s.replacingCharacters(in: r, with: String(s[r].prefix(4))))
        }
        return nil
    }

    /// Whether the library sent a day alone ("2026-09-23"), with no time in it.
    static func isDayOnly(_ s: String?) -> Bool { s?.count == 10 }

    /// Whole days from `now`'s day to `d`'s day (0 today, 1 tomorrow, -1 yesterday).
    static func daysBetween(_ now: Date, _ d: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
    }

    /// `d` in a fixed pattern, in English, as the desktop's InvariantCulture writes it.
    static func words(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: d)
    }

    private static func sameYear(_ d: Date, _ now: Date) -> Bool { calendar.isDate(d, equalTo: now, toGranularity: .year) }

    /// A note's or a deadline's day: "Today", "Yesterday", "Tomorrow", then "Wed 7 Oct" within the year, then
    /// "7 Oct 2025".
    static func day(_ d: Date, now: Date = .now) -> String {
        switch daysBetween(now, d) {
        case 0: "Today"
        case -1: "Yesterday"
        case 1: "Tomorrow"
        default: date(d, now: now)
        }
    }

    /// A day as its date, whatever today is: "Mon 12 Oct", and "12 Oct 2025" once it's another year (a class page's
    /// list, under "This week").
    static func date(_ d: Date, now: Date = .now) -> String {
        words(d, sameYear(d, now) ? "EEE d MMM" : "d MMM yyyy")
    }

    /// The same as `date`, kept for the screens that ask for it by this name.
    static func shortDate(_ d: Date, now: Date = .now) -> String { date(d, now: now) }

    /// A time of day: "9:30 AM", "11:59 PM".
    static func time(_ d: Date) -> String { words(d, "h:mm a") }

    /// When a chat was last added to, as the desktop's Chats list says it: "Today 4:30 PM", "Yesterday 9:05 AM",
    /// "Mon 4:30 PM" within the week, else "Mon 12 Oct".
    static func chatWhen(_ d: Date, now: Date = .now) -> String {
        switch -daysBetween(now, d) {
        case 0: "Today " + time(d)
        case 1: "Yesterday " + time(d)
        case 2..<7: words(d, "EEE h:mm a")
        default: words(d, "EEE d MMM")
        }
    }

    /// Home's title: "Monday, October 12".
    static func longDate(_ d: Date = .now) -> String { words(d, "EEEE, MMMM d") }

    /// How long: "48 min", "1 h 12 min", "2 h 00 min", "under a minute"; "" with no length.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        // Rounded half to even, as the desktop's Math.Round: 30 seconds is under a minute.
        let m = Int((seconds / 60).rounded(.toNearestOrEven))
        if m < 1 { return "under a minute" }
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
    }

    /// When a note was, and how long, on its page: "Monday 12 October at 9:30 AM, 52 min" (with its year once that
    /// isn't this one; without the time when the library sent only the day).
    static func noteWhen(_ date: String?, _ seconds: Double?, now: Date = .now) -> String {
        var when = ""
        if let d = parse(date) {
            let day = words(d, sameYear(d, now) ? "EEEE d MMMM" : "EEEE d MMMM yyyy")
            when = isDayOnly(date) ? day : "\(day) at \(time(d))"
        }
        return [when, duration(seconds)].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The line under a lecture's title where there's room for only one: "Thu 15 Oct, 52 min".
    static func lectureMeta(_ date: String?, _ seconds: Double?, now: Date = .now) -> String {
        [parse(date).map { day($0, now: now) } ?? "", duration(seconds)].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The first day (the Sunday) of `d`'s week: weeks run Sunday to Saturday, as Canvas's calendar has them and the
    /// desktop's Due and "This week" do.
    static func weekStart(_ d: Date) -> Date {
        var cal = calendar
        cal.firstWeekday = 1
        return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
    }

    /// The heading a lecture sits under on its class's page: "This week", "Last week", then the month ("September",
    /// "May 2025").
    static func lectureGroup(_ date: String?, now: Date = .now) -> String {
        guard let d = parse(date) else { return "Undated" }
        let thisWeek = weekStart(now)
        if d >= thisWeek { return "This week" }
        if d >= calendar.date(byAdding: .day, value: -7, to: thisWeek)! { return "Last week" }
        return words(d, sameYear(d, now) ? "MMMM" : "MMMM yyyy")
    }

    /// Items under their headings, in the order they came (newest first).
    static func grouped<T>(_ items: [T], by label: (T) -> String) -> [(label: String, items: [T])] {
        var groups: [(label: String, items: [T])] = []
        for item in items {
            let l = label(item)
            if let last = groups.indices.last, groups[last].label == l { groups[last].items.append(item) } else { groups.append((l, [item])) }
        }
        return groups
    }

    /// A day as a row says it: the same as `day`.
    static func dayLabel(_ d: Date, now: Date = .now) -> String { day(d, now: now) }

    /// When something is due: "Today, 11:59 PM", "Tomorrow, 9:00 AM", "Fri 3 Oct, 5:00 PM"; a due of midnight (or a
    /// day alone) is the day.
    static func dueWhen(_ due: String?, now: Date = .now) -> String {
        guard let d = parse(due) else { return "No due date" }
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour == 0 && c.minute == 0) || isDayOnly(due) ? day(d, now: now) : "\(day(d, now: now)), \(time(d))"
    }

    /// Something due, in a class page's rail: "Today, 11:59 PM", "Sun 18 Oct, in 6 days" (within two weeks), "Fri
    /// 11 Dec", or "Was due Mon 5 Oct" once it's missing.
    static func railDue(_ due: String?, late: Bool, now: Date = .now) -> String {
        guard let d = parse(due) else { return "No due date" }
        if late { return "Was due \(date(d, now: now))" }
        let away = daysBetween(now, d)
        if away <= 1 { return "\(day(d, now: now)), \(time(d))" }
        return away <= 14 ? "\(day(d, now: now)), in \(away) days" : day(d, now: now)
    }

    /// "in 11 minutes", "in a minute": how soon an event starts.
    static func inMinutes(_ until: TimeInterval) -> String {
        let m = max(1, Int((until / 60).rounded(.up)))
        return m == 1 ? "in a minute" : "in \(m) minutes"
    }

    /// How long until (or since): "in 3 hours", "in 2 days", "2 days ago".
    static func relative(_ due: String?, now: Date = .now) -> String {
        guard let d = parse(due) else { return "" }
        let s = d.timeIntervalSince(now)
        let a = abs(s)
        func words(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        let amount = a < 3600 ? words(max(1, Int((a / 60).rounded())), "minute")
            : a < 86_400 ? words(Int((a / 3600).rounded()), "hour")
            : words(Int((a / 86_400).rounded()), "day")
        return s >= 0 ? "in \(amount)" : "\(amount) ago"
    }

    /// An event's time: "All day", "9:00 AM – 10:15 AM".
    static func timeRange(_ start: String, _ end: String, allDay: Bool) -> String {
        if allDay { return "All day" }
        guard let s = parse(start) else { return "" }
        return parse(end).map { "\(time(s)) – \(time($0))" } ?? time(s)
    }

    /// "2.4 MB", "830 KB", "12 bytes".
    static func fileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) byte\(bytes == 1 ? "" : "s")" }
        let units = ["KB", "MB", "GB"]
        var v = Double(bytes) / 1024
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return (v >= 10 || i == 0 ? "\(Int(v.rounded()))" : String(format: "%.1f", v)) + " " + units[i]
    }

    /// A moment in a recording: "4:05", "1:02:03".
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
    }

    /// "just now", "5 min ago", "3 h ago", "Yesterday", or the date.
    static func ago(_ when: String?, now: Date = .now) -> String {
        guard let d = parse(when) else { return "" }
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if daysBetween(now, d) == 0 { return "\(Int(s / 3600)) h ago" }
        return day(d, now: now)
    }

    /// What a note's row says in place of its summary while it has none: "Writing notes…".
    static func statusWord(_ status: String) -> String {
        switch status {
        case "queued", "working": "Writing notes…"
        case "failed": "Notes couldn't be written"
        default: status
        }
    }
}

/// What a recording is called, by where it's filed (the desktop's `Nouns`): a lecture in a class, a meeting in a
/// club's or work's folder, a recording in none. Lists that mix them (Home, search, Ask on Home) say "notes".
enum Nouns {
    static let lecture = "lecture", meeting = "meeting", recording = "recording"

    /// The noun for a note in `folder` (nil, "" or "Unsorted" for none), whose sidebar group is `group` ("" or nil
    /// for Classes; "Clubs", "Work" or the student's own). In a library that isn't for school, a folder's notes are
    /// meetings for work and recordings otherwise.
    static func of(folder: String?, group: String?, school: Bool = true, work: Bool = false) -> String {
        guard let folder, !folder.isEmpty, folder != "Unsorted" else { return recording }
        if (group ?? "").isEmpty { return school ? lecture : work ? meeting : recording }
        return meeting
    }

    /// "Lectures", "Meetings": a folder's section of them.
    static func section(_ noun: String) -> String { capital(noun) + "s" }

    static func capital(_ noun: String) -> String { noun.prefix(1).uppercased() + noun.dropFirst() }

    /// The title a note goes by until it has its own (the desktop's WorkingTitle): "Calculus II, Mon 12 Oct", or with
    /// no folder "Recording, Mon 12 Oct at 1:45 PM".
    static func untitled(folder: String?, date: String?, now: Date = .now) -> String {
        guard let d = Format.parse(date) else { return folder.map { $0 } ?? capital(recording) }
        let day = Format.words(d, "EEE d MMM")
        if let folder, !folder.isEmpty, folder != "Unsorted" { return "\(folder), \(day)" }
        return Format.isDayOnly(date) ? "Recording, \(day)" : "Recording, \(day) at \(Format.time(d))"
    }
}

/// A sentence with maths in it, for a line of plain text (a lecture's summary in a list), as the desktop's PlainMath
/// does it: the dollar signs go, and simple LaTeX becomes the characters it stands for (`$c^T x$` is cᵀx, `\le` is ≤).
/// What has no plain form is left readable, never as raw LaTeX. The notes themselves typeset maths properly.
enum PlainMath {
    static let symbols: [String: String] = [
        "cdot": "·", "times": "×", "div": "÷", "pm": "±", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥",
        "ne": "≠", "neq": "≠", "approx": "≈", "equiv": "≡", "to": "→", "rightarrow": "→", "leftarrow": "←",
        "Rightarrow": "⇒", "implies": "⇒", "iff": "⇔", "infty": "∞", "in": "∈", "notin": "∉", "subset": "⊂",
        "subseteq": "⊆", "cup": "∪", "cap": "∩", "forall": "∀", "exists": "∃", "sum": "∑", "prod": "∏",
        "int": "∫", "partial": "∂", "nabla": "∇", "ldots": "…", "dots": "…", "cdots": "⋯", "neg": "¬",
        "land": "∧", "lor": "∨", "emptyset": "∅", "circ": "∘", "propto": "∝", "sim": "∼",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Omega": "Ω",
        "log": "log", "ln": "ln", "sin": "sin", "cos": "cos", "tan": "tan", "max": "max", "min": "min", "lim": "lim",
    ]
    static let superFrom = Array("0123456789+-=nTiaxk"), superTo = Array("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼ⁿᵀⁱᵃˣᵏ")
    static let subFrom = Array("0123456789+-=ijnkxaeotm"), subTo = Array("₀₁₂₃₄₅₆₇₈₉₊₋₌ᵢⱼₙₖₓₐₑₒₜₘ")

    /// The sentence with its maths in plain characters.
    static func inline(_ text: String) -> String {
        guard text.contains("$") || text.contains("\\(") else { return text }
        return text.replacing(/\$\$(.+?)\$\$|\$(.+?)\$|\\\((.+?)\\\)/.dotMatchesNewlines()) { m in
            plain(String(m.output.1 ?? m.output.2 ?? m.output.3 ?? ""))
        }
    }

    static func plain(_ tex: String) -> String {
        var t = tex
        for _ in 0..<3 {
            t = t.replacing(/\\(?:text|mathrm|mathbf|mathit|operatorname|mathcal|boldsymbol)\s*\{([^{}]*)\}/) { String($0.output.1) }
            t = t.replacing(/\\(?:d|t)?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/) { "\(paren(String($0.output.1)))/\(paren(String($0.output.2)))" }
            t = t.replacing(/\\sqrt\s*\{([^{}]*)\}/) { "√" + paren(String($0.output.1)) }
        }
        t = t.replacing(/\\mathbb\s*\{([A-Z])\}/) { m in
            switch m.output.1 { case "R": "ℝ"; case "N": "ℕ"; case "Z": "ℤ"; case "Q": "ℚ"; case "C": "ℂ"; default: String(m.output.1) }
        }
        t = t.replacing(/([\^_])(?:\{([^{}]*)\}|(\\[A-Za-z]+|[A-Za-z0-9+\-=]))/) { m in
            let up = m.output.1 == "^"
            let body = String(m.output.2 ?? m.output.3 ?? "")
            if body.hasPrefix("\\") { return (up ? "^" : "_") + body }
            let (from, to) = up ? (superFrom, superTo) : (subFrom, subTo)
            var made = ""
            for c in body {
                // No such small letter: say it in line instead ("x^y"), never half and half.
                guard let at = from.firstIndex(of: c) else { return (up ? "^" : "_") + (body.count > 1 ? "(\(body))" : body) }
                made.append(to[at])
            }
            return made
        }
        t = t.replacing(/\\([A-Za-z]+)/) { symbols[String($0.output.1)] ?? String($0.output.1) }
        for (a, b) in [("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\ ", " "), ("{", ""), ("}", ""), ("\\", "")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        // After a raised letter the space typed between two things goes ("c^T x" is cᵀx).
        t = t.replacing(/([⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼ⁿᵀⁱᵃˣᵏ]) (?=[A-Za-z0-9(])/) { String($0.output.1) }
        return t.replacing(/\s{2,}/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// More than one thing over or under a fraction's bar needs brackets round it.
    static func paren(_ part: String) -> String {
        let p = part.trimmingCharacters(in: .whitespaces)
        return p.contains(" ") || p.contains("+") || p.contains("-") ? "(\(p))" : p
    }
}
