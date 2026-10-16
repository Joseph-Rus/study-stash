import Foundation

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
        switch (method, path) {
        case ("GET", "/api/v2/me"):
            return json(["paired": true, "library": ["name": "Demo library", "version": "demo"], "device": ["id": "demo", "name": "This phone", "added": iso(-86_400 * 3)]])
        case ("GET", "/api/v2/library"):
            return json(overview)
        case ("GET", "/api/v2/lectures"):
            let cls = q["class"]
            return json(lectures.filter { cls == nil || $0.cls == cls }.map(\.summary))
        case ("GET", _) where path.hasPrefix("/api/v2/lectures/") && path.hasSuffix("/rendered"):
            let id = String(path.dropFirst("/api/v2/lectures/".count).dropLast("/rendered".count))
            guard let l = lectures.first(where: { $0.id == id }) else { return json(["detail": "no such lecture"], 404) }
            return json(["id": l.id, "title": l.title, "class": l.cls, "date": l.date, "html": l.html])
        case ("GET", _) where path.hasPrefix("/api/v2/lectures/"):
            let id = String(path.dropFirst("/api/v2/lectures/".count))
            guard let l = lectures.first(where: { $0.id == id }) else { return json(["detail": "no such lecture"], 404) }
            var full = l.summary
            full["notes"] = l.html
            full["transcript"] = l.transcript
            full["error"] = NSNull()
            return json(full)
        case ("GET", "/api/v2/search"):
            let words = (q["q"] ?? "").lowercased()
            let hits = lectures.filter { l in
                let text = (l.title + " " + l.topics.joined(separator: " ") + " " + l.transcript).lowercased()
                return words.split(separator: " ").contains { w in text.contains(w) }
            }
            return json(["query": q["q"] ?? "", "lectures": hits.map(\.summary), "classes": [], "passages": hits.prefix(3).map { l in
                ["id": l.id, "title": l.title, "class": l.cls, "date": l.date, "kind": "transcript", "section": "", "at": 312, "text": String(l.transcript.prefix(220))] as [String: Any]
            }])
        case ("GET", "/api/v2/canvas/due"):
            return json(["synced": iso(-1800), "to_hand_in": 3, "next": NSNull(), "groups": [
                ["key": "week", "label": "This week", "items": [due(1, "Problem Set 6: Integration by Parts", "Calculus II", 2), due(2, "Lab Report: Acid–Base Titration", "Organic Chemistry", 4)]],
                ["key": "later", "label": "Later", "items": [due(3, "Essay: Memory and Eyewitness Testimony", "Intro to Psychology", 10)]],
            ]])
        case ("GET", "/api/v2/canvas/assignment"):
            return json([
                "class": "Calculus II", "id": 1, "name": "Problem Set 6: Integration by Parts", "kind": "assignment", "due": localISO(2), "points": 20,
                "label": "To do", "score_text": "", "late": false, "missing": false, "url": "https://canvas.example.edu",
                "instructions_html": "<p>Evaluate each integral, showing every step. Use the LIATE rule to choose <em>u</em>.</p><ol><li><span class=\"math\" data-tex=\"\\int x e^{x}\\,dx\">∫ x e^x dx</span></li><li><span class=\"math\" data-tex=\"\\int x^2 \\ln x\\,dx\">∫ x² ln x dx</span></li></ol>",
                "rubric": [["criterion": "Correct choice of u and dv", "points": 8], ["criterion": "Algebra and final answers", "points": 12]], "comments": [],
            ])
        case ("GET", "/api/v2/calendar/upcoming"):
            return json(["updated": iso(-300), "events": [
                event("e1", "Calculus II", 1, 9, 50, "Science Hall 204"),
                event("e2", "Intro to Psychology", 1, 11, 75, "Lecture Hall B"),
                event("e3", "Organic Chemistry Lab", 2, 13, 170, "Chem 110"),
            ]])
        case ("GET", "/api/v2/attachments"):
            return json(["attachments": []])
        case ("GET", "/api/v2/chats"):
            return json([])
        case ("POST", "/api/v2/ai/ask"):
            let question = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["question"] as? String) ?? ""
            return ask(question)
        case ("POST", "/api/v2/ai/warm"):
            return json([:])
        case ("POST", "/api/v2/lectures"):
            return json(["id": "demo", "status": "queued", "class_name": NSNull(), "has_transcript": true])
        case ("POST", "/api/v2/attachments"):
            return json(["attachments": []])
        case ("POST", "/api/v2/uses"), ("POST", "/api/v2/classes/alias"):
            return json(overview)
        case ("GET", "/api/v2/voice-memos"):
            return json(["memos": []])
        default:
            return json(["detail": "The demo library doesn't do that."], 404)
        }
    }

    // MARK: the made-up library

    struct DemoLecture {
        var id, title, cls: String
        var daysAgo: Int
        var minutes: Int
        var topics: [String]
        var summaryText: String
        var html: String
        var transcript: String

        var date: String { DemoLibrary.day(-daysAgo) }
        var summary: [String: Any] {
            ["id": id, "title": title, "class": cls, "date": date, "seconds": minutes * 60, "owner": "You", "status": "done",
             "summary": summaryText, "topics": topics, "has_transcript": true]
        }
    }

    static let classes = ["Calculus II", "Intro to Psychology", "Organic Chemistry"]

    static var overview: [String: Any] {
        ["name": "Demo library", "version": "demo", "unsorted": 0, "writing": 0, "ask": true, "notes_model": "Claude", "uses": ["student"], "for_school": true,
         "classes": classes.enumerated().map { i, c in
             ["name": c, "lectures": lectures.filter { $0.cls == c }.count, "color": i, "description": "", "code": ["MATH 162", "PSYC 101", "CHEM 231"][i], "aliases": []] as [String: Any]
         }]
    }

    static let lectures: [DemoLecture] = [
        DemoLecture(id: "demo-calc-ibp", title: "Integration by Parts and the LIATE Rule", cls: "Calculus II", daysAgo: 1, minutes: 52,
                    topics: ["Integration by parts", "LIATE", "Tabular method"],
                    summaryText: "How to integrate products by reversing the product rule, and how to choose u.",
                    html: """
                    <h2>Summary</h2><p>Integration by parts turns the integral of a product into an easier one by running the product rule backwards. Most of the skill is choosing which factor to call <em>u</em>.</p>
                    <h2>Key points</h2><ul><li>The formula: <span class="math display" data-tex="\\int u\\,dv = uv - \\int v\\,du">∫ u dv = uv − ∫ v du</span></li><li><strong>LIATE</strong> picks <em>u</em>: Logarithmic, Inverse trig, Algebraic, Trig, Exponential — whichever comes first.</li><li>Repeated parts: when <em>u</em> is a polynomial, the tabular method saves time.</li></ul>
                    <h2>Details and examples</h2><p>Example: <span class="math" data-tex="\\int x e^{x}\\,dx">∫ x eˣ dx</span>. Let <span class="math" data-tex="u = x">u = x</span>, <span class="math" data-tex="dv = e^x dx">dv = eˣ dx</span>, so <span class="math display" data-tex="\\int x e^x\\,dx = x e^x - \\int e^x\\,dx = e^x(x-1) + C">= eˣ(x − 1) + C</span></p>
                    <table><tr><th>Sign</th><th>u and its derivatives</th><th>dv and its integrals</th></tr><tr><td>+</td><td>x²</td><td>eˣ</td></tr><tr><td>−</td><td>2x</td><td>eˣ</td></tr><tr><td>+</td><td>2</td><td>eˣ</td></tr></table>
                    <h2>Questions to review</h2><ol><li>Why does LIATE put logarithms first?</li><li>Evaluate ∫ x cos x dx.</li><li>When does integration by parts loop back to the original integral, and how do you finish?</li></ol>
                    """,
                    transcript: "[00:00] Alright, let's get going. Today is integration by parts.\n[00:12] It's really just the product rule run backwards.\n[03:40] So how do you choose u? There's a rule of thumb, LIATE.\n[09:15] Let's do x e to the x together.\n[21:30] When u is a polynomial, the tabular method is a lifesaver."),
        DemoLecture(id: "demo-psych-memory", title: "Memory: Encoding, Storage and Retrieval", cls: "Intro to Psychology", daysAgo: 2, minutes: 74,
                    topics: ["Working memory", "Levels of processing", "Misinformation effect"],
                    summaryText: "The three stages of memory, why deeper processing sticks, and how memories get rewritten.",
                    html: """
                    <h2>Summary</h2><p>Memory works in three stages: encoding, storage and retrieval. What we notice and how deeply we process it decides what lasts, and recall is a reconstruction, not a replay.</p>
                    <h2>Key points</h2><ul><li><strong>Working memory</strong> holds about 4 chunks for a few seconds; rehearsal keeps them there.</li><li><strong>Levels of processing</strong>: meaning-based (semantic) encoding beats sound or appearance.</li><li><strong>The misinformation effect</strong>: questions asked after an event change what people remember (Loftus &amp; Palmer, 1974).</li></ul>
                    <h2>Definitions</h2><ul><li><strong>Encoding</strong>: turning experience into a form memory can store.</li><li><strong>Retrieval cue</strong>: anything that helps bring a memory back.</li></ul>
                    <h2>Announcements</h2><ul><li>Essay on eyewitness testimony due in ten days.</li></ul>
                    """,
                    transcript: "[00:00] Today: how memory actually works.\n[05:20] Working memory holds about four chunks.\n[31:10] Loftus and Palmer — smashed versus hit.\n[70:02] The essay is due in ten days."),
        DemoLecture(id: "demo-chem-sn", title: "SN1 vs SN2: Substitution Mechanisms", cls: "Organic Chemistry", daysAgo: 4, minutes: 50,
                    topics: ["SN1", "SN2", "Carbocations", "Stereochemistry"],
                    summaryText: "When substitution happens in one step or two, and how to tell from the substrate and solvent.",
                    html: """
                    <h2>Summary</h2><p>Nucleophilic substitution goes one of two ways: SN2 in a single backside attack, or SN1 through a carbocation. Substrate, nucleophile and solvent decide which.</p>
                    <h2>Key points</h2><ul><li><strong>SN2</strong>: one step, rate = k[RX][Nu⁻], inversion of configuration, favoured by methyl and primary substrates.</li><li><strong>SN1</strong>: two steps through a carbocation, rate = k[RX], racemization, favoured by tertiary substrates and polar protic solvents.</li></ul>
                    <h2>Questions to review</h2><ol><li>Why can't tertiary halides do SN2?</li><li>Predict the product of (R)-2-bromobutane with NaCN in DMSO.</li></ol>
                    """,
                    transcript: "[00:00] Substitution. Two mechanisms.\n[08:00] SN2 is a backside attack — think umbrella flipping inside out.\n[25:40] SN1 goes through a carbocation, so stability is everything."),
    ]

    static func ask(_ question: String) -> (Int, String, Data) {
        let answer = question.lowercased().contains("quiz") || question.contains("JSON")
            ? """
              {"cards":[{"front":"Integration by parts formula","back":"∫u dv = uv − ∫v du"},{"front":"What does LIATE decide?","back":"Which factor to call u"},{"front":"Working memory holds about…","back":"4 chunks"},{"front":"SN2 rate law","back":"rate = k[RX][Nu⁻]"},{"front":"SN1 stereochemistry","back":"Racemization"}],
               "quiz":[{"question":"In ∫x eˣ dx, which is u?","choices":["eˣ","x","x eˣ","1"],"answer":1,"why":"Algebraic comes before exponential in LIATE."},{"question":"Which substrate favours SN1?","choices":["Methyl","Primary","Tertiary","Vinyl"],"answer":2,"why":"Tertiary carbocations are the most stable."}]}
              """
            : "Integration by parts reverses the product rule: **∫u dv = uv − ∫v du**. Pick *u* with LIATE (logs, inverse trig, algebraic, trig, exponential), so for ∫x eˣ dx you let u = x and get eˣ(x − 1) + C."
        let lines = [
            ["kind": "text", "text": answer],
            ["kind": "done", "reply": ["answer": answer, "sources": [["id": "demo-calc-ibp", "title": "Integration by Parts and the LIATE Rule", "class": "Calculus II", "date": day(-1), "at": 222, "section": "Key points"]],
                                       "engine": "claude", "engine_name": "Claude", "asked": "claude", "asked_name": "Claude", "fell_back": false, "why": ""]],
        ]
        let text = lines.compactMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        return (200, "application/x-ndjson", Data(text.utf8))
    }

    static func due(_ id: Int, _ name: String, _ cls: String, _ inDays: Int) -> [String: Any] {
        ["class": cls, "id": id, "name": name, "kind": "assignment", "due": localISO(inDays), "points": 20, "status": "open", "label": "To do",
         "score_text": "", "late": false, "missing": false, "excused": false, "submitted": NSNull(), "url": "https://canvas.example.edu"]
    }

    static func event(_ id: String, _ title: String, _ inDays: Int, _ hour: Int, _ minutes: Int, _ place: String) -> [String: Any] {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date.now.addingTimeInterval(Double(inDays) * 86_400))!
        return ["id": id, "title": title, "start": ISO8601DateFormatter().string(from: start),
                "end": ISO8601DateFormatter().string(from: start.addingTimeInterval(Double(minutes) * 60)), "allDay": false, "location": place, "class": title.hasPrefix("Organic") ? "Organic Chemistry" : title]
    }

    static func iso(_ offset: TimeInterval) -> String { ISO8601DateFormatter().string(from: .now.addingTimeInterval(offset)) }
    static func day(_ days: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now.addingTimeInterval(Double(days) * 86_400))
    }
    static func localISO(_ inDays: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'23:59"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now.addingTimeInterval(Double(inDays) * 86_400))
    }
}
