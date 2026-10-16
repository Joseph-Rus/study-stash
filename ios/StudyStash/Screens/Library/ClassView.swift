import QuickLook
import SwiftUI

/// A folder's page (a class, or a club's or work's folder), as the desktop's (Overview.axaml, a folder): its name
/// underlined in its highlighter, a sentence saying its code, when it meets and when it next does, Attach (into it) and
/// Ask about it, what's due next, its lectures (or meetings) under This week, Last week and the months before, and its
/// notebooks and files. Record is the bar above the tabs, which records into this class while its page is up. On a
/// phone it's one column; on an iPad the desktop's rail (Due, Next class, notebooks and files) stands beside the
/// lectures.
struct ClassView: View {
    @Environment(AppModel.self) private var app
    let name: String

    @State private var lectures: Resource<[LectureSummary]>?
    @State private var files: Resource<[Attachment]>?
    @State private var library: Resource<LibraryOverview>?
    @State private var due: Resource<DueList>?
    @State private var upcoming: Resource<Upcoming>?
    @State private var recorder = Recorder.shared
    @State private var notebooks = NotebookStore.shared
    @State private var asking = false
    @State private var searching = false
    @State private var openNotebook: NotebookID?
    @State private var width: CGFloat = 0
    @State private var message: String?

    /// Wide enough for the rail beside the lectures (an iPad), as the desktop's window when it isn't narrow.
    private var wide: Bool { width >= 760 }
    private var margin: CGFloat { wide ? Space.pageRegular : Space.pageCompact }

