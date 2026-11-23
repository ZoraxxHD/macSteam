// Native CloudRedirect v2.6.8 integration for CrossOver Windows Steam bottles
import Foundation

enum CloudProviderKind: String, CaseIterable, Sendable {
    case local = "local"
    case folder = "folder"
    case gdrive = "gdrive"
    case onedrive = "onedrive"
    case r2 = "r2"
    case s3 = "s3"

    var displayName: String {
        let fr = L10n.isFrench
        switch self {
        case .local:    return fr ? "Mode local uniquement" : "Local Only"
        case .folder:   return fr ? "Dossier macOS / iCloud" : "macOS / iCloud Folder"
        case .gdrive:   return "Google Drive"
        case .onedrive: return "OneDrive"
        case .r2:       return "Cloudflare R2"
        case .s3:       return "S3 Compatible"
        }
    }

    var tokenFileName: String? {
        switch self {
        case .gdrive:   return "google_tokens.json"
        case .onedrive: return "onedrive_tokens.json"
        case .r2:       return "r2_credentials.json"
        case .s3:       return "s3_credentials.json"
        case .folder, .local: return nil
        }
    }
}

struct CloudRedirectConfig: Sendable {
    var provider: CloudProviderKind = .folder
    /// macOS POSIX folder path when provider == .folder (converted to Z:\... for CrossOver Wine).
    var localFolderPath: String = CloudRedirectInstaller.defaultLocalSyncFolder.path
    /// Google Drive concurrent upload cap in MB (24..64).
    var uploadInFlightMb: Int = 24

    // Sync & runtime toggles (matching CloudRedirect 2.6.8 cloud_intercept.cpp + SettingsPage.xaml.cs)
    var syncLuas: Bool = true
    var syncAchievements: Bool = true
    var syncPlaytime: Bool = true
    var showNonSteamGame: Bool = true
    var autoUpdateDll: Bool = true
    var parentalBypassPlaytime: Bool = false
    var parentalIgnorePlaytime: Bool = false

    // Cloudflare R2 fields (r2_credentials.json)
    var accountId: String = ""
    var r2AccessKeyId: String = ""
    var r2SecretAccessKey: String = ""
    var r2Bucket: String = ""
    var r2KeyPrefix: String = ""
    var r2Endpoint: String = ""

    // S3-compatible fields (s3_credentials.json)
    var s3Endpoint: String = ""
    var s3Region: String = "us-east-1"
    var s3Bucket: String = ""
    var s3KeyPrefix: String = ""
    var s3AccessKeyId: String = ""
    var s3SecretAccessKey: String = ""
    var s3CaCertPath: String = ""
    var s3SignPayload: Bool = false
    var s3AllowInsecureHttp: Bool = false
    var s3AllowInsecureTls: Bool = false

    // Compatibility helpers used by CloudRedirectTester
    var bucket: String { provider == .r2 ? r2Bucket : s3Bucket }
    var endpoint: String { provider == .r2 ? r2Endpoint : s3Endpoint }
    var region: String { s3Region }
    var accessKeyId: String { provider == .r2 ? r2AccessKeyId : s3AccessKeyId }
    var secretAccessKey: String { provider == .r2 ? r2SecretAccessKey : s3SecretAccessKey }
}

enum CloudRedirectError: LocalizedError {
    case noBottleFound
    case steamRunning
    case downloadFailed(String)
    case invalidInput(String)
    case commandFailed(String)

    var errorDescription: String? {
        let fr = L10n.isFrench
        switch self {
        case .noBottleFound:
            return fr
                ? "Aucune bouteille Steam CrossOver détectée. Installez d'abord Steam dans CrossOver."
                : "No CrossOver Steam bottle detected. Install Steam inside CrossOver first."
        case .steamRunning:
            return fr
                ? "Fermez Steam dans CrossOver avant d'installer ou modifier CloudRedirect."
                : "Quit Steam inside CrossOver before installing or modifying CloudRedirect."
        case .downloadFailed(let msg):
            return fr ? "Téléchargement CloudRedirect échoué : \(msg)" : "CloudRedirect download failed: \(msg)"
        case .invalidInput(let msg), .commandFailed(let msg):
            return msg
        }
    }
}

struct StoredCloudApp: Sendable {
    let appId: Int
    let accountId: String
    let changeNumber: String
    let fileCount: Int
    let totalBytes: Int64
    let folderURL: URL
}

