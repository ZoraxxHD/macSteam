// Home Dashboard View Controller (LuaTools-inspired layout)
import AppKit
import UniformTypeIdentifiers

final class HomeViewController: NSViewController {
    let store: ConfigStore
    var onNavigate: ((MainViewController.Item) -> Void)?
    var onSelectGameInLibrary: ((Int) -> Void)?
    var onImportFiles: (([URL]) -> Void)?

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!

    // Top 2 Hero Stat Cards
    private var gamesBigCountLabel: NSTextField!
    private var gamesSubLabel: NSTextField!
    private var pluginHeaderLabel: NSTextField!
    private var pluginValueLabel: NSTextField!

    // Middle Unified Status Card rows
    private var steamRowLabel: NSTextField!
    private var accountRowLabel: NSTextField!
    private var macsteamRowLabel: NSTextField!
    private var crossoverRowLabel: NSTextField!

    // Inline Drop/Import Card
    private var dropTitleLabel: NSTextField!
    private var dropSubLabel: NSTextField!
    private var browseFilesBtn: NSButton!

    private var recentHeaderLabel: NSTextField!
    private var recentStack: NSStackView!
    private var recentEmptyLabel: NSTextField!

    private var searchBtn: NSButton!
    private var crossoverBtn: NSButton!
    private var restartSteamBtn: NSButton!
    private var openSteamBtn: NSButton!

    private let artLoader = StoreArtLoader()

