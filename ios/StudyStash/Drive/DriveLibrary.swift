import Foundation
import Synchronization

/// The library on the student's laptop, reached through their Google Drive: every /api/v2 request to
/// `drive.studystash.app` is answered here, by a URLProtocol on the app's session, the way `DemoLibrary` answers the
/// sample classes. `APIClient` and every screen stay as they are: reads come from the copy on the phone at once, and
/// anything else goes to the laptop through `DriveLink`, streamed answers handed on line by line.
final class DriveLibrary: URLProtocol, @unchecked Sendable {
    static let host = "drive.studystash.app"
    static let base = URL(string: "https://\(host)")!
    /// A failure's NSError domain: its description is the words the screen shows (`APIError.unreachable(_:)`).
    static let errorDomain = "app.studystash.drive"

    private static let current = Mutex<DriveLink?>(nil)

    /// The signed-in account's link (nil when the phone isn't connected over Google).
    static var link: DriveLink? {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    /// The link, waiting up to 5 seconds for it.
    static func waitForLink() async -> DriveLink? {
        for _ in 0..<50 {
            if let link { return link }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return link
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let answering = Mutex<Task<Void, Never>?>(nil)

    override func startLoading() {
        let client = Handle(client: client, owner: self)
        guard let url = request.url else {
            client.fail(DriveLink.notAnswering)
            return
        }
        var path = url.path(percentEncoded: false)
        var raw = url.path(percentEncoded: true)
        for p in ["/api/v2"] where path.hasPrefix(p) {
            path.removeFirst(p.count)
            raw.removeFirst(p.count)
        }
        if let q = url.query(percentEncoded: true), !q.isEmpty { raw += "?" + q }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let incoming = DriveLink.Incoming(
            method: request.httpMethod ?? "GET", path: path, raw: raw,
            query: Dictionary(items.compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a }),
            body: DemoLibrary.body(of: request), type: request.value(forHTTPHeaderField: "Content-Type"))
        let t = Task { await DriveLibrary.answer(incoming, url: url, client: client) }
        answering.withLock { $0 = t }
    }

    /// Hand the link's answer to the loading system as it comes. Just after launch the sign-in may still be making
    /// the link: a few seconds for it.
    private static func answer(_ incoming: DriveLink.Incoming, url: URL, client: Handle) async {
        guard let link = await waitForLink() else {
            client.fail(GoogleProblem.ended.words)
            return
        }
        do {
            for try await piece in link.handle(incoming) {
                switch piece {
                case let .head(status, type): client.head(url, status, type)
                case .data(let d): client.load(d)
                }
            }
            client.finish()
        } catch is CancellationError {
        } catch let f as DriveLink.Failure {
            client.fail(f.words)
        } catch {
            client.fail(DriveLink.notAnswering)
        }
    }

    override func stopLoading() {
        answering.withLock { $0?.cancel() }
    }

    /// The URL loading system's side, handed to the task that answers (it isn't Sendable, but takes calls from any
    /// thread).
    private struct Handle: @unchecked Sendable {
        let client: (any URLProtocolClient)?
        let owner: URLProtocol

        func head(_ url: URL, _ status: Int, _ type: String) {
            let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
            client?.urlProtocol(owner, didReceive: r, cacheStoragePolicy: .notAllowed)
        }

        func load(_ d: Data) { client?.urlProtocol(owner, didLoad: d) }
        func finish() { client?.urlProtocolDidFinishLoading(owner) }

        func fail(_ words: String) {
            client?.urlProtocol(owner, didFailWithError: NSError(domain: DriveLibrary.errorDomain, code: 1,
                                                                 userInfo: [NSLocalizedDescriptionKey: words]))
        }
    }
}
