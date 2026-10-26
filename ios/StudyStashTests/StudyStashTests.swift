import Foundation
import Testing
@testable import StudyStash

// MARK: - finding the library

@Suite struct LibraryAddressTests {
    @Test func qrCodeGivesHttpsFirstThenTheTailscaleIP() {
        let qr = "http://100.64.0.1:8787/app/?https=https%3A%2F%2Fmac.tail1234.ts.net%3A8443%2Fapp%2F"
        #expect(LibraryAddress.candidates(from: qr).map(\.absoluteString) == [
            "https://mac.tail1234.ts.net:8443", "http://100.64.0.1:8787",
        ])
    }

    @Test func plainAddressAloneIsItsRoot() {
        #expect(LibraryAddress.candidates(from: " http://100.87.191.40:8787/app/ ").map(\.absoluteString) == ["http://100.87.191.40:8787"])
    }

    @Test func bareHostGuessesTheScheme() {
        #expect(LibraryAddress.candidates(from: "mac.tail1234.ts.net:8443").map(\.absoluteString) == ["https://mac.tail1234.ts.net:8443"])
        #expect(LibraryAddress.candidates(from: "100.64.0.1:8787").map(\.absoluteString) == ["http://100.64.0.1:8787"])
    }

    @Test func nonsenseFindsNothing() {
        #expect(LibraryAddress.candidates(from: "").isEmpty)
        #expect(LibraryAddress.candidates(from: "ftp://example.com").isEmpty)
    }

    @Test func qrCodeWithItsCodeGivesTheSameAddressesAndTheCode() {
        let qr = "http://100.64.0.1:8787/app/?https=https%3A%2F%2Fmac.tail1234.ts.net%3A8443%2Fapp%2F#code=042917"
        #expect(LibraryAddress.candidates(from: qr).map(\.absoluteString) == [
            "https://mac.tail1234.ts.net:8443", "http://100.64.0.1:8787",
        ])
        #expect(LibraryAddress.code(from: qr) == "042917")
        #expect(LibraryAddress.code(from: "http://100.64.0.1:8787/app/?code=042917") == "042917")
        #expect(LibraryAddress.code(from: "100.64.0.1:8787#code=042917") == "042917")
        #expect(LibraryAddress.candidates(from: "100.64.0.1#code=042917").map(\.absoluteString) == ["http://100.64.0.1"])
        #expect(LibraryAddress.code(from: "mac.tail1234.ts.net:8443/app/#code=042%20917") == "042917")
    }

    @Test func noCodeOrNotSixDigitsAsksForIt() {
        #expect(LibraryAddress.code(from: "http://100.64.0.1:8787/app/?https=https%3A%2F%2Fmac.tail1234.ts.net%3A8443%2Fapp%2F") == nil)
        #expect(LibraryAddress.code(from: "mac.tail1234.ts.net:8443") == nil)
        #expect(LibraryAddress.code(from: "http://100.64.0.1:8787/app/#code=04291") == nil)
        #expect(LibraryAddress.code(from: "http://100.64.0.1:8787/app/#code=abcdef") == nil)
        #expect(LibraryAddress.code(from: "") == nil)
    }
}

// MARK: - pairing with the code the QR code brought

@MainActor @Suite struct ScanPairingTests {
    let base = URL(string: "http://100.64.0.1:8787")!
    let library = Me.Library(name: "Joey's library", version: "0.17.2")
    func joined(needsUses: Bool) -> Joined { Joined(base: base, library: library, needsUses: needsUses) }

    @Test func aCodeFromTheScanPairsAndSkipsTheCodePage() async {
        var sent: String?
        let (page, joined) = await ScanPairing.next(base: base, library: library, code: "042917") { code in
            sent = code
            return self.joined(needsUses: false)
        }
        #expect(sent == "042917")
        #expect(page == .done)
        #expect(joined?.library == library)
        let (first, _) = await ScanPairing.next(base: base, library: library, code: "042917") { _ in self.joined(needsUses: true) }
        #expect(first == .uses)
    }

