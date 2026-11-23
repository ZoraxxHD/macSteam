// Mac-friendly editor for config.yaml + LuaTools Account, Hubcap Key, and Language settings.

import AppKit
import Combine

final class ConfigViewController: NSViewController {
    let store: ConfigStore
    var onUpdateGame: ((Int) -> Void)?
    var onManageBuilds: ((Int) -> Void)?

    private var detailContainer: NSView!
    private var currentSection: Section = .settings

    var hideWhatsNewSwitch: NSSwitch!
    private var fastFetchSwitch: NSSwitch!
    private var autoUpdateAppsSwitch: NSSwitch!
    private var donateKeysSwitch: NSSwitch!
    private var cefPluginSwitch: NSSwitch!
    private var langPopup: NSPopUpButton!

    // Account controls
    private var accountStatusLabel: NSTextField!
    private var discordSignInBtn: NSButton!
    private var codeInputField: NSTextField!
    private var redeemCodeBtn: NSButton!
    private var signOutBtn: NSButton!

    // Hubcap controls
    private var hubcapInputField: NSTextField!
    private var hubcapSaveBtn: NSButton!
    private var hubcapClearBtn: NSButton!
    private var hubcapRefreshBtn: NSButton!
    private var hubcapStatusLabel: NSTextField!

    private var checkUpdateButton: NSButton?
    private var autoUpdateSwitch: NSSwitch?
    private var updaterSub: AnyCancellable?

    private var appsCardList: AppCardListView?

    enum Section: String, CaseIterable {
        case settings = "Settings"
        case apps = "Apps"

        var symbol: String {
            switch self {
            case .settings: return "gearshape"
            case .apps:     return "square.grid.2x2"
            }
        }

        var title: String {
            switch self {
            case .settings: return L10n.tr("sidebar.settings")
            case .apps:     return L10n.tr("sidebar.apps")
            }
        }
    }

