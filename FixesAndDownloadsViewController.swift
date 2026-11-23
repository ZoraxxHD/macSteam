// FixesViewController, DownloadsViewController, and PluginViewController.
import AppKit

// MARK: - Shared Helpers

@MainActor
private func makeFeatureCard(symbol: String, tint: NSColor, text: String) -> NSView {
    let card = NSView()
    card.applyCardSurface()
    card.translatesAutoresizingMaskIntoConstraints = false

    let badge = IconBadgeView(symbol: symbol, tint: tint, size: 32, pointSize: 14)
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = Typography.body
    label.textColor = .labelColor
    label.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(badge)
    card.addSubview(label)
    NSLayoutConstraint.activate([
        badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        badge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

        label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
        label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        label.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 10),
        label.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10),
        label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
    ])
    return card
}

@MainActor
private func makeInfoBanner(text: String, tint: NSColor = .systemBlue) -> NSView {
    let box = NSView()
    box.wantsLayer = true
    box.layer?.cornerRadius = 8
    box.layer?.borderWidth = 1
    box.effectiveAppearance.performAsCurrentDrawingAppearance {
        box.layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
        box.layer?.borderColor = tint.withAlphaComponent(0.28).cgColor
    }
    box.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(wrappingLabelWithString: text)
    label.font = Typography.caption
    label.textColor = tint
    label.translatesAutoresizingMaskIntoConstraints = false

    box.addSubview(label)
    NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
        label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
        label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
    ])
    return box
}

// MARK: - 1. FixesViewController (LuaTools-style Card Grid + Detail View)

final class FixesViewController: NSViewController {
    let store: ConfigStore
    var onOpenSettings: (() -> Void)?

    private var titleLabel: NSTextField!
    private var countPill: PillBadge!
    private var refreshBtn: NSButton!
    private var spinner: NSProgressIndicator!

    // Grid browser views
    private var browserContainer: NSView!
    private var searchField: NSSearchField!
    private var chipsScroll: NSScrollView!
    private var chipsStack: NSStackView!
    private var gridCollection: NSCollectionView!
    private var emptyBrowserState: EmptyStateView!

    // Detail views (shown when a card is clicked)
    private var detailContainer: NSScrollView!
    private var backBtn: NSButton!
    private var heroBanner: SteamArtThumbView!
    private var selectedTitleLabel: NSTextField!
    private var metaPillsRow: NSStackView!
    private var fixesStack: NSStackView!

    private var allGames: [DenuvoGameListing] = []
    private var filteredGames: [DenuvoGameListing] = []
    private var allTags: [DenuvoTag] = []
    private var selectedTagId: String?
    private var myGamesOnly = false
    private var selectedGame: DenuvoGameListing?

    private static let cardItemID = NSUserInterfaceItemIdentifier("FixGameGridItem")

