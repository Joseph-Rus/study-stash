import Foundation
import Observation

/// What the library last said for each read, on disk, so a screen opens with it at once (and offline), then
/// refreshes. Keyed by a name the screen picks ("library", "lecture:abc").
final class ResponseCache: Sendable {
    static let shared = ResponseCache()

    private let folder: URL

    init(folder: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "library")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        folder.appending(path: key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
    }

    func read<T: Codable>(_ key: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(Wrapped<T>.self, from: data).value
    }

    func write<T: Codable>(_ key: String, _ value: T) {
        guard let data = try? JSONEncoder().encode(Wrapped(value: value)) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private struct Wrapped<T: Codable>: Codable { var value: T }
}

/// One read a screen shows: what was saved before straight away, then what the library says now. `error` is set
/// only when there's nothing to show.
@MainActor @Observable
final class Resource<T: Codable & Sendable> {
    private(set) var value: T?
    private(set) var error: APIError?
    private(set) var loading = false
    /// The value shown came from the cache, and the library couldn't be reached to refresh it.
    private(set) var stale = false

    @ObservationIgnored let key: String
    @ObservationIgnored private let fetch: @Sendable () async throws -> T

    init(_ key: String, fetch: @escaping @Sendable () async throws -> T) {
        self.key = key
        self.fetch = fetch
        value = ResponseCache.shared.read(key, as: T.self)
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let fresh = try await fetch()
            value = fresh
            error = nil
            stale = false
            ResponseCache.shared.write(key, fresh)
        } catch is CancellationError {
        } catch let e as APIError {
            stale = value != nil
            error = e
        } catch {
            stale = value != nil
            self.error = APIError(status: -1, detail: "The library sent something this app couldn't read. Update Syft Notes on your computer and here.")
        }
    }
}