    @Test func aRefusedCodeOpensTheCodePageWithTheLibrarysWords() async {
        let words = "That code isn't right, or it's more than ten minutes old. Make a new one in Egghead Notes' Settings."
        let (page, joined) = await ScanPairing.next(base: base, library: library, code: "042917") { _ in
            throw APIError(status: 401, detail: words)
        }
        #expect(page == .code(base: base, library: library, problem: words))
        #expect(joined == nil)
    }

    @Test func noCodeIsTheCodePageAsBefore() async {
        var asked = false
        let (page, _) = await ScanPairing.next(base: base, library: library, code: nil) { _ in
            asked = true
            return self.joined(needsUses: false)
        }
        #expect(!asked)
        #expect(page == .code(base: base, library: library))
    }
}

// MARK: - the client

@Suite struct APIClientTests {
    let api = APIClient(base: URL(string: "http://100.64.0.1:8787")!)

    @Test func urlsKeepTheQueryAndDropEmptyValues() {
        #expect(api.url("/lectures", ["class": "CS 101", "limit": "5", "before": nil, "x": ""]).absoluteString
            == "http://100.64.0.1:8787/api/v2/lectures?class=CS%20101&limit=5")
    }

    @Test func pathSegmentsAreEscaped() {
        #expect(APIClient.segment("../../state.db") == "..%2F..%2Fstate.db")
        #expect(APIClient.segment("C# & Why?") == "C%23%20%26%20Why%3F")
    }

    @Test func errorsSayWhatHappened() {
        #expect(APIError.words(for: 401).contains("pairing"))
        #expect(APIError.words(for: 503).contains("problem"))
        #expect(APIError.unreachableLibrary.unreachable)
    }
}

// MARK: - reading what the library sends

@Suite struct DecodingTests {
    func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func libraryOverview() throws {
        let o = try decode("""
        {"name":"Sam's library","version":"0.16.15","classes":[{"name":"Data Mining","lectures":11,"color":3,"description":"","code":"CSCI 4230","aliases":["CSCI 4230"]}],
         "unsorted":1,"writing":0,"ask":true,"notes_model":"Claude","laptops":[],"gone":[]}
        """, as: LibraryOverview.self)
        #expect(o.classes.first?.code == "CSCI 4230")
        #expect(o.notesModel == "Claude")
    }

    @Test func lectureSummaryWithNulls() throws {
        let l = try decode("""
        [{"id":"rec-1","title":null,"class":null,"date":"2026-10-15","seconds":null,"owner":null,"status":"working","summary":"","topics":[],"has_transcript":true}]
        """, as: [LectureSummary].self)
        #expect(l[0].displayTitle == "Untitled lecture")
        #expect(l[0].isWriting)
        #expect(l[0].hasTranscript)
    }

    @Test func dueList() throws {
        let d = try decode("""
        {"synced":"2026-10-15T20:48:25.1375340-07:00","to_hand_in":2,"next":null,"groups":[{"key":"week","label":"This week","items":[
          {"class":"Data Mining","id":42,"name":"HW 3","kind":"assignment","due":"2026-10-18T23:59","due_at":"2026-10-19T06:59:59Z","points":100,
           "status":"open","label":"To do","score":null,"grade":"","score_text":"","late":false,"missing":false,"excused":false,"submitted":null,
           "graded_at":null,"marked_done":null,"url":"https://canvas.example.edu/courses/1/assignments/42","folder":null}]}]}
        """, as: DueList.self)
        #expect(d.toHandIn == 2)
        #expect(d.groups[0].items[0].points == 100)
    }