    init(store: ConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 560))

        // Top Header (LuaTools style: bold left title + right refresh)
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor

        countPill = PillBadge(text: "0", symbol: "gamecontroller", tint: .systemPurple)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        refreshBtn = makeButton(title: "", target: self, action: #selector(refreshTapped))

        let headerRow = NSStackView(views: [titleLabel, countPill, NSView(), spinner, refreshBtn])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // Browser container (Search + Filter Chips + 3-column Game Card Grid)
        browserContainer = NSView()
        browserContainer.translatesAutoresizingMaskIntoConstraints = false

        searchField = NSSearchField()
        searchField.controlSize = .large
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(filterChanged)
        searchField.sendsSearchStringImmediately = true

        chipsScroll = NSScrollView()
        chipsScroll.drawsBackground = false
        chipsScroll.hasHorizontalScroller = false
        chipsScroll.hasVerticalScroller = false
        chipsScroll.borderType = .noBorder
        chipsScroll.translatesAutoresizingMaskIntoConstraints = false

        chipsStack = NSStackView()
        chipsStack.orientation = .horizontal
        chipsStack.alignment = .centerY
        chipsStack.spacing = 6
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsScroll.documentView = chipsStack

        let flow = NSCollectionViewFlowLayout()
        flow.minimumInteritemSpacing = 12
        flow.minimumLineSpacing = 12
        flow.sectionInset = NSEdgeInsets(top: 4, left: 0, bottom: 16, right: 0)

        gridCollection = NSCollectionView()
        gridCollection.collectionViewLayout = flow
        gridCollection.backgroundColors = [.clear]
        gridCollection.isSelectable = true
        gridCollection.allowsMultipleSelection = false
        gridCollection.register(FixGameGridItem.self, forItemWithIdentifier: Self.cardItemID)
        gridCollection.dataSource = self
        gridCollection.delegate = self

        let gridScroll = makeScrollView()
        gridScroll.translatesAutoresizingMaskIntoConstraints = false
        gridScroll.documentView = gridCollection

        emptyBrowserState = EmptyStateView(
            symbol: "wrench.adjustable",
            prompt: L10n.isFrench ? "Aucun jeu trouvé" : "No games found",
            hint: L10n.isFrench ? "Modifiez votre recherche ou vos filtres." : "Try adjusting your search or filter tags."
        )
        emptyBrowserState.isHidden = true

        browserContainer.addSubview(searchField)
        browserContainer.addSubview(chipsScroll)
        browserContainer.addSubview(gridScroll)
        browserContainer.addSubview(emptyBrowserState)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: browserContainer.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),

            chipsScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            chipsScroll.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            chipsScroll.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 30),

            chipsStack.topAnchor.constraint(equalTo: chipsScroll.contentView.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScroll.contentView.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScroll.contentView.leadingAnchor),

            gridScroll.topAnchor.constraint(equalTo: chipsScroll.bottomAnchor, constant: 10),
            gridScroll.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: browserContainer.bottomAnchor),

            emptyBrowserState.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            emptyBrowserState.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),
        ])

        // Detail container (shown when user clicks a game card)
        detailContainer = makeScrollView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.isHidden = true
        let detailDoc = NSView()
        detailDoc.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.documentView = detailDoc

        backBtn = makeButton(title: L10n.isFrench ? "← Retour aux correctifs" : "← Back to Fixes", target: self, action: #selector(backToGrid))

        heroBanner = SteamArtThumbView(cornerRadius: 10, fallbackSymbolSize: 34)
        selectedTitleLabel = NSTextField(labelWithString: "")
        selectedTitleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        selectedTitleLabel.lineBreakMode = .byWordWrapping
        selectedTitleLabel.maximumNumberOfLines = 2

        metaPillsRow = NSStackView()
        metaPillsRow.orientation = .horizontal
        metaPillsRow.alignment = .centerY
        metaPillsRow.spacing = 6

        fixesStack = NSStackView()
        fixesStack.orientation = .vertical
        fixesStack.alignment = .leading
        fixesStack.spacing = 10
        fixesStack.translatesAutoresizingMaskIntoConstraints = false

        let detailStack = NSStackView(views: [backBtn, heroBanner, selectedTitleLabel, metaPillsRow, fixesStack])
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 10
        detailStack.setCustomSpacing(14, after: metaPillsRow)
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailDoc.addSubview(detailStack)

        heroBanner.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        heroBanner.heightAnchor.constraint(equalToConstant: 160).isActive = true
        fixesStack.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            detailDoc.topAnchor.constraint(equalTo: detailContainer.contentView.topAnchor),
            detailDoc.leadingAnchor.constraint(equalTo: detailContainer.contentView.leadingAnchor),
            detailDoc.trailingAnchor.constraint(equalTo: detailContainer.contentView.trailingAnchor),

            detailStack.topAnchor.constraint(equalTo: detailDoc.topAnchor, constant: 4),
            detailStack.leadingAnchor.constraint(equalTo: detailDoc.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: detailDoc.trailingAnchor),
            detailStack.bottomAnchor.constraint(equalTo: detailDoc.bottomAnchor, constant: -16),
        ])

        let M = Metrics.paneMargin
        root.addSubview(headerRow)
        root.addSubview(browserContainer)
        root.addSubview(detailContainer)

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: root.topAnchor, constant: M - 4),
            headerRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),
            headerRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -M),

            browserContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 14),
            browserContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),
            browserContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -M),
            browserContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -M),

            detailContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 14),
            detailContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),
            detailContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -M),
            detailContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -M),
        ])

        view = root
        NotificationCenter.default.addObserver(self, selector: #selector(localizeLabels), name: L10n.languageChangedNotification, object: nil)
        localizeLabels()
        loadListings()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let flow = gridCollection.collectionViewLayout as? NSCollectionViewFlowLayout {
            let avail = max(220, gridCollection.bounds.width)
            let cols: CGFloat = avail >= 740 ? 3 : (avail >= 460 ? 2 : 1)
            let w = floor((avail - flow.minimumInteritemSpacing * (cols - 1) - 2) / cols)
            let target = NSSize(width: max(180, w), height: 176)
            if flow.itemSize != target {
                flow.itemSize = target
            }
        }
    }

    @objc private func localizeLabels() {
        guard isViewLoaded else { return }
        titleLabel.stringValue = L10n.tr("sidebar.fixes")
        searchField.placeholderString = L10n.tr("fixes.search.placeholder")
        refreshBtn.title = L10n.tr("fixes.btn.refresh")
        backBtn.title = L10n.isFrench ? "← Retour aux correctifs" : "← Back to Fixes"
        rebuildChips()
    }

    private func rebuildChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let myChip = FilterChipButton(title: L10n.tr("fixes.filter.my_games"), active: myGamesOnly, tint: .systemPurple) { [weak self] in
            self?.myGamesOnly.toggle()
            self?.rebuildChips()
            self?.applyFilter()
        }
        chipsStack.addArrangedSubview(myChip)

        for tag in allTags {
            let isSelected = (selectedTagId == tag.id)
            let tint = tag.color.flatMap { NSColor(hex: $0) } ?? .systemPurple
            let chip = FilterChipButton(title: tag.name, active: isSelected, tint: tint) { [weak self] in
                if self?.selectedTagId == tag.id {
                    self?.selectedTagId = nil
                } else {
                    self?.selectedTagId = tag.id
                }
                self?.rebuildChips()
                self?.applyFilter()
            }
            chipsStack.addArrangedSubview(chip)
        }
    }

    @objc private func refreshTapped() {
        loadListings()
    }

    @objc private func backToGrid() {
        selectedGame = nil
        detailContainer.isHidden = true
        browserContainer.isHidden = false
        gridCollection.deselectAll(nil)
    }

    func openForAppId(_ appId: Int) {
        _ = view
        Task {
            if allGames.isEmpty {
                let (games, tags) = await LuaToolsAPI.shared.getDenuvoListings()
                await MainActor.run {
                    self.allGames = games
                    self.allTags = tags
                    self.rebuildChips()
                    self.applyFilter()
                }
            }
            await MainActor.run {
                if let g = self.filteredGames.first(where: { Int($0.appid) == appId }) {
                    self.loadFixes(for: g)
                }
            }
        }
    }

    private func loadListings() {
        spinner.startAnimation(nil)
        Task {
            let (games, tags) = await LuaToolsAPI.shared.getDenuvoListings()
            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.allGames = games
                self.allTags = tags
                self.rebuildChips()
                self.applyFilter()
            }
        }
    }

    @objc private func filterChanged() {
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownedIds = Set(store.config.apps)

        filteredGames = allGames.filter { g in
            if myGamesOnly, let id = Int(g.appid), !ownedIds.contains(id) { return false }
            if let tid = selectedTagId, !g.tags.contains(where: { $0.id == tid }) { return false }
            if !q.isEmpty {
                return g.name.localizedCaseInsensitiveContains(q) || g.appid.contains(q)
            }
            return true
        }
        let unit = L10n.isFrench ? "jeux" : "games"
        countPill.update(text: "\(filteredGames.count) \(unit)", symbol: "gamecontroller", tint: .systemPurple)
        emptyBrowserState.isHidden = !filteredGames.isEmpty
        gridCollection.reloadData()
    }

    private func loadFixes(for game: DenuvoGameListing) {
        selectedGame = game
        browserContainer.isHidden = true
        detailContainer.isHidden = false

        heroBanner.load(headerURL: game.header_image)
        selectedTitleLabel.stringValue = game.name

        metaPillsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        metaPillsRow.addArrangedSubview(PillBadge(text: "App \(game.appid)", symbol: "number", tint: .secondaryLabelColor))

        let appId = Int(game.appid) ?? 0
        let installed = SteamLibraryService.getInstallDir(appId: appId) != nil
        metaPillsRow.addArrangedSubview(PillBadge(
            text: installed ? (L10n.isFrench ? "Installé" : "Installed") : (L10n.isFrench ? "Non installé" : "Not installed"),
            symbol: installed ? "checkmark.circle.fill" : "minus.circle",
            tint: installed ? .systemGreen : .secondaryLabelColor
        ))

        for t in game.tags.prefix(5) {
            let tint = t.color.flatMap { NSColor(hex: $0) } ?? .systemPurple
            metaPillsRow.addArrangedSubview(PillBadge(text: t.name, tint: tint))
        }

        fixesStack.subviews.forEach { $0.removeFromSuperview() }
        spinner.startAnimation(nil)

        Task {
            let fixes = await LuaToolsAPI.shared.getDenuvoFixes(appId: game.appid)
            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.renderFixes(fixes, for: game)
            }
        }
    }

    private func renderFixes(_ fixes: [DenuvoFix], for game: DenuvoGameListing) {
        fixesStack.subviews.forEach { $0.removeFromSuperview() }
        let appId = Int(game.appid) ?? 0
        let gameInstalled = (SteamLibraryService.getInstallDir(appId: appId) != nil)

        for fix in fixes {
            let card = NSView()
            card.applyCardSurface()
            card.translatesAutoresizingMaskIntoConstraints = false

            let applied = (fix.hasFix == true) && SteamLibraryService.isFixApplied(appId: appId, fixId: fix.id)
            let badgeSymbol = applied ? "checkmark.seal.fill" : (fix.hasFix == true ? "wrench.and.screwdriver.fill" : "doc.zipper")
            let badgeTint: NSColor = applied ? .systemGreen : .systemPurple
            let iconBadge = IconBadgeView(symbol: badgeSymbol, tint: badgeTint, size: 36, pointSize: 16)

            let title = NSTextField(labelWithString: fix.title)
            title.font = .systemFont(ofSize: 14, weight: .semibold)
            title.lineBreakMode = .byWordWrapping
            title.maximumNumberOfLines = 2

            let titleRow = NSStackView(views: [iconBadge, title, NSView()])
            titleRow.orientation = .horizontal
            titleRow.alignment = .centerY
            titleRow.spacing = 10
            if applied {
                titleRow.addArrangedSubview(PillBadge(
                    text: L10n.isFrench ? "Appliqué" : "Applied",
                    symbol: "checkmark.circle.fill",
                    tint: .systemGreen
                ))
            }

            let desc = NSTextField(wrappingLabelWithString: fix.description ?? "")
            desc.font = Typography.caption
            desc.textColor = .secondaryLabelColor
            desc.isHidden = (fix.description?.isEmpty ?? true)

            var btnViews: [NSView] = []
            if fix.hasManifest == true {
                let mBtn = FixActionButton(title: L10n.tr("fixes.btn.download_manifest")) { [weak self] in
                    self?.downloadFixSlot(fix: fix, game: game, slot: "manifest")
                }
                if fix.hasFix != true { mBtn.bezelColor = .controlAccentColor }
                btnViews.append(mBtn)
            }
            if fix.hasFix == true {
                if applied {
                    let revBtn = FixActionButton(title: L10n.tr("fixes.btn.revert_fix")) { [weak self] in
                        self?.revertFix(fix: fix, game: game)
                    }
                    btnViews.append(revBtn)
                } else {
                    let fBtn = FixActionButton(title: L10n.tr("fixes.btn.apply_fix")) { [weak self] in
                        self?.downloadFixSlot(fix: fix, game: game, slot: "fix")
                    }
                    fBtn.bezelColor = .controlAccentColor
                    fBtn.isEnabled = gameInstalled
                    if !gameInstalled {
                        fBtn.toolTip = L10n.tr("fixes.status.game_not_installed")
                    }
                    btnViews.append(fBtn)
                }
            }

            let btnRow = NSStackView(views: btnViews)
            btnRow.orientation = .horizontal
            btnRow.spacing = 8

            let vStack = NSStackView(views: [titleRow, desc, btnRow])
            vStack.orientation = .vertical
            vStack.alignment = .leading
            vStack.spacing = 8
            vStack.translatesAutoresizingMaskIntoConstraints = false
            titleRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

            card.addSubview(vStack)
            NSLayoutConstraint.activate([
                vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            ])
            fixesStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: fixesStack.widthAnchor).isActive = true
        }
    }

    private func downloadFixSlot(fix: DenuvoFix, game: DenuvoGameListing, slot: String) {
        if AuthService.shared.isGuest {
            onOpenSettings?()
            return
        }
        let appId = Int(game.appid) ?? 0
        let fallbackName = (slot == "manifest")
            ? (fix.manifestFilename ?? "\(appId).zip")
            : (fix.fixFilename ?? "\(appId)_fix.zip")
        let storeRef = store

        let qItem = DownloadQueueItem(
            dedupeKey: "denuvo:\(fix.id):\(slot)",
            appId: appId,
            title: game.name,
            subtitle: "\(fix.title) (\(slot))",
            work: { item in
                let fileURL = try await LuaToolsAPI.shared.downloadDenuvo(
                    fixId: fix.id,
                    slot: slot,
                    fallbackName: fallbackName,
                    onProgress: { read, total in
                        DownloadQueue.shared.updateProgress(for: item, bytesRead: read, totalBytes: total)
                    }
                )
                defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
                DownloadQueue.shared.setInstalling(item)
                if slot == "manifest" {
                    _ = try UnifiedInstaller.installDownloaded(
                        fileURL: fileURL,
                        appId: appId,
                        gameName: game.name,
                        source: "Fix",
                        forceLocked: true,
                        store: storeRef
                    )
                    return L10n.isFrench ? "Manifest épinglé installé" : "Pinned manifest installed"
                } else {
                    try SteamLibraryService.applyFixArchive(zipURL: fileURL, appId: appId, fixId: fix.id)
                    return L10n.tr("fixes.status.applied")
                }
            },
            onFinished: { [weak self] _, _ in
                DispatchQueue.main.async {
                    if let g = self?.selectedGame { self?.loadFixes(for: g) }
                }
            }
        )
        DownloadQueue.shared.enqueue(qItem)
    }

    private func revertFix(fix: DenuvoFix, game: DenuvoGameListing) {
        let appId = Int(game.appid) ?? 0
        do {
            try SteamLibraryService.revertFix(appId: appId, fixId: fix.id)
            loadFixes(for: game)
        } catch {
            presentAlert("Revert failed", error.localizedDescription, style: .warning)
        }
    }
}

