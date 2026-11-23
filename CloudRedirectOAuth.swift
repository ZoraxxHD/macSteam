// Native OAuth2 PKCE (Google Drive & OneDrive) + Connection Tester (GDrive, OneDrive, R2, S3, Folder)
import AppKit
import CryptoKit
import Foundation
import Network

enum CloudOAuthError: LocalizedError {
    case cancelled
    case portBusy(UInt16)
    case missingCallbackCode(String)
    case tokenExchangeFailed(String)
    case missingRefreshToken
    case testFailed(String)

    var errorDescription: String? {
        let fr = L10n.isFrench
        switch self {
        case .cancelled:
            return fr ? "Authentification annulée." : "Authentication cancelled."
        case .portBusy(let port):
            return fr
                ? "Le port local \(port) est déjà utilisé par une autre application."
                : "Local port \(port) is already in use by another application."
        case .missingCallbackCode(let detail):
            return fr ? "Réponse OAuth invalide : \(detail)" : "Invalid OAuth callback: \(detail)"
        case .tokenExchangeFailed(let detail):
            return fr ? "Échange de jeton échoué : \(detail)" : "Token exchange failed: \(detail)"
        case .missingRefreshToken:
            return fr
                ? "Aucun refresh_token reçu. Révoquez l'accès et réessayez."
                : "No refresh_token returned. Revoke access and retry."
        case .testFailed(let msg):
            return msg
        }
    }
}

struct CloudTokenPayload: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int64
}

// MARK: - OAuth2 PKCE Loopback Flow (Google Drive & OneDrive)

final class CloudRedirectOAuthSession: @unchecked Sendable {

    // Same public OAuth clients shipped by CloudRedirect 2.6.8
    static let gdriveClientId = "1072944905499-vm2v2i5dvn0a0d2o4ca36i1vge8cvbn0.apps.googleusercontent.com"
    static let gdriveClientSecret = "v6V3fKV_zWU7iw1DrpO1rknX"
    static let gdriveScope = "https://www.googleapis.com/auth/drive.file"
    static let gdriveAuthURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let gdriveTokenURL = "https://oauth2.googleapis.com/token"

    static let oneDriveClientId = "b15665d9-eda6-4092-8539-0eec376afd59"
    static let oneDriveClientSecret = "qtyfaBBYA403=unZUP40~_#"
    static let oneDriveScope = "Files.ReadWrite offline_access"
    static let oneDriveAuthURL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    static let oneDriveTokenURL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    static let oneDrivePort: UInt16 = 53682

