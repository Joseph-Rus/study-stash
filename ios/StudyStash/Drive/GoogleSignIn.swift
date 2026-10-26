import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

// Signing in to Google on the phone, for the phone over Google Drive (docs/phone-google.md): the system's sign-in
// sheet (ASWebAuthenticationSession) with PKCE and the iOS client, no secret and no Google SDK. Only Egghead Notes' own
// hidden folder in the student's Drive is asked for (drive.appdata), and their email to say which account it is.

/// Why signing in or reaching Drive didn't work, in the student's words.
struct GoogleProblem: Error, LocalizedError, Equatable, Sendable {
    var words: String
    var errorDescription: String? { words }

    static let school = GoogleProblem(words: "Your school's Google account doesn't allow Egghead Notes. Try a personal Gmail on both.")
    static let noFolder = GoogleProblem(words: "Egghead Notes needs its folder in your Google Drive. Continue with Google again and leave the Google Drive box ticked.")
    static let refused = GoogleProblem(words: "Google didn't let Egghead Notes in. Continue with Google again, and choose Allow.")
    static let ended = GoogleProblem(words: "Your Google sign-in on this phone has ended. Continue with Google again.")
    static let offline = GoogleProblem(words: "This phone isn't online. Connect to the internet, then try again.")
    static let notInThisBuild = GoogleProblem(words: "Continue with Google isn't set up in this copy of Egghead Notes yet.")
    static let removed = GoogleProblem(words: "Your laptop removed this phone. Sign in again to use it.")
}

/// The iOS client Google gave Egghead Notes, from the build setting `GOOGLE_IOS_CLIENT_ID` (Info.plist `GoogleClientID`).
enum GoogleClient {
    static let scopes = "openid email https://www.googleapis.com/auth/drive.appdata"
    static let authorize = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// "1073354844610-abc.apps.googleusercontent.com", or nil while the build has the placeholder.
    static var id: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com"), !id.contains("replace-me"), !id.contains("$(") else { return nil }
        return id
    }

    /// The client's id turned round, Google's redirect scheme for an iOS client: "com.googleusercontent.apps.1073…-abc".
    static func scheme(of id: String) -> String {
        "com.googleusercontent.apps." + id.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    static func redirect(of id: String) -> String { scheme(of: id) + ":/oauth2redirect" }
}

/// What the Keychain keeps for the account this phone signed in with.
struct GoogleAccount: Codable, Sendable, Equatable {
    var email: String
    var refreshToken: String
    var clientID: String
    /// Only in a debug build's `-drive-token-file` (a Desktop client's): sent when refreshing.
    var clientSecret: String?
    var tokenURL: URL?
}

/// The Keychain item: one account at a time, readable after the phone's first unlock (so the background refresh can
/// reach Drive), never synced to other devices.
enum GoogleKeychain {
    private static let service = "app.studystash.ios.google"
    private static let item = "account"

    static func read() -> GoogleAccount? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: item, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }

    static func save(_ account: GoogleAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        forget()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: item, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func forget() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: item]
        SecItemDelete(query as CFDictionary)
    }
}

/// Access to Drive for one signed-in account: a short-lived access token, refreshed from the long-lived one when it runs
/// out (or Drive turns it down).
actor GoogleTokens {
    let account: GoogleAccount
    private var access: (token: String, until: Date)?
    private let session: URLSession

    init(account: GoogleAccount, session: URLSession = GoogleTokens.plainSession) {
        self.account = account
        self.session = session
    }

    /// A session that only ever talks to Google (never the in-app libraries).
    static let plainSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    var email: String { account.email }

    func token() async throws -> String {
        if let access, access.until > .now.addingTimeInterval(60) { return access.token }
        var fields = ["client_id": account.clientID, "refresh_token": account.refreshToken, "grant_type": "refresh_token"]
        if let secret = account.clientSecret { fields["client_secret"] = secret }
        let reply = try await GoogleSignIn.post(account.tokenURL ?? GoogleClient.token, fields, session: session)
        guard let token = reply.access_token else {
            // The student took Egghead Notes' access away (or it ran out): signing in again is the way back.
            throw reply.error == "invalid_grant" ? GoogleProblem.ended : GoogleProblem(words: reply.error_description ?? GoogleProblem.ended.words)
        }
        access = (token, .now.addingTimeInterval(Double(reply.expires_in ?? 3600)))
        return token
    }

    /// Drive said the token was no good: the next call refreshes it.
    func invalidate() { access = nil }

    /// Take Egghead Notes' access away at Google (signing out), as far as Google can be reached.
    func revoke() async {
        var r = URLRequest(url: GoogleClient.revoke)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = GoogleSignIn.form(["token": account.refreshToken])
        _ = try? await session.data(for: r)
    }
}