    init(store: ConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = docView

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel = NSTextField(wrappingLabelWithString: "")
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Quick action bar
        searchBtn = makeButton(title: "", target: self, action: #selector(openSearch))
        searchBtn.bezelColor = .controlAccentColor
        crossoverBtn = makeButton(title: "", target: self, action: #selector(openCrossOver))
        restartSteamBtn = makeButton(title: "", target: self, action: #selector(restartSteam))
        openSteamBtn = makeButton(title: "", target: self, action: #selector(openSteam))

        let actionBar = NSStackView(views: [searchBtn, crossoverBtn, restartSteamBtn, openSteamBtn])
        actionBar.orientation = .horizontal
        actionBar.spacing = 10
        actionBar.translatesAutoresizingMaskIntoConstraints = false

        // Top 2 Hero Cards (Screenshot 2: Big number left, Plugin status right)
        gamesBigCountLabel = NSTextField(labelWithString: "0")
        gamesBigCountLabel.font = .systemFont(ofSize: 30, weight: .bold)
        gamesBigCountLabel.textColor = .systemPurple

        gamesSubLabel = NSTextField(labelWithString: "")
        gamesSubLabel.font = Typography.caption
        gamesSubLabel.textColor = .secondaryLabelColor

        let gamesHeroCard = ClickableCardView(target: self, action: #selector(openApps))
        gamesHeroCard.applyCardSurface()
        gamesHeroCard.translatesAutoresizingMaskIntoConstraints = false
        let gamesHeroStack = NSStackView(views: [gamesBigCountLabel, gamesSubLabel])
        gamesHeroStack.orientation = .vertical
        gamesHeroStack.alignment = .leading
        gamesHeroStack.spacing = 2
        gamesHeroStack.translatesAutoresizingMaskIntoConstraints = false
        gamesHeroCard.addSubview(gamesHeroStack)
        NSLayoutConstraint.activate([
            gamesHeroCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 82),
            gamesHeroStack.leadingAnchor.constraint(equalTo: gamesHeroCard.leadingAnchor, constant: 18),
            gamesHeroStack.trailingAnchor.constraint(equalTo: gamesHeroCard.trailingAnchor, constant: -14),
            gamesHeroStack.centerYAnchor.constraint(equalTo: gamesHeroCard.centerYAnchor),
        ])

        pluginHeaderLabel = NSTextField(labelWithString: "")
        pluginHeaderLabel.font = Typography.caption
        pluginHeaderLabel.textColor = .secondaryLabelColor

        pluginValueLabel = NSTextField(labelWithString: "")
        pluginValueLabel.font = .systemFont(ofSize: 16, weight: .bold)
        pluginValueLabel.textColor = .systemGreen

        let pluginHeroCard = ClickableCardView(target: self, action: #selector(openPlugin))
        pluginHeroCard.applyCardSurface()
        pluginHeroCard.translatesAutoresizingMaskIntoConstraints = false
        let pluginHeroStack = NSStackView(views: [pluginHeaderLabel, pluginValueLabel])
        pluginHeroStack.orientation = .vertical
        pluginHeroStack.alignment = .leading
        pluginHeroStack.spacing = 4
        pluginHeroStack.translatesAutoresizingMaskIntoConstraints = false
        pluginHeroCard.addSubview(pluginHeroStack)
        NSLayoutConstraint.activate([
            pluginHeroCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 82),
            pluginHeroStack.leadingAnchor.constraint(equalTo: pluginHeroCard.leadingAnchor, constant: 18),
            pluginHeroStack.trailingAnchor.constraint(equalTo: pluginHeroCard.trailingAnchor, constant: -14),
            pluginHeroStack.centerYAnchor.constraint(equalTo: pluginHeroCard.centerYAnchor),
        ])

        let topRow = NSStackView(views: [gamesHeroCard, pluginHeroCard])
        topRow.orientation = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 12
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // Middle Unified Status Card (Screenshot 2: Steam, Account, macSteam, CrossOver)
        steamRowLabel = makeStatusRowLabel()
        accountRowLabel = makeStatusRowLabel()
        macsteamRowLabel = makeStatusRowLabel()
        crossoverRowLabel = makeStatusRowLabel()

        let statusListCard = NSView()
        statusListCard.applyCardSurface()
        statusListCard.translatesAutoresizingMaskIntoConstraints = false
        let statusRows: [(String, NSColor, NSTextField, Selector)] = [
            ("checkmark.circle.fill", .systemGreen, steamRowLabel, #selector(openInstall)),
            ("person.crop.circle", .systemPurple, accountRowLabel, #selector(openSettings)),
            ("shield.lefthalf.filled", .systemBlue, macsteamRowLabel, #selector(openInstall)),
            ("play.desktopcomputer", .systemPurple, crossoverRowLabel, #selector(openCrossOver)),
        ]
        var prevRow: NSView?
        for (idx, item) in statusRows.enumerated() {
            let row = makeStatusRow(symbol: item.0, tint: item.1, label: item.2, action: item.3)
            statusListCard.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: statusListCard.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: statusListCard.trailingAnchor),
            ])
            if let prevRow {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                statusListCard.addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.topAnchor.constraint(equalTo: prevRow.bottomAnchor),
                    sep.leadingAnchor.constraint(equalTo: statusListCard.leadingAnchor, constant: 14),
                    sep.trailingAnchor.constraint(equalTo: statusListCard.trailingAnchor, constant: -14),
                    row.topAnchor.constraint(equalTo: sep.bottomAnchor),
                ])
            } else {
                row.topAnchor.constraint(equalTo: statusListCard.topAnchor).isActive = true
            }
            if idx == statusRows.count - 1 {
                row.bottomAnchor.constraint(equalTo: statusListCard.bottomAnchor).isActive = true
            }
            prevRow = row
        }

        // Inline Quick Import Card (accepts drag-and-drop .lua/.zip or browse)
        let importCard = DashboardDropCard { [weak self] urls in
            self?.onImportFiles?(urls)
        }
        importCard.applyCardSurface()
        importCard.translatesAutoresizingMaskIntoConstraints = false

        let importIcon = IconBadgeView(symbol: "arrow.down.doc.fill", tint: .systemPurple, size: 38, pointSize: 17)
        dropTitleLabel = NSTextField(labelWithString: "")
        dropTitleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        dropSubLabel = NSTextField(labelWithString: "")
        dropSubLabel.font = Typography.caption
        dropSubLabel.textColor = .secondaryLabelColor
        browseFilesBtn = makeButton(title: "", target: self, action: #selector(browseImportFiles))

        let dropTextStack = NSStackView(views: [dropTitleLabel, dropSubLabel, browseFilesBtn])
        dropTextStack.orientation = .vertical
        dropTextStack.alignment = .leading
        dropTextStack.spacing = 4
        dropTextStack.setCustomSpacing(8, after: dropSubLabel)
        dropTextStack.translatesAutoresizingMaskIntoConstraints = false

        importCard.addSubview(importIcon)
        importCard.addSubview(dropTextStack)
        NSLayoutConstraint.activate([
            importIcon.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 18),
            importIcon.centerYAnchor.constraint(equalTo: importCard.centerYAnchor),

            dropTextStack.leadingAnchor.constraint(equalTo: importIcon.trailingAnchor, constant: 14),
            dropTextStack.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -16),
            dropTextStack.topAnchor.constraint(equalTo: importCard.topAnchor, constant: 14),
            dropTextStack.bottomAnchor.constraint(equalTo: importCard.bottomAnchor, constant: -14),
        ])

        // Recently Added section
        recentHeaderLabel = settingsGroupLabel("")
        recentStack = NSStackView()
        recentStack.orientation = .horizontal
        recentStack.spacing = 12
        recentStack.alignment = .top
        recentStack.distribution = .fillEqually
        recentStack.translatesAutoresizingMaskIntoConstraints = false

        recentEmptyLabel = NSTextField(wrappingLabelWithString: "")
        recentEmptyLabel.font = Typography.body
        recentEmptyLabel.textColor = .tertiaryLabelColor
        recentEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            actionBar,
            topRow,
            statusListCard,
            importCard,
            recentHeaderLabel,
            recentStack,
            recentEmptyLabel
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.setCustomSpacing(4, after: titleLabel)
        mainStack.setCustomSpacing(16, after: subtitleLabel)
        mainStack.setCustomSpacing(16, after: actionBar)
        mainStack.setCustomSpacing(8, after: recentHeaderLabel)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        docView.addSubview(mainStack)
        topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        statusListCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        importCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        recentStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let M = Metrics.paneMargin
        NSLayoutConstraint.activate([
            docView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: M - 4),
            mainStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: M),
            mainStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -M),
            mainStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -M),
        ])

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 540))
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(refreshUI), name: .libraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshUI), name: AuthService.authStateChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshUI), name: L10n.languageChangedNotification, object: nil)

        refreshUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshUI()
    }

    private func makeStatusRowLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = Typography.body
        l.textColor = .labelColor
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func makeStatusRow(symbol: String, tint: NSColor, label: NSTextField, action: Selector) -> NSView {
        let row = ClickableCardView(target: self, action: action)
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon)
        row.addSubview(label)
        row.addSubview(chevron)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc func refreshUI() {
        guard isViewLoaded else { return }
        let fr = L10n.isFrench
        titleLabel.stringValue = fr ? "Bienvenue dans macSteam" : "Welcome to macSteam"
        subtitleLabel.stringValue = L10n.tr("home.subtitle")
        searchBtn.title = L10n.tr("home.quick.search")
        crossoverBtn.title = L10n.tr("sidebar.crossover")
        restartSteamBtn.title = L10n.tr("home.quick.restart_steam")
        openSteamBtn.title = L10n.tr("home.quick.open_steam")
        recentHeaderLabel.stringValue = L10n.tr("home.recent.title")
        recentEmptyLabel.stringValue = L10n.tr("home.recent.empty")
        pluginHeaderLabel.stringValue = L10n.tr("home.card.plugin")

        dropTitleLabel.stringValue = fr ? "Déposez des fichiers .lua, .manifest ou .zip ici" : "Drop .lua, .manifest, or .zip files here"
        dropSubLabel.stringValue = fr ? "…ou ouvrez l'importateur pour parcourir vos fichiers." : "…or open the importer to browse your files."
        browseFilesBtn.title = fr ? "Parcourir les fichiers…" : "Browse Files…"

        // Games count
        let topGames = store.config.topLevelApps
        let dlcCount = max(0, store.config.apps.count - topGames.count)
        gamesBigCountLabel.stringValue = "\(topGames.count)"
        gamesSubLabel.stringValue = L10n.tr("home.card.games.sub", topGames.count, dlcCount)

        // Plugin status
        let pStatus = PluginInstallerService.shared.currentStatus()
        if pStatus.cefMarkerInstalled && pStatus.serverRunning {
            pluginValueLabel.stringValue = L10n.tr("home.card.plugin.active")
            pluginValueLabel.textColor = .systemGreen
        } else {
            pluginValueLabel.stringValue = L10n.tr("home.card.plugin.inactive")
            pluginValueLabel.textColor = .secondaryLabelColor
        }

        // Unified status rows
        if SteamInstaller.status() == .steamMissing {
            steamRowLabel.stringValue = fr ? "Steam introuvable dans /Applications" : "Steam not found in /Applications"
        } else {
            let build = MacCrab.detectedVersion() ?? "?"
            steamRowLabel.stringValue = fr
                ? "Steam détecté · /Applications/Steam.app (Build \(build))"
                : "Steam detected · /Applications/Steam.app (Build \(build))"
        }

        var accParts: [String] = []
        if AuthService.shared.isSignedIn {
            accParts.append(fr ? "Connecté en tant que \(AuthService.shared.displayName ?? "User")" : "Signed in as \(AuthService.shared.displayName ?? "User")")
        } else {
            accParts.append(L10n.tr("home.card.account.guest"))
        }
        if let hk = AppSettings.shared.hubcapApiKey, !hk.isEmpty {
            accParts.append("Hubcap ✓")
        }
        accountRowLabel.stringValue = accParts.joined(separator: " · ")

        switch SteamInstaller.status() {
        case .installed:
            let v = SteamInstaller.deployedDylibVersion() ?? "0.7.1"
            macsteamRowLabel.stringValue = fr ? "macSteam · Installé (v\(v))" : "macSteam · Installed (v\(v))"
        case .outdated(let b, let d):
            macsteamRowLabel.stringValue = fr ? "macSteam · Mise à jour dispo (v\(d) → v\(b))" : "macSteam · Update available (v\(d) → v\(b))"
        default:
            macsteamRowLabel.stringValue = fr ? "macSteam · Non installé (cliquez pour installer)" : "macSteam · Not installed (click to install)"
        }

        switch CrossOverInstaller.status() {
        case .noCrossOver:
            crossoverRowLabel.stringValue = fr ? "CrossOver · Aucune bouteille Steam détectée" : "CrossOver · No Steam bottle found"
        case .notInstalled(let bottle):
            crossoverRowLabel.stringValue = fr ? "CrossOver · Bouteille '\(bottle)' à configurer" : "CrossOver · Bottle '\(bottle)' not configured"
        case .installed(let bottle):
            let count = CrossOverInstaller.syncedLuaCount()
            crossoverRowLabel.stringValue = fr ? "CrossOver · '\(bottle)' prêt (\(count) jeu(x))" : "CrossOver · '\(bottle)' ready (\(count) game(s))"
        }

        // Recently added strip (last 4 top-level games)
        recentStack.subviews.forEach { $0.removeFromSuperview() }
        let recentIds = Array(topGames.suffix(4).reversed())
        recentEmptyLabel.isHidden = !recentIds.isEmpty
        recentStack.isHidden = recentIds.isEmpty

        for id in recentIds {
            let fallbackName = store.config.appNames[id] ?? "App \(id)"
            let tile = RecentGameTileView(appId: id, title: artLoader.name(for: id) ?? fallbackName, image: artLoader.image(for: id)) { [weak self] clickedId in
                self?.onSelectGameInLibrary?(clickedId)
            }
            recentStack.addArrangedSubview(tile)
        }

        if !recentIds.isEmpty {
            artLoader.load(recentIds, artWidth: 320, onName: { [weak self] id, name in
                guard let self else { return }
                for case let tile as RecentGameTileView in self.recentStack.arrangedSubviews where tile.appId == id {
                    tile.setTitle(name)
                }
            }, onArt: { [weak self] id, img in
                guard let self else { return }
                for case let tile as RecentGameTileView in self.recentStack.arrangedSubviews where tile.appId == id {
                    tile.setImage(img)
                }
            })
        }
    }

    @objc private func openSearch() { onNavigate?(.search) }
    @objc private func browseImportFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        let types = ["zip", "lua"].compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty { panel.allowedContentTypes = types }
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            onImportFiles?(panel.urls)
        }
    }
    @objc private func openCrossOver() { onNavigate?(.crossover) }
    @objc private func openApps() { onNavigate?(.config(.apps)) }
    @objc private func openInstall() { onNavigate?(.install) }
    @objc private func openSettings() { onNavigate?(.config(.settings)) }
    @objc private func openPlugin() { onNavigate?(.plugin) }
    @objc private func restartSteam() { SteamLibraryService.restartSteam() }
    @objc private func openSteam() { NSWorkspace.shared.open(Paths.steamApp) }
}

