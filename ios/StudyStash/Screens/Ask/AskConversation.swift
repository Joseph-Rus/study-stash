import SwiftUI

// What Ask holds: one conversation with the library's AI, kept by the library as a chat the way the desktop keeps
// them (Home's, a class's, a lecture's: AiAskModel.Chats), so it's carried on by a follow-up, listed in Chats on the
// phone and on the computer, and picked up again from either. The stages a question goes through are the ones the
// phone can see: sent, the library has it, its words arriving.

/// One question and what came back: the answer as it was written, the lectures it drew on, or why there's none.
struct AskTurn: Codable, Identifiable, Hashable, Sendable {
    struct Source: Codable, Hashable, Sendable {
        var id: String?
        var title: String
        var `class`: String?
        var date: String?
        var at: Double?
        /// Where in the notes it came from ("Key points") when it isn't a moment in the recording.
        var section: String?
        /// Every moment in this lecture the answer drew on, earliest first.
        var moments: [Double]?

        var times: [Double] { moments ?? at.map { [$0] } ?? [] }
    }
    enum State: String, Codable, Sendable { case asking, done, failed }

    var id = UUID()
    var question: String
    /// What it was asked about, in words ("Calculus II"); nil for everything.
    var scope: String?
    /// What it was asked about, to ask it again.
    var asked: AskScope?
    var answer = ""
    var sources: [Source] = []
    var state: State = .asking
    var problem: String?
    var engine: String?
    /// "This answer came from Ollama. Claude didn't respond in time."
    var note: String?
    /// Stopped by the student partway (what came by then is the answer).
    var stopped: Bool?

    /// One source a lecture, however many of its sections the answer drew on, in the order they came; a lecture's
    /// moments gathered, earliest first.
    static func merged(_ sources: [AskSource]) -> [Source] {
        var out: [Source] = []
        for s in sources {
            if let id = s.id, let i = out.firstIndex(where: { $0.id == id }) {
                if let at = s.at, !(out[i].moments ?? []).contains(where: { Int($0) == Int(at) }) {
                    out[i].moments = ((out[i].moments ?? []) + [at]).sorted()
                    out[i].at = out[i].moments?.first
                }
                continue
            }
            out.append(.init(id: s.id, title: s.title, class: s.class, date: s.date, at: s.at,
                             section: s.section.isEmpty ? nil : s.section, moments: s.at.map { [$0] }))
        }
        return out
    }

    /// The sources as the library takes them back with a follow-up (one a moment).
    var askSources: [AskSource] {
        sources.flatMap { s in
            let times: [Double?] = s.times.isEmpty ? [nil] : s.times
            return times.map { AskSource(id: s.id, title: s.title, class: s.class, date: s.date, at: $0, section: s.section ?? "") }
        }
    }
}

/// What Ask is about: everything, one class, or one lecture (and the class it's in, when it's known).
enum AskScope: Hashable, Codable, Sendable {
    case everything
    case `class`(String)
    case lecture(id: String, title: String, class: String? = nil)

    /// The scope's name in the Ask bar and its menu: "All notes", "Calculus II", "This lecture".
    func label(noun: String = Nouns.lecture) -> String {
        switch self {
        case .everything: "All notes"
        case .class(let c): c
        case .lecture: "This \(noun)"
        }
    }

    /// The Ask bar's words: "Ask anything about your notes", "Ask about Machine Learning", "Ask about this lecture".
    func placeholder(noun: String = Nouns.lecture) -> String {
        switch self {
        case .everything: "Ask anything about your notes"
        case .class(let c): "Ask about \(c)"
        case .lecture: "Ask about this \(noun)"
        }
    }

    var className: String? {
        switch self {
        case .everything: nil
        case .class(let c): c
        case .lecture(_, _, let c): c
        }
    }

    /// Where a conversation started here is kept and listed: Home's, a class's, a lecture's (with its class).
    var place: AskPlace {
        switch self {
        case .everything: .home
        case .class(let c): AskPlace(scope: "class", class: c)
        case let .lecture(id, _, c): AskPlace(scope: "lecture", lecture: id, class: c)
        }
    }

    /// A lecture opened without its class: the class from what the library said last about it (its page, Home's
    /// notes), so it's called a lecture, a meeting or a recording as its folder has it. Nil when nothing says.
    var lectureClassSaved: String? {
        guard case let .lecture(id, _, nil) = self else { return nil }
        let cls = ResponseCache.shared.read("lecture:\(id)", as: Lecture.self)?.class
            ?? ResponseCache.shared.read("home-notes", as: [LectureSummary].self)?.first { $0.id == id }?.class
        return cls.flatMap { $0.isEmpty || $0 == "Unsorted" ? nil : $0 }
    }

    /// This scope with a lecture's class set to `cls`.
    func inClass(_ cls: String?) -> AskScope {
        guard case let .lecture(id, title, nil) = self, let cls else { return self }
        return .lecture(id: id, title: title, class: cls)
    }
}