struct Userdata760Entry: Sendable {
    let accountId: String
    let appId: String
    let fileCount: Int
    let totalBytes: Int64
    let remotePath: URL
}

enum CloudRedirectInstaller {

    struct Status: Sendable {
        let bottles: [CrossOverInstaller.Bottle]
        let dllInstalled: Bool
        let dllVersionHint: String?
        let cloudEnabledInToml: Bool
        let configExists: Bool
        let isSteamRunning: Bool
        let savedProviders: [CloudProviderKind]

        var hasBottle: Bool { !bottles.isEmpty }
        var isActive: Bool { dllInstalled && cloudEnabledInToml }
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/madoiscool/CloudRedirect/releases/latest")!
    static let fallbackDllURL = URL(string: "https://github.com/madoiscool/CloudRedirect/releases/download/v2.6.8/cloud_redirect.dll")!
    static let bundledVersion = "2.6.8"

    static var defaultLocalSyncFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CloudRedirect Saves", isDirectory: true)
    }

    // MARK: - Status & Paths

    static func inspectStatus() -> Status {
        let bottles = CrossOverInstaller.findSteamBottles()
        var dllInstalled = false
        var cloudEnabled = false
        var configExists = false
        var versionHint: String?
        var savedProviders: [CloudProviderKind] = []

        if let bottle = bottles.first {
            let dllURL = bottle.steamDir.appendingPathComponent("cloud_redirect.dll")
            dllInstalled = FileManager.default.fileExists(atPath: dllURL.path)
            cloudEnabled = isCloudEnabledInToml(steamDir: bottle.steamDir)
            configExists = FileManager.default.fileExists(atPath: configFileURL(in: bottle).path)

            let verURL = appDataDir(in: bottle).appendingPathComponent("dll_version.txt")
            if let v = try? String(contentsOf: verURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty {
                versionHint = v
            }

            for kind in [CloudProviderKind.gdrive, .onedrive, .r2, .s3] {
                if hasSavedCredentials(for: kind, in: bottle) {
                    savedProviders.append(kind)
                }
            }
        }

        return Status(
            bottles: bottles,
            dllInstalled: dllInstalled,
            dllVersionHint: versionHint,
            cloudEnabledInToml: cloudEnabled,
            configExists: configExists,
            isSteamRunning: CrossOverInstaller.isCrossOverSteamRunning(),
            savedProviders: savedProviders
        )
    }

    static func appDataDir(in bottle: CrossOverInstaller.Bottle) -> URL {
        let usersDir = bottle.root.appendingPathComponent("drive_c/users", isDirectory: true)
        let fm = FileManager.default
        let fallbackUser = "crossover"
        var chosenUser = fallbackUser

        if let entries = try? fm.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let candidates = entries.map(\.lastPathComponent).filter {
                $0.lowercased() != "public" && $0.lowercased() != "default" && $0.lowercased() != "all users"
            }
            if candidates.contains(fallbackUser) {
                chosenUser = fallbackUser
            } else if let first = candidates.first {
                chosenUser = first
            }
        }

        return usersDir
            .appendingPathComponent(chosenUser, isDirectory: true)
            .appendingPathComponent("AppData/Roaming/CloudRedirect", isDirectory: true)
    }

    static func wineUserName(in bottle: CrossOverInstaller.Bottle) -> String {
        appDataDir(in: bottle)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
    }

    static func configFileURL(in bottle: CrossOverInstaller.Bottle) -> URL {
        appDataDir(in: bottle).appendingPathComponent("config.json")
    }

    static func tokenFileURL(for kind: CloudProviderKind, in bottle: CrossOverInstaller.Bottle) -> URL? {
        guard let name = kind.tokenFileName else { return nil }
        return appDataDir(in: bottle).appendingPathComponent(name)
    }

    static func wineTokenPath(for kind: CloudProviderKind, in bottle: CrossOverInstaller.Bottle) -> String? {
        guard let name = kind.tokenFileName else { return nil }
        let user = wineUserName(in: bottle)
        return "C:\\users\\\(user)\\AppData\\Roaming\\CloudRedirect\\\(name)"
    }

    static func logFileURL(in bottle: CrossOverInstaller.Bottle) -> URL {
        let candidate = bottle.steamDir.appendingPathComponent("cloud_redirect/cloud_redirect.log")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return bottle.steamDir.appendingPathComponent("cloud_redirect.log")
    }