    @Test func askEventsOneALine() throws {
        guard case .text("Hel") = try decode(#"{"kind":"text","text":"Hel"}"#, as: AskEvent.self) else { Issue.record("text"); return }
        guard case let .error(status, detail) = try decode(#"{"kind":"error","status":503,"detail":"No AI"}"#, as: AskEvent.self) else {
            Issue.record("error"); return
        }
        #expect(status == 503 && detail == "No AI")
        let done = try decode("""
        {"kind":"done","reply":{"answer":"A table.","sources":[{"id":"l1","title":"LR","class":"Compilers","date":"2026-10-14","at":null,"section":"Summary"}],
         "engine":"claude","engine_name":"Claude","asked":"claude","asked_name":"Claude","fell_back":false,"why":""}}
        """, as: AskEvent.self)
        guard case .done(let reply) = done else { Issue.record("done"); return }
        #expect(reply.sources.count == 1)
        // A kept chat's id comes first: an answer, not an error.
        guard case .chat("261024-101500-a1b2c3") = try decode(#"{"kind":"chat","id":"261024-101500-a1b2c3"}"#, as: AskEvent.self) else {
            Issue.record("chat"); return
        }
    }

    /// Which AI answers Ask: the library's `GET /ai` says it by its id ("codex" is ChatGPT); an answer by its name.
    @Test func theAnsweringAIIsReadFromTheLibrary() throws {
        let s = try decode("""
        {"provider":"claude","jobs":{"notes":{"provider":"claude","model":"","own":false},"ask":{"provider":"codex","model":"gpt-5","own":true}},
         "providers":[{"id":"claude","name":"Claude","installed":true,"site":"","test":"","models":[]}]}
        """, as: AISettings.self)
        #expect(AskEngine(id: s.jobs?["ask"]?.provider) == .chatgpt)
        #expect(AskEngine(id: "gemini") == .gemini && AskEngine(id: "ollama") == .ollama && AskEngine(id: "something") == nil)
        #expect(AskEngine(name: "Local model (Ollama)") == .ollama && AskEngine(name: "Claude") == .claude)
    }

    /// A chat picked from Chats opens as it was: each question with its answer and sources, a failed one with why.
    @Test @MainActor func aKeptChatOpensAsItsTurns() throws {
        let chat = try decode("""
        {"id":"c1","title":"Limits","class":"Calculus II","lecture":"","updated":"2026-10-24T09:00:00.0000000-07:00","kind":"ask","scope":"home","turns":2,
         "messages":[{"role":"user","text":"What's a limit?","when":"","tools":[]},
                     {"role":"assistant","text":"Where f goes **near** a point.","when":"","tools":[],"failed":false,
                      "sources":[{"id":"l1","title":"Limits","class":"Calculus II","date":"2026-10-20","at":95,"section":""}],"engine":"claude","engine_name":"Claude","stopped":false},
                     {"role":"user","text":"And continuity?","when":"","tools":[]},
                     {"role":"assistant","text":"Claude didn't answer.","when":"","tools":[],"failed":true}]}
        """, as: Chat.self)
        let turns = AskConversation.turns(of: chat)
        #expect(turns.map(\.question) == ["What's a limit?", "And continuity?"])
        #expect(turns[0].state == .done && turns[0].engine == "Claude" && turns[0].sources.first?.times == [95])
        #expect(turns[1].state == .failed && turns[1].problem == "Claude didn't answer." && turns[1].answer.isEmpty)
        #expect(ChatSummary(id: "c1", title: "", class: "", lecture: "", updated: "", kind: "ask").isAsk)
    }

    @Test func modelsRoundTripThroughTheCache() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = ResponseCache(folder: folder)
        let o = LibraryOverview(name: "L", version: "1", classes: [ClassInfo(name: "C", lectures: 1, color: 2)], unsorted: 0, writing: 0, ask: true)
        cache.write("library", o)
        #expect(cache.read("library", as: LibraryOverview.self)?.classes.first?.color == 2)
        cache.clear()
        #expect(cache.read("library", as: LibraryOverview.self) == nil)
    }
}

// MARK: - words

@Suite struct FormatTests {
    let now = Format.parse("2026-10-15T12:00:00")!

    @Test func parsesTheLibrarysDates() {
        #expect(Format.parse("2026-09-23") != nil)
        #expect(Format.parse("2026-10-02T23:59") != nil)
        #expect(Format.parse("2026-10-15T20:48:25.1375340-07:00") != nil)
        #expect(Format.parse("2026-10-19T06:59:59Z") != nil)
        #expect(Format.parse("nope") == nil)
    }

    @Test func durations() {
        #expect(Format.duration(nil) == "")
        #expect(Format.duration(30) == "under a minute")
        #expect(Format.duration(48 * 60) == "48 min")
        #expect(Format.duration(72 * 60) == "1 h 12 min")
        #expect(Format.duration(120 * 60) == "2 h 00 min")
    }