    private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var settled = false

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<T, Error>) {
            let cont: CheckedContinuation<T, Error>? = lock.withLock {
                guard !settled else { return nil }
                settled = true
                let c = continuation
                continuation = nil
                return c
            }
            cont?.resume(with: result)
        }
    }

    private let lock = NSLock()
    private var listener: NWListener?
    private var codeGate: ContinuationGate<String>?
    private var isCancelled = false

    func cancel() {
        let (gate, l): (ContinuationGate<String>?, NWListener?) = lock.withLock {
            isCancelled = true
            let g = codeGate
            codeGate = nil
            let current = listener
            listener = nil
            return (g, current)
        }

        l?.cancel()
        gate?.finish(.failure(CloudOAuthError.cancelled))
    }

    private func installListener(_ nwListener: NWListener) -> Bool {
        lock.withLock {
            guard !isCancelled else { return false }
            listener = nwListener
            return true
        }
    }

    private func installCodeGate(_ gate: ContinuationGate<String>) -> Bool {
        lock.withLock {
            guard !isCancelled else { return false }
            codeGate = gate
            return true
        }
    }

    private func takeCodeGate() -> ContinuationGate<String>? {
        lock.withLock {
            let g = codeGate
            codeGate = nil
            return g
        }
    }

    func authorize(
        provider: CloudProviderKind,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> CloudTokenPayload {
        guard provider == .gdrive || provider == .onedrive else {
            throw CloudOAuthError.tokenExchangeFailed("Unsupported OAuth provider")
        }

        let fr = L10n.isFrench
        let state = Self.randomURLSafeString(length: 32)
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.pkceChallenge(for: verifier)

        let fixedPort: NWEndpoint.Port = (provider == .onedrive) ? NWEndpoint.Port(rawValue: Self.oneDrivePort)! : .any
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwListener: NWListener
        do {
            nwListener = try NWListener(using: params, on: fixedPort)
        } catch {
            if provider == .onedrive {
                throw CloudOAuthError.portBusy(Self.oneDrivePort)
            }
            throw error
        }

        guard installListener(nwListener) else {
            throw CloudOAuthError.cancelled
        }

        defer { stopListener() }

        let boundPort: UInt16 = try await startAndWaitForPort(
            nwListener,
            fixedPort: provider == .onedrive ? Self.oneDrivePort : nil,
            expectedState: state
        )
        let redirectURI = (provider == .onedrive)
            ? "http://localhost:\(boundPort)/"
            : "http://localhost:\(boundPort)/callback"

        onLog((fr ? "Écoute locale sur " : "Listening locally on ") + redirectURI)

        let authURL = Self.buildAuthURL(
            provider: provider,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: challenge
        )

        onLog(fr ? "Ouverture du navigateur…" : "Opening default browser…")
        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        onLog(fr ? "En attente de validation dans le navigateur…" : "Waiting for browser authorization…")
        let code = try await waitForOAuthCode()

        onLog(fr ? "Code reçu, échange contre les jetons…" : "Code received, exchanging for tokens…")
        let payload = try await Self.exchangeCode(
            provider: provider,
            code: code,
            redirectURI: redirectURI,
            codeVerifier: verifier
        )
        onLog(fr ? "Authentification réussie !" : "Authentication succeeded!")
        return payload
    }

    private func stopListener() {
        let l: NWListener? = lock.withLock {
            let current = listener
            listener = nil
            return current
        }
        l?.cancel()
    }

    private func startAndWaitForPort(
        _ nwListener: NWListener,
        fixedPort: UInt16?,
        expectedState: String
    ) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            let gate = ContinuationGate(cont)
            // Must be assigned BEFORE nwListener.start(queue:) or macOS raises POSIX EINVAL (error 22)
            nwListener.newConnectionHandler = { [weak self] conn in
                self?.handleIncomingConnection(conn, expectedState: expectedState)
            }
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = nwListener.port?.rawValue, p > 0 {
                        gate.finish(.success(p))
                    } else if let fp = fixedPort {
                        gate.finish(.success(fp))
                    } else {
                        gate.finish(.failure(CloudOAuthError.missingCallbackCode("No bound port")))
                    }
                case .failed(let err):
                    if let fp = fixedPort {
                        gate.finish(.failure(CloudOAuthError.portBusy(fp)))
                    } else {
                        gate.finish(.failure(err))
                    }
                case .cancelled:
                    gate.finish(.failure(CloudOAuthError.cancelled))
                default:
                    break
                }
            }
            nwListener.start(queue: DispatchQueue(label: "com.macsteam.cloudredirect.oauth"))
        }
    }

    private func waitForOAuthCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let gate = ContinuationGate(cont)
            guard installCodeGate(gate) else {
                gate.finish(.failure(CloudOAuthError.cancelled))
                return
            }
        }
    }

    private func handleIncomingConnection(_ conn: NWConnection, expectedState: String) {
        conn.start(queue: DispatchQueue(label: "com.macsteam.cloudredirect.oauth.conn"))
        readHTTPHead(conn, expectedState: expectedState, buffer: Data())
    }

    private func readHTTPHead(_ conn: NWConnection, expectedState: String, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self else {
                conn.cancel()
                return
            }
            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
            }
            let terminator = Data("\r\n\r\n".utf8)
            if accumulated.range(of: terminator) == nil && !isComplete && error == nil && accumulated.count < 32768 {
                self.readHTTPHead(conn, expectedState: expectedState, buffer: accumulated)
                return
            }
            guard let raw = String(data: accumulated, encoding: .utf8),
                  let firstLine = raw.components(separatedBy: "\r\n").first else {
                conn.cancel()
                return
            }

            // Parse `GET /callback?code=... HTTP/1.1`
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                Self.sendHTTP(conn, status: "400 Bad Request", contentType: "text/plain", body: "Bad request")
                return
            }
            let target = String(parts[1])
            guard let comps = URLComponents(string: "http://localhost" + target) else {
                Self.sendHTTP(conn, status: "400 Bad Request", contentType: "text/plain", body: "Bad URL")
                return
            }

            let items = comps.queryItems ?? []
            let code = items.first(where: { $0.name == "code" })?.value
            let err = items.first(where: { $0.name == "error" })?.value
            let state = items.first(where: { $0.name == "state" })?.value

            // Ignore favicon / preflight requests without OAuth params
            if code == nil && err == nil && state == nil {
                Self.sendHTTP(conn, status: "204 No Content", contentType: "text/plain", body: "")
                return
            }

            let fr = L10n.isFrench
            var resolvedCode: String? = code
            var resolvedErr: String? = err
            if state != expectedState {
                resolvedErr = "state_mismatch"
                resolvedCode = nil
            }

            let html: String
            if let resolvedCode, !resolvedCode.isEmpty {
                let t = fr ? "Connexion réussie" : "Authorization Successful"
                let p = fr ? "Vous pouvez fermer cet onglet et revenir à macSteam." : "You can close this tab and return to macSteam."
                html = "<html><body style=\"font-family:-apple-system,sans-serif;text-align:center;padding:60px;background:#1c1c1e;color:#fff\"><h1>\(t)</h1><p>\(p)</p></body></html>"
            } else {
                let t = fr ? "Échec de l'autorisation" : "Authorization Failed"
                let msg = resolvedErr ?? "unknown"
                html = "<html><body style=\"font-family:-apple-system,sans-serif;text-align:center;padding:60px;background:#1c1c1e;color:#fff\"><h1>\(t)</h1><p>\(msg)</p></body></html>"
            }

            Self.sendHTTP(conn, status: "200 OK", contentType: "text/html; charset=utf-8", body: html)

            let gate = self.takeCodeGate()

            if let resolvedCode, !resolvedCode.isEmpty {
                gate?.finish(.success(resolvedCode))
            } else {
                gate?.finish(.failure(CloudOAuthError.missingCallbackCode(resolvedErr ?? "unknown")))
            }
        }
    }

    private static func sendHTTP(_ conn: NWConnection, status: String, contentType: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var full = Data(header.utf8)
        full.append(bodyData)
        conn.send(content: full, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func buildAuthURL(
        provider: CloudProviderKind,
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) -> URL {
        var comps: URLComponents
        var items: [URLQueryItem]
        if provider == .onedrive {
            comps = URLComponents(string: oneDriveAuthURL)!
            items = [
                URLQueryItem(name: "client_id", value: oneDriveClientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: oneDriveScope),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]
        } else {
            comps = URLComponents(string: gdriveAuthURL)!
            items = [
                URLQueryItem(name: "client_id", value: gdriveClientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: gdriveScope),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]
        }
        comps.queryItems = items
        return comps.url!
    }

    private static func exchangeCode(
        provider: CloudProviderKind,
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> CloudTokenPayload {
        let tokenURL = URL(string: provider == .onedrive ? oneDriveTokenURL : gdriveTokenURL)!
        var fields: [(String, String)] = [
            ("code", code),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", codeVerifier),
        ]
        if provider == .onedrive {
            fields.append(("client_id", oneDriveClientId))
            fields.append(("client_secret", oneDriveClientSecret))
            fields.append(("scope", oneDriveScope))
        } else {
            fields.append(("client_id", gdriveClientId))
            fields.append(("client_secret", gdriveClientSecret))
        }
        return try await postTokenForm(url: tokenURL, fields: fields, fallbackRefresh: nil)
    }

    static func refreshAccessToken(provider: CloudProviderKind, existing: CloudTokenPayload) async throws -> CloudTokenPayload {
        let tokenURL = URL(string: provider == .onedrive ? oneDriveTokenURL : gdriveTokenURL)!
        var fields: [(String, String)] = [
            ("refresh_token", existing.refresh_token),
            ("grant_type", "refresh_token"),
        ]
        if provider == .onedrive {
            fields.append(("client_id", oneDriveClientId))
            fields.append(("client_secret", oneDriveClientSecret))
            fields.append(("scope", oneDriveScope))
        } else {
            fields.append(("client_id", gdriveClientId))
            fields.append(("client_secret", gdriveClientSecret))
        }
        return try await postTokenForm(url: tokenURL, fields: fields, fallbackRefresh: existing.refresh_token)
    }

    private static func postTokenForm(
        url: URL,
        fields: [(String, String)],
        fallbackRefresh: String?
    ) async throws -> CloudTokenPayload {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        req.httpBody = Data((comps.percentEncodedQuery ?? "").utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CloudOAuthError.tokenExchangeFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudOAuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
        }

        let access = (json["access_token"] as? String) ?? ""
        let refresh = ((json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? fallbackRefresh ?? ""
        let expiresIn = (json["expires_in"] as? NSNumber)?.int64Value ?? 3600
        guard !refresh.isEmpty else {
            throw CloudOAuthError.missingRefreshToken
        }
        let expiresAt = Int64(Date().timeIntervalSince1970) + expiresIn
        return CloudTokenPayload(access_token: access, refresh_token: refresh, expires_at: expiresAt)
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        let b64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return String(b64.prefix(length))
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Connection Tester (Folder, GDrive, OneDrive, R2, S3)

enum CloudRedirectTester {

    private final class InsecureTLSDelegate: NSObject, URLSessionDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    static func testConnection(config: CloudRedirectConfig) async throws -> String {
        let fr = L10n.isFrench
        switch config.provider {
        case .local:
            return fr ? "Mode local actif (aucun serveur distant)." : "Local-only mode active (no remote server)."

        case .folder:
            let fm = FileManager.default
            let dir = URL(fileURLWithPath: config.localFolderPath, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let probe = dir.appendingPathComponent(".cloudredirect_probe_\(UUID().uuidString)")
            try Data("ok".utf8).write(to: probe)
            try? fm.removeItem(at: probe)
            return fr ? "Dossier accessible en écriture : \(dir.path)" : "Writable folder verified: \(dir.path)"

        case .gdrive, .onedrive:
            guard let bottle = CrossOverInstaller.findSteamBottles().first else {
                throw CloudRedirectError.noBottleFound
            }
            guard var payload = CloudRedirectInstaller.readOAuthToken(for: config.provider, in: bottle) else {
                throw CloudOAuthError.testFailed(fr ? "Aucun jeton enregistré. Connectez-vous d'abord." : "No token saved yet. Sign in first.")
            }
            let now = Int64(Date().timeIntervalSince1970)
            if payload.access_token.isEmpty || payload.expires_at <= now + 60 {
                payload = try await CloudRedirectOAuthSession.refreshAccessToken(provider: config.provider, existing: payload)
                try CloudRedirectInstaller.saveOAuthToken(payload, for: config.provider, writeToBottle: false)
            }

            if config.provider == .gdrive {
                var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(displayName,emailAddress)")!)
                req.setValue("Bearer \(payload.access_token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    throw CloudOAuthError.testFailed("Google Drive HTTP \(code)")
                }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let user = obj["user"] as? [String: Any],
                   let email = user["emailAddress"] as? String {
                    return (fr ? "Connecté à Google Drive : " : "Connected to Google Drive: ") + email
                }
                return fr ? "Connexion Google Drive OK" : "Google Drive connection OK"
            } else {
                var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive")!)
                req.setValue("Bearer \(payload.access_token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    throw CloudOAuthError.testFailed("OneDrive HTTP \(code)")
                }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let owner = (obj["owner"] as? [String: Any])?["user"] as? [String: Any],
                   let display = owner["displayName"] as? String {
                    return (fr ? "Connecté à OneDrive : " : "Connected to OneDrive: ") + display
                }
                return fr ? "Connexion OneDrive OK" : "OneDrive connection OK"
            }

        case .r2, .s3:
            return try await testS3Compatible(config: config)
        }
    }

    private static func testS3Compatible(config: CloudRedirectConfig) async throws -> String {
        let fr = L10n.isFrench
        let isR2 = (config.provider == .r2)
        let bucket = config.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = config.accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = config.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty, !accessKey.isEmpty, !secretKey.isEmpty else {
            throw CloudOAuthError.testFailed(fr ? "Renseignez Bucket, Access Key ID et Secret Access Key." : "Fill in Bucket, Access Key ID, and Secret Access Key.")
        }

        var rawEndpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = "https"
        if rawEndpoint.isEmpty && isR2 {
            let acct = config.accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard acct.count == 32 else {
                throw CloudOAuthError.testFailed(fr ? "Account ID R2 invalide (32 hex attendus)." : "Invalid R2 Account ID (32 hex chars expected).")
            }
            rawEndpoint = "\(acct).r2.cloudflarestorage.com"
        }
        if let idx = rawEndpoint.range(of: "://") {
            scheme = String(rawEndpoint[..<idx.lowerBound]).lowercased()
            rawEndpoint = String(rawEndpoint[idx.upperBound...])
        }
        if let slash = rawEndpoint.firstIndex(of: "/") {
            rawEndpoint = String(rawEndpoint[..<slash])
        }
        guard !rawEndpoint.isEmpty else {
            throw CloudOAuthError.testFailed(fr ? "Endpoint manquant." : "Missing endpoint.")
        }

        let region = isR2 ? "auto" : (config.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "us-east-1" : config.region.trimmingCharacters(in: .whitespacesAndNewlines))
        let canonicalUri = "/\(bucket)"
        let canonicalQuery = "list-type=2&max-keys=1"
        guard let url = URL(string: "\(scheme)://\(rawEndpoint)\(canonicalUri)?\(canonicalQuery)") else {
            throw CloudOAuthError.testFailed("URL S3 invalide")
        }

        let now = Date()
        let amzFmt = DateFormatter()
        amzFmt.locale = Locale(identifier: "en_US_POSIX")
        amzFmt.timeZone = TimeZone(secondsFromGMT: 0)
        amzFmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = amzFmt.string(from: now)
        let dateStamp = String(amzDate.prefix(8))

        let payloadHash = isR2 || !config.s3SignPayload
            ? "UNSIGNED-PAYLOAD"
            : SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()

        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = "host:\(rawEndpoint)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let canonicalRequest = "GET\n\(canonicalUri)\n\(canonicalQuery)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalReqHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(canonicalReqHash)"

        func hmac(_ key: Data, _ msg: String) -> Data {
            let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: key))
            return Data(mac)
        }
        let kDate = hmac(Data(("AWS4" + secretKey).utf8), dateStamp)
        let kRegion = hmac(kDate, region)
        let kService = hmac(kRegion, "s3")
        let kSigning = hmac(kService, "aws4_request")
        let signature = hmac(kSigning, stringToSign).map { String(format: "%02x", $0) }.joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue(rawEndpoint, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let session: URLSession
        if !isR2 && config.s3AllowInsecureTls {
            session = URLSession(configuration: .ephemeral, delegate: InsecureTLSDelegate(), delegateQueue: nil)
        } else {
            session = URLSession.shared
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CloudOAuthError.testFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw CloudOAuthError.testFailed("HTTP \(http.statusCode): \(snippet)")
        }
        return (fr ? "Connexion bucket OK : " : "Bucket connection OK: ") + "\(rawEndpoint)/\(bucket)"
    }
}
