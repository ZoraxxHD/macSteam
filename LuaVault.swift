// LuaVault, LuaEditor, Detailed Lua Parser, and Unified Installer syncing stplug-in <-> config.yaml.
import CryptoKit
import Foundation

extension Notification.Name {
    static let libraryDidChange = Notification.Name("MacsteamLibraryDidChange")
    static let vaultDidChange = Notification.Name("MacsteamVaultDidChange")
}

// MARK: - Detailed Lua Parser (Active + Commented entries & pins)

struct DetailedLuaEntry: Sendable, Equatable {
    var id: Int
    var key: String?
    var manifestId: String?
    var commentedManifestId: String?
    var comment: String?
    var sizeOnDisk: Int64?
    var isEnabled: Bool
    var isBaseApp: Bool

    var hasKey: Bool { key != nil }
    var isDlc: Bool { !isBaseApp && key == nil }
    var isLocked: Bool { manifestId != nil }
    var canLock: Bool { manifestId != nil || commentedManifestId != nil }
}

struct DetailedLuaContents: Sendable, Equatable {
    var baseAppId: Int
    var entries: [DetailedLuaEntry] // both enabled and disabled entries in order
    var activePins: [Int: String]
    var commentedPins: [Int: String]

    var depotCount: Int { entries.filter { $0.isEnabled && $0.hasKey }.count }
    var dlcCount: Int { entries.filter { $0.isEnabled && $0.isDlc }.count }
    var isPinned: Bool { !activePins.isEmpty }
}

enum DetailedLuaParser {
    private static let addAppRegex = try! NSRegularExpression(
        pattern: #"addappid\s*\(\s*(\d+)\s*(?:,\s*\d+\s*(?:,\s*"([0-9a-fA-F]*)"\s*)?)?\s*\)"#,
        options: .caseInsensitive
    )
    private static let setManifestRegex = try! NSRegularExpression(
        pattern: #"setManifestid\s*\(\s*(\d+)\s*,\s*"(\d+)"\s*(?:,\s*(\d+))?\s*\)"#,
        options: .caseInsensitive
    )

    static func parse(text: String, fallbackAppId: Int) -> DetailedLuaContents {
        var order: [Int] = []
        var keyById: [Int: String] = [:]
        var enabledById: [Int: Bool] = [:]
        var commentById: [Int: String] = [:]
        var activePins: [Int: String] = [:]
        var commentedPins: [Int: String] = [:]
        var sizes: [Int: Int64] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let isCommented = line.hasPrefix("--")
            let uncommented = isCommented
                ? String(line.drop(while: { $0 == "-" || $0 == " " || $0 == "\t" }))
                : line

            let nsLine = line as NSString
            let fullLineRange = NSRange(location: 0, length: nsLine.length)

            if let pm = setManifestRegex.firstMatch(in: line, range: fullLineRange),
               let depotId = Int(nsLine.substring(with: pm.range(at: 1))) {
                let gid = nsLine.substring(with: pm.range(at: 2))
                if isCommented {
                    commentedPins[depotId] = gid
                } else {
                    activePins[depotId] = gid
                }
                if pm.range(at: 3).location != NSNotFound,
                   let sz = Int64(nsLine.substring(with: pm.range(at: 3))), sz > 0 {
                    sizes[depotId] = sz
                }
            }

            let nsUncommented = uncommented as NSString
            let unRange = NSRange(location: 0, length: nsUncommented.length)
            if let am = addAppRegex.firstMatch(in: uncommented, range: unRange),
               let id = Int(nsUncommented.substring(with: am.range(at: 1))) {
                var key: String?
                if am.range(at: 2).location != NSNotFound {
                    let k = nsUncommented.substring(with: am.range(at: 2)).lowercased()
                    if !k.isEmpty { key = k }
                }

                // Extract trailing comment after the closing paren
                let afterParen = String(uncommented.dropFirst(am.range.location + am.range.length))
                if let cRange = afterParen.range(of: "--") {
                    let c = afterParen[cRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !c.isEmpty && !c.lowercased().contains("addappid") && !c.lowercased().contains("setmanifestid") {
                        commentById[id] = c
                    }
                }

                if !order.contains(id) {
                    order.append(id)
                }
                if let key {
                    keyById[id] = key
                }
                if !isCommented {
                    enabledById[id] = true
                } else if enabledById[id] == nil {
                    enabledById[id] = false
                }
            }
        }

        let baseId = order.first ?? fallbackAppId
        let entries: [DetailedLuaEntry] = order.map { id in
            DetailedLuaEntry(
                id: id,
                key: keyById[id],
                manifestId: activePins[id],
                commentedManifestId: commentedPins[id],
                comment: commentById[id],
                sizeOnDisk: sizes[id],
                isEnabled: enabledById[id] ?? true,
                isBaseApp: id == baseId && keyById[id] == nil
            )
        }
        return DetailedLuaContents(
            baseAppId: baseId,
            entries: entries,
            activePins: activePins,
            commentedPins: commentedPins
        )
    }

