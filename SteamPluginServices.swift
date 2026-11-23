// Steam Store Page Plugin: CEF WebSocket Injector (:8080), Local HTTP Server (:6767), and Plugin Manager.
import AppKit
import Foundation
import Network

// MARK: - Headless Add Pipeline for Store Plugin

final class PluginAddService: @unchecked Sendable {
    static let shared = PluginAddService()

    struct SourceRowState: Sendable {
        var name: String
        var displayName: String
        var status: String
        var needsKey: Bool
        var locked: Bool
        var stats: String?
        var downloading: Bool = false
        var progress: Double = 0
        var indeterminate: Bool = false

        var available: Bool { status == "available" }
        var canDownload: Bool { available && !locked }
    }

    final class AddState: @unchecked Sendable {
        let appId: Int
        var gameName: String?
        var checking: Bool = true
        var fastFetch: Bool = false
        var sourcesLoaded: Bool = false
        var sources: [SourceRowState] = []
        var installStatus: String?
        var installFailed: Bool = false
        var error: String?
        var busy: Bool = false

        init(appId: Int, gameName: String?, fastFetch: Bool) {
            self.appId = appId
            self.gameName = gameName
            self.fastFetch = fastFetch
        }
    }

    private let lock = NSLock()
    private var states: [Int: AddState] = [:]
    var store: ConfigStore?

    private init() {}

    func getState(appId: Int) -> AddState? {
        lock.lock(); defer { lock.unlock() }
        return states[appId]
    }

    func start(appId: Int, gameName: String?) {
        let st = AddState(appId: appId, gameName: gameName, fastFetch: AppSettings.shared.fastFetch)
        lock.lock()
        states[appId] = st
        lock.unlock()

        Task.detached { [weak self] in
            await self?.checkAsync(appId: appId, state: st)
        }
    }

    func pick(appId: Int, sourceName: String) {
        guard let st = getState(appId: appId), !st.busy else { return }
        guard let idx = st.sources.firstIndex(where: {
            $0.name.caseInsensitiveCompare(sourceName) == .orderedSame ||
            $0.displayName.caseInsensitiveCompare(sourceName) == .orderedSame
        }) else { return }
        let row = st.sources[idx]
        Task.detached { [weak self] in
            await self?.downloadAsync(appId: appId, state: st, sourceName: row.name, needsKey: row.needsKey)
        }
    }

    private func checkAsync(appId: Int, state: AddState) async {
        if state.gameName == nil {
            state.gameName = await LuaToolsAPI.shared.resolveGameDetails(appId: appId)?.name
        }
        let statuses = await LuaToolsAPI.shared.checkSources(appId: appId)
        let key = AppSettings.shared.hubcapApiKey
        var rows: [SourceRowState] = statuses.map { (name, status) in
            let meta = SourceMetaInfo.get(name)
            return SourceRowState(
                name: name,
                displayName: meta.displayName ?? name,
                status: status,
                needsKey: meta.requiresUserKey,
                locked: meta.requiresUserKey && (key?.isEmpty ?? true),
                stats: nil
            )
        }.sorted { a, b in
            if a.name == "Luie" { return true }
            if b.name == "Luie" { return false }
            if a.available != b.available { return a.available && !b.available }
            return (a.needsKey ? 1 : 0) > (b.needsKey ? 1 : 0)
        }

        if let key, !key.isEmpty, let stats = await HubcapService.shared.getStats(key: key) {
            for i in rows.indices where rows[i].needsKey {
                rows[i].locked = !stats.canMakeRequests
                rows[i].stats = "\(stats.dailyUsage)/\(stats.dailyLimit)"
            }
        }
        if let usage = await LuaToolsAPI.shared.getStandardUsage() {
            for i in rows.indices where !rows[i].needsKey {
                rows[i].stats = "\(usage.used)/\(usage.limit)"
            }
        }

        state.sources = rows
        state.sourcesLoaded = true
        state.checking = false

        if state.fastFetch, let best = rows.first(where: { $0.canDownload }) {
            await downloadAsync(appId: appId, state: state, sourceName: best.name, needsKey: best.needsKey)
        }
    }

