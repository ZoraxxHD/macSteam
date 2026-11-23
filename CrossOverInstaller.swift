// CrossOver (Windows Steam) BetterSteamTools installer and Lua sync
import AppKit
import Foundation

enum CrossOverInstaller {

    struct Bottle {
        let name: String
        let root: URL
        let steamDir: URL
    }

    enum Status: Equatable {
        case noCrossOver
        case notInstalled(bottle: String)
        case installed(bottle: String)
    }

    private static let latestTomlURL =
        "https://raw.githubusercontent.com/madoiscool/BetterSteamTools/refs/heads/updates/opensteamtool/latest.toml"
    private static let fallbackVersion = "v1.0.9"
    private static let dllNames = ["dwmapi.dll", "xinput1_4.dll", "OpenSteamTool.dll"]

    static var bottlesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
    }

    static func findSteamBottles() -> [Bottle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: bottlesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [Bottle] = []
        for dir in entries {
            let steamDir = dir.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
            let steamExe = steamDir.appendingPathComponent("steam.exe")
            let steamDll = steamDir.appendingPathComponent("Steam.dll")
            if fm.fileExists(atPath: steamExe.path) || fm.fileExists(atPath: steamDll.path) {
                result.append(Bottle(name: dir.lastPathComponent, root: dir, steamDir: steamDir))
            }
        }
        return result.sorted { a, b in
            let aIsSteam = a.name.caseInsensitiveCompare("Steam") == .orderedSame
            let bIsSteam = b.name.caseInsensitiveCompare("Steam") == .orderedSame
            if aIsSteam != bIsSteam { return aIsSteam }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func status() -> Status {
        let bottles = findSteamBottles()
        guard let first = bottles.first else { return .noCrossOver }
        let fm = FileManager.default
        let hasDLLs = dllNames.allSatisfy {
            fm.fileExists(atPath: first.steamDir.appendingPathComponent($0).path)
        }
        let hasToml = fm.fileExists(atPath: first.steamDir.appendingPathComponent("opensteamtool.toml").path)
        let hasOverride = hasWineDllOverride(in: first.root)
        if hasDLLs && hasToml && hasOverride {
            return .installed(bottle: first.name)
        }
        return .notInstalled(bottle: first.name)
    }

    static func install(progress: (@Sendable (String) -> Void)? = nil) throws {
        let bottles = findSteamBottles()
        guard !bottles.isEmpty else {
            throw StepFailure(step: "Locate CrossOver Steam",
                              detail: "No CrossOver bottle with Windows Steam found in ~/Library/Application Support/CrossOver/Bottles/.")
        }

        let fm = FileManager.default
        let work = Paths.configDir.appendingPathComponent("bst-crossover", isDirectory: true)
        try? fm.removeItem(at: work)
        try Paths.ensureDir(work)
        defer { try? fm.removeItem(at: work) }

        progress?("Checking latest BetterSteamTools version")
        let version = fetchLatestVersion() ?? fallbackVersion
        let zipURL = "https://github.com/madoiscool/BetterSteamTools/releases/download/\(version)/OpenSteamTool-\(version)-Release.zip"
        let zipPath = work.appendingPathComponent("bst.zip")

        progress?("Downloading BetterSteamTools \(version)")
        let dl = Subprocess.run("/usr/bin/curl", ["-fSL", zipURL, "-o", zipPath.path])
        guard dl.code == 0, fm.fileExists(atPath: zipPath.path) else {
            throw StepFailure(step: "Download BetterSteamTools",
                              detail: dl.stderr.isEmpty ? "curl exit \(dl.code)" : dl.stderr)
        }

        let extractDir = work.appendingPathComponent("extracted", isDirectory: true)
        try Paths.ensureDir(extractDir)
        let uz = Subprocess.run("/usr/bin/unzip", ["-oq", zipPath.path, "-d", extractDir.path])
        guard uz.code == 0 else {
            throw StepFailure(step: "Extract BetterSteamTools",
                              detail: uz.stderr.isEmpty ? "unzip exit \(uz.code)" : uz.stderr)
        }

        for bottle in bottles {
            progress?("Installing into CrossOver bottle '\(bottle.name)'")
            for dll in dllNames {
                guard let src = findFile(named: dll, under: extractDir) else {
                    throw StepFailure(step: "Locate \(dll)",
                                      detail: "\(dll) was not found inside BetterSteamTools archive.")
                }
                let dst = bottle.steamDir.appendingPathComponent(dll)
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
            }

            try writeOpenSteamToolToml(in: bottle.steamDir)
            try ensureWineDllOverride(in: bottle.root)
            clearAppCache(in: bottle.steamDir)
        }

        progress?("Syncing Lua game files")
        syncLuaFiles()
        progress?("Done")
    }

    /// Removes Steam's `appcache/packageinfo.vdf` and `appcache/appinfo.vdf` so Windows Steam
    /// rebuilds its license/library cache with newly added OpenSteamTool `.lua` manifests.
    static func clearAppCache(in steamDir: URL) {
        let fm = FileManager.default
        let appcache = steamDir.appendingPathComponent("appcache", isDirectory: true)
        for name in ["packageinfo.vdf", "appinfo.vdf"] {
            let file = appcache.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) {
                try? fm.removeItem(at: file)
            }
        }
    }

    static func syncLuaFiles() {
        let fm = FileManager.default
        let bottles = findSteamBottles()
        guard !bottles.isEmpty else { return }

        let srcFiles = (try? fm.contentsOfDirectory(
            at: Paths.stPlugInDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "lua" } ?? []

        let srcNames = Set(srcFiles.map(\.lastPathComponent))
        let steamRunning = isCrossOverSteamRunning()

        for bottle in bottles {
            let dstDir = bottle.steamDir.appendingPathComponent("config/stplug-in", isDirectory: true)
            try? Paths.ensureDir(dstDir)
            var changed = false

            if let existing = try? fm.contentsOfDirectory(at: dstDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in existing where url.pathExtension.lowercased() == "lua" {
                    let name = url.lastPathComponent
                    if name != "manifest.lua" && !srcNames.contains(name) {
                        try? fm.removeItem(at: url)
                        changed = true
                    }
                }
            }

            for src in srcFiles {
                let dst = dstDir.appendingPathComponent(src.lastPathComponent)
                if fm.fileExists(atPath: dst.path) {
                    if (try? Data(contentsOf: src)) == (try? Data(contentsOf: dst)) {
                        continue
                    }
                    try? fm.removeItem(at: dst)
                }
                if (try? fm.copyItem(at: src, to: dst)) != nil {
                    changed = true
                }
            }

            if changed && !steamRunning {
                clearAppCache(in: bottle.steamDir)
            }
        }
    }

    static func isCrossOverSteamRunning() -> Bool {
        let out = Subprocess.run("/usr/bin/pgrep", ["-if", "steam\\.exe"])
        return out.code == 0
    }

    /// Cleanly terminates CrossOver's Windows Steam processes (`steam.exe` / `steamwebhelper.exe`).
    static func closeCrossOverSteam() {
        _ = Subprocess.run("/usr/bin/pkill", ["-if", "steam\\.exe"])
        _ = Subprocess.run("/usr/bin/pkill", ["-if", "steamwebhelper\\.exe"])
    }

    static func syncedLuaCount() -> Int {
        guard let bottle = findSteamBottles().first else { return 0 }
        let dstDir = bottle.steamDir.appendingPathComponent("config/stplug-in", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dstDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "lua" && $0.lastPathComponent != "manifest.lua" }.count
    }

    static func openCrossOverSteam(closeMacSteam: Bool = true) {
        guard let bottle = findSteamBottles().first else { return }
        let cxWine = "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
        DispatchQueue.global(qos: .userInitiated).async {
            try? ensureWineDllOverride(in: bottle.root)
            if closeMacSteam {
                // Prevent dual-client session conflicts ("PAS DE CONNEXION" / 0-byte downloads)
                Subprocess.killSteam()
            }
            if FileManager.default.fileExists(atPath: cxWine) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cxWine)
                p.arguments = ["--bottle", bottle.name, "C:\\Program Files (x86)\\Steam\\steam.exe"]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
            } else {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/CrossOver.app"))
                }
            }
        }
    }

    /// Closes macOS Steam (to prevent session conflicts), restarts CrossOver Steam, clears stale
    /// `appcache` (`packageinfo.vdf` / `appinfo.vdf`), and syncs Lua files so newly added games appear immediately.
    static func restartCrossOverSteam() {
        DispatchQueue.global(qos: .userInitiated).async {
            Subprocess.killSteam()
            if isCrossOverSteamRunning() {
                closeCrossOverSteam()
                Thread.sleep(forTimeInterval: 1.5)
            }
            for bottle in findSteamBottles() {
                clearAppCache(in: bottle.steamDir)
            }
            syncLuaFiles()
            openCrossOverSteam(closeMacSteam: false)
        }
    }

    // MARK: - Helpers

    private static func fetchLatestVersion() -> String? {
        let out = Subprocess.run("/usr/bin/curl", ["-fsSL", "--max-time", "8", latestTomlURL])
        guard out.code == 0 else { return nil }
        for line in out.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version") {
                let parts = trimmed.split(separator: "\"")
                if parts.count >= 2 {
                    return String(parts[1])
                }
            }
        }
        return nil
    }

    private static func findFile(named name: String, under root: URL) -> URL? {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                return url
            }
        }
        return nil
    }

    private static func writeOpenSteamToolToml(in steamDir: URL) throws {
        let tomlURL = steamDir.appendingPathComponent("opensteamtool.toml")
        let existingCloudEnabled: Bool? = (try? String(contentsOf: tomlURL, encoding: .utf8))
            .flatMap { CloudRedirectInstaller.extractCloudSectionEnabled(from: $0) }

        var content = """
        [manifest]
        provider = "wudrm"

        [lua]
        paths = ["config/stplug-in"]
        """ + "\n"

        if let cloudEnabled = existingCloudEnabled {
            content += "\n[cloud]\nenabled = \(cloudEnabled ? "true" : "false")\n"
        }

        try content.write(to: tomlURL, atomically: true, encoding: .utf8)
    }

    private static let steamExeOverrides: [(String, String)] = [
        ("dwmapi", "native,builtin"),
        ("xinput1_4", "native,builtin"),
    ]

    private static let defaultWineDllOverrides: [(String, String)] = [
        ("OnlineFix64", "native"),
        ("SteamOverlay64", "native"),
        ("steam_api64", "native"),
        ("dnet", "native"),
        ("winmm", "native,builtin"),
    ]

    /// Automatically configures Wine DLL overrides (`dwmapi`, `xinput1_4` for `steam.exe`
    /// and default Wine overrides for Online-Fix) on all detected CrossOver Steam bottles.
    static func ensureAllBottlesWineOverrides() {
        for bottle in findSteamBottles() {
            try? ensureWineDllOverride(in: bottle.root)
        }
    }

    /// Pushes DLL overrides directly into a running `wineserver` session via `wine reg add`
    /// so the active bottle immediately picks them up in RAM and does not overwrite `user.reg` on exit.
    static func applyLiveWineRegistryOverrides(
        bottleName: String,
        regKey: String,
        overrides: [(String, String)]
    ) {
        let cxWine = "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
        guard FileManager.default.fileExists(atPath: cxWine), isCrossOverSteamRunning() else { return }
        for (dll, mode) in overrides {
            _ = Subprocess.run(cxWine, [
                "--bottle", bottleName,
                "reg", "add", regKey,
                "/v", dll,
                "/t", "REG_SZ",
                "/d", mode,
                "/f",
            ])
        }
    }

    private static func hasWineDllOverride(in bottleRoot: URL) -> Bool {
        let regURL = bottleRoot.appendingPathComponent("user.reg")
        guard let text = try? String(contentsOf: regURL, encoding: .utf8) else { return false }
        let steamHeader = "[Software\\\\Wine\\\\AppDefaults\\\\steam.exe\\\\DllOverrides]"
        let defaultHeader = "[Software\\\\Wine\\\\DllOverrides]"
        return sectionHasAllOverrides(in: text, sectionHeader: steamHeader, overrides: steamExeOverrides)
            && sectionHasAllOverrides(in: text, sectionHeader: defaultHeader, overrides: defaultWineDllOverrides)
    }

    private static func ensureWineDllOverride(in bottleRoot: URL) throws {
        let regURL = bottleRoot.appendingPathComponent("user.reg")
        guard FileManager.default.fileExists(atPath: regURL.path) else {
            throw StepFailure(step: "Locate user.reg",
                              detail: "Missing user.reg in CrossOver bottle at \(bottleRoot.path).")
        }
        var text = try String(contentsOf: regURL, encoding: .utf8)
        let steamHeader = "[Software\\\\Wine\\\\AppDefaults\\\\steam.exe\\\\DllOverrides]"
        let defaultHeader = "[Software\\\\Wine\\\\DllOverrides]"

        let c1 = upsertDllOverrides(in: &text, sectionHeader: steamHeader, overrides: steamExeOverrides)
        let c2 = upsertDllOverrides(in: &text, sectionHeader: defaultHeader, overrides: defaultWineDllOverrides)

        if c1 || c2 {
            try text.write(to: regURL, atomically: true, encoding: .utf8)
            let bottleName = bottleRoot.lastPathComponent
            if c1 {
                applyLiveWineRegistryOverrides(
                    bottleName: bottleName,
                    regKey: "HKCU\\Software\\Wine\\AppDefaults\\steam.exe\\DllOverrides",
                    overrides: steamExeOverrides
                )
            }
            if c2 {
                applyLiveWineRegistryOverrides(
                    bottleName: bottleName,
                    regKey: "HKCU\\Software\\Wine\\DllOverrides",
                    overrides: defaultWineDllOverrides
                )
            }
        }
    }

    private static func sectionRange(in text: String, sectionHeader: String) -> Range<String.Index>? {
        guard let headerStart = text.range(of: sectionHeader, options: .caseInsensitive) else { return nil }
        let afterHeader = text[headerStart.upperBound...]
        let end = afterHeader.range(of: "\n[")?.lowerBound ?? text.endIndex
        return headerStart.lowerBound..<end
    }

    private static func sectionHasAllOverrides(
        in text: String,
        sectionHeader: String,
        overrides: [(String, String)]
    ) -> Bool {
        guard let range = sectionRange(in: text, sectionHeader: sectionHeader) else { return false }
        let slice = text[range].lowercased()
        return overrides.allSatisfy { (dll, mode) in
            slice.contains("\"\(dll.lowercased())\"=\"\(mode.lowercased())\"")
        }
    }

    private static func upsertDllOverrides(
        in text: inout String,
        sectionHeader: String,
        overrides: [(String, String)]
    ) -> Bool {
        if let range = sectionRange(in: text, sectionHeader: sectionHeader) {
            let sliceLower = text[range].lowercased()
            var missingLines: [String] = []
            for (dll, mode) in overrides {
                let needle = "\"\(dll.lowercased())\"="
                if !sliceLower.contains(needle) {
                    missingLines.append("\"\(dll)\"=\"\(mode)\"")
                }
            }
            guard !missingLines.isEmpty else { return false }

            // Insert right after `#time=...` if present, otherwise right after header line
            var insertPos = text[range.lowerBound...].firstIndex(of: "\n") ?? range.upperBound
            let afterHeaderLine = text.index(after: insertPos)
            if afterHeaderLine < range.upperBound, text[afterHeaderLine...].hasPrefix("#time=") {
                if let timeLineEnd = text[afterHeaderLine...].firstIndex(of: "\n") {
                    insertPos = timeLineEnd
                }
            }
            text.insert(contentsOf: "\n" + missingLines.joined(separator: "\n"), at: insertPos)
            return true
        } else {
            if !text.hasSuffix("\n") { text.append("\n") }
            var block = "\n\(sectionHeader) \(Int(Date().timeIntervalSince1970))\n"
            for (dll, mode) in overrides {
                block += "\"\(dll)\"=\"\(mode)\"\n"
            }
            text.append(block)
            return true
        }
    }
}
