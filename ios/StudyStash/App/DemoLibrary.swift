import Foundation
import UIKit
import Synchronization

/// A library that lives in the app: made-up classes, lectures with notes, due work, a calendar and answers, for
/// trying Study Stash without a computer (and for App Review). Every /api/v2 request to `demo.studystash.app` is
/// answered here, by a URLProtocol on the app's session.
final class DemoLibrary: URLProtocol, @unchecked Sendable {
    static let host = "demo.studystash.app"
    static let base = URL(string: "https://\(host)")!

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, type, body) = Self.answer(path: url.path(), query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [],
                                               method: request.httpMethod ?? "GET", body: Self.body(of: request))
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func body(of r: URLRequest) -> Data? {
        if let d = r.httpBody { return d }
        guard let s = r.httpBodyStream else { return nil }
        s.open()
        defer { s.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
        return data
    }

    // MARK: answers

    static func json(_ o: Any, _ status: Int = 200) -> (Int, String, Data) {
        (status, "application/json", (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8))
    }

    static func answer(path: String, query: [URLQueryItem], method: String, body: Data?) -> (Int, String, Data) {
        let q = Dictionary(query.compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a })
        let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let lecturePath = path.hasPrefix("/api/v2/lectures/") ? String(path.dropFirst("/api/v2/lectures/".count)) : nil
        switch (method, path) {
        case ("GET", "/api/v2/me"):
            return json(["paired": true, "library": ["name": "Demo library", "version": "demo"], "device": ["id": "demo", "name": "This phone", "added": iso(-86_400 * 3)]])
        case ("GET", "/api/v2/library"):
            return json(overview)
        case ("GET", "/api/v2/lectures"):
            let cls = q["class"]
            return json(lectures.filter { cls == nil || $0.cls == cls }.map(\.summary))
        case ("GET", _) where lecturePath?.hasSuffix("/rendered") == true:
            let id = String(lecturePath!.dropLast("/rendered".count))
            guard let l = lectures.first(where: { $0.id == id }) else { return json(["detail": "no such lecture"], 404) }
            return json(["id": l.id, "title": l.title, "class": l.cls, "date": l.date, "html": l.html + (DemoPhotos.on && id == DemoPhotos.lecture ? DemoPhotos.embed : "")])
        case ("GET", _) where lecturePath != nil:
            guard let l = lectures.first(where: { $0.id == lecturePath }) else { return json(["detail": "no such lecture"], 404) }
            return json(l.full)
        // Move to, Rename, Delete and Undo, Write again: kept while the app runs.
        case ("POST", _) where lecturePath?.hasSuffix("/class") == true:
            let id = String(lecturePath!.dropLast("/class".count))
            changes.withLock { $0.moved[id] = sent["class"] as? String ?? "Unsorted" }
            return lectures.first { $0.id == id }.map { json($0.full) } ?? json(["detail": "no such lecture"], 404)
        case ("POST", _) where lecturePath?.hasSuffix("/title") == true:
            let id = String(lecturePath!.dropLast("/title".count))
            changes.withLock { $0.renamed[id] = sent["title"] as? String ?? "" }
            return lectures.first { $0.id == id }.map { json($0.full) } ?? json(["detail": "no such lecture"], 404)
        case ("POST", _) where lecturePath?.hasSuffix("/restore") == true:
            let id = String(lecturePath!.dropLast("/restore".count))
            changes.withLock { _ = $0.trashed.remove(id) }
            return lectures.first { $0.id == id }.map { json($0.full) } ?? json(["detail": "It's no longer in the trash, so it can't come back."], 404)
        case ("POST", _) where lecturePath?.hasSuffix("/rewrite") == true:
            return json(["id": String(lecturePath!.dropLast("/rewrite".count)), "status": "queued"])
        case ("DELETE", _) where lecturePath != nil:
            changes.withLock { _ = $0.trashed.insert(lecturePath!) }
            return json(["deleted": lecturePath!, "undo_minutes": 10])
        case ("GET", "/api/v2/search"):
            return search(q["q"] ?? "", class: q["class"])
        case ("GET", "/api/v2/canvas/due"):
            return json(["synced": iso(-1800), "to_hand_in": dueItems.filter { $0.group != "handed_in" }.count, "next": NSNull(), "groups": dueGroups])
        case ("GET", "/api/v2/canvas/assignment"):
            guard let d = dueItems.first(where: { String($0.id) == q["id"] }) else { return json(["detail": "no such assignment"], 404) }
            return json(d.detail)
        case ("GET", "/api/v2/calendar/upcoming"):
            return json(["updated": iso(-300), "events": [
                // On now, in a few minutes: Up next says "In 9 minutes", and the Record bar "Record Calculus II".
                eventIn("e0", "Calculus II", minutes: 9, length: 50, "Science Hall 204"),
                event("e1", "Intro to Psychology", 1, 11, 75, "Lecture Hall B"),
                event("e2", "Calculus II", 2, 9, 50, "Science Hall 204"),
                event("e3", "Organic Chemistry Lab", 2, 13, 170, "Chem 110"),
            ]])
        case ("GET", "/api/v2/attachments"):
            return json(["attachments": DemoPhotos.on && q["lecture"] == DemoPhotos.lecture ? DemoPhotos.attachments : []])
        case ("GET", _) where path.hasPrefix("/api/v2/attachments/demo-board-") && path.hasSuffix("/raw"):
            return (200, "image/jpeg", DemoPhotos.picture(path))
        case ("GET", "/api/v2/chats"):
            return json([])
        case ("POST", "/api/v2/ai/ask"):
            return ask(sent["question"] as? String ?? "", lecture: sent["lecture"] as? String)
        case ("POST", "/api/v2/ai/warm"):
            return json([:])
        case ("POST", "/api/v2/lectures"):
            // A recording sent from this phone: "being written" for half a minute, then written up round what was typed.
            guard let id = sent["id"] as? String else { return json(["detail": "a lecture needs an id"], 400) }
            changes.withLock { $0.received[id] = (body ?? Data(), .now) }
            return json(["id": id, "status": "queued", "class_name": sent["class"] ?? NSNull(), "has_transcript": true])
        case ("POST", "/api/v2/attachments"):
            return json(["attachments": []])
        case ("POST", "/api/v2/uses"), ("POST", "/api/v2/classes/alias"):
            return json(overview)
        case ("GET", "/api/v2/voice-memos"):
            return json(["memos": []])
        // Setup's pictures and tests: 123456 pairs, any other code is refused in the library's words.
        case ("POST", "/api/v2/devices/pair"):
            guard sent["code"] as? String == "123456" else {
                return json(["error": "That code isn't right, or it's more than ten minutes old. Make a new one in Study Stash's Settings."], 401)
            }
            return json(["device": ["id": "demo", "name": sent["name"] as? String ?? "This phone", "added": iso(0)]])
        default:
            return json(["detail": "The demo library doesn't do that."], 404)
        }
    }

    /// What's changed in the demo while the app runs: lectures moved, renamed, deleted, and ones the phone sent.
    struct Changes: Sendable {
        var moved: [String: String] = [:]
        var renamed: [String: String] = [:]
        var trashed: Set<String> = []
        var received: [String: (body: Data, at: Date)] = [:]
    }
    static let changes = Mutex(Changes())

    /// The search: lectures whose words match, and passages from what was said, at the second it was said.
    static func search(_ query: String, class cls: String?) -> (Int, String, Data) {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { $0.count > 1 }
        let pool = lectures.filter { cls == nil || $0.cls == cls }
        let hits = pool.filter { l in
            let text = (l.title + " " + l.topics.joined(separator: " ") + " " + l.transcript + " " + l.summaryText).lowercased()
            return words.contains { text.contains($0) }
        }
        var passages: [[String: Any]] = []
        for l in hits {
            for line in l.transcript.split(separator: "\n") where words.contains(where: { line.lowercased().contains($0) }) {
                guard let m = line.firstMatch(of: /^\[(\d+):(\d{2})\]\s*(.*)$/) else { continue }
                let at = (Int(m.1) ?? 0) * 60 + (Int(m.2) ?? 0)
                passages.append(["id": l.id, "title": l.title, "class": l.cls, "date": l.date, "kind": "transcript", "section": "", "at": at, "text": String(m.3)])
            }
        }
        let classes = (overview["classes"] as? [[String: Any]] ?? []).filter { c in words.contains { (c["name"] as? String ?? "").lowercased().contains($0) } }
        return json(["query": query, "lectures": hits.map(\.summary), "classes": classes, "passages": Array(passages.prefix(8))])
    }

    // MARK: the made-up library

    struct DemoLecture {
        var id, title, cls: String
        var daysAgo: Int
        /// When it started that day ("9:00 AM").
        var hour = 9
        var minutes: Int
        var topics: [String]
        var summaryText: String
        var html: String
        var transcript: String
        /// "done", or "working" while its notes are being written.
        var status = "done"
        /// What the student typed while it recorded (the notes mark those lines ==like this==).
        var typed = ""
        /// Its exact start, for one sent from this phone.
        var started: String?

        var date: String { started ?? DemoLibrary.day(-daysAgo, at: hour) }
        var summary: [String: Any] {
            ["id": id, "title": title, "class": cls, "date": date, "seconds": minutes * 60, "owner": "You", "status": status,
             "summary": summaryText, "topics": topics, "has_transcript": true]
        }
        var full: [String: Any] {
            var f = summary
            f["notes"] = html
            f["typed"] = typed
            f["transcript"] = transcript
            f["error"] = NSNull()
            return f
        }
    }

    /// The lectures as they are now: the made-up ones and any sent from this phone, newest first, with the moves,
    /// renames and deletes made here.
    static var lectures: [DemoLecture] {
        let c = changes.withLock { $0 }
        let sentHere = c.received.map { id, r in sentFromPhone(id, r.body, r.at) }
        return (sentHere + made).filter { !c.trashed.contains($0.id) }.map { l in
            var l = l
            if let to = c.moved[l.id] { l.cls = to }
            if let t = c.renamed[l.id] { l.title = t }
            return l
        }
    }

    /// One sent from this phone: being written for half a minute, then its notes, its typed lines kept as its own.
    static func sentFromPhone(_ id: String, _ body: Data, _ at: Date) -> DemoLecture {
        let p = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let typed = p["notes"] as? String ?? ""
        let transcript = p["transcript"] as? String ?? ""
        let done = Date.now.timeIntervalSince(at) > 30
        let lines = typed.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let said = transcript.split(separator: "\n").prefix(3).map { $0.replacing(/^\[[\d:]+\]\s*/, with: "") }
        let html = done ? "<h2>Summary</h2><p>\(said.joined(separator: " "))</p>"
            + (lines.isEmpty ? "" : "<h2>Your notes</h2><ul>" + lines.map { "<li>==\($0)== Said in class around it: \(said.first ?? "")</li>" }.joined() + "</ul>") : ""
        let title = (p["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (done ? "Bottom-up parsing and LR tables" : "")
        return DemoLecture(id: id, title: title, cls: p["class"] as? String ?? "Unsorted", daysAgo: 0,
                           minutes: Int((p["seconds"] as? Double ?? 60) / 60), topics: done ? ["LR parsing", "Shift and reduce"] : [],
                           summaryText: done ? "An LR parser reads left to right and builds a rightmost derivation in reverse." : "",
                           html: html, transcript: transcript, status: done ? "done" : "working", typed: typed, started: p["date"] as? String)
    }

    static let classes = ["Calculus II", "Intro to Psychology", "Organic Chemistry"]
    /// Each one's highlighter by its place, as on the desktop: yellow, green, orange.

    static var overview: [String: Any] {
        var o = baseOverview
        #if DEBUG
        // `-recording-now`: the laptop is recording a Calculus II lecture (the banner on Home).
        if DebugLaunch.flag("-recording-now") {
            o["recording_now"] = ["id": "rec-demo-now", "class": "Calculus II", "title": "Calculus II", "started": ISO8601DateFormatter().string(from: .now.addingTimeInterval(-12 * 60))]
        }
        #endif
        return o
    }

    static var baseOverview: [String: Any] {
        ["name": "Demo library", "version": "demo", "unsorted": lectures.filter { $0.cls == "Unsorted" }.count, "writing": lectures.filter { $0.status != "done" }.count, "ask": true, "notes_model": "Claude", "uses": ["student"], "for_school": true,
         "classes": classes.enumerated().map { i, c in
             ["name": c, "lectures": lectures.filter { $0.cls == c }.count, "color": i, "description": "", "group": "", "code": ["MATH 162", "PSYC 101", "CHEM 231"][i], "aliases": []] as [String: Any]
         }]
    }

    static let made: [DemoLecture] = [
        // Being written: today's, its notes not in yet, what was typed and said there to read.
        DemoLecture(id: "demo-psych-sleep", title: "", cls: "Intro to Psychology", daysAgo: 0, hour: 8, minutes: 48,
                    topics: [], summaryText: "", html: "",
                    transcript: "[00:00] Okay, sleep. Why do we spend a third of our lives doing it?\n[06:30] There are four stages, and REM is where most dreaming happens.\n[19:45] In REM your muscles are mostly paralysed, which is why you don't act dreams out.",
                    status: "working", typed: "Sleep stages: N1, N2, N3, REM\nREM = dreams, muscles paralysed"),
        DemoLecture(id: "demo-calc-ibp", title: "Integration by Parts and the LIATE Rule", cls: "Calculus II", daysAgo: 1, minutes: 52,
                    topics: ["Integration by parts", "LIATE", "Tabular method"],
                    summaryText: "How to integrate products by reversing the product rule, and how to choose u.",
                    html: """
                    <h2>Summary</h2><p>Integration by parts turns the integral of a product into an easier one by running the product rule backwards. Most of the skill is choosing which factor to call <em>u</em>.</p>
                    <h2>Key points</h2><ul><li>==Product rule backwards== The formula: <span class="math display" data-tex="\\int u\\,dv = uv - \\int v\\,du">∫ u dv = uv − ∫ v du</span></li><li>==LIATE picks u== Logarithmic, Inverse trig, Algebraic, Trig, Exponential: whichever comes first.</li><li>==Tabular method for polynomials== When <em>u</em> is a polynomial, the tabular method saves time.</li></ul>
                    <h2>Details and examples</h2><p>Example: <span class="math" data-tex="\\int x e^{x}\\,dx">∫ x eˣ dx</span>. Let <span class="math" data-tex="u = x">u = x</span>, <span class="math" data-tex="dv = e^x dx">dv = eˣ dx</span>, so <span class="math display" data-tex="\\int x e^x\\,dx = x e^x - \\int e^x\\,dx = e^x(x-1) + C">= eˣ(x − 1) + C</span></p>
                    <table><tr><th>Sign</th><th>u and its derivatives</th><th>dv and its integrals</th></tr><tr><td>+</td><td>x²</td><td>eˣ</td></tr><tr><td>−</td><td>2x</td><td>eˣ</td></tr><tr><td>+</td><td>2</td><td>eˣ</td></tr></table>
                    <h2>Questions to review</h2><ol><li>Why does LIATE put logarithms first?</li><li>Evaluate ∫ x cos x dx.</li><li>When does integration by parts loop back to the original integral, and how do you finish?</li></ol>
                    """,
                    transcript: "[00:00] Alright, let's get going. Today is integration by parts.\n[00:12] It's really just the product rule run backwards.\n[03:40] So how do you choose u? There's a rule of thumb, LIATE.\n[09:15] Let's do x e to the x together.\n[21:30] When u is a polynomial, the tabular method is a lifesaver.",
                    typed: "Product rule backwards\nLIATE picks u\nTabular method for polynomials"),
        DemoLecture(id: "demo-psych-memory", title: "Memory: Encoding, Storage and Retrieval", cls: "Intro to Psychology", daysAgo: 2, hour: 11, minutes: 74,
                    topics: ["Working memory", "Levels of processing", "Misinformation effect"],
                    summaryText: "The three stages of memory, why deeper processing sticks, and how memories get rewritten.",
                    html: """
                    <h2>Summary</h2><p>Memory works in three stages: encoding, storage and retrieval. What we notice and how deeply we process it decides what lasts, and recall is a reconstruction, not a replay.</p>
                    <h2>Key points</h2><ul><li><strong>Working memory</strong> holds about 4 chunks for a few seconds; rehearsal keeps them there.</li><li><strong>Levels of processing</strong>: meaning-based (semantic) encoding beats sound or appearance.</li><li><strong>The misinformation effect</strong>: questions asked after an event change what people remember (Loftus &amp; Palmer, 1974).</li></ul>
                    <h2>Definitions</h2><ul><li><strong>Encoding</strong>: turning experience into a form memory can store.</li><li><strong>Retrieval cue</strong>: anything that helps bring a memory back.</li></ul>
                    <h2>Announcements</h2><ul><li>Essay on eyewitness testimony due in ten days.</li></ul>
                    """,
                    transcript: "[00:00] Today: how memory actually works.\n[05:20] Working memory holds about four chunks.\n[31:10] Loftus and Palmer — smashed versus hit.\n[70:02] The essay is due in ten days."),
        DemoLecture(id: "demo-unsorted-study-group", title: "", cls: "Unsorted", daysAgo: 3, hour: 16, minutes: 18,
                    topics: ["Exam plan", "Practice problems"],
                    summaryText: "A study group planning the week before the calculus midterm: who takes which practice set, and when to meet.",
                    html: "<h2>Summary</h2><p>Planning for the calculus midterm: split the practice problems, meet Thursday to go through integration by parts.</p>",
                    transcript: "[00:00] Okay, so the midterm is next Friday.\n[02:10] I'll take the integration by parts set.\n[11:45] Thursday at four in the library?"),
        DemoLecture(id: "demo-chem-sn", title: "SN1 vs SN2: Substitution Mechanisms", cls: "Organic Chemistry", daysAgo: 4, hour: 13, minutes: 50,
                    topics: ["SN1", "SN2", "Carbocations", "Stereochemistry"],
                    summaryText: "When substitution happens in one step or two, and how to tell from the substrate and solvent.",
                    html: """
                    <h2>Summary</h2><p>Nucleophilic substitution goes one of two ways: SN2 in a single backside attack, or SN1 through a carbocation. Substrate, nucleophile and solvent decide which.</p>
                    <h2>Key points</h2><ul><li><strong>SN2</strong>: one step, rate = k[RX][Nu⁻], inversion of configuration, favoured by methyl and primary substrates.</li><li><strong>SN1</strong>: two steps through a carbocation, rate = k[RX], racemization, favoured by tertiary substrates and polar protic solvents.</li></ul>
                    <h2>Questions to review</h2><ol><li>Why can't tertiary halides do SN2?</li><li>Predict the product of (R)-2-bromobutane with NaCN in DMSO.</li></ol>
                    """,
                    transcript: "[00:00] Substitution. Two mechanisms.\n[08:00] SN2 is a backside attack — think umbrella flipping inside out.\n[25:40] SN1 goes through a carbocation, so stability is everything."),
    ]

    /// Flashcards and a quiz for the lecture asked about (Study), or an answer with its source at the second.
    static func ask(_ question: String, lecture: String?) -> (Int, String, Data) {
        let answer: String
        let source: [String: Any]
        // Study asks for a lecture's deck in JSON; a student's own question ("What's on Quiz 4?") gets an answer in words.
        if question.contains("JSON") {
            answer = decks[lecture ?? ""] ?? decks["demo-calc-ibp"]!
            source = ["id": lecture ?? "demo-calc-ibp", "title": lectures.first { $0.id == lecture }?.title ?? "", "class": lectures.first { $0.id == lecture }?.cls ?? "", "date": day(-1), "at": 0, "section": "Key points"]
        } else {
            answer = "Integration by parts reverses the product rule: **∫u dv = uv − ∫v du**. Pick *u* with LIATE (logs, inverse trig, algebraic, trig, exponential), so for ∫x eˣ dx you let u = x and get eˣ(x − 1) + C."
            source = ["id": "demo-calc-ibp", "title": "Integration by Parts and the LIATE Rule", "class": "Calculus II", "date": day(-1, at: 9), "at": 220, "section": "Key points"]
        }
        let lines = [
            ["kind": "text", "text": answer],
            ["kind": "done", "reply": ["answer": answer, "sources": [source], "engine": "claude", "engine_name": "Claude", "asked": "claude", "asked_name": "Claude", "fell_back": false, "why": ""]],
        ]
        let text = lines.compactMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        return (200, "application/x-ndjson", Data(text.utf8))
    }

    /// Each lecture's own flashcards and quiz.
    static let decks: [String: String] = [
        "demo-calc-ibp": """
            {"cards":[{"front":"The integration by parts formula","back":"∫u dv = uv − ∫v du"},{"front":"What does LIATE decide?","back":"Which factor to call u"},{"front":"LIATE, in order","back":"Logarithmic, Inverse trig, Algebraic, Trig, Exponential"},{"front":"When is the tabular method quickest?","back":"When u is a polynomial"},{"front":"∫ x eˣ dx","back":"eˣ(x − 1) + C"}],
             "quiz":[{"question":"In ∫x eˣ dx, which is u?","choices":["eˣ","x","x eˣ","1"],"answer":1,"why":"Algebraic comes before exponential in LIATE."},{"question":"Integration by parts runs which rule backwards?","choices":["The chain rule","The quotient rule","The product rule","The power rule"],"answer":2,"why":"d(uv) = u dv + v du, rearranged and integrated."},{"question":"For ∫x² ln x dx, u is…","choices":["x²","ln x","x² ln x","dx"],"answer":1,"why":"Logarithms come first in LIATE."}]}
            """,
        "demo-psych-memory": """
            {"cards":[{"front":"The three stages of memory","back":"Encoding, storage, retrieval"},{"front":"How much does working memory hold?","back":"About 4 chunks"},{"front":"Levels of processing","back":"Meaning-based encoding lasts longer than sound or look"},{"front":"The misinformation effect","back":"Questions after an event change what's remembered"}],
             "quiz":[{"question":"Which encoding lasts longest?","choices":["Visual","Acoustic","Semantic","Structural"],"answer":2,"why":"Processing for meaning goes deepest."},{"question":"Loftus and Palmer changed which word?","choices":["Saw","Smashed","Drove","Stopped"],"answer":1,"why":"\\"Smashed\\" raised the speeds people remembered."}]}
            """,
        "demo-chem-sn": """
            {"cards":[{"front":"SN2 rate law","back":"rate = k[RX][Nu⁻]"},{"front":"SN1 stereochemistry","back":"Racemization"},{"front":"SN2 stereochemistry","back":"Inversion of configuration"},{"front":"Which substrates favour SN1?","back":"Tertiary"}],
             "quiz":[{"question":"Which substrate favours SN1?","choices":["Methyl","Primary","Tertiary","Vinyl"],"answer":2,"why":"Tertiary carbocations are the most stable."},{"question":"SN2 happens in how many steps?","choices":["One","Two","Three","It depends"],"answer":0,"why":"A single backside attack."}]}
            """,
    ]

    /// Work to hand in: due tonight, this week, later, one missing and one handed in.
    struct DemoDue {
        var id: Int
        var name, cls: String
        var kind = "assignment"
        /// Days from today, and the time (11:59 PM unless said).
        var inDays: Int
        var hour = 23, minute = 59
        /// "overdue", "week", "later" or "handed_in".
        var group: String
        var points: Double = 20

        var missing: Bool { group == "overdue" }
        var label: String { group == "overdue" ? "Missing" : group == "handed_in" ? "Submitted" : "To do" }
        var due: String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'\(String(format: "%02d:%02d", hour, minute))"
            return f.string(from: .now.addingTimeInterval(Double(inDays) * 86_400))
        }
        var item: [String: Any] {
            ["class": cls, "id": id, "name": name, "kind": kind, "due": due, "points": points, "status": group == "handed_in" ? "submitted" : missing ? "missing" : "open",
             "label": label, "score_text": group == "handed_in" ? "18/20" : "", "late": missing, "missing": missing, "excused": false,
             "submitted": group == "handed_in" ? DemoLibrary.iso(-86_400) : NSNull(), "url": "https://canvas.example.edu"]
        }
        var detail: [String: Any] {
            ["class": cls, "id": id, "name": name, "kind": kind, "due": due, "points": points, "label": label, "score_text": group == "handed_in" ? "18/20" : "",
             "late": missing, "missing": missing, "url": "https://canvas.example.edu",
             "instructions_html": id == 1
                ? "<p>Evaluate each integral, showing every step. Use the LIATE rule to choose <em>u</em>.</p><ol><li><span class=\"math\" data-tex=\"\\int x e^{x}\\,dx\">∫ x e^x dx</span></li><li><span class=\"math\" data-tex=\"\\int x^2 \\ln x\\,dx\">∫ x² ln x dx</span></li></ol>"
                : "<p>\(name). Hand it in on Canvas.</p>",
             "rubric": id == 1 ? [["criterion": "Correct choice of u and dv", "points": 8], ["criterion": "Algebra and final answers", "points": 12]] : [],
             "comments": []]
        }
    }

    static let dueItems: [DemoDue] = [
        DemoDue(id: 5, name: "Problem Set 5: Substitution", cls: "Calculus II", inDays: -3, group: "overdue"),
        DemoDue(id: 4, name: "Quiz 4: Memory", cls: "Intro to Psychology", kind: "quiz", inDays: 0, group: "week", points: 10),
        DemoDue(id: 1, name: "Problem Set 6: Integration by Parts", cls: "Calculus II", inDays: 2, group: "week"),
        DemoDue(id: 2, name: "Lab Report: Acid–Base Titration", cls: "Organic Chemistry", inDays: 4, hour: 17, minute: 0, group: "week"),
        DemoDue(id: 3, name: "Essay: Memory and Eyewitness Testimony", cls: "Intro to Psychology", inDays: 10, group: "later"),
        DemoDue(id: 6, name: "Problem Set 4: Areas", cls: "Calculus II", inDays: -6, group: "handed_in"),
    ]

    static var dueGroups: [[String: Any]] {
        [("overdue", "Missing"), ("week", "This week"), ("later", "Later"), ("handed_in", "Handed in")].compactMap { key, label in
            let items = dueItems.filter { $0.group == key }
            return items.isEmpty ? nil : ["key": key, "label": label, "items": items.map(\.item)]
        }
    }

    static func event(_ id: String, _ title: String, _ inDays: Int, _ hour: Int, _ minutes: Int, _ place: String) -> [String: Any] {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date.now.addingTimeInterval(Double(inDays) * 86_400))!
        return eventAt(id, title, start, minutes, place)
    }

    /// An event starting `minutes` from now (rounded to the minute).
    static func eventIn(_ id: String, _ title: String, minutes: Int, length: Int, _ place: String) -> [String: Any] {
        let start = Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + Double(minutes) * 60)
        return eventAt(id, title, start, length, place)
    }

    static func eventAt(_ id: String, _ title: String, _ start: Date, _ minutes: Int, _ place: String) -> [String: Any] {
        ["id": id, "title": title, "start": ISO8601DateFormatter().string(from: start),
         "end": ISO8601DateFormatter().string(from: start.addingTimeInterval(Double(minutes) * 60)), "allDay": false, "location": place,
         "class": title.hasPrefix("Organic") ? "Organic Chemistry" : title]
    }

    static func iso(_ offset: TimeInterval) -> String { ISO8601DateFormatter().string(from: .now.addingTimeInterval(offset)) }
    static func day(_ days: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now.addingTimeInterval(Double(days) * 86_400))
    }
    /// That day at `hour` o'clock, local time ("2026-10-15T09:00:00").
    static func day(_ days: Int, at hour: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'\(String(format: "%02d", hour)):00:00"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now.addingTimeInterval(Double(days) * 86_400))
    }
    static func localISO(_ inDays: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'23:59"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now.addingTimeInterval(Double(inDays) * 86_400))
    }
}