    private func downloadAsync(appId: Int, state: AddState, sourceName: String, needsKey: Bool) async {
        guard !state.busy, let store else { return }
        state.busy = true
        state.error = nil
        state.installStatus = nil
        state.installFailed = false

        if let idx = state.sources.firstIndex(where: { $0.name == sourceName }) {
            state.sources[idx].downloading = true
            state.sources[idx].indeterminate = true
        }

        let title = state.gameName ?? "App \(appId)"
        let qItem = DownloadQueueItem(
            dedupeKey: "manifest:\(appId)",
            appId: appId,
            title: title,
            subtitle: SourceMetaInfo.get(sourceName).displayName ?? sourceName,
            work: { item in
                let fileURL = try await LuaToolsAPI.shared.downloadManifest(
                    appId: appId,
                    source: sourceName,
                    gameName: title,
                    onProgress: { read, total in
                        DownloadQueue.shared.updateProgress(for: item, bytesRead: read, totalBytes: total)
                        if let i = state.sources.firstIndex(where: { $0.name == sourceName }) {
                            state.sources[i].indeterminate = (total == nil)
                            if let total, total > 0 {
                                state.sources[i].progress = Double(read) / Double(total) * 100.0
                            }
                        }
                    }
                )
                defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
                DownloadQueue.shared.setInstalling(item)
                let res = try UnifiedInstaller.installDownloaded(
                    fileURL: fileURL,
                    appId: appId,
                    gameName: title,
                    source: sourceName,
                    store: store
                )
                return L10n.isFrench
                    ? "\(title) ajouté (\(res.manifestCount) manifests)"
                    : "Added \(title) (\(res.manifestCount) manifests)"
            },
            onFinished: { item, ok in
                if let i = state.sources.firstIndex(where: { $0.name == sourceName }) {
                    state.sources[i].downloading = false
                    state.sources[i].indeterminate = false
                }
                state.busy = false
                if ok {
                    state.installStatus = item.message
                    state.installFailed = false
                } else {
                    state.error = item.message
                    state.installFailed = true
                }
            }
        )
        DownloadQueue.shared.enqueue(qItem)
    }
}

// MARK: - Plugin Installer Service (macOS CEF Marker + luatools.js)

final class PluginInstallerService: @unchecked Sendable {
    static let shared = PluginInstallerService()

    struct Status: Sendable {
        let frontendInstalled: Bool
        let cefMarkerInstalled: Bool
        let serverRunning: Bool
        let installedTag: String?
        let latestTag: String?
    }

    private var luatoolsJsURL: URL {
        Paths.pluginDir.appendingPathComponent("public/luatools.js")
    }
    private var manifestURL: URL {
        Paths.pluginDir.appendingPathComponent("installed.json")
    }

    private init() {}

    func currentStatus() -> Status {
        let fm = FileManager.default
        let frontend = fm.fileExists(atPath: luatoolsJsURL.path)
        let cef = fm.fileExists(atPath: Paths.cefMarkerRoot.path) || fm.fileExists(atPath: Paths.cefMarkerInner.path)
        var tag: String?
        if let data = try? Data(contentsOf: manifestURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            tag = json["tag"] as? String
        }
        return Status(
            frontendInstalled: frontend,
            cefMarkerInstalled: cef,
            serverRunning: HttpServerService.shared.isListening,
            installedTag: tag,
            latestTag: nil
        )
    }

    func ensureCefMarkers() {
        for marker in [Paths.cefMarkerRoot, Paths.cefMarkerInner, Paths.cefMarkerOuter] {
            try? Paths.ensureDir(marker.deletingLastPathComponent())
            if !FileManager.default.fileExists(atPath: marker.path) {
                try? Data().write(to: marker, options: .atomic)
            }
        }
    }

