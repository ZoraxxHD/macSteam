// Install pane (LuaTools Screenshot 3 style)
import AppKit

final class InstallViewController: NSViewController {

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var stateBadge: PillBadge!
    private var steamPill: PillBadge!
    private var dylibPill: PillBadge!
    private var updatesPill: PillBadge!

    private var installButton: NSButton!
    private var uninstallButton: NSButton!
    private var updateBlockButton: NSButton!
    private var openButton: NSButton!
    private var spinner: NSProgressIndicator!

    private var bundledDylib: URL? {
        Bundle.main.url(forResource: "macsteam", withExtension: "dylib")
    }

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let fr = L10n.isFrench
        titleLabel = NSTextField(labelWithString: L10n.tr("sidebar.install"))
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        subtitleLabel = NSTextField(wrappingLabelWithString: fr
            ? "Injecte macsteam.dylib dans Steam macOS pour débloquer vos jeux et DLC."
            : "Injects macsteam.dylib into macOS Steam to unlock your configured games and DLCs.")
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = .secondaryLabelColor

        // Main "État" card
        let stateCard = NSView()
        stateCard.applyCardSurface()
        stateCard.translatesAutoresizingMaskIntoConstraints = false

        let cardIcon = NSImageView()
        cardIcon.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)
        cardIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        cardIcon.contentTintColor = .systemGreen

        let stateHeading = NSTextField(labelWithString: fr ? "État" : "Status")
        stateHeading.font = .systemFont(ofSize: 15, weight: .bold)
        stateBadge = PillBadge(text: "—", tint: .systemPurple)

        let stateTopRow = NSStackView(views: [cardIcon, stateHeading, stateBadge, NSView()])
        stateTopRow.orientation = .horizontal
        stateTopRow.alignment = .centerY
        stateTopRow.spacing = 8

        steamPill = PillBadge(text: "—", tint: .secondaryLabelColor)
        dylibPill = PillBadge(text: "—", tint: .secondaryLabelColor)
        updatesPill = PillBadge(text: "—", tint: .secondaryLabelColor)

        let rowsCard = SettingsCard(rows: [
            SettingRow(title: fr ? "Client Steam macOS" : "macOS Steam Client", control: steamPill),
            SettingRow(title: "macsteam.dylib", control: dylibPill),
            SettingRow(title: fr ? "Blocage mises à jour" : "Auto-Update Block", control: updatesPill),
        ])

        installButton = makeButton(title: "Install", target: self, action: #selector(doInstall))
        installButton.bezelColor = .controlAccentColor
        installButton.keyEquivalent = "\r"
        uninstallButton = makeButton(title: "Uninstall", target: self, action: #selector(doUninstall))
        updateBlockButton = makeButton(title: "Allow Updates", target: self, action: #selector(toggleUpdateBlock))
        openButton = makeButton(title: fr ? "Ouvrir Steam" : "Open Steam", target: self, action: #selector(openSteam))

        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let btnRow = NSStackView(views: [installButton, uninstallButton, updateBlockButton, openButton, spinner, NSView()])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        let cardStack = NSStackView(views: [stateTopRow, rowsCard, btnRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        rowsCard.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        btnRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        stateCard.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: stateCard.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: stateCard.bottomAnchor, constant: -16),
            cardStack.leadingAnchor.constraint(equalTo: stateCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: stateCard.trailingAnchor, constant: -16),
        ])

        let featuresHeader = settingsGroupLabel(fr ? "Fonctionnalités notables" : "Notable Features")
        let f1 = makeInstallFeatureCard(
            symbol: "bolt.shield.fill",
            tint: .systemPurple,
            text: fr ? "Débloque les jeux et DLC directement au démarrage de Steam" : "Unlocks configured games and DLCs automatically when Steam launches"
        )
        let f2 = makeInstallFeatureCard(
            symbol: "lock.shield.fill",
            tint: .systemPurple,
            text: fr ? "Empêche les mises à jour automatiques de Steam via steam.cfg" : "Blocks Steam client self-updates automatically via steam.cfg"
        )
        let f3 = makeInstallFeatureCard(
            symbol: "arrow.down.circle.fill",
            tint: .systemPurple,
            text: fr ? "Récupère les codes de manifests via OpenSteamTool, wudrm et steam.run" : "Fetches manifest request codes via OpenSteamTool, wudrm, and steam.run"
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
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    // MARK: - Status rendering

    private func refresh() {
        let status = SteamInstaller.status()
        let hasPayload = (bundledDylib != nil)
        let blockOn = SteamInstaller.updateBlockEnabled()
        let fr = L10n.isFrench

        if status == .steamMissing {
            steamPill.update(text: fr ? "Absent" : "Missing", symbol: "xmark.circle.fill", tint: .systemRed)
        } else {
            let build = MacCrab.detectedVersion() ?? "—"
            steamPill.update(text: "Build \(build)", symbol: "checkmark.circle.fill", tint: .systemGreen)
        }

        switch status {
        case .installed:
            let ver = SteamInstaller.deployedDylibVersion() ?? "0.7.1"
            stateBadge.update(text: fr ? "Installé" : "Installed", tint: .systemGreen)
            dylibPill.update(text: "v\(ver)", symbol: "checkmark.circle.fill", tint: .systemGreen)
            installButton.title = fr ? "Réinstaller" : "Reinstall"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .outdated(let bundled, _):
            stateBadge.update(text: fr ? "Mise à jour dispo" : "Update available", tint: .systemOrange)
            dylibPill.update(text: "v\(bundled) available", symbol: "arrow.up.circle.fill", tint: .systemOrange)
            installButton.title = fr ? "Mettre à jour" : "Update"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .notInstalled:
            stateBadge.update(text: fr ? "Non installé" : "Not installed", tint: .systemOrange)
            dylibPill.update(text: fr ? "Non injecté" : "Not injected", symbol: "minus.circle", tint: .secondaryLabelColor)
            installButton.title = fr ? "Installer" : "Install"
            uninstallButton.isEnabled = false
            openButton.isEnabled = true
        case .foreign:
            stateBadge.update(text: "Foreign", tint: .systemOrange)
            dylibPill.update(text: "Foreign", symbol: "exclamationmark.triangle.fill", tint: .systemOrange)
            installButton.title = fr ? "Installer" : "Install"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .steamMissing:
            stateBadge.update(text: fr ? "Steam introuvable" : "Steam missing", tint: .systemRed)
            dylibPill.update(text: "—", symbol: "minus.circle", tint: .secondaryLabelColor)
            installButton.title = fr ? "Installer" : "Install"
            uninstallButton.isEnabled = false
            openButton.isEnabled = false
        }

        updatesPill.update(
            text: blockOn ? (fr ? "Bloqué ✓" : "Blocked ✓") : (fr ? "Autorisé" : "Allowed"),
            symbol: blockOn ? "lock.shield.fill" : "exclamationmark.shield",
            tint: blockOn ? .systemGreen : .systemOrange
        )

        updateBlockButton.title = blockOn ? (fr ? "Autoriser MÀJ" : "Allow Updates") : (fr ? "Bloquer MÀJ" : "Block Updates")
        switch status {
        case .installed, .outdated: updateBlockButton.isEnabled = true
        default: updateBlockButton.isEnabled = false
        }

        installButton.isEnabled = hasPayload && status != .steamMissing
    }

    private func buildIsOlder(_ lhs: String, than rhs: String) -> Bool {
        guard let l = Int(lhs), let r = Int(rhs) else { return false }
        return l < r
    }

    // MARK: - Actions

    @objc private func doInstall() {
        guard let dylib = bundledDylib else { return }

        switch MacCrab.status() {
        case .unsupported(let version):
            promptVersionFix(currentBuild: version, dylib: dylib)
        default:
            runInstall(dylib: dylib, pinFirst: false)
        }
    }

    private func promptVersionFix(currentBuild: String, dylib: URL) {
        let tooOld = buildIsOlder(currentBuild, than: MacCrab.supportedVersion)
        let alert = NSAlert()
        alert.alertStyle = .warning
        if tooOld {
            alert.messageText = "Steam version is older than the supported version"
            alert.informativeText = "Your Steam client is on a build of Steam that is older "
                + "than the build that macSteam supports. This installer can upgrade you to the "
                + "latest supported version of Steam, or you can install on your current "
                + "build\u{2026}at your own risk."
            alert.addButton(withTitle: "Update and Install")
        } else {
            alert.messageText = "Steam version is newer than the supported version!"
            alert.informativeText = "Your Steam client is on a build of Steam that is newer "
                + "than the build that macSteam supports! This installer can downgrade you to "
                + "the latest supported version of Steam, or you can install anyway on your "
                + "current build\u{2026}at your own risk."
            alert.addButton(withTitle: "Downgrade and Install")
        }
        alert.addButton(withTitle: "Install Anyway")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  runInstall(dylib: dylib, pinFirst: true)
        case .alertSecondButtonReturn: runInstall(dylib: dylib, pinFirst: false)
        default: return
        }
    }

    private func runInstall(dylib: URL, pinFirst: Bool) {
        runBusy(verb: L10n.isFrench ? "Installation" : "Installing") {
            switch SteamInstaller.status() {
            case .installed, .outdated:
                try SteamInstaller.install(sourceDylib: dylib)
            default:
                try MacCrab.ensurePristineBundle()
                if pinFirst { try MacCrab.pinToSupported() }
                try SteamInstaller.install(sourceDylib: dylib)
            }
        }
    }

    @objc private func doUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall macSteam from Steam?"
        alert.informativeText = "This downloads a clean, Valve-signed Steam and replaces the "
            + "installed one, removing macSteam completely. Takes a few minutes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runBusy(verb: "Uninstalling") { try MacCrab.uninstallToStock() }
    }

    @objc private func toggleUpdateBlock() {
        guard SteamInstaller.updateBlockEnabled() else {
            runBusy { try SteamInstaller.enableUpdateBlock() }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow Steam to update?"
        alert.informativeText = "macSteam blocks the Steam client from updating the client "
            + "itself. If you disable this behavior, a future Steam update will break macSteam "
            + "until macSteam is updated to match. You have been warned."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runBusy { try SteamInstaller.disableUpdateBlock() }
    }

    @objc private func openSteam() {
        NSWorkspace.shared.open(Paths.steamApp)
    }

    private func runBusy(verb: String = "Working", _ work: @escaping @Sendable () throws -> Void) {
        stateBadge.update(text: "\(verb)…", tint: .controlAccentColor)

        MacsteamApp.runBusy(spinner: spinner, setBusy: { [self] busy in
            installButton.isEnabled = !busy && bundledDylib != nil
            uninstallButton.isEnabled = !busy
            updateBlockButton.isEnabled = !busy
            openButton.isEnabled = !busy
        }, refresh: { [self] in refresh() }, work: work)
    }
}

@MainActor
private func makeInstallFeatureCard(symbol: String, tint: NSColor, text: String) -> NSView {
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
