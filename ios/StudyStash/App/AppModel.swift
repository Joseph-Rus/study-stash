import Foundation
import Observation
import SwiftUI

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

        var id: String {
            switch self {
            case .files(let f, _, _): "files-\(f.map(\.id.uuidString).joined())"
            case .audio(let f): "audio-\(f?.id.uuidString ?? "")"
            case .goodnotes(let u): "goodnotes-\(u.path)"
            case .handwriting(let c, let l): "handwriting-\(c ?? "")-\(l?.id ?? "")"
            }
        }
    }

    var incoming: Incoming?
    /// A screen to open on the Library tab (from a notification).
    var pendingRoute: Route?

    /// Fresh due work and calendar: reminders scheduled from them, recordings waiting sent, notes ready said.
    func refreshInBackground() async {
        guard let api else { return }
        async let due = try? api.due()
        async let upcoming = try? api.upcoming()
        let (d, u) = await (due, upcoming)
        if let d { ResponseCache.shared.write("due", d) }
        if let u { ResponseCache.shared.write("upcoming", u) }
        await Reminders.schedule(upcoming: u, due: d) { [weak self] e in self?.className(ofEvent: e) }
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

    /// The recording screen is up; `recordFor` is the class it starts with.
    var showingRecorder = false
    var recordFor: String?

    func record(for cls: String?) {
        recordFor = cls
        showingRecorder = true
    }

    /// Each class's place in the library, which is its colour.
    var classIndex: [String: Int] = [:]

    func color(of cls: String?) -> Color {
        guard let cls else { return .secondary }
        if cls == "Unsorted" { return .gray }
        return (classIndex[cls] ?? classIndex[ClassMatch.normalized(cls)]).map { ClassColor.of($0) } ?? .accentColor
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

    func color(ofEvent e: UpcomingEvent) -> Color {
        className(ofEvent: e).map { color(of: $0) } ?? .secondary
    }

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

    /// The library no longer knows this phone (removed in Settings), or the student chose to forget it.
    func signedOut() {
        guard phase != .unpaired else { return }
        phase = .unpaired
    }

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
    var record: String { "Record a \(lecture)" }
}
