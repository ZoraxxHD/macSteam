// macOS Steam Library resolver, Launch Options editor (localconfig.vdf), and Fix applicator/reverter.
import AppKit
import Foundation

enum SteamLibraryService {
    private static let pathRegex = try! NSRegularExpression(pattern: #""path"\s*"([^"]+)""#, options: .caseInsensitive)
    private static let installDirRegex = try! NSRegularExpression(pattern: #""installdir"\s*"([^"]+)""#, options: .caseInsensitive)

    static func getLibraryRoots() -> [URL] {
        var roots: [URL] = []

        func appendUnique(_ url: URL) {
            let std = url.standardizedFileURL
            if !roots.contains(where: { $0.standardizedFileURL == std }),
               FileManager.default.fileExists(atPath: url.path) {
                roots.append(url)
            }
        }

        func collectFromSteamRoot(_ steamRoot: URL, bottleRoot: URL?) {
            appendUnique(steamRoot)
            let vdfURL = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
            guard let text = try? String(contentsOf: vdfURL, encoding: .utf8) else { return }
            let ns = text as NSString
            for m in pathRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: #"\\"#, with: "/")
                let resolvedPath: String
                if let bottleRoot, raw.lowercased().hasPrefix("c:/") {
                    let tail = String(raw.dropFirst(3))
                    resolvedPath = bottleRoot.appendingPathComponent("drive_c").appendingPathComponent(tail).path
                } else if raw.lowercased().hasPrefix("z:/") {
                    resolvedPath = "/" + String(raw.dropFirst(3))
                } else {
                    resolvedPath = raw
                }
                appendUnique(URL(fileURLWithPath: resolvedPath, isDirectory: true))
            }
        }

        // 1. Native macOS Steam libraries
        collectFromSteamRoot(Paths.steamRoot, bottleRoot: nil)

        // 2. CrossOver Windows Steam bottle libraries
        for bottle in CrossOverInstaller.findSteamBottles() {
            collectFromSteamRoot(bottle.steamDir, bottleRoot: bottle.root)
        }

        return roots
    }

    static func getInstallDir(appId: Int) -> URL? {
        let fm = FileManager.default
        for root in getLibraryRoots() {
            let acf = root.appendingPathComponent("steamapps/appmanifest_\(appId).acf")
            guard let text = try? String(contentsOf: acf, encoding: .utf8) else { continue }
            let ns = text as NSString
            guard let m = installDirRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let dirName = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: #"\\"#, with: "/")
            let commonDir = root.appendingPathComponent("steamapps/common").appendingPathComponent(dirName, isDirectory: true)
            if fm.fileExists(atPath: commonDir.path) {
                return commonDir
            }
        }
        return nil
    }

    // MARK: - Steam Process & Deep Links

    static func restartSteam() {
        // Close CrossOver Steam too so the two clients don't kick each other offline
        CrossOverInstaller.closeCrossOverSteam()
        Subprocess.killSteam()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSWorkspace.shared.open(Paths.steamApp)
        }
    }

    static func openSteamURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Launch Options (userdata/<uid>/config/localconfig.vdf)

