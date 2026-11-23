// Online Search, Featured Games, Source Checker, and Manifest/DLC Downloader View Controller.
import AppKit

final class SearchDownloadViewController: NSViewController {
    let store: ConfigStore
    var onOpenGameInLibrary: ((Int) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var pageTitleLabel: NSTextField!
    private var pageSubtitleLabel: NSTextField!
    private var searchField: NSSearchField!
    private var fastFetchCheck: NSButton!
    private var spinner: NSProgressIndicator!

    // Search results list
    private var resultsCard: NSView!
    private var resultsStack: NSStackView!

    // Featured strips (shown when idle)
    private var featuredContainer: NSStackView!
    private var topSellersHeader: NSTextField!
    private var topSellersRow: NSStackView!
    private var newReleasesHeader: NSTextField!
    private var newReleasesRow: NSStackView!

    // Selected game details card
    private var detailsCard: NSView!
    private var detailsArt: NSImageView!
    private var detailsTitle: NSTextField!
    private var detailsBadge: NSTextField!
    private var detailsGenres: NSTextField!
    private var checkSourcesBtn: NSButton!

    // Sources / DLC container
    private var sourcesHeader: NSTextField!
    private var sourcesStack: NSStackView!

    // Install result banner
    private var bannerCard: NSView!
    private var bannerLabel: NSTextField!
    private var revealBtn: NSButton!

    private var searchTask: Task<Void, Never>?
    private var currentDetails: GameDetails?
    private var lastInstalledAppId: Int?
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

        // Page header (LuaTools Screenshot 4 style)
        pageTitleLabel = NSTextField(labelWithString: "")
        pageTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        pageTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        pageSubtitleLabel = NSTextField(labelWithString: "")
        pageSubtitleLabel.font = Typography.body
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Top search bar + FastFetch
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .large
        searchField.font = Typography.body
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false

        fastFetchCheck = NSButton(checkboxWithTitle: "", target: self, action: #selector(fastFetchToggled))
        fastFetchCheck.translatesAutoresizingMaskIntoConstraints = false
        fastFetchCheck.state = AppSettings.shared.fastFetch ? .on : .off

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSStackView(views: [searchField, spinner, fastFetchCheck])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 12
        topBar.translatesAutoresizingMaskIntoConstraints = false

        // Search results dropdown card
        resultsCard = NSView()
        resultsCard.applyCardSurface()
        resultsCard.translatesAutoresizingMaskIntoConstraints = false
        resultsCard.isHidden = true

        resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 2
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsCard.addSubview(resultsStack)
        NSLayoutConstraint.activate([
            resultsStack.topAnchor.constraint(equalTo: resultsCard.topAnchor, constant: 6),
            resultsStack.leadingAnchor.constraint(equalTo: resultsCard.leadingAnchor, constant: 6),
            resultsStack.trailingAnchor.constraint(equalTo: resultsCard.trailingAnchor, constant: -6),
            resultsStack.bottomAnchor.constraint(equalTo: resultsCard.bottomAnchor, constant: -6),
        ])

        // Install status banner
        bannerCard = NSView()
        bannerCard.applyCardSurface()
        bannerCard.translatesAutoresizingMaskIntoConstraints = false
        bannerCard.isHidden = true

        bannerLabel = NSTextField(wrappingLabelWithString: "")
        bannerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        bannerLabel.textColor = .systemGreen
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false

        revealBtn = makeButton(title: "", target: self, action: #selector(revealInstalledGame))
        let bannerRow = NSStackView(views: [bannerLabel, revealBtn])
        bannerRow.orientation = .horizontal
        bannerRow.alignment = .centerY
        bannerRow.spacing = 12
        bannerRow.translatesAutoresizingMaskIntoConstraints = false
        bannerCard.addSubview(bannerRow)
        NSLayoutConstraint.activate([
            bannerRow.topAnchor.constraint(equalTo: bannerCard.topAnchor, constant: 10),
            bannerRow.leadingAnchor.constraint(equalTo: bannerCard.leadingAnchor, constant: 14),
            bannerRow.trailingAnchor.constraint(equalTo: bannerCard.trailingAnchor, constant: -14),
            bannerRow.bottomAnchor.constraint(equalTo: bannerCard.bottomAnchor, constant: -10),
        ])

        // Selected Game Details Card
        detailsCard = buildDetailsCard()
        detailsCard.isHidden = true

        // Sources Section
        sourcesHeader = settingsGroupLabel("")
        sourcesHeader.isHidden = true
        sourcesStack = NSStackView()
        sourcesStack.orientation = .vertical
        sourcesStack.alignment = .leading
        sourcesStack.spacing = 8
        sourcesStack.translatesAutoresizingMaskIntoConstraints = false
        sourcesStack.isHidden = true

        // Featured Strips (horizontally scrollable like LuaTools)
        topSellersHeader = settingsGroupLabel("")
        topSellersRow = NSStackView()
        topSellersRow.orientation = .horizontal
        topSellersRow.alignment = .top
        topSellersRow.spacing = 12
        topSellersRow.translatesAutoresizingMaskIntoConstraints = false
        let topSellersScroll = makeHorizontalCarousel(for: topSellersRow)

        newReleasesHeader = settingsGroupLabel("")
        newReleasesRow = NSStackView()
        newReleasesRow.orientation = .horizontal
        newReleasesRow.alignment = .top
        newReleasesRow.spacing = 12
        newReleasesRow.translatesAutoresizingMaskIntoConstraints = false
        let newReleasesScroll = makeHorizontalCarousel(for: newReleasesRow)

        featuredContainer = NSStackView(views: [
            topSellersHeader, topSellersScroll,
            newReleasesHeader, newReleasesScroll
        ])
        featuredContainer.orientation = .vertical
        featuredContainer.alignment = .leading
        featuredContainer.spacing = 10
        featuredContainer.setCustomSpacing(18, after: topSellersScroll)
        featuredContainer.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [
            pageTitleLabel,
            pageSubtitleLabel,
            topBar,
            resultsCard,
            bannerCard,
            detailsCard,
            sourcesHeader,
            sourcesStack,
            featuredContainer
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.setCustomSpacing(4, after: pageTitleLabel)
        mainStack.setCustomSpacing(14, after: pageSubtitleLabel)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        docView.addSubview(mainStack)
        for v in [topBar, resultsCard, bannerCard, detailsCard, sourcesStack, featuredContainer, topSellersScroll, newReleasesScroll] {
            v?.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        }

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

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 540))
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(localizeLabels), name: L10n.languageChangedNotification, object: nil)
        localizeLabels()
        loadFeaturedIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fastFetchCheck.state = AppSettings.shared.fastFetch ? .on : .off
    }