/// `-photos-demo`: a calculus lecture with three whiteboard photos in its strip and the second embedded in its notes.
enum DemoPhotos {
    static let lecture = "demo-calc-ibp"
    static var on: Bool { DebugLaunch.flag("-photos-demo") }
    static let embed = "<h2>On the board</h2><p><img src=\"/api/v2/attachments/demo-board-2/raw\" alt=\"Whiteboard at 12:34\"></p>"

    static var attachments: [[String: Any]] {
        [(1, 4.0 * 60), (2, 12 * 60 + 34), (3, 31.0 * 60)].map { n, at in
            ["id": "demo-board-\(n)", "name": "whiteboard-\(n).jpg", "class": "Calculus II", "lecture": lecture, "size": 180_000,
             "type": "image/jpeg", "added": "2026-10-24T09:00:00-07:00", "hasText": false, "reading": false,
             "taken": "2026-10-24T09:\(10 + n):00-07:00", "at": at, "kind": "whiteboard"]
        }
    }

    /// A made-up board: white, a green frame and a few lines of marker.
    static func picture(_ path: String) -> Data {
        let n = Int(path.split(separator: "-").last?.prefix(1) ?? "1") ?? 1
        let size = CGSize(width: 800, height: 600)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.8) { c in
            UIColor(white: 0.97, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.55, alpha: 1).setStroke()
            c.cgContext.setLineWidth(10); c.cgContext.stroke(CGRect(origin: .zero, size: size))
            let ink: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 54, weight: .semibold), .foregroundColor: UIColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1)]
            ["∫ u dv = uv − ∫ v du", "u = x, dv = eˣ dx", "LIATE (\(n))"].enumerated().forEach { i, t in
                (t as NSString).draw(at: CGPoint(x: 60, y: 90 + CGFloat(i) * 130), withAttributes: ink)
            }
        }
    }
}
