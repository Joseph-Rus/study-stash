import Foundation
import WidgetKit
import Observation
import SwiftUI

/// The tabs: Home, Due (school libraries), Ask and Search on a phone; on an iPad's sidebar also each class
/// (`folder`). Settings is a page pushed from Home's toolbar.
enum TabID: Hashable, Sendable {
    case home, due, ask, search
    case folder(String)
}

extension View {
    /// This page is about `cls` (a class's page, a lecture in it): while it shows, the Record bar says "Record
    /// Calculus II" and records into it. Nil says nothing (the bar falls back to the class on the calendar now).
    func recordsInto(_ cls: String?) -> some View { modifier(RecordsInto(cls: cls)) }

    /// While this page shows, the Record bar above the tabs is hidden (a page that hides the tab bar).
    func hidesRecordBar(_ hide: Bool = true) -> some View { modifier(HidesRecordBar(hide: hide)) }
}

private struct RecordsInto: ViewModifier {
    var cls: String?
    @Environment(AppModel.self) private var app
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { app.enterRecordPlace(token, cls) }
            .onChange(of: cls) { _, new in app.enterRecordPlace(token, new) }
            .onDisappear { app.leaveRecordPlace(token) }
    }
}

private struct HidesRecordBar: ViewModifier {
    var hide: Bool
    @Environment(AppModel.self) private var app
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { app.hideRecordBar(token, hide) }
            .onChange(of: hide) { _, new in app.hideRecordBar(token, new) }
            .onDisappear { app.hideRecordBar(token, false) }
    }
}