    @objc private func localizeLabels() {
        guard isViewLoaded else { return }
        let fr = L10n.isFrench
        pageTitleLabel.stringValue = fr ? "C'est parti pour Luaer !" : "Search & Add Games"
        pageSubtitleLabel.stringValue = fr
            ? "Saisissez un App ID, collez un lien Steam ou recherchez par nom de jeu"
            : "Enter an App ID, paste a Steam link, or search by game name"
        searchField.placeholderString = L10n.tr("search.placeholder")
        fastFetchCheck.title = L10n.tr("search.fastfetch")
        topSellersHeader.stringValue = L10n.tr("search.featured.top")
        newReleasesHeader.stringValue = L10n.tr("search.featured.new")
        sourcesHeader.stringValue = L10n.tr("search.sources.title")
        revealBtn.title = L10n.tr("search.btn.reveal_library")
        if let d = currentDetails {
            checkSourcesBtn.title = d.isDlc ? L10n.tr("search.btn.check_dlc") : L10n.tr("search.btn.check_sources")
        }
    }

    private func buildDetailsCard() -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        detailsArt = NSImageView()
        detailsArt.imageScaling = .scaleProportionallyUpOrDown
        detailsArt.wantsLayer = true
        detailsArt.layer?.cornerRadius = 6
        detailsArt.layer?.masksToBounds = true
        detailsArt.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        detailsArt.translatesAutoresizingMaskIntoConstraints = false

