// Persistent user settings and cache for LuaTools + macSteam integration.
import Foundation

enum LuaToolsConstants {
    static let supabaseUrl = "https://db.lua.tools"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NzYwMzkzNzYsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.f_-K38u3odjltP-g_67FVmG32Vg-_-k-lNBvIaVUVBM"
    static let apiBaseUrl = "https://lua.tools"
    static let hubcapBaseUrl = "https://hubcapmanifest.com"
    static let oauthCallbackPort: UInt16 = 53789
    static let oauthCallbackUrl = "http://localhost:53789/callback"
    static let dailyDownloadLimit = 25

    static let steamStoreSearchUrl = "https://store.steampowered.com/api/storesearch/"
    static let steamFeaturedUrl = "https://store.steampowered.com/api/featuredcategories"
    static let hardwareAppIdListUrl = "https://raw.githubusercontent.com/jsnli/steamappidlist/master/data/hardware_appid.json"

    static let manifestBackendUrl = "http://167.235.229.108"
    static let manifestBackendUserAgent = "secretgoonpoon"
    static let donateKeysUserAgent = "discord(dot)gg/luatools"

    static let pluginReleasesOwner = "madoiscool"
    static let pluginReleasesRepo = "LTSP"

    static let githubApiMirrors = ["https://lua.tools/api/gh/"]
    static let githubDownloadMirrors = [
        "https://ghproxy.net/",
        "https://ghfast.top/",
        "https://gh.ddlc.top/"
    ]
}

struct SettingsPayload: Codable {
    var language: String? = nil
    var fastFetch: Bool = false
    var autoUpdateApps: Bool = true
    var donateKeys: Bool = true
    var hubcapApiKey: String? = nil
    var cefPluginEnabled: Bool = true
}

struct DownloadHistoryRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var appId: Int
    var title: String
    var source: String
    var status: String
    var completedAt: Date
    var message: String?
}

struct CachePayload: Codable {
    var loadedAppIds: [Int] = []
    var donatedAppIds: [String] = []
    var downloadHistory: [DownloadHistoryRecord] = []
}

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let lock = NSLock()
    private var payload = SettingsPayload()
    private var cache = CachePayload()

    private init() {
        load()
    }

    private func load() {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? Data(contentsOf: Paths.settingsFile),
           let decoded = try? JSONDecoder().decode(SettingsPayload.self, from: data) {
            payload = decoded
        }
        if let cdata = try? Data(contentsOf: Paths.cacheFile),
           let decodedCache = try? JSONDecoder().decode(CachePayload.self, from: cdata) {
            cache = decodedCache
        }
    }

    private func saveSettingsLocked() {
        try? Paths.ensureDir(Paths.configDir)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Paths.settingsFile, options: .atomic)
        }
    }

    private func saveCacheLocked() {
        try? Paths.ensureDir(Paths.configDir)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Paths.cacheFile, options: .atomic)
        }
    }

    var language: String? {
        get { lock.lock(); defer { lock.unlock() }; return payload.language }
        set { lock.lock(); payload.language = newValue; saveSettingsLocked(); lock.unlock() }
    }

    var fastFetch: Bool {
        get { lock.lock(); defer { lock.unlock() }; return payload.fastFetch }
        set { lock.lock(); payload.fastFetch = newValue; saveSettingsLocked(); lock.unlock() }
    }

    var autoUpdateApps: Bool {
        get { lock.lock(); defer { lock.unlock() }; return payload.autoUpdateApps }
        set { lock.lock(); payload.autoUpdateApps = newValue; saveSettingsLocked(); lock.unlock() }
    }

    var donateKeys: Bool {
        get { lock.lock(); defer { lock.unlock() }; return payload.donateKeys }
        set { lock.lock(); payload.donateKeys = newValue; saveSettingsLocked(); lock.unlock() }
    }

    var hubcapApiKey: String? {
        get { lock.lock(); defer { lock.unlock() }; return payload.hubcapApiKey }
        set { lock.lock(); payload.hubcapApiKey = newValue; saveSettingsLocked(); lock.unlock() }
    }

    var cefPluginEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return payload.cefPluginEnabled }
        set { lock.lock(); payload.cefPluginEnabled = newValue; saveSettingsLocked(); lock.unlock() }
    }

    // MARK: - Cache accessors

    var loadedAppIds: [Int] {
        get { lock.lock(); defer { lock.unlock() }; return cache.loadedAppIds }
        set { lock.lock(); cache.loadedAppIds = Array(Set(newValue)); saveCacheLocked(); lock.unlock() }
    }

    func recordLoadedApp(_ appId: Int) {
        lock.lock()
        if !cache.loadedAppIds.contains(appId) {
            cache.loadedAppIds.append(appId)
            saveCacheLocked()
        }
        lock.unlock()
    }

    func removeLoadedApp(_ appId: Int) {
        lock.lock()
        cache.loadedAppIds.removeAll { $0 == appId }
        saveCacheLocked()
        lock.unlock()
    }

    func clearLoadedApps() {
        lock.lock()
        cache.loadedAppIds.removeAll()
        saveCacheLocked()
        lock.unlock()
    }

    var donatedAppIds: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return Set(cache.donatedAppIds) }
        set { lock.lock(); cache.donatedAppIds = Array(newValue); saveCacheLocked(); lock.unlock() }
    }

    var downloadHistory: [DownloadHistoryRecord] {
        get { lock.lock(); defer { lock.unlock() }; return cache.downloadHistory }
        set { lock.lock(); cache.downloadHistory = Array(newValue.prefix(100)); saveCacheLocked(); lock.unlock() }
    }

    func appendHistory(_ record: DownloadHistoryRecord) {
        lock.lock()
        cache.downloadHistory.insert(record, at: 0)
        if cache.downloadHistory.count > 100 {
            cache.downloadHistory = Array(cache.downloadHistory.prefix(100))
        }
        saveCacheLocked()
        lock.unlock()
    }

    func clearHistory() {
        lock.lock()
        cache.downloadHistory.removeAll()
        saveCacheLocked()
        lock.unlock()
    }
}
