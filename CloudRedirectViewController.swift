// CloudRedirect v2.6.8 native pane styled & structured after Windows CloudRedirect (Dashboard, Provider, Apps, Achievements & Playtime, Clean Up & 760, Migration)
import AppKit

final class CloudRedirectViewController: NSViewController {

    private let orderedProviders: [CloudProviderKind] = [.folder, .gdrive, .onedrive, .r2, .s3, .local]

    // Header & Sub-tab navigation
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var tabSegment: NSSegmentedControl!
    private var tabStacks: [NSStackView] = []

    // MARK: Tab 0 - Dashboard
    private var dashProviderSubtitle: NSTextField!
    private var dashProviderBadge: PillBadge!
    private var dashSteamSubtitle: NSTextField!
    private var dashAppsSubtitle: NSTextField!
    private var dashDllSubtitle: NSTextField!
    private var dashDllBadge: PillBadge!
    private var dashMultiAccountCard: NSView!
    private var dashMultiAccountLabel: NSTextField!
    private var dashProgressBar: NSProgressIndicator!
    private var dashProgressLabel: NSTextField!
    private var dashInstallBtn: NSButton!
    private var dashToggleBtn: NSButton!

    // MARK: Tab 1 - Provider & Settings
    private var providerPopup: NSPopUpButton!
    private var providerStatusPill: PillBadge!
    private var testConnButton: NSButton!
    private var localNoteSection: NSStackView!
    private var folderSection: NSStackView!
    private var folderPathField: NSTextField!
    private var winePathHintLabel: NSTextField!
    private var iCloudButton: NSButton!
    private var oauthSection: NSStackView!
    private var oauthDescLabel: NSTextField!
    private var oauthSignInButton: NSButton!
    private var oauthCancelButton: NSButton!
    private var oauthRevokeButton: NSButton!
    private var oauthLogLabel: NSTextField!
    private var gdriveInFlightRow: NSStackView!
    private var gdriveInFlightSlider: NSSlider!
    private var gdriveInFlightValueLabel: NSTextField!
    private var r2Section: NSStackView!
    private var r2AccountIdField: NSTextField!
    private var r2AccessKeyField: NSTextField!
    private var r2SecretKeyField: NSSecureTextField!
    private var r2BucketField: NSTextField!
    private var r2PrefixField: NSTextField!
    private var r2EndpointField: NSTextField!
    private var s3Section: NSStackView!
    private var s3EndpointField: NSTextField!
    private var s3RegionField: NSTextField!
    private var s3BucketField: NSTextField!
    private var s3PrefixField: NSTextField!
    private var s3AccessKeyField: NSTextField!
    private var s3SecretKeyField: NSSecureTextField!
    private var s3CaCertField: NSTextField!
    private var s3SignPayloadSwitch: NSSwitch!
    private var s3InsecureHttpSwitch: NSSwitch!
    private var s3InsecureTlsSwitch: NSSwitch!
    private var syncLuasSwitch: NSSwitch!
    private var syncAchievementsSwitch: NSSwitch!
    private var syncPlaytimeSwitch: NSSwitch!
    private var showNonSteamSwitch: NSSwitch!
    private var autoUpdateSwitch: NSSwitch!
    private var parentalBypassSwitch: NSSwitch!
    private var parentalIgnoreSwitch: NSSwitch!
    private var saveConfigButton: NSButton!

    // MARK: Tab 2 - Apps
    private var appsSearchField: NSSearchField!
    private var appsSummaryLabel: NSTextField!
    private var appsListStack: NSStackView!

    // MARK: Tab 3 - Achievements & Playtime
    private var statsSearchField: NSSearchField!
    private var statsSummaryLabel: NSTextField!
    private var statsListStack: NSStackView!
    private var expandedStatKeys: Set<String> = []

    // MARK: Tab 4 - Clean Up & 760
    private var savedProvidersStack: NSStackView!
    private var cloud760SummaryLabel: NSTextField!
    private var cloud760ListStack: NSStackView!
    private var clean760Button: NSButton!

    // MARK: Tab 5 - Migration & Multi-account Sync
    private var migSourceAccountPopup: NSPopUpButton!
    private var migTargetAccountPopup: NSPopUpButton!
    private var migAccountCopyBtn: NSButton!
    private var migAccountStatusLabel: NSTextField!
    private var migGamesSummaryLabel: NSTextField!
    private var migGamesListStack: NSStackView!

    // State
    private var isBusy = false
    private var isFetchingCloud = false
    private var lastCloudFetchAt: Date?
    private var oauthSession: CloudRedirectOAuthSession?
    private var currentConfig = CloudRedirectConfig()
    private var snapshot: CloudSnapshot?
    private var resolvedStoreInfo: [Int: StoreAppInfo] = [:]

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let fr = L10n.isFrench
        titleLabel = NSTextField(labelWithString: L10n.tr("sidebar.cloud_redirect"))
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        subtitleLabel = makeWrappingLabel(
            fr
            ? "Synchronisez vos sauvegardes Steam Cloud, succès et temps de jeu dans CrossOver Steam (CloudRedirect v\(CloudRedirectInstaller.bundledVersion))."
            : "Sync CrossOver Steam Cloud saves, achievements, and playtime seamlessly (CloudRedirect v\(CloudRedirectInstaller.bundledVersion)).",
            font: Typography.body,
            color: .secondaryLabelColor
        )