    func removeCefMarkers() {
        for marker in [Paths.cefMarkerRoot, Paths.cefMarkerInner, Paths.cefMarkerOuter] {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    func installOrUpdate() async throws {
        ensureCefMarkers()
        let pubDir = Paths.pluginDir.appendingPathComponent("public", isDirectory: true)
        try Paths.ensureDir(pubDir)

        // Try fetching latest plugin.zip from madoiscool/LTSP on GitHub; fall back to built-in native script
        var installedTag = "v1.4-macsteam"
        if let (zipURL, tag) = try? await fetchGithubPluginZip() {
            defer { try? FileManager.default.removeItem(at: zipURL.deletingLastPathComponent()) }
            let tmpExtract = FileManager.default.temporaryDirectory.appendingPathComponent("ltsp-\(UUID().uuidString)")
            try? Paths.ensureDir(tmpExtract)
            defer { try? FileManager.default.removeItem(at: tmpExtract) }
            let u = Subprocess.run("/usr/bin/unzip", ["-o", zipURL.path, "-d", tmpExtract.path])
            if u.code == 0, let foundJs = findFile(named: "luatools.js", in: tmpExtract) {
                try? FileManager.default.removeItem(at: luatoolsJsURL)
                try FileManager.default.copyItem(at: foundJs, to: luatoolsJsURL)
                installedTag = tag
            }
        }

        if !FileManager.default.fileExists(atPath: luatoolsJsURL.path) {
            try Self.builtinLuaToolsJs.write(to: luatoolsJsURL, atomically: true, encoding: .utf8)
        }

        let meta = try JSONSerialization.data(withJSONObject: ["tag": installedTag])
        try meta.write(to: manifestURL, options: .atomic)

        CefInjectorService.shared.reloadPluginFiles()
    }

    func uninstall() {
        removeCefMarkers()
        try? FileManager.default.removeItem(at: Paths.pluginDir)
        CefInjectorService.shared.reloadPluginFiles()
    }

    private func fetchGithubPluginZip() async throws -> (URL, String)? {
        let apiUrlStr = "https://api.github.com/repos/\(LuaToolsConstants.pluginReleasesOwner)/\(LuaToolsConstants.pluginReleasesRepo)/releases/latest"
        guard let apiUrl = URL(string: apiUrlStr) else { return nil }
        var req = URLRequest(url: apiUrl)
        req.setValue("macSteam", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { return nil }

        guard let zipAsset = assets.first(where: { ($0["name"] as? String)?.lowercased() == "plugin.zip" }),
              let dlUrlStr = zipAsset["browser_download_url"] as? String,
              let dlUrl = URL(string: dlUrlStr) else { return nil }

        let fileURL = try await LuaToolsAPI.shared.downloadToTemp(request: URLRequest(url: dlUrl), filename: "plugin.zip", onProgress: nil)
        return (fileURL, tag)
    }

    private func findFile(named name: String, in dir: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    // Built-in store-page script so the Steam Store integration works even without downloading from GitHub
    static let builtinLuaToolsJs: String = """
    (function(){
      if (window.__LuaToolsReady) return;
      window.__LuaToolsReady = true;
      function getAppId() {
        var m = location.pathname.match(/\\/app\\/(\\d+)/);
        return m ? parseInt(m[1], 10) : null;
      }
      function call(method, args) {
        if (window.Millennium && typeof window.Millennium.callServerMethod === 'function') {
          return window.Millennium.callServerMethod('luatools', method, args || {});
        }
        return Promise.resolve({});
      }
      function injectButton() {
        var appid = getAppId();
        if (!appid || document.getElementById('macsteam-lt-btn')) return;
        var target = document.querySelector('.apphub_OtherSiteInfo') || document.querySelector('.game_area_purchase_game_wrapper');
        if (!target) return;
        var btn = document.createElement('a');
        btn.id = 'macsteam-lt-btn';
        btn.className = 'btnv6_blue_hoverfade btn_medium';
        btn.style.marginRight = '8px';
        btn.style.cursor = 'pointer';
        var span = document.createElement('span');
        span.textContent = 'Add via macSteam';
        btn.appendChild(span);
        target.prepend(btn);

        call('HasLuaToolsForApp', { appid: appid }).then(function(r) {
          if (r && r.exists) span.textContent = 'Update in macSteam ✓';
        });

        btn.onclick = function() {
          var titleEl = document.getElementById('appHubAppName');
          var name = titleEl ? titleEl.textContent.trim() : ('App ' + appid);
          span.textContent = 'Checking sources…';
          call('StartLuaToolsAdd', { appid: appid, name: name }).then(function() {
            var poll = setInterval(function() {
              call('GetLuaToolsAddStatus', { appid: appid }).then(function(st) {
                if (!st) return;
                if (st.error) {
                  clearInterval(poll);
                  span.textContent = 'Error: ' + st.error;
                  return;
                }
                if (st.installStatus) {
                  clearInterval(poll);
                  span.textContent = 'Added to macSteam ✓';
                  return;
                }
                if (st.sourcesLoaded && !st.fastFetch && st.sources && st.sources.length > 0) {
                  var avail = st.sources.find(function(s){ return s.canDownload; });
                  if (avail && !st._picked) {
                    st._picked = true;
                    span.textContent = 'Downloading (' + avail.displayName + ')…';
                    call('PickLuaToolsAddSource', { appid: appid, source: avail.name });
                  } else if (!avail) {
                    clearInterval(poll);
                    span.textContent = 'No source available';
                  }
                }
              });
            }, 600);
          });
        };
      }
      setInterval(injectButton, 1200);
      injectButton();
    })();
    """
}

// MARK: - Local HTTP Server (127.0.0.1:6767)

final class HttpServerService: @unchecked Sendable {
    static let shared = HttpServerService()

    private var listener: NWListener?
    private(set) var isListening = false
    var store: ConfigStore?
    var onOpenSettings: (@MainActor () -> Void)?
    var onOpenFix: (@MainActor (Int) -> Void)?

    private init() {}

    func start(store: ConfigStore) {
        self.store = store
        PluginAddService.shared.store = store
        guard listener == nil else { return }

        guard let port = NWEndpoint.Port(rawValue: 6767) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)

        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.isListening = true
                } else if case .failed = state {
                    self?.isListening = false
                }
            }
            l.start(queue: .global(qos: .utility))
            listener = l
        } catch {
            isListening = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, _, _ in
            guard let self, let data, let raw = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            Task {
                let (status, responseBody) = await self.routeHttpRequest(raw)
                let bodyData = Data(responseBody.utf8)
                let headers = [
                    "HTTP/1.1 \(status) OK",
                    "Content-Type: application/json; charset=utf-8",
                    "Access-Control-Allow-Origin: *",
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers: Content-Type",
                    "Content-Length: \(bodyData.count)",
                    "Connection: close",
                    "",
                    ""
                ].joined(separator: "\r\n")
                var packet = Data(headers.utf8)
                packet.append(bodyData)
                conn.send(content: packet, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
    }

    func routeDirectRPC(method: String, path: String, body: String) async -> String {
        let (_, resp) = await handleRoute(method: method, path: path, body: body)
        return resp
    }

    private func routeHttpRequest(_ raw: String) async -> (Int, String) {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headerBlock = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        let firstLine = headerBlock.components(separatedBy: "\r\n").first ?? ""
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else { return (400, #"{"success":false,"error":"Bad request"}"#) }
        let method = String(tokens[0]).uppercased()
        let fullPath = String(tokens[1])
        let pathOnly = fullPath.split(separator: "?").first.map(String.init) ?? fullPath
        let cleanPath = pathOnly.count > 1 && pathOnly.hasSuffix("/") ? String(pathOnly.dropLast()) : pathOnly

        if method == "OPTIONS" { return (204, "") }
        return await handleRoute(method: method, path: cleanPath, body: body)
    }

    private func handleRoute(method: String, path: String, body: String) async -> (Int, String) {
        let segs = path.split(separator: "/").map(String.init)

        // /has/{appid}
        if segs.count == 2 && segs[0] == "has", let appId = Int(segs[1]) {
            let exists = store?.config.apps.contains(appId) ?? false
            return (200, #"{"success":true,"exists":\#(exists)}"#)
        }

        // /add/{appid}
        if segs.count == 2 && segs[0] == "add", let appId = Int(segs[1]) {
            var gameName: String?
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                gameName = json["name"] as? String
            }
            PluginAddService.shared.start(appId: appId, gameName: gameName)
            return (200, #"{"success":true}"#)
        }

        // /add-status/{appid}
        if segs.count == 2 && segs[0] == "add-status", let appId = Int(segs[1]) {
            let installed = store?.config.apps.contains(appId) ?? false
            guard let st = PluginAddService.shared.getState(appId: appId) else {
                return (200, #"{"success":true,"checking":false,"sourcesLoaded":false,"sources":[],"installed":\#(installed)}"#)
            }
            let sourcesArr: [[String: Any]] = st.sources.map { s in
                [
                    "name": s.name,
                    "displayName": s.displayName,
                    "status": s.status,
                    "available": s.available,
                    "canDownload": s.canDownload,
                    "locked": s.locked,
                    "needsKey": s.needsKey,
                    "stats": s.stats as Any,
                    "downloading": s.downloading,
                    "progress": s.progress,
                    "indeterminate": s.indeterminate
                ]
            }
            let payload: [String: Any] = [
                "success": true,
                "appid": st.appId,
                "checking": st.checking,
                "fastFetch": st.fastFetch,
                "sourcesLoaded": st.sourcesLoaded,
                "sources": sourcesArr,
                "installStatus": st.installStatus as Any,
                "installFailed": st.installFailed,
                "error": st.error as Any,
                "installed": installed
            ]
            return (200, serializeJSON(payload))
        }

        // /add-source/{appid}
        if segs.count == 2 && segs[0] == "add-source", let appId = Int(segs[1]) {
            var source = ""
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                source = (json["source"] as? String) ?? ""
            }
            guard !source.isEmpty else { return (400, #"{"success":false,"error":"source is required"}"#) }
            PluginAddService.shared.pick(appId: appId, sourceName: source)
            return (200, #"{"success":true}"#)
        }

        // /check-sources/{appid}
        if segs.count == 2 && segs[0] == "check-sources", let appId = Int(segs[1]) {
            let statuses = await LuaToolsAPI.shared.checkSources(appId: appId)
            let results = statuses.map { ["name": $0.key, "available": $0.value == "available"] }
            return (200, serializeJSON(["success": true, "results": results]))
        }

        // /remove/{appid}
        if segs.count == 2 && segs[0] == "remove", let appId = Int(segs[1]) {
            try? store?.removeApps([appId])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .libraryDidChange, object: appId)
            }
            return (200, #"{"success":true,"count":1}"#)
        }

        // /cancel/{appid}
        if segs.count == 2 && segs[0] == "cancel", let appId = Int(segs[1]) {
            if let item = DownloadQueue.shared.findActive(dedupeKey: "manifest:\(appId)") {
                DownloadQueue.shared.cancel(item)
            }
            return (200, #"{"success":true}"#)
        }

        // /open/fix/{appid}
        if segs.count == 3 && segs[0] == "open" && segs[1] == "fix", let appId = Int(segs[2]) {
            let callback = onOpenFix
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                callback?(appId)
            }
            return (200, #"{"success":true}"#)
        }

        // /open/settings
        if path == "/open/settings" {
            let callback = onOpenSettings
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                callback?()
            }
            return (200, #"{"success":true}"#)
        }

        // /restart-steam
        if path == "/restart-steam" {
            SteamLibraryService.restartSteam()
            return (200, #"{"success":true}"#)
        }

        // /loaded-apps
        if path == "/loaded-apps" {
            if method == "POST" {
                AppSettings.shared.clearLoadedApps()
                return (200, #"{"success":true}"#)
            }
            let ids = AppSettings.shared.loadedAppIds
            let apps = ids.map { id -> [String: Any] in
                let name = store?.config.appNames[id] ?? "App \(id)"
                return ["appid": id, "name": name]
            }
            return (200, serializeJSON(["success": true, "apps": apps]))
        }

        // /api-list
        if path == "/api-list" {
            return (200, #"{"success":true,"apis":[{"name":"Ryuu","index":0},{"name":"Sushi","index":1}]}"#)
        }

        // /icon
        if path == "/icon" {
            return (200, #"{"success":false,"dataUrl":""}"#)
        }

        return (404, #"{"success":false,"error":"Not found"}"#)
    }

    private func serializeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"success":false}"#
        }
        return str
    }
}

// MARK: - CEF WebSocket Injector Service (127.0.0.1:8080)
// Event-driven CDP Runtime.addBinding over one persistent WebSocket per Store tab + NSWorkspace lifecycle gating (0 wakeups/sec when idle).

final class CefInjectorService: @unchecked Sendable {
    static let shared = CefInjectorService()

    private let session: URLSession
    private let lock = NSLock()
    private var discoveryTask: Task<Void, Never>?
    private var attachedTabs: [String: Task<Void, Never>] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var started = false
    private var luatoolsJs: String = PluginInstallerService.builtinLuaToolsJs
    private var cdpId: Int = 1

    private static let cefDebugURL = URL(string: "http://127.0.0.1:8080/json")!
    private static let rpcBindingName = "__macSteamRPC"

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        session = URLSession(configuration: cfg)
    }

    func start() {
        reloadPluginFiles()
        let enabled = AppSettings.shared.cefPluginEnabled
        if enabled {
            PluginInstallerService.shared.ensureCefMarkers()
        }

        lock.withLock {
            started = true
        }
        installWorkspaceObserversIfNeeded()

        if enabled && isNativeSteamRunning() {
            startDiscoveryLoopIfNeeded()
        } else {
            stopDiscoveryLoop()
        }
    }

    func stop() {
        lock.withLock {
            started = false
        }
        removeWorkspaceObservers()
        stopDiscoveryLoop()
    }

    /// Call whenever `AppSettings.shared.cefPluginEnabled` changes.
    func refreshEnabledState() {
        let enabled = AppSettings.shared.cefPluginEnabled
        if enabled {
            PluginInstallerService.shared.ensureCefMarkers()
            if isNativeSteamRunning() {
                startDiscoveryLoopIfNeeded()
            }
        } else {
            stopDiscoveryLoop()
        }
    }

    func reloadPluginFiles() {
        let jsURL = Paths.pluginDir.appendingPathComponent("public/luatools.js")
        let loaded: String
        if let diskJs = try? String(contentsOf: jsURL, encoding: .utf8), !diskJs.isEmpty {
            loaded = diskJs
        } else {
            loaded = PluginInstallerService.builtinLuaToolsJs
        }
        lock.withLock { luatoolsJs = loaded }
    }

    private func isNativeSteamRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if let bid = app.bundleIdentifier?.lowercased(), bid == "com.valvesoftware.steam" {
                return true
            }
            if let name = app.localizedName?.lowercased(), name == "steam" {
                return app.executableURL?.path.contains("/Applications/Steam.app") == true
                    || app.executableURL?.path.contains("steam_osx") == true
            }
            return false
        }
    }

    private func installWorkspaceObserversIfNeeded() {
        let alreadyInstalled = lock.withLock { !workspaceObservers.isEmpty }
        guard !alreadyInstalled else { return }

        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let isStarted = self.lock.withLock { self.started }
            if isStarted && AppSettings.shared.cefPluginEnabled && self.isNativeSteamRunning() {
                self.startDiscoveryLoopIfNeeded()
            }
        }
        let termObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !self.isNativeSteamRunning() {
                self.stopDiscoveryLoop()
            }
        }
        lock.withLock {
            workspaceObservers = [launchObs, termObs]
        }
    }

    private func removeWorkspaceObservers() {
        let observers: [NSObjectProtocol] = lock.withLock {
            let copy = workspaceObservers
            workspaceObservers.removeAll()
            return copy
        }
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }

    private func startDiscoveryLoopIfNeeded() {
        lock.withLock {
            guard discoveryTask == nil else { return }
            discoveryTask = Task.detached(priority: .background) { [weak self] in
                await self?.runDiscoveryLoop()
            }
        }
    }

    private func stopDiscoveryLoop() {
        let (disc, tabs): (Task<Void, Never>?, [Task<Void, Never>]) = lock.withLock {
            let d = discoveryTask
            discoveryTask = nil
            let t = Array(attachedTabs.values)
            attachedTabs.removeAll()
            return (d, t)
        }
        disc?.cancel()
        for t in tabs { t.cancel() }
    }

    private func nextCdpId() -> Int {
        lock.withLock {
            cdpId += 1
            return cdpId
        }
    }

    private func runDiscoveryLoop() async {
        var failStreak = 0

        while !Task.isCancelled {
            guard AppSettings.shared.cefPluginEnabled && isNativeSteamRunning() else {
                stopDiscoveryLoop()
                return
            }

            if let (data, resp) = try? await session.data(from: Self.cefDebugURL),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                failStreak = 0
                var activeStoreTabIds: Set<String> = []

                for tab in arr {
                    guard let urlStr = tab["url"] as? String,
                          urlStr.lowercased().contains("store.steampowered.com"),
                          let wsStr = tab["webSocketDebuggerUrl"] as? String,
                          let wsURL = URL(string: wsStr),
                          let tabId = tab["id"] as? String else { continue }
                    activeStoreTabIds.insert(tabId)
                    attachTabIfNeeded(tabId: tabId, wsURL: wsURL)
                }

                // Cancel sessions for closed or navigated-away tabs
                let staleTasks: [Task<Void, Never>] = lock.withLock {
                    var stale: [Task<Void, Never>] = []
                    for (id, task) in attachedTabs where !activeStoreTabIds.contains(id) {
                        stale.append(task)
                        attachedTabs.removeValue(forKey: id)
                    }
                    return stale
                }
                for t in staleTasks { t.cancel() }

                // Gentle 5s tab discovery; active tabs communicate purely via push events (0 polling)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } else {
                // Back off up to 30s when CEF port 8080 isn't open (e.g., normal Steam without debug flag)
                failStreak = min(failStreak + 1, 4)
                let delaySeconds: UInt64 = [5, 10, 20, 30][min(failStreak - 1, 3)]
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }
    }

    private func attachTabIfNeeded(tabId: String, wsURL: URL) {
        lock.withLock {
            guard attachedTabs[tabId] == nil else { return }
            attachedTabs[tabId] = Task.detached(priority: .utility) { [weak self] in
                await self?.runPersistentTabSession(tabId: tabId, wsURL: wsURL)
                self?.detachTab(tabId: tabId)
            }
        }
    }

    private func detachTab(tabId: String) {
        lock.withLock {
            _ = attachedTabs.removeValue(forKey: tabId)
        }
    }

    private func runPersistentTabSession(tabId: String, wsURL: URL) async {
        let ws = session.webSocketTask(with: wsURL)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        // Enable Runtime events + push binding (zero polling!)
        guard await sendCdp(ws: ws, method: "Runtime.enable", params: [:]),
              await sendCdp(ws: ws, method: "Runtime.addBinding", params: ["name": Self.rpcBindingName]) else {
            return
        }

        let script = lock.withLock { Self.polyfillJs + "\n" + luatoolsJs }
        let injectExpr = "if(window.__LuaToolsReady!==true){\(script)}"
        _ = await sendCdp(ws: ws, method: "Runtime.evaluate", params: ["expression": injectExpr])

        // Block silently in kernel kqueue waiting for CDP push events (0% idle CPU)
        while !Task.isCancelled {
            let msg: URLSessionWebSocketTask.Message
            do {
                msg = try await ws.receive()
            } catch {
                break
            }

            guard case .string(let text) = msg,
                  let data = text.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["method"] as? String) == "Runtime.bindingCalled",
                  let params = root["params"] as? [String: Any],
                  (params["name"] as? String) == Self.rpcBindingName,
                  let payloadStr = params["payload"] as? String,
                  let payloadData = payloadStr.data(using: .utf8),
                  let req = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let reqId = req["id"] as? String,
                  let method = req["method"] as? String else {
                continue
            }

            let argsJSON = (req["args"] as? String) ?? "{}"
            let resStr = await callBackend(method: method, argsJSON: argsJSON)
            let safeId = (try? String(data: JSONSerialization.data(withJSONObject: [reqId]), encoding: .utf8)) ?? "[]"
            let safePayload: String
            if let rData = resStr.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: rData)) != nil {
                safePayload = resStr
            } else {
                safePayload = (try? String(data: JSONSerialization.data(withJSONObject: ["v": resStr]), encoding: .utf8)) ?? "{}"
            }
            let resolveExpr = "window.__macSteamResolve&&window.__macSteamResolve((\(safeId))[0],\(safePayload));"
            _ = await sendCdp(ws: ws, method: "Runtime.evaluate", params: ["expression": resolveExpr])
        }
    }

    private func sendCdp(ws: URLSessionWebSocketTask, method: String, params: [String: Any]) async -> Bool {
        let payload: [String: Any] = [
            "id": nextCdpId(),
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return false }
        do {
            try await ws.send(.string(jsonStr))
            return true
        } catch {
            return false
        }
    }

    private func callBackend(method: String, argsJSON: String) async -> String {
        let map: [String: (String, String)] = [
            "HasLuaToolsForApp": ("GET", "/has/{appid}"),
            "CheckApisForApp": ("POST", "/check-sources/{appid}"),
            "DeleteLuaToolsForApp": ("POST", "/remove/{appid}"),
            "StartLuaToolsAdd": ("POST", "/add/{appid}"),
            "GetLuaToolsAddStatus": ("GET", "/add-status/{appid}"),
            "PickLuaToolsAddSource": ("POST", "/add-source/{appid}"),
            "CancelAddViaLuaTools": ("POST", "/cancel/{appid}"),
            "OpenSettings": ("POST", "/open/settings"),
            "OpenFix": ("POST", "/open/fix/{appid}"),
            "RestartSteam": ("POST", "/restart-steam"),
            "ReadLoadedApps": ("GET", "/loaded-apps"),
            "DismissLoadedApps": ("POST", "/loaded-apps"),
            "GetApiList": ("GET", "/api-list"),
            "GetIconDataUrl": ("GET", "/icon")
        ]
        guard let (httpMethod, template) = map[method] else {
            return #"{"success":true}"#
        }
        var path = template
        if let data = argsJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in dict {
                path = path.replacingOccurrences(of: "{\(k)}", with: "\(v)")
            }
        }
        return await HttpServerService.shared.routeDirectRPC(method: httpMethod, path: path, body: argsJSON)
    }

    private static let polyfillJs = """
    (function(){
    var real=window.Millennium;
    var resolvers={},reqId=0;
    window.__macSteamResolve=function(id,val){
      var cb=resolvers[id];
      if(!cb)return;
      delete resolvers[id];
      cb.rv(val);
    };
    function ltCall(p,m,a){
      var i='_ltr_'+(++reqId);
      return new Promise(function(rv,rj){
        resolvers[i]={rv:rv,rj:rj};
        setTimeout(function(){if(resolvers[i]){delete resolvers[i];rv({success:true});}},10000);
        if(typeof window.__macSteamRPC==='function'){
          window.__macSteamRPC(JSON.stringify({id:i,method:m,args:JSON.stringify(a||{})}));
        }else{
          delete resolvers[i];rv({success:true});
        }
      });
    }
    if(real&&typeof real.callServerMethod==='function'){
      var realCall=real.callServerMethod.bind(real);
      real.callServerMethod=function(p,m,a){return p==='luatools'?ltCall(p,m,a):realCall(p,m,a)};
      window.Millennium=real;
    }else{
      window.Millennium={callServerMethod:function(p,m,a){return ltCall(p,m,a)}};
    }
    })();
    """
}
