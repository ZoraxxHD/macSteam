// LuaTools, Hubcap, Steam Storefront, Denuvo Fixes, and DonateKeys API client.
import Foundation

// MARK: - Models

struct SteamSearchResult: Sendable, Equatable {
    let appId: Int
    let name: String
    let iconUrl: String?
}

struct SteamFeaturedItem: Sendable, Equatable {
    let id: Int
    let name: String
    let largeCapsuleImage: String?
}

struct GameDetails: Sendable, Equatable {
    let appId: Int
    let name: String
    let type: String
    let baseAppId: String?
    let genres: [String]
    let headerImage: String?
    let releaseDate: String?

    var isDlc: Bool { type.lowercased() == "dlc" }
}

struct AppOverview: Sendable, Equatable {
    let shortDescription: String?
    let developers: [String]
    let publishers: [String]
    let genres: [String]
    let releaseDateText: String?
    let metacritic: Int?
    let isFree: Bool

    var developerLabel: String { developers.joined(separator: ", ") }
    var publisherLabel: String { publishers.joined(separator: ", ") }
}

struct AppFilterData: Sendable, Equatable {
    let type: String?
    let genres: [String]
    let windows: Bool
    let mac: Bool
    let linux: Bool
    let releaseYear: Int?
    let releaseDateText: String?
    let isFree: Bool
    let metacritic: Int?
    let reviews: Int?
    let isAdult: Bool
}

struct DlcDepot: Sendable, Equatable {
    let depotId: String
    let language: String?
    let osList: String?
    let included: Bool

    var meta: String {
        var parts = [language ?? "default"]
        if let osList, !osList.isEmpty { parts.append(osList) }
        return parts.joined(separator: " · ")
    }
}

struct DlcInfo: Sendable, Equatable {
    let appId: String
    let name: String
    let type: String
    let depotCount: Int
    let haveCount: Int
    let missingCount: Int
    let depots: [DlcDepot]
}

struct HubcapStats: Sendable, Equatable {
    let userId: String
    let dailyUsage: Int
    let dailyLimit: Int
    let canMakeRequests: Bool
    let apiKeyExpiresAt: String?
}

struct HubcapManifestStatus: Sendable, Equatable {
    let status: String
    let manifestFileExists: Bool
}

struct SourceMetaInfo: Sendable {
    let displayName: String?
    let discordUrl: String?
    let requiresUserKey: Bool

    static let all: [String: SourceMetaInfo] = [
        "Luie": SourceMetaInfo(displayName: "Luie (LuaTools)", discordUrl: "https://discord.gg/luatools", requiresUserKey: false),
        "Ryuu": SourceMetaInfo(displayName: nil, discordUrl: "https://discord.gg/manifests", requiresUserKey: false),
        "TwentyTwo Cloud": SourceMetaInfo(displayName: nil, discordUrl: "https://discord.gg/RrukXPyv5b", requiresUserKey: false),
        "Sushi": SourceMetaInfo(displayName: nil, discordUrl: "https://discord.gg/hMdv5dQhcN", requiresUserKey: false),
        "Skyflare": SourceMetaInfo(displayName: nil, discordUrl: "https://discord.gg/luatools", requiresUserKey: false),
        "Sadie (Morrenus)": SourceMetaInfo(displayName: "Sadie (Hubcap)", discordUrl: "https://discord.gg/hubcapsmanifest", requiresUserKey: true)
    ]

    static func get(_ name: String) -> SourceMetaInfo {
        all[name] ?? SourceMetaInfo(displayName: nil, discordUrl: nil, requiresUserKey: false)
    }
}

struct DenuvoTag: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let slug: String?
    let color: String?
}

struct DenuvoGameListing: Codable, Sendable, Equatable {
    let appid: String
    let name: String
    let header_image: String?
    let fixCount: Int
    let tags: [DenuvoTag]
}

struct DenuvoFix: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let description: String?
    let tags: [DenuvoTag]?
    let hasManifest: Bool?
    let hasFix: Bool?
    let manifestFilename: String?
    let fixFilename: String?
    let createdAt: String?
}

