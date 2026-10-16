import Foundation

/// Something the library said no to, or couldn't be asked at all. `status` 0 means the phone never reached it (no
/// network, or Tailscale off); `detail` is the library's own words when it gave some.
struct APIError: Error, LocalizedError, Sendable, Equatable {
    var status: Int
    var detail: String

    var unreachable: Bool { status == 0 }
    var unauthorized: Bool { status == 401 }
    var errorDescription: String? { detail }

    static let unreachableLibrary = APIError(status: 0, detail: "Can't reach your library. Is Tailscale on, and your computer awake?")

    static func words(for status: Int) -> String {
        switch status {
        case 401: "This phone needs pairing with your library again."
        case 404: "That isn't in your library any more."
        case 413: "That's too big to send in one go (up to 200 MB)."
        case 429: "Too many tries. Wait a minute, then try again."
        case 500...: "Your library had a problem. Try again in a moment."
        default: "Something went wrong."
        }
    }
}

/// The library's /api/v2, typed. Every call carries the `device` cookie pairing set (kept by the session's cookie
/// storage, so it survives relaunches).
final class APIClient: Sendable {
    let base: URL
    private let session: URLSession
    private let onUnauthorized: @Sendable () -> Void

    init(base: URL, session: URLSession = .shared, onUnauthorized: @escaping @Sendable () -> Void = {}) {
        self.base = base
        self.session = session
        self.onUnauthorized = onUnauthorized
    }

    static let decoder = JSONDecoder()

