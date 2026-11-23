// Remote CloudRedirect explorer & sync client (Google Drive, OneDrive, Folder, Local fallback)
import Foundation

struct CloudAppRecord: Sendable {
    let appId: Int
    let accountId: String
    let changeNumber: Int
    let fileCount: Int
    let totalBytes: Int64
    let isLocal: Bool
    let isCloud: Bool
    let localFolderURL: URL?
    let remoteId: String?
}

struct CloudAchievementEntry: Sendable {
    let statId: UInt32
    let bit: Int
    let name: String
    let unlockUnix: UInt32
    let unlocked: Bool
}

struct CloudStatAppRecord: Sendable {
    let appId: Int
    let accountId: String
    let minutesForever: UInt32
    let lastPlayedUnix: UInt32
    let achievements: [CloudAchievementEntry]
}

struct CloudSnapshot: Sendable {
    let provider: CloudProviderKind
    let authenticated: Bool
    let statusText: String
    let crossoverAccountIds: [String]
    let cloudAccountIds: [String]
    let apps: [CloudAppRecord]
    let stats: [CloudStatAppRecord]
    let errorMessage: String?
}

enum CloudRedirectCloudClient {

    // MARK: - Unified Snapshot (Cloud + Local CrossOver)

    static func fetchSnapshot(config: CloudRedirectConfig) async -> CloudSnapshot {
        let localApps = CloudRedirectInstaller.scanStoredApps()
        let localStats = scanLocalStats()
        let crossoverAccounts = scanCrossOverAccountIds()

        var cloudApps: [CloudAppRecord] = []
        var cloudStats: [CloudStatAppRecord] = []
        var cloudAccounts: Set<String> = []
        var authenticated = false
        var statusText = config.provider.displayName
        var errorMessage: String? = nil

        let fr = L10n.isFrench

        switch config.provider {
        case .local:
            authenticated = true
            statusText = fr ? "Mode local uniquement" : "Local Only"

        case .folder:
            let dir = URL(fileURLWithPath: config.localFolderPath, isDirectory: true)
            let exists = FileManager.default.fileExists(atPath: dir.path)
            authenticated = exists
            statusText = exists
                ? (fr ? "Dossier accessible" : "Folder accessible")
                : (fr ? "Dossier introuvable" : "Folder not found")
            if exists {
                let res = scanFolderBackend(root: dir)
                cloudApps = res.apps
                cloudStats = res.stats
                cloudAccounts = Set(res.accounts)
            }

        case .gdrive:
            if let bottle = CrossOverInstaller.findSteamBottles().first,
               var token = CloudRedirectInstaller.readOAuthToken(for: .gdrive, in: bottle) {
                do {
                    token = try await ensureFreshToken(token, provider: .gdrive)
                    authenticated = true
                    statusText = fr ? "Google Drive — Connecté" : "Google Drive — Authenticated"
                    let res = try await fetchGDriveSnapshot(accessToken: token.access_token)
                    cloudApps = res.apps
                    cloudStats = res.stats
                    cloudAccounts = Set(res.accounts)
                } catch {
                    statusText = fr ? "Google Drive — Erreur" : "Google Drive — Error"
                    errorMessage = error.localizedDescription
                }
            } else {
                statusText = fr ? "Google Drive — Non connecté" : "Google Drive — Not signed in"
            }

        case .onedrive:
            if let bottle = CrossOverInstaller.findSteamBottles().first,
               var token = CloudRedirectInstaller.readOAuthToken(for: .onedrive, in: bottle) {
                do {
                    token = try await ensureFreshToken(token, provider: .onedrive)
                    authenticated = true
                    statusText = fr ? "OneDrive — Connecté" : "OneDrive — Authenticated"
                    let res = try await fetchOneDriveSnapshot(accessToken: token.access_token)
                    cloudApps = res.apps
                    cloudStats = res.stats
                    cloudAccounts = Set(res.accounts)
                } catch {
                    statusText = fr ? "OneDrive — Erreur" : "OneDrive — Error"
                    errorMessage = error.localizedDescription
                }
            } else {
                statusText = fr ? "OneDrive — Non connecté" : "OneDrive — Not signed in"
            }

        case .r2, .s3:
            if let bottle = CrossOverInstaller.findSteamBottles().first,
               CloudRedirectInstaller.hasSavedCredentials(for: config.provider, in: bottle) {
                authenticated = true
                statusText = "\(config.provider.displayName) — " + (fr ? "Configuré" : "Configured")
            } else {
                statusText = "\(config.provider.displayName) — " + (fr ? "Non configuré" : "Not configured")
            }
        }

        // Merge local + cloud apps keyed by (accountId, appId)
        var mergedApps: [String: CloudAppRecord] = [:]
        for c in cloudApps {
            mergedApps["\(c.accountId)/\(c.appId)"] = c
        }
        for l in localApps {
            let key = "\(l.accountId)/\(l.appId)"
            let localCn = Int(l.changeNumber) ?? 0
            if let existing = mergedApps[key] {
                mergedApps[key] = CloudAppRecord(
                    appId: existing.appId,
                    accountId: existing.accountId,
                    changeNumber: max(existing.changeNumber, localCn),
                    fileCount: max(existing.fileCount, l.fileCount),
                    totalBytes: max(existing.totalBytes, l.totalBytes),
                    isLocal: true,
                    isCloud: true,
                    localFolderURL: l.folderURL,
                    remoteId: existing.remoteId
                )
            } else {
                mergedApps[key] = CloudAppRecord(
                    appId: l.appId,
                    accountId: l.accountId,
                    changeNumber: localCn,
                    fileCount: l.fileCount,
                    totalBytes: l.totalBytes,
                    isLocal: true,
                    isCloud: false,
                    localFolderURL: l.folderURL,
                    remoteId: nil
                )
            }
            cloudAccounts.insert(l.accountId)
        }

        // Merge cloud stats + local stats keyed by (accountId, appId); cloud/newer playtime wins
        var mergedStats: [String: CloudStatAppRecord] = [:]
        for l in localStats {
            mergedStats["\(l.accountId)/\(l.appId)"] = l
            cloudAccounts.insert(l.accountId)
        }
        for c in cloudStats {
            let key = "\(c.accountId)/\(c.appId)"
            if let existing = mergedStats[key] {
                if c.minutesForever >= existing.minutesForever || c.achievements.count >= existing.achievements.count {
                    mergedStats[key] = c
                }
            } else {
                mergedStats[key] = c
            }
            cloudAccounts.insert(c.accountId)
        }

        let sortedApps = mergedApps.values.sorted {
            if $0.accountId != $1.accountId { return $0.accountId < $1.accountId }
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.appId < $1.appId
        }
        let sortedStats = mergedStats.values.sorted {
            if $0.accountId != $1.accountId { return $0.accountId < $1.accountId }
            if $0.minutesForever != $1.minutesForever { return $0.minutesForever > $1.minutesForever }
            return $0.appId < $1.appId
        }

        return CloudSnapshot(
            provider: config.provider,
            authenticated: authenticated,
            statusText: statusText,
            crossoverAccountIds: crossoverAccounts,
            cloudAccountIds: cloudAccounts.sorted(),
            apps: sortedApps,
            stats: sortedStats,
            errorMessage: errorMessage
        )
    }