private final class ClickableCardView: NSView {
    weak var target: AnyObject?
    let action: Selector

    init(target: AnyObject?, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.8
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        if let target {
            _ = target.perform(action)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurfaceColors()
    }
}

private final class RecentGameTileView: NSView {
    let appId: Int
    private let artView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let idField = NSTextField(labelWithString: "")
    private let onClick: (Int) -> Void

    init(appId: Int, title: String, image: NSImage?, onClick: @escaping (Int) -> Void) {
        self.appId = appId
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyCardSurface()

        artView.imageScaling = .scaleProportionallyUpOrDown
        artView.wantsLayer = true
        artView.layer?.cornerRadius = 6
        artView.layer?.masksToBounds = true
        artView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        artView.image = image
        artView.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        idField.stringValue = "AppID \(appId)"
        idField.font = Typography.caption
        idField.textColor = .secondaryLabelColor
        idField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(artView)
        addSubview(titleField)
        addSubview(idField)

        NSLayoutConstraint.activate([
            artView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            artView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            artView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            artView.heightAnchor.constraint(equalToConstant: 72),

            titleField.topAnchor.constraint(equalTo: artView.bottomAnchor, constant: 6),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            idField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            idField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            idField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            idField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ name: String) { titleField.stringValue = name }
    func setImage(_ img: NSImage?) { artView.image = img }

    override func mouseUp(with event: NSEvent) {
        onClick(appId)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurfaceColors()
    }
}

private final class DashboardDropCard: NSView {
    private let onDrop: ([URL]) -> Void

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func validURLs(from info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
        return urls.filter {
            ["zip", "lua"].contains($0.pathExtension.lowercased()) || $0.hasDirectoryPath
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = !validURLs(from: sender).isEmpty
        if valid {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.borderColor = NSColor.controlAccentColor.cgColor
            }
        }
        return valid ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        applyCardSurfaceColors()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        applyCardSurfaceColors()
        let urls = validURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurfaceColors()
    }
}