/// What's happening to the question being answered, as far as the phone can see it.
enum AskStage: Sendable, Equatable {
    /// Sent, and the library hasn't taken it yet (over Google Drive: the laptop hasn't read the phone's request).
    case sending
    /// The library has it and is reading the notes: no words yet.
    case reading
    /// Its words are arriving.
    case writing

    /// What the page says while there are no words yet: "Asking your laptop…", then "Reading your notes…".
    func words(overDrive: Bool) -> String {
        switch self {
        case .sending: overDrive ? "Asking your laptop…" : "Asking your library…"
        case .reading, .writing: "Reading your notes…"
        }
    }
}

/// A conversation with the library's AI: questions, answers streaming in, and their sources. Kept by the library as
/// a chat at `place` (when it keeps chats), and on this phone as it was last (`saveKey`), so the Ask tab opens where
/// the student left it.
@MainActor @Observable
final class AskConversation {
    var turns: [AskTurn]
    /// The library's kept chat this is (a follow-up carries it on); nil until the library has said, so the next
    /// question starts a new one.
    private(set) var chatID: String?
    /// Whether the library keeps chats: nil until it has answered once here.
    private(set) var keeps: Bool?
    /// Where the question being answered has got to.
    private(set) var stage: AskStage = .sending
    /// When the question being answered was sent.
    private(set) var askedAt: Date?
    /// Where its chats are kept and listed (nil: nothing kept).
    let place: AskPlace?

    @ObservationIgnored private let saveKey: String?
    @ObservationIgnored private var asking: Task<Void, Never>?
    @ObservationIgnored private var stopping = false
    /// When the student last stopped an answer. A laptop over Google Drive finishes it anyway, so a question straight
    /// after can find the chat still answering.
    @ObservationIgnored private var stoppedAt: Date?

    private struct Saved: Codable {
        var turns: [AskTurn]
        var chat: String?
    }

    init(saveKey: String?, place: AskPlace?) {
        self.saveKey = saveKey
        self.place = place
        // `-ask-new` (debug): start with nothing asked, for pictures of the empty page.
        let data = DebugLaunch.flag("-ask-new") ? nil : saveKey.flatMap { UserDefaults.standard.data(forKey: $0) }
        // Kept by this version (with its chat), or by the one before (the turns alone).
        let saved = data.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
            ?? data.flatMap { try? JSONDecoder().decode([AskTurn].self, from: $0) }.map { Saved(turns: $0) }
        // A question stopped by the app closing is marked as such, not left asking forever.
        turns = (saved?.turns ?? []).map { var t = $0; if t.state == .asking { t.state = .failed; t.problem = "Stopped before it was answered." }; return t }
        chatID = saved?.chat
    }

    var busy: Bool { turns.contains { $0.state == .asking } }

    /// The question being answered has no words yet.
    var waiting: Bool { turns.last.map { $0.state == .asking && $0.answer.isEmpty } ?? false }

    private func save() {
        guard let saveKey, let data = try? JSONEncoder().encode(Saved(turns: Array(turns.suffix(30)), chat: chatID)) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    // MARK: asking

    /// Ask in the background (Stop stops it).
    func send(_ text: String, scope: AskScope, label: String?, api: APIClient) {
        guard !busy else { return }
        asking = Task { await ask(text, scope: scope, label: label, api: api) }
    }

    /// Stop the answer being written: what came by then stays, said to be stopped.
    func stop() {
        guard busy else { return }
        stopping = true
        asking?.cancel()
    }

    /// Ask `text` and follow the answer as it's written, its stage on the way.
    func ask(_ text: String, scope: AskScope, label: String?, api: APIClient) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        // The conversation so far goes with a follow-up to a library that doesn't keep it (one that does reads it).
        let earlier = keeps == true || turns.isEmpty ? nil : history()
        let turn = AskTurn(question: q, scope: scope == .everything ? nil : label, asked: scope)
        turns.append(turn)
        stage = .sending
        askedAt = .now
        stopping = false
        let i = turns.count - 1
        func update(_ change: (inout AskTurn) -> Void) { if turns.indices.contains(i), turns[i].id == turn.id { change(&turns[i]) } }
        #if DEBUG
        // `-ask-waiting` (debug): leave it asking, for pictures of an answer on its way (`-ask-stage reading|writing`).
        if DebugLaunch.flag("-ask-waiting") {
            switch DebugLaunch.value("-ask-stage") {
            case "reading": stage = .reading
            case "writing": stage = .writing; update { $0.answer = Self.sampleWriting }
            default: break
            }
            return
        }
        #endif
        let overDrive = api.base.host() == DriveLibrary.host
        var lecture: String?, cls: String?
        switch scope {
        case .everything: break
        case .class(let c): cls = c
        case .lecture(let id, _, _): lecture = id
        }
        do {
            let stream = try await api.ask(q, lecture: lecture, class: cls, chat: place == nil ? nil : chatID ?? "new", place: place, history: earlier)
            // The library has the question.
            if !Task.isCancelled { stage = .reading }
            for try await event in stream {
                switch event {
                case .chat(let id):
                    chatID = id
                case .text(let t):
                    stage = .writing
                    update { $0.answer += t }
                case .answer(let t):
                    stage = .writing
                    update { $0.answer = t }
                case .done(let reply):
                    update {
                        if !reply.answer.isEmpty { $0.answer = reply.answer }
                        $0.sources = AskTurn.merged(reply.sources)
                        $0.engine = reply.engineName
                        if reply.fellBack { $0.note = "This answer came from \(reply.engineName). \(reply.why)".trimmingCharacters(in: .whitespaces) }
                        $0.state = .done
                    }
                    if let kept = reply.chat {
                        chatID = kept
                        keeps = true
                    } else if place != nil {
                        // A library too old to keep chats: the next question carries the conversation itself.
                        keeps = false
                        chatID = nil
                    }
                case .error(_, let detail):
                    update { $0.state = .failed; $0.problem = detail.isEmpty ? "The library couldn't answer that." : detail }
                }
            }
            update {
                guard $0.state == .asking else { return }
                if stopping {
                    $0.state = .done
                    $0.stopped = true
                } else {
                    $0.state = $0.answer.isEmpty ? .failed : .done
                    if $0.answer.isEmpty { $0.problem = "No answer came back." }
                }
            }
        } catch {
            update {
                if stopping || error is CancellationError {
                    $0.state = .done
                    $0.stopped = true
                } else {
                    $0.state = .failed
                    $0.problem = Self.problem(error, partway: !$0.answer.isEmpty, overDrive: overDrive, justStopped: stoppedAt.map { Date.now.timeIntervalSince($0) < 180 } ?? false)
                }
            }
        }
        if stopping { stoppedAt = .now }
        stopping = false
        asking = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        save()
    }

