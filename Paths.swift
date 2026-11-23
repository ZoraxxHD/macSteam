// Canonical filesystem locations shared by the dylib and this app.

import Foundation

enum Paths {
    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/macsteam", isDirectory: true)
    }
    static var configFile: URL {
        configDir.appendingPathComponent("config.yaml")
    }

    static var configBackupDir: URL {
        configDir.appendingPathComponent("backups", isDirectory: true)
    }

    static var signaturesDir: URL {
        configDir.appendingPathComponent("signatures", isDirectory: true)
    }

    static var stPlugInDir: URL {
        configDir.appendingPathComponent("stplug-in", isDirectory: true)
    }

    static var vaultDir: URL {
        configDir.appendingPathComponent("luavault", isDirectory: true)
    }

    static var detailsCacheDir: URL {
        configDir.appendingPathComponent("details", isDirectory: true)
    }

    static var pluginDir: URL {
        configDir.appendingPathComponent("plugin", isDirectory: true)
    }

    static var settingsFile: URL {
        configDir.appendingPathComponent("settings.json")
    }

    static var authFile: URL {
        configDir.appendingPathComponent("auth.json")
    }

    static var cacheFile: URL {
        configDir.appendingPathComponent("cache.json")
    }

    static var steamRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }

    static var depotCache: URL {
        steamRoot.appendingPathComponent("depotcache", isDirectory: true)
    }

    static var steamApp: URL {
        URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true)
    }
    static var steamAppExecutable: URL {
        steamApp.appendingPathComponent("Contents/MacOS/steam_osx")
    }
    static var steamAppInfoPlist: URL {
        steamApp.appendingPathComponent("Contents/Info.plist")
    }
    static var steamAppInjectedDylib: URL {
        steamApp.appendingPathComponent("Contents/MacOS/macsteam.dylib")
    }

    static var innerClientMacOS: URL {
        steamRoot.appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS", isDirectory: true)
    }

    static var packageDir: URL {
        innerClientMacOS.appendingPathComponent("package", isDirectory: true)
    }

    static var steamCfgRoot: URL {
        steamRoot.appendingPathComponent("steam.cfg")
    }
    static var steamCfgInner: URL {
        innerClientMacOS.appendingPathComponent("steam.cfg")
    }

    static var cefMarkerRoot: URL {
        steamRoot.appendingPathComponent(".cef-enable-remote-debugging")
    }
    static var cefMarkerInner: URL {
        innerClientMacOS.appendingPathComponent(".cef-enable-remote-debugging")
    }
    static var cefMarkerOuter: URL {
        steamApp.appendingPathComponent("Contents/MacOS/.cef-enable-remote-debugging")
    }

    static let defaultInjectionPackage = 20200

    static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