    init(store: ConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 540))
        root.translatesAutoresizingMaskIntoConstraints = false
        detailContainer = root
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(handleExternalChange), name: AuthService.authStateChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleExternalChange), name: L10n.languageChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLibraryDidChange), name: .libraryDidChange, object: nil)

        showDetail(for: currentSection)
    }

    @objc private func handleExternalChange() {
        if isViewLoaded {
            showDetail(for: currentSection)
        }
    }

    @objc private func handleLibraryDidChange() {
        guard isViewLoaded, currentSection == .apps else { return }
        if let appsCardList {
            appsCardList.refresh()
        } else {
            showDetail(for: .apps)
        }
    }

    func select(section: Section) {
        _ = view
        showDetail(for: section)
    }

    func selectAppInList(_ appID: Int) {
        select(section: .apps)
        appsCardList?.selectApp(appID: appID)
    }

    func reloadFromStore() {
        if isViewLoaded {
            showDetail(for: currentSection)
        }
    }

    private func persisting(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            NSSound.beep()
            presentAlert("Couldn’t save config", error.localizedDescription, style: .warning)
        }
    }

    private func confirmDestructive(_ message: String, informative: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.remove"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Detail routing

    private func showDetail(for section: Section) {
        currentSection = section
        appsCardList = nil

        detailContainer.subviews.forEach { $0.removeFromSuperview() }

        let content: NSView
        switch section {
        case .settings: content = buildSettingsDetail()
        case .apps:     content = buildAppsDetail()
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.addSubview(content)
        let m = (section == .apps) ? Metrics.paneMargin : 0
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: m),
            content.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: m),
            content.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -m),
            content.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -m),
        ])
    }

    private func buildSettingsDetail() -> NSView {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        // 1. General & Interface
        langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for lang in L10n.Language.allCases {
            langPopup.addItem(withTitle: lang.displayName)
        }
        if let idx = L10n.Language.allCases.firstIndex(of: L10n.currentLanguageSetting) {
            langPopup.selectItem(at: idx)
        }
        langPopup.target = self
        langPopup.action = #selector(languagePopupChanged)

        hideWhatsNewSwitch = makeToggle(isOn: store.config.hideWhatsNew, action: #selector(settingsChanged))
        fastFetchSwitch = makeToggle(isOn: AppSettings.shared.fastFetch, action: #selector(luaToolsTogglesChanged))
        autoUpdateAppsSwitch = makeToggle(isOn: AppSettings.shared.autoUpdateApps, action: #selector(luaToolsTogglesChanged))
        donateKeysSwitch = makeToggle(isOn: AppSettings.shared.donateKeys, action: #selector(luaToolsTogglesChanged))
        cefPluginSwitch = makeToggle(isOn: AppSettings.shared.cefPluginEnabled, action: #selector(luaToolsTogglesChanged))

        let generalHeader = settingsGroupLabel(L10n.tr("settings.group.general"))
        let generalCard = SettingsCard(rows: [
            SettingRow(title: L10n.tr("settings.lang.title"), control: langPopup),
            SettingRow(title: L10n.tr("settings.hide_whats_new"), control: hideWhatsNewSwitch),
            SettingRow(title: L10n.tr("settings.fast_fetch"), control: fastFetchSwitch),
            SettingRow(title: L10n.tr("settings.auto_update_apps"), control: autoUpdateAppsSwitch),
            SettingRow(title: L10n.tr("settings.donate_keys"), control: donateKeysSwitch),
            SettingRow(title: L10n.tr("settings.cef_plugin"), control: cefPluginSwitch),
        ])

        // 2. LuaTools Account
        let accountHeader = settingsGroupLabel(L10n.tr("settings.group.account"))
        let accountCard = buildAccountCard()

        // 3. Hubcap API Key
        let hubcapHeader = settingsGroupLabel(L10n.tr("settings.group.hubcap"))
        let hubcapCard = buildHubcapCard()

        // 4. Updates
        let updater = UpdaterManager.shared
        let btn = NSButton(title: L10n.tr("settings.updates.check"), target: self, action: #selector(checkForUpdatesTapped))
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.isEnabled = updater.canCheckForUpdates
        checkUpdateButton = btn

        let autoSwitch = makeToggle(isOn: updater.automaticallyChecksForUpdates, action: #selector(autoUpdateChanged))
        autoUpdateSwitch = autoSwitch

        let updatesHeader = settingsGroupLabel(L10n.tr("settings.group.updates"))
        let updatesCard = SettingsCard(rows: [
            SettingRow(title: L10n.tr("settings.updates.auto"), control: autoSwitch),
            SettingRow(title: L10n.tr("settings.updates.check"), control: btn),
        ])

        updaterSub = updater.$canCheckForUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] can in self?.checkUpdateButton?.isEnabled = can }

        let stack = NSStackView(views: [
            generalHeader, generalCard,
            accountHeader, accountCard,
            hubcapHeader, hubcapCard,
            updatesHeader, updatesCard
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(18, after: generalCard)
        stack.setCustomSpacing(18, after: accountCard)
        stack.setCustomSpacing(18, after: hubcapCard)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for c in [generalCard, accountCard, hubcapCard, updatesCard] {
            c.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        doc.addSubview(stack)
        let m = Metrics.paneMargin
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: m),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: m),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -m),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -m),
        ])

        if !(AppSettings.shared.hubcapApiKey?.isEmpty ?? true) {
            refreshHubcapQuota()
        }
        return scroll
    }

    private func buildAccountCard() -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let signedIn = AuthService.shared.isSignedIn
        let statusStr = signedIn
            ? L10n.tr("home.card.account.signedin", AuthService.shared.displayName ?? "User")
            : L10n.tr("settings.account.guest")

        accountStatusLabel = NSTextField(labelWithString: statusStr)
        accountStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        accountStatusLabel.textColor = signedIn ? .systemGreen : .secondaryLabelColor

        discordSignInBtn = makeButton(title: L10n.tr("settings.account.signin_discord"), target: self, action: #selector(signInDiscordTapped))
        codeInputField = NSTextField(frame: .zero)
        codeInputField.placeholderString = L10n.tr("settings.account.code_placeholder")
        codeInputField.translatesAutoresizingMaskIntoConstraints = false
        codeInputField.widthAnchor.constraint(equalToConstant: 110).isActive = true

        redeemCodeBtn = makeButton(title: L10n.tr("settings.account.signin_code"), target: self, action: #selector(redeemBotCodeTapped))
        signOutBtn = makeButton(title: L10n.tr("settings.account.signout"), target: self, action: #selector(signOutTapped))

        let controlsRow: NSStackView
        if signedIn {
            controlsRow = NSStackView(views: [accountStatusLabel, signOutBtn])
        } else {
            controlsRow = NSStackView(views: [discordSignInBtn, codeInputField, redeemCodeBtn])
        }
        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 10

        let vStack = NSStackView(views: signedIn ? [controlsRow] : [accountStatusLabel, controlsRow])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func buildHubcapCard() -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let hasKey = !(AppSettings.shared.hubcapApiKey?.isEmpty ?? true)
        hubcapStatusLabel = NSTextField(labelWithString: hasKey ? "Hubcap API Key ✓" : "Not configured")
        hubcapStatusLabel.font = Typography.caption
        hubcapStatusLabel.textColor = hasKey ? .systemGreen : .secondaryLabelColor

        hubcapInputField = NSSecureTextField(frame: .zero)
        hubcapInputField.placeholderString = L10n.tr("settings.hubcap.placeholder")
        hubcapInputField.translatesAutoresizingMaskIntoConstraints = false

        hubcapSaveBtn = makeButton(title: L10n.tr("settings.hubcap.save"), target: self, action: #selector(saveHubcapKeyTapped))
        hubcapRefreshBtn = makeButton(title: L10n.tr("settings.hubcap.refresh"), target: self, action: #selector(refreshHubcapQuota))
        hubcapClearBtn = makeButton(title: L10n.tr("settings.hubcap.clear"), target: self, action: #selector(clearHubcapKeyTapped))

        let row = NSStackView(views: hasKey ? [hubcapRefreshBtn, hubcapClearBtn] : [hubcapInputField, hubcapSaveBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let vStack = NSStackView(views: [hubcapStatusLabel, row])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false
        if !hasKey {
            row.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        }

        card.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func makeToggle(isOn: Bool, action: Selector) -> NSSwitch {
        let s = NSSwitch()
        s.state = isOn ? .on : .off
        s.target = self
        s.action = action
        return s
    }

    // MARK: - Actions

    @objc private func languagePopupChanged() {
        let idx = langPopup.indexOfSelectedItem
        guard idx >= 0, idx < L10n.Language.allCases.count else { return }
        L10n.currentLanguageSetting = L10n.Language.allCases[idx]
    }

    @objc private func settingsChanged() {
        persisting { try store.setHideWhatsNew(hideWhatsNewSwitch.state == .on) }
    }

    @objc private func luaToolsTogglesChanged() {
        AppSettings.shared.fastFetch = (fastFetchSwitch.state == .on)
        AppSettings.shared.autoUpdateApps = (autoUpdateAppsSwitch.state == .on)
        AppSettings.shared.donateKeys = (donateKeysSwitch.state == .on)
        AppSettings.shared.cefPluginEnabled = (cefPluginSwitch.state == .on)
        CefInjectorService.shared.refreshEnabledState()
    }

    @objc private func signInDiscordTapped() {
        discordSignInBtn.isEnabled = false
        Task {
            do {
                try await AuthService.shared.signInWithDiscord()
            } catch {
                await MainActor.run {
                    self.discordSignInBtn.isEnabled = true
                    presentAlert("Discord Sign-In", error.localizedDescription, style: .warning)
                }
            }
        }
    }

    @objc private func redeemBotCodeTapped() {
        let code = codeInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        redeemCodeBtn.isEnabled = false
        Task {
            do {
                try await AuthService.shared.signInWithCode(code)
            } catch {
                await MainActor.run {
                    self.redeemCodeBtn.isEnabled = true
                    presentAlert("Code Sign-In", error.localizedDescription, style: .warning)
                }
            }
        }
    }

    @objc private func signOutTapped() {
        AuthService.shared.signOut()
    }

    @objc private func saveHubcapKeyTapped() {
        let key = hubcapInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HubcapService.isValidKeyFormat(key) else {
            presentAlert("Hubcap Key", "Invalid format. Expected 'smm_' followed by 96 hex characters.", style: .warning)
            return
        }
        hubcapSaveBtn.isEnabled = false
        Task {
            let stats = await HubcapService.shared.getStats(key: key)
            await MainActor.run {
                self.hubcapSaveBtn.isEnabled = true
                guard stats != nil else {
                    presentAlert("Hubcap Key", "Could not validate key with hubcapmanifest.com.", style: .warning)
                    return
                }
                AppSettings.shared.hubcapApiKey = key
                self.showDetail(for: .settings)
            }
        }
    }

    @objc private func refreshHubcapQuota() {
        guard let key = AppSettings.shared.hubcapApiKey, !key.isEmpty else { return }
        Task {
            if let stats = await HubcapService.shared.getStats(key: key) {
                await MainActor.run {
                    self.hubcapStatusLabel?.stringValue = L10n.tr("settings.hubcap.configured", stats.dailyUsage, stats.dailyLimit)
                }
            }
        }
    }

    @objc private func clearHubcapKeyTapped() {
        AppSettings.shared.hubcapApiKey = nil
        showDetail(for: .settings)
    }

    @objc private func checkForUpdatesTapped() {
        UpdaterManager.shared.checkForUpdates()
    }

    @objc private func autoUpdateChanged() {
        UpdaterManager.shared.automaticallyChecksForUpdates = (autoUpdateSwitch?.state == .on)
    }

    // MARK: Apps detail (Steam game cards)

    private func buildAppsDetail() -> NSView {
        let list = AppCardListView(store: store)
        list.onUpdateGame = { [weak self] appID in
            self?.onUpdateGame?(appID)
        }
        list.onManageBuilds = { [weak self] appID in
            self?.onManageBuilds?(appID)
        }
        list.performRemoval = { [weak self] ids in
            guard let self else { return false }
            var ok = true
            self.persisting {
                do { try self.store.removeApps(ids) }
                catch { ok = false; throw error }
            }
            return ok
        }
        list.confirmRemoval = { [weak self, weak list] removed in
            guard let self, let list else { return true }
            let baseGames = removed.filter { list.dlcCount(for: $0) > 0 }
            if let game = baseGames.first, removed.count > 1 {
                let n = list.dlcCount(for: game)
                return self.confirmDestructive(
                    "Remove \(list.displayName(for: game)) and its \(n) DLC?",
                    informative: "This removes the game and its DLC from the macSteam "
                        + "configuration. macSteam will no longer unlock the title.")
            }
            let names = ListFormatter.localizedString(
                byJoining: removed.map { list.displayName(for: $0) })
            let titleNoun = removed.count > 1 ? "these titles" : "the title"
            return self.confirmDestructive(
                "Remove \(names)?",
                informative: "This removes \(names) from the macSteam configuration. "
                    + "macSteam will no longer unlock \(titleNoun).")
        }
        appsCardList = list
        return list.listView
    }
}