    @Test func daysAndTimesInTheDesktopsWords() {
        #expect(Format.day(Format.parse("2026-10-15T09:30")!, now: now) == "Today")
        #expect(Format.day(Format.parse("2026-10-14")!, now: now) == "Yesterday")
        #expect(Format.day(Format.parse("2026-10-07")!, now: now) == "Wed 7 Oct")
        #expect(Format.day(Format.parse("2025-10-07")!, now: now) == "7 Oct 2025")
        #expect(Format.time(Format.parse("2026-10-15T21:05")!) == "9:05 PM")
        #expect(Format.noteWhen("2026-10-12T09:30:00", 52 * 60, now: now) == "Monday 12 October at 9:30 AM, 52 min")
    }

    @Test func dueWhenIsTheDayForMidnight() {
        #expect(Format.dueWhen("2026-10-15", now: now) == "Today")
        #expect(Format.dueWhen("2026-10-16T00:00", now: now) == "Tomorrow")
        #expect(Format.dueWhen("2026-10-16T09:00", now: now).hasPrefix("Tomorrow, "))
        #expect(Format.dueWhen(nil, now: now) == "No due date")
    }

    @Test func lectureGroups() {
        #expect(Format.lectureGroup("2026-10-14", now: now) == "This week")
        #expect(Format.lectureGroup("2026-10-07", now: now) == "Last week")
        #expect(Format.lectureGroup(nil, now: now) == "Undated")
        #expect(Format.lectureGroup("2025-05-01", now: now).contains("2025"))
    }

    @Test func groupingKeepsOrder() {
        let g = Format.grouped([1, 2, 4, 5, 7]) { $0 < 3 ? "a" : $0 < 6 ? "b" : "c" }
        #expect(g.map(\.label) == ["a", "b", "c"])
        #expect(g[1].items == [4, 5])
    }

    @Test func sizesAndClocks() {
        #expect(Format.fileSize(12) == "12 bytes")
        #expect(Format.fileSize(830 * 1024) == "830 KB")
        #expect(Format.fileSize(Int(2.4 * 1024 * 1024)) == "2.4 MB")
        #expect(Format.clock(245) == "4:05")
        #expect(Format.clock(3723) == "1:02:03")
    }
}

// MARK: - classes, transcripts, answers

@Suite struct TextTests {
    @Test func classNamesMatchTheWayCanvasWritesThem() {
        #expect(ClassMatch.normalized("Theory Of Computation & Compilers") == "theory of computation and compilers")
        let index = AppModel.index([ClassInfo(name: "Theory of Computation and Compilers", lectures: 1, color: 4, code: "CSCI 4150")])
        #expect(index["theory of computation and compilers"] == 4)
        #expect(index["csci 4150"] == 4)
    }

    @Test func transcriptLines() {
        let lines = TranscriptView.lines("[00:05] Hello there\n[1:02:03] Later on\nnot a line\n[00:09]")
        #expect(lines.map(\.stamp) == ["00:05", "1:02:03"])
        #expect(lines[1].words == "Later on")
    }

    @Test func markdownBlocks() {
        let blocks = MarkdownText.blocks("## Heading\nSome **bold**\ntext.\n\n- one\n  - two\n1. first")
        #expect(blocks.count == 5)
        if case .heading("Heading") = blocks[0] {} else { Issue.record("heading") }
        if case .paragraph("Some **bold** text.") = blocks[1] {} else { Issue.record("paragraph") }
        if case .bullet("two", 1) = blocks[3] {} else { Issue.record("nested bullet") }
        if case .numbered(1, "first") = blocks[4] {} else { Issue.record("numbered") }
    }

    @Test func askSourcesOneALecture() {
        let s = AskTurn.merged([
            AskSource(id: "l1", title: "LR", class: nil, date: nil, at: nil, section: "Summary"),
            AskSource(id: "l1", title: "LR", class: nil, date: nil, at: nil, section: "Tables"),
            AskSource(id: "l2", title: "LL", class: nil, date: nil, at: nil, section: "Summary"),
        ])
        #expect(s.map(\.id) == ["l1", "l2"])
    }