        tabSegment = NSSegmentedControl(labels: [
            fr ? "Tableau de bord" : "Dashboard",
            fr ? "Fournisseur" : "Provider",
            fr ? "Jeux" : "Apps",
            fr ? "Succès & Temps" : "Achievements",
            fr ? "Nettoyage" : "Clean Up",
            fr ? "Migration" : "Migration",
        ], trackingMode: .selectOne, target: self, action: #selector(tabChanged))
        tabSegment.segmentStyle = .rounded
        tabSegment.selectedSegment = 0

        let dashboardTab = buildDashboardTab(fr: fr)
        let providerTab = buildProviderTab(fr: fr)
        let appsTab = buildAppsTab(fr: fr)
        let statsTab = buildStatsTab(fr: fr)
        let cleanupTab = buildCleanupTab(fr: fr)
        let migrationTab = buildMigrationTab(fr: fr)
        tabStacks = [dashboardTab, providerTab, appsTab, statsTab, cleanupTab, migrationTab]

        let mainStack = NSStackView(views: [titleLabel, subtitleLabel, tabSegment] + tabStacks)
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.setCustomSpacing(4, after: titleLabel)
        mainStack.setCustomSpacing(12, after: subtitleLabel)
        mainStack.setCustomSpacing(16, after: tabSegment)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        doc.addSubview(mainStack)
        for s in tabStacks {
            s.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        }

        let M = Metrics.paneMargin
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            // Prevent any wide text or card from expanding beyond the scroll viewport width
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            mainStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: M - 4),
            mainStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: M),
            mainStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -M),
            mainStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -M),
        ])

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 660))
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        switchTab(to: 0)
        currentConfig = CloudRedirectInstaller.loadConfig()
        applyConfigToFields(currentConfig)
        refreshLocalStatusUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadAllState(forceCloud: false)
    }

    // MARK: - Tab 0: Dashboard (Windows CloudRedirect Screenshot 1 style)

    private func buildDashboardTab(fr: Bool) -> NSStackView {
        // Card 1: Cloud Provider
        dashProviderBadge = PillBadge(text: "—", tint: .secondaryLabelColor)
        dashProviderSubtitle = makeWrappingLabel("—", font: Typography.body, color: .secondaryLabelColor)
        let c1 = makeDashboardRowCard(
            title: fr ? "Fournisseur Cloud" : "Cloud Provider",
            subtitleLabel: dashProviderSubtitle,
            badge: dashProviderBadge,
            symbol: "icloud.fill",
            tint: .systemTeal
        )

        // Card 2: Steam Installation
        dashSteamSubtitle = makeWrappingLabel("—", font: Typography.body, color: .secondaryLabelColor)
        let c2 = makeDashboardRowCard(
            title: fr ? "Installation Steam (CrossOver)" : "Steam Installation (CrossOver)",
            subtitleLabel: dashSteamSubtitle,
            badge: nil,
            symbol: "desktopcomputer",
            tint: .systemBlue
        )

        // Card 3: Apps Syncing
        dashAppsSubtitle = makeWrappingLabel("—", font: Typography.body, color: .secondaryLabelColor)
        let c3 = makeDashboardRowCard(
            title: fr ? "Jeux synchronisés" : "Apps Syncing",
            subtitleLabel: dashAppsSubtitle,
            badge: nil,
            symbol: "square.grid.2x2.fill",
            tint: .systemPurple
        )

        // Card 4: CloudRedirect DLL
        dashDllBadge = PillBadge(text: "—", tint: .secondaryLabelColor)
        dashDllSubtitle = makeWrappingLabel("—", font: Typography.body, color: .secondaryLabelColor)
        let c4 = makeDashboardRowCard(
            title: "CloudRedirect DLL",
            subtitleLabel: dashDllSubtitle,
            badge: dashDllBadge,
            symbol: "powerplug.fill",
            tint: .systemGreen
        )

        // Multi-account warning card (explains Windows vs Mac save split when 2 accounts exist)
        dashMultiAccountCard = NSView()
        dashMultiAccountCard.applyCardSurface()
        dashMultiAccountCard.translatesAutoresizingMaskIntoConstraints = false
        dashMultiAccountCard.isHidden = true

        let warnIcon = NSImageView()
        warnIcon.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)
        warnIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        warnIcon.contentTintColor = .systemOrange

        let warnTitle = NSTextField(labelWithString: fr ? "Deux comptes Steam détectés sur vos sauvegardes" : "Multiple Steam Accounts Detected")
        warnTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        dashMultiAccountLabel = makeWrappingLabel("", font: Typography.caption, color: .secondaryLabelColor)

        let goMigBtn = makeButton(title: fr ? "Synchroniser / Copier vers CrossOver →" : "Sync / Copy Account Saves →", target: self, action: #selector(doJumpToMigration))
        let warnCol = NSStackView(views: [warnTitle, dashMultiAccountLabel, goMigBtn])
        warnCol.orientation = .vertical
        warnCol.alignment = .leading
        warnCol.spacing = 6

        let warnRow = NSStackView(views: [warnIcon, warnCol])
        warnRow.orientation = .horizontal
        warnRow.alignment = .top
        warnRow.spacing = 12
        warnRow.translatesAutoresizingMaskIntoConstraints = false
        dashMultiAccountCard.addSubview(warnRow)
        NSLayoutConstraint.activate([
            warnRow.topAnchor.constraint(equalTo: dashMultiAccountCard.topAnchor, constant: 14),
            warnRow.bottomAnchor.constraint(equalTo: dashMultiAccountCard.bottomAnchor, constant: -14),
            warnRow.leadingAnchor.constraint(equalTo: dashMultiAccountCard.leadingAnchor, constant: 16),
            warnRow.trailingAnchor.constraint(equalTo: dashMultiAccountCard.trailingAnchor, constant: -16),
        ])

        // Quick Actions (Screenshot 1 bottom)
        let actionsHeader = settingsGroupLabel(fr ? "Actions rapides" : "Quick Actions")

        dashInstallBtn = makeButton(title: fr ? "Installer / Mettre à jour DLL" : "Install / Update DLL", target: self, action: #selector(doInstallOrUpdate))
        dashInstallBtn.bezelColor = .controlAccentColor
        dashToggleBtn = makeButton(title: fr ? "Activer / Désactiver" : "Enable / Disable", target: self, action: #selector(doToggleEnabled))
        let openLogBtn = makeButton(title: fr ? "Ouvrir le log" : "Show Log in Folder", target: self, action: #selector(doOpenLogFile))
        let restartSteamBtn = makeButton(title: fr ? "Relancer Steam" : "Restart Steam", target: self, action: #selector(doLaunchCrossOverSteam))
        let openCfgBtn = makeButton(title: fr ? "Dossier config" : "Config Folder", target: self, action: #selector(doOpenConfigDir))
        let refreshBtn = makeButton(title: fr ? "Actualiser Cloud" : "Refresh Cloud", target: self, action: #selector(doRefreshAll))

        let row1 = NSStackView(views: [dashInstallBtn, dashToggleBtn, refreshBtn, NSView()])
        row1.orientation = .horizontal
        row1.spacing = 8

        let row2 = NSStackView(views: [openLogBtn, restartSteamBtn, openCfgBtn, NSView()])
        row2.orientation = .horizontal
        row2.spacing = 8

        dashProgressBar = NSProgressIndicator()
        dashProgressBar.style = .bar
        dashProgressBar.isIndeterminate = false
        dashProgressBar.minValue = 0
        dashProgressBar.maxValue = 100
        dashProgressBar.isHidden = true

        dashProgressLabel = NSTextField(labelWithString: "")
        dashProgressLabel.font = Typography.caption
        dashProgressLabel.textColor = .secondaryLabelColor
        dashProgressLabel.isHidden = true

        let stack = NSStackView(views: [
            c1, c2, c3, c4, dashMultiAccountCard,
            actionsHeader, row1, row2, dashProgressBar, dashProgressLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: c4)
        for v in [c1, c2, c3, c4, dashMultiAccountCard!, row1, row2, dashProgressBar!] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeDashboardRowCard(
        title: String,
        subtitleLabel: NSTextField,
        badge: PillBadge?,
        symbol: String,
        tint: NSColor
    ) -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font = .systemFont(ofSize: 13.5, weight: .semibold)

        let titleRow = NSStackView(views: badge != nil ? [titleLbl, badge!, NSView()] : [titleLbl, NSView()])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let leftCol = NSStackView(views: [titleRow, subtitleLabel])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 3

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        iconView.contentTintColor = tint
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [leftCol, NSView(), iconView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    // MARK: - Tab 1: Provider & Settings

    private func buildProviderTab(fr: Bool) -> NSStackView {
        let providerCard = makeProviderCard(fr: fr)
        let optionsCard = makeOptionsCard(fr: fr)
        let stack = NSStackView(views: [providerCard, optionsCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        providerCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        optionsCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeProviderCard(fr: Bool) -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: fr ? "Fournisseur Cloud" : "Cloud Provider")
        heading.font = .systemFont(ofSize: 15, weight: .bold)

        providerStatusPill = PillBadge(text: "—", tint: .secondaryLabelColor)

        let topTitleRow = NSStackView(views: [heading, providerStatusPill, NSView()])
        topTitleRow.orientation = .horizontal
        topTitleRow.alignment = .centerY
        topTitleRow.spacing = 8

        providerPopup = NSPopUpButton()
        for kind in orderedProviders {
            providerPopup.addItem(withTitle: kind.displayName)
        }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)

        testConnButton = makeButton(title: fr ? "Tester la connexion" : "Test Connection", target: self, action: #selector(doTestConnection))

        let selectorRow = NSStackView(views: [providerPopup, testConnButton, NSView()])
        selectorRow.orientation = .horizontal
        selectorRow.alignment = .centerY
        selectorRow.spacing = 8

        // 1. Local-only note
        let localLbl = makeWrappingLabel(
            fr
            ? "Mode local uniquement : les sauvegardes restent dans <Steam>/cloud_redirect/storage sans synchronisation externe."
            : "Local-only mode: saves stay inside <Steam>/cloud_redirect/storage without external cloud sync.",
            font: Typography.body,
            color: .secondaryLabelColor
        )
        localNoteSection = NSStackView(views: [localLbl])
        localNoteSection.orientation = .vertical
        localNoteSection.alignment = .leading

        // 2. Folder section
        folderPathField = makeMonoField(placeholder: CloudRedirectInstaller.defaultLocalSyncFolder.path)
        folderPathField.lineBreakMode = .byTruncatingMiddle
        let browseBtn = makeButton(title: fr ? "Choisir…" : "Choose…", target: self, action: #selector(doChooseFolder))
        iCloudButton = makeButton(title: "iCloud Drive", target: self, action: #selector(doUseICloudFolder))
        let openSyncBtn = makeButton(title: fr ? "Ouvrir" : "Open", target: self, action: #selector(doOpenSyncFolder))

        let folderInputRow = NSStackView(views: [folderPathField, browseBtn, iCloudButton, openSyncBtn])
        folderInputRow.orientation = .horizontal
        folderInputRow.alignment = .centerY
        folderInputRow.spacing = 8

        winePathHintLabel = makeWrappingLabel("", font: Typography.caption, color: .secondaryLabelColor)
        folderSection = NSStackView(views: [folderInputRow, winePathHintLabel])
        folderSection.orientation = .vertical
        folderSection.alignment = .leading
        folderSection.spacing = 6
        folderInputRow.widthAnchor.constraint(equalTo: folderSection.widthAnchor).isActive = true

        // 3. OAuth (Google Drive / OneDrive)
        oauthDescLabel = makeWrappingLabel("", font: Typography.body, color: .secondaryLabelColor)

        oauthSignInButton = makeButton(title: "", target: self, action: #selector(doOAuthSignIn))
        oauthSignInButton.bezelColor = .controlAccentColor
        oauthCancelButton = makeButton(title: fr ? "Annuler" : "Cancel", target: self, action: #selector(doOAuthCancel))
        oauthCancelButton.isHidden = true
        oauthRevokeButton = makeButton(title: fr ? "Déconnecter" : "Sign Out", target: self, action: #selector(doOAuthRevoke))

        let oauthBtnRow = NSStackView(views: [oauthSignInButton, oauthCancelButton, oauthRevokeButton, NSView()])
        oauthBtnRow.orientation = .horizontal
        oauthBtnRow.alignment = .centerY
        oauthBtnRow.spacing = 8

        oauthLogLabel = makeWrappingLabel("", font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        oauthLogLabel.isHidden = true

        let inFlightLbl = NSTextField(labelWithString: fr ? "Tampon d'upload simultané (Google Drive)" : "Concurrent Upload Cap (Google Drive)")
        inFlightLbl.font = Typography.body
        gdriveInFlightSlider = NSSlider(value: 24, minValue: 24, maxValue: 64, target: self, action: #selector(inFlightSliderChanged))
        gdriveInFlightSlider.numberOfTickMarks = 5
        gdriveInFlightSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        gdriveInFlightValueLabel = NSTextField(labelWithString: "24 MB")
        gdriveInFlightValueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        gdriveInFlightValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        gdriveInFlightRow = NSStackView(views: [inFlightLbl, NSView(), gdriveInFlightSlider, gdriveInFlightValueLabel])
        gdriveInFlightRow.orientation = .horizontal
        gdriveInFlightRow.alignment = .centerY
        gdriveInFlightRow.spacing = 8

        oauthSection = NSStackView(views: [oauthDescLabel, oauthBtnRow, oauthLogLabel, gdriveInFlightRow])
        oauthSection.orientation = .vertical
        oauthSection.alignment = .leading
        oauthSection.spacing = 10
        oauthBtnRow.widthAnchor.constraint(equalTo: oauthSection.widthAnchor).isActive = true
        gdriveInFlightRow.widthAnchor.constraint(equalTo: oauthSection.widthAnchor).isActive = true

        // 4. R2 section
        r2AccountIdField = makeMonoField(placeholder: fr ? "32 caractères hexadécimaux (ex: a1b2c3d4…)" : "32 lowercase hex chars")
        r2AccessKeyField = makeMonoField(placeholder: "Access Key ID")
        r2SecretKeyField = makeSecureMonoField()
        r2BucketField = makeMonoField(placeholder: "my-cloudredirect-saves")
        r2PrefixField = makeMonoField(placeholder: fr ? "(Optionnel) cloudredirect/" : "(Optional) cloudredirect/")
        r2EndpointField = makeMonoField(placeholder: fr ? "(Optionnel) Endpoint personnalisé" : "(Optional) Custom endpoint")

        let r2Rows = [
            makeLabeledFieldRow(label: "Cloudflare Account ID", field: r2AccountIdField),
            makeLabeledFieldRow(label: "Access Key ID", field: r2AccessKeyField),
            makeLabeledFieldRow(label: "Secret Access Key", field: r2SecretKeyField),
            makeLabeledFieldRow(label: "Bucket", field: r2BucketField),
            makeLabeledFieldRow(label: fr ? "Préfixe (Key Prefix)" : "Key Prefix", field: r2PrefixField),
            makeLabeledFieldRow(label: fr ? "Endpoint personnalisé" : "Custom Endpoint", field: r2EndpointField),
        ]
        r2Section = NSStackView(views: r2Rows)
        r2Section.orientation = .vertical
        r2Section.alignment = .leading
        r2Section.spacing = 8
        for r in r2Rows { r.widthAnchor.constraint(equalTo: r2Section.widthAnchor).isActive = true }

        // 5. S3 section
        s3EndpointField = makeMonoField(placeholder: "https://s3.us-east-1.amazonaws.com")
        s3RegionField = makeMonoField(placeholder: "us-east-1")
        s3BucketField = makeMonoField(placeholder: "my-cloudredirect-saves")
        s3PrefixField = makeMonoField(placeholder: fr ? "(Optionnel) cloudredirect/" : "(Optional) cloudredirect/")
        s3AccessKeyField = makeMonoField(placeholder: "AKIA…")
        s3SecretKeyField = makeSecureMonoField()
        s3CaCertField = makeMonoField(placeholder: fr ? "(Optionnel) Certificat CA .pem" : "(Optional) CA cert .pem")
        let browseCaBtn = makeButton(title: fr ? "Parcourir…" : "Browse…", target: self, action: #selector(doChooseS3CaCert))

        let caRow = NSStackView(views: [s3CaCertField, browseCaBtn])
        caRow.orientation = .horizontal
        caRow.spacing = 8

        s3SignPayloadSwitch = NSSwitch()
        s3InsecureHttpSwitch = NSSwitch()
        s3InsecureTlsSwitch = NSSwitch()

        let s3AdvCard = SettingsCard(rows: [
            SettingRow(title: fr ? "Signer le payload SHA-256 (sign_payload)" : "Sign SHA-256 payload (sign_payload)", control: s3SignPayloadSwitch),
            SettingRow(title: fr ? "Autoriser HTTP non chiffré (allow_insecure_http)" : "Allow plain HTTP (allow_insecure_http)", control: s3InsecureHttpSwitch),
            SettingRow(title: fr ? "Ignorer validation TLS (allow_insecure_tls)" : "Allow insecure TLS (allow_insecure_tls)", control: s3InsecureTlsSwitch),
        ])

        let s3Rows = [
            makeLabeledFieldRow(label: "Endpoint S3", field: s3EndpointField),
            makeLabeledFieldRow(label: fr ? "Région" : "Region", field: s3RegionField),
            makeLabeledFieldRow(label: "Bucket", field: s3BucketField),
            makeLabeledFieldRow(label: fr ? "Préfixe (Key Prefix)" : "Key Prefix", field: s3PrefixField),
            makeLabeledFieldRow(label: "Access Key ID", field: s3AccessKeyField),
            makeLabeledFieldRow(label: "Secret Access Key", field: s3SecretKeyField),
            makeLabeledFieldRow(label: fr ? "Certificat CA (.pem)" : "CA Cert (.pem)", field: caRow),
        ]
        s3Section = NSStackView(views: s3Rows + [s3AdvCard])
        s3Section.orientation = .vertical
        s3Section.alignment = .leading
        s3Section.spacing = 8
        for r in s3Rows { r.widthAnchor.constraint(equalTo: s3Section.widthAnchor).isActive = true }
        s3AdvCard.widthAnchor.constraint(equalTo: s3Section.widthAnchor).isActive = true

        let stack = NSStackView(views: [
            topTitleRow, selectorRow, localNoteSection, folderSection, oauthSection, r2Section, s3Section,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [topTitleRow, selectorRow, localNoteSection, folderSection, oauthSection, r2Section, s3Section] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func makeOptionsCard(fr: Bool) -> NSView {
        let card = NSView()
        card.applyCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: fr ? "Options de synchronisation & Contrôle parental" : "Sync & Parental Options")
        heading.font = .systemFont(ofSize: 15, weight: .bold)

        syncLuasSwitch = NSSwitch()
        syncAchievementsSwitch = NSSwitch()
        syncPlaytimeSwitch = NSSwitch()
        showNonSteamSwitch = NSSwitch()
        autoUpdateSwitch = NSSwitch()
        parentalBypassSwitch = NSSwitch()
        parentalIgnoreSwitch = NSSwitch()

        let rows = SettingsCard(rows: [
            SettingRow(title: fr ? "Synchroniser les fichiers .lua" : "Sync .lua game definitions", control: syncLuasSwitch),
            SettingRow(title: fr ? "Synchroniser les succès" : "Sync Achievements", control: syncAchievementsSwitch),
            SettingRow(title: fr ? "Synchroniser le temps de jeu" : "Sync Playtime", control: syncPlaytimeSwitch),
            SettingRow(title: fr ? "Afficher l'overlay jeu non-Steam" : "Show Non-Steam Game overlay", control: showNonSteamSwitch),
            SettingRow(title: fr ? "Mise à jour auto de cloud_redirect.dll" : "Auto-update cloud_redirect.dll", control: autoUpdateSwitch),
            SettingRow(title: fr ? "Contrôle parental : contourner la limite de jeu" : "Parental: bypass playtime restriction", control: parentalBypassSwitch),
            SettingRow(title: fr ? "Contrôle parental : ignorer le suivi de durée" : "Parental: ignore playtime tracking", control: parentalIgnoreSwitch),
        ])

        saveConfigButton = makeButton(title: fr ? "Enregistrer la configuration" : "Save Configuration", target: self, action: #selector(doSaveConfig))
        saveConfigButton.bezelColor = .controlAccentColor

        let btnRow = NSStackView(views: [saveConfigButton, NSView()])
        btnRow.orientation = .horizontal

        let stack = NSStackView(views: [heading, rows, btnRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        rows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        btnRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    // MARK: - Tab 2: Apps (Screenshot 2)

    private func buildAppsTab(fr: Bool) -> NSStackView {
        appsSearchField = NSSearchField()
        appsSearchField.placeholderString = fr ? "Rechercher par nom ou AppID…" : "Search by name or AppID…"
        appsSearchField.target = self
        appsSearchField.action = #selector(appsFilterChanged)

        let refreshBtn = makeButton(title: fr ? "Actualiser" : "Refresh", target: self, action: #selector(doRefreshAll))
        let exportAllBtn = makeButton(title: fr ? "Backup complet (.zip)" : "Export All (.zip)", target: self, action: #selector(doExportAllApps))

        let topBar = NSStackView(views: [refreshBtn, exportAllBtn, appsSearchField])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8

        appsSummaryLabel = makeWrappingLabel("—", font: Typography.caption, color: .secondaryLabelColor)

        appsListStack = NSStackView()
        appsListStack.orientation = .vertical
        appsListStack.alignment = .leading
        appsListStack.spacing = 8

        let stack = NSStackView(views: [topBar, appsSummaryLabel, appsListStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        topBar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        appsListStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Tab 3: Achievements & Playtime (Screenshot 4)

    private func buildStatsTab(fr: Bool) -> NSStackView {
        statsSearchField = NSSearchField()
        statsSearchField.placeholderString = fr ? "Rechercher par nom ou AppID…" : "Search by name or AppID…"
        statsSearchField.target = self
        statsSearchField.action = #selector(statsFilterChanged)

        let refreshBtn = makeButton(title: fr ? "Actualiser" : "Refresh", target: self, action: #selector(doRefreshAll))

        let topBar = NSStackView(views: [statsSearchField, refreshBtn])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8

        statsSummaryLabel = makeWrappingLabel("—", font: Typography.caption, color: .secondaryLabelColor)

        statsListStack = NSStackView()
        statsListStack.orientation = .vertical
        statsListStack.alignment = .leading
        statsListStack.spacing = 8

        let stack = NSStackView(views: [topBar, statsSummaryLabel, statsListStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        topBar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statsListStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Tab 4: Clean Up & 760

    private func buildCleanupTab(fr: Bool) -> NSStackView {
        // Saved accounts/credentials overview
        let savedCard = NSView()
        savedCard.applyCardSurface()
        savedCard.translatesAutoresizingMaskIntoConstraints = false

        let savedTitle = NSTextField(labelWithString: fr ? "Fournisseurs enregistrés (token_paths)" : "Saved Providers (token_paths)")
        savedTitle.font = .systemFont(ofSize: 15, weight: .bold)

        savedProvidersStack = NSStackView()
        savedProvidersStack.orientation = .horizontal
        savedProvidersStack.alignment = .centerY
        savedProvidersStack.spacing = 8

        let savedInner = NSStackView(views: [savedTitle, savedProvidersStack])
        savedInner.orientation = .vertical
        savedInner.alignment = .leading
        savedInner.spacing = 8
        savedInner.translatesAutoresizingMaskIntoConstraints = false
        savedCard.addSubview(savedInner)
        NSLayoutConstraint.activate([
            savedInner.topAnchor.constraint(equalTo: savedCard.topAnchor, constant: 16),
            savedInner.bottomAnchor.constraint(equalTo: savedCard.bottomAnchor, constant: -16),
            savedInner.leadingAnchor.constraint(equalTo: savedCard.leadingAnchor, constant: 16),
            savedInner.trailingAnchor.constraint(equalTo: savedCard.trailingAnchor, constant: -16),
        ])

        // 760 Clean Up card
        let card760 = NSView()
        card760.applyCardSurface()
        card760.translatesAutoresizingMaskIntoConstraints = false

        let t760 = NSTextField(labelWithString: fr ? "Nettoyage Steam 760 (userdata)" : "Steam 760 Clean Up (userdata)")
        t760.font = .systemFont(ofSize: 15, weight: .bold)
        cloud760SummaryLabel = makeWrappingLabel("—", font: Typography.body, color: .secondaryLabelColor)

        let scan760Btn = makeButton(title: fr ? "Analyser 760" : "Scan 760", target: self, action: #selector(doRefresh760))
        clean760Button = makeButton(title: fr ? "Sauvegarder & Nettoyer 760" : "Backup & Clean 760", target: self, action: #selector(doClean760))
        let row760 = NSStackView(views: [scan760Btn, clean760Button, NSView()])
        row760.orientation = .horizontal
        row760.spacing = 8

        cloud760ListStack = NSStackView()
        cloud760ListStack.orientation = .vertical
        cloud760ListStack.alignment = .leading
        cloud760ListStack.spacing = 4

        let inner760 = NSStackView(views: [t760, cloud760SummaryLabel, row760, cloud760ListStack])
        inner760.orientation = .vertical
        inner760.alignment = .leading
        inner760.spacing = 10
        inner760.translatesAutoresizingMaskIntoConstraints = false
        row760.widthAnchor.constraint(equalTo: inner760.widthAnchor).isActive = true
        cloud760ListStack.widthAnchor.constraint(equalTo: inner760.widthAnchor).isActive = true

        card760.addSubview(inner760)
        NSLayoutConstraint.activate([
            inner760.topAnchor.constraint(equalTo: card760.topAnchor, constant: 16),
            inner760.bottomAnchor.constraint(equalTo: card760.bottomAnchor, constant: -16),
            inner760.leadingAnchor.constraint(equalTo: card760.leadingAnchor, constant: 16),
            inner760.trailingAnchor.constraint(equalTo: card760.trailingAnchor, constant: -16),
        ])

        // Local Cache Reset + Folders
        let resetCard = NSView()
        resetCard.applyCardSurface()
        resetCard.translatesAutoresizingMaskIntoConstraints = false

        let tReset = NSTextField(labelWithString: fr ? "Cache local CrossOver & Journaux" : "Local Cache & Logs")
        tReset.font = .systemFont(ofSize: 15, weight: .bold)

        let resetBtn = makeButton(title: fr ? "Réinitialiser cache local" : "Reset Local Cache", target: self, action: #selector(doResetLocalCache))
        let openLogBtn = makeButton(title: fr ? "Ouvrir cloud_redirect.log" : "Open cloud_redirect.log", target: self, action: #selector(doOpenLogFile))
        let openDirBtn = makeButton(title: fr ? "Dossier cloud_redirect" : "cloud_redirect Folder", target: self, action: #selector(doOpenSteamCloudDir))
        let resetRow = NSStackView(views: [resetBtn, openLogBtn, openDirBtn, NSView()])
        resetRow.orientation = .horizontal
        resetRow.spacing = 8

        let resetInner = NSStackView(views: [tReset, resetRow])
        resetInner.orientation = .vertical
        resetInner.alignment = .leading
        resetInner.spacing = 10
        resetInner.translatesAutoresizingMaskIntoConstraints = false
        resetRow.widthAnchor.constraint(equalTo: resetInner.widthAnchor).isActive = true
        resetCard.addSubview(resetInner)
        NSLayoutConstraint.activate([
            resetInner.topAnchor.constraint(equalTo: resetCard.topAnchor, constant: 16),
            resetInner.bottomAnchor.constraint(equalTo: resetCard.bottomAnchor, constant: -16),
            resetInner.leadingAnchor.constraint(equalTo: resetCard.leadingAnchor, constant: 16),
            resetInner.trailingAnchor.constraint(equalTo: resetCard.trailingAnchor, constant: -16),
        ])

        let stack = NSStackView(views: [savedCard, card760, resetCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        for v in [savedCard, card760, resetCard] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    // MARK: - Tab 5: Migration & Account Sync (Screenshot 5)

    private func buildMigrationTab(fr: Bool) -> NSStackView {
        // Account-to-account sync card (fixes Windows vs Mac two-packet save split)
        let acctCard = NSView()
        acctCard.applyCardSurface()
        acctCard.translatesAutoresizingMaskIntoConstraints = false

        let acctTitle = NSTextField(labelWithString: fr ? "Synchroniser / Copier entre deux comptes Steam (Windows ↔ Mac)" : "Sync / Copy Between Steam Accounts (Windows ↔ Mac)")
        acctTitle.font = .systemFont(ofSize: 15, weight: .bold)

        let acctDesc = makeWrappingLabel(
            fr
            ? "CloudRedirect sépare les sauvegardes par ID de compte Steam (<AccountID>/<AppID>). Si votre PC Windows et votre Mac CrossOver utilisent deux comptes différents, copiez directement les sauvegardes et succès de l'un vers l'autre sur le Cloud."
            : "CloudRedirect isolates saves per Steam Account ID (<AccountID>/<AppID>). If Windows and CrossOver Mac use different accounts, copy saves and stats directly between accounts in the cloud.",
            font: Typography.caption,
            color: .secondaryLabelColor
        )

        migSourceAccountPopup = NSPopUpButton()
        migTargetAccountPopup = NSPopUpButton()
        let arrowLbl = NSTextField(labelWithString: "→")
        arrowLbl.font = .systemFont(ofSize: 15, weight: .bold)

        migAccountCopyBtn = makeButton(title: fr ? "Copier les sauvegardes" : "Copy Cloud Saves", target: self, action: #selector(doCopyBetweenAccounts))
        migAccountCopyBtn.bezelColor = .controlAccentColor

        let pickerRow = NSStackView(views: [migSourceAccountPopup, arrowLbl, migTargetAccountPopup, migAccountCopyBtn, NSView()])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY
        pickerRow.spacing = 8

        migAccountStatusLabel = makeWrappingLabel("", font: Typography.caption, color: .secondaryLabelColor)

        let acctInner = NSStackView(views: [acctTitle, acctDesc, pickerRow, migAccountStatusLabel])
        acctInner.orientation = .vertical
        acctInner.alignment = .leading
        acctInner.spacing = 10
        acctInner.translatesAutoresizingMaskIntoConstraints = false
        pickerRow.widthAnchor.constraint(equalTo: acctInner.widthAnchor).isActive = true
        acctCard.addSubview(acctInner)
        NSLayoutConstraint.activate([
            acctInner.topAnchor.constraint(equalTo: acctCard.topAnchor, constant: 16),
            acctInner.bottomAnchor.constraint(equalTo: acctCard.bottomAnchor, constant: -16),
            acctInner.leadingAnchor.constraint(equalTo: acctCard.leadingAnchor, constant: 16),
            acctInner.trailingAnchor.constraint(equalTo: acctCard.trailingAnchor, constant: -16),
        ])

        // Cloud games overview across accounts (Screenshot 5 list)
        migGamesSummaryLabel = NSTextField(labelWithString: "—")
        migGamesSummaryLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)

        migGamesListStack = NSStackView()
        migGamesListStack.orientation = .vertical
        migGamesListStack.alignment = .leading
        migGamesListStack.spacing = 8

        let stack = NSStackView(views: [acctCard, migGamesSummaryLabel, migGamesListStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        acctCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        migGamesListStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Small UI Helpers

    private func makeWrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let lbl = NSTextField(wrappingLabelWithString: text)
        lbl.font = font
        lbl.textColor = color
        lbl.preferredMaxLayoutWidth = 0
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }

    private func makeMonoField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        f.placeholderString = placeholder
        f.usesSingleLineMode = true
        return f
    }

    private func makeSecureMonoField() -> NSSecureTextField {
        let f = NSSecureTextField()
        f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        f.placeholderString = "••••••••••••••••"
        f.usesSingleLineMode = true
        return f
    }

    private func makeLabeledFieldRow(label: String, field: NSView) -> NSStackView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = Typography.body
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        lbl.widthAnchor.constraint(equalToConstant: 170).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [lbl, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private static func formatPlaytime(minutes: UInt32, fr: Bool) -> String {
        if minutes == 0 {
            return fr ? "Aucun temps de jeu" : "None played"
        }
        let hours = Double(minutes) / 60.0
        if hours < 0.1 {
            return "\(minutes) min " + (fr ? "jouées" : "played")
        }
        let formatted = String(format: "%.1f", hours)
        return "\(formatted) h " + (fr ? "jouées" : "played")
    }

    // MARK: - State Loading & Rendering

    private func switchTab(to index: Int) {
        for (i, s) in tabStacks.enumerated() {
            s.isHidden = (i != index)
        }
        if index == 4 { reloadToolsTab() }
    }

    private func selectedProvider() -> CloudProviderKind {
        let idx = providerPopup.indexOfSelectedItem
        if idx >= 0 && idx < orderedProviders.count {
            return orderedProviders[idx]
        }
        return .folder
    }

    private func loadAllState(forceCloud: Bool = true) {
        currentConfig = CloudRedirectInstaller.loadConfig()
        applyConfigToFields(currentConfig)
        refreshLocalStatusUI()
        reloadToolsTab()

        if !forceCloud {
            if isFetchingCloud { return }
            if let last = lastCloudFetchAt, Date().timeIntervalSince(last) < 60, snapshot != nil {
                return
            }
        }
        guard !isFetchingCloud else { return }
        isFetchingCloud = true

        let cfg = currentConfig
        Task { @MainActor [weak self] in
            let snap = await CloudRedirectCloudClient.fetchSnapshot(config: cfg)
            guard let self else { return }
            self.isFetchingCloud = false
            self.lastCloudFetchAt = Date()
            self.snapshot = snap
            self.applySnapshotToUI(snap)

            let allIds = Array(Set(snap.apps.map(\.appId) + snap.stats.map(\.appId)))
            if !allIds.isEmpty {
                let resolved = await SteamStoreClient.shared.resolve(appIDs: allIds)
                for (id, info) in resolved {
                    self.resolvedStoreInfo[id] = info
                }
                self.renderAppsTab()
                self.renderStatsTab()
                self.renderMigrationTab()
            }
        }
    }

    private func applySnapshotToUI(_ snap: CloudSnapshot) {
        let fr = L10n.isFrench
        dashProviderSubtitle.stringValue = snap.errorMessage != nil
            ? "\(snap.statusText) — \(snap.errorMessage!)"
            : snap.statusText
        dashProviderBadge.update(
            text: snap.authenticated ? (fr ? "Authentifié" : "Authenticated") : (fr ? "Non connecté" : "Not signed in"),
            tint: snap.authenticated ? .systemGreen : .systemOrange
        )

        let totalUniqueApps = Set(snap.apps.map { "\($0.accountId)/\($0.appId)" }).count
        let acctsStr = snap.cloudAccountIds.isEmpty ? "—" : snap.cloudAccountIds.joined(separator: ", ")
        dashAppsSubtitle.stringValue = fr
            ? "\(totalUniqueApps) jeu(x) détecté(s) · Compte(s) : \(acctsStr)"
            : "\(totalUniqueApps) app(s) with cloud/local data · Account(s): \(acctsStr)"

        // Highlight Windows vs Mac account mismatch clearly if found
        let activeCrossOver = snap.crossoverAccountIds
        let extraCloudAccounts = snap.cloudAccountIds.filter { !activeCrossOver.contains($0) }
        if !extraCloudAccounts.isEmpty {
            dashMultiAccountCard.isHidden = false
            let xoText = activeCrossOver.isEmpty ? "—" : activeCrossOver.joined(separator: ", ")
            let extText = extraCloudAccounts.joined(separator: ", ")
            dashMultiAccountLabel.stringValue = fr
                ? "CrossOver utilise le compte Steam [\(xoText)], mais d'autres sauvegardes existent sur le Cloud pour [\(extText)]. Connectez le même compte dans CrossOver ou copiez vos sauvegardes via Migration."
                : "CrossOver is signed into Steam [\(xoText)], while cloud saves also exist for [\(extText)]. Sign into the same Steam account or copy saves in Migration."
        } else {
            dashMultiAccountCard.isHidden = true
        }

        renderAppsTab()
        renderStatsTab()
        renderMigrationTab()
    }

    private func applyConfigToFields(_ cfg: CloudRedirectConfig) {
        if let idx = orderedProviders.firstIndex(of: cfg.provider) {
            providerPopup.selectItem(at: idx)
        }
        folderPathField.stringValue = cfg.localFolderPath
        gdriveInFlightSlider.doubleValue = Double(cfg.uploadInFlightMb)
        gdriveInFlightValueLabel.stringValue = "\(cfg.uploadInFlightMb) MB"

        r2AccountIdField.stringValue = cfg.accountId
        r2AccessKeyField.stringValue = cfg.r2AccessKeyId
        r2SecretKeyField.stringValue = cfg.r2SecretAccessKey
        r2BucketField.stringValue = cfg.r2Bucket
        r2PrefixField.stringValue = cfg.r2KeyPrefix
        r2EndpointField.stringValue = cfg.r2Endpoint

        s3EndpointField.stringValue = cfg.s3Endpoint
        s3RegionField.stringValue = cfg.s3Region.isEmpty ? "us-east-1" : cfg.s3Region
        s3BucketField.stringValue = cfg.s3Bucket
        s3PrefixField.stringValue = cfg.s3KeyPrefix
        s3AccessKeyField.stringValue = cfg.s3AccessKeyId
        s3SecretKeyField.stringValue = cfg.s3SecretAccessKey
        s3CaCertField.stringValue = cfg.s3CaCertPath
        s3SignPayloadSwitch.state = cfg.s3SignPayload ? .on : .off
        s3InsecureHttpSwitch.state = cfg.s3AllowInsecureHttp ? .on : .off
        s3InsecureTlsSwitch.state = cfg.s3AllowInsecureTls ? .on : .off

        syncLuasSwitch.state = cfg.syncLuas ? .on : .off
        syncAchievementsSwitch.state = cfg.syncAchievements ? .on : .off
        syncPlaytimeSwitch.state = cfg.syncPlaytime ? .on : .off
        showNonSteamSwitch.state = cfg.showNonSteamGame ? .on : .off
        autoUpdateSwitch.state = cfg.autoUpdateDll ? .on : .off
        parentalBypassSwitch.state = cfg.parentalBypassPlaytime ? .on : .off
        parentalIgnoreSwitch.state = cfg.parentalIgnorePlaytime ? .on : .off

        updateProviderVisibility()
    }

    private func readConfigFromFields() -> CloudRedirectConfig {
        var cfg = currentConfig
        cfg.provider = selectedProvider()

        let rawFolder = folderPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.localFolderPath = rawFolder.isEmpty ? CloudRedirectInstaller.defaultLocalSyncFolder.path : rawFolder
        cfg.uploadInFlightMb = min(64, max(24, Int(gdriveInFlightSlider.doubleValue.rounded())))

        cfg.accountId = r2AccountIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.r2AccessKeyId = r2AccessKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.r2SecretAccessKey = r2SecretKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.r2Bucket = r2BucketField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.r2KeyPrefix = r2PrefixField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.r2Endpoint = r2EndpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        cfg.s3Endpoint = s3EndpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3Region = s3RegionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3Bucket = s3BucketField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3KeyPrefix = s3PrefixField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3AccessKeyId = s3AccessKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3SecretAccessKey = s3SecretKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3CaCertPath = s3CaCertField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.s3SignPayload = (s3SignPayloadSwitch.state == .on)
        cfg.s3AllowInsecureHttp = (s3InsecureHttpSwitch.state == .on)
        cfg.s3AllowInsecureTls = (s3InsecureTlsSwitch.state == .on)

        cfg.syncLuas = (syncLuasSwitch.state == .on)
        cfg.syncAchievements = (syncAchievementsSwitch.state == .on)
        cfg.syncPlaytime = (syncPlaytimeSwitch.state == .on)
        cfg.showNonSteamGame = (showNonSteamSwitch.state == .on)
        cfg.autoUpdateDll = (autoUpdateSwitch.state == .on)
        cfg.parentalBypassPlaytime = (parentalBypassSwitch.state == .on)
        cfg.parentalIgnorePlaytime = (parentalIgnoreSwitch.state == .on)
        return cfg
    }

    private func updateProviderVisibility() {
        let fr = L10n.isFrench
        let prov = selectedProvider()

        localNoteSection.isHidden = (prov != .local)
        folderSection.isHidden = (prov != .folder)
        oauthSection.isHidden = (prov != .gdrive && prov != .onedrive)
        r2Section.isHidden = (prov != .r2)
        s3Section.isHidden = (prov != .s3)
        gdriveInFlightRow.isHidden = (prov != .gdrive)
        testConnButton.isEnabled = (prov != .local) && !isBusy

        if prov == .folder {
            let chosen = folderPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let effective = chosen.isEmpty ? CloudRedirectInstaller.defaultLocalSyncFolder.path : chosen
            winePathHintLabel.stringValue = (fr ? "Chemin CrossOver Wine : " : "CrossOver Wine path: ") + CloudRedirectInstaller.macPathToWinePath(effective)
            let iCloudDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            iCloudButton.isEnabled = FileManager.default.fileExists(atPath: iCloudDir.path)
        } else if prov == .gdrive || prov == .onedrive {
            let isGDrive = (prov == .gdrive)
            oauthDescLabel.stringValue = isGDrive
                ? (fr ? "Connectez votre compte Google pour sauvegarder automatiquement dans Google Drive (dossier CloudRedirect)."
                      : "Sign in with Google to sync saves automatically to Google Drive (CloudRedirect folder).")
                : (fr ? "Connectez votre compte Microsoft pour sauvegarder dans OneDrive (callback local sur le port 53682)."
                      : "Sign in with Microsoft to sync saves to OneDrive (local callback on port 53682).")
            oauthSignInButton.title = isGDrive
                ? (fr ? "Se connecter avec Google" : "Sign in with Google")
                : (fr ? "Se connecter avec Microsoft" : "Sign in with Microsoft")
        }

        updateProviderCredentialPill()
    }

    private func updateProviderCredentialPill() {
        let fr = L10n.isFrench
        let prov = selectedProvider()
        let bottle = CrossOverInstaller.findSteamBottles().first

        switch prov {
        case .local:
            providerStatusPill.update(text: "Local", tint: .secondaryLabelColor)
        case .folder:
            let p = folderPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let exists = !p.isEmpty && FileManager.default.fileExists(atPath: p)
            providerStatusPill.update(text: exists ? (fr ? "Dossier prêt" : "Folder ready") : (fr ? "À créer" : "Will create"), tint: exists ? .systemGreen : .systemOrange)
        case .gdrive, .onedrive:
            let hasTok = bottle.map { CloudRedirectInstaller.hasSavedCredentials(for: prov, in: $0) } ?? false
            providerStatusPill.update(text: hasTok ? (fr ? "Authentifié" : "Authenticated") : (fr ? "Non connecté" : "Not signed in"), tint: hasTok ? .systemGreen : .systemOrange)
            oauthRevokeButton.isEnabled = hasTok && (oauthSession == nil)
        case .r2, .s3:
            let hasCred = bottle.map { CloudRedirectInstaller.hasSavedCredentials(for: prov, in: $0) } ?? false
            providerStatusPill.update(text: hasCred ? (fr ? "Identifiants enregistrés" : "Credentials saved") : (fr ? "Non configuré" : "Not configured"), tint: hasCred ? .systemGreen : .systemOrange)
        }
    }

    private func refreshLocalStatusUI() {
        let fr = L10n.isFrench
        let status = CloudRedirectInstaller.inspectStatus()

        if let bottle = status.bottles.first {
            dashSteamSubtitle.stringValue = "\(bottle.name) — \(bottle.steamDir.path)"
        } else {
            dashSteamSubtitle.stringValue = fr ? "Aucune bouteille Steam CrossOver détectée" : "No CrossOver Steam bottle detected"
        }

        if status.dllInstalled {
            let ver = status.dllVersionHint ?? "v\(CloudRedirectInstaller.bundledVersion)"
            let tomlState = status.cloudEnabledInToml ? (fr ? "[cloud] activé" : "[cloud] enabled") : (fr ? "[cloud] désactivé" : "[cloud] disabled")
            dashDllSubtitle.stringValue = (fr ? "Installée (" : "Installed (") + "\(ver)) · \(tomlState)"
            dashDllBadge.update(text: status.isActive ? (fr ? "Actif" : "Active") : (fr ? "Inactif" : "Inactive"), tint: status.isActive ? .systemGreen : .systemOrange)
        } else {
            dashDllSubtitle.stringValue = fr ? "cloud_redirect.dll non installée" : "cloud_redirect.dll not installed"
            dashDllBadge.update(text: fr ? "Non installée" : "Missing", tint: .systemOrange)
        }

        dashInstallBtn.title = status.dllInstalled
            ? (fr ? "Mettre à jour DLL" : "Update DLL")
            : (fr ? "Installer & Activer DLL" : "Install & Enable DLL")
        dashToggleBtn.title = status.cloudEnabledInToml
            ? (fr ? "Désactiver [cloud]" : "Disable [cloud]")
            : (fr ? "Activer [cloud]" : "Enable [cloud]")

        dashInstallBtn.isEnabled = !isBusy && status.hasBottle
        dashToggleBtn.isEnabled = !isBusy && status.hasBottle && status.dllInstalled
        saveConfigButton.isEnabled = !isBusy && status.hasBottle
        updateProviderCredentialPill()
    }

    private func setBusy(_ busy: Bool, label: String = "", progress: Double = 0) {
        isBusy = busy
        dashProgressBar.isHidden = !busy
        dashProgressLabel.isHidden = !busy
        if busy {
            dashProgressBar.doubleValue = progress * 100
            dashProgressLabel.stringValue = label
        }
        refreshLocalStatusUI()
    }

    // MARK: - Apps, Stats & Migration Renderers

    private func renderAppsTab() {
        let fr = L10n.isFrench
        appsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let snap = snapshot else {
            appsSummaryLabel.stringValue = fr ? "Chargement des sauvegardes…" : "Loading cloud saves…"
            return
        }

        let query = appsSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = snap.apps.filter { app in
            if query.isEmpty { return true }
            let name = (resolvedStoreInfo[app.appId]?.name ?? "").lowercased()
            return name.contains(query) || "\(app.appId)".contains(query) || app.accountId.contains(query)
        }

        let totalBytes = filtered.reduce(Int64(0)) { $0 + $1.totalBytes }
        let totalSizeStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        appsSummaryLabel.stringValue = fr
            ? "\(filtered.count) jeu(x) · \(totalSizeStr)"
            : "\(filtered.count) game(s) · \(totalSizeStr)"

        for (index, app) in filtered.enumerated() {
            let card = NSView()
            card.applyCardSurface()
            card.translatesAutoresizingMaskIntoConstraints = false

            let thumb = SteamArtThumbView(cornerRadius: 6, fallbackSymbolSize: 15)
            thumb.widthAnchor.constraint(equalToConstant: 108).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 50).isActive = true
            thumb.load(headerURL: resolvedStoreInfo[app.appId]?.headerURL)

            let title = NSTextField(labelWithString: resolvedStoreInfo[app.appId]?.name ?? "AppID \(app.appId)")
            title.font = .systemFont(ofSize: 13.5, weight: .semibold)
            title.lineBreakMode = .byTruncatingTail

            let sizeStr = ByteCountFormatter.string(fromByteCount: app.totalBytes, countStyle: .file)
            let locTag = app.isCloud && app.isLocal
                ? "Cloud + Local"
                : (app.isCloud ? "Cloud" : "Local")
            let sub = makeWrappingLabel(
                "\(app.appId) · Compte \(app.accountId) · \(app.fileCount) \(fr ? "fichiers" : "files") · \(sizeStr) · CN: \(app.changeNumber) · \(locTag)",
                font: Typography.caption,
                color: .secondaryLabelColor
            )

            let infoCol = NSStackView(views: [title, sub])
            infoCol.orientation = .vertical
            infoCol.alignment = .leading
            infoCol.spacing = 3

            var rightBtns: [NSView] = []
            if app.localFolderURL != nil {
                let zipBtn = makeButton(title: ".zip", target: self, action: #selector(doExportFilteredApp(_:)))
                zipBtn.tag = index
                let openBtn = makeButton(title: fr ? "Ouvrir" : "Open", target: self, action: #selector(doOpenFilteredApp(_:)))
                openBtn.tag = index
                rightBtns.append(zipBtn)
                rightBtns.append(openBtn)
            }
            let delBtn = NSButton()
            delBtn.bezelStyle = .rounded
            delBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            delBtn.contentTintColor = .systemRed
            delBtn.target = self
            delBtn.action = #selector(doDeleteFilteredApp(_:))
            delBtn.tag = index
            rightBtns.append(delBtn)

            let row = NSStackView(views: [thumb, infoCol, NSView()] + rightBtns)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            ])
            appsListStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: appsListStack.widthAnchor).isActive = true
        }
    }

    private func filteredAppsForUI() -> [CloudAppRecord] {
        guard let snap = snapshot else { return [] }
        let query = appsSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snap.apps.filter { app in
            if query.isEmpty { return true }
            let name = (resolvedStoreInfo[app.appId]?.name ?? "").lowercased()
            return name.contains(query) || "\(app.appId)".contains(query) || app.accountId.contains(query)
        }
    }

    private func renderStatsTab() {
        let fr = L10n.isFrench
        statsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let snap = snapshot else {
            statsSummaryLabel.stringValue = fr ? "Chargement des succès et temps de jeu…" : "Loading achievements & playtime…"
            return
        }

        let query = statsSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = snap.stats.filter { s in
            if query.isEmpty { return true }
            let name = (resolvedStoreInfo[s.appId]?.name ?? "").lowercased()
            return name.contains(query) || "\(s.appId)".contains(query) || s.accountId.contains(query)
        }

        statsSummaryLabel.stringValue = fr
            ? "\(filtered.count) jeu(x) avec statistiques synchronisées"
            : "\(filtered.count) game(s) with synced stats"

        let grouped = Dictionary(grouping: filtered, by: \.accountId)
        for accountId in grouped.keys.sorted() {
            let acctHeader = NSTextField(labelWithString: (fr ? "Compte " : "Account ") + accountId)
            acctHeader.font = .systemFont(ofSize: 15, weight: .bold)
            statsListStack.addArrangedSubview(acctHeader)

            for item in grouped[accountId] ?? [] {
                let key = "\(item.accountId)/\(item.appId)"
                let expanded = expandedStatKeys.contains(key)

                let card = NSView()
                card.applyCardSurface()
                card.translatesAutoresizingMaskIntoConstraints = false

                let expandBtn = NSButton(title: expanded ? "⌄" : "›", target: self, action: #selector(doToggleStatExpand(_:)))
                expandBtn.bezelStyle = .inline
                expandBtn.identifier = NSUserInterfaceItemIdentifier(key)
                expandBtn.widthAnchor.constraint(equalToConstant: 24).isActive = true

                let thumb = SteamArtThumbView(cornerRadius: 6, fallbackSymbolSize: 15)
                thumb.widthAnchor.constraint(equalToConstant: 108).isActive = true
                thumb.heightAnchor.constraint(equalToConstant: 50).isActive = true
                thumb.load(headerURL: resolvedStoreInfo[item.appId]?.headerURL)

                let title = NSTextField(labelWithString: resolvedStoreInfo[item.appId]?.name ?? "AppID \(item.appId)")
                title.font = .systemFont(ofSize: 13.5, weight: .semibold)
                title.lineBreakMode = .byTruncatingTail

                let playtime = Self.formatPlaytime(minutes: item.minutesForever, fr: fr)
                let unlockedCount = item.achievements.filter(\.unlocked).count
                let achPart = unlockedCount > 0 ? " · \(unlockedCount) \(fr ? "succès" : "achievements")" : ""
                let sub = NSTextField(labelWithString: "\(item.appId) · \(playtime)\(achPart)")
                sub.font = Typography.caption
                sub.textColor = .secondaryLabelColor

                let col = NSStackView(views: [title, sub])
                col.orientation = .vertical
                col.alignment = .leading
                col.spacing = 3

                let topRow = NSStackView(views: [expandBtn, thumb, col, NSView()])
                topRow.orientation = .horizontal
                topRow.alignment = .centerY
                topRow.spacing = 10

                var cardViews: [NSView] = [topRow]
                if expanded {
                    let achText: String
                    if item.achievements.isEmpty {
                        achText = fr ? "Aucun succès débloqué enregistré." : "No unlocked achievements recorded."
                    } else {
                        let df = DateFormatter()
                        df.dateStyle = .short
                        df.timeStyle = .short
                        achText = item.achievements.prefix(30).map { a in
                            let dateStr = a.unlockUnix > 0 ? " (" + df.string(from: Date(timeIntervalSince1970: TimeInterval(a.unlockUnix))) + ")" : ""
                            return "• \(a.name)\(dateStr)"
                        }.joined(separator: "\n")
                    }
                    let detailsLbl = makeWrappingLabel(achText, font: Typography.caption, color: .secondaryLabelColor)
                    cardViews.append(detailsLbl)
                }

                let inner = NSStackView(views: cardViews)
                inner.orientation = .vertical
                inner.alignment = .leading
                inner.spacing = 8
                inner.translatesAutoresizingMaskIntoConstraints = false
                topRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

                card.addSubview(inner)
                NSLayoutConstraint.activate([
                    inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                    inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
                    inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                    inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                ])
                statsListStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: statsListStack.widthAnchor).isActive = true
            }
        }
    }

    private func renderMigrationTab() {
        let fr = L10n.isFrench
        migSourceAccountPopup.removeAllItems()
        migTargetAccountPopup.removeAllItems()
        migGamesListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let snap = snapshot else {
            migGamesSummaryLabel.stringValue = "—"
            migAccountCopyBtn.isEnabled = false
            return
        }

        let allAccounts = Array(Set(snap.cloudAccountIds + snap.crossoverAccountIds)).sorted()
        for acc in allAccounts {
            let isXO = snap.crossoverAccountIds.contains(acc)
            let label = isXO ? "\(acc) (CrossOver)" : acc
            migSourceAccountPopup.addItem(withTitle: label)
            migSourceAccountPopup.lastItem?.representedObject = acc
            migTargetAccountPopup.addItem(withTitle: label)
            migTargetAccountPopup.lastItem?.representedObject = acc
        }
        if allAccounts.count >= 2 {
            // Default source = non-CrossOver (e.g. Windows account), target = CrossOver account
            if let srcIdx = allAccounts.firstIndex(where: { !snap.crossoverAccountIds.contains($0) }) {
                migSourceAccountPopup.selectItem(at: srcIdx)
            }
            if let dstIdx = allAccounts.firstIndex(where: { snap.crossoverAccountIds.contains($0) }) {
                migTargetAccountPopup.selectItem(at: dstIdx)
            }
        }
        migAccountCopyBtn.isEnabled = allAccounts.count >= 2 && (snap.provider == .gdrive || snap.provider == .folder)

        let cloudApps = snap.apps.filter(\.isCloud)
        let acctCount = Set(cloudApps.map(\.accountId)).count
        migGamesSummaryLabel.stringValue = fr
            ? "\(cloudApps.count) jeu(x) sur \(acctCount) compte(s) (\(snap.provider.displayName)) :"
            : "\(cloudApps.count) game(s) across \(acctCount) account(s) (\(snap.provider.displayName)):"

        for app in cloudApps.prefix(40) {
            let card = NSView()
            card.applyCardSurface()
            card.translatesAutoresizingMaskIntoConstraints = false

            let thumb = SteamArtThumbView(cornerRadius: 6, fallbackSymbolSize: 15)
            thumb.widthAnchor.constraint(equalToConstant: 108).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 50).isActive = true
            thumb.load(headerURL: resolvedStoreInfo[app.appId]?.headerURL)

            let title = NSTextField(labelWithString: resolvedStoreInfo[app.appId]?.name ?? "AppID \(app.appId)")
            title.font = .systemFont(ofSize: 13.5, weight: .semibold)
            let sub = NSTextField(labelWithString: "\(app.appId) · Compte \(app.accountId)")
            sub.font = Typography.caption
            sub.textColor = .secondaryLabelColor

            let col = NSStackView(views: [title, sub])
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 2

            let row = NSStackView(views: [thumb, col, NSView()])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            ])
            migGamesListStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: migGamesListStack.widthAnchor).isActive = true
        }
    }

    private func reloadToolsTab() {
        let fr = L10n.isFrench
        savedProvidersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let bottle = CrossOverInstaller.findSteamBottles().first

        for kind in [CloudProviderKind.gdrive, .onedrive, .r2, .s3] {
            let ok = bottle.map { CloudRedirectInstaller.hasSavedCredentials(for: kind, in: $0) } ?? false
            savedProvidersStack.addArrangedSubview(PillBadge(
                text: kind.displayName + (ok ? " ✓" : ""),
                tint: ok ? .systemGreen : .secondaryLabelColor
            ))
        }

        let entries = CloudRedirectInstaller.scanUserdata760()
        cloud760ListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if entries.isEmpty {
            cloud760SummaryLabel.stringValue = fr
                ? "Aucune donnée Steam 760 locale résiduelle détectée dans userdata/*/760/remote."
                : "No Steam 760 remote cache folders detected in userdata/*/760/remote."
            clean760Button.isEnabled = false
        } else {
            let bytes = entries.reduce(Int64(0)) { $0 + $1.totalBytes }
            let sizeStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            cloud760SummaryLabel.stringValue = fr
                ? "\(entries.count) dossier(s) AppID dans 760/remote · \(sizeStr)."
                : "\(entries.count) AppID folder(s) in 760/remote · \(sizeStr)."
            clean760Button.isEnabled = true

            for e in entries.prefix(15) {
                let sz = ByteCountFormatter.string(fromByteCount: e.totalBytes, countStyle: .file)
                let lbl = NSTextField(labelWithString: "• \(e.accountId)/760/remote/\(e.appId) — \(e.fileCount) \(fr ? "fichiers" : "files") (\(sz))")
                lbl.font = Typography.caption
                lbl.textColor = .secondaryLabelColor
                cloud760ListStack.addArrangedSubview(lbl)
            }
        }
    }

    // MARK: - Actions

    @objc private func tabChanged() {
        switchTab(to: tabSegment.selectedSegment)
    }

    @objc private func doJumpToMigration() {
        tabSegment.selectedSegment = 5
        switchTab(to: 5)
    }

    @objc private func doRefreshAll() {
        loadAllState()
    }

    @objc private func appsFilterChanged() {
        renderAppsTab()
    }

    @objc private func statsFilterChanged() {
        renderStatsTab()
    }

    @objc private func doToggleStatExpand(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        if expandedStatKeys.contains(key) {
            expandedStatKeys.remove(key)
        } else {
            expandedStatKeys.insert(key)
        }
        renderStatsTab()
    }

    @objc private func providerChanged() {
        updateProviderVisibility()
    }

    @objc private func inFlightSliderChanged() {
        let mb = min(64, max(24, Int(gdriveInFlightSlider.doubleValue.rounded())))
        gdriveInFlightValueLabel.stringValue = "\(mb) MB"
    }

    @objc private func doChooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folderPathField.stringValue = url.path
            updateProviderVisibility()
        }
    }

    @objc private func doUseICloudFolder() {
        let iCloudFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("CloudRedirect Saves", isDirectory: true)
        folderPathField.stringValue = iCloudFolder.path
        updateProviderVisibility()
    }

    @objc private func doOpenSyncFolder() {
        let cfg = readConfigFromFields()
        let url = URL(fileURLWithPath: cfg.localFolderPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func doChooseS3CaCert() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            s3CaCertField.stringValue = url.path
        }
    }

    @objc private func doOAuthSignIn() {
        let prov = selectedProvider()
        guard prov == .gdrive || prov == .onedrive, oauthSession == nil else { return }

        let fr = L10n.isFrench
        let session = CloudRedirectOAuthSession()
        oauthSession = session
        oauthSignInButton.isEnabled = false
        oauthRevokeButton.isEnabled = false
        oauthCancelButton.isHidden = false
        oauthLogLabel.isHidden = false
        oauthLogLabel.stringValue = fr ? "Démarrage OAuth2…" : "Starting OAuth2…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.authorize(provider: prov) { [weak self] line in
                    Task { @MainActor in
                        guard let self else { return }
                        let prev = self.oauthLogLabel.stringValue
                        self.oauthLogLabel.stringValue = prev.isEmpty ? line : prev + "\n" + line
                    }
                }
                try CloudRedirectInstaller.saveOAuthToken(payload, for: prov)
                var cfg = self.readConfigFromFields()
                cfg.provider = prov
                try CloudRedirectInstaller.saveConfig(cfg, validateActiveProviderCredentials: false)
                self.currentConfig = cfg
                self.finishOAuthUI()
                self.loadAllState()
                self.showAlert(
                    title: fr ? "Connexion \(prov.displayName) réussie" : "\(prov.displayName) Connected",
                    message: fr ? "Le jeton OAuth a été enregistré dans votre bouteille CrossOver." : "OAuth tokens saved inside your CrossOver bottle.",
                    style: .informational
                )
            } catch {
                self.finishOAuthUI()
                self.refreshLocalStatusUI()
                if case CloudOAuthError.cancelled = error { return }
                self.showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
            }
        }
    }

    @objc private func doOAuthCancel() { oauthSession?.cancel() }

    @objc private func doOAuthRevoke() {
        let prov = selectedProvider()
        guard prov == .gdrive || prov == .onedrive else { return }
        CloudRedirectInstaller.revokeOAuthToken(for: prov)
        loadAllState()
    }

    private func finishOAuthUI() {
        oauthSession = nil
        oauthSignInButton.isEnabled = true
        oauthCancelButton.isHidden = true
    }

    @objc private func doTestConnection() {
        let fr = L10n.isFrench
        let cfg = readConfigFromFields()
        testConnButton.isEnabled = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.testConnButton.isEnabled = (self.selectedProvider() != .local) && !self.isBusy }
            do {
                if cfg.provider == .r2 || cfg.provider == .s3 || cfg.provider == .folder {
                    try CloudRedirectInstaller.saveConfig(cfg)
                    self.currentConfig = cfg
                }
                let resultMsg = try await CloudRedirectTester.testConnection(config: cfg)
                self.showAlert(title: fr ? "Test réussi" : "Connection OK", message: resultMsg, style: .informational)
            } catch {
                self.showAlert(title: fr ? "Échec du test" : "Connection Failed", message: error.localizedDescription, style: .warning)
            }
        }
    }

    @objc private func doSaveConfig() {
        let fr = L10n.isFrench
        let cfg = readConfigFromFields()
        do {
            try CloudRedirectInstaller.saveConfig(cfg)
            currentConfig = cfg
            loadAllState()
            showAlert(
                title: fr ? "Configuration enregistrée" : "Configuration Saved",
                message: fr ? "config.json et les identifiants ont été enregistrés." : "config.json and provider credentials saved.",
                style: .informational
            )
        } catch {
            showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func doInstallOrUpdate() {
        guard !isBusy else { return }
        let fr = L10n.isFrench
        let cfg = readConfigFromFields()
        do {
            try CloudRedirectInstaller.saveConfig(cfg)
            currentConfig = cfg
        } catch {
            showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
            return
        }

        setBusy(true, label: fr ? "Préparation…" : "Preparing…", progress: 0.05)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let tag = try await CloudRedirectInstaller.installAndEnable(config: cfg) { [weak self] fraction, msg in
                    Task { @MainActor in
                        self?.dashProgressBar.doubleValue = fraction * 100
                        self?.dashProgressLabel.stringValue = msg
                    }
                }
                self.setBusy(false)
                self.loadAllState()
                self.showAlert(
                    title: fr ? "CloudRedirect \(tag) prêt" : "CloudRedirect \(tag) Ready",
                    message: fr ? "Relancez Steam dans CrossOver pour appliquer." : "Restart Steam in CrossOver to apply.",
                    style: .informational
                )
            } catch {
                self.setBusy(false)
                self.showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .critical)
            }
        }
    }

    @objc private func doToggleEnabled() {
        let fr = L10n.isFrench
        let status = CloudRedirectInstaller.inspectStatus()
        let next = !status.cloudEnabledInToml
        do {
            try CloudRedirectInstaller.setEnabled(next)
            refreshLocalStatusUI()
            showAlert(
                title: next ? (fr ? "CloudRedirect activé" : "CloudRedirect Enabled") : (fr ? "CloudRedirect désactivé" : "CloudRedirect Disabled"),
                message: fr ? "opensteamtool.toml mis à jour. Relancez Steam dans CrossOver." : "opensteamtool.toml updated. Restart Steam in CrossOver.",
                style: .informational
            )
        } catch {
            showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func doLaunchCrossOverSteam() {
        CrossOverInstaller.restartCrossOverSteam()
    }

    @objc private func doOpenConfigDir() {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return }
        let dir = CloudRedirectInstaller.appDataDir(in: bottle)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func doExportFilteredApp(_ sender: NSButton) {
        let list = filteredAppsForUI()
        guard sender.tag >= 0 && sender.tag < list.count, let url = list[sender.tag].localFolderURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CloudRedirect-\(list[sender.tag].appId).zip"
        if panel.runModal() == .OK, let dest = panel.url {
            try? CloudRedirectInstaller.exportBackupZip(from: url, to: dest)
        }
    }

    @objc private func doOpenFilteredApp(_ sender: NSButton) {
        let list = filteredAppsForUI()
        guard sender.tag >= 0 && sender.tag < list.count, let url = list[sender.tag].localFolderURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func doDeleteFilteredApp(_ sender: NSButton) {
        let list = filteredAppsForUI()
        guard sender.tag >= 0 && sender.tag < list.count else { return }
        let app = list[sender.tag]
        let fr = L10n.isFrench
        let name = resolvedStoreInfo[app.appId]?.name ?? "AppID \(app.appId)"
        guard confirmDanger(
            title: fr ? "Supprimer \(name) ?" : "Delete \(name)?",
            message: fr
                ? "Supprime les données CloudRedirect pour \(app.accountId)/\(app.appId) (Local\(app.isCloud ? " & Cloud" : ""))."
                : "Removes CloudRedirect data for \(app.accountId)/\(app.appId) (Local\(app.isCloud ? " & Cloud" : ""))."
        ) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let localURL = app.localFolderURL {
                    try FileManager.default.removeItem(at: localURL)
                }
                if app.isCloud {
                    try await CloudRedirectCloudClient.deleteCloudApp(app: app, provider: self.currentConfig.provider)
                }
                self.loadAllState()
            } catch {
                self.showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
            }
        }
    }

    @objc private func doExportAllApps() {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return }
        let storageDir = bottle.steamDir.appendingPathComponent("cloud_redirect/storage", isDirectory: true)
        guard FileManager.default.fileExists(atPath: storageDir.path) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CloudRedirect-AllSaves.zip"
        if panel.runModal() == .OK, let dest = panel.url {
            try? CloudRedirectInstaller.exportBackupZip(from: storageDir, to: dest)
        }
    }

    @objc private func doCopyBetweenAccounts() {
        guard let src = migSourceAccountPopup.selectedItem?.representedObject as? String,
              let dst = migTargetAccountPopup.selectedItem?.representedObject as? String else { return }
        let fr = L10n.isFrench
        guard src != dst else {
            showAlert(title: L10n.tr("common.error"), message: fr ? "Choisissez deux comptes différents." : "Choose two different accounts.", style: .warning)
            return
        }
        guard confirmDanger(
            title: fr ? "Copier les sauvegardes ?" : "Copy cloud saves?",
            message: fr
                ? "Toutes les sauvegardes et statistiques du compte \(src) seront copiées vers \(dst) sur \(currentConfig.provider.displayName)."
                : "All saves and stats from account \(src) will be copied to \(dst) on \(currentConfig.provider.displayName)."
        ) else { return }

        migAccountCopyBtn.isEnabled = false
        migAccountStatusLabel.stringValue = fr ? "Copie en cours…" : "Copying…"
        let cfg = currentConfig

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.migAccountCopyBtn.isEnabled = true }
            do {
                let count = try await CloudRedirectCloudClient.copyCloudSavesBetweenAccounts(config: cfg, from: src, to: dst) { [weak self] msg in
                    Task { @MainActor in
                        self?.migAccountStatusLabel.stringValue = msg
                    }
                }
                self.migAccountStatusLabel.stringValue = fr
                    ? "Copie terminée : \(count) jeu(x) copiés de \(src) vers \(dst)."
                    : "Copy finished: \(count) game(s) copied from \(src) to \(dst)."
                self.loadAllState()
            } catch {
                self.migAccountStatusLabel.stringValue = error.localizedDescription
                self.showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
            }
        }
    }

    @objc private func doResetLocalCache() {
        let fr = L10n.isFrench
        guard confirmDanger(
            title: fr ? "Réinitialiser le cache local ?" : "Reset local cache?",
            message: fr ? "Supprime storage, blobs et saves dans CrossOver Steam." : "Deletes local storage, blobs, and saves in CrossOver Steam."
        ) else { return }
        do {
            _ = try CloudRedirectInstaller.resetLocalStorage()
            loadAllState()
        } catch {
            showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func doRefresh760() { reloadToolsTab() }

    @objc private func doClean760() {
        let fr = L10n.isFrench
        guard confirmDanger(
            title: fr ? "Nettoyer Steam 760 ?" : "Clean Steam 760?",
            message: fr ? "Un backup ZIP de userdata est créé avant suppression." : "A userdata ZIP backup is created before cleanup."
        ) else { return }
        do {
            let res = try CloudRedirectInstaller.cleanAllUserdata760WithBackup()
            reloadToolsTab()
            showAlert(
                title: fr ? "Nettoyage 760 terminé" : "760 Cleanup Complete",
                message: "\(res.cleanedCount) " + (fr ? "dossier(s) nettoyé(s)." : "folder(s) cleaned."),
                style: .informational
            )
        } catch {
            showAlert(title: L10n.tr("common.error"), message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func doOpenLogFile() {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return }
        let url = CloudRedirectInstaller.logFileURL(in: bottle)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc private func doOpenSteamCloudDir() {
        guard let bottle = CrossOverInstaller.findSteamBottles().first else { return }
        let dir = bottle.steamDir.appendingPathComponent("cloud_redirect", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: - Alerts

    private func confirmDanger(title: String, message: String) -> Bool {
        let fr = L10n.isFrench
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: fr ? "Confirmer" : "Confirm")
        alert.addButton(withTitle: fr ? "Annuler" : "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: L10n.tr("common.ok"))
        if let win = view.window {
            alert.beginSheetModal(for: win)
        } else {
            alert.runModal()
        }
    }
}