        detailsTitle = NSTextField(labelWithString: "")
        detailsTitle.font = .systemFont(ofSize: 17, weight: .bold)
        detailsTitle.textColor = .labelColor
        detailsTitle.lineBreakMode = .byTruncatingTail

        detailsBadge = NSTextField(labelWithString: "")
        detailsBadge.font = Typography.caption
        detailsBadge.textColor = .controlAccentColor

        detailsGenres = NSTextField(labelWithString: "")
        detailsGenres.font = Typography.caption
        detailsGenres.textColor = .secondaryLabelColor
        detailsGenres.lineBreakMode = .byTruncatingTail

        checkSourcesBtn = makeButton(title: L10n.tr("search.btn.check_sources"), target: self, action: #selector(checkSourcesTapped))
        checkSourcesBtn.keyEquivalent = "\r"

        let infoStack = NSStackView(views: [detailsTitle, detailsBadge, detailsGenres, checkSourcesBtn])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        infoStack.setCustomSpacing(10, after: detailsGenres)
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(detailsArt)
        card.addSubview(infoStack)

        NSLayoutConstraint.activate([
            detailsArt.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            detailsArt.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            detailsArt.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            detailsArt.widthAnchor.constraint(equalToConstant: 210),
            detailsArt.heightAnchor.constraint(equalToConstant: 98),

            infoStack.leadingAnchor.constraint(equalTo: detailsArt.trailingAnchor, constant: 16),
            infoStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            infoStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    // MARK: - Featured Strips

    private func makeHorizontalCarousel(for row: NSStackView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = row

        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 148),
            row.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            row.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentView.bottomAnchor),
        ])
        return scroll
    }

    private func loadFeaturedIfNeeded() {
        Task {
            let (top, fresh) = await LuaToolsAPI.shared.getFeatured()
            await MainActor.run {
                self.populateFeatured(row: self.topSellersRow, items: Array(top.prefix(16)))
                self.populateFeatured(row: self.newReleasesRow, items: Array(fresh.prefix(16)))
            }
        }
    }

    private func populateFeatured(row: NSStackView, items: [SteamFeaturedItem]) {
        row.subviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let tile = RecentFeaturedCard(item: item) { [weak self] appId, name in
                self?.selectApp(appId: appId, name: name)
            }
            row.addArrangedSubview(tile)
            artLoader.load([item.id], artWidth: 300, onName: { _, _ in }, onArt: { id, img in
                if id == item.id { tile.setImage(img) }
            })
        }
    }

    // MARK: - Search & Seed

    func seedSearch(appId: Int) {
        _ = view
        searchField.stringValue = "\(appId)"
        selectApp(appId: appId, name: nil)
    }

    @objc private func fastFetchToggled() {
        AppSettings.shared.fastFetch = (fastFetchCheck.state == .on)
    }

    @objc private func searchFieldAction() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        if query.isEmpty {
            resultsCard.isHidden = true
            detailsCard.isHidden = true
            sourcesHeader.isHidden = true
            sourcesStack.isHidden = true
            featuredContainer.isHidden = false
            spinner.stopAnimation(nil)
            return
        }

        if let directAppId = SteamLinkParser.extractAppId(from: query) {
            resultsCard.isHidden = true
            spinner.stopAnimation(nil)
            selectApp(appId: directAppId, name: nil)
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self.spinner.startAnimation(nil) }
            let results = await LuaToolsAPI.shared.search(query: query)
            if Task.isCancelled {
                await MainActor.run { self.spinner.stopAnimation(nil) }
                return
            }
            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.renderSearchResults(results)
            }
        }
    }

    private func renderSearchResults(_ results: [SteamSearchResult]) {
        resultsStack.subviews.forEach { $0.removeFromSuperview() }
        guard !results.isEmpty else {
            resultsCard.isHidden = true
            return
        }
        for r in results {
            let btn = NSButton(title: "\(r.name)  (AppID \(r.appId))", target: self, action: #selector(searchResultClicked(_:)))
            btn.tag = r.appId
            btn.bezelStyle = .recessed
            btn.showsBorderOnlyWhileMouseInside = true
            btn.alignment = .left
            btn.font = Typography.body
            btn.translatesAutoresizingMaskIntoConstraints = false
            resultsStack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        }
        resultsCard.isHidden = false
    }

    @objc private func searchResultClicked(_ sender: NSButton) {
        let appId = sender.tag
        resultsCard.isHidden = true
        selectApp(appId: appId, name: nil)
    }

    private func selectApp(appId: Int, name: String?) {
        resultsCard.isHidden = true
        featuredContainer.isHidden = true
        sourcesHeader.isHidden = true
        sourcesStack.isHidden = true
        bannerCard.isHidden = true
        spinner.startAnimation(nil)

        Task {
            let details = await LuaToolsAPI.shared.resolveGameDetails(appId: appId)
                ?? GameDetails(appId: appId, name: name ?? "App \(appId)", type: "game", baseAppId: nil, genres: [], headerImage: nil, releaseDate: nil)
            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.currentDetails = details
                self.showDetails(details)
                if AppSettings.shared.fastFetch {
                    self.checkSourcesTapped()
                }
            }
        }
    }

    private func showDetails(_ d: GameDetails) {
        detailsTitle.stringValue = d.name
        if d.isDlc, let base = d.baseAppId {
            detailsBadge.stringValue = L10n.tr("search.dlc.badge", base)
            checkSourcesBtn.title = L10n.tr("search.btn.check_dlc")
        } else {
            detailsBadge.stringValue = L10n.tr("search.game.badge", d.appId)
            checkSourcesBtn.title = L10n.tr("search.btn.check_sources")
        }
        var meta = d.genres
        if let rel = d.releaseDate, !rel.isEmpty { meta.append(rel) }
        detailsGenres.stringValue = meta.joined(separator: "  ·  ")
        detailsArt.image = artLoader.image(for: d.appId)
        detailsCard.isHidden = false

        artLoader.load([d.appId], artWidth: 420, onName: { _, _ in }, onArt: { [weak self] id, img in
            if self?.currentDetails?.appId == id {
                self?.detailsArt.image = img
            }
        })
    }

    // MARK: - Check Sources & Download

    @objc private func checkSourcesTapped() {
        guard let details = currentDetails else { return }
        spinner.startAnimation(nil)
        checkSourcesBtn.isEnabled = false
        sourcesStack.subviews.forEach { $0.removeFromSuperview() }
        sourcesHeader.isHidden = false
        sourcesStack.isHidden = false

        if details.isDlc {
            guard let baseAppId = details.baseAppId else {
                spinner.stopAnimation(nil)
                checkSourcesBtn.isEnabled = true
                return
            }
            Task {
                do {
                    let info = try await LuaToolsAPI.shared.getDlcInfo(appId: details.appId, baseAppId: baseAppId)
                    await MainActor.run {
                        self.spinner.stopAnimation(nil)
                        self.checkSourcesBtn.isEnabled = true
                        self.renderDlcInfo(info, details: details, baseAppId: baseAppId)
                    }
                } catch {
                    await MainActor.run {
                        self.spinner.stopAnimation(nil)
                        self.checkSourcesBtn.isEnabled = true
                        self.renderDlcDirectButton(details: details, baseAppId: baseAppId, error: error.localizedDescription)
                    }
                }
            }
            return
        }

        Task {
            let statuses = await LuaToolsAPI.shared.checkSources(appId: details.appId)
            let key = AppSettings.shared.hubcapApiKey
            let hubStats = (key != nil && !key!.isEmpty) ? await HubcapService.shared.getStats(key: key!) : nil
            let stdUsage = await LuaToolsAPI.shared.getStandardUsage()

            await MainActor.run {
                self.spinner.stopAnimation(nil)
                self.checkSourcesBtn.isEnabled = true
                self.renderSources(statuses: statuses, details: details, hubStats: hubStats, stdUsage: stdUsage)
            }
        }
    }

    private func renderSources(
        statuses: [String: String],
        details: GameDetails,
        hubStats: HubcapStats?,
        stdUsage: (used: Int, limit: Int)?
    ) {
        sourcesStack.subviews.forEach { $0.removeFromSuperview() }
        let sorted = statuses.sorted { a, b in
            if a.key == "Luie" { return true }
            if b.key == "Luie" { return false }
            let availA = (a.value == "available") ? 1 : 0
            let availB = (b.value == "available") ? 1 : 0
            if availA != availB { return availA > availB }
            let ka = SourceMetaInfo.get(a.key).requiresUserKey ? 1 : 0
            let kb = SourceMetaInfo.get(b.key).requiresUserKey ? 1 : 0
            if ka != kb { return ka > kb }
            return a.key < b.key
        }

        let hasKey = !(AppSettings.shared.hubcapApiKey?.isEmpty ?? true)
        var firstAvailableSource: String?

        for (name, status) in sorted {
            let meta = SourceMetaInfo.get(name)
            let displayName = meta.displayName ?? name
            let isAvailable = (status == "available")
            let locked = meta.requiresUserKey && (!hasKey || hubStats?.canMakeRequests == false)
            let canDownload = isAvailable && !locked

            if firstAvailableSource == nil && canDownload {
                firstAvailableSource = name
            }

            var quotaText = ""
            if meta.requiresUserKey {
                if let hubStats { quotaText = "\(hubStats.dailyUsage)/\(hubStats.dailyLimit)" }
            } else if let stdUsage {
                quotaText = "\(stdUsage.used)/\(stdUsage.limit)"
            }

            let row = buildSourceRow(
                sourceName: name,
                displayName: displayName,
                status: status,
                needsKey: meta.requiresUserKey,
                locked: locked,
                quotaText: quotaText,
                discordUrl: meta.discordUrl,
                canDownload: canDownload
            )
            sourcesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: sourcesStack.widthAnchor).isActive = true
        }

        if AppSettings.shared.fastFetch, let best = firstAvailableSource {
            startDownload(sourceName: best, details: details)
        }
    }

    private func buildSourceRow(
        sourceName: String,
        displayName: String,
        status: String,
        needsKey: Bool,
        locked: Bool,
        quotaText: String,
        discordUrl: String?,
        canDownload: Bool
    ) -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .labelColor

        let badgeText: String
        let badgeColor: NSColor
        if needsKey && locked {
            badgeText = L10n.tr("search.status.needs_key")
            badgeColor = .systemOrange
        } else if status == "available" {
            badgeText = L10n.tr("search.status.available")
            badgeColor = .systemGreen
        } else {
            badgeText = L10n.tr("search.status.unavailable")
            badgeColor = .secondaryLabelColor
        }

        let badgeLabel = NSTextField(labelWithString: badgeText + (quotaText.isEmpty ? "" : "  ·  \(quotaText)"))
        badgeLabel.font = Typography.caption
        badgeLabel.textColor = badgeColor

        let leftStack = NSStackView(views: [nameLabel, badgeLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let dlBtn = makeButton(title: L10n.tr("search.btn.download"), target: self, action: #selector(downloadSourceClicked(_:)))
        dlBtn.identifier = NSUserInterfaceItemIdentifier(sourceName)
        dlBtn.isEnabled = canDownload

        card.addSubview(leftStack)
        card.addSubview(dlBtn)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 56),
            leftStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            leftStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            dlBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            dlBtn.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    private func renderDlcInfo(_ info: DlcInfo, details: GameDetails, baseAppId: String) {
        sourcesStack.subviews.forEach { $0.removeFromSuperview() }
        let summary = NSTextField(labelWithString: "\(info.name) — \(info.haveCount)/\(info.depotCount) depots")
        summary.font = Typography.body
        sourcesStack.addArrangedSubview(summary)

        let genBtn = makeButton(title: L10n.tr("search.btn.generate_dlc"), target: self, action: #selector(generateDlcClicked))
        sourcesStack.addArrangedSubview(genBtn)
    }

    private func renderDlcDirectButton(details: GameDetails, baseAppId: String, error: String) {
        sourcesStack.subviews.forEach { $0.removeFromSuperview() }
        let genBtn = makeButton(title: L10n.tr("search.btn.generate_dlc"), target: self, action: #selector(generateDlcClicked))
        sourcesStack.addArrangedSubview(genBtn)
    }

    @objc private func downloadSourceClicked(_ sender: NSButton) {
        guard let sourceName = sender.identifier?.rawValue,
              let details = currentDetails else { return }
        startDownload(sourceName: sourceName, details: details)
    }

    private func startDownload(sourceName: String, details: GameDetails) {
        let meta = SourceMetaInfo.get(sourceName)
        let hasHubcap = !(AppSettings.shared.hubcapApiKey?.isEmpty ?? true)
        if !meta.requiresUserKey && AuthService.shared.isGuest {
            let alert = NSAlert()
            alert.messageText = L10n.tr("search.err.signin_required")
            alert.addButton(withTitle: L10n.tr("sidebar.settings"))
            alert.addButton(withTitle: L10n.tr("common.cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                onOpenSettings?()
            }
            return
        }
        if meta.requiresUserKey && !hasHubcap {
            onOpenSettings?()
            return
        }

        spinner.startAnimation(nil)
        let storeRef = store

        let item = DownloadQueueItem(
            dedupeKey: "manifest:\(details.appId)",
            appId: details.appId,
            title: details.name,
            subtitle: meta.displayName ?? sourceName,
            work: { [weak self] qItem in
                let fileURL = try await LuaToolsAPI.shared.downloadManifest(
                    appId: details.appId,
                    source: sourceName,
                    gameName: details.name,
                    onProgress: { read, total in
                        DownloadQueue.shared.updateProgress(for: qItem, bytesRead: read, totalBytes: total)
                    }
                )
                defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

                // Overwrite confirmation if game already exists
                if let existingLua = LuaVault.shared.readLiveText(details.appId), !existingLua.isEmpty {
                    let proceed = await MainActor.run { () -> Bool in
                        guard let self else { return true }
                        return self.confirmOverwrite(fileURL: fileURL, existingLua: existingLua, details: details)
                    }
                    if !proceed { throw CancellationError() }
                }

                DownloadQueue.shared.setInstalling(qItem)
                let res = try UnifiedInstaller.installDownloaded(
                    fileURL: fileURL,
                    appId: details.appId,
                    gameName: details.name,
                    source: sourceName,
                    store: storeRef
                )
                return "\(details.name) (\(res.manifestCount) manifests, \(res.dlcCount) DLC)"
            },
            onFinished: { [weak self] qItem, ok in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.spinner.stopAnimation(nil)
                    if ok {
                        self.lastInstalledAppId = details.appId
                        self.bannerLabel.stringValue = L10n.tr("search.installed.banner", qItem.message ?? details.name)
                        self.bannerCard.isHidden = false
                    } else if let msg = qItem.message {
                        presentAlert("Download failed", msg, style: .warning)
                    }
                }
            }
        )
        DownloadQueue.shared.enqueue(item)
    }

    @objc private func generateDlcClicked() {
        guard let details = currentDetails, let baseAppId = details.baseAppId else { return }
        if AuthService.shared.isGuest {
            onOpenSettings?()
            return
        }
        spinner.startAnimation(nil)
        let storeRef = store
        let item = DownloadQueueItem(
            dedupeKey: "dlc:\(details.appId)",
            appId: details.appId,
            title: details.name,
            subtitle: "DLC",
            work: { qItem in
                let fileURL = try await LuaToolsAPI.shared.generateDlc(
                    appId: details.appId,
                    baseAppId: baseAppId,
                    gameName: details.name,
                    onProgress: { read, total in
                        DownloadQueue.shared.updateProgress(for: qItem, bytesRead: read, totalBytes: total)
                    }
                )
                defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
                DownloadQueue.shared.setInstalling(qItem)
                _ = try UnifiedInstaller.installDownloaded(
                    fileURL: fileURL,
                    appId: details.appId,
                    gameName: details.name,
                    source: "DLC Generator",
                    store: storeRef
                )
                return details.name
            },
            onFinished: { [weak self] qItem, ok in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.spinner.stopAnimation(nil)
                    if ok {
                        self.lastInstalledAppId = details.appId
                        self.bannerLabel.stringValue = L10n.tr("search.installed.banner", details.name)
                        self.bannerCard.isHidden = false
                    } else if let msg = qItem.message {
                        presentAlert("DLC failed", msg, style: .warning)
                    }
                }
            }
        )
        DownloadQueue.shared.enqueue(item)
    }

    private func confirmOverwrite(fileURL: URL, existingLua: String, details: GameDetails) -> Bool {
        var newLuaText = ""
        if UnifiedInstaller.isZipFile(fileURL) {
            if let plans = try? ZipImporter.buildPlans(from: fileURL),
               let first = plans.first {
                newLuaText = first.luaText
                for p in plans { ZipImporter.cleanup(p.extractDir) }
            }
        } else if let txt = try? String(contentsOf: fileURL, encoding: .utf8) {
            newLuaText = txt
        }
        guard !newLuaText.isEmpty else { return true }

        let diff = DetailedLuaParser.diff(oldText: existingLua, newText: newLuaText, appId: details.appId)
        let alert = NSAlert()
        alert.messageText = L10n.tr("search.overwrite.title", details.name)
        var lines = [L10n.tr("search.overwrite.subtitle")]
        if diff.added.isEmpty && diff.removed.isEmpty {
            lines.append(L10n.tr("search.overwrite.no_changes"))
        } else {
            if !diff.added.isEmpty {
                let ids = diff.added.prefix(8).map { "\($0.id)" }.joined(separator: ", ")
                lines.append(L10n.tr("search.overwrite.added", diff.added.count, ids))
            }
            if !diff.removed.isEmpty {
                let ids = diff.removed.prefix(8).map { "\($0.id)" }.joined(separator: ", ")
                lines.append(L10n.tr("search.overwrite.removed", diff.removed.count, ids))
            }
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: L10n.tr("search.overwrite.confirm"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func revealInstalledGame() {
        if let id = lastInstalledAppId {
            onOpenGameInLibrary?(id)
        }
    }
}

private final class RecentFeaturedCard: NSView {
    let item: SteamFeaturedItem
    private let artView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let onSelect: (Int, String) -> Void

    init(item: SteamFeaturedItem, onSelect: @escaping (Int, String) -> Void) {
        self.item = item
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyCardSurface()

        artView.imageScaling = .scaleProportionallyUpOrDown
        artView.wantsLayer = true
        artView.layer?.cornerRadius = 6
        artView.layer?.masksToBounds = true
        artView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        artView.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = item.name
        nameField.font = .systemFont(ofSize: 12, weight: .semibold)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(artView)
        addSubview(nameField)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 196),

            artView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            artView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            artView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            artView.heightAnchor.constraint(equalToConstant: 90),

            nameField.topAnchor.constraint(equalTo: artView.bottomAnchor, constant: 6),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ img: NSImage?) { artView.image = img }

    override func mouseUp(with event: NSEvent) {
        onSelect(item.id, item.name)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurfaceColors()
    }
}