extension FixesViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredGames.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.cardItemID, for: indexPath) as! FixGameGridItem
        if indexPath.item < filteredGames.count {
            item.configure(with: filteredGames[indexPath.item])
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let idx = indexPaths.first, idx.item < filteredGames.count else { return }
        loadFixes(for: filteredGames[idx.item])
    }
}

private final class FixGameGridItem: NSCollectionViewItem {
    private let card = NSView()
    private let artView = SteamArtThumbView(cornerRadius: 8, fallbackSymbolSize: 24)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 176))
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        artView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subLabel.font = Typography.caption
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(artView)
        card.addSubview(titleLabel)
        card.addSubview(subLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            artView.topAnchor.constraint(equalTo: card.topAnchor),
            artView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            artView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            artView.heightAnchor.constraint(equalToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: artView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
        view = root
    }

    func configure(with game: DenuvoGameListing) {
        artView.load(headerURL: game.header_image)
        titleLabel.stringValue = game.name
        let fr = L10n.isFrench
        subLabel.stringValue = fr
            ? "\(game.fixCount) correctif\(game.fixCount > 1 ? "s" : "")"
            : "\(game.fixCount) fix\(game.fixCount == 1 ? "" : "es")"
    }
}

private final class FilterChipButton: NSButton {
    private let onTap: () -> Void
    private let chipTint: NSColor
    private let isActiveChip: Bool

