import Foundation

// The library's /api/v2 as the phone reads it. Each shape mirrors web/src/api/types.ts (and the C# named there);
// fields a library from before them doesn't send are optional.

/// GET /api/v2/me (no sign-in needed): whether this phone is paired, and which library it reached.
struct Me: Codable, Sendable {
    struct Library: Codable, Sendable, Hashable {
        var name: String
        var version: String
    }
    var paired: Bool
    var library: Library
    var device: Device?
}

/// POST /api/v2/devices/pair → the device this phone now is.
struct Device: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var added: String
    var lastSeen: String?
}

/// One class. `color` is the class's place in the library: its dot's colour.
struct ClassInfo: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var lectures: Int
    var color: Int
    var description: String?
    /// The linked Canvas course's short code ("CSCI 321"), "" when there's none.
    var code: String?
    var aliases: [String]?
    var id: String { name }
}

/// GET /api/v2/library.
struct LibraryOverview: Codable, Sendable {
    var name: String
    var version: String
    var classes: [ClassInfo]
    var unsorted: Int
    /// Lectures queued or being written.
    var writing: Int
    var ask: Bool
    var notesModel: String?

    enum CodingKeys: String, CodingKey {
        case name, version, classes, unsorted, writing, ask
        case notesModel = "notes_model"
    }
}

/// One lecture in a list.
struct LectureSummary: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String?
    var `class`: String?
    var date: String?
    var seconds: Double?
    var owner: String?
    /// "queued", "working", "done" or "failed".
    var status: String
    var summary: String
    var topics: [String]
    var hasTranscript: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, `class`, date, seconds, owner, status, summary, topics
        case hasTranscript = "has_transcript"
    }

    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? "Untitled lecture" }
    var isWriting: Bool { status == "queued" || status == "working" }
}

/// GET /api/v2/lectures/{id}: the summary plus the notes and transcript.
struct Lecture: Codable, Sendable {
    var id: String
    var title: String?
    var `class`: String?
    var date: String?
    var seconds: Double?
    var owner: String?
    var status: String
    var summary: String
    var topics: [String]
    var notes: String
    var transcript: String
    var error: String?
    /// That reason in a sentence, when no notes will be written ("This lecture is too short for notes…").
    var noNotesWhy: String?

    enum CodingKeys: String, CodingKey {
        case id, title, `class`, date, seconds, owner, status, summary, topics, notes, transcript, error
        case noNotesWhy = "no_notes_why"
    }

    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? "Untitled lecture" }
}

/// GET /api/v2/lectures/{id}/rendered: the notes as safe HTML, diagrams inline, no scripts.
struct RenderedLecture: Codable, Sendable {
    var id: String
    var title: String
    var `class`: String?
    var date: String?
    var html: String
}

/// A passage the search found.
struct Passage: Codable, Sendable, Hashable {
    var id: String
    var title: String?
    var `class`: String?
    var date: String?
    /// "notes" or "transcript".
    var kind: String
    var section: String
    /// Seconds into the recording, for a transcript passage.
    var at: Double?
    var text: String
}

/// GET /api/v2/search.
struct SearchResults: Codable, Sendable {
    var query: String
    var lectures: [LectureSummary]
    var passages: [Passage]
    var classes: [ClassInfo]
}

/// One source an answer used.
struct AskSource: Codable, Sendable, Hashable {
    var id: String?
    var title: String
    var `class`: String?
    var date: String?
    var at: Double?
    var section: String
}

/// POST /api/v2/ai/ask.
struct AskReply: Codable, Sendable {
    var answer: String
    var sources: [AskSource]
    var engineName: String
    var fellBack: Bool
    var why: String

    enum CodingKeys: String, CodingKey {
        case answer, sources, why
        case engineName = "engine_name"
        case fellBack = "fell_back"
    }
}

/// What POST /api/v2/ai/ask with stream: true sends, one per line.
enum AskEvent: Decodable, Sendable {
    case text(String)
    case answer(String)
    case done(AskReply)
    case error(status: Int, detail: String)

