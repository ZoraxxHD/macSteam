// LuaTools Supabase & Discord OAuth PKCE + Bot Code authentication service.
import AppKit
import CryptoKit
import Foundation
import Network

struct StoredAuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var displayName: String?
    var email: String?
    var avatarUrl: String?
}

enum AuthError: LocalizedError {
    case notSignedIn
    case invalidCode
    case expiredCode
    case serverError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return L10n.isFrench ? "Non connecté à LuaTools." : "Not signed in to LuaTools."
        case .invalidCode: return L10n.isFrench ? "Code invalide." : "Invalid login code."
        case .expiredCode: return L10n.isFrench ? "Ce code a expiré." : "This login code has expired."
        case .serverError(let msg): return msg
        case .cancelled: return L10n.isFrench ? "Connexion annulée." : "Sign-in cancelled."
        }
    }
}

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()
    static let authStateChangedNotification = Notification.Name("MacsteamAuthStateChanged")

    private let lock = NSLock()
    private var session: StoredAuthSession?
    private let urlSession: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: cfg)
        loadStored()
    }

    var isSignedIn: Bool {
        lock.lock(); defer { lock.unlock() }
        return session != nil && !(session?.refreshToken.isEmpty ?? true)
    }

    var isGuest: Bool { !isSignedIn }

    var displayName: String? {
        lock.lock(); defer { lock.unlock() }
        return session?.displayName ?? session?.email
    }

    var email: String? {
        lock.lock(); defer { lock.unlock() }
        return session?.email
    }

    var avatarUrl: String? {
        lock.lock(); defer { lock.unlock() }
        return session?.avatarUrl
    }

    private func loadStored() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: Paths.authFile),
              let decoded = try? JSONDecoder().decode(StoredAuthSession.self, from: data),
              !decoded.refreshToken.isEmpty else {
            session = nil
            return
        }
        session = decoded
    }

    private func saveStored(_ s: StoredAuthSession?) {
        lock.lock()
        session = s
        if let s, let data = try? JSONEncoder().encode(s) {
            try? Paths.ensureDir(Paths.configDir)
            try? data.write(to: Paths.authFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Paths.authFile)
        }
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.authStateChangedNotification, object: nil)
        }
    }

    func signOut() {
        saveStored(nil)
    }

    func validAccessToken() async throws -> String {
        let current: StoredAuthSession? = {
            lock.lock(); defer { lock.unlock() }
            return session
        }()
        guard let current else { throw AuthError.notSignedIn }
        if current.expiresAt > Date().addingTimeInterval(120) {
            return current.accessToken
        }
        return try await refreshSession(refreshToken: current.refreshToken)
    }

    private func refreshSession(refreshToken: String) async throws -> String {
        guard let url = URL(string: "\(LuaToolsConstants.supabaseUrl)/auth/v1/token?grant_type=refresh_token") else {
            throw AuthError.serverError("Invalid Supabase URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(LuaToolsConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            saveStored(nil)
            throw AuthError.notSignedIn
        }
        let parsed = try parseSupabaseSession(data)
        saveStored(parsed)
        return parsed.accessToken
    }

    // MARK: - 6-character Discord Bot Code Sign-In (/login)

    func signInWithCode(_ rawCode: String) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else { throw AuthError.invalidCode }

        guard let redeemUrl = URL(string: "\(LuaToolsConstants.apiBaseUrl)/api/auth/code/redeem") else {
            throw AuthError.serverError("Invalid redeem URL")
        }
        var redeemReq = URLRequest(url: redeemUrl)
        redeemReq.httpMethod = "POST"
        redeemReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        redeemReq.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (redeemData, redeemResp) = try await urlSession.data(for: redeemReq)
        guard let http = redeemResp as? HTTPURLResponse else {
            throw AuthError.serverError("No HTTP response")
        }
        if http.statusCode == 410 { throw AuthError.expiredCode }
        if http.statusCode == 404 || http.statusCode == 400 { throw AuthError.invalidCode }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: redeemData) as? [String: Any],
              let tokenHash = json["token"] as? String, !tokenHash.isEmpty else {
            throw AuthError.serverError("Code redemption failed (HTTP \(http.statusCode))")
        }

        guard let verifyUrl = URL(string: "\(LuaToolsConstants.supabaseUrl)/auth/v1/verify") else {
            throw AuthError.serverError("Invalid verify URL")
        }
        var verifyReq = URLRequest(url: verifyUrl)
        verifyReq.httpMethod = "POST"
        verifyReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verifyReq.setValue(LuaToolsConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        verifyReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "magiclink",
            "token_hash": tokenHash
        ])

        let (verifyData, verifyResp) = try await urlSession.data(for: verifyReq)
        guard let vHttp = verifyResp as? HTTPURLResponse, (200..<300).contains(vHttp.statusCode) else {
            throw AuthError.serverError("Token verification failed")
        }
        let parsed = try parseSupabaseSession(verifyData)
        saveStored(parsed)
    }

    // MARK: - Discord OAuth PKCE Sign-In

    func signInWithDiscord() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirectEncoded = LuaToolsConstants.oauthCallbackUrl
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? LuaToolsConstants.oauthCallbackUrl
        let authUrlStr = "\(LuaToolsConstants.supabaseUrl)/auth/v1/authorize?provider=discord"
            + "&redirect_to=\(redirectEncoded)"
            + "&code_challenge=\(challenge)&code_challenge_method=s256"

        guard let authUrl = URL(string: authUrlStr) else {
            throw AuthError.serverError("Failed to build OAuth URL")
        }

        let code = try await listenForOAuthCode(opening: authUrl)

        guard let tokenUrl = URL(string: "\(LuaToolsConstants.supabaseUrl)/auth/v1/token?grant_type=pkce") else {
            throw AuthError.serverError("Invalid PKCE token URL")
        }
        var req = URLRequest(url: tokenUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(LuaToolsConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "auth_code": code,
            "code_verifier": verifier
        ])

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.serverError("Token exchange failed: \(body)")
        }
        let parsed = try parseSupabaseSession(data)
        saveStored(parsed)
    }

    private func listenForOAuthCode(opening url: URL) async throws -> String {
        let port = NWEndpoint.Port(rawValue: LuaToolsConstants.oauthCallbackPort)!
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)

        return try await withCheckedThrowingContinuation { continuation in
            final class OnceBox: @unchecked Sendable {
                let lock = NSLock()
                var done = false
                func tryComplete() -> Bool {
                    lock.lock(); defer { lock.unlock() }
                    if done { return false }
                    done = true
                    return true
                }
            }
            let once = OnceBox()

            listener.newConnectionHandler = { conn in
                conn.start(queue: .global(qos: .userInitiated))
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    guard let data, let reqStr = String(data: data, encoding: .utf8),
                          let firstLine = reqStr.split(separator: "\r\n").first else {
                        conn.cancel()
                        return
                    }
                    let parts = firstLine.split(separator: " ")
                    guard parts.count >= 2 else { conn.cancel(); return }
                    let pathAndQuery = String(parts[1])
                    guard let comps = URLComponents(string: "http://localhost\(pathAndQuery)") else {
                        conn.cancel()
                        return
                    }
                    let items = comps.queryItems ?? []
                    let code = items.first(where: { $0.name == "code" })?.value
                    let errDesc = items.first(where: { $0.name == "error_description" })?.value

                    if code == nil && errDesc == nil {
                        let resp404 = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        conn.send(content: Data(resp404.utf8), completion: .contentProcessed { _ in conn.cancel() })
                        return
                    }

                    let ok = (code != nil)
                    let html = """
                    <!doctype html><html><head><meta charset="utf-8"><title>macSteam · LuaTools</title>
                    <style>body{background:#0b0b12;color:#e5e7eb;font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
                    .card{text-align:center;padding:2.5rem 3rem;background:#14141c;border:1px solid rgba(255,255,255,.1);border-radius:14px}
                    h1{font-size:1.3rem;margin:0 0 .5rem;color:\(ok ? "#34d399" : "#f87171")}</style></head>
                    <body><div class="card"><h1>\(ok ? "Connected to macSteam!" : "Sign-in failed")</h1>
                    <p>You can close this browser tab and return to macSteam.</p></div></body></html>
                    """
                    let bodyBytes = Data(html.utf8)
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyBytes.count)\r\nConnection: close\r\n\r\n"
                    var packet = Data(header.utf8)
                    packet.append(bodyBytes)

                    conn.send(content: packet, completion: .contentProcessed { _ in
                        conn.cancel()
                        listener.cancel()
                        if once.tryComplete() {
                            if let code {
                                continuation.resume(returning: code)
                            } else {
                                continuation.resume(throwing: AuthError.serverError(errDesc ?? "Access denied"))
                            }
                        }
                    })
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                case .failed(let err):
                    listener.cancel()
                    if once.tryComplete() {
                        continuation.resume(throwing: err)
                    }
                default:
                    break
                }
            }

            listener.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
                if once.tryComplete() {
                    listener.cancel()
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }
        }
    }

    // MARK: - Helpers

    private func parseSupabaseSession(_ data: Data) throws -> StoredAuthSession {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String,
              let refresh = root["refresh_token"] as? String else {
            throw AuthError.serverError("Malformed session payload")
        }
        let expiresIn = (root["expires_in"] as? Int) ?? 3600
        var displayName: String?
        var email: String?
        var avatar: String?

        if let user = root["user"] as? [String: Any] {
            email = user["email"] as? String
            if let meta = user["user_metadata"] as? [String: Any] {
                if let claims = meta["custom_claims"] as? [String: Any],
                   let gn = claims["global_name"] as? String, !gn.isEmpty {
                    displayName = gn
                } else if let fn = meta["full_name"] as? String, !fn.isEmpty {
                    displayName = fn
                } else if let n = meta["name"] as? String, !n.isEmpty {
                    displayName = n
                }
                avatar = meta["avatar_url"] as? String
            }
        }
        return StoredAuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            displayName: displayName ?? email,
            email: email,
            avatarUrl: avatar
        )
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
