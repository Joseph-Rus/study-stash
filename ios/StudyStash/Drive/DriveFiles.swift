import Foundation

/// A file in Egghead Notes' hidden folder.
struct DriveFile: Sendable, Equatable {
    var id: String
    var name: String
    var modified: Date
}

enum DriveError: Error, Equatable {
    /// No such file (deleted, or never there).
    case notFound
    /// Google couldn't be reached: no internet.
    case offline
    /// Drive said no, in its words.
    case refused(Int, String)
}

/// Egghead Notes' hidden folder in the student's Google Drive (the appDataFolder): what the phone does with it. One
/// implementation talks to Google; the tests have one in memory.
protocol DriveFiles: Sendable {
    /// The id of the file called `name`, or nil when there's none.
    func find(_ name: String) async throws -> String?
    /// Every file whose name starts with `prefix`.
    func list(prefix: String) async throws -> [DriveFile]
    func read(_ id: String) async throws -> Data
    /// A new file; its id.
    func create(_ name: String, _ data: Data, type: String) async throws -> String
    func update(_ id: String, _ data: Data, type: String) async throws
    func delete(_ id: String) async throws
}

/// The folder through Drive's REST API (v3), with the signed-in account's tokens.
struct GoogleDrive: DriveFiles {
    let tokens: GoogleTokens
    var session: URLSession = GoogleTokens.plainSession

    private static let api = "https://www.googleapis.com/drive/v3"
    private static let upload = "https://www.googleapis.com/upload/drive/v3"
    /// Larger than this goes up in Drive's resumable way (one PUT after the file is announced).
    private static let simpleLimit = 4 * 1024 * 1024

    func find(_ name: String) async throws -> String? {
        let q = "name = '\(name.replacingOccurrences(of: "'", with: "\\'"))' and trashed = false"
        let data = try await call("GET", Self.api + "/files?" + Self.query(["spaces": "appDataFolder", "q": q, "orderBy": "modifiedTime desc",
                                                                            "pageSize": "10", "fields": "files(id,name,modifiedTime)"]))
        return try Self.files(data).first?.id
    }

    func list(prefix: String) async throws -> [DriveFile] {
        var out: [DriveFile] = []
        var page: String?
        repeat {
            var q = ["spaces": "appDataFolder", "q": "trashed = false", "pageSize": "1000", "fields": "nextPageToken,files(id,name,modifiedTime)"]
            if let page { q["pageToken"] = page }
            let data = try await call("GET", Self.api + "/files?" + Self.query(q))
            out += try Self.files(data).filter { $0.name.hasPrefix(prefix) }
            page = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["nextPageToken"] as? String
        } while page != nil
        return out
    }

    func read(_ id: String) async throws -> Data {
        try await call("GET", Self.api + "/files/\(id)?alt=media")
    }

    func create(_ name: String, _ data: Data, type: String) async throws -> String {
        let meta = try JSONSerialization.data(withJSONObject: ["name": name, "parents": ["appDataFolder"]])
        let reply: Data
        if data.count <= Self.simpleLimit {
            let boundary = "studystash-\(UUID().uuidString)"
            var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
            body.append(meta)
            body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n--\(boundary)--".utf8))
            reply = try await call("POST", Self.upload + "/files?uploadType=multipart&fields=id", body: body,
                                   type: "multipart/related; boundary=\(boundary)")
        } else {
            reply = try await resumable("POST", Self.upload + "/files?uploadType=resumable&fields=id", meta: meta, data, type: type)
        }
        guard let id = (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["id"] as? String else {
            throw DriveError.refused(500, "Drive didn't say what it called the file.")
        }
        return id
    }

    func update(_ id: String, _ data: Data, type: String) async throws {
        if data.count <= Self.simpleLimit {
            _ = try await call("PATCH", Self.upload + "/files/\(id)?uploadType=media&fields=id", body: data, type: type)
        } else {
            _ = try await resumable("PATCH", Self.upload + "/files/\(id)?uploadType=resumable&fields=id", meta: Data("{}".utf8), data, type: type)
        }
    }

    func delete(_ id: String) async throws {
        do {
            _ = try await call("DELETE", Self.api + "/files/\(id)")
        } catch DriveError.notFound {}
    }

    // MARK: talking to Google

    /// One call, with the access token; turned down once for an old token, it's refreshed and tried again.
    private func call(_ method: String, _ url: String, body: Data? = nil, type: String? = nil, headers: [String: String] = [:],
                      fresh: Bool = false) async throws -> Data {
        let (data, http) = try await send(method, url, body: body, type: type, headers: headers)
        if http.statusCode == 401, !fresh {
            await tokens.invalidate()
            return try await call(method, url, body: body, type: type, headers: headers, fresh: true)
        }
        try Self.check(http, data)
        return data
    }

    private func send(_ method: String, _ url: String, body: Data?, type: String?, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = method
        r.timeoutInterval = body.map { $0.count > Self.simpleLimit ? 600 : 30 } ?? 30
        r.setValue("Bearer \(try await tokens.token())", forHTTPHeaderField: "Authorization")
        if let type { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = body
        do {
            let (data, response) = try await session.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw DriveError.offline }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch let e as DriveError {
            throw e
        } catch {
            throw DriveError.offline
        }
    }

    /// A big file: announced with its metadata, then its bytes in one PUT to the address Drive gave.
    private func resumable(_ method: String, _ url: String, meta: Data, _ data: Data, type: String) async throws -> Data {
        let (start, http) = try await send(method, url, body: meta, type: "application/json; charset=UTF-8",
                                           headers: ["X-Upload-Content-Type": type, "X-Upload-Content-Length": String(data.count)])
        try Self.check(http, start)
        guard let location = http.value(forHTTPHeaderField: "Location") else { throw DriveError.refused(500, "Drive didn't say where to send the file.") }
        let (reply, done) = try await send("PUT", location, body: data, type: type, headers: [:])
        try Self.check(done, reply)
        return reply
    }

    private static func check(_ http: HTTPURLResponse, _ data: Data) throws {
        guard !(200..<300).contains(http.statusCode) else { return }
        if http.statusCode == 404 { throw DriveError.notFound }
        let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = o?["error"] as? [String: Any]
        let reason = ((error?["errors"] as? [[String: Any]])?.first?["reason"] as? String) ?? ""
        // The Drive box unticked on Google's page (or access taken back for the folder).
        if http.statusCode == 403, reason == "insufficientPermissions" || reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT" {
            throw GoogleProblem.noFolder
        }
        throw DriveError.refused(http.statusCode, error?["message"] as? String ?? "Google Drive said no (\(http.statusCode)).")
    }

    private static func files(_ data: Data) throws -> [DriveFile] {
        let o = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (o?["files"] as? [[String: Any]] ?? []).compactMap { f in
            guard let id = f["id"] as? String, let name = f["name"] as? String else { return nil }
            return DriveFile(id: id, name: name, modified: (f["modifiedTime"] as? String).flatMap(iso.date(from:)) ?? .distantPast)
        }
    }

    private static func query(_ q: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return q.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}