    static func diff(oldText: String, newText: String, appId: Int) -> (added: [DetailedLuaEntry], removed: [DetailedLuaEntry]) {
        let oldParsed = parse(text: oldText, fallbackAppId: appId)
        let newParsed = parse(text: newText, fallbackAppId: appId)
        let oldIds = Set(oldParsed.entries.filter(\.isEnabled).map(\.id))
        let newIds = Set(newParsed.entries.filter(\.isEnabled).map(\.id))
        let added = newParsed.entries.filter { $0.isEnabled && !oldIds.contains($0.id) }
        let removed = oldParsed.entries.filter { $0.isEnabled && !newIds.contains($0.id) }
        return (added, removed)
    }
}

// MARK: - LuaEditor (Comment/Uncomment addappid & setManifestid lines)

enum LuaEditor {
    static func setDepotLocked(lua: String, depotId: Int, locked: Bool) -> String {
        let pattern = #"^(\s*)(--\s*)?(setManifestid\s*\(\s*"# + "\(depotId)" + #"\s*[,)])"#
        return rewrite(lua: lua, pattern: pattern, active: locked)
    }

    static func setDepotEnabled(lua: String, depotId: Int, enabled: Bool) -> String {
        let pattern = #"^(\s*)(--\s*)?(addappid\s*\(\s*"# + "\(depotId)" + #"\s*[,)])"#
        return rewrite(lua: lua, pattern: pattern, active: enabled)
    }

    static func commentOutAllManifestPins(lua: String) -> String {
        let lines = lua.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let regex = try! NSRegularExpression(pattern: #"^(\s*)(setManifestid\s*\()"#, options: .caseInsensitive)
        let out = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--") { return line }
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard regex.firstMatch(in: line, range: range) != nil else { return line }
            return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1-- $2")
        }
        return out.joined(separator: "\n")
    }

    private static func rewrite(lua: String, pattern: String, active: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return lua
        }
        let lines = lua.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let updated = lines.map { line -> String in
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = regex.firstMatch(in: line, range: range) else { return line }
            let indent = ns.substring(with: m.range(at: 1))
            let hasComment = m.range(at: 2).location != NSNotFound
            if hasComment == !active { return line }
            if active {
                let commentEnd = m.range(at: 2).location + m.range(at: 2).length
                let rest = ns.substring(from: commentEnd)
                return indent + rest
            } else {
                let rest = ns.substring(from: m.range(at: 1).length)
                return indent + "-- " + rest
            }
        }
        return updated.joined(separator: "\n")
    }
}

// MARK: - LuaVariant & LuaVault

struct LuaVariant: Codable, Sendable, Equatable {
    var hash: String
    var kind: String // "default", "build", "preset"
    var buildId: String?
    var label: String?
    var capturedAt: Date
    var source: String?
    var manifestIds: [String: String]
    var depotCount: Int
    var dlcCount: Int

    var isPinned: Bool { !manifestIds.isEmpty }

    var displayLabel: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        if let buildId { return "Build \(buildId)" }
        if kind == "default" { return L10n.isFrench ? "Par défaut" : "Default" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "Preset (\(df.string(from: capturedAt)))"
    }
}

private struct VaultIndex: Codable {
    var appId: Int
    var variants: [LuaVariant] = []
    var editBaseHash: String?
}

final class LuaVault: @unchecked Sendable {
    static let shared = LuaVault()
    private let lock = NSLock()