    /// Maps a macOS POSIX path (`/Users/foo/Bar`) to Wine `Z:\Users\foo\Bar`.
    static func macPathToWinePath(_ macPath: String) -> String {
        let trimmed = macPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 && trimmed[trimmed.index(after: trimmed.startIndex)] == ":" {
            return trimmed
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let normalized = expanded.hasPrefix("/") ? expanded : "/" + expanded
        return "Z:" + normalized.replacingOccurrences(of: "/", with: "\\")
    }

    /// Maps a Wine `Z:\Users\...` path back to a macOS POSIX path when possible.
    static func winePathToMacPath(_ winePath: String) -> String {
        let trimmed = winePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("z:\\") {
            return String(trimmed.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
        }
        if trimmed.lowercased().hasPrefix("z:/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    // MARK: - macOS Credential Mirror (untouched by Wine DPAPI encryption)

    /// `cloud_redirect.dll` inside CrossOver Wine automatically upgrades plaintext JSON
    /// token/credential files to Windows DPAPI binary blobs (`CryptProtectData`) on read
    /// and on every hourly token refresh. Keeping an owner-only (`0600`) JSON mirror in
    /// `~/Library/Application Support/macsteam/cloudredirect/` ensures macOS stays signed in
    /// permanently without breaking Wine's DPAPI files.
    static var macMirrorDir: URL {
        Paths.configDir.appendingPathComponent("cloudredirect", isDirectory: true)
    }

    static func mirrorTokenFileURL(for kind: CloudProviderKind) -> URL? {
        guard let name = kind.tokenFileName else { return nil }
        return macMirrorDir.appendingPathComponent(name)
    }

    private static func isPlainJSON(_ data: Data) -> Bool {
        for b in data {
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { continue }
            return b == 0x7B // '{'
        }
        return false
    }

    private static func writeMirrorData(_ data: Data, for kind: CloudProviderKind) {
        guard let url = mirrorTokenFileURL(for: kind) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: macMirrorDir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Reads plaintext JSON credentials/tokens for `kind`.
    /// 1) If the CrossOver bottle file is still plaintext JSON, mirrors it to macOS and returns it.
    /// 2) If Wine DPAPI-encrypted the bottle file (or it is missing), falls back to the macOS mirror
    ///    (and re-seeds the bottle if the bottle file does not exist).
    static func readCredentialJSON(for kind: CloudProviderKind, in bottle: CrossOverInstaller.Bottle?) -> Data? {
        let bottleURL = bottle.flatMap { tokenFileURL(for: kind, in: $0) }
        if let bottleURL,
           let data = try? Data(contentsOf: bottleURL),
           isPlainJSON(data) {
            writeMirrorData(data, for: kind)
            return data
        }

        if let mirrorURL = mirrorTokenFileURL(for: kind),
           let mirrorData = try? Data(contentsOf: mirrorURL),
           isPlainJSON(mirrorData) {
            // If the bottle lost its token file completely, restore it from the macOS mirror.
            if let bottleURL, !FileManager.default.fileExists(atPath: bottleURL.path) {
                try? FileManager.default.createDirectory(at: bottleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? mirrorData.write(to: bottleURL, options: .atomic)
            }
            return mirrorData
        }

        return nil
    }

    // MARK: - Token / Credential Helpers

    static func hasSavedCredentials(for kind: CloudProviderKind, in bottle: CrossOverInstaller.Bottle) -> Bool {
        switch kind {
        case .gdrive, .onedrive:
            return readOAuthToken(for: kind, in: bottle) != nil
        case .r2:
            guard let data = readCredentialJSON(for: .r2, in: bottle),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let ak = (obj["access_key_id"] as? String) ?? ""
            let sk = (obj["secret_access_key"] as? String) ?? ""
            let bk = (obj["bucket"] as? String) ?? ""
            return !ak.isEmpty && !sk.isEmpty && !bk.isEmpty
        case .s3:
            guard let data = readCredentialJSON(for: .s3, in: bottle),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let ak = (obj["access_key_id"] as? String) ?? ""
            let sk = (obj["secret_access_key"] as? String) ?? ""
            let bk = (obj["bucket"] as? String) ?? ""
            let ep = (obj["endpoint"] as? String) ?? ""
            return !ak.isEmpty && !sk.isEmpty && !bk.isEmpty && !ep.isEmpty
        case .folder, .local:
            return false
        }
    }

    static func readOAuthToken(for kind: CloudProviderKind, in bottle: CrossOverInstaller.Bottle) -> CloudTokenPayload? {
        guard kind == .gdrive || kind == .onedrive,
              let data = readCredentialJSON(for: kind, in: bottle) else { return nil }
        guard let decoded = try? JSONDecoder().decode(CloudTokenPayload.self, from: data),
              !decoded.refresh_token.isEmpty else { return nil }
        return decoded
    }

    static func saveOAuthToken(_ payload: CloudTokenPayload, for kind: CloudProviderKind, writeToBottle: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        // Always update the macOS mirror first (immune to Wine DPAPI re-encryption)
        writeMirrorData(data, for: kind)

        let bottles = CrossOverInstaller.findSteamBottles()
        guard !bottles.isEmpty else {
            if writeToBottle { throw CloudRedirectError.noBottleFound }
            return
        }

        for bottle in bottles {
            guard let url = tokenFileURL(for: kind, in: bottle) else { continue }
            let bottleExists = FileManager.default.fileExists(atPath: url.path)
            if writeToBottle || !bottleExists {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        }
    }

    static func revokeOAuthToken(for kind: CloudProviderKind) {
        if let mirrorURL = mirrorTokenFileURL(for: kind) {
            try? FileManager.default.removeItem(at: mirrorURL)
        }
        for bottle in CrossOverInstaller.findSteamBottles() {
            if let url = tokenFileURL(for: kind, in: bottle) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Reading & Writing Config

    static func loadConfig() -> CloudRedirectConfig {
        var cfg = CloudRedirectConfig()
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return cfg }

        if let data = try? Data(contentsOf: configFileURL(in: bottle)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let rawProv = obj["provider"] as? String,
               let prov = CloudProviderKind(rawValue: rawProv.lowercased()) {
                cfg.provider = prov
            }
            if let syncPath = obj["sync_path"] as? String, !syncPath.isEmpty {
                let mapped = winePathToMacPath(syncPath)
                if mapped.hasPrefix("/") {
                    cfg.localFolderPath = mapped
                }
            }
            if let mb = (obj["upload_inflight_mb"] as? NSNumber)?.intValue {
                cfg.uploadInFlightMb = min(64, max(24, mb))
            }
            if let v = obj["sync_luas"] as? Bool { cfg.syncLuas = v }
            if let v = obj["sync_achievements"] as? Bool { cfg.syncAchievements = v }
            if let v = obj["sync_playtime"] as? Bool { cfg.syncPlaytime = v }
            if let v = obj["show_non_steam_game"] as? Bool { cfg.showNonSteamGame = v }
            if let v = obj["auto_update_dll"] as? Bool { cfg.autoUpdateDll = v }
            if let v = obj["parental_bypass_playtime"] as? Bool { cfg.parentalBypassPlaytime = v }
            if let v = obj["parental_ignore_playtime"] as? Bool { cfg.parentalIgnorePlaytime = v }
        }

        // Load R2 credentials (with macOS mirror fallback if Wine DPAPI-encrypted the bottle file)
        if let data = readCredentialJSON(for: .r2, in: bottle),
           let r2 = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cfg.accountId = (r2["account_id"] as? String) ?? ""
            cfg.r2AccessKeyId = (r2["access_key_id"] as? String) ?? ""
            cfg.r2SecretAccessKey = (r2["secret_access_key"] as? String) ?? ""
            cfg.r2Bucket = (r2["bucket"] as? String) ?? ""
            cfg.r2KeyPrefix = (r2["key_prefix"] as? String) ?? ""
            cfg.r2Endpoint = (r2["endpoint"] as? String) ?? ""
        }

        // Load S3 credentials (with macOS mirror & legacy s3_config.json fallback)
        let legacyS3 = appDataDir(in: bottle).appendingPathComponent("s3_config.json")
        let s3Data: Data? = readCredentialJSON(for: .s3, in: bottle) ?? (try? Data(contentsOf: legacyS3)).flatMap { isPlainJSON($0) ? $0 : nil }
        if let data = s3Data,
           let s3 = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cfg.s3Endpoint = (s3["endpoint"] as? String) ?? ""
            cfg.s3Region = (s3["region"] as? String) ?? "us-east-1"
            cfg.s3Bucket = (s3["bucket"] as? String) ?? ""
            cfg.s3KeyPrefix = (s3["key_prefix"] as? String) ?? ""
            cfg.s3AccessKeyId = (s3["access_key_id"] as? String) ?? ""
            cfg.s3SecretAccessKey = (s3["secret_access_key"] as? String) ?? ""
            cfg.s3CaCertPath = (s3["ca_cert_path"] as? String).map(winePathToMacPath) ?? ""
            cfg.s3SignPayload = (s3["sign_payload"] as? Bool) ?? false
            cfg.s3AllowInsecureHttp = (s3["allow_insecure_http"] as? Bool) ?? false
            cfg.s3AllowInsecureTls = (s3["allow_insecure_tls"] as? Bool) ?? false
        }

        return cfg
    }

    static func saveConfig(_ cfg: CloudRedirectConfig, validateActiveProviderCredentials: Bool = true) throws {
        let bottles = CrossOverInstaller.findSteamBottles()
        guard !bottles.isEmpty else { throw CloudRedirectError.noBottleFound }

        let fr = L10n.isFrench
        if cfg.provider == .folder {
            let folderURL = URL(fileURLWithPath: cfg.localFolderPath, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } else if validateActiveProviderCredentials && cfg.provider == .r2 {
            let acct = cfg.accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ak = cfg.r2AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sk = cfg.r2SecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let bk = cfg.r2Bucket.trimmingCharacters(in: .whitespacesAndNewlines)
            let ep = cfg.r2Endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if ak.isEmpty || sk.isEmpty || bk.isEmpty || (acct.isEmpty && ep.isEmpty) {
                throw CloudRedirectError.invalidInput(fr
                    ? "Cloudflare R2 : renseignez Account ID (32 hex), Access Key ID, Secret Key et Bucket."
                    : "Cloudflare R2: fill in Account ID (32 hex), Access Key ID, Secret Key, and Bucket.")
            }
        } else if validateActiveProviderCredentials && cfg.provider == .s3 {
            let ep = cfg.s3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let reg = cfg.s3Region.trimmingCharacters(in: .whitespacesAndNewlines)
            let ak = cfg.s3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sk = cfg.s3SecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let bk = cfg.s3Bucket.trimmingCharacters(in: .whitespacesAndNewlines)
            if ep.isEmpty || reg.isEmpty || ak.isEmpty || sk.isEmpty || bk.isEmpty {
                throw CloudRedirectError.invalidInput(fr
                    ? "S3 Compatible : renseignez Endpoint, Région, Bucket, Access Key ID et Secret Key."
                    : "S3 Compatible: fill in Endpoint, Region, Bucket, Access Key ID, and Secret Key.")
            }
        }

        for bottle in bottles {
            try writeConfigFiles(cfg, in: bottle)
        }
    }

    private static func writeConfigFiles(_ cfg: CloudRedirectConfig, in bottle: CrossOverInstaller.Bottle) throws {
        let dir = appDataDir(in: bottle)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write r2_credentials.json if populated
        let r2Ak = cfg.r2AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let r2Bk = cfg.r2Bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r2Ak.isEmpty || !r2Bk.isEmpty {
            var r2Obj: [String: Any] = [
                "account_id": cfg.accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "access_key_id": r2Ak,
                "secret_access_key": cfg.r2SecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
                "bucket": r2Bk,
            ]
            let prefix = cfg.r2KeyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { r2Obj["key_prefix"] = prefix }
            let ep = cfg.r2Endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ep.isEmpty { r2Obj["endpoint"] = ep }
            if let url = tokenFileURL(for: .r2, in: bottle) {
                let d = try JSONSerialization.data(withJSONObject: r2Obj, options: [.prettyPrinted, .sortedKeys])
                writeMirrorData(d, for: .r2)
                try d.write(to: url, options: .atomic)
            }
        }

        // Write s3_credentials.json if populated
        let s3Ak = cfg.s3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let s3Bk = cfg.s3Bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s3Ak.isEmpty || !s3Bk.isEmpty {
            let reg = cfg.s3Region.trimmingCharacters(in: .whitespacesAndNewlines)
            var s3Obj: [String: Any] = [
                "endpoint": cfg.s3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                "region": reg.isEmpty ? "us-east-1" : reg,
                "bucket": s3Bk,
                "access_key_id": s3Ak,
                "secret_access_key": cfg.s3SecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            let prefix = cfg.s3KeyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { s3Obj["key_prefix"] = prefix }
            if cfg.s3SignPayload { s3Obj["sign_payload"] = true }
            if cfg.s3AllowInsecureHttp { s3Obj["allow_insecure_http"] = true }
            if cfg.s3AllowInsecureTls { s3Obj["allow_insecure_tls"] = true }
            let ca = cfg.s3CaCertPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ca.isEmpty { s3Obj["ca_cert_path"] = macPathToWinePath(ca) }

            if let url = tokenFileURL(for: .s3, in: bottle) {
                let d = try JSONSerialization.data(withJSONObject: s3Obj, options: [.prettyPrinted, .sortedKeys])
                writeMirrorData(d, for: .s3)
                try d.write(to: url, options: .atomic)
            }
        }

        // Preserve existing config.json keys & token_paths registry
        let cfgURL = configFileURL(in: bottle)
        var rootObj: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: cfgURL),
           let existingObj = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            rootObj = existingObj
        }

        var tokenPaths = (rootObj["token_paths"] as? [String: String]) ?? [:]
        for p in [CloudProviderKind.gdrive, .onedrive, .r2, .s3] {
            if let wp = wineTokenPath(for: p, in: bottle) {
                if p == cfg.provider || hasSavedCredentials(for: p, in: bottle) {
                    tokenPaths[p.rawValue] = wp
                }
            }
        }

        rootObj["provider"] = cfg.provider.rawValue
        rootObj["upload_inflight_mb"] = min(64, max(24, cfg.uploadInFlightMb))
        rootObj["sync_luas"] = cfg.syncLuas
        rootObj["sync_achievements"] = cfg.syncAchievements
        rootObj["sync_playtime"] = cfg.syncPlaytime
        rootObj["show_non_steam_game"] = cfg.showNonSteamGame
        rootObj["auto_update_dll"] = cfg.autoUpdateDll
        rootObj["parental_bypass_playtime"] = cfg.parentalBypassPlaytime
        rootObj["parental_ignore_playtime"] = cfg.parentalIgnorePlaytime
        rootObj["token_paths"] = tokenPaths

        switch cfg.provider {
        case .local:
            rootObj.removeValue(forKey: "sync_path")
        case .folder:
            rootObj["sync_path"] = macPathToWinePath(cfg.localFolderPath)
        case .gdrive, .onedrive, .r2, .s3:
            if let wp = wineTokenPath(for: cfg.provider, in: bottle) {
                rootObj["token_path"] = wp
            }
        }

        let data = try JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: cfgURL, options: .atomic)
    }

    // MARK: - Install, Update, Toggle in opensteamtool.toml

    static func installAndEnable(
        config: CloudRedirectConfig,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> String {
        let bottles = CrossOverInstaller.findSteamBottles()
        guard !bottles.isEmpty else { throw CloudRedirectError.noBottleFound }
        if CrossOverInstaller.isCrossOverSteamRunning() {
            throw CloudRedirectError.steamRunning
        }

        let fr = L10n.isFrench
        onProgress?(0.15, fr ? "Recherche de la dernière version de CloudRedirect…" : "Checking latest CloudRedirect release…")
        let (dllData, tag) = try await downloadLatestDll(onProgress: onProgress)

        onProgress?(0.78, fr ? "Déploiement de cloud_redirect.dll dans CrossOver…" : "Deploying cloud_redirect.dll into CrossOver…")
        for bottle in bottles {
            let dllURL = bottle.steamDir.appendingPathComponent("cloud_redirect.dll")
            try dllData.write(to: dllURL, options: .atomic)

            try setCloudEnabledInToml(true, steamDir: bottle.steamDir)

            let appData = appDataDir(in: bottle)
            try FileManager.default.createDirectory(at: appData, withIntermediateDirectories: true)
            let verURL = appData.appendingPathComponent("dll_version.txt")
            try? tag.write(to: verURL, atomically: true, encoding: .utf8)

            try writeConfigFiles(config, in: bottle)
        }

        onProgress?(1.0, fr ? "CloudRedirect \(tag) activé" : "CloudRedirect \(tag) enabled")
        return tag
    }

    static func setEnabled(_ enabled: Bool) throws {
        let bottles = CrossOverInstaller.findSteamBottles()
        guard !bottles.isEmpty else { throw CloudRedirectError.noBottleFound }
        if CrossOverInstaller.isCrossOverSteamRunning() {
            throw CloudRedirectError.steamRunning
        }
        for bottle in bottles {
            try setCloudEnabledInToml(enabled, steamDir: bottle.steamDir)
        }
    }

    static func isCloudEnabledInToml(steamDir: URL) -> Bool {
        let tomlURL = steamDir.appendingPathComponent("opensteamtool.toml")
        guard let text = try? String(contentsOf: tomlURL, encoding: .utf8) else { return false }
        return extractCloudSectionEnabled(from: text) ?? false
    }

    static func extractCloudSectionEnabled(from toml: String) -> Bool? {
        var inCloud = false
        for rawLine in toml.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                inCloud = (line.lowercased() == "[cloud]")
                continue
            }
            if inCloud {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 && parts[0].lowercased() == "enabled" {
                    return parts[1].lowercased() == "true"
                }
            }
        }
        return nil
    }

    static func setCloudEnabledInToml(_ enabled: Bool, steamDir: URL) throws {
        let tomlURL = steamDir.appendingPathComponent("opensteamtool.toml")
        var text = (try? String(contentsOf: tomlURL, encoding: .utf8)) ?? """
        [manifest]
        provider = "wudrm"

        [lua]
        paths = ["config/stplug-in"]
        """

        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        var inCloud = false
        var sawCloudSection = false
        var wroteEnabledInCloud = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if inCloud && !wroteEnabledInCloud {
                    out.append("enabled = \(enabled ? "true" : "false")")
                    wroteEnabledInCloud = true
                }
                if trimmed.lowercased() == "[cloud]" {
                    inCloud = true
                    sawCloudSection = true
                } else {
                    inCloud = false
                }
                out.append(rawLine)
                continue
            }

            if inCloud {
                let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 && parts[0].lowercased() == "enabled" {
                    out.append("enabled = \(enabled ? "true" : "false")")
                    wroteEnabledInCloud = true
                    continue
                }
            }
            out.append(rawLine)
        }

        if inCloud && !wroteEnabledInCloud {
            out.append("enabled = \(enabled ? "true" : "false")")
            wroteEnabledInCloud = true
        }

        if !sawCloudSection {
            while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                out.removeLast()
            }
            out.append("")
            out.append("[cloud]")
            out.append("enabled = \(enabled ? "true" : "false")")
        }

        text = out.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        try text.write(to: tomlURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Local Storage Browser, Backups, Reset & 760 Cleanup

    static func scanStoredApps() -> [StoredCloudApp] {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return [] }
        let storageDir = bottle.steamDir.appendingPathComponent("cloud_redirect/storage", isDirectory: true)
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
            return []
        }

        let metaNames: Set<String> = ["cn.dat", "cn.cloudredirect", "root_token.dat", "file_tokens.dat", "manifest.cloudredirect"]
        var results: [StoredCloudApp] = []

        for accountDir in accounts {
            let accountId = accountDir.lastPathComponent
            guard let appDirs = try? fm.contentsOfDirectory(at: accountDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { continue }
            for appDir in appDirs {
                guard let appId = Int(appDir.lastPathComponent), appId > 0 else { continue }
                var cn = ""
                for candidate in ["cn.cloudredirect", "cn.dat"] {
                    let u = appDir.appendingPathComponent(candidate)
                    if let s = try? String(contentsOf: u, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                        cn = s
                        break
                    }
                }
                var fileCount = 0
                var totalBytes: Int64 = 0
                if let e = fm.enumerator(at: appDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                    while let item = e.nextObject() as? URL {
                        if let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                           vals.isRegularFile == true,
                           !metaNames.contains(item.lastPathComponent) {
                            fileCount += 1
                            totalBytes += Int64(vals.fileSize ?? 0)
                        }
                    }
                }
                results.append(StoredCloudApp(
                    appId: appId,
                    accountId: accountId,
                    changeNumber: cn,
                    fileCount: fileCount,
                    totalBytes: totalBytes,
                    folderURL: appDir
                ))
            }
        }
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    static func deleteStoredApp(_ app: StoredCloudApp) throws {
        if CrossOverInstaller.isCrossOverSteamRunning() {
            throw CloudRedirectError.steamRunning
        }
        try FileManager.default.removeItem(at: app.folderURL)
    }

    static func exportBackupZip(from sourceDir: URL, to zipURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDir.path, zipURL.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw CloudRedirectError.commandFailed("ditto exited with status \(proc.terminationStatus)")
        }
    }

    static func resetLocalStorage() throws -> Int {
        if CrossOverInstaller.isCrossOverSteamRunning() {
            throw CloudRedirectError.steamRunning
        }
        let bottles = CrossOverInstaller.findSteamBottles()
        guard !bottles.isEmpty else { throw CloudRedirectError.noBottleFound }
        var removed = 0
        let fm = FileManager.default
        for bottle in bottles {
            let root = bottle.steamDir.appendingPathComponent("cloud_redirect", isDirectory: true)
            for sub in ["storage", "blobs", "saves"] {
                let target = root.appendingPathComponent(sub, isDirectory: true)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                    removed += 1
                }
            }
        }
        return removed
    }

    static func scanUserdata760() -> [Userdata760Entry] {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return [] }
        let userdata = bottle.steamDir.appendingPathComponent("userdata", isDirectory: true)
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }

        var entries: [Userdata760Entry] = []
        for acc in accounts {
            let accountId = acc.lastPathComponent
            let cloud760 = acc.appendingPathComponent("760/remote", isDirectory: true)
            guard let appDirs = try? fm.contentsOfDirectory(at: cloud760, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for appDir in appDirs {
                var count = 0
                var bytes: Int64 = 0
                if let e = fm.enumerator(at: appDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                    while let f = e.nextObject() as? URL {
                        if let rv = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                           rv.isRegularFile == true {
                            count += 1
                            bytes += Int64(rv.fileSize ?? 0)
                        }
                    }
                }
                entries.append(Userdata760Entry(
                    accountId: accountId,
                    appId: appDir.lastPathComponent,
                    fileCount: count,
                    totalBytes: bytes,
                    remotePath: appDir
                ))
            }
        }
        return entries.sorted { $0.totalBytes > $1.totalBytes }
    }

    static func cleanAllUserdata760WithBackup() throws -> (cleanedCount: Int, backupURL: URL?) {
        if CrossOverInstaller.isCrossOverSteamRunning() {
            throw CloudRedirectError.steamRunning
        }
        guard let bottle = CrossOverInstaller.findSteamBottles().first else {
            throw CloudRedirectError.noBottleFound
        }
        let entries = scanUserdata760()
        guard !entries.isEmpty else { return (0, nil) }

        let backupsDir = bottle.steamDir.appendingPathComponent("cloud_redirect/backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let backupZip = backupsDir.appendingPathComponent("userdata760-\(fmt.string(from: Date())).zip")
        try? exportBackupZip(from: bottle.steamDir.appendingPathComponent("userdata"), to: backupZip)

        var count = 0
        for e in entries {
            try? FileManager.default.removeItem(at: e.remotePath)
            count += 1
        }
        return (count, FileManager.default.fileExists(atPath: backupZip.path) ? backupZip : nil)
    }

    // MARK: - GitHub Release Download

    private static func downloadLatestDll(
        onProgress: (@Sendable (Double, String) -> Void)?
    ) async throws -> (Data, String) {
        let fr = L10n.isFrench
        var assetURL = fallbackDllURL
        var tagName = "v\(bundledVersion)"

        var apiReq = URLRequest(url: latestReleaseAPI)
        apiReq.timeoutInterval = 20
        apiReq.setValue("macSteam/1.0", forHTTPHeaderField: "User-Agent")

        if let (metaData, metaResp) = try? await URLSession.shared.data(for: apiReq),
           let http = metaResp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            if let tag = json["tag_name"] as? String, !tag.isEmpty {
                tagName = tag
            }
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name == "cloud_redirect.dll",
                       let dl = asset["browser_download_url"] as? String,
                       let u = URL(string: dl) {
                        assetURL = u
                        break
                    }
                }
            }
        }

        onProgress?(0.40, fr ? "Téléchargement de cloud_redirect.dll (\(tagName))…" : "Downloading cloud_redirect.dll (\(tagName))…")

        var dlReq = URLRequest(url: assetURL)
        dlReq.timeoutInterval = 120
        dlReq.setValue("macSteam/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: dlReq)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 10_000 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudRedirectError.downloadFailed("HTTP \(code)")
        }

        guard data.first == 0x4D && data.dropFirst().first == 0x5A else {
            throw CloudRedirectError.downloadFailed(fr ? "Fichier DLL invalide" : "Invalid DLL binary")
        }

        return (data, tagName)
    }
}
