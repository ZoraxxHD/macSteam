// The source-list sidebar. Its selection drives the detail pane.

import AppKit

final class SidebarViewController: NSViewController {
    private let onSelect: (MainViewController.Item) -> Void
    private var outline: NSOutlineView!

    private var leafRowHeight: CGFloat {
        max(28, ceil(Typography.body.ascender - Typography.body.descender) + 12)
    }
    private var groupRowHeight: CGFloat {
        max(22, ceil(Typography.columnHeader.ascender - Typography.columnHeader.descender) + 8)
    }

    private enum Row {
        case group(String)
        case leaf(title: String, symbol: String, item: MainViewController.Item)
    }

    private var rows: [Row] {
        [
            .group(L10n.tr("sidebar.group.discover")),
            .leaf(title: L10n.tr("sidebar.home"), symbol: "house", item: .home),
            .leaf(title: L10n.tr("sidebar.search"), symbol: "magnifyingglass", item: .search),

            .group(L10n.tr("sidebar.group.library")),
            .leaf(title: L10n.tr("sidebar.apps"), symbol: ConfigViewController.Section.apps.symbol, item: .config(.apps)),
            .leaf(title: L10n.tr("sidebar.builds"), symbol: "shippingbox", item: .builds),
            .leaf(title: L10n.tr("sidebar.fixes"), symbol: "wrench.adjustable", item: .fixes),
            .leaf(title: L10n.tr("sidebar.downloads"), symbol: "arrow.down.circle", item: .downloads),

            .group(L10n.tr("sidebar.group.macsteam")),
            .leaf(title: L10n.tr("sidebar.plugin"), symbol: "puzzlepiece.extension", item: .plugin),
            .leaf(title: L10n.tr("sidebar.install"), symbol: "shield.lefthalf.filled", item: .install),
            .leaf(title: L10n.tr("sidebar.crossover"), symbol: "play.desktopcomputer", item: .crossover),
            .leaf(title: L10n.tr("sidebar.cloud_redirect"), symbol: "icloud.and.arrow.up", item: .cloudRedirect),
            .leaf(title: L10n.tr("sidebar.repair"), symbol: "wrench.and.screwdriver", item: .repair),
            .leaf(title: L10n.tr("sidebar.settings"), symbol: ConfigViewController.Section.settings.symbol, item: .config(.settings)),
        ]
    }

    init(onSelect: @escaping (MainViewController.Item) -> Void) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let scroll = makeScrollView()

        outline = NSOutlineView()
        outline.headerView = nil
        outline.rowSizeStyle = .medium
        outline.floatsGroupRows = false
        outline.style = .sourceList
        outline.backgroundColor = .clear

        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        outline.dataSource = self
        outline.delegate = self
        scroll.documentView = outline

        view = scroll
        outline.reloadData()

        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: L10n.languageChangedNotification, object: nil)
    }

    @objc private func languageDidChange() {
        let selRow = outline.selectedRow
        outline.reloadData()
        if selRow >= 0 && selRow < outline.numberOfRows {
            outline.selectRowIndexes(IndexSet(integer: selRow), byExtendingSelection: false)
        }
        recolorLeafGlyphs()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let nc = NotificationCenter.default
        if let win = view.window {
            nc.addObserver(self, selector: #selector(windowActivityChanged),
                           name: NSWindow.didBecomeKeyNotification, object: win)
            nc.addObserver(self, selector: #selector(windowActivityChanged),
                           name: NSWindow.didResignKeyNotification, object: win)
        }
        recolorLeafGlyphs()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    }

    @objc private func windowActivityChanged() { recolorLeafGlyphs() }

    private func recolorLeafGlyphs() {
        let active = view.window?.isKeyWindow ?? false
        let tint: NSColor = active ? .controlAccentColor : .secondaryLabelColor
        for r in 0..<outline.numberOfRows {
            guard let cell = outline.view(atColumn: 0, row: r, makeIfNecessary: false) as? NSTableCellView else { continue }
            cell.imageView?.contentTintColor = tint
        }
    }

    func selectDefault() {
        select(.home)
    }

    func select(_ item: MainViewController.Item) {
        let currentRows = rows
        for (i, row) in currentRows.enumerated() {
            if case .leaf(_, _, let it) = row, it == item {
                let outlineRow = outline.row(forItem: i)
                guard outlineRow >= 0 else { return }
                outline.selectRowIndexes(IndexSet(integer: outlineRow), byExtendingSelection: false)
                outline.scrollRowToVisible(outlineRow)
                return
            }
        }
    }
}

// MARK: - Source list data source / delegate

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? rows.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        index
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        let currentRows = rows
        guard let i = item as? Int, i < currentRows.count, case .group = currentRows[i] else { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        let currentRows = rows
        guard let i = item as? Int, i < currentRows.count else { return false }
        if case .group = currentRows[i] { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let currentRows = rows
        guard let i = item as? Int, i < currentRows.count else { return nil }
        switch currentRows[i] {
        case .group(let title):
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: title)
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),
            ])
            return cell

        case .leaf(let title, let symbol, _):
            let cell = NSTableCellView()
            let img = NSImageView()
            img.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            img.contentTintColor = (view.window?.isKeyWindow ?? true)
                ? .controlAccentColor : .secondaryLabelColor
            img.symbolConfiguration = .init(textStyle: .body)
            img.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: title)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(img)
            cell.addSubview(label)
            cell.imageView = img
            cell.textField = label
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        let currentRows = rows
        guard let i = item as? Int, i < currentRows.count, case .group = currentRows[i] else {
            return leafRowHeight
        }
        return groupRowHeight
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let currentRows = rows
        let sel = outline.selectedRow
        guard sel >= 0, let i = outline.item(atRow: sel) as? Int, i < currentRows.count else { return }
        if case .leaf(_, _, let item) = currentRows[i] {
            onSelect(item)
        }
    }
}
