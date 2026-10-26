import Foundation

/// Where a library might be, from what the student scanned or pasted: the QR code in Settings → Add a phone
/// ("http://100.64.0.1:8787/app/?https=https%3A%2F%2Fmac.tail.ts.net%3A8443%2Fapp%2F"), either of those addresses
/// alone, or a bare host ("mac.tail.ts.net:8443", "100.64.0.1:8787"). A computer on a newer Egghead Notes ends the QR
/// code's address with the pairing code too ("…%2Fapp%2F#code=042917"), so the phone needn't ask for it.
///
/// `candidates` are the API roots to try, best first: the https one (Tailscale Serve) before the plain Tailscale IP.
enum LibraryAddress {
    static func candidates(from raw: String) -> [URL] {
        guard let parsed = parse(raw) else { return [] }
        let (url, parts) = parsed
        var found: [URL] = []
        if let secure = parts.queryItems?.first(where: { $0.name == "https" })?.value,
           let secureURL = URL(string: secure), let root = root(of: secureURL) {
            found.append(root)
        }
        if let root = root(of: url) { found.append(root) }
        var seen = Set<URL>()
        return found.filter { seen.insert($0).inserted }
    }

    /// The 6-digit code that came with the address: `#code=042917` at its end (or `?code=`, or in the https address
    /// inside it). Nil when there's none, as from a computer that isn't updated yet: then the phone asks for it.
    static func code(from raw: String) -> String? {
        guard let parts = parse(raw)?.parts else { return nil }
        var inner: URLComponents?
        if let secure = parts.queryItems?.first(where: { $0.name == "https" })?.value { inner = URLComponents(string: secure) }
        for p in [parts, inner].compactMap({ $0 }) {
            if let code = code(in: p.fragment) ?? p.queryItems?.first(where: { $0.name == "code" })?.value.flatMap(sixDigits) {
                return code
            }
        }
        return nil
    }

    /// `code=042917` among a fragment's `name=value` pairs.
    private static func code(in fragment: String?) -> String? {
        guard let fragment else { return nil }
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == "code", let code = sixDigits(kv[1].removingPercentEncoding ?? kv[1]) { return code }
        }
        return nil
    }

    /// Six digits, as the computer shows them ("042 917" too).
    private static func sixDigits(_ s: String) -> String? {
        let digits = s.filter { $0 != " " }
        return digits.count == 6 && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) ? digits : nil
    }

    /// What was scanned or typed as a URL, with a scheme guessed for a bare host; nil if it isn't one.
    private static func parse(_ raw: String) -> (url: URL, parts: URLComponents)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let withScheme = text.contains("://") ? text : (looksLikeIP(text) ? "http://" : "https://") + text
        guard let url = URL(string: withScheme), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.host() != nil
        else { return nil }
        return (url: url, parts: parts)
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
        let host = s.split(whereSeparator: { ":/#?".contains($0) }).first.map(String.init) ?? s
        return host.split(separator: ".").count == 4 && host.allSatisfy { $0.isNumber || $0 == "." }
    }
}