    private var info: ClassInfo? {
        library?.value?.classes.first { $0.name == name } ?? app.classes.first { $0.name == name }
    }
    private var noun: String { app.noun(of: name) }
    private var isClass: Bool { noun == "lecture" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if lectures?.stale == true { OfflineNote().padding(.bottom, 16) }
                header
                AskBarButton(placeholder: "Ask about \(name)", scope: isClass ? "This class" : "This folder") { asking = true }
                    .padding(.top, 20)
                if wide {
                    HStack(alignment: .top, spacing: 48) {
                        notes.frame(maxWidth: .infinity, alignment: .leading)
                        rail.frame(width: 272)
                    }
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 40) {
                        if !dueRows.isEmpty { dueSection(heading: .h2) }
                        notes
                        if hasAttached { attached(heading: .h2) }
                    }
                    .padding(.top, 36)
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: 1040 + 2 * margin, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .foregroundStyle(.ink)
        .page()
        .titleOnScroll(name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // FLOWS: scope these results to the class once the core's search takes one.
                    Button("Search in \(name)", icon: "search") { searching = true }
                } label: {
                    Label("More", icon: "more_horiz")
                }
                .accessibilityLabel("More for \(name)")
            }
        }
        // FLOWS: .recordsInto(name) once the core is in, so the Record bar says "Record Calculus II" and records here.
        .toast($message)
        .sheet(isPresented: $asking) { AskSheet(scope: .class(name)) }
        .navigationDestination(isPresented: $searching) { SearchResultsView(query: name) }
        .fullScreenCover(item: $openNotebook) { NotebookEditor(id: $0.id) }
        .refreshable { await load() }
        .task {
            guard let api = app.api else { return }
            if lectures == nil {
                lectures = Resource("class:\(name)") { try await api.lectures(class: name, limit: 500) }
                files = Resource("class:\(name):files") { try await api.attachments(class: name) }
                library = Resource("library") { try await api.library() }
                due = Resource("due") { try await api.due() }
                upcoming = Resource("upcoming") { try await api.upcoming() }
            }
            await load()
        }
        // What was attached from here shows when the Attach sheet closes; a recording, when the recorder does.
        .onChange(of: app.incoming?.id) { _, now in if now == nil { Task { await files?.load() } } }
        .onChange(of: app.showingRecorder) { _, now in if !now { Task { await lectures?.load() } } }
    }

    private func load() async {
        async let a: Void = lectures?.load() ?? ()
        async let b: Void = files?.load() ?? ()
        async let c: Void = library?.load() ?? ()
        async let d: Void = due?.load() ?? ()
        async let e: Void = upcoming?.load() ?? ()
        _ = await (a, b, c, d, e)
        if let v = library?.value { app.learn(v) }
    }

    // MARK: the header

    /// The name underlined in its highlighter, the sentence under it, and Attach: under them on a phone, beside them
    /// on an iPad (at the header's foot, as the desktop has it).
    @ViewBuilder private var header: some View {
        let title = VStack(alignment: .leading, spacing: 0) {
            FolderTitle(name, hue: app.hue(of: name))
                .fixedSize(horizontal: false, vertical: true)
            if !lede.isEmpty {
                Text(lede).textStyle(.lede).foregroundStyle(.inkMuted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        if wide {
            HStack(alignment: .bottom, spacing: 24) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                attach
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                title
                attach
            }
        }
    }

    /// The sentence under the title, in the desktop's words: for a class its code ("MATH 162 on Canvas.") and when it
    /// meets ("Meets Tuesday and Thursday at 9:00 AM."); for a club or work, "Club meetings, Thursdays at 6:00 PM.";
    /// with nothing on the calendar for it, how many there are. On a phone, when it next meets after that (an iPad's
    /// rail says it instead).
    private var lede: String {
        let first = ClassWords.lede(name: name, group: info?.group ?? "", code: info?.code ?? "", noun: noun,
                                    count: info?.lectures ?? lectures?.value?.count ?? 0, events: ownEvents)
        guard !wide, let next = ClassWords.next(ownEvents, name: name) else { return first }
        let said = next.on ? "\(next.words)." : "Next \(isClass ? "class" : "meeting"): \(next.words)."
        return first.isEmpty ? said : "\(first) \(said)"
    }

    /// Attach: the one Attach sheet, for this folder (scan pages, photos, files, write notes, a recording, GoodNotes).
    private var attach: some View {
        Button {
            // FLOWS: app.incoming = .attach(className: name, lecture: nil) once the core is in.
            app.incoming = .files([], className: name, lecture: nil)
        } label: {
            Label("Attach", icon: "attach_file")
        }
        .buttonStyle(.pill)
        .fixedSize()
        .accessibilityHint("Scan pages, photos, files, notes or a recording, into \(name)")
    }

    // MARK: due

    private var dueRows: [ClassWords.DueRow] { ClassWords.due(due?.value, in: name) }

    /// The next three to hand in (anything missing first), each opening its assignment, and the calendar link.
    private func dueSection(heading: AppText) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Due", style: heading)
            ForEach(Array(dueRows.enumerated()), id: \.element.item.id) { i, row in
                if i > 0 { Rule() }
                NavigationLink(value: Route.assignment(class: row.item.class, id: row.item.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.item.name)
                            .font(.atkinson(heading == .h2 ? 16 : 14.5, .bold, relativeTo: .subheadline))
                            .foregroundStyle(.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.when)
                            .font(.atkinson(heading == .h2 ? 13 : 12, row.soon ? .bold : .medium, relativeTo: .caption))
                            .foregroundStyle(row.late ? Color.late : row.soon ? .ink : .inkSubtle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, i == 0 ? 0 : 10)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.row)
                .accessibilityLabel("\(row.item.name), \(row.late ? "missing, " : "due ")\(row.when)")
            }
            Button("See these on the calendar") {
                // FLOWS: app.showDue(class: name) once the core is in (Due, filtered to this class).
            }
            .buttonStyle(.textLink)
            .padding(.top, 6)
        }
    }

    // MARK: the lectures

    private var shownLectures: [LectureSummary]? {
        #if DEBUG
        // `-class-empty`: the page as an empty class has it, for pictures (the demo's classes all have lectures).
        if DebugLaunch.flag("-class-empty") { return lectures?.value.map { _ in [] } }
        #endif
        return lectures?.value
    }

    /// "Lectures" (or "Meetings"): This week, Last week, then the months, as the desktop's note rows without the
    /// folder. Empty, what to do about it, and Record into this class right there.
    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(Nouns.section(noun), style: .h2).padding(.bottom, 6)
            if let list = shownLectures {
                if list.isEmpty {
                    EmptyText("No \(noun)s yet. Record one here, or attach a recording.")
                    recordHere.padding(.top, 16)
                } else {
                    let groups = Format.grouped(list) { Format.lectureGroup($0.date) }
                    ForEach(Array(groups.enumerated()), id: \.element.label) { g, group in
                        GroupLabel(group.label)
                            .padding(.top, g == 0 ? 0 : 26)
                            .padding(.bottom, 2)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { i, l in
                            NavigationLink(value: Route.lecture(l.id)) {
                                NoteRow(lecture: l, showFolder: false, first: i == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let error = lectures?.error {
                EmptyState(title: error.unreachable ? "Can't reach your library" : "Couldn't load this \(app.words.cls)",
                           detail: "\(error.detail) Recording still works.", actionTitle: "Try again") {
                    Task { await lectures?.load() }
                }
            } else {
                ProgressView().tint(.inkSubtle).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    /// The one Record on the page, for an empty class: records into it (or, while something records, opens that).
    private var recordHere: some View {
        let state: RecordState = recorder.phase == .recording ? .recording : recorder.phase == .paused ? .paused : .idle
        return RecordButton(state: state,
                            words: state == .idle ? "Record" : recorder.recording?.className ?? "Recording",
                            elapsed: Format.clock(recorder.elapsed),
                            levels: recorder.levels,
                            action: { app.record(for: state == .idle ? name : recorder.recording?.className) },
                            stop: { Task { await recorder.stop(api: app.api) } })
            .fixedSize()
            .accessibilityHint(state == .idle ? "Records a \(noun) into \(name)" : "Opens the recording")
    }

    // MARK: the rail (an iPad), and what's attached

    /// What the desktop's rail holds, in its order: Due, Next class, then the notebooks and files.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !dueRows.isEmpty { dueSection(heading: .railTitle) }
            if let next = ClassWords.next(ownEvents, name: name) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(isClass ? "Next class" : "Next meeting", style: .railTitle)
                    Text(next.words).textStyle(.className).foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if hasAttached { attached(heading: .railTitle) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var classNotebooks: [Notebook] {
        notebooks.notebooks.filter { $0.className == name }.sorted { $0.updated > $1.updated }
    }
    private var hasAttached: Bool { !classNotebooks.isEmpty || !(files?.value ?? []).isEmpty }

    /// This class's notebooks on this phone (a tap opens one) and the files attached to it (a tap shows one).
    private func attached(heading: AppText) -> some View {
        let books = classNotebooks, list = files?.value ?? []
        let title = books.isEmpty ? "Files" : list.isEmpty ? "Notebooks" : "Notebooks and files"
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title, style: heading)
            if !books.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(books) { n in
                            Button { openNotebook = NotebookID(id: n.id) } label: { NotebookCover(notebook: n) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                .padding(.bottom, list.isEmpty ? 0 : 12)
            }
            if !list.isEmpty {
                AttachmentList(files: list) { f in Task { await remove(f) } }
            }
        }
    }

    // MARK: what it needs

    /// This folder's events on the calendar from now on (a week of them), soonest first.
    private var ownEvents: [UpcomingEvent] {
        (upcoming?.value?.events ?? []).filter { !$0.allDay && app.className(ofEvent: $0) == name }
            .sorted { (Format.parse($0.start) ?? .distantFuture) < (Format.parse($1.start) ?? .distantFuture) }
    }

    private func remove(_ f: Attachment) async {
        guard let api = app.api else { return }
        do {
            try await api.deleteAttachment(f.id)
            await files?.load()
            message = "Removed \(f.name)."
        } catch let e as APIError {
            message = e.detail
        } catch {}
    }
}

/// A notebook opened over the page.
private struct NotebookID: Identifiable { var id: UUID }

/// A section's heading: the page's ("Lectures", 17) on a phone, the rail's ("Due", 15) on an iPad.
private struct SectionTitle: View {
    var text: String
    var style: AppText
    init(_ text: String, style: AppText) {
        self.text = text
        self.style = style
    }
    var body: some View {
        Text(text).textStyle(style).foregroundStyle(.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 8)
    }
}

/// A notebook's first page, as small as a thumbnail, its title under it and, until it's in the library, saying so.
private struct NotebookCover: View {
    var notebook: Notebook
    @State private var store = NotebookStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = store.thumbnail(notebook, width: 200) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white
                }
            }
            .frame(width: 96, height: 124)
            .clipShape(.rect(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line))
            Text(notebook.title).textStyle(.folder).foregroundStyle(.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
            Text(notebook.needsSaving ? "Not saved to your library" : Format.day(notebook.updated))
                .textStyle(.micro).foregroundStyle(notebook.needsSaving ? .inkMuted : .inkSubtle)
                .lineLimit(2)
        }
        .frame(width: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The words a folder's page says, as the desktop's OverviewModel says them (ForClass, Meets, NextMeets, Rail).
enum ClassWords {
    /// "MATH 162 on Canvas. Meets Tuesday and Thursday at 9:00 AM."; "Club meetings, Thursdays at 6:00 PM."; "3
    /// lectures so far." when the calendar says nothing of it. `group` is "" for a class; a code means it's on Canvas.
    static func lede(name: String, group: String, code: String, noun: String, count: Int, events: [UpcomingEvent],
                     now: Date = .now) -> String {
        let isClass = group.isEmpty
        var parts: [String] = []
        if isClass, !code.isEmpty, code.caseInsensitiveCompare(name) != .orderedSame { parts.append("\(code) on Canvas.") }
        let when = meets(name: name, events: events, asClass: isClass, now: now)
        let kind = group == "Clubs" ? "Club meetings" : group == "Work" ? "Work meetings" : "Meetings"
        if isClass, !when.isEmpty { parts.append(when + ".") }
        else if !when.isEmpty { parts.append("\(kind), \(when).") }
        else if parts.isEmpty { parts.append(count == 0 ? "No \(noun)s yet." : "\(count) \(noun)\(count == 1 ? "" : "s") so far.") }
        return parts.joined(separator: " ")
    }

    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let plurals = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]

    /// When a folder meets, from its week of events: for a class "Meets Monday, Wednesday and Friday at 9:30 AM", for
    /// a club or work "Thursdays at 6:00 PM"; the time only when every meeting starts at the same one. Its events named
    /// for it are its regular meetings; one with a name of its own (a lab, a team sync) counts only when there are none
    /// of those. "" with nothing on the calendar for it.
    static func meets(name: String, events: [UpcomingEvent], asClass: Bool, now: Date = .now) -> String {
        var own = events.filter { !$0.allDay }
        let regular = own.filter { ClassMatch.normalized($0.title) == ClassMatch.normalized(name) }
        if !regular.isEmpty { own = regular }
        let weekOn = now.addingTimeInterval(7 * 86_400)
        let starts = own.compactMap { Format.parse($0.start) }.filter { $0 < weekOn }
        guard !starts.isEmpty else { return "" }
        let cal = Format.calendar
        // Monday first, as the desktop lists them.
        let weekdays = Set(starts.map { cal.component(.weekday, from: $0) - 1 }).sorted { ($0 + 6) % 7 < ($1 + 6) % 7 }
        var times: [String] = []
        for s in starts.map(Format.time) where !times.contains(s) { times.append(s) }
        let at = times.count == 1 ? " at \(times[0])" : ""
        return asClass ? "Meets \(list(weekdays.map { days[$0] }))\(at)" : "\(list(weekdays.map { plurals[$0] }))\(at)"
    }

    /// When it next meets: "Tomorrow at 9:00 AM", "Wednesday at 9:30 AM", with the event's name when it's more than
    /// the folder's own ("Sunday at 1:00 PM, Organic Chemistry Lab") and where ("in Science Hall 204"); `on` while it
    /// is ("On now, until 9:50 AM"). Nil with nothing ahead.
    static func next(_ events: [UpcomingEvent], name: String, now: Date = .now) -> (words: String, on: Bool)? {
        guard let e = events.first(where: { (Format.parse($0.end) ?? .distantPast) > now }),
              let start = Format.parse(e.start) else { return nil }
        let on = start <= now
        var words: String
        if on {
            words = Format.parse(e.end).map { "On now, until \(Format.time($0))" } ?? "On now"
        } else {
            let away = Format.daysBetween(now, start)
            let day = away == 0 ? "Today" : away == 1 ? "Tomorrow" : away < 7 ? Format.words(start, "EEEE") : Format.words(start, "EEE d MMM")
            words = "\(day) at \(Format.time(start))"
        }
        if ClassMatch.normalized(e.title) != ClassMatch.normalized(name) { words += ", \(e.title)" }
        if let place = e.location?.trimmingCharacters(in: .whitespaces), !place.isEmpty { words += " in \(place)" }
        return (words, on)
    }

    /// "Monday", "Monday and Wednesday", "Monday, Wednesday and Friday".
    static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        default: words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
    }

    struct DueRow {
        var item: DueItem
        var when: String
        var late: Bool
        /// Due within a week: said in bold ink.
        var soon: Bool
    }

    /// The next three still to hand in for this class, anything missing first: "Sun 18 Oct, in 6 days", "Was due Mon
    /// 5 Oct".
    static func due(_ list: DueList?, in name: String, now: Date = .now) -> [DueRow] {
        var late: [DueItem] = [], ahead: [DueItem] = []
        for g in list?.groups ?? [] where ["overdue", "week", "later"].contains(g.key) {
            for i in g.items where i.class == name && !i.excused {
                if g.key == "overdue" || i.missing { late.append(i) } else if i.due != nil { ahead.append(i) }
            }
        }
        func at(_ i: DueItem) -> Date { Format.parse(i.due) ?? .distantFuture }
        let rows = late.sorted { at($0) < at($1) }.map { DueRow(item: $0, when: Format.railDue($0.due, late: true, now: now), late: true, soon: false) }
            + ahead.sorted { at($0) < at($1) }.map { i in
                DueRow(item: i, when: Format.railDue(i.due, late: false, now: now), late: false, soon: Format.daysBetween(now, at(i)) <= 7)
            }
        return Array(rows.prefix(3))
    }
}

/// Files added to a class or lecture, each opening in Quick Look: what it is, its name, and "Slides · 2.4 MB" under it
/// (the desktop's words), parted by hairlines. With `onRemove`, a press and hold offers Remove.
struct AttachmentList: View {
    @Environment(AppModel.self) private var app
    var files: [Attachment]
    var onRemove: ((Attachment) -> Void)?
    @State private var preview: URL?
    @State private var opening: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.element.id) { i, f in
                if i > 0 { Rule() }
                Button { Task { await open(f) } } label: {
                    HStack(spacing: 12) {
                        Icon(Self.icon(f), size: 18).foregroundStyle(.inkMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).textStyle(.body).foregroundStyle(.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Text(Self.about(f)).textStyle(.micro).foregroundStyle(.inkSubtle)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if opening == f.id { ProgressView().tint(.inkSubtle) }
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.row)
                .accessibilityLabel("\(f.name), \(Self.about(f))")
                .contextMenu {
                    if let onRemove {
                        Button("Remove", icon: "delete", role: .destructive) { onRemove(f) }
                    }
                }
            }
        }
        .quickLookPreview($preview)
    }

    /// A slide deck, a picture, a recording, or a page (the desktop's AttachmentWords.Icon).
    static func icon(_ f: Attachment) -> String {
        if f.type.hasPrefix("audio/") { return "graphic_eq" }
        if kind(f) == "Slides" { return "slideshow" }
        return f.type.hasPrefix("image/") ? "image" : "description"
    }

    /// "Slides · 2.4 MB", "Your notes · 830 KB · Reading your handwriting…", "Handout · 1.2 MB · No words to read in it".
    static func about(_ f: Attachment) -> String {
        let audio = f.type.hasPrefix("audio/")
        let state = f.reading ? "Reading your handwriting…" : f.hasText || audio ? "" : "No words to read in it"
        return [audio ? "Recording" : kind(f), Format.fileSize(f.size), state].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What the notes call it (the desktop's Attachments.KindOf): slides, the student's own notes, or a handout.
    static func kind(_ f: Attachment) -> String {
        let url = URL(fileURLWithPath: f.name)
        if ["pptx", "ppt", "key"].contains(url.pathExtension.lowercased()) { return "Slides" }
        if f.type.hasPrefix("image/") { return "Your notes" }
        let stem = url.deletingPathExtension().lastPathComponent
        func has(_ pattern: String) -> Bool { stem.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has(#"note|handwrit|goodnotes|notability|scan|my\b"#) { return "Your notes" }
        if has(#"slide|deck|lecture|ppt|keynote|week\s*\d|chapter|ch\s*\d"#) { return "Slides" }
        return "Handout"
    }

    /// Download it (with the pairing cookie) to a temporary file Quick Look can show.
    private func open(_ f: Attachment) async {
        guard let api = app.api else { return }
        opening = f.id
        defer { opening = nil }
        do {
            let (data, _) = try await AppModel.session.data(from: api.attachmentURL(f.id))
            let dir = FileManager.default.temporaryDirectory.appending(path: f.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: f.name)
            try data.write(to: file)
            preview = file
        } catch {}
    }
}