    // MARK: - CrossOver Local Helpers

    static func scanCrossOverAccountIds() -> [String] {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return [] }
        let userdata = bottle.steamDir.appendingPathComponent("userdata", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        return dirs.map(\.lastPathComponent).filter { $0.allSatisfy(\.isNumber) && !$0.isEmpty && $0 != "0" }.sorted()
    }

    private static func scanLocalStats() -> [CloudStatAppRecord] {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return [] }
        let statsRoot = bottle.steamDir.appendingPathComponent("cloud_redirect/stats", isDirectory: true)
        let fm = FileManager.default
        guard let accountDirs = try? fm.contentsOfDirectory(at: statsRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        var results: [CloudStatAppRecord] = []
        for acctDir in accountDirs {
            let accountId = acctDir.lastPathComponent
            guard accountId.allSatisfy(\.isNumber), !accountId.isEmpty else { continue }
            guard let files = try? fm.contentsOfDirectory(at: acctDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for f in files where f.pathExtension.lowercased() == "json" {
                let stem = f.deletingPathExtension().lastPathComponent
                guard let appId = Int(stem), appId > 0,
                      let data = try? Data(contentsOf: f),
                      let rec = parseAppStatsJSON(data, accountId: accountId, appId: appId) else { continue }
                results.append(rec)
            }
        }
        return results
    }

    private static func ensureFreshToken(_ token: CloudTokenPayload, provider: CloudProviderKind) async throws -> CloudTokenPayload {
        let now = Int64(Date().timeIntervalSince1970)
        if !token.access_token.isEmpty && token.expires_at > now + 90 {
            return token
        }
        let refreshed = try await CloudRedirectOAuthSession.refreshAccessToken(provider: provider, existing: token)
        try? CloudRedirectInstaller.saveOAuthToken(refreshed, for: provider, writeToBottle: false)
        return refreshed
    }

    // MARK: - Stats JSON Parsing (`<appId>.json` or `<account>/0/stats.json`)

    private static func parseAccountStatsBundle(_ data: Data, accountId: String) -> [CloudStatAppRecord] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [CloudStatAppRecord] = []
        for (appKey, val) in obj {
            guard let appId = Int(appKey), appId > 0, let dict = val as? [String: Any] else { continue }
            out.append(parseAppStatsDict(dict, accountId: accountId, appId: appId))
        }
        return out
    }