/// Signing in: Google's own page in the system's sheet, then the code it sends back swapped for the tokens.
enum GoogleSignIn {
    struct TokenReply: Decodable {
        var access_token: String?
        var expires_in: Int?
        var refresh_token: String?
        var id_token: String?
        var scope: String?
        var error: String?
        var error_description: String?
    }

    /// Sign in with the sheet `web` shows; `hint` pre-picks the account (from the laptop's QR code).
    @MainActor
    static func signIn(hint: String?, using web: WebAuthenticationSession) async throws -> GoogleAccount {
        guard let client = GoogleClient.id else { throw GoogleProblem.notInThisBuild }
        let verifier = randomString(64)
        let state = randomString(24)
        var c = URLComponents(url: GoogleClient.authorize, resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "client_id", value: client),
            URLQueryItem(name: "redirect_uri", value: GoogleClient.redirect(of: client)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleClient.scopes),
            URLQueryItem(name: "code_challenge", value: challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if let hint, !hint.isEmpty { query.append(URLQueryItem(name: "login_hint", value: hint)) } else {
            query.append(URLQueryItem(name: "prompt", value: "select_account"))
        }
        c.queryItems = query
        let back: URL
        do {
            back = try await web.authenticate(using: c.url!, callback: .customScheme(GoogleClient.scheme(of: client)),
                                              additionalHeaderFields: [:])
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            throw CancellationError()
        }
        let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = item("error") { throw problem(for: error) }
        guard item("state") == state, let code = item("code") else { throw GoogleProblem.refused }
        let reply = try await post(GoogleClient.token, ["code": code, "client_id": client, "redirect_uri": GoogleClient.redirect(of: client),
                                                        "grant_type": "authorization_code", "code_verifier": verifier])
        return try account(from: reply, client: client)
    }

    /// The account the tokens are for, once Google's reply has everything Egghead Notes needs.
    static func account(from reply: TokenReply, client: String) throws -> GoogleAccount {
        if let error = reply.error { throw problem(for: error) }
        guard let refresh = reply.refresh_token else { throw GoogleProblem.refused }
        // Google's sign-in page lets the student untick the Drive box: then there's no folder to share.
        guard reply.scope?.split(separator: " ").contains("https://www.googleapis.com/auth/drive.appdata") == true else {
            throw GoogleProblem.noFolder
        }
        return GoogleAccount(email: email(in: reply.id_token) ?? "", refreshToken: refresh, clientID: client)
    }

    /// Google's error codes, said plainly. A school (Workspace) account whose admin blocks apps it hasn't approved
    /// comes back as admin_policy_enforced or org_internal.
    static func problem(for error: String) -> GoogleProblem {
        switch error {
        case "admin_policy_enforced", "org_internal", "unauthorized_client", "access_blocked": .school
        case "access_denied": .refused
        default: GoogleProblem(words: "Google couldn't sign you in (\(error)). Try again.")
        }
    }

    /// The email in an id_token (it came straight from Google over https, so it's read, not checked).
    static func email(in idToken: String?) -> String? {
        guard let parts = idToken?.split(separator: "."), parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    static func post(_ url: URL, _ fields: [String: String], session: URLSession = GoogleTokens.plainSession) async throws -> TokenReply {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = form(fields)
        let data: Data
        do {
            (data, _) = try await session.data(for: r)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GoogleProblem.offline
        }
        guard let reply = try? JSONDecoder().decode(TokenReply.self, from: data) else { throw GoogleProblem.refused }
        return reply
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").utf8)
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomString(_ bytes: Int) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    #if DEBUG
    /// `-drive-token-file <path>` (debug builds): an account already allowed, from a JSON with `client_id`,
    /// `client_secret`, `token_uri` and `refresh_token`, so a test needs no one to press Allow. Its email is read from
    /// the first refresh. Never kept in the Keychain.
    static func debugAccount() async -> GoogleAccount? {
        guard let path = DebugLaunch.value("-drive-token-file"),
              let data = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let client = o["client_id"] as? String, let refresh = o["refresh_token"] as? String else { return nil }
        let secret = o["client_secret"] as? String
        let tokenURL = (o["token_uri"] as? String).flatMap(URL.init(string:)) ?? GoogleClient.token
        var fields = ["client_id": client, "refresh_token": refresh, "grant_type": "refresh_token"]
        if let secret { fields["client_secret"] = secret }
        let found = (try? await post(tokenURL, fields)).flatMap { email(in: $0.id_token) } ?? "test@example.com"
        return GoogleAccount(email: found, refreshToken: refresh, clientID: client, clientSecret: secret, tokenURL: tokenURL)
    }
    #endif
}
