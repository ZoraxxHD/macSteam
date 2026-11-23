// Depots & Builds Manager View Controller (LuaVault variants, per-depot/DLC switches, raw Lua editor, manifest fetcher).
import AppKit

final class BuildsViewController: NSViewController {
    let store: ConfigStore

    private var gameSearchField: NSSearchField!
    private var gamesTable: NSTableView!

    private var rightContainer: NSView!
    private var emptyStateView: EmptyStateView!
    private var detailStack: NSStackView!

    private var selectedGameTitle: NSTextField!
    private var variantsHeader: NSTextField!
    private var variantPopup: NSPopUpButton!
    private var applyVariantBtn: NSButton!
    private var savePresetBtn: NSButton!
    private var editLuaBtn: NSButton!
    private var renameVariantBtn: NSButton!
    private var deleteVariantBtn: NSButton!

    private var depotsHeader: NSTextField!
    private var depotSearchField: NSSearchField!
    private var depotsTable: NSTableView!

    private var allGameIds: [Int] = []
    private var filteredGameIds: [Int] = []
    private var activeAppId: Int?

    private var variants: [LuaVariant] = []
    private var allEntries: [DetailedLuaEntry] = []
    private var filteredEntries: [DetailedLuaEntry] = []

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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))

        // Left pane: card surface wrapping search + games list (LuaTools Screenshot 1 style)
        let leftPane = NSView()
        leftPane.applyCardSurface()
        leftPane.translatesAutoresizingMaskIntoConstraints = false

        let pageHeader = NSTextField(labelWithString: L10n.tr("sidebar.builds"))
        pageHeader.font = .systemFont(ofSize: 22, weight: .bold)
        pageHeader.translatesAutoresizingMaskIntoConstraints = false

        gameSearchField = NSSearchField()
        gameSearchField.translatesAutoresizingMaskIntoConstraints = false
        gameSearchField.target = self
        gameSearchField.action = #selector(gameSearchChanged)
        gameSearchField.sendsSearchStringImmediately = true

        let gamesScroll = makeScrollView()
        gamesScroll.translatesAutoresizingMaskIntoConstraints = false

        gamesTable = NSTableView()
        gamesTable.headerView = nil
        gamesTable.rowHeight = 52
        gamesTable.intercellSpacing = NSSize(width: 0, height: 3)
        gamesTable.style = .inset
        gamesTable.backgroundColor = .clear
        let gCol = NSTableColumn(identifier: .init("game"))
        gCol.resizingMask = .autoresizingMask
        gamesTable.addTableColumn(gCol)
        gamesTable.dataSource = self
        gamesTable.delegate = self
        gamesScroll.documentView = gamesTable

        leftPane.addSubview(gameSearchField)
        leftPane.addSubview(gamesScroll)

        // Right pane: variants + depots
        rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false

        emptyStateView = EmptyStateView(
            symbol: "shippingbox",
            prompt: L10n.tr("builds.title"),
            hint: L10n.tr("builds.empty")
        )

        selectedGameTitle = NSTextField(labelWithString: "")
        selectedGameTitle.font = Typography.largeTitle
        selectedGameTitle.textColor = .labelColor
        selectedGameTitle.lineBreakMode = .byTruncatingTail

        variantsHeader = settingsGroupLabel("")
        variantPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        variantPopup.translatesAutoresizingMaskIntoConstraints = false
        variantPopup.target = self
        variantPopup.action = #selector(variantPopupChanged)

        applyVariantBtn = makeButton(title: "", target: self, action: #selector(applySelectedVariant))
        applyVariantBtn.bezelColor = .controlAccentColor
        savePresetBtn = makeButton(title: "", target: self, action: #selector(saveAsPresetTapped))
        editLuaBtn = makeButton(title: "", target: self, action: #selector(editLuaTapped))
        renameVariantBtn = makeButton(title: "", target: self, action: #selector(renameVariantTapped))
        deleteVariantBtn = makeButton(title: "", target: self, action: #selector(deleteVariantTapped))

        let variantBar = NSStackView(views: [variantPopup, applyVariantBtn, savePresetBtn, editLuaBtn, renameVariantBtn, deleteVariantBtn])
        variantBar.orientation = .horizontal
        variantBar.spacing = 8
        variantBar.translatesAutoresizingMaskIntoConstraints = false

        depotsHeader = settingsGroupLabel("")
        depotSearchField = NSSearchField()
        depotSearchField.translatesAutoresizingMaskIntoConstraints = false
        depotSearchField.target = self
        depotSearchField.action = #selector(depotSearchChanged)
        depotSearchField.sendsSearchStringImmediately = true

        let depotsScroll = makeScrollView()
        depotsScroll.translatesAutoresizingMaskIntoConstraints = false
        depotsScroll.applyCardSurface()

        depotsTable = NSTableView()
        depotsTable.headerView = nil
        depotsTable.rowHeight = 52
        depotsTable.style = .inset
        depotsTable.selectionHighlightStyle = .none
        depotsTable.backgroundColor = .clear
        let dCol = NSTableColumn(identifier: .init("depot"))
        dCol.resizingMask = .autoresizingMask
        depotsTable.addTableColumn(dCol)
        depotsTable.dataSource = self
        depotsTable.delegate = self
        depotsScroll.documentView = depotsTable

        detailStack = NSStackView(views: [
            selectedGameTitle,
            variantsHeader,
            variantBar,
            depotsHeader,
            depotSearchField,
            depotsScroll
        ])
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 10
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.isHidden = true

        rightContainer.addSubview(emptyStateView)
        rightContainer.addSubview(detailStack)

        depotSearchField.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        depotsScroll.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        depotsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        let M = Metrics.paneMargin
        root.addSubview(pageHeader)
        root.addSubview(leftPane)
        root.addSubview(rightContainer)

        NSLayoutConstraint.activate([
            pageHeader.topAnchor.constraint(equalTo: root.topAnchor, constant: M - 4),
            pageHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),

            leftPane.topAnchor.constraint(equalTo: pageHeader.bottomAnchor, constant: 14),
            leftPane.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),
            leftPane.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -M),
            leftPane.widthAnchor.constraint(equalToConstant: 255),

            gameSearchField.topAnchor.constraint(equalTo: leftPane.topAnchor, constant: 10),
            gameSearchField.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor, constant: 10),
            gameSearchField.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -10),

            gamesScroll.topAnchor.constraint(equalTo: gameSearchField.bottomAnchor, constant: 8),
            gamesScroll.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor, constant: 4),
            gamesScroll.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -4),
            gamesScroll.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor, constant: -6),

            rightContainer.topAnchor.constraint(equalTo: pageHeader.bottomAnchor, constant: 14),
            rightContainer.leadingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: 18),
            rightContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -M),
            rightContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -M),

            emptyStateView.centerXAnchor.constraint(equalTo: rightContainer.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: rightContainer.centerYAnchor),

            detailStack.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            detailStack.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            detailStack.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
        ])

        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(reloadGames), name: .libraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(localizeLabels), name: L10n.languageChangedNotification, object: nil)
        localizeLabels()
        reloadGames()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reloadGames()
    }

    @objc private func localizeLabels() {
        guard isViewLoaded else { return }
        gameSearchField.placeholderString = L10n.tr("builds.games.placeholder")
        variantsHeader.stringValue = L10n.tr("builds.variants.title")
        applyVariantBtn.title = L10n.tr("builds.btn.apply")
        savePresetBtn.title = L10n.tr("builds.btn.save_preset")
        editLuaBtn.title = L10n.tr("builds.btn.edit_lua")
        renameVariantBtn.title = L10n.tr("builds.btn.rename")
        deleteVariantBtn.title = L10n.tr("builds.btn.delete_variant")
        depotsHeader.stringValue = L10n.tr("builds.depots.title")
        depotSearchField.placeholderString = L10n.tr("builds.depots.search")
        depotsTable.reloadData()
    }

    func selectApp(appId: Int) {
        _ = view
        reloadGames()
        if let idx = filteredGameIds.firstIndex(of: appId) {
            gamesTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            gamesTable.scrollRowToVisible(idx)
        }
        loadActiveGame(appId)
    }

    @objc private func reloadGames() {
        guard isViewLoaded else { return }
        allGameIds = store.config.topLevelApps
        applyGameFilter()
        artLoader.load(allGameIds, artWidth: 120, onName: { [weak self] _, _ in
            self?.gamesTable.reloadData()
        }, onArt: { _, _ in })
    }

    @objc private func gameSearchChanged() {
        applyGameFilter()
    }

    private func applyGameFilter() {
        let q = gameSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            filteredGameIds = allGameIds
        } else {
            filteredGameIds = allGameIds.filter { id in
                let name = displayName(for: id)
                return name.localizedCaseInsensitiveContains(q) || "\(id)".contains(q)
            }
        }
        gamesTable.reloadData()
        if let active = activeAppId, let idx = filteredGameIds.firstIndex(of: active) {
            gamesTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    private func displayName(for appId: Int) -> String {
        if let n = artLoader.name(for: appId), !n.isEmpty { return n }
        if let n = store.config.appNames[appId], !n.isEmpty { return n }
        return "App \(appId)"
    }

    private func loadActiveGame(_ appId: Int?) {
        activeAppId = appId
        guard let appId else {
            emptyStateView.isHidden = false
            detailStack.isHidden = true
            return
        }
        emptyStateView.isHidden = true
        detailStack.isHidden = false
        selectedGameTitle.stringValue = "\(displayName(for: appId))  (\(appId))"

        // Ensure live lua exists in stplug-in (synthesizing from config.yaml if needed)
        let liveLua = LuaVault.shared.ensureLiveLua(for: appId, store: store)
        reloadVariants(for: appId, liveLua: liveLua)
    }

    private func reloadVariants(for appId: Int, liveLua: String) {
        variants = LuaVault.shared.getVariants(appId: appId)
        let activeHash = LuaVault.hashText(liveLua)

        variantPopup.removeAllItems()
        var activeIdx = 0
        for (i, v) in variants.enumerated() {
            let isLive = (v.hash == activeHash)
            let suffix = isLive ? (L10n.isFrench ? " [Actif]" : " [Active]") : ""
            variantPopup.addItem(withTitle: "\(v.displayLabel) — \(v.depotCount) depots, \(v.dlcCount) DLC\(suffix)")
            if isLive { activeIdx = i }
        }
        if !variants.isEmpty {
            variantPopup.selectItem(at: activeIdx)
        }
        updateVariantButtons(activeHash: activeHash)
        parseAndShowDepots(luaText: liveLua, appId: appId)
    }

    private func updateVariantButtons(activeHash: String) {
        let selIdx = variantPopup.indexOfSelectedItem
        guard selIdx >= 0, selIdx < variants.count else {
            applyVariantBtn.isEnabled = false
            renameVariantBtn.isEnabled = false
            deleteVariantBtn.isEnabled = false
            return
        }
        let v = variants[selIdx]
        let isLive = (v.hash == activeHash)
        applyVariantBtn.isEnabled = !isLive
        renameVariantBtn.isEnabled = true
        deleteVariantBtn.isEnabled = !isLive
    }

    @objc private func variantPopupChanged() {
        guard let appId = activeAppId else { return }
        let liveText = LuaVault.shared.ensureLiveLua(for: appId, store: store)
        updateVariantButtons(activeHash: LuaVault.hashText(liveText))
    }

    private func parseAndShowDepots(luaText: String, appId: Int) {
        let parsed = DetailedLuaParser.parse(text: luaText, fallbackAppId: appId)
        allEntries = parsed.entries
        applyDepotFilter()
    }

    @objc private func depotSearchChanged() {
        applyDepotFilter()
    }

    private func applyDepotFilter() {
        let q = depotSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            filteredEntries = allEntries
        } else {
            filteredEntries = allEntries.filter { e in
                "\(e.id)".contains(q) ||
                (e.comment?.localizedCaseInsensitiveContains(q) == true) ||
                (e.manifestId?.contains(q) == true) ||
                (e.commentedManifestId?.contains(q) == true)
            }
        }
        depotsTable.reloadData()
    }

    // MARK: - Variant Actions

    @objc private func applySelectedVariant() {
        guard let appId = activeAppId else { return }
        let idx = variantPopup.indexOfSelectedItem
        guard idx >= 0, idx < variants.count else { return }
        let variant = variants[idx]
        if LuaVault.shared.applyVariant(appId: appId, variant: variant, store: store) {
            loadActiveGame(appId)
        }
    }

    @objc private func saveAsPresetTapped() {
        guard let appId = activeAppId else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("builds.btn.save_preset")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Preset Name"
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.tr("common.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = LuaVault.shared.ensureLiveLua(for: appId, store: store)
        _ = LuaVault.shared.capture(appId: appId, luaText: text, kind: "preset", label: input.stringValue)
        loadActiveGame(appId)
    }

    @objc private func renameVariantTapped() {
        guard let appId = activeAppId else { return }
        let idx = variantPopup.indexOfSelectedItem
        guard idx >= 0, idx < variants.count else { return }
        let v = variants[idx]

        let alert = NSAlert()
        alert.messageText = L10n.tr("builds.btn.rename")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = v.displayLabel
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.tr("common.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LuaVault.shared.renameVariant(appId: appId, hash: v.hash, newLabel: input.stringValue)
        loadActiveGame(appId)
    }

    @objc private func deleteVariantTapped() {
        guard let appId = activeAppId else { return }
        let idx = variantPopup.indexOfSelectedItem
        guard idx >= 0, idx < variants.count else { return }
        let v = variants[idx]
        if LuaVault.shared.deleteVariant(appId: appId, hash: v.hash) {
            loadActiveGame(appId)
        }
    }

    @objc private func editLuaTapped() {
        guard let appId = activeAppId else { return }
        let currentLua = LuaVault.shared.ensureLiveLua(for: appId, store: store)

        let alert = NSAlert()
        alert.messageText = "\(displayName(for: appId)) — \(appId).lua"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = true
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.string = currentLua
        scroll.documentView = tv
        alert.accessoryView = scroll
        alert.addButton(withTitle: L10n.tr("common.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let edited = tv.string
        LuaVault.shared.writeLiveAndSyncConfig(appId: appId, luaText: edited, store: store)
        LuaVault.shared.syncDefaultFromLive(appId: appId)
        loadActiveGame(appId)
    }

    // MARK: - Per-depot Toggles & Manifest Download

    private func toggleDepotEnabled(depotId: Int, enabled: Bool) {
        guard let appId = activeAppId else { return }
        let current = LuaVault.shared.ensureLiveLua(for: appId, store: store)
        let updated = LuaEditor.setDepotEnabled(lua: current, depotId: depotId, enabled: enabled)
        LuaVault.shared.writeLiveAndSyncConfig(appId: appId, luaText: updated, store: store)
        LuaVault.shared.syncDefaultFromLive(appId: appId)
        loadActiveGame(appId)
    }

    private func toggleDepotPinned(depotId: Int, pinned: Bool) {
        guard let appId = activeAppId else { return }
        let current = LuaVault.shared.ensureLiveLua(for: appId, store: store)
        let updated = LuaEditor.setDepotLocked(lua: current, depotId: depotId, locked: pinned)
        LuaVault.shared.writeLiveAndSyncConfig(appId: appId, luaText: updated, store: store)
        LuaVault.shared.syncDefaultFromLive(appId: appId)
        loadActiveGame(appId)
    }

    private func downloadDepotManifest(depotId: Int, manifestId: String) {
        guard let appId = activeAppId else { return }
        let qItem = DownloadQueueItem(
            dedupeKey: "depotmanifest:\(depotId):\(manifestId)",
            appId: appId,
            title: "Depot \(depotId)",
            subtitle: "Manifest \(manifestId)",
            work: { item in
                let fileURL = try await LuaToolsAPI.shared.downloadDepotManifest(
                    depotId: depotId,
                    manifestId: manifestId,
                    onProgress: { read, total in
                        DownloadQueue.shared.updateProgress(for: item, bytesRead: read, totalBytes: total)
                    }
                )
                defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
                DownloadQueue.shared.setInstalling(item)
                _ = try ZipImporter.copyManifests([fileURL])
                return "\(depotId)_\(manifestId).manifest"
            }
        )
        DownloadQueue.shared.enqueue(qItem)
    }
}

extension BuildsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === gamesTable { return filteredGameIds.count }
        return filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === gamesTable {
            guard row < filteredGameIds.count else { return nil }
            let id = filteredGameIds[row]
            let cell = NSTableCellView()
            let title = NSTextField(labelWithString: displayName(for: id))
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.lineBreakMode = .byTruncatingTail
            title.translatesAutoresizingMaskIntoConstraints = false

            let thumb = SteamArtThumbView(cornerRadius: 5, fallbackSymbolSize: 14)
            thumb.load(appId: id)

            let sub = NSTextField(labelWithString: "App \(id)")
            sub.font = Typography.caption
            sub.textColor = .secondaryLabelColor
            sub.translatesAutoresizingMaskIntoConstraints = false

            let textStack = NSStackView(views: [title, sub])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 1
            textStack.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(thumb)
            cell.addSubview(textStack)
            NSLayoutConstraint.activate([
                thumb.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                thumb.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 72),
                thumb.heightAnchor.constraint(equalToConstant: 34),

                textStack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
                textStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        guard row < filteredEntries.count else { return nil }
        let entry = filteredEntries[row]
        let cell = NSTableCellView()

        let kindBadge = entry.isBaseApp ? "BASE" : (entry.isDlc ? "DLC" : "DEPOT")
        let kindTint: NSColor = entry.isBaseApp ? .controlAccentColor : (entry.isDlc ? .systemPurple : .secondaryLabelColor)
        let pill = PillBadge(text: kindBadge, tint: kindTint)
        let nameText = entry.comment ?? store.config.appNames[entry.id] ?? "\(kindBadge) \(entry.id)"
        let titleLabel = NSTextField(labelWithString: "\(nameText)  (#\(entry.id))")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let titleRow = NSStackView(views: [pill, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let gid = entry.manifestId ?? entry.commentedManifestId
        let metaText: String
        if let gid {
            let pinState = (entry.manifestId != nil) ? "Pinned" : "Auto-Update"
            metaText = "Manifest GID: \(gid) (\(pinState))"
        } else if let key = entry.key {
            metaText = "Key: \(key.prefix(12))…"
        } else {
            metaText = "App / DLC Unlock"
        }
        let metaLabel = NSTextField(labelWithString: metaText)
        metaLabel.font = Typography.caption
        metaLabel.textColor = .secondaryLabelColor

        let leftStack = NSStackView(views: [titleRow, metaLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        var rightViews: [NSView] = []
        if let gid {
            let dlBtn = DepotActionButton(title: L10n.tr("builds.depot.download_manifest")) { [weak self] in
                self?.downloadDepotManifest(depotId: entry.id, manifestId: gid)
            }
            dlBtn.controlSize = .small
            rightViews.append(dlBtn)
        }

        if entry.canLock {
            let pinCheck = DepotActionCheckbox(title: L10n.tr("builds.depot.pinned"), isOn: entry.isLocked) { [weak self] on in
                self?.toggleDepotPinned(depotId: entry.id, pinned: on)
            }
            rightViews.append(pinCheck)
        }

        if !entry.isBaseApp {
            let enableCheck = DepotActionCheckbox(title: L10n.tr("builds.depot.enabled"), isOn: entry.isEnabled) { [weak self] on in
                self?.toggleDepotEnabled(depotId: entry.id, enabled: on)
            }
            rightViews.append(enableCheck)
        }

        let rightStack = NSStackView(views: rightViews)
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 10
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(leftStack)
        cell.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -10),

            rightStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === gamesTable else { return }
        let row = gamesTable.selectedRow
        guard row >= 0, row < filteredGameIds.count else {
            loadActiveGame(nil)
            return
        }
        loadActiveGame(filteredGameIds[row])
    }
}

private final class DepotActionCheckbox: NSButton {
    private let onToggle: (Bool) -> Void

    init(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        self.state = isOn ? .on : .off
        self.controlSize = .small
        self.font = Typography.caption
        self.target = self
        self.action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() {
        onToggle(state == .on)
    }
}

private final class DepotActionButton: NSButton {
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

    @objc private func clicked() {
        onTap()
    }
}