    /// Why a question has no answer, in the words the phone uses for its link: the laptop's over Google Drive, the
    /// library's over Tailscale.
    static func problem(_ error: any Error, partway: Bool, overDrive: Bool, justStopped: Bool) -> String {
        let api = error as? APIError
        if partway {
            return overDrive ? "Your laptop stopped answering partway through. Is it on and awake?"
                : "Your library stopped answering partway through. Check it's on and connected."
        }
        // The chat is still answering: here, the answer just stopped, which the laptop finishes anyway.
        if api?.status == 409, justStopped {
            return overDrive ? "Your laptop is still finishing the answer you stopped. Ask again in a moment."
                : "Your library is still finishing the answer you stopped. Ask again in a moment."
        }
        return api?.detail ?? (overDrive ? DriveLink.notAnswering : "Your library isn't answering. Check it's on and connected.")
    }

    /// The turns that were answered, the last few, for a library that doesn't keep the chat.
    private func history() -> [AskHistoryTurn] {
        turns.filter { $0.state == .done && !$0.answer.isEmpty }.suffix(6).map {
            AskHistoryTurn(question: $0.question, answer: String($0.answer.prefix(4000)), sources: $0.askSources)
        }
    }

    /// A question that failed, asked again in its own place.
    func retry(_ turn: AskTurn, scope: AskScope, label: String?, api: APIClient) {
        guard !busy else { return }
        turns.removeAll { $0.id == turn.id }
        send(turn.question, scope: turn.asked ?? scope, label: turn.scope ?? label, api: api)
    }

    // MARK: chats

    /// A new chat: nothing asked, and the next question starts another kept chat (this one stays in Chats).
    func startOver() {
        stop()
        turns = []
        chatID = nil
        save()
    }

    /// A kept chat opened to carry on: its questions and answers as they were.
    func open(_ chat: Chat) {
        stop()
        turns = Self.turns(of: chat)
        chatID = chat.id
        keeps = true
        save()
    }

    /// A kept chat's messages as turns: each question with the answer after it.
    static func turns(of chat: Chat) -> [AskTurn] {
        var out: [AskTurn] = []
        let m = chat.messages
        var i = 0
        while i + 1 < m.count {
            guard m[i].role == "user", m[i + 1].role == "assistant" else { i += 1; continue }
            let a = m[i + 1]
            var t = AskTurn(question: m[i].text)
            if a.failed == true {
                t.state = .failed
                t.problem = a.text
            } else {
                t.state = .done
                t.answer = a.text
                t.sources = AskTurn.merged(a.sources ?? [])
                t.engine = a.engineName
                t.stopped = a.stopped == true ? true : nil
            }
            out.append(t)
            i += 2
        }
        return out
    }

    /// The chat's name: its first question, as the library names it.
    var title: String? { turns.first?.question }

    #if DEBUG
    /// An answer partway through being written, for `-ask-waiting -ask-stage writing`.
    static let sampleWriting = "Pick **u** with LIATE, the order from the lecture:\n\n1. **L**ogarithms\n2. **I**nverse trig\n3. **A**lgebraic, like x or x²\n4. **T**rig"
    #endif
}