    enum CodingKeys: String, CodingKey { case kind, text, reply, status, detail }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "answer": self = .answer(try c.decode(String.self, forKey: .text))
        case "done": self = .done(try c.decode(AskReply.self, forKey: .reply))
        default:
            self = .error(status: (try? c.decode(Int.self, forKey: .status)) ?? 500,
                          detail: (try? c.decode(String.self, forKey: .detail)) ?? "Something went wrong.")
        }
    }
}

/// A chat in the list.
struct ChatSummary: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var `class`: String
    var lecture: String
    var updated: String
}

struct ChatMessage: Codable, Sendable, Hashable {
    var role: String
    var text: String
    var when: String
    var tools: [String]?
    var failed: Bool?
}

/// GET /api/v2/chats/{id}.
struct Chat: Codable, Sendable {
    var id: String
    var title: String
    var `class`: String
    var lecture: String
    var updated: String
    var messages: [ChatMessage]
}

/// What POST /api/v2/chat sends, one per line: first the chat's id, then its events, then done.
struct ChatEvent: Codable, Sendable {
    var chat: String?
    var kind: String?
    var text: String?
    var name: String?
}

/// One assignment on the Due list. `due` is local time without an offset.
struct DueItem: Codable, Sendable, Hashable {
    var `class`: String
    var id: Int
    var name: String
    /// "assignment", "quiz", "discussion" or "todo".
    var kind: String
    var due: String?
    var points: Double?
    var status: String
    var label: String
    var scoreText: String
    var late: Bool
    var missing: Bool
    var excused: Bool
    var submitted: String?
    var url: String

    enum CodingKeys: String, CodingKey {
        case `class`, id, name, kind, due, points, status, label, late, missing, excused, submitted, url
        case scoreText = "score_text"
    }
}

/// GET /api/v2/canvas/due.
struct DueList: Codable, Sendable {
    struct Group: Codable, Sendable, Hashable {
        /// "overdue", "week", "later", "undated" or "handed_in".
        var key: String
        var label: String
        var items: [DueItem]
    }
    var synced: String?
    var toHandIn: Int
    var groups: [Group]

    enum CodingKeys: String, CodingKey {
        case synced, groups
        case toHandIn = "to_hand_in"
    }
}

/// One event in GET /api/v2/calendar/upcoming. `class` is the matched class, or nil.
struct UpcomingEvent: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var start: String
    var end: String
    var allDay: Bool
    var location: String?
    var `class`: String?
}

struct Upcoming: Codable, Sendable {
    var events: [UpcomingEvent]
    var updated: String?
}

/// GET /api/v2/canvas/assignment: one assignment's page.
struct AssignmentDetail: Codable, Sendable {
    struct Criterion: Codable, Sendable, Hashable {
        struct Mark: Codable, Sendable, Hashable {
            var points: Double?
            var comment: String?
        }
        var criterion: String
        var points: Double?
        var description: String?
        var mark: Mark?
    }
    struct Comment: Codable, Sendable, Hashable {
        var author: String
        var text: String
        var when: String?
        var mine: Bool?
    }
    var `class`: String
    var id: Int
    var name: String
    var kind: String
    var due: String?
    var points: Double?
    var label: String
    var scoreText: String
    var late: Bool
    var missing: Bool
    var url: String
    var instructions: String?
    var instructionsHTML: String?
    var rubric: [Criterion]
    var comments: [Comment]

    enum CodingKeys: String, CodingKey {
        case `class`, id, name, kind, due, points, label, late, missing, url, instructions, rubric, comments
        case scoreText = "score_text"
        case instructionsHTML = "instructions_html"
    }
}

/// A file added to a class or lecture.
struct Attachment: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var `class`: String
    var lecture: String?
    var size: Int
    var type: String
    var added: String
    var hasText: Bool
    /// Still being read: show "Reading your handwriting…" and keep asking.
    var reading: Bool
}

/// A recording sent from the phone: waiting for a computer, being written down there, done, or failed.
struct VoiceMemo: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var `class`: String?
    var title: String
    var size: Int
    var added: String
    var by: String
    /// "waiting", "transcribing", "done" or "failed".
    var state: String
    var computer: String?
    var lecture: String?
    var error: String?
    var ready: Bool?
}