    private static func parseAppStatsJSON(_ data: Data, accountId: String, appId: Int) -> CloudStatAppRecord? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseAppStatsDict(dict, accountId: accountId, appId: appId)
    }

    private static func parseAppStatsDict(_ dict: [String: Any], accountId: String, appId: Int) -> CloudStatAppRecord {
        var minutesForever: UInt32 = 0
        var lastPlayed: UInt32 = 0
        if let pt = dict["playtime"] as? [String: Any] {
            minutesForever = (pt["minutes_forever"] as? NSNumber)?.uint32Value ?? 0
            lastPlayed = (pt["last_played"] as? NSNumber)?.uint32Value ?? 0
        }

        var achievements: [CloudAchievementEntry] = []
        if let achs = dict["achievements"] as? [[String: Any]] {
            for a in achs {
                let statId = (a["stat_id"] as? NSNumber)?.uint32Value ?? 0
                let bits = (a["bits"] as? NSNumber)?.uint32Value ?? 0
                let times = (a["unlock_times"] as? [NSNumber])?.map { $0.uint32Value } ?? []
                let names = (a["names"] as? [String]) ?? []

                for bit in 0..<32 {
                    let unlocked = (bits & (1 << bit)) != 0
                    let t = bit < times.count ? times[bit] : 0
                    if !unlocked && t == 0 { continue }
                    let rawName = bit < names.count ? names[bit] : ""
                    let display = rawName.isEmpty ? "Achievement #\(statId).\(bit)" : rawName
                    achievements.append(CloudAchievementEntry(
                        statId: statId,
                        bit: bit,
                        name: display,
                        unlockUnix: t,
                        unlocked: unlocked
                    ))
                }
            }
        }
        achievements.sort { $0.unlockUnix > $1.unlockUnix }

        return CloudStatAppRecord(
            appId: appId,
            accountId: accountId,
            minutesForever: minutesForever,
            lastPlayedUnix: lastPlayed,
            achievements: achievements
        )
    }

    private static func parseStateMetadata(_ data: Data) -> (cn: Int, files: Int, bytes: Int64) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (0, 0, 0)
        }
        let cn = (obj["cn"] as? NSNumber)?.intValue ?? 0
        if let files = obj["files"] as? [String: Any] {
            var totalBytes: Int64 = 0
            for (_, val) in files {
                if let f = val as? [String: Any], let sz = f["size"] as? NSNumber {
                    totalBytes += sz.int64Value
                }
            }
            return (cn, files.count, totalBytes)
        }
        return (cn, 0, 0)
    }

    // MARK: - Folder Backend

    private static func scanFolderBackend(root: URL) -> (accounts: [String], apps: [CloudAppRecord], stats: [CloudStatAppRecord]) {
        let fm = FileManager.default
        let cloudSub = root.appendingPathComponent("CloudRedirect", isDirectory: true)
        let base = fm.fileExists(atPath: cloudSub.path) ? cloudSub : root

        guard let acctDirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return ([], [], [])
        }
        var accounts: [String] = []
        var apps: [CloudAppRecord] = []
        var stats: [CloudStatAppRecord] = []

        for acctDir in acctDirs {
            let accountId = acctDir.lastPathComponent
            guard accountId.allSatisfy(\.isNumber), !accountId.isEmpty else { continue }
            accounts.append(accountId)

            let statsFile = acctDir.appendingPathComponent("0/stats.json")
            if let sData = try? Data(contentsOf: statsFile) {
                stats.append(contentsOf: parseAccountStatsBundle(sData, accountId: accountId))
            }

            guard let appDirs = try? fm.contentsOfDirectory(at: acctDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for appDir in appDirs {
                guard let appId = Int(appDir.lastPathComponent), appId > 0 else { continue }
                var cn = 0
                var count = 0
                var bytes: Int64 = 0
                let stateURL = appDir.appendingPathComponent("state.cloudredirect")
                if let sData = try? Data(contentsOf: stateURL) {
                    let meta = parseStateMetadata(sData)
                    cn = meta.cn
                    count = meta.files
                    bytes = meta.bytes
                }
                apps.append(CloudAppRecord(
                    appId: appId,
                    accountId: accountId,
                    changeNumber: cn,
                    fileCount: count,
                    totalBytes: bytes,
                    isLocal: false,
                    isCloud: true,
                    localFolderURL: nil,
                    remoteId: appDir.path
                ))
            }
        }
        return (accounts, apps, stats)
    }

    // MARK: - Google Drive REST v3

    private struct DriveItem: Sendable {
        let id: String
        let name: String
        let mimeType: String
    }

    private static func gdriveListChildren(parentId: String, accessToken: String, onlyFolders: Bool? = nil) async throws -> [DriveItem] {
        var items: [DriveItem] = []
        var pageToken: String? = nil

        repeat {
            var q = "'\(parentId)' in parents and trashed=false"
            if let onlyFolders {
                q += onlyFolders
                    ? " and mimeType='application/vnd.google-apps.folder'"
                    : " and mimeType!='application/vnd.google-apps.folder'"
            }
            var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var queryItems = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType)"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            comps.queryItems = queryItems

            var req = URLRequest(url: comps.url!)
            req.timeoutInterval = 25
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                throw CloudOAuthError.testFailed("Google Drive list HTTP \(code)")
            }
            if let files = json["files"] as? [[String: Any]] {
                for f in files {
                    if let id = f["id"] as? String,
                       let name = f["name"] as? String,
                       let mime = f["mimeType"] as? String {
                        items.append(DriveItem(id: id, name: name, mimeType: mime))
                    }
                }
            }
            pageToken = (json["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil

        return items
    }

    private static func gdriveFindRootFolder(accessToken: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "name='CloudRedirect' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "10"),
        ]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 20
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudOAuthError.testFailed("Google Drive root lookup HTTP \(code)")
        }
        return files.first?["id"] as? String
    }

    private static func gdriveDownloadFile(fileId: String, accessToken: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!)
        req.timeoutInterval = 25
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudOAuthError.testFailed("Google Drive download HTTP \(code)")
        }
        return data
    }

    private static func fetchGDriveSnapshot(accessToken: String) async throws -> (accounts: [String], apps: [CloudAppRecord], stats: [CloudStatAppRecord]) {
        guard let rootId = try await gdriveFindRootFolder(accessToken: accessToken) else {
            return ([], [], [])
        }

        let accountFolders = try await gdriveListChildren(parentId: rootId, accessToken: accessToken, onlyFolders: true)
            .filter { $0.name.allSatisfy(\.isNumber) && !$0.name.isEmpty }

        var accounts: [String] = []
        var apps: [CloudAppRecord] = []
        var stats: [CloudStatAppRecord] = []

        for acctFolder in accountFolders {
            let accountId = acctFolder.name
            accounts.append(accountId)

            let children = try await gdriveListChildren(parentId: acctFolder.id, accessToken: accessToken, onlyFolders: true)

            // Account-scope stats: <accountId>/0/stats.json
            if let zeroFolder = children.first(where: { $0.name == "0" }) {
                let zeroFiles = try await gdriveListChildren(parentId: zeroFolder.id, accessToken: accessToken, onlyFolders: false)
                if let statsFile = zeroFiles.first(where: { $0.name == "stats.json" }),
                   let data = try? await gdriveDownloadFile(fileId: statsFile.id, accessToken: accessToken) {
                    stats.append(contentsOf: parseAccountStatsBundle(data, accountId: accountId))
                }
            }

            let appFolders = children.filter { $0.name != "0" && (Int($0.name) ?? 0) > 0 }
            // Cap concurrent folder fetches to 4 workers to avoid CPU & Wi-Fi energy spikes
            let maxWorkers = 4
            let fetchedForAcct: [(CloudAppRecord, CloudStatAppRecord?)] = await withTaskGroup(of: (CloudAppRecord, CloudStatAppRecord?).self) { group in
                var out: [(CloudAppRecord, CloudStatAppRecord?)] = []
                var nextIdx = 0

                func enqueueNext() {
                    guard nextIdx < appFolders.count else { return }
                    let appFolder = appFolders[nextIdx]
                    nextIdx += 1
                    let appId = Int(appFolder.name) ?? 0
                    group.addTask {
                        var cn = 0
                        var fileCount = 0
                        var totalBytes: Int64 = 0
                        var legacyStat: CloudStatAppRecord? = nil

                        if let appFiles = try? await gdriveListChildren(parentId: appFolder.id, accessToken: accessToken, onlyFolders: false) {
                            if let stateFile = appFiles.first(where: { $0.name == "state.cloudredirect" }),
                               let data = try? await gdriveDownloadFile(fileId: stateFile.id, accessToken: accessToken) {
                                let meta = parseStateMetadata(data)
                                cn = meta.cn
                                fileCount = meta.files
                                totalBytes = meta.bytes
                            } else if let cnFile = appFiles.first(where: { $0.name == "cn.cloudredirect" || $0.name == "cn.dat" }),
                                      let data = try? await gdriveDownloadFile(fileId: cnFile.id, accessToken: accessToken),
                                      let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                cn = Int(s) ?? 0
                            }
                            if let statFile = appFiles.first(where: { $0.name == "stats.json" }),
                               let data = try? await gdriveDownloadFile(fileId: statFile.id, accessToken: accessToken) {
                                legacyStat = parseAppStatsJSON(data, accountId: accountId, appId: appId)
                            }
                        }

                        let rec = CloudAppRecord(
                            appId: appId,
                            accountId: accountId,
                            changeNumber: cn,
                            fileCount: fileCount,
                            totalBytes: totalBytes,
                            isLocal: false,
                            isCloud: true,
                            localFolderURL: nil,
                            remoteId: appFolder.id
                        )
                        return (rec, legacyStat)
                    }
                }

                for _ in 0..<min(maxWorkers, appFolders.count) { enqueueNext() }
                for await pair in group {
                    out.append(pair)
                    enqueueNext()
                }
                return out
            }

            let existingStatIds = Set(stats.filter { $0.accountId == accountId }.map(\.appId))
            for (rec, legacyStat) in fetchedForAcct {
                apps.append(rec)
                if let legacyStat, !existingStatIds.contains(legacyStat.appId) {
                    stats.append(legacyStat)
                }
            }
        }

        return (accounts, apps, stats)
    }

    // MARK: - OneDrive Graph API Snapshot

    private static func fetchOneDriveSnapshot(accessToken: String) async throws -> (accounts: [String], apps: [CloudAppRecord], stats: [CloudStatAppRecord]) {
        func listChildren(path: String) async throws -> [[String: Any]] {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let url = URL(string: "https://graph.microsoft.com/v1.0/me/drive/root:/\(encoded):/children?$top=1000")!
            var req = URLRequest(url: url)
            req.timeoutInterval = 25
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return [] }
            if http.statusCode == 404 { return [] }
            guard (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = json["value"] as? [[String: Any]] else {
                throw CloudOAuthError.testFailed("OneDrive HTTP \(http.statusCode)")
            }
            return value
        }

        func downloadPath(_ path: String) async -> Data? {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let url = URL(string: "https://graph.microsoft.com/v1.0/me/drive/root:/\(encoded):/content")!
            var req = URLRequest(url: url)
            req.timeoutInterval = 25
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        }

        let acctItems = try await listChildren(path: "CloudRedirect")
        var accounts: [String] = []
        var apps: [CloudAppRecord] = []
        var stats: [CloudStatAppRecord] = []

        for item in acctItems {
            guard item["folder"] != nil,
                  let accountId = item["name"] as? String,
                  accountId.allSatisfy(\.isNumber), !accountId.isEmpty else { continue }
            accounts.append(accountId)

            if let sData = await downloadPath("CloudRedirect/\(accountId)/0/stats.json") {
                stats.append(contentsOf: parseAccountStatsBundle(sData, accountId: accountId))
            }

            let appItems = (try? await listChildren(path: "CloudRedirect/\(accountId)")) ?? []
            for a in appItems {
                guard a["folder"] != nil,
                      let appName = a["name"] as? String,
                      let appId = Int(appName), appId > 0 else { continue }
                var cn = 0
                var count = 0
                var bytes: Int64 = 0
                if let stData = await downloadPath("CloudRedirect/\(accountId)/\(appId)/state.cloudredirect") {
                    let meta = parseStateMetadata(stData)
                    cn = meta.cn
                    count = meta.files
                    bytes = meta.bytes
                }
                apps.append(CloudAppRecord(
                    appId: appId,
                    accountId: accountId,
                    changeNumber: cn,
                    fileCount: count,
                    totalBytes: bytes,
                    isLocal: false,
                    isCloud: true,
                    localFolderURL: nil,
                    remoteId: a["id"] as? String
                ))
            }
        }
        return (accounts, apps, stats)
    }

    // MARK: - Delete Cloud App & Copy Saves Between Accounts

    static func deleteCloudApp(app: CloudAppRecord, provider: CloudProviderKind) async throws {
        guard app.isCloud, let remoteId = app.remoteId else { return }
        switch provider {
        case .folder:
            try FileManager.default.removeItem(atPath: remoteId)
        case .gdrive:
            guard let bottle = CrossOverInstaller.findSteamBottles().first,
                  let rawToken = CloudRedirectInstaller.readOAuthToken(for: .gdrive, in: bottle) else {
                throw CloudRedirectError.noBottleFound
            }
            let token = try await ensureFreshToken(rawToken, provider: .gdrive)
            var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(remoteId)")!)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(#"{"trashed":true}"#.utf8)
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                throw CloudOAuthError.testFailed("Google Drive trash HTTP \(code)")
            }
        default:
            throw CloudOAuthError.testFailed(L10n.isFrench
                ? "Suppression distante non supportée directement pour ce fournisseur."
                : "Remote deletion is not supported directly for this provider.")
        }
    }

    /// Copies all app save folders + `0/stats.json` from `sourceAccount` to `targetAccount` on the active Cloud backend.
    static func copyCloudSavesBetweenAccounts(
        config: CloudRedirectConfig,
        from sourceAccount: String,
        to targetAccount: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        let fr = L10n.isFrench
        guard !sourceAccount.isEmpty, !targetAccount.isEmpty, sourceAccount != targetAccount else {
            throw CloudRedirectError.invalidInput(fr ? "Comptes source et destination identiques ou invalides." : "Invalid source/destination account IDs.")
        }

        switch config.provider {
        case .folder:
            let root = URL(fileURLWithPath: config.localFolderPath, isDirectory: true)
            let cloudSub = root.appendingPathComponent("CloudRedirect", isDirectory: true)
            let base = FileManager.default.fileExists(atPath: cloudSub.path) ? cloudSub : root
            let srcDir = base.appendingPathComponent(sourceAccount, isDirectory: true)
            let dstDir = base.appendingPathComponent(targetAccount, isDirectory: true)
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return 0 }
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            var copied = 0
            for item in items {
                let targetItem = dstDir.appendingPathComponent(item.lastPathComponent, isDirectory: true)
                if fm.fileExists(atPath: targetItem.path) {
                    try fm.removeItem(at: targetItem)
                }
                try fm.copyItem(at: item, to: targetItem)
                if (Int(item.lastPathComponent) ?? 0) > 0 { copied += 1 }
            }
            return copied

        case .gdrive:
            guard let bottle = CrossOverInstaller.findSteamBottles().first,
                  let rawToken = CloudRedirectInstaller.readOAuthToken(for: .gdrive, in: bottle) else {
                throw CloudRedirectError.noBottleFound
            }
            let token = try await ensureFreshToken(rawToken, provider: .gdrive)
            guard let rootId = try await gdriveFindRootFolder(accessToken: token.access_token) else { return 0 }
            let acctFolders = try await gdriveListChildren(parentId: rootId, accessToken: token.access_token, onlyFolders: true)
            guard let srcFolder = acctFolders.first(where: { $0.name == sourceAccount }) else { return 0 }

            let dstFolderId: String
            if let existingDst = acctFolders.first(where: { $0.name == targetAccount }) {
                dstFolderId = existingDst.id
            } else {
                dstFolderId = try await gdriveCreateFolder(name: targetAccount, parentId: rootId, accessToken: token.access_token)
            }

            let srcChildren = try await gdriveListChildren(parentId: srcFolder.id, accessToken: token.access_token, onlyFolders: true)
            var copiedApps = 0
            for child in srcChildren {
                onProgress((fr ? "Copie Google Drive : " : "Copying Google Drive folder: ") + child.name)
                try await gdriveCopyFolderRecursively(
                    srcFolderId: child.id,
                    folderName: child.name,
                    dstParentId: dstFolderId,
                    accessToken: token.access_token
                )
                if (Int(child.name) ?? 0) > 0 {
                    copiedApps += 1
                }
            }
            return copiedApps

        default:
            throw CloudOAuthError.testFailed(fr
                ? "La copie inter-comptes directe est prise en charge pour Google Drive et Dossier local."
                : "Account-to-account copy is supported for Google Drive and Local Folder.")
        }
    }

    private static func gdriveCreateFolder(name: String, parentId: String, accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parentId],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudOAuthError.testFailed("Google Drive create folder HTTP \(code)")
        }
        return id
    }

    private static func gdriveCopyFolderRecursively(
        srcFolderId: String,
        folderName: String,
        dstParentId: String,
        accessToken: String
    ) async throws {
        let existingDstChildren = try await gdriveListChildren(parentId: dstParentId, accessToken: accessToken, onlyFolders: nil)
        let dstFolderId: String
        if let existing = existingDstChildren.first(where: { $0.name == folderName && $0.mimeType == "application/vnd.google-apps.folder" }) {
            dstFolderId = existing.id
        } else {
            dstFolderId = try await gdriveCreateFolder(name: folderName, parentId: dstParentId, accessToken: accessToken)
        }

        let dstChildrenAfter = try await gdriveListChildren(parentId: dstFolderId, accessToken: accessToken, onlyFolders: nil)
        let srcItems = try await gdriveListChildren(parentId: srcFolderId, accessToken: accessToken, onlyFolders: nil)

        for item in srcItems {
            if item.mimeType == "application/vnd.google-apps.folder" {
                try await gdriveCopyFolderRecursively(
                    srcFolderId: item.id,
                    folderName: item.name,
                    dstParentId: dstFolderId,
                    accessToken: accessToken
                )
            } else {
                // Remove old file with same name in destination if replacing metadata/blobs
                for dup in dstChildrenAfter where dup.name == item.name && dup.mimeType != "application/vnd.google-apps.folder" {
                    var delReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(dup.id)")!)
                    delReq.httpMethod = "DELETE"
                    delReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: delReq)
                }
                var copyReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)/copy")!)
                copyReq.httpMethod = "POST"
                copyReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                copyReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                copyReq.httpBody = try JSONSerialization.data(withJSONObject: [
                    "name": item.name,
                    "parents": [dstFolderId],
                ])
                let (_, resp) = try await URLSession.shared.data(for: copyReq)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    throw CloudOAuthError.testFailed("Google Drive copy file HTTP \(code)")
                }
            }
        }
    }
}