struct DenuvoFixRecordEntry: Codable, Sendable {
    var relativePath: String
    var action: String // "modified" or "added"
    var backupPath: String?
}

struct DenuvoFixRecord: Codable, Sendable {
    var appId: Int
    var fixId: String
    var appliedAt: String
    var files: [DenuvoFixRecordEntry]
}

// MARK: - Steam Link Parser

enum SteamLinkParser {
    private static let storeAppRegex = try! NSRegularExpression(pattern: #"(?:store\.steampowered\.com|steamcommunity\.com)/app/(\d+)"#, options: .caseInsensitive)
    private static let steamDbRegex = try! NSRegularExpression(pattern: #"steamdb\.info/app/(\d+)"#, options: .caseInsensitive)
    private static let steamUriRegex = try! NSRegularExpression(pattern: #"^steam://(?:store|run|install|launch|nav/games/details)/(\d+)"#, options: .caseInsensitive)

    static func extractAppId(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Int(trimmed), direct > 0 { return direct }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        for regex in [storeAppRegex, steamDbRegex, steamUriRegex] {
            if let m = regex.firstMatch(in: trimmed, range: range), m.numberOfRanges > 1 {
                if let id = Int(ns.substring(with: m.range(at: 1))), id > 0 {
                    return id
                }
            }
        }
        return nil
    }
}

// MARK: - Hubcap Service

final class HubcapService: @unchecked Sendable {
    static let shared = HubcapService()

    private let session: URLSession
    private static let keyRegex = try! NSRegularExpression(pattern: #"^smm_[0-9a-f]{96}$"#)

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 300
        session = URLSession(configuration: cfg)
    }

    static func isValidKeyFormat(_ key: String?) -> Bool {
        guard let key else { return false }
        let ns = key as NSString
        return keyRegex.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)) != nil
    }

    func getStats(key: String) async -> HubcapStats? {
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(LuaToolsConstants.hubcapBaseUrl)/api/v1/user/stats?api_key=\(encoded)") else {
            return nil
        }
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return HubcapStats(
            userId: (json["user_id"] as? String) ?? "",
            dailyUsage: (json["daily_usage"] as? Int) ?? 0,
            dailyLimit: (json["daily_limit"] as? Int) ?? 0,
            canMakeRequests: (json["can_make_requests"] as? Bool) ?? false,
            apiKeyExpiresAt: json["api_key_expires_at"] as? String
        )
    }

    func checkStatus(key: String, appId: Int) async -> HubcapManifestStatus? {
        guard let url = URL(string: "\(LuaToolsConstants.hubcapBaseUrl)/api/v1/status/\(appId)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return HubcapManifestStatus(
            status: (json["status"] as? String) ?? "",
            manifestFileExists: (json["manifest_file_exists"] as? Bool) ?? false
        )
    }

    func downloadManifest(appId: Int, key: String, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(LuaToolsConstants.hubcapBaseUrl)/api/v1/manifest/\(appId)?api_key=\(encoded)") else {
            throw NSError(domain: "Hubcap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Hubcap URL"])
        }
        return try await LuaToolsAPI.shared.downloadToTemp(request: URLRequest(url: url), filename: "\(appId).zip", onProgress: onProgress)
    }
}

// MARK: - LuaTools API & Steam AppInfo Cache

final class LuaToolsAPI: @unchecked Sendable {
    static let shared = LuaToolsAPI()
    static let hubcapSourceName = "Sadie (Morrenus)"