    /// A path under /api/v2 with its query (empty and missing values left out).
    func url(_ path: String, _ query: [String: String?] = [:]) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.percentEncodedPath = "/api/v2" + path
        let items = query.sorted { $0.key < $1.key }.compactMap { k, v in v.flatMap { $0.isEmpty ? nil : URLQueryItem(name: k, value: $0) } }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }

    static func segment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? s
    }

    // MARK: sending

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.unreachableLibrary
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachableLibrary }
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, data) }
        return (data, http)
    }

    private func failure(_ status: Int, _ data: Data) -> APIError {
        struct Body: Decodable { var detail: String?; var error: String? }
        let body = try? Self.decoder.decode(Body.self, from: data)
        if status == 401 { onUnauthorized() }
        let detail = body?.detail ?? body?.error ?? ""
        return APIError(status: status, detail: detail.isEmpty ? APIError.words(for: status) : detail)
    }

    private func request(_ method: String, _ path: String, query: [String: String?] = [:], json: (any Encodable)? = nil) throws -> URLRequest {
        var r = URLRequest(url: url(path, query))
        r.httpMethod = method
        r.timeoutInterval = 30
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(json)
        }
        return r
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        let (data, _) = try await send(request("GET", path, query: query))
        return try Self.decoder.decode(T.self, from: data)
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        let (data, _) = try await send(request("POST", path, json: body))
        return try Self.decoder.decode(T.self, from: data)
    }

    func delete(_ path: String) async throws {
        _ = try await send(request("DELETE", path))
    }

    /// A streamed reply, one JSON object a line (Ask and chat).
    func lines<T: Decodable & Sendable>(_ path: String, _ body: some Encodable, as: T.Type) async throws -> AsyncThrowingStream<T, Error> {
        let req = try request("POST", path, json: body)
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch {
            throw APIError.unreachableLibrary
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachableLibrary }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw failure(http.statusCode, data)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        if let value = try? Self.decoder.decode(T.self, from: Data(line.utf8)) { continuation.yield(value) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A multipart upload: files plus plain fields.
    func upload<T: Decodable>(_ path: String, files: [(name: String, type: String, data: Data)], fields: [String: String?]) async throws -> T {
        let boundary = "StudyStash-\(UUID().uuidString)"
        var body = Data()
        func line(_ s: String) { body.append(Data((s + "\r\n").utf8)) }
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
            guard let v, !v.isEmpty else { continue }
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(k)\"")
            line("")
            line(v)
        }
        for f in files {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"file\"; filename=\"\(f.name.replacingOccurrences(of: "\"", with: "'"))\"")
            line("Content-Type: \(f.type)")
            line("")
            body.append(f.data)
            line("")
        }
        line("--\(boundary)--")
        var r = URLRequest(url: url(path))
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let (data, _) = try await send(r)
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: this phone

    func me() async throws -> Me { try await get("/me") }

    /// Pair with the 6-digit code the library showed; the library sets the `device` cookie.
    func pair(code: String, name: String) async throws -> Device {
        struct Body: Encodable { var code: String; var name: String }
        struct Reply: Decodable { var device: Device }
        let reply: Reply = try await post("/devices/pair", Body(code: code, name: name))
        return reply.device
    }

    func devices() async throws -> [Device] {
        struct Reply: Decodable { var devices: [Device] }
        let reply: Reply = try await get("/devices")
        return reply.devices
    }

    func removeDevice(_ id: String) async throws { try await delete("/devices/\(Self.segment(id))") }

    // MARK: the library

    func library() async throws -> LibraryOverview { try await get("/library") }

    /// Lectures newest first: in one class (or "Unsorted") or all, `before` a date to page back.
    func lectures(class cls: String? = nil, limit: Int? = nil, before: String? = nil) async throws -> [LectureSummary] {
        try await get("/lectures", query: ["class": cls, "limit": limit.map(String.init), "before": before])
    }

    func lecture(_ id: String) async throws -> Lecture { try await get("/lectures/\(Self.segment(id))") }
    func rendered(_ id: String) async throws -> RenderedLecture { try await get("/lectures/\(Self.segment(id))/rendered") }

    func search(_ q: String, class cls: String? = nil, limit: Int? = nil) async throws -> SearchResults {
        try await get("/search", query: ["q": q, "class": cls, "limit": limit.map(String.init)])
    }

    // MARK: asking

    struct AskBody: Encodable { var question: String; var lecture: String?; var `class`: String?; var stream = true }

    func ask(_ question: String, lecture: String? = nil, class cls: String? = nil) async throws -> AsyncThrowingStream<AskEvent, Error> {
        try await lines("/ai/ask", AskBody(question: question, lecture: lecture, class: cls), as: AskEvent.self)
    }

    /// Let the engine that will answer get ready while the question is typed.
    func warm() async {
        struct Empty: Encodable {}
        struct Any_: Decodable {}
        _ = try? await post("/ai/warm", Empty()) as Any_
    }

    func chats() async throws -> [ChatSummary] { try await get("/chats") }
    func chat(_ id: String) async throws -> Chat { try await get("/chats/\(Self.segment(id))") }
    func deleteChat(_ id: String) async throws { try await delete("/chats/\(Self.segment(id))") }

    struct ChatBody: Encodable { var message: String; var chat: String?; var `class`: String?; var lecture: String?; var edit = false }

    func sendChat(_ message: String, chat: String?, class cls: String? = nil, lecture: String? = nil) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try await lines("/chat", ChatBody(message: message, chat: chat, class: cls, lecture: lecture), as: ChatEvent.self)
    }

    // MARK: what's coming

    func due() async throws -> DueList { try await get("/canvas/due") }
    func assignment(class cls: String, id: Int) async throws -> AssignmentDetail {
        try await get("/canvas/assignment", query: ["class": cls, "id": String(id)])
    }
    func upcoming() async throws -> Upcoming { try await get("/calendar/upcoming") }

    // MARK: files

    func attachments(class cls: String? = nil, lecture: String? = nil) async throws -> [Attachment] {
        struct Reply: Decodable { var attachments: [Attachment] }
        let reply: Reply = try await get("/attachments", query: ["class": cls, "lecture": lecture])
        return reply.attachments
    }

    func attachmentURL(_ id: String) -> URL { url("/attachments/\(Self.segment(id))/raw") }
    func deleteAttachment(_ id: String) async throws { try await delete("/attachments/\(Self.segment(id))") }

    func upload(files: [(name: String, type: String, data: Data)], class cls: String?, lecture: String?) async throws -> [Attachment] {
        struct Reply: Decodable { var attachments: [Attachment]? }
        let reply: Reply = try await upload("/attachments", files: files, fields: ["class": cls, "lecture": lecture])
        return reply.attachments ?? []
    }

    // MARK: voice memos

    func voiceMemos() async throws -> [VoiceMemo] {
        struct Reply: Decodable { var memos: [VoiceMemo] }
        let reply: Reply = try await get("/voice-memos")
        return reply.memos
    }

    func sendVoiceMemo(name: String, data: Data, type: String, class cls: String?, title: String?) async throws -> VoiceMemo {
        try await upload("/voice-memos", files: [(name, type, data)], fields: ["class": cls, "title": title])
    }

    func retryVoiceMemo(_ id: String) async throws -> VoiceMemo {
        struct Empty: Encodable {}
        return try await post("/voice-memos/\(Self.segment(id))/retry", Empty())
    }

    func deleteVoiceMemo(_ id: String) async throws { try await delete("/voice-memos/\(Self.segment(id))") }
}