    init(title: String, active: Bool, tint: NSColor, onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.chipTint = tint
        self.isActiveChip = active
        super.init(frame: .zero)
        self.title = title
        self.isBordered = false
        self.wantsLayer = true
        self.font = .systemFont(ofSize: 11.5, weight: active ? .semibold : .medium)
        self.target = self
        self.action = #selector(clicked)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer?.cornerRadius = 8
        self.layer?.borderWidth = 1
        refreshColors()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + 18, height: 26)
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self else { return }
            if self.isActiveChip {
                self.layer?.backgroundColor = self.chipTint.withAlphaComponent(0.28).cgColor
                self.layer?.borderColor = self.chipTint.cgColor
                self.contentTintColor = .labelColor
            } else {
                self.layer?.backgroundColor = self.chipTint.withAlphaComponent(0.08).cgColor
                self.layer?.borderColor = self.chipTint.withAlphaComponent(0.35).cgColor
                self.contentTintColor = self.chipTint
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    @objc private func clicked() { onTap() }
}

private final class FixActionButton: NSButton {
    private let onTap: () -> Void
    init(title: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
        self.target = self
        self.action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func clicked() { onTap() }
}

// MARK: - 2. DownloadsViewController (Active Queue & History)

final class DownloadsViewController: NSViewController {
    private var paneHeader: PaneHeaderView!
    private var activeHeader: NSTextField!
    private var activeStack: NSStackView!
    private var historyHeader: NSTextField!
    private var clearHistoryBtn: NSButton!
    private var historyStack: NSStackView!
    private var emptyState: EmptyStateView!

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = docView