/// The whole app's state: which library this phone is paired with, and the client that reaches it.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        /// No library yet, or it said this phone isn't paired.
        case unpaired
        /// Paired before; finding out whether the library still knows this phone.
        case checking
        /// Paired and in.
        case ready
    }

    private(set) var phase: Phase
    private(set) var api: APIClient?
    private(set) var libraryName: String
    /// The library couldn't be reached last time it was asked: screens show what was saved before.
    var offline = false
    /// Something opened from another app (or chosen from +), waiting for its sheet.
    enum Incoming: Identifiable {
        case files([PendingFile], className: String?, lecture: (id: String, title: String)?)
        case audio(PendingFile?)
        case goodnotes(URL)
        case handwriting(className: String?, lecture: (id: String, title: String)?)
        /// The Attach sheet, the one chooser (scan, photos, files, write, import a recording, GoodNotes), for a class
        /// and maybe a lecture; nil class from Home (it asks which).
        case attach(className: String?, lecture: (id: String, title: String)?)

        var id: String {
            switch self {
            case .attach(let c, let l): "attach-\(c ?? "")-\(l?.id ?? "")"
            case .files(let f, _, _): "files-\(f.map(\.id.uuidString).joined())"
            case .audio(let f): "audio-\(f?.id.uuidString ?? "")"
            case .goodnotes(let u): "goodnotes-\(u.path)"
            case .handwriting(let c, let l): "handwriting-\(c ?? "")-\(l?.id ?? "")"
            }
        }
    }

    var incoming: Incoming?

    // MARK: where the app is: tabs, their stacks, going somewhere

    /// The tab showing.
    var tab: TabID = DebugLaunch.tab ?? .home
    /// Each tab's stack of pages (`NavigationStack(path: app.stack(.due))`).
    var paths: [TabID: NavigationPath] = [:]
    /// Goes up by one whenever `go` closes what's presented: a page that presents a sheet or cover of its own closes it
    /// on a change (`.onChange(of: app.dismissal) { asking = false }`).
    private(set) var dismissal = 0
    /// The class Due shows when it's opened for one (`showDue(class:)`); nil for all.
    var dueFilter: String?

    /// A tab's stack, for its NavigationStack.
    func stack(_ tab: TabID) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    /// Go to `route` from anywhere (a sheet, a widget, a notification, another tab): close what's presented, select
    /// `tab`, with `root` empty its stack first, then push `route` (nil: just the tab).
    func go(_ route: Route?, tab: TabID = .home, root: Bool = false) {
        showingRecorder = false
        incoming = nil
        dismissal += 1
        var path = root ? NavigationPath() : (paths[tab] ?? NavigationPath())
        if let route { path.append(route) }
        paths[tab] = path
        self.tab = tab
    }

    /// A tab at its first page (Home from setup, a class-start notification).
    func go(to tab: TabID, root: Bool = true) { go(nil, tab: tab, root: root) }

    /// Due, showing one class's work (or all).
    func showDue(class cls: String?) {
        dueFilter = cls
        go(to: forSchool ? .due : .home, root: true)
    }

    /// Fresh due work and calendar: reminders scheduled from them, recordings waiting sent, notes ready said.
    func refreshInBackground() async {
        guard let api else { return }
        async let due = try? api.due()
        async let upcoming = try? api.upcoming()
        let (d, u) = await (due, upcoming)
        if let d { ResponseCache.shared.write("due", d) }
        if let u { ResponseCache.shared.write("upcoming", u); self.upcoming = u }
        await Reminders.schedule(upcoming: u, due: d) { [weak self] e in self?.className(ofEvent: e) }
        writeGlance(upcoming: u, due: d)
        await RecordingStore.shared.sendWaiting(api: api)
        await Reminders.checkNotes(api: api)
        if let all = try? await api.lectures(limit: 500) { SpotlightIndex.index(all) }
    }

    /// A file another app handed over ("Open in Study Stash" / the share sheet).
    func open(_ url: URL) {
        if url.pathExtension.lowercased() == "goodnotes" {
            incoming = .goodnotes(url)
            return
        }
        guard let file = PendingFile.from(url: url) else { return }
        incoming = file.type.hasPrefix("audio/") || file.type.hasPrefix("video/") ? .audio(file) : .files([file], className: nil, lecture: nil)
    }

    // MARK: recording: where Record records, starting, after Stop

    /// The recording screen is up; `recordFor` is the class it starts with, `recordTitle` its title (from an event:
    /// "Calculus II, Fri 16 Oct"; "" for none).
    var showingRecorder = false
    var recordFor: String?
    var recordTitle = ""

    /// Open the recorder, recording into `cls` (nil: Unsorted) with `title`; or, when something's recording, show it.
    func record(for cls: String?, title: String = "") {
        recordFor = cls
        recordTitle = title
        showingRecorder = true
    }

    /// The calendar, as the library last said (Record's class now, Up next).
    var upcoming: Upcoming? = ResponseCache.shared.read("upcoming", as: Upcoming.self)

    /// The pages showing that are about a class, innermost last (`.recordsInto(cls)`).
    private var recordPlaces: [(token: UUID, cls: String?)] = []
    /// The class of the page showing, if it's about one (a class's page, a lecture in it).
    var recordHere: String? { recordPlaces.last?.cls }
    /// Where Record records: the page's class, else the class on the calendar now (from 10 minutes before), else none.
    var recordClass: String? { recordHere ?? classNow(upcoming) }
    /// What the Record bar says: "Record Calculus II", or "Record".
    var recordWords: String { recordClass.map { "Record \($0)" } ?? "Record" }

    func enterRecordPlace(_ token: UUID, _ cls: String?) {
        recordPlaces.removeAll { $0.token == token }
        recordPlaces.append((token, cls))
    }

    func leaveRecordPlace(_ token: UUID) { recordPlaces.removeAll { $0.token == token } }

    /// Pages that hide the Record bar (the lecture page, with the tab bar hidden).
    private var barHiders: Set<UUID> = []
    var recordBarHidden: Bool { !barHiders.isEmpty }
    func hideRecordBar(_ token: UUID, _ hide: Bool) { if hide { barHiders.insert(token) } else { barHiders.remove(token) } }

    /// After Stop (and after Import a recording): the recorder closes, then the lecture opens in its "being written"
    /// state when the library has it (`sent`), else the recording on this phone. `id` is the recording's, which is
    /// the lecture's id in the library too.
    func recordingFinished(id: String, sent: Bool) {
        go(sent ? .lecture(id) : .recording(id), tab: .home)
    }

    /// Each class's place in the library, which picks its highlighter.
    var classIndex: [String: Int] = [:]

    /// A class's highlighter (the desktop's for that class), or nil for none: Unsorted, or a name no class has. Show
    /// it only as a `Swatch`, a `Highlight` behind the class's name, or the underline of its page's title.
    func hue(of cls: String?) -> Highlighter? {
        guard let cls, cls != "Unsorted" else { return nil }
        return (classIndex[cls] ?? classIndex[ClassMatch.normalized(cls)]).map(Highlighter.init(classIndex:))
    }

    /// The class colour as a tint, from the look before. A class's colour is never a tint now (only a swatch, a
    /// highlight or an underline): this is ink, so what still asks for it is drawn as the desktop draws it.
    @available(*, deprecated, message: "A class's colour is only a Swatch, a Highlight or a FolderTitle's underline: use hue(of:); text and icons are ink")
    func color(of cls: String?) -> Color { .ink }

    /// The sidebar group a class is in on the computer ("" for Classes).
    func group(of cls: String?) -> String? {
        guard let cls else { return nil }
        return classes.first { $0.name == cls }?.group
    }

    /// What a recording in `cls` is called: "lecture", "meeting" or "recording" (`Nouns`).
    func noun(of cls: String?) -> String {
        Nouns.of(folder: cls, group: group(of: cls), school: forSchool, work: words.work)
    }

    /// Every class, as the library last said.
    var classes: [ClassInfo] = []

    /// A calendar event's class: the one the library matched, else one whose name, other name or course code the
    /// title carries ("Machine Learning" in "Machine & Deep Learning").
    func className(ofEvent e: UpcomingEvent) -> String? {
        if let c = e.class { return c }
        let title = ClassMatch.normalized(e.title)
        let words = Set(title.split(separator: " "))
        var best: (name: String, score: Int)?
        for c in classes {
            for key in [c.name] + (c.aliases ?? []) + [c.code ?? ""] where !key.isEmpty {
                let k = ClassMatch.normalized(key)
                let ws = k.split(separator: " ").filter { $0.count > 2 && $0 != "and" }
                let hit = k == title || (k.count >= 4 && title.contains(k)) || (ws.count >= 2 && ws.allSatisfy(words.contains))
                if hit, k.count > (best?.score ?? 0) { best = (c.name, k.count) }
            }
        }
        return best?.name
    }

    /// A class the event looks like it's for, when the library didn't match one: the one to suggest.
    func suggestion(forEvent e: UpcomingEvent) -> String? {
        e.class == nil ? className(ofEvent: e) : nil
    }

    /// Every event called this is `cls`'s from now on (the library keeps the title as one of the class's names).
    func file(event e: UpcomingEvent, in cls: String) async throws {
        guard let api else { return }
        let overview = try await api.setAlias(e.title, class: cls)
        learn(overview)
        ResponseCache.shared.write("library", overview)
    }

    /// A calendar event's class's highlighter, or nil when it's no class's.
    func hue(ofEvent e: UpcomingEvent) -> Highlighter? { hue(of: className(ofEvent: e)) }

    /// The class on the calendar right now (or starting in the next 10 minutes), to record for.
    func classNow(_ upcoming: Upcoming?) -> String? {
        let now = Date.now
        return upcoming?.events.first { e in
            guard !e.allDay, let s = Format.parse(e.start), let end = Format.parse(e.end) else { return false }
            return s.addingTimeInterval(-600) <= now && now < end
        }.flatMap(className(ofEvent:))
    }

    func learn(_ overview: LibraryOverview) {
        classIndex = Self.index(overview.classes)
        classes = overview.classes
        libraryName = overview.name
        uses = overview.uses
        if let s = overview.forSchool { forSchool = s }
    }

    /// What the widgets show: the next classes and what's due next, with their classes' highlighters ("blue").
    func writeGlance(upcoming: Upcoming?, due: DueList?) {
        let now = Date.now
        let events = (upcoming?.events ?? []).compactMap { e -> Glance.Event? in
            guard !e.allDay, let s = Format.parse(e.start), let end = Format.parse(e.end), end > now else { return nil }
            let cls = className(ofEvent: e)
            return Glance.Event(title: e.title, className: cls, start: s, end: end, location: e.location, color: hue(of: cls)?.rawValue)
        }
        let open = (due?.groups ?? []).filter { ["overdue", "week", "later"].contains($0.key) }
            .flatMap { g in g.items.map { (item: $0, overdue: g.key == "overdue") } }
        let dueItems = open.compactMap { x -> Glance.Due? in
            guard let at = Format.parse(x.item.due) else { return nil }
            return Glance.Due(name: x.item.name, className: x.item.class, due: at, overdue: x.overdue, color: hue(of: x.item.class)?.rawValue)
        }
        Glance(library: libraryName, events: Array(events.prefix(6)), due: Array(dueItems.prefix(6)), toHandIn: due?.toHandIn ?? 0, updated: now).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// What the library is for (nil: it's from before it was asked; empty: not asked yet).
    var uses: [String]?
    /// School (classes, Canvas, due dates), or folders for everything else.
    var forSchool = true
    var words: Words { Words(school: forSchool, work: uses?.contains("work") == true && !forSchool) }

    /// Ask what it's for, once, when the library hasn't been told.
    var needsUses: Bool { uses?.isEmpty == true && !askedUses }
    var askedUses: Bool {
        get { UserDefaults.standard.bool(forKey: "askedUses") }
        set { UserDefaults.standard.set(newValue, forKey: "askedUses") }
    }

    func setUses(_ list: [String]) async {
        askedUses = true
        guard let api, let overview = try? await api.setUses(list) else { return }
        learn(overview)
        ResponseCache.shared.write("library", overview)
    }

    /// Each class by its name, its other names and its course code, as `color(of:)` and `classFor(event:)` look
    /// them up; a calendar names a class the way Canvas does ("Theory Of Computation & Compilers").
    nonisolated static func index(_ classes: [ClassInfo]) -> [String: Int] {
        var out: [String: Int] = [:]
        for c in classes {
            for key in [c.name] + (c.aliases ?? []) + [c.code ?? ""] where !key.isEmpty {
                out[key] = out[key] ?? c.color
                out[ClassMatch.normalized(key)] = out[ClassMatch.normalized(key)] ?? c.color
            }
        }
        return out
    }

    @ObservationIgnored private let defaults: UserDefaults
    static let baseKey = "library.base"
    static let nameKey = "library.name"

    /// The app's one model, for what Siri and Shortcuts ask (they run in the app's process).
    static weak var current: AppModel?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defer { if defaults == .standard { AppModel.current = self } }
        libraryName = defaults.string(forKey: Self.nameKey) ?? "Your library"
        if let saved = ResponseCache.shared.read("library", as: LibraryOverview.self) {
            classIndex = Self.index(saved.classes)
            classes = saved.classes
            uses = saved.uses
            forSchool = saved.forSchool ?? true
        }
        if let s = defaults.string(forKey: Self.baseKey), let base = URL(string: s) {
            phase = .checking
            api = makeClient(base)
        } else {
            phase = .unpaired
        }
    }

    private func makeClient(_ base: URL) -> APIClient {
        APIClient(base: base, session: Self.session) { [weak self] in
            Task { @MainActor in self?.signedOut() }
        }
    }

    /// One session for the app: cookies (the pairing) kept for good, and a cache for when the library is away.
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 20
        // The demo library answers in the app.
        c.protocolClasses = [DemoLibrary.self] + (c.protocolClasses ?? [])
        return URLSession(configuration: c)
    }()

    /// On launch: is this phone still paired? An unreachable library keeps the phone in, reading what was saved.
    func check() async {
        guard let api else { phase = .unpaired; return }
        do {
            let me = try await api.me()
            libraryName = me.library.name
            defaults.set(me.library.name, forKey: Self.nameKey)
            offline = false
            phase = me.paired ? .ready : .unpaired
            if me.paired { await RecordingStore.shared.sendWaiting(api: api) }
        } catch let e as APIError where e.unreachable {
            offline = true
            phase = .ready
        } catch {
            phase = .ready
        }
    }

    /// Paired with the library at `base`: remember it.
    func paired(base: URL, library: Me.Library) {
        // Another library's lectures aren't this one's.
        if api?.base != base {
            ResponseCache.shared.clear()
            classIndex = [:]
            classes = []
        }
        defaults.set(base.absoluteString, forKey: Self.baseKey)
        defaults.set(library.name, forKey: Self.nameKey)
        libraryName = library.name
        api = makeClient(base)
        offline = false
        phase = .ready
    }

    var isDemo: Bool { api?.base.host() == DemoLibrary.host }

    func tryDemo() {
        paired(base: DemoLibrary.base, library: Me.Library(name: "Demo library", version: "demo"))
    }

    /// The library no longer knows this phone (removed in Settings), or the student chose to forget it.
    func signedOut() {
        guard phase != .unpaired else { return }
        phase = .unpaired
    }

    #if DEBUG
    /// Forget the library on this phone only, without asking it anything (`-unpaired`): setup shows.
    func forgetHere() {
        defaults.removeObject(forKey: Self.baseKey)
        defaults.removeObject(forKey: Self.nameKey)
        api = nil
        libraryName = "Your library"
        phase = .unpaired
    }
    #endif

    func forget() async {
        if let api, let me = try? await api.me(), let id = me.device?.id { try? await api.removeDevice(id) }
        if let base = api?.base {
            for cookie in HTTPCookieStorage.shared.cookies(for: base) ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
        defaults.removeObject(forKey: Self.baseKey)
        defaults.removeObject(forKey: Self.nameKey)
        ResponseCache.shared.clear()
        SpotlightIndex.clear()
        api = nil
        libraryName = "Your library"
        phase = .unpaired
    }
}

enum ClassMatch {
    /// "Theory Of Computation & Compilers" → "theory of computation and compilers".
    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The app's words for what it holds: classes and lectures for school; folders and recordings (meetings at work) else.
struct Words {
    var school: Bool
    var work: Bool

    var cls: String { school ? "class" : "folder" }
    var classes: String { school ? "Classes" : "Folders" }
    var anyClass: String { school ? "Any class" : "Any folder" }
    var lecture: String { school ? "lecture" : work ? "meeting" : "recording" }
    var lectures: String { school ? "lectures" : work ? "meetings" : "recordings" }
    /// The Record bar's word with no class to name: "Record".
    var record: String { "Record" }
}