    @Test func aClassHasTheDesktopsHighlighter() {
        // Skin.ClassHues: the order classes take them by their place in the library.
        #expect((0..<9).map { Highlighter(classIndex: $0) } == [.yellow, .green, .orange, .pink, .blue, .teal, .violet, .lime, .yellow])
    }
}

// MARK: - recordings

@Suite struct RecordingTests {
    @Test func idsAreWhatTheLibraryTakes() {
        let id = Recording.newID(Format.parse("2026-10-15T09:15:00")!)
        #expect(id.wholeMatch(of: /phone-20261015-091500-[0-9a-f]{6}/) != nil)
        #expect(Recording.newID() != Recording.newID())
    }

    @Test func transcriptLinesAsTheLibraryReadsThem() {
        var r = Recording(id: "phone-x", started: .now)
        r.segments = [.init(start: 5, text: " Hello there "), .init(start: 65, text: ""), .init(start: 3723, text: "Much later")]
        #expect(r.transcript == "[00:05] Hello there\n[1:02:03] Much later")
    }

    @Test func payloadKeepsTypedTitleAndNotesOnly() throws {
        var r = Recording(id: "phone-20261015-091500-a1b2c3", started: Format.parse("2026-10-15T09:15:00")!, className: "Compilers")
        r.segments = [.init(start: 0, text: "Hi")]
        r.notes = "  \n"
        let p = r.payload
        #expect(p.title == nil && p.title_typed == false && p.notes == nil && p.class == "Compilers")
        #expect(p.date.hasPrefix("2026-10-15T09:15:00"))
        #expect(r.displayTitle.hasPrefix("Compilers, "))
        r.title = "Midterm review"
        r.titleTyped = true
        r.notes = "- ask about LR(1)"
        #expect(r.payload.title == "Midterm review" && r.payload.title_typed && r.payload.notes == "- ask about LR(1)")
    }

    @Test @MainActor func storeKeepsRecordingsAndMarksInterruptedOnesWaiting() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = RecordingStore(folder: folder)
        store.save(Recording(id: "phone-20261015-091500-a1b2c3", started: .now))
        let again = RecordingStore(folder: folder)
        #expect(again.recordings.count == 1)
        #expect(again.recordings[0].state == .waiting)
        again.delete(again.recordings[0])
        #expect(RecordingStore(folder: folder).recordings.isEmpty)
    }

    @Test @MainActor func calendarEventsFindTheirClass() {
        let app = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        app.learn(LibraryOverview(name: "L", version: "1", classes: [
            ClassInfo(name: "Machine Learning", lectures: 1, color: 0),
            ClassInfo(name: "Theory of Computation and Compilers", lectures: 1, color: 1, code: "CSCI 4150"),
        ], unsorted: 0, writing: 0, ask: true))
        func event(_ title: String) -> UpcomingEvent { UpcomingEvent(id: "e", title: title, start: "", end: "", allDay: false) }
        #expect(app.className(ofEvent: event("Machine & Deep Learning")) == "Machine Learning")
        #expect(app.className(ofEvent: event("Theory Of Computation & Compilers")) == "Theory of Computation and Compilers")
        #expect(app.className(ofEvent: event("CSCI 4150 Lab")) == "Theory of Computation and Compilers")
        #expect(app.className(ofEvent: event("Lunch")) == nil)
    }
}

@Suite struct StudyDeckTests {
    @Test func aDeckIsReadFromAnAnswerWrappedInProse() throws {
        let text = """
        Here you go!
        ```json
        {"cards":[{"front":"LR(1)?","back":"1 token of lookahead"},{"front":"","back":"dropped"}],
         "quiz":[{"question":"Shift does?","choices":["push","pop"],"answer":0,"why":"It pushes."},{"question":"bad","choices":["a"],"answer":3}]}
        ```
        """
        let d = try #require(StudyDeck.parse(text))
        #expect(d.cards.count == 1)
        #expect(d.quiz.count == 1 && d.quiz[0].why == "It pushes.")
        #expect(StudyDeck.parse("No JSON here") == nil)
    }
}