    private init() {
        try? Paths.ensureDir(Paths.stPlugInDir)
        try? Paths.ensureDir(Paths.vaultDir)
    }

    private func appDir(_ appId: Int) -> URL {
        Paths.vaultDir.appendingPathComponent("\(appId)", isDirectory: true)
    }

    private func indexPath(_ appId: Int) -> URL {
        appDir(appId).appendingPathComponent("index.json")
    }

    private func variantPath(_ appId: Int, hash: String) -> URL {
        appDir(appId).appendingPathComponent("\(hash).lua")
    }

    func livePath(_ appId: Int) -> URL {
        Paths.stPlugInDir.appendingPathComponent("\(appId).lua")
    }

    func readLiveText(_ appId: Int) -> String? {
        let url = livePath(appId)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Synthesizes a `<appid>.lua` in `stplug-in` from `config.yaml` if the game was imported before `stplug-in` existed.
    func ensureLiveLua(for appId: Int, store: ConfigStore) -> String {
        if let existing = readLiveText(appId), !existing.isEmpty {
            syncDefaultFromLive(appId: appId)
            return existing
        }
        let cfg = store.config
        var lines: [String] = []
        let gameName = cfg.appNames[appId] ?? "App \(appId)"
        lines.append("-- \(gameName)")
        lines.append("addappid(\(appId)) -- \(gameName)")

        // Base depots
        if let baseGroup = cfg.depotKeyGroups.first(where: { $0.appID == appId }) {
            for (depotId, key) in baseGroup.depots {
                lines.append("addappid(\(depotId), 1, \"\(key)\")")
            }
        }
        // DLCs and their depots
        for dlcId in cfg.children(of: appId) {
            let dlcName = cfg.appNames[dlcId] ?? "DLC \(dlcId)"
            lines.append("addappid(\(dlcId)) -- \(dlcName)")
            if let dlcGroup = cfg.depotKeyGroups.first(where: { $0.appID == dlcId }) {
                for (depotId, key) in dlcGroup.depots {
                    lines.append("addappid(\(depotId), 1, \"\(key)\")")
                }
            }
        }
        // Any manifests in depotcache matching known depots
        let text = lines.joined(separator: "\n") + "\n"
        try? Paths.ensureDir(Paths.stPlugInDir)
        try? text.write(to: livePath(appId), atomically: true, encoding: .utf8)
        syncDefaultFromLive(appId: appId)
        return text
    }

    func getVariants(appId: Int) -> [LuaVariant] {
        lock.lock(); defer { lock.unlock() }
        return loadIndexLocked(appId).variants.sorted { $0.capturedAt > $1.capturedAt }
    }

    func getActiveHash(appId: Int) -> String? {
        guard let text = readLiveText(appId) else { return nil }
        return Self.hashText(text)
    }

    @discardableResult
    func capture(appId: Int, luaText: String, kind: String, buildId: String? = nil, source: String? = nil, label: String? = nil) -> LuaVariant {
        let hash = Self.hashText(luaText)
        lock.lock()
        var index = loadIndexLocked(appId)
        if let i = index.variants.firstIndex(where: { $0.hash == hash }) {
            if index.variants[i].buildId == nil, let buildId {
                index.variants[i].buildId = buildId
                index.variants[i].kind = "build"
            }
            if let label, !label.isEmpty {
                index.variants[i].label = label
            }
            let existing = index.variants[i]
            saveIndexLocked(appId, index: index)
            lock.unlock()
            return existing
        }

        try? Paths.ensureDir(appDir(appId))
        try? luaText.write(to: variantPath(appId, hash: hash), atomically: true, encoding: .utf8)

        let parsed = DetailedLuaParser.parse(text: luaText, fallbackAppId: appId)
        var pins: [String: String] = [:]
        for (k, v) in parsed.activePins { pins["\(k)"] = v }

        let variant = LuaVariant(
            hash: hash,
            kind: buildId != nil ? "build" : kind,
            buildId: buildId,
            label: label,
            capturedAt: Date(),
            source: source,
            manifestIds: pins,
            depotCount: parsed.depotCount,
            dlcCount: parsed.dlcCount
        )
        index.variants.append(variant)
        saveIndexLocked(appId, index: index)
        lock.unlock()
        notifyVaultChanged(appId)
        return variant
    }

    func syncDefaultFromLive(appId: Int) {
        guard let liveText = readLiveText(appId), !liveText.isEmpty else { return }
        let liveHash = Self.hashText(liveText)
        lock.lock()
        var index = loadIndexLocked(appId)
        if index.variants.contains(where: { $0.hash == liveHash }) {
            lock.unlock()
            return
        }
        // Replace old default
        for old in index.variants where old.kind == "default" && old.hash != liveHash {
            try? FileManager.default.removeItem(at: variantPath(appId, hash: old.hash))
        }
        index.variants.removeAll { $0.kind == "default" && $0.hash != liveHash }

        try? Paths.ensureDir(appDir(appId))
        try? liveText.write(to: variantPath(appId, hash: liveHash), atomically: true, encoding: .utf8)
        let parsed = DetailedLuaParser.parse(text: liveText, fallbackAppId: appId)
        var pins: [String: String] = [:]
        for (k, v) in parsed.activePins { pins["\(k)"] = v }

        let defVariant = LuaVariant(
            hash: liveHash,
            kind: "default",
            buildId: nil,
            label: nil,
            capturedAt: Date(),
            source: nil,
            manifestIds: pins,
            depotCount: parsed.depotCount,
            dlcCount: parsed.dlcCount
        )
        index.variants.append(defVariant)
        saveIndexLocked(appId, index: index)
        lock.unlock()
    }

    func applyVariant(appId: Int, variant: LuaVariant, store: ConfigStore) -> Bool {
        let src = variantPath(appId, hash: variant.hash)
        guard let text = try? String(contentsOf: src, encoding: .utf8) else { return false }
        return writeLiveAndSyncConfig(appId: appId, luaText: text, store: store)
    }

    @discardableResult
    func writeLiveAndSyncConfig(appId: Int, luaText: String, store: ConfigStore) -> Bool {
        do {
            try Paths.ensureDir(Paths.stPlugInDir)
            try luaText.write(to: livePath(appId), atomically: true, encoding: .utf8)
            CrossOverInstaller.syncLuaFiles()

            // Sync enabled apps, DLCs, and depot keys with ConfigStore (config.yaml)
            let script = LuaManifestParser.parse(luaText)
            try store.mutate { cfg in
                // Remove old child DLCs and depot groups for this app before re-merging active ones
                let existingChildren = cfg.children(of: appId)
                let dropIds = Set([appId] + existingChildren)
                cfg.depotKeyGroups.removeAll { dropIds.contains($0.appID) }
                for child in existingChildren {
                    cfg.apps.removeAll { $0 == child }
                }
                _ = cfg.addApp(appId)
                _ = cfg.addPackage(Paths.defaultInjectionPackage)
                for dlc in script.dlcAppIDs {
                    _ = cfg.addApp(dlc)
                    cfg.appParents[dlc] = appId
                }
                for (id, name) in script.appNames {
                    cfg.appNames[id] = name
                }
                for (depot, key) in script.depotKeys {
                    let owner = script.depotOwner[depot] ?? appId
                    _ = cfg.upsertDepotKey(appID: owner, depotID: depot, key: key)
                }
            }
            notifyVaultChanged(appId)
            return true
        } catch {
            return false
        }
    }

    func renameVariant(appId: Int, hash: String, newLabel: String?) {
        lock.lock()
        var index = loadIndexLocked(appId)
        if let i = index.variants.firstIndex(where: { $0.hash == hash }) {
            let trimmed = newLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            index.variants[i].label = (trimmed?.isEmpty == false) ? trimmed : nil
            saveIndexLocked(appId, index: index)
        }
        lock.unlock()
        notifyVaultChanged(appId)
    }

    func deleteVariant(appId: Int, hash: String) -> Bool {
        if getActiveHash(appId: appId) == hash { return false }
        lock.lock()
        var index = loadIndexLocked(appId)
        let before = index.variants.count
        index.variants.removeAll { $0.hash == hash }
        guard index.variants.count < before else { lock.unlock(); return false }
        saveIndexLocked(appId, index: index)
        try? FileManager.default.removeItem(at: variantPath(appId, hash: hash))
        lock.unlock()
        notifyVaultChanged(appId)
        return true
    }

    private func loadIndexLocked(_ appId: Int) -> VaultIndex {
        let p = indexPath(appId)
        if let data = try? Data(contentsOf: p),
           let decoded = try? JSONDecoder().decode(VaultIndex.self, from: data) {
            return decoded
        }
        return VaultIndex(appId: appId)
    }

    private func saveIndexLocked(_ appId: Int, index: VaultIndex) {
        try? Paths.ensureDir(appDir(appId))
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexPath(appId), options: .atomic)
        }
    }

    private func notifyVaultChanged(_ appId: Int) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .vaultDidChange, object: appId)
            NotificationCenter.default.post(name: .libraryDidChange, object: appId)
        }
    }

    static func hashText(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Unified Installer (Downloads & Local Imports -> stplug-in + depotcache + LuaVault + ConfigStore)

enum UnifiedInstaller {
    private static let buildIdRegex = try! NSRegularExpression(pattern: #"^\s*\d+_(\d+)\s*$"#)

    static func isZipFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 4) else { return false }
        try? handle.close()
        return magic == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static func extractBuildId(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        let ns = stem as NSString
        guard let m = buildIdRegex.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    @discardableResult
    static func installDownloaded(
        fileURL: URL,
        appId: Int,
        gameName: String?,
        source: String?,
        forceLocked: Bool = false,
        store: ConfigStore
    ) throws -> (manifestCount: Int, dlcCount: Int) {
        let isZip = isZipFile(fileURL)
        let plans: [ImportPlan]
        if isZip {
            plans = try ZipImporter.buildPlans(from: fileURL)
        } else {
            plans = [try ZipImporter.buildPlan(fromLua: fileURL)]
        }
        defer {
            for p in plans { ZipImporter.cleanup(p.extractDir) }
        }
        guard let plan = plans.first else {
            throw ImportError.noLua
        }

        let resolvedAppId = plan.mainAppID ?? appId
        let manifestCount = try ZipImporter.copyManifests(plan.manifestFiles)

        // Read raw lua text from extractDir or source
        var rawLuaText = ""
        if isZip {
            if let files = try? FileManager.default.contentsOfDirectory(at: plan.extractDir, includingPropertiesForKeys: nil),
               let luaURL = files.first(where: { $0.pathExtension.lowercased() == "lua" }),
               let txt = try? String(contentsOf: luaURL, encoding: .utf8) {
                rawLuaText = txt
            }
        } else if let txt = try? String(contentsOf: fileURL, encoding: .utf8) {
            rawLuaText = txt
        }

        let buildId = extractBuildId(from: fileURL.lastPathComponent)
        let shouldStripPins = AppSettings.shared.autoUpdateApps && !forceLocked && buildId == nil
        let installedLuaText = shouldStripPins ? LuaEditor.commentOutAllManifestPins(lua: rawLuaText) : rawLuaText

        if !installedLuaText.isEmpty {
            try Paths.ensureDir(Paths.stPlugInDir)
            try installedLuaText.write(
                to: LuaVault.shared.livePath(resolvedAppId),
                atomically: true,
                encoding: .utf8
            )
            if let buildId {
                LuaVault.shared.capture(
                    appId: resolvedAppId,
                    luaText: rawLuaText,
                    kind: "build",
                    buildId: buildId,
                    source: source
                )
            } else {
                LuaVault.shared.syncDefaultFromLive(appId: resolvedAppId)
            }
        }

        try store.mutate { cfg in
            var mutablePlan = plan
            if mutablePlan.mainAppID == nil { mutablePlan.mainAppID = resolvedAppId }
            if let gameName, !gameName.isEmpty {
                mutablePlan.appNames[resolvedAppId] = gameName
            }
            _ = ZipImporter.merge(mutablePlan, into: &cfg)
        }

        AppSettings.shared.recordLoadedApp(resolvedAppId)
        DonateKeysService.sendPendingKeysIfEnabled(config: store.config)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .libraryDidChange, object: resolvedAppId)
        }
        return (manifestCount, plan.dlcAppIDs.count)
    }
}
