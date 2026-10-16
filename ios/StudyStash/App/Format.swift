import Foundation

/// Dates, times and sizes in the app's words: "Tue 23 Sep · 1 h 12 min", "This week", "Tomorrow, 5:00 PM".
/// The same rules as web/src/format.ts.
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

    /// Whole days from `now`'s day to `d`'s day (0 today, 1 tomorrow, -1 yesterday).
    static func daysBetween(_ now: Date, _ d: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
    }

    private static func string(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    /// "Tue 23 Sep", with the year when it isn't this one.
    static func shortDate(_ d: Date, now: Date = .now) -> String {
        string(d, calendar.isDate(d, equalTo: now, toGranularity: .year) ? "EEE d MMM" : "EEE d MMM yyyy")
    }

    /// "5:00 PM" or "17:00", as the phone tells time.
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// "1 h 12 min", "48 min", "under a minute".
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        if seconds < 60 { return "under a minute" }
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m) min" }
        let rest = m % 60
        return rest == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", rest)) min"
    }

    /// A lecture's line under its title: "Tue 23 Sep · 1 h 12 min".
    static func lectureMeta(_ date: String?, _ seconds: Double?, now: Date = .now) -> String {
        [parse(date).map { shortDate($0, now: now) } ?? "", duration(seconds)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The heading a lecture sits under in a class: "This week", "Last week", then the month ("August", "May 2025").
    static func lectureGroup(_ date: String?, now: Date = .now) -> String {
        guard let d = parse(date) else { return "Undated" }
        var cal = calendar
        cal.firstWeekday = 2
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        if d >= thisWeek { return "This week" }
        if d >= thisWeek.addingTimeInterval(-7 * 86_400) { return "Last week" }
        return string(d, cal.isDate(d, equalTo: now, toGranularity: .year) ? "MMMM" : "MMMM yyyy")
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

    /// A day as a heading: "Today", "Tomorrow", "Yesterday", "Wednesday 1 Oct".
    static func dayLabel(_ d: Date, now: Date = .now) -> String {
        switch daysBetween(now, d) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: string(d, calendar.isDate(d, equalTo: now, toGranularity: .year) ? "EEEE d MMM" : "EEEE d MMM yyyy")
        }
    }

    /// When something is due: "Today, 11:59 PM", "Tomorrow, 9:00 AM", "Fri 3 Oct, 5:00 PM"; a due of midnight is the day.
    static func dueWhen(_ due: String?, now: Date = .now) -> String {
        guard let d = parse(due) else { return "No due date" }
        let n = daysBetween(now, d)
        let day = n == 0 ? "Today" : n == 1 ? "Tomorrow" : n == -1 ? "Yesterday" : shortDate(d, now: now)
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour == 0 && c.minute == 0) || due?.count == 10 ? day : "\(day), \(time(d))"
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

    /// "just now", "5 min ago", "3 h ago", "yesterday", or the date.
    static func ago(_ when: String?, now: Date = .now) -> String {
        guard let d = parse(when) else { return "" }
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if daysBetween(now, d) == 0 { return "\(Int(s / 3600)) h ago" }
        if daysBetween(now, d) == -1 { return "yesterday" }
        return shortDate(d, now: now)
    }

    /// "Writing notes…" for a lecture that isn't done.
    static func statusWord(_ status: String) -> String {
        switch status {
        case "queued": "Waiting to be written…"
        case "working": "Writing notes…"
        case "failed": "Notes couldn't be written"
        default: status
        }
    }
}
