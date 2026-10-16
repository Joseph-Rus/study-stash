import Foundation

/// What the widgets show, written by the app whenever it has a fresh look at the library and read by the widgets:
/// the next few classes on the calendar and the next things due, with each class's colour.
struct Glance: Codable, Sendable {
    struct Event: Codable, Hashable, Sendable {
        var title: String
        var className: String?
        var start: Date
        var end: Date
        var location: String?
        var color: String?
    }
    struct Due: Codable, Hashable, Sendable {
        var name: String
        var className: String
        var due: Date
        var overdue: Bool
        var color: String?
    }

    var library: String
    var events: [Event]
    var due: [Due]
    var toHandIn: Int
    var updated: Date

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

    static let sample = Glance(library: "Demo library",
                               events: [Event(title: "Calculus II", className: "Calculus II", start: .now.addingTimeInterval(3600), end: .now.addingTimeInterval(6600), location: "Science Hall 204", color: "#3b82f6")],
                               due: [Due(name: "Problem Set 6", className: "Calculus II", due: .now.addingTimeInterval(86_400 * 2), overdue: false, color: "#3b82f6"),
                                     Due(name: "Lab Report: Titration", className: "Organic Chemistry", due: .now.addingTimeInterval(86_400 * 4), overdue: false, color: "#a855f7")],
                               toHandIn: 3, updated: .now)
}
