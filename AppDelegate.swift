import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appName = "macSteam Config"
    let store = ConfigStore()
    private let updaterManager = UpdaterManager.shared
    var window: NSWindow!
    var mainVC: MainViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if enforceSingleInstance() { return }

        store.load()
        updaterManager.start()

        buildMenu()

        mainVC = MainViewController(store: store)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = appName
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.contentViewController = mainVC

        window.isRestorable = false
        window.contentMinSize = NSSize(width: 820, height: 520)

        window.autorecalculatesKeyViewLoop = true
        window.identifier = NSUserInterfaceItemIdentifier("MacsteamMainWindow")

        let toolbar = NSToolbar(identifier: "MacsteamMainToolbar")
        toolbar.delegate = mainVC
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.setFrameAutosaveName("MacsteamMainWindow.v3")
        if !window.setFrameUsingName(window.frameAutosaveName) {
            window.setContentSize(NSSize(width: 980, height: 640))
            window.center()
        }

        // Start LuaTools Store Plugin backend & CEF injector
        HttpServerService.shared.onOpenSettings = { [weak self] in
            self?.mainVC.navigateTo(.config(.settings))
        }
        HttpServerService.shared.onOpenFix = { [weak self] appId in
            self?.mainVC.openFixes(appId: appId)
        }
        HttpServerService.shared.start(store: store)
        CefInjectorService.shared.start()
        DonateKeysService.sendPendingKeysIfEnabled(config: store.config)
        DispatchQueue.global(qos: .utility).async {
            CrossOverInstaller.ensureAllBottlesWineOverrides()
        }

        window.makeKeyAndOrderFront(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "luatools" || scheme == "macsteam" else { continue }
            let host = url.host?.lowercased() ?? ""
            let pathIds = url.pathComponents.compactMap { Int($0) }
            let appId = pathIds.first ?? Int(host)
            guard let appId, appId > 0 else { continue }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if host == "fix" {
                mainVC.openFixes(appId: appId)
            } else {
                mainVC.openSearch(appId: appId)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CefInjectorService.shared.stop()
        HttpServerService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func checkForUpdatesMenu() {
        updaterManager.checkForUpdates()
    }

    private func enforceSingleInstance() -> Bool {
        guard let me = Bundle.main.bundleIdentifier else { return false }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == me && $0.processIdentifier != getpid()
        }
        guard let existing = others.first else { return false }
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Check for Updates…",
                        action: #selector(checkForUpdatesMenu),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesMenu = NSMenu()
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                        action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Import Zip…",
                         action: #selector(MainViewController.importZip), keyEquivalent: "i").target = nil
        fileMenu.addItem(.separator())
        let removeItem = fileMenu.addItem(withTitle: "Remove",
                         action: #selector(DeletingOutlineView.removeApps(_:)), keyEquivalent: String(UnicodeScalar(NSDeleteCharacter)!))
        removeItem.keyEquivalentModifierMask = [.command]
        removeItem.target = nil
        fileMenuItem.submenu = fileMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}
