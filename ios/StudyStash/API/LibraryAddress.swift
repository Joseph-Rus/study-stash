import Foundation

/// Where a library might be, from what the student scanned or pasted: the QR code in Settings → Add a phone
/// ("http://100.64.0.1:8787/app/?https=https%3A%2F%2Fmac.tail.ts.net%3A8443%2Fapp%2F"), either of those addresses
/// alone, or a bare host ("mac.tail.ts.net:8443", "100.64.0.1:8787").
///
/// The answer is the API roots to try, best first: the https one (Tailscale Serve) before the plain Tailscale IP.
enum LibraryAddress {
    static func candidates(from raw: String) -> [URL] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let withScheme = text.contains("://") ? text : (looksLikeIP(text) ? "http://" : "https://") + text
        guard let url = URL(string: withScheme), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.host() != nil
        else { return [] }

        var found: [URL] = []
        if let secure = parts.queryItems?.first(where: { $0.name == "https" })?.value,
           let secureURL = URL(string: secure), let root = root(of: secureURL) {
            found.append(root)
        }
        if let root = root(of: url) { found.append(root) }
        var seen = Set<URL>()
        return found.filter { seen.insert($0).inserted }
    }

    /// The library's own address: scheme, host and port, with the phone app's /app/ path and any query gone.
    static func root(of url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host() else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = url.port
        return c.url
    }

    private static func looksLikeIP(_ s: String) -> Bool {
        let host = s.split(separator: ":").first.map(String.init) ?? s
        return host.split(separator: ".").count == 4 && host.allSatisfy { $0.isNumber || $0 == "." }
    }
}