    private let session: URLSession
    private let lock = NSLock()
    private var filterMemo: [Int: AppFilterData] = [:]
    private var overviewMemo: [Int: AppOverview] = [:]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg)
        try? Paths.ensureDir(Paths.detailsCacheDir)
    }

    // MARK: - Search & Featured

    func search(query: String) async -> [SteamSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(LuaToolsConstants.steamStoreSearchUrl)?term=\(encoded)&l=english&cc=US") else {
            return []
        }
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            return []
        }
        var out: [SteamSearchResult] = []
        for item in items.prefix(10) {
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String else { continue }
            let icon = (item["tiny_image"] as? String)
                ?? "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/capsule_sm_120.jpg"
            out.append(SteamSearchResult(appId: id, name: name, iconUrl: icon))
        }
        return out
    }

    func getFeatured() async -> (topSellers: [SteamFeaturedItem], newReleases: [SteamFeaturedItem]) {
        guard let url = URL(string: "\(LuaToolsConstants.steamFeaturedUrl)?cc=us&l=english"),
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }
        func parseCategory(_ key: String) -> [SteamFeaturedItem] {
            guard let cat = root[key] as? [String: Any],
                  let items = cat["items"] as? [[String: Any]] else { return [] }
            var seen = Set<Int>()
            var list: [SteamFeaturedItem] = []
            for it in items {
                let type = (it["type"] as? Int) ?? -1
                guard type == 0,
                      let id = it["id"] as? Int, id > 0,
                      let name = it["name"] as? String,
                      let img = it["large_capsule_image"] as? String, !img.isEmpty,
                      seen.insert(id).inserted else { continue }
                list.append(SteamFeaturedItem(id: id, name: name, largeCapsuleImage: img))
                if list.count >= 16 { break }
            }
            return list
        }
        return (parseCategory("top_sellers"), parseCategory("new_releases"))
    }

    // MARK: - Full AppDetails & Disk Cache

    private func detailsFile(for appId: Int) -> URL {
        Paths.detailsCacheDir.appendingPathComponent("\(appId).json")
    }

    func ensureFullDetails(appId: Int) async -> [String: Any]? {
        let file = detailsFile(for: appId)
        if let data = try? Data(contentsOf: file),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !obj.isEmpty {
            return obj
        }

        let lang = L10n.isFrench ? "french" : "english"
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appId)&cc=us&l=\(lang)"),
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Find matching entry (direct key or child-keyed entry where steam_appid == appId)
        var foundData: [String: Any]?
        if let direct = root["\(appId)"] as? [String: Any],
           (direct["success"] as? Bool) == true,
           let d = direct["data"] as? [String: Any] {
            foundData = d
        } else {
            for (_, v) in root {
                if let entry = v as? [String: Any],
                   let d = entry["data"] as? [String: Any],
                   let sa = d["steam_appid"] as? Int, sa == appId {
                    foundData = d
                    break
                }
            }
        }

        guard let foundData else { return nil }
        if let serialized = try? JSONSerialization.data(withJSONObject: foundData) {
            try? Paths.ensureDir(Paths.detailsCacheDir)
            try? serialized.write(to: file, options: .atomic)
        }
        return foundData
    }

    func resolveGameDetails(appId: Int) async -> GameDetails? {
        guard let d = await ensureFullDetails(appId: appId),
              let name = d["name"] as? String, !name.isEmpty else {
            return nil
        }
        var genres: [String] = []
        if let gArr = d["genres"] as? [[String: Any]] {
            for g in gArr {
                if let desc = g["description"] as? String { genres.append(desc) }
            }
        }
        var baseApp: String?
        if let fg = d["fullgame"] as? [String: Any] {
            if let s = fg["appid"] as? String { baseApp = s }
            else if let n = fg["appid"] as? Int { baseApp = "\(n)" }
        }
        let relDate = (d["release_date"] as? [String: Any])?["date"] as? String
        return GameDetails(
            appId: (d["steam_appid"] as? Int) ?? appId,
            name: name,
            type: (d["type"] as? String) ?? "game",
            baseAppId: baseApp,
            genres: genres,
            headerImage: d["header_image"] as? String,
            releaseDate: relDate
        )
    }

    func getOverview(appId: Int) async -> AppOverview? {
        if let cached = lock.withLock({ overviewMemo[appId] }) { return cached }

        guard let d = await ensureFullDetails(appId: appId) else { return nil }
        let desc = (d["short_description"] as? String)?
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let devs = (d["developers"] as? [String]) ?? []
        let pubs = (d["publishers"] as? [String]) ?? []
        var genres: [String] = []
        if let gArr = d["genres"] as? [[String: Any]] {
            for g in gArr {
                if let s = g["description"] as? String { genres.append(s) }
            }
        }
        let rel = (d["release_date"] as? [String: Any])?["date"] as? String
        let mc = (d["metacritic"] as? [String: Any])?["score"] as? Int
        let isFree = (d["is_free"] as? Bool) ?? false

        let ov = AppOverview(
            shortDescription: desc,
            developers: devs,
            publishers: pubs,
            genres: genres,
            releaseDateText: rel,
            metacritic: mc,
            isFree: isFree
        )
        lock.withLock { overviewMemo[appId] = ov }
        return ov
    }

    func getFilterData(appId: Int) -> AppFilterData? {
        lock.lock()
        if let cached = filterMemo[appId] { lock.unlock(); return cached }
        lock.unlock()

        let file = detailsFile(for: appId)
        guard let data = try? Data(contentsOf: file),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !d.isEmpty else { return nil }

        let type = d["type"] as? String
        var genres: [String] = []
        if let gArr = d["genres"] as? [[String: Any]] {
            for g in gArr {
                if let s = g["description"] as? String { genres.append(s) }
            }
        }
        let platforms = d["platforms"] as? [String: Any]
        let win = (platforms?["windows"] as? Bool) ?? false
        let mac = (platforms?["mac"] as? Bool) ?? false
        let lin = (platforms?["linux"] as? Bool) ?? false

        let rel = (d["release_date"] as? [String: Any])?["date"] as? String
        var year: Int?
        if let rel, let range = rel.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            year = Int(rel[range])
        }
        let isFree = (d["is_free"] as? Bool) ?? false
        let mc = (d["metacritic"] as? [String: Any])?["score"] as? Int
        let reviews = (d["recommendations"] as? [String: Any])?["total"] as? Int
        var isAdult = false
        if let cd = d["content_descriptors"] as? [String: Any],
           let ids = cd["ids"] as? [Int] {
            isAdult = ids.contains(where: { $0 == 3 || $0 == 4 })
        }

        let fd = AppFilterData(
            type: type,
            genres: genres,
            windows: win,
            mac: mac,
            linux: lin,
            releaseYear: year,
            releaseDateText: rel,
            isFree: isFree,
            metacritic: mc,
            reviews: reviews,
            isAdult: isAdult
        )
        lock.lock()
        filterMemo[appId] = fd
        lock.unlock()
        return fd
    }

    // MARK: - Sources & Availability

    func checkSources(appId: Int) async -> [String: String] {
        var result: [String: String] = [:]
        let urlStr = "\(LuaToolsConstants.manifestBackendUrl)/check_apis?appid=\(appId)"
        if let url = URL(string: urlStr) {
            var req = URLRequest(url: url)
            req.setValue(LuaToolsConstants.manifestBackendUserAgent, forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                result = dict
            }
        }
        // Fallback via curl in case ATS blocks plain HTTP in an unbundled debug build
        if result.isEmpty {
            let curlOut = await Task.detached {
                Subprocess.run("/usr/bin/curl", ["-s", "-m", "10", "-A", LuaToolsConstants.manifestBackendUserAgent, urlStr])
            }.value
            if curlOut.code == 0,
               let data = curlOut.stdout.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                result = dict
            }
        }
        // Always ensure official LuaTools source "Luie" is listed
        if result["Luie"] == nil {
            result["Luie"] = "available"
        }
        // Synthesize Hubcap source
        if let key = AppSettings.shared.hubcapApiKey, !key.isEmpty {
            let st = await HubcapService.shared.checkStatus(key: key, appId: appId)
            result[Self.hubcapSourceName] = (st?.manifestFileExists == true) ? "available" : "unavailable"
        } else {
            result[Self.hubcapSourceName] = "unknown"
        }
        return result
    }

    func getStandardUsage() async -> (used: Int, limit: Int)? {
        guard AuthService.shared.isSignedIn,
              let token = try? await AuthService.shared.validAccessToken() else { return nil }
        let formatter = ISO8601DateFormatter()
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: Date())
        let iso = formatter.string(from: startOfDay)
        guard let encoded = iso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(LuaToolsConstants.supabaseUrl)/rest/v1/user_downloads?select=appid&downloaded_at=gte.\(encoded)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.setValue(LuaToolsConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("count=exact", forHTTPHeaderField: "Prefer")

        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range") else {
            return nil
        }
        let parts = range.split(separator: "/")
        let used = (parts.count == 2) ? (Int(parts[1]) ?? 0) : 0
        return (used, LuaToolsConstants.dailyDownloadLimit)
    }

    // MARK: - DLC & Manifest Downloads

    func getDlcInfo(appId: Int, baseAppId: String) async throws -> DlcInfo {
        let data = try await sendAuthedGET(path: "/api/dlc/info?appid=\(appId)&base=\(baseAppId)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LuaToolsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid DLC JSON"])
        }
        var depots: [DlcDepot] = []
        if let arr = json["depots"] as? [[String: Any]] {
            for d in arr {
                depots.append(DlcDepot(
                    depotId: (d["depotId"] as? String) ?? "",
                    language: d["language"] as? String,
                    osList: d["oslist"] as? String,
                    included: (d["included"] as? Bool) ?? false
                ))
            }
        }
        return DlcInfo(
            appId: (json["appid"] as? String) ?? "\(appId)",
            name: (json["name"] as? String) ?? "",
            type: (json["type"] as? String) ?? "dlc",
            depotCount: (json["depotCount"] as? Int) ?? depots.count,
            haveCount: (json["haveCount"] as? Int) ?? 0,
            missingCount: (json["missingCount"] as? Int) ?? 0,
            depots: depots
        )
    }

    func downloadManifest(appId: Int, source: String, gameName: String?, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        if source == Self.hubcapSourceName {
            guard let key = AppSettings.shared.hubcapApiKey, !key.isEmpty else {
                throw NSError(domain: "LuaToolsAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.tr("search.err.signin_required")])
            }
            return try await HubcapService.shared.downloadManifest(appId: appId, key: key, onProgress: onProgress)
        }
        let srcEnc = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
        var path = "/api/manifest/download?appid=\(appId)&source=\(srcEnc)"
        if let gameName, !gameName.isEmpty,
           let gEnc = gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&game_name=\(gEnc)"
        }
        let req = try await buildAuthedRequest(path: path)
        return try await downloadToTemp(request: req, filename: "\(appId).zip", onProgress: onProgress)
    }

    func generateDlc(appId: Int, baseAppId: String, gameName: String?, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        var path = "/api/dlc/generate?appid=\(appId)&base=\(baseAppId)"
        if let gameName, !gameName.isEmpty,
           let gEnc = gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&game_name=\(gEnc)"
        }
        let req = try await buildAuthedRequest(path: path)
        return try await downloadToTemp(request: req, filename: "\(appId).lua", onProgress: onProgress)
    }

    func downloadDepotManifest(depotId: Int, manifestId: String, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        let req = try await buildAuthedRequest(path: "/api/givemethemanifestpunk/\(depotId)/\(manifestId)")
        return try await downloadToTemp(request: req, filename: "\(depotId)_\(manifestId).manifest", onProgress: onProgress)
    }

    // MARK: - Denuvo / Game Fixes

    func getDenuvoListings() async -> (games: [DenuvoGameListing], tags: [DenuvoTag]) {
        guard let url = URL(string: "\(LuaToolsConstants.apiBaseUrl)/api/denuvo/listings"),
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return ([], [])
        }
        struct ListingsDTO: Decodable {
            let games: [DenuvoGameListing]?
            let tags: [DenuvoTag]?
        }
        guard let decoded = try? JSONDecoder().decode(ListingsDTO.self, from: data) else {
            return ([], [])
        }
        return (decoded.games ?? [], decoded.tags ?? [])
    }

    func getDenuvoFixes(appId: String) async -> [DenuvoFix] {
        guard let enc = appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(LuaToolsConstants.apiBaseUrl)/api/denuvo/fixes?appid=\(enc)"),
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        struct FixesDTO: Decodable {
            let fixes: [DenuvoFix]?
        }
        return (try? JSONDecoder().decode(FixesDTO.self, from: data).fixes) ?? []
    }

    func downloadDenuvo(fixId: String, slot: String, fallbackName: String, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        let fEnc = fixId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fixId
        let sEnc = slot.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? slot
        let data = try await sendAuthedGET(path: "/api/denuvo/download?fix=\(fEnc)&slot=\(sEnc)")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signedUrlStr = json["url"] as? String,
              let signedUrl = URL(string: signedUrlStr) else {
            throw NSError(domain: "LuaToolsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty download URL from server"])
        }
        return try await downloadToTemp(request: URLRequest(url: signedUrl), filename: fallbackName, onProgress: onProgress)
    }

    // MARK: - HTTP Plumbing

    private func buildAuthedRequest(path: String) async throws -> URLRequest {
        let token = try await AuthService.shared.validAccessToken()
        guard let url = URL(string: "\(LuaToolsConstants.apiBaseUrl)\(path)") else {
            throw NSError(domain: "LuaToolsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func sendAuthedGET(path: String) async throws -> Data {
        let req = try await buildAuthedRequest(path: path)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "LuaToolsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            var message = "HTTP \(http.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String, !err.isEmpty {
                message = err
            }
            throw NSError(domain: "LuaToolsAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    func downloadToTemp(request: URLRequest, filename: String, onProgress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> URL {
        let (asyncBytes, resp) = try await session.bytes(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "LuaToolsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            var errData = Data()
            for try await b in asyncBytes {
                errData.append(b)
                if errData.count > 4096 { break }
            }
            var message = "HTTP \(http.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: errData) as? [String: Any],
               let err = json["error"] as? String, !err.isEmpty {
                message = err
            }
            throw NSError(domain: "LuaToolsAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let expectedLength: Int64? = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsteam-dl-\(UUID().uuidString)", isDirectory: true)
        try Paths.ensureDir(tmpDir)
        let dest = tmpDir.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(65536)
        var totalRead: Int64 = 0
        var lastReport = Date.distantPast

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                try handle.write(contentsOf: buffer)
                totalRead += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReport) >= 0.1 {
                    lastReport = now
                    onProgress?(totalRead, expectedLength)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            totalRead += Int64(buffer.count)
        }
        onProgress?(totalRead, expectedLength)
        return dest
    }
}

// MARK: - DonateKeysService (macOS config.vdf + config.yaml key donation)

enum DonateKeysService {
    static func sendPendingKeysIfEnabled(config: MacsteamConfig) {
        guard AppSettings.shared.donateKeys else { return }
        Task.detached(priority: .background) {
            var pairs: [(String, String)] = []
            // 1. From macSteam config.yaml
            for group in config.depotKeyGroups {
                for d in group.depots where d.key.count == 64 {
                    pairs.append(("\(d.depotID)", d.key))
                }
            }
            // 2. From Steam config/config.vdf
            let vdfURL = Paths.steamRoot.appendingPathComponent("config/config.vdf")
            if let vdfText = try? String(contentsOf: vdfURL, encoding: .utf8) {
                pairs.append(contentsOf: extractVdfKeys(vdfText))
            }
            guard !pairs.isEmpty else { return }

            var donated = AppSettings.shared.donatedAppIds
            var seen = Set<String>()
            var fresh: [(String, String)] = []
            for (depotId, key) in pairs {
                if !donated.contains(depotId) && seen.insert(depotId).inserted {
                    fresh.append((depotId, key))
                }
            }
            guard !fresh.isEmpty,
                  let url = URL(string: "\(LuaToolsConstants.manifestBackendUrl)/donatekeys/send") else { return }

            let payload = fresh.map { "\($0.0):\($0.1)" }.joined(separator: ",")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.setValue(LuaToolsConstants.donateKeysUserAgent, forHTTPHeaderField: "User-Agent")
            req.httpBody = Data(payload.utf8)

            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                for (depotId, _) in fresh { donated.insert(depotId) }
                AppSettings.shared.donatedAppIds = donated
            }
        }
    }

    private static func extractVdfKeys(_ text: String) -> [(String, String)] {
        let pattern = #""(\d{1,10})"\s*\{\s*"DecryptionKey"\s*"([0-9a-fA-F]{64})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
        }
    }
}