        paneHeader = PaneHeaderView(
            symbol: "arrow.down.circle.fill",
            tint: .controlAccentColor,
            title: L10n.tr("sidebar.downloads"),
            subtitle: L10n.isFrench
                ? "File d'attente en direct et historique des téléchargements"
                : "Live download queue and recent installation history"
        )

        activeHeader = settingsGroupLabel("")
        activeStack = NSStackView()
        activeStack.orientation = .vertical
        activeStack.alignment = .leading
        activeStack.spacing = 8
        activeStack.translatesAutoresizingMaskIntoConstraints = false

        historyHeader = settingsGroupLabel("")
        clearHistoryBtn = makeButton(title: "", target: self, action: #selector(clearHistoryTapped))

        let histHeaderRow = NSStackView(views: [historyHeader, NSView(), clearHistoryBtn])
        histHeaderRow.orientation = .horizontal
        histHeaderRow.alignment = .centerY
        histHeaderRow.spacing = 12
        histHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        historyStack = NSStackView()
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 8
        historyStack.translatesAutoresizingMaskIntoConstraints = false

        emptyState = EmptyStateView(
            symbol: "arrow.down.circle",
            prompt: L10n.tr("downloads.empty"),
            hint: L10n.isFrench
                ? "Les jeux et correctifs téléchargés apparaîtront ici avec leur progression."
                : "Downloaded games and fixes will appear here with live progress."
        )

        let mainStack = NSStackView(views: [
            paneHeader,
            activeHeader,
            activeStack,
            histHeaderRow,
            historyStack,
            emptyState
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.setCustomSpacing(18, after: paneHeader)
        mainStack.setCustomSpacing(20, after: activeStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        docView.addSubview(mainStack)
        paneHeader.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        histHeaderRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        activeStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        historyStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        emptyState.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let M = Metrics.paneMargin
        NSLayoutConstraint.activate([
            docView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: M),
            mainStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: M),
            mainStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -M),
            mainStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -M),
        ])

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 520))
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(reloadQueue), name: DownloadQueue.queueDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadQueue), name: L10n.languageChangedNotification, object: nil)
        reloadQueue()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reloadQueue()
    }

    @objc private func clearHistoryTapped() {
        AppSettings.shared.clearHistory()
        reloadQueue()
    }

    private func toneColor(for status: String) -> NSColor {
        switch status.lowercased() {
        case "completed", "done": return .systemGreen
        case "failed", "error": return .systemRed
        case "canceled", "cancelled": return .systemOrange
        default: return .controlAccentColor
        }
    }

    @objc private func reloadQueue() {
        guard isViewLoaded else { return }
        paneHeader.titleLabel.stringValue = L10n.tr("sidebar.downloads")
        paneHeader.subtitleLabel.stringValue = L10n.isFrench
            ? "File d'attente en direct et historique des téléchargements"
            : "Live download queue and recent installation history"
        activeHeader.stringValue = L10n.tr("downloads.active.title")
        historyHeader.stringValue = L10n.tr("downloads.history.title")
        clearHistoryBtn.title = L10n.tr("downloads.btn.clear_history")

        let items = DownloadQueue.shared.items
        let history = AppSettings.shared.downloadHistory

        activeHeader.isHidden = items.isEmpty
        activeStack.isHidden = items.isEmpty
        historyHeader.isHidden = history.isEmpty
        historyStack.isHidden = history.isEmpty

        func stopProgressAnimations(in root: NSView) {
            for sub in root.subviews {
                if let bar = sub as? NSProgressIndicator {
                    bar.stopAnimation(nil)
                } else {
                    stopProgressAnimations(in: sub)
                }
            }
        }
        stopProgressAnimations(in: activeStack)
        activeStack.subviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let card = NSView()
            card.applyCardSurface()
            card.translatesAutoresizingMaskIntoConstraints = false

            let thumb = SteamArtThumbView(cornerRadius: 6, fallbackSymbolSize: 15)
            thumb.load(appId: item.appId)

            let title = NSTextField(labelWithString: "\(item.title)  ·  \(item.subtitle)")
            title.font = .systemFont(ofSize: 13.5, weight: .semibold)
            title.lineBreakMode = .byTruncatingTail

            let statusPill = PillBadge(
                text: item.status.rawValue.uppercased(),
                symbol: item.status.isActive ? "arrow.down.circle.fill" : "exclamationmark.circle",
                tint: toneColor(for: item.status.rawValue)
            )

            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = item.isIndeterminate
            bar.minValue = 0
            bar.maxValue = 1
            bar.doubleValue = item.progressFraction
            if item.isIndeterminate && item.status.isActive { bar.startAnimation(nil) }
            bar.translatesAutoresizingMaskIntoConstraints = false

            let statusLbl = NSTextField(labelWithString: item.message ?? "")
            statusLbl.font = Typography.caption
            statusLbl.textColor = .secondaryLabelColor
            statusLbl.isHidden = (item.message?.isEmpty ?? true)

            let actionBtn: NSButton
            if item.status.isActive {
                actionBtn = FixActionButton(title: L10n.tr("downloads.btn.cancel")) {
                    DownloadQueue.shared.cancel(item)
                }
            } else {
                actionBtn = FixActionButton(title: L10n.tr("downloads.btn.retry")) {
                    DownloadQueue.shared.retry(item)
                }
            }

            let topRow = NSStackView(views: [title, statusPill, NSView(), actionBtn])
            topRow.orientation = .horizontal
            topRow.alignment = .centerY
            topRow.spacing = 8

            let vStack = NSStackView(views: [topRow, bar, statusLbl])
            vStack.orientation = .vertical
            vStack.alignment = .leading
            vStack.spacing = 6
            vStack.translatesAutoresizingMaskIntoConstraints = false
            topRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
            bar.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

            card.addSubview(thumb)
            card.addSubview(vStack)
            NSLayoutConstraint.activate([
                thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                thumb.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 74),
                thumb.heightAnchor.constraint(equalToConstant: 34),

                vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                vStack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
                vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            ])
            activeStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: activeStack.widthAnchor).isActive = true
        }

        historyStack.subviews.forEach { $0.removeFromSuperview() }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        for rec in history.prefix(30) {
            let row = NSView()
            row.applyCardSurface()
            row.translatesAutoresizingMaskIntoConstraints = false

            let thumb = SteamArtThumbView(cornerRadius: 6, fallbackSymbolSize: 15)
            thumb.load(appId: rec.appId)

            let lbl = NSTextField(labelWithString: rec.title)
            lbl.font = .systemFont(ofSize: 13.5, weight: .semibold)
            lbl.lineBreakMode = .byTruncatingTail

            let subText = [rec.source, df.string(from: rec.completedAt), rec.message]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  ")
            let sub = NSTextField(labelWithString: subText)
            sub.font = Typography.caption
            sub.textColor = .secondaryLabelColor
            sub.lineBreakMode = .byTruncatingTail

            let pill = PillBadge(
                text: rec.status.uppercased(),
                symbol: rec.status.lowercased() == "completed" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: toneColor(for: rec.status)
            )

            let st = NSStackView(views: [lbl, sub])
            st.orientation = .vertical
            st.alignment = .leading
            st.spacing = 2
            st.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(thumb)
            row.addSubview(st)
            row.addSubview(pill)
            NSLayoutConstraint.activate([
                thumb.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                thumb.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 74),
                thumb.heightAnchor.constraint(equalToConstant: 34),

                st.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                st.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
                st.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -10),
                st.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),

                pill.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                pill.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            historyStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
        }

        clearHistoryBtn.isHidden = history.isEmpty
        emptyState.isHidden = !(items.isEmpty && history.isEmpty)
    }
}

