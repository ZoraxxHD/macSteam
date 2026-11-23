// Apps-pane game list with LuaTools search, filters, sorting, and detail inspector flyout.
import AppKit

@MainActor
final class AppNode: NSObject {
    let appID: Int
    var dlc: [DLCNode]
    init(appID: Int, dlc: [DLCNode] = []) { self.appID = appID; self.dlc = dlc }
}

@MainActor
final class DLCNode: NSObject {
    let appID: Int
    init(appID: Int) { self.appID = appID }
}

@MainActor
final class AppCardListView: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let listView: NSView

    private let outline = DeletingOutlineView()
    private let store: ConfigStore

    private var appIDs: [Int] { store.config.apps }
    private var nodes: [AppNode] = []

    private let art = StoreArtLoader()
    private var emptyState: EmptyStateView!

    private var searchField: NSSearchField!
    private var typePopup: NSPopUpButton!
    private var pricePopup: NSPopUpButton!
    private var sortPopup: NSPopUpButton!

    // Inspector UI on the right
    private var inspectorCard: NSView!
    private var inspectorEmptyLabel: NSTextField!
    private var inspectorContentStack: NSStackView!
    private var inspectorArt: NSImageView!
    private var inspectorTitle: NSTextField!
    private var inspectorSub: NSTextField!
    private var inspectorDesc: NSTextField!
    private var inspectorMeta: NSTextField!
    private var inspectedAppID: Int?

    var performRemoval: ((_ ids: [Int]) -> Bool)?
    var confirmRemoval: ((_ removed: [Int]) -> Bool)?
    var onUpdateGame: ((_ appID: Int) -> Void)?
    var onManageBuilds: ((_ appID: Int) -> Void)?

    private static let minRowHeight: CGFloat = 48
    private static let maxRowHeight: CGFloat = 160
    private static let defaultRowHeight: CGFloat = 84
    private static let snapDistance: CGFloat = 3
    private static let artInset: CGFloat = 8
    private static let artAspect: CGFloat = 460.0 / 215.0
    static let rowHeightDefaultsKey = "AppsRowHeight"
    static let rowHeightChanged = Notification.Name("AppsRowHeightChanged")

    private var rowHeight: CGFloat = AppCardListView.defaultRowHeight
    private var artHeight: CGFloat { rowHeight - 2 * Self.artInset }
    private var artWidth: CGFloat { (artHeight * Self.artAspect).rounded() }
    private static var decodeWidth: CGFloat {
        ((maxRowHeight - 2 * artInset) * artAspect * 2).rounded()
    }

    private static let cellID = NSUserInterfaceItemIdentifier("AppRowCell")
    private let sizeSlider = ResettableSlider()

    deinit { NotificationCenter.default.removeObserver(self) }

    init(store: ConfigStore) {
        self.store = store
        self.rowHeight = Self.loadRowHeight()

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        self.listView = root
        super.init()

        // Top Filter & Sort Bar
        searchField = NSSearchField()
        searchField.placeholderString = L10n.tr("library.search.placeholder")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(filterOrSortChanged)
        searchField.sendsSearchStringImmediately = true

        typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        typePopup.addItems(withTitles: [
            L10n.tr("library.filter.all_types"),
            L10n.tr("library.filter.games"),
            L10n.tr("library.filter.dlc")
        ])
        typePopup.target = self
        typePopup.action = #selector(filterOrSortChanged)

        pricePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        pricePopup.addItems(withTitles: [
            L10n.tr("library.filter.all_prices"),
            L10n.tr("library.filter.free"),
            L10n.tr("library.filter.paid")
        ])
        pricePopup.target = self
        pricePopup.action = #selector(filterOrSortChanged)

        sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sortPopup.addItems(withTitles: [
            L10n.tr("library.sort.recent"),
            L10n.tr("library.sort.name"),
            L10n.tr("library.sort.metacritic")
        ])
        sortPopup.target = self
        sortPopup.action = #selector(filterOrSortChanged)

        let filterBar = NSStackView(views: [searchField, typePopup, pricePopup, sortPopup])
        filterBar.orientation = .horizontal
        filterBar.alignment = .centerY
        filterBar.spacing = 8
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        outline.headerView = nil
        outline.rowHeight = rowHeight
        outline.rowSizeStyle = .custom
        outline.style = .inset
        outline.selectionHighlightStyle = .regular
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.usesAutomaticRowHeights = false
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 6
        outline.autoresizesOutlineColumn = false
        let col = NSTableColumn(identifier: .init("app"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = outline

        emptyState = EmptyStateView(symbol: "square.stack.3d.up",
                                    prompt: L10n.isFrench ? "Aucun jeu" : "No games yet",
                                    hint: L10n.isFrench ? "Recherchez ou importez un jeu pour l'ajouter." : "Search or import a game to add it.")
        emptyState.isHidden = !store.config.apps.isEmpty

        let sizeBar = makeSizeSliderBar(
            slider: sizeSlider,
            min: Self.minRowHeight, max: Self.maxRowHeight,
            defaultValue: Self.defaultRowHeight,
            currentValue: rowHeight,
            accessibilityLabel: "Game row size",
            smallGlyphSize: 12, largeGlyphSize: 18)

        let footerDivider = NSBox()
        footerDivider.boxType = .separator
        footerDivider.translatesAutoresizingMaskIntoConstraints = false

        inspectorCard = buildInspectorCard()

        root.addSubview(filterBar)
        root.addSubview(scroll)
        root.addSubview(inspectorCard)
        root.addSubview(footerDivider)
        root.addSubview(sizeBar)
        root.addSubview(emptyState)

        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: root.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: inspectorCard.leadingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -6),

            inspectorCard.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 10),
            inspectorCard.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            inspectorCard.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -6),
            inspectorCard.widthAnchor.constraint(equalToConstant: 250),

            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: sizeBar.topAnchor, constant: -8),

            sizeBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sizeBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            sizeBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeSliderChanged)

        NotificationCenter.default.addObserver(
            self, selector: #selector(externalRowHeightChanged),
            name: Self.rowHeightChanged, object: nil)

        outline.dataSource = self
        outline.delegate = self
        outline.doubleAction = nil
        outline.onDeleteKey = { [weak self] in self?.removeSelected() }
        outline.menu = makeContextMenu()

        reloadTree()
        resolveAll()
    }

    private func buildInspectorCard() -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        inspectorEmptyLabel = NSTextField(wrappingLabelWithString: L10n.tr("library.inspector.empty"))
        inspectorEmptyLabel.font = Typography.caption
        inspectorEmptyLabel.textColor = .tertiaryLabelColor
        inspectorEmptyLabel.alignment = .center
        inspectorEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        inspectorArt = NSImageView()
        inspectorArt.imageScaling = .scaleProportionallyUpOrDown
        inspectorArt.wantsLayer = true
        inspectorArt.layer?.cornerRadius = 6
        inspectorArt.layer?.masksToBounds = true
        inspectorArt.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        inspectorArt.translatesAutoresizingMaskIntoConstraints = false

        inspectorTitle = NSTextField(wrappingLabelWithString: "")
        inspectorTitle.font = .systemFont(ofSize: 15, weight: .bold)
        inspectorTitle.textColor = .labelColor

        inspectorSub = NSTextField(labelWithString: "")
        inspectorSub.font = Typography.caption
        inspectorSub.textColor = .controlAccentColor

        inspectorMeta = NSTextField(wrappingLabelWithString: "")
        inspectorMeta.font = Typography.caption
        inspectorMeta.textColor = .secondaryLabelColor

        inspectorDesc = NSTextField(wrappingLabelWithString: "")
        inspectorDesc.font = Typography.caption
        inspectorDesc.textColor = .secondaryLabelColor
        inspectorDesc.maximumNumberOfLines = 4

        let updateBtn = makeButton(title: L10n.tr("library.inspector.update"), target: self, action: #selector(inspectorUpdateTapped))
        let depotsBtn = makeButton(title: L10n.tr("library.inspector.depots"), target: self, action: #selector(inspectorDepotsTapped))
        let launchBtn = makeButton(title: L10n.tr("library.inspector.launch_options"), target: self, action: #selector(inspectorLaunchOptionsTapped))
        let steamBtn = makeButton(title: L10n.tr("library.inspector.open_steam"), target: self, action: #selector(inspectorOpenSteamTapped))
        let storeBtn = makeButton(title: L10n.tr("library.inspector.store_page"), target: self, action: #selector(inspectorStorePageTapped))
        let finderBtn = makeButton(title: L10n.tr("library.inspector.reveal_finder"), target: self, action: #selector(inspectorRevealFinderTapped))
        let removeBtn = makeButton(title: L10n.tr("library.inspector.remove"), target: self, action: #selector(removeMenuItem))

        inspectorContentStack = NSStackView(views: [
            inspectorArt,
            inspectorTitle,
            inspectorSub,
            inspectorMeta,
            inspectorDesc,
            updateBtn,
            depotsBtn,
            launchBtn,
            steamBtn,
            storeBtn,
            finderBtn,
            removeBtn
        ])
        inspectorContentStack.orientation = .vertical
        inspectorContentStack.alignment = .leading
        inspectorContentStack.spacing = 6
        inspectorContentStack.translatesAutoresizingMaskIntoConstraints = false
        inspectorContentStack.isHidden = true

        NSLayoutConstraint.activate([
            inspectorArt.widthAnchor.constraint(equalToConstant: 222),
            inspectorArt.heightAnchor.constraint(equalToConstant: 104),
        ])
        for b in [updateBtn, depotsBtn, launchBtn, steamBtn, storeBtn, finderBtn, removeBtn] {
            b.widthAnchor.constraint(equalTo: inspectorContentStack.widthAnchor).isActive = true
        }

        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        doc.addSubview(inspectorContentStack)

        card.addSubview(scroll)
        card.addSubview(inspectorEmptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            inspectorContentStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 12),
            inspectorContentStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 12),
            inspectorContentStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -12),
            inspectorContentStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),

            inspectorEmptyLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            inspectorEmptyLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            inspectorEmptyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inspectorEmptyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    // MARK: - Inspector Selection & Actions

    func selectApp(appID: Int) {
        for r in 0..<outline.numberOfRows {
            if rowAppID(r) == appID {
                outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
                outline.scrollRowToVisible(r)
                updateInspector(for: appID)
                return
            }
        }
    }

    private func updateInspector(for appID: Int?) {
        inspectedAppID = appID
        guard let appID else {
            inspectorEmptyLabel.isHidden = false
            inspectorContentStack.isHidden = true
            return
        }
        inspectorEmptyLabel.isHidden = true
        inspectorContentStack.isHidden = false

        inspectorTitle.stringValue = displayName(for: appID)
        let dlcCount = self.dlcCount(for: appID)
        inspectorSub.stringValue = "AppID \(appID)" + (dlcCount > 0 ? "  ·  \(dlcCount) DLC" : "")
        inspectorArt.image = art.image(for: appID)
        inspectorMeta.stringValue = ""
        inspectorDesc.stringValue = ""

        Task {
            if let ov = await LuaToolsAPI.shared.getOverview(appId: appID) {
                await MainActor.run {
                    guard self.inspectedAppID == appID else { return }
                    var metaParts: [String] = []
                    if !ov.developerLabel.isEmpty { metaParts.append(ov.developerLabel) }
                    if let rel = ov.releaseDateText, !rel.isEmpty { metaParts.append(rel) }
                    if let mc = ov.metacritic { metaParts.append("Metacritic \(mc)") }
                    if !ov.genres.isEmpty { metaParts.append(ov.genres.joined(separator: ", ")) }
                    self.inspectorMeta.stringValue = metaParts.joined(separator: " · ")
                    self.inspectorDesc.stringValue = ov.shortDescription ?? ""
                }
            }
        }
    }

    @objc private func inspectorUpdateTapped() {
        if let id = inspectedAppID { onUpdateGame?(id) }
    }

    @objc private func inspectorDepotsTapped() {
        if let id = inspectedAppID { onManageBuilds?(id) }
    }

    @objc private func inspectorLaunchOptionsTapped() {
        guard let id = inspectedAppID else { return }
        let current = SteamLibraryService.readLaunchOptions(appId: id)
        let alert = NSAlert()
        alert.messageText = L10n.tr("library.launch_options.title", displayName(for: id))
        alert.informativeText = L10n.tr("library.launch_options.info")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = current
        input.placeholderString = "-windowed"
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.tr("library.launch_options.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            _ = SteamLibraryService.writeLaunchOptions(appId: id, options: input.stringValue)
        }
    }

    @objc private func inspectorOpenSteamTapped() {
        if let id = inspectedAppID {
            SteamLibraryService.openSteamURL("steam://nav/games/details/\(id)")
        }
    }

    @objc private func inspectorStorePageTapped() {
        if let id = inspectedAppID {
            SteamLibraryService.openSteamURL("steam://store/\(id)")
        }
    }

    @objc private func inspectorRevealFinderTapped() {
        guard let id = inspectedAppID else { return }
        if let installDir = SteamLibraryService.getInstallDir(appId: id) {
            SteamLibraryService.revealInFinder(installDir)
        } else {
            let luaFile = LuaVault.shared.livePath(id)
            if FileManager.default.fileExists(atPath: luaFile.path) {
                SteamLibraryService.revealInFinder(luaFile)
            } else {
                SteamLibraryService.revealInFinder(Paths.configFile)
            }
        }
    }

    // MARK: - Filter & Sort

    @objc private func filterOrSortChanged() {
        reloadTree()
    }

    // MARK: - row size

    @objc private func sizeSliderChanged() {
        let h = sizeSlider.snappedValue(min: Self.minRowHeight, max: Self.maxRowHeight,
                                        snapDistance: Self.snapDistance)
        guard h != rowHeight else { return }
        rowHeight = h
        applyRowHeight()
    }

    @objc private func externalRowHeightChanged() {
        let h = Self.loadRowHeight()
        guard h != rowHeight else { return }
        rowHeight = h
        sizeSlider.doubleValue = Double(h)
        outline.rowHeight = h
        let expanded = expandedAppIDs()
        outline.reloadData()
        for node in nodes where expanded.contains(node.appID) { outline.expandItem(node) }
    }

    private func applyRowHeight() {
        outline.rowHeight = rowHeight
        let expanded = expandedAppIDs()
        outline.reloadData()
        for node in nodes where expanded.contains(node.appID) { outline.expandItem(node) }
        UserDefaults.standard.set(Double(rowHeight), forKey: Self.rowHeightDefaultsKey)
    }

    private static func loadRowHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: rowHeightDefaultsKey)
        guard stored > 0 else { return defaultRowHeight }
        return min(max(CGFloat(stored), minRowHeight), maxRowHeight)
    }

    private func updateEmptyState() { emptyState.isHidden = !nodes.isEmpty }

    private func reloadTree() {
        let expanded = expandedAppIDs()
        rebuildTree()
        outline.reloadData()
        for node in nodes where expanded.contains(node.appID) {
            outline.expandItem(node)
        }
        updateEmptyState()
    }

    private func expandedAppIDs() -> Set<Int> {
        var ids = Set<Int>()
        for node in nodes where outline.isItemExpanded(node) { ids.insert(node.appID) }
        return ids
    }

    func refresh() {
        reloadTree()
        resolveAll()
    }

    private func rebuildTree() {
        let q = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typeIdx = typePopup?.indexOfSelectedItem ?? 0 // 0=All, 1=Games, 2=DLC
        let priceIdx = pricePopup?.indexOfSelectedItem ?? 0 // 0=All, 1=Free, 2=Paid
        let sortIdx = sortPopup?.indexOfSelectedItem ?? 0 // 0=Recent, 1=Name, 2=Metacritic

        var nodeByID: [Int: AppNode] = [:]
        var order: [AppNode] = []

        func matchesFilter(_ id: Int, isDLC: Bool) -> Bool {
            if typeIdx == 1 && isDLC { return false }
            if typeIdx == 2 && !isDLC { return false }
            if priceIdx > 0, let fd = LuaToolsAPI.shared.getFilterData(appId: id) {
                if priceIdx == 1 && !fd.isFree { return false }
                if priceIdx == 2 && fd.isFree { return false }
            }
            if !q.isEmpty {
                let name = displayName(for: id)
                if !name.localizedCaseInsensitiveContains(q) && !"\(id)".contains(q) {
                    return false
                }
            }
            return true
        }

        if typeIdx == 2 {
            // Flat DLC list when filtering by DLC only
            for id in appIDs where isNestableDLC(id) && matchesFilter(id, isDLC: true) {
                let node = AppNode(appID: id)
                nodeByID[id] = node
                order.append(node)
            }
        } else {
            for id in appIDs where !isNestableDLC(id) && matchesFilter(id, isDLC: false) {
                let node = AppNode(appID: id)
                nodeByID[id] = node
                order.append(node)
            }
            if typeIdx == 0 {
                for id in appIDs where isNestableDLC(id) {
                    let parent = store.config.appParents[id]
                    if let parent, let node = nodeByID[parent] {
                        node.dlc.append(DLCNode(appID: id))
                    } else if matchesFilter(id, isDLC: true) {
                        let node = AppNode(appID: id)
                        nodeByID[id] = node
                        order.append(node)
                    }
                }
            }
        }

        if sortIdx == 1 {
            order.sort { displayName(for: $0.appID).localizedCaseInsensitiveCompare(displayName(for: $1.appID)) == .orderedAscending }
        } else if sortIdx == 2 {
            order.sort {
                let m0 = LuaToolsAPI.shared.getFilterData(appId: $0.appID)?.metacritic ?? -1
                let m1 = LuaToolsAPI.shared.getFilterData(appId: $1.appID)?.metacritic ?? -1
                return m0 > m1
            }
        } else {
            // Recently added (reverse of config order)
            order.reverse()
        }

        nodes = order
    }

    private func isNestableDLC(_ id: Int) -> Bool {
        guard let parent = store.config.appParents[id] else { return false }
        return appIDs.contains(parent)
    }

    private func resolveAll() {
        art.load(appIDs, artWidth: Self.decodeWidth,
                 onName: { [weak self] id, _ in
                     guard let self else { return }
                     self.applyToRows(appID: id) { $0.setName(self.displayName(for: id)) }
                     if self.inspectedAppID == id {
                         self.inspectorTitle.stringValue = self.displayName(for: id)
                     }
                 },
                 onArt: { [weak self] id, image in
                     self?.applyToRows(appID: id) { $0.setArt(image) }
                     if self?.inspectedAppID == id {
                         self?.inspectorArt.image = image
                     }
                 })
    }

    private func applyToRows(appID: Int, _ apply: (AppRowCell) -> Void) {
        for row in 0..<outline.numberOfRows {
            guard rowAppID(row) == appID,
                  let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppRowCell
            else { continue }
            apply(cell)
        }
    }

    private func rowAppID(_ row: Int) -> Int? {
        switch outline.item(atRow: row) {
        case let n as AppNode: return n.appID
        case let d as DLCNode: return d.appID
        default: return nil
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    private func removeSelected() {
        let rows = targetRows()
        guard !rows.isEmpty else { NSSound.beep(); return }

        var removed = Set<Int>()
        for row in rows {
            switch outline.item(atRow: row) {
            case let node as AppNode:
                removed.insert(node.appID)
                for child in node.dlc { removed.insert(child.appID) }
            case let child as DLCNode:
                removed.insert(child.appID)
            default:
                break
            }
        }
        guard !removed.isEmpty else { NSSound.beep(); return }

        let removedList = appIDs.filter { removed.contains($0) }
        if let gate = confirmRemoval, !gate(removedList) { return }

        guard performRemoval?(removedList) ?? false else { return }
        if let inspected = inspectedAppID, removed.contains(inspected) {
            updateInspector(for: nil)
        }
        reloadTree()
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    private func targetRows() -> [Int] {
        let clicked = outline.clickedRow
        let selected = outline.selectedRowIndexes
        if clicked >= 0 && !selected.contains(clicked) { return [clicked] }
        return selected.sorted()
    }

    @objc private func removeMenuItem() { removeSelected() }

    func displayName(for appID: Int) -> String {
        if let n = art.name(for: appID) { return n }
        if let n = store.config.appNames[appID], !n.isEmpty { return n }
        return "App \(appID)"
    }

    func dlcCount(for appID: Int) -> Int {
        nodes.first { $0.appID == appID }?.dlc.count ?? 0
    }

    // MARK: - NSOutlineView data source & delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return nodes.count }
        if let node = item as? AppNode { return node.dlc.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return nodes[index] }
        let node = item as! AppNode
        return node.dlc[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? AppNode { return !node.dlc.isEmpty }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let artSize = NSSize(width: artWidth, height: artHeight)
        let cell = (outlineView.makeView(withIdentifier: Self.cellID, owner: self) as? AppRowCell)
            ?? AppRowCell(identifier: Self.cellID, artSize: artSize)
        cell.setArtSize(artSize)

        if let node = item as? AppNode {
            cell.configure(name: displayName(for: node.appID), appID: node.appID,
                           art: art.image(for: node.appID), isDLC: false)
        } else if let child = item as? DLCNode {
            cell.configure(name: displayName(for: child.appID), appID: child.appID,
                           art: art.image(for: child.appID), isDLC: true)
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outline.selectedRow
        guard row >= 0, let id = rowAppID(row) else {
            updateInspector(for: nil)
            return
        }
        updateInspector(for: id)
    }
}

extension AppCardListView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rows = targetRows()
        guard !rows.isEmpty else { return }

        let title = removeMenuTitle(for: rows)
        let item = NSMenuItem(title: title, action: #selector(removeMenuItem), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func removeMenuTitle(for rows: [Int]) -> String {
        if rows.count == 1, case let node as AppNode = outline.item(atRow: rows[0]) {
            let n = node.dlc.count
            if n > 0 { return "Remove \(displayName(for: node.appID)) and \(n) DLC" }
            return "Remove \(displayName(for: node.appID))"
        }
        if rows.count == 1, case let child as DLCNode = outline.item(atRow: rows[0]) {
            return "Remove \(displayName(for: child.appID))"
        }
        return "Remove \(rows.count) Items"
    }
}

@MainActor
final class DeletingOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if deleteKeyCodes.contains(event.keyCode) { onDeleteKey?(); return }
        super.keyDown(with: event)
    }

    @objc func removeApps(_ sender: Any?) {
        onDeleteKey?()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(removeApps(_:)) {
            return selectedRow >= 0
        }
        return true
    }
}

@MainActor
final class AppRowCell: NSTableCellView {
    private let art = NSImageView()
    private let placeholder = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    private var artWidthConstraint: NSLayoutConstraint!
    private var artHeightConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier, artSize: NSSize) {
        super.init(frame: .zero)
        self.identifier = identifier
        build(artSize: artSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(artSize: NSSize) {
        art.imageScaling = .scaleProportionallyUpOrDown
        art.wantsLayer = true
        art.layer?.cornerRadius = 6
        art.layer?.masksToBounds = true
        art.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        art.translatesAutoresizingMaskIntoConstraints = false

        placeholder.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        placeholder.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        placeholder.contentTintColor = Colors.quiet
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(art)
        addSubview(placeholder)
        addSubview(nameLabel)

        artWidthConstraint = art.widthAnchor.constraint(equalToConstant: artSize.width)
        artHeightConstraint = art.heightAnchor.constraint(equalToConstant: artSize.height)

        NSLayoutConstraint.activate([
            art.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            art.centerYAnchor.constraint(equalTo: centerYAnchor),
            artWidthConstraint,
            artHeightConstraint,

            placeholder.centerXAnchor.constraint(equalTo: art.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: art.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    func setArtSize(_ size: NSSize) {
        guard artWidthConstraint.constant != size.width
            || artHeightConstraint.constant != size.height else { return }
        artWidthConstraint.constant = size.width
        artHeightConstraint.constant = size.height
    }

    func configure(name: String, appID: Int, art image: NSImage?, isDLC: Bool) {
        nameLabel.stringValue = name.isEmpty ? "App \(appID)" : name
        nameLabel.font = .systemFont(ofSize: 14, weight: isDLC ? .regular : .semibold)
        setArt(image)
    }

    func setName(_ name: String) {
        if !name.isEmpty { nameLabel.stringValue = name }
    }

    func setArt(_ image: NSImage?) {
        art.image = image
        placeholder.isHidden = (image != nil)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        art.image = nil
        placeholder.isHidden = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.art.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }
}
