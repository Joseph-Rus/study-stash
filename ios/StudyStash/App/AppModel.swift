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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        libraryName = defaults.string(forKey: Self.nameKey) ?? "Your library"
        if let saved = ResponseCache.shared.read("library", as: LibraryOverview.self) {
            classIndex = Self.index(saved.classes)
            classes = saved.classes
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