// MARK: - 3. PluginViewController (LuaTools Screenshot 3 style)

final class PluginViewController: NSViewController {
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var stateBadge: PillBadge!
    private var serverPill: PillBadge!
    private var cefPill: PillBadge!
    private var scriptPill: PillBadge!

    private var installBtn: NSButton!
    private var uninstallBtn: NSButton!
    private var restartSteamBtn: NSButton!
    private var spinner: NSProgressIndicator!

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        subtitleLabel = NSTextField(wrappingLabelWithString: "")
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = .secondaryLabelColor

        // Main "État" card (Screenshot 3 style)
        let stateCard = NSView()
        stateCard.applyCardSurface()
        stateCard.translatesAutoresizingMaskIntoConstraints = false

        let cardIcon = NSImageView()
        cardIcon.image = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil)
        cardIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        cardIcon.contentTintColor = .systemBlue

        let stateHeading = NSTextField(labelWithString: L10n.isFrench ? "État" : "Status")
        stateHeading.font = .systemFont(ofSize: 15, weight: .bold)
        stateBadge = PillBadge(text: "—", tint: .systemPurple)

        let stateTopRow = NSStackView(views: [cardIcon, stateHeading, stateBadge, NSView()])
        stateTopRow.orientation = .horizontal
        stateTopRow.alignment = .centerY
        stateTopRow.spacing = 8

        serverPill = PillBadge(text: "Stopped", tint: .secondaryLabelColor)
        cefPill = PillBadge(text: "Not set", tint: .secondaryLabelColor)
        scriptPill = PillBadge(text: "Missing", tint: .secondaryLabelColor)

        let rowsCard = SettingsCard(rows: [
            SettingRow(title: L10n.tr("plugin.row.server"), control: serverPill),
            SettingRow(title: L10n.tr("plugin.row.cef"), control: cefPill),
            SettingRow(title: L10n.tr("plugin.row.script"), control: scriptPill),
        ])

        let infoBanner = makeInfoBanner(
            text: L10n.isFrench
                ? "Le plugin injecte un bouton natif dans les pages de la boutique Steam via CEF (port 8080)."
                : "The plugin injects a native button into Steam Store pages via the CEF debugging bridge (port 8080).",
            tint: .systemBlue
        )

        installBtn = makeButton(title: "", target: self, action: #selector(installTapped))
        installBtn.bezelColor = .controlAccentColor
        installBtn.keyEquivalent = "\r"
        uninstallBtn = makeButton(title: "", target: self, action: #selector(uninstallTapped))
        restartSteamBtn = makeButton(title: "", target: self, action: #selector(restartSteamTapped))

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let btnRow = NSStackView(views: [installBtn, uninstallBtn, restartSteamBtn, spinner, NSView()])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        let cardStack = NSStackView(views: [stateTopRow, rowsCard, infoBanner, btnRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        rowsCard.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        infoBanner.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        btnRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        stateCard.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: stateCard.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: stateCard.bottomAnchor, constant: -16),
            cardStack.leadingAnchor.constraint(equalTo: stateCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: stateCard.trailingAnchor, constant: -16),
        ])

        // "Fonctionnalités notables" section (Screenshot 3 style)
        let featuresHeader = settingsGroupLabel(L10n.isFrench ? "Fonctionnalités notables" : "Notable Features")
        let f1 = makeFeatureCard(
            symbol: "plus.circle",
            tint: .systemPurple,
            text: L10n.isFrench ? "Ajoute un bouton « Add via LuaTools / macSteam » aux pages du magasin Steam" : "Adds an 'Add via LuaTools / macSteam' button to Steam Store pages"
        )
        let f2 = makeFeatureCard(
            symbol: "arrow.triangle.2.circlepath",
            tint: .systemPurple,
            text: L10n.isFrench ? "Met à jour le script frontend automatiquement" : "Updates the frontend script automatically"
        )
        let f3 = makeFeatureCard(
            symbol: "puzzlepiece.extension",
            tint: .systemPurple,
            text: L10n.isFrench ? "Fonctionne nativement avec le pont CEF de Steam macOS" : "Works natively with macOS Steam's CEF debugging bridge"
        )

        let mainStack = NSStackView(views: [titleLabel, subtitleLabel, stateCard, featuresHeader, f1, f2, f3])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.setCustomSpacing(4, after: titleLabel)
        mainStack.setCustomSpacing(16, after: subtitleLabel)
        mainStack.setCustomSpacing(18, after: stateCard)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        doc.addSubview(mainStack)
        stateCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        f1.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        f2.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        f3.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let M = Metrics.paneMargin
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: M - 4),
            mainStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: M),
            mainStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -M),
            mainStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -M),
        ])

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 500))
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: L10n.languageChangedNotification, object: nil)
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    @objc private func refresh() {
        guard isViewLoaded else { return }
        let st = PluginInstallerService.shared.currentStatus()
        let active = st.frontendInstalled && st.cefMarkerInstalled && st.serverRunning

        titleLabel.stringValue = L10n.tr("sidebar.plugin")
        subtitleLabel.stringValue = L10n.tr("plugin.subtitle")
        stateBadge.update(
            text: active ? L10n.tr("plugin.status.installed") : L10n.tr("plugin.status.not_installed"),
            tint: active ? .systemGreen : .systemOrange
        )

        serverPill.update(
            text: st.serverRunning ? "Running" : "Stopped",
            symbol: st.serverRunning ? "checkmark.circle.fill" : "pause.circle",
            tint: st.serverRunning ? .systemGreen : .secondaryLabelColor
        )
        cefPill.update(
            text: st.cefMarkerInstalled ? "Enabled" : "Not set",
            symbol: st.cefMarkerInstalled ? "checkmark.circle.fill" : "minus.circle",
            tint: st.cefMarkerInstalled ? .systemGreen : .secondaryLabelColor
        )
        scriptPill.update(
            text: st.frontendInstalled ? (st.installedTag ?? "Installed") : "Missing",
            symbol: st.frontendInstalled ? "checkmark.circle.fill" : "xmark.circle",
            tint: st.frontendInstalled ? .systemGreen : .systemOrange
        )

        installBtn.title = active ? L10n.tr("plugin.btn.update") : L10n.tr("plugin.btn.install")
        uninstallBtn.title = L10n.tr("plugin.btn.uninstall")
        uninstallBtn.isEnabled = st.frontendInstalled || st.cefMarkerInstalled
        restartSteamBtn.title = L10n.tr("plugin.btn.restart_steam")
    }

    @objc private func installTapped() {
        spinner.startAnimation(nil)
        installBtn.isEnabled = false
        Task {
            try? await PluginInstallerService.shared.installOrUpdate()
            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.installBtn.isEnabled = true
                self.refresh()
            }
        }
    }

    @objc private func uninstallTapped() {
        PluginInstallerService.shared.uninstall()
        refresh()
    }

    @objc private func restartSteamTapped() {
        SteamLibraryService.restartSteam()
    }
}
