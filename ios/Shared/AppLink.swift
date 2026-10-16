import Foundation

/// The app's own links (`studystash://…`), for widgets, the Live Activity, notifications and anything else that
/// opens a place in the app. The app reads them in `AppModel.open(_:)`. Compiled into the app and the widgets.
enum AppLink {
    static let scheme = "studystash"

    /// Home.
    static var home: URL { make("home") }
    /// Record, into `cls` (nil: the class on now, else none).
    static func record(class cls: String? = nil) -> URL { make("record", query: ["class": cls]) }
    /// The recording going on (the recorder), else Home.
    static var recording: URL { make("recording") }
    /// A lecture; with `at`, its transcript at that second.
    static func lecture(_ id: String, at: Double? = nil) -> URL { make("lecture", [id], query: ["at": at.map { String(Int($0)) }]) }
    /// A class's page.
    static func folder(_ name: String) -> URL { make("class", [name]) }
    /// Due.
    static var due: URL { make("due") }
    /// An assignment.
    static func assignment(class cls: String, id: Int) -> URL { make("assignment", [cls, String(id)]) }
    /// Ask.
    static var ask: URL { make("ask") }

    private static func make(_ host: String, _ parts: [String] = [], query: [String: String?] = [:]) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.path = parts.isEmpty ? "" : "/" + parts.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/"))) ?? $0 }.joined(separator: "/")
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }

    /// A link's place: its host, its path's parts (decoded), its query.
    static func parts(_ url: URL) -> (place: String, path: [String], query: [String: String])? {
        guard url.scheme == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = c.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let query = Dictionary((c.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a })
        return (c.host ?? "", path, query)
    }
}