    private static func findLocalConfigFiles() -> [URL] {
        var steamRoots: [URL] = [Paths.steamRoot]
        for bottle in CrossOverInstaller.findSteamBottles() {
            steamRoots.append(bottle.steamDir)
        }
        var out: [URL] = []
        for root in steamRoots {
            let userdata = root.appendingPathComponent("userdata", isDirectory: true)
            guard let users = try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil) else {
                continue
            }
            for u in users {
                let cfg = u.appendingPathComponent("config/localconfig.vdf")
                if FileManager.default.fileExists(atPath: cfg.path) {
                    out.append(cfg)
                }
            }
        }
        return out
    }

    static func readLaunchOptions(appId: Int) -> String {
        for file in findLocalConfigFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if let opts = extractLaunchOptions(from: text, appId: appId) {
                return opts
            }
        }
        return ""
    }

    @discardableResult
    static func writeLaunchOptions(appId: Int, options: String) -> Bool {
        let files = findLocalConfigFiles()
        guard !files.isEmpty else { return false }
        var anySaved = false
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let updated = updateLaunchOptions(in: text, appId: appId, options: options)
            if (try? updated.write(to: file, atomically: true, encoding: .utf8)) != nil {
                anySaved = true
            }
        }
        return anySaved
    }

    private static func extractLaunchOptions(from vdf: String, appId: Int) -> String? {
        let pattern = #""\#(appId)"\s*\{[^}]*?"LaunchOptions"\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let ns = vdf as NSString
        guard let m = regex.firstMatch(in: vdf, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: m.range(at: 1))
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\"#, with: "\\")
    }

    private static func updateLaunchOptions(in vdf: String, appId: Int, options: String) -> String {
        let escaped = options
            .replacingOccurrences(of: "\\", with: #"\\"#)
            .replacingOccurrences(of: "\"", with: #"\""#)

        // 1. If app block already has "LaunchOptions", replace its value
        let existingOptPattern = #"("\#(appId)"\s*\{[^}]*?"LaunchOptions"\s*")"((?:[^"\\]|\\.)*)"(")"#
        if let regex = try? NSRegularExpression(pattern: existingOptPattern, options: [.dotMatchesLineSeparators]) {
            let ns = vdf as NSString
            let range = NSRange(location: 0, length: ns.length)
            if regex.firstMatch(in: vdf, range: range) != nil {
                return regex.stringByReplacingMatches(in: vdf, range: range, withTemplate: "$1\(escaped)$3")
            }
        }

        // 2. If app block exists without "LaunchOptions", insert it right after "<appId>" {
        let appBlockPattern = #"("\#(appId)"\s*\{\s*\n)"#
        if let regex = try? NSRegularExpression(pattern: appBlockPattern) {
            let ns = vdf as NSString
            let range = NSRange(location: 0, length: ns.length)
            if regex.firstMatch(in: vdf, range: range) != nil {
                return regex.stringByReplacingMatches(
                    in: vdf,
                    range: range,
                    withTemplate: "$1\t\t\t\t\t\t\"LaunchOptions\"\t\t\"\(escaped)\"\n"
                )
            }
        }
        return vdf
    }

    // MARK: - Denuvo / Game Fix Apply & Revert

    private static let fixRecordDirName = ".luatools-fix"

    static func safeFixKey(_ fixId: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return fixId.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
    }

    static func fixRecordURL(installDir: URL, fixId: String) -> URL {
        installDir
            .appendingPathComponent(fixRecordDirName, isDirectory: true)
            .appendingPathComponent("\(safeFixKey(fixId)).json")
    }

    static func isFixApplied(appId: Int, fixId: String) -> Bool {
        guard let dir = getInstallDir(appId: appId) else { return false }
        return FileManager.default.fileExists(atPath: fixRecordURL(installDir: dir, fixId: fixId).path)
    }

    private static let wineProxyDllStems: Set<String> = [
        "winmm", "version", "winhttp", "dinput8", "dsound",
        "xinput1_3", "xinput1_4", "xinput9_1_0", "dwmapi",
        "dxgi", "d3d9", "d3d11", "d3d12", "opengl32",
        "psapi", "profapi", "iphlpapi", "ws2_32", "msimg32", "hid"
    ]

    static func applyFixArchive(zipURL: URL, appId: Int, fixId: String) throws {
        guard let installDir = getInstallDir(appId: appId) else {
            throw NSError(domain: "SteamLibrary", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.tr("fixes.status.game_not_installed")])
        }
        let fm = FileManager.default

        // Clean up any prior broken `/private*` files if a previous version extracted with symlink mismatch
        let recURL = fixRecordURL(installDir: installDir, fixId: fixId)
        if fm.fileExists(atPath: recURL.path) {
            try? revertFix(appId: appId, fixId: fixId)
        }

        let tmpExtract = fm.temporaryDirectory.appendingPathComponent("macsteam-fix-\(UUID().uuidString)", isDirectory: true)
        try Paths.ensureDir(tmpExtract)
        defer { try? fm.removeItem(at: tmpExtract) }

        let res = Subprocess.run("/usr/bin/unzip", ["-o", zipURL.path, "-d", tmpExtract.path])
        if res.code != 0 {
            throw NSError(domain: "SteamLibrary", code: Int(res.code), userInfo: [NSLocalizedDescriptionKey: "Unzip failed: \(res.stderr)"])
        }

        let fixKey = safeFixKey(fixId)
        let fixDir = installDir.appendingPathComponent(fixRecordDirName, isDirectory: true)
        try Paths.ensureDir(fixDir)

        // Resolve `/var` -> `/private/var` symlinks on BOTH paths so prefix stripping never leaves "private..."
        let canonicalExtract = tmpExtract.resolvingSymlinksInPath().standardizedFileURL
        let basePrefix = canonicalExtract.path.hasSuffix("/") ? canonicalExtract.path : canonicalExtract.path + "/"

        var entries: [DenuvoFixRecordEntry] = []
        var extractedDllStems: Set<String> = []
        let enumerator = fm.enumerator(at: canonicalExtract, includingPropertiesForKeys: [.isDirectoryKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }

            let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            var relPath: String
            if canonicalFile.hasPrefix(basePrefix) {
                relPath = String(canonicalFile.dropFirst(basePrefix.count))
            } else {
                let rawBase = tmpExtract.path.hasSuffix("/") ? tmpExtract.path : tmpExtract.path + "/"
                relPath = fileURL.path.replacingOccurrences(of: rawBase, with: "")
                if relPath.hasPrefix("/private") {
                    relPath = String(relPath.dropFirst("/private".count))
                }
            }
            while relPath.hasPrefix("/") {
                relPath.removeFirst()
            }
            if relPath.isEmpty || relPath.contains("..") { continue }

            let destURL = installDir.appendingPathComponent(relPath)
            if destURL.pathExtension.lowercased() == "dll" {
                let stem = destURL.deletingPathExtension().lastPathComponent.lowercased()
                if wineProxyDllStems.contains(stem) {
                    extractedDllStems.insert(stem)
                }
            }

            if fm.fileExists(atPath: destURL.path) {
                let bakRel = "\(fixKey)/\(relPath).bak"
                let bakAbs = fixDir.appendingPathComponent(bakRel)
                try Paths.ensureDir(bakAbs.deletingLastPathComponent())
                if !fm.fileExists(atPath: bakAbs.path) {
                    try fm.copyItem(at: destURL, to: bakAbs)
                }
                try fm.removeItem(at: destURL)
                try fm.copyItem(at: fileURL, to: destURL)
                entries.append(DenuvoFixRecordEntry(relativePath: relPath, action: "modified", backupPath: bakRel))
            } else {
                try Paths.ensureDir(destURL.deletingLastPathComponent())
                try fm.copyItem(at: fileURL, to: destURL)
                entries.append(DenuvoFixRecordEntry(relativePath: relPath, action: "added", backupPath: nil))
            }
        }

        // Ensure default Wine DLL overrides (OnlineFix64, SteamOverlay64, steam_api64, dnet, winmm)
        // are configured and pushed live to wineserver if CrossOver Steam is running.
        CrossOverInstaller.ensureAllBottlesWineOverrides()
        if !extractedDllStems.isEmpty {
            registerCrossOverDllOverridesIfNeeded(installDir: installDir, dllStems: extractedDllStems)
        }

        let record = DenuvoFixRecord(
            appId: appId,
            fixId: fixId,
            appliedAt: ISO8601DateFormatter().string(from: Date()),
            files: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let recordData = try encoder.encode(record)
        try recordData.write(to: recURL, options: .atomic)
    }

    static func revertFix(appId: Int, fixId: String) throws {
        guard let installDir = getInstallDir(appId: appId) else {
            throw NSError(domain: "SteamLibrary", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.tr("fixes.status.game_not_installed")])
        }
        let recURL = fixRecordURL(installDir: installDir, fixId: fixId)
        let data = try Data(contentsOf: recURL)
        let record = try JSONDecoder().decode(DenuvoFixRecord.self, from: data)
        let fm = FileManager.default
        let fixDir = installDir.appendingPathComponent(fixRecordDirName, isDirectory: true)

        for entry in record.files {
            var rel = entry.relativePath
            while rel.hasPrefix("/") { rel.removeFirst() }
            if rel.contains("..") { continue }
            let target = installDir.appendingPathComponent(rel)
            if entry.action == "modified", let bakRel = entry.backupPath {
                let bakURL = fixDir.appendingPathComponent(bakRel)
                if fm.fileExists(atPath: bakURL.path) {
                    try? fm.removeItem(at: target)
                    try? fm.copyItem(at: bakURL, to: target)
                    try? fm.removeItem(at: bakURL)
                }
            } else if entry.action == "added" {
                try? fm.removeItem(at: target)
                // Clean up empty parent folder if it was a broken `private*` folder
                let parent = target.deletingLastPathComponent()
                if parent != installDir,
                   parent.lastPathComponent.hasPrefix("private"),
                   ((try? fm.contentsOfDirectory(atPath: parent.path))?.isEmpty == true) {
                    try? fm.removeItem(at: parent)
                }
            }
        }
        try? fm.removeItem(at: recURL)
    }

    /// Registers `"<dll>"="native,builtin"` under `[Software\\Wine\\AppDefaults\\<exe>\\DllOverrides]`
    /// in the CrossOver bottle's `user.reg` so Wine loads proxy fix DLLs (e.g. `winmm.dll` for Online-Fix).
    static func registerCrossOverDllOverridesIfNeeded(installDir: URL, dllStems: Set<String>) {
        guard let bottle = CrossOverInstaller.findSteamBottles().first(where: {
            installDir.standardizedFileURL.path.hasPrefix($0.root.standardizedFileURL.path)
        }) else { return }

        let regURL = bottle.root.appendingPathComponent("user.reg")
        guard var regText = try? String(contentsOf: regURL, encoding: .utf8) else { return }

        let fm = FileManager.default
        var exeNames: Set<String> = []
        if let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let name = url.lastPathComponent
                let lower = name.lowercased()
                if lower.contains("crashhandler") || lower.hasPrefix("unins") || lower.contains("redist") || lower.contains("setup") {
                    continue
                }
                exeNames.insert(name)
            }
        }
        guard !exeNames.isEmpty else { return }

        var modified = false
        for exe in exeNames.sorted() {
            let sectionHeader = "[Software\\\\Wine\\\\AppDefaults\\\\\(exe)\\\\DllOverrides]"
            if let range = regText.range(of: sectionHeader) {
                let afterHeader = regText[range.upperBound...]
                let nextSection = afterHeader.range(of: "\n[")?.lowerBound ?? regText.endIndex
                let sectionSlice = String(regText[range.lowerBound..<nextSection])
                var additions: [String] = []
                for dll in dllStems.sorted() {
                    let key = "\"\(dll)\"="
                    if !sectionSlice.contains(key) {
                        additions.append("\"\(dll)\"=\"native,builtin\"")
                    }
                }
                if !additions.isEmpty, let lineEnd = regText[range.upperBound...].firstIndex(of: "\n") {
                    let insertBlock = "\n" + additions.joined(separator: "\n")
                    regText.insert(contentsOf: insertBlock, at: lineEnd)
                    modified = true
                }
            } else {
                var block = "\n\(sectionHeader) \(Int(Date().timeIntervalSince1970))\n"
                for dll in dllStems.sorted() {
                    block += "\"\(dll)\"=\"native,builtin\"\n"
                }
                regText.append(block)
                modified = true
            }
        }

        if modified {
            try? regText.write(to: regURL, atomically: true, encoding: .utf8)
            let liveOverrides = dllStems.sorted().map { ($0, "native,builtin") }
            for exe in exeNames.sorted() {
                CrossOverInstaller.applyLiveWineRegistryOverrides(
                    bottleName: bottle.name,
                    regKey: "HKCU\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides",
                    overrides: liveOverrides
                )
            }
        }
    }
}
