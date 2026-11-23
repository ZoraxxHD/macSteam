// Main split view controller
import AppKit

final class MainViewController: NSSplitViewController {
    let store: ConfigStore

    private var sidebarVC: SidebarViewController!
    private var detailContainerVC: NSViewController!
    private var homeVC: HomeViewController!
    private var searchVC: SearchDownloadViewController!
    private var importVC: ImportViewController!
    private var configVC: ConfigViewController!
    private var buildsVC: BuildsViewController!
    private var fixesVC: FixesViewController!
    private var downloadsVC: DownloadsViewController!
    private var pluginVC: PluginViewController!
    private var installVC: InstallViewController!
    private var crossoverVC: CrossOverViewController!
    private var cloudRedirectVC: CloudRedirectViewController!
    private var repairVC: RepairViewController!

    private let titleLabel: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .semibold)
        field.textColor = .labelColor
        field.alignment = .natural
        return field
    }()

    enum Item: Equatable {
        case home
        case search
        case importZip
        case config(ConfigViewController.Section)
        case builds
        case fixes
        case downloads
        case plugin
        case install
        case crossover
        case cloudRedirect
        case repair
    }

    private var activeItem: Item?

    init(store: ConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        homeVC = HomeViewController(store: store)
        homeVC.onNavigate = { [weak self] item in
            self?.sidebarVC.select(item)
        }
        homeVC.onSelectGameInLibrary = { [weak self] appId in
            self?.sidebarVC.select(.config(.apps))
            self?.configVC.selectAppInList(appId)
        }
        homeVC.onImportFiles = { [weak self] urls in
            self?.importVC.importFiles(urls)
            self?.show(.importZip)
        }

        searchVC = SearchDownloadViewController(store: store)
        searchVC.onOpenGameInLibrary = { [weak self] appId in
            self?.sidebarVC.select(.config(.apps))
            self?.configVC.selectAppInList(appId)
        }
        searchVC.onOpenSettings = { [weak self] in
            self?.sidebarVC.select(.config(.settings))
        }

        importVC = ImportViewController(store: store, onConfigChanged: { [weak self] in
            self?.configVC.reloadFromStore()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        })

        configVC = ConfigViewController(store: store)
        configVC.onUpdateGame = { [weak self] appId in
            self?.sidebarVC.select(.search)
            self?.searchVC.seedSearch(appId: appId)
        }
        configVC.onManageBuilds = { [weak self] appId in
            self?.sidebarVC.select(.builds)
            self?.buildsVC.selectApp(appId: appId)
        }

        buildsVC = BuildsViewController(store: store)

        fixesVC = FixesViewController(store: store)
        fixesVC.onOpenSettings = { [weak self] in
            self?.sidebarVC.select(.config(.settings))
        }

        downloadsVC = DownloadsViewController()
        pluginVC = PluginViewController()
        installVC = InstallViewController()
        crossoverVC = CrossOverViewController()
        cloudRedirectVC = CloudRedirectViewController()
        repairVC = RepairViewController()

        detailContainerVC = NSViewController()
        detailContainerVC.view = NSView()
        for child in [homeVC, searchVC, importVC, configVC, buildsVC, fixesVC, downloadsVC, pluginVC, installVC, crossoverVC, cloudRedirectVC, repairVC] as [NSViewController] {
            detailContainerVC.addChild(child)
        }

        sidebarVC = SidebarViewController(onSelect: { [weak self] item in
            self?.show(item)
        })

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 195
        sidebarItem.maximumThickness = 250
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: detailContainerVC)
        detailItem.minimumThickness = 580

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        super.loadView()

        NotificationCenter.default.addObserver(self, selector: #selector(refreshActiveTitle), name: L10n.languageChangedNotification, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
        sidebarVC.selectDefault()
    }

    @objc private func refreshActiveTitle() {
        if let active = activeItem {
            titleLabel.stringValue = title(for: active)
        }
    }

    // MARK: - Detail routing

    func navigateTo(_ item: Item) {
        sidebarVC.select(item)
    }

    func openSearch(appId: Int) {
        sidebarVC.select(.search)
        searchVC.seedSearch(appId: appId)
    }

    func openFixes(appId: Int) {
        sidebarVC.select(.fixes)
        fixesVC.openForAppId(appId)
    }

    private func title(for item: Item) -> String {
        switch item {
        case .home:      return L10n.tr("sidebar.home")
        case .search:    return L10n.tr("sidebar.search")
        case .importZip: return L10n.tr("sidebar.import")
        case .config(let section): return section.title
        case .builds:    return L10n.tr("sidebar.builds")
        case .fixes:     return L10n.tr("sidebar.fixes")
        case .downloads: return L10n.tr("sidebar.downloads")
        case .plugin:    return L10n.tr("sidebar.plugin")
        case .install:   return L10n.tr("sidebar.install")
        case .crossover:     return L10n.tr("sidebar.crossover")
        case .cloudRedirect: return L10n.tr("sidebar.cloud_redirect")
        case .repair:        return L10n.tr("sidebar.repair")
        }
    }

    private func show(_ item: Item) {
        activeItem = item
        let child: NSViewController
        switch item {
        case .home:
            child = homeVC
        case .search:
            child = searchVC
        case .importZip:
            child = importVC
        case .config(let section):
            configVC.select(section: section)
            child = configVC
        case .builds:
            child = buildsVC
        case .fixes:
            child = fixesVC
        case .downloads:
            child = downloadsVC
        case .plugin:
            child = pluginVC
        case .install:
            child = installVC
        case .crossover:
            child = crossoverVC
        case .cloudRedirect:
            child = cloudRedirectVC
        case .repair:
            child = repairVC
        }
        titleLabel.stringValue = title(for: item)
        swapDetail(to: child.view)
    }

    private func swapDetail(to newView: NSView) {
        let host = detailContainerVC.view
        guard newView.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        newView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(newView)
        NSLayoutConstraint.activate([
            newView.topAnchor.constraint(equalTo: host.topAnchor),
            newView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            newView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    // MARK: - Menu / toolbar actions

    @objc func importZip() {
        sidebarVC.select(.importZip)
        importVC.pickZip()
    }
}

// MARK: - Window

extension MainViewController: NSWindowDelegate {
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        activeItem == .importZip ? importVC.reviewUndoManager : nil
    }
}

// MARK: - Toolbar

extension MainViewController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .sectionTitle]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .sectionTitle else { return nil }
        let item = NSToolbarItem(itemIdentifier: .sectionTitle)
        item.view = titleLabel
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let sectionTitle = NSToolbarItem.Identifier("sectionTitle")
}
