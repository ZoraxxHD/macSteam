// CrossOver (Windows Steam) dedicated pane (LuaTools Screenshot 3 style + loading bar)
import AppKit

final class CrossOverViewController: NSViewController {

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var stateBadge: PillBadge!
    private var bottlePill: PillBadge!
    private var bstPill: PillBadge!
    private var syncedPill: PillBadge!
    private var progressBar: NSProgressIndicator!
    private var progressLabel: NSTextField!
    private var launchButton: NSButton!
    private var syncButton: NSButton!
    private var installButton: NSButton!

    private var isBusy = false

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let fr = L10n.isFrench
        titleLabel = NSTextField(labelWithString: L10n.tr("sidebar.crossover"))
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        subtitleLabel = NSTextField(wrappingLabelWithString: fr
            ? "Jouez aux jeux exclusifs Windows via votre bouteille Steam dans CrossOver."
            : "Play Windows-only games through your Steam bottle inside CrossOver.")
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = .secondaryLabelColor

        // Main "État" card
        let stateCard = NSView()
        stateCard.applyCardSurface()
        stateCard.translatesAutoresizingMaskIntoConstraints = false

        let cardIcon = NSImageView()
        cardIcon.image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: nil)
        cardIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        cardIcon.contentTintColor = .systemPurple

        let stateHeading = NSTextField(labelWithString: fr ? "État" : "Status")
        stateHeading.font = .systemFont(ofSize: 15, weight: .bold)
        stateBadge = PillBadge(text: "—", tint: .systemPurple)

        let stateTopRow = NSStackView(views: [cardIcon, stateHeading, stateBadge, NSView()])
        stateTopRow.orientation = .horizontal
        stateTopRow.alignment = .centerY
        stateTopRow.spacing = 8

        bottlePill = PillBadge(text: "—", tint: .secondaryLabelColor)
        bstPill = PillBadge(text: "—", tint: .secondaryLabelColor)
        syncedPill = PillBadge(text: "0", tint: .controlAccentColor)

        let rowsCard = SettingsCard(rows: [
            SettingRow(title: fr ? "Bouteille CrossOver" : "CrossOver Bottle", control: bottlePill),
            SettingRow(title: "BetterSteamTools", control: bstPill),
            SettingRow(title: fr ? "Jeux Lua synchronisés" : "Synced Lua Games", control: syncedPill),
        ])

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        progressLabel = NSTextField(labelWithString: "")
        progressLabel.font = Typography.caption
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.isHidden = true
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        launchButton = makeButton(title: "", target: self, action: #selector(doLaunch))
        launchButton.bezelColor = .controlAccentColor
        launchButton.keyEquivalent = "\r"
        syncButton = makeButton(title: "", target: self, action: #selector(doSync))
        installButton = makeButton(title: "", target: self, action: #selector(doInstall))

        let btnRow = NSStackView(views: [launchButton, syncButton, installButton, NSView()])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        let cardStack = NSStackView(views: [stateTopRow, rowsCard, progressBar, progressLabel, btnRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 10
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        rowsCard.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        progressBar.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        btnRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        stateCard.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: stateCard.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: stateCard.bottomAnchor, constant: -16),
            cardStack.leadingAnchor.constraint(equalTo: stateCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: stateCard.trailingAnchor, constant: -16),
        ])

        let featuresHeader = settingsGroupLabel(fr ? "Fonctionnalités notables" : "Notable Features")
        let f1 = makeCrossOverFeatureCard(
            symbol: "shippingbox.fill",
            tint: .systemPurple,
            text: fr ? "Détecte automatiquement votre bouteille Steam Windows dans CrossOver" : "Automatically detects your Windows Steam bottle inside CrossOver"
        )
        let f2 = makeCrossOverFeatureCard(
            symbol: "gearshape.2.fill",
            tint: .systemPurple,
            text: fr ? "Déploie BetterSteamTools et configure les surcharges Wine (dwmapi / xinput1_4)" : "Deploys BetterSteamTools and configures Wine DLL overrides automatically"
        )
        let f3 = makeCrossOverFeatureCard(
            symbol: "arrow.triangle.2.circlepath",
            tint: .systemPurple,
            text: fr ? "Synchronise vos fichiers .lua automatiquement à chaque ajout de jeu" : "Syncs your .lua game files automatically whenever you add or edit games"
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

    private func refresh() {
        guard !isBusy else { return }

        let fr = L10n.isFrench
        let synced = CrossOverInstaller.syncedLuaCount()
        let status = CrossOverInstaller.status()
        let running = CrossOverInstaller.isCrossOverSteamRunning()
        launchButton.title = running
            ? (fr ? "Relancer CrossOver Steam" : "Restart CrossOver Steam")
            : (fr ? "Lancer CrossOver Steam" : "Launch CrossOver Steam")
        syncButton.title = fr ? "Synchroniser les jeux" : "Sync Games"
        syncedPill.update(
            text: "\(synced) " + (fr ? "jeu(x)" : "game(s)"),
            symbol: "gamecontroller.fill",
            tint: synced > 0 ? .controlAccentColor : .secondaryLabelColor
        )

        switch status {
        case .noCrossOver:
            stateBadge.update(text: fr ? "Introuvable" : "Not found", tint: .systemRed)
            bottlePill.update(text: fr ? "Introuvable" : "Not found", symbol: "xmark.circle", tint: .systemRed)
            bstPill.update(text: "—", tint: .secondaryLabelColor)
            installButton.title = fr ? "Installer" : "Install"
            installButton.isEnabled = false
            syncButton.isEnabled = false
            launchButton.isEnabled = false

        case .notInstalled(let bottle):
            stateBadge.update(text: fr ? "Non configuré" : "Not configured", tint: .systemOrange)
            bottlePill.update(text: bottle, symbol: "shippingbox.fill", tint: .controlAccentColor)
            bstPill.update(text: fr ? "Non installé" : "Not installed", symbol: "minus.circle", tint: .systemOrange)
            installButton.title = fr ? "Installer" : "Install"
            installButton.isEnabled = true
            syncButton.isEnabled = false
            launchButton.isEnabled = true

        case .installed(let bottle):
            stateBadge.update(
                text: running ? (fr ? "En cours" : "Running") : (fr ? "Prêt" : "Ready"),
                tint: .systemGreen
            )
            bottlePill.update(text: bottle, symbol: "shippingbox.fill", tint: .systemGreen)
            bstPill.update(text: fr ? "Configuré ✓" : "Configured ✓", symbol: "checkmark.circle.fill", tint: .systemGreen)
            installButton.title = fr ? "Réinstaller" : "Reinstall"
            installButton.isEnabled = true
            syncButton.isEnabled = true
            launchButton.isEnabled = true
        }
    }

    private func setBusy(_ busy: Bool, message: String = "", progress: Double = 0) {
        isBusy = busy
        launchButton.isEnabled = !busy
        syncButton.isEnabled = !busy
        installButton.isEnabled = !busy
        progressBar.isHidden = !busy
        progressLabel.isHidden = !busy
        if busy {
            progressBar.doubleValue = progress
            progressLabel.stringValue = message
        } else {
            progressBar.doubleValue = 0
            progressLabel.stringValue = ""
            refresh()
        }
    }

    @objc private func doLaunch() {
        guard !isBusy else { return }
        let fr = L10n.isFrench
        setBusy(true, message: fr ? "Synchronisation des jeux…" : "Syncing games…", progress: 15)

        Task { [weak self] in
            let alreadyRunning = await Task.detached {
                CrossOverInstaller.syncLuaFiles()
                return CrossOverInstaller.isCrossOverSteamRunning()
            }.value

            guard let self else { return }
            self.progressBar.doubleValue = 35
            self.progressLabel.stringValue = alreadyRunning
                ? (fr ? "Fermeture de Steam macOS et redémarrage de CrossOver Steam…" : "Closing macOS Steam & restarting CrossOver Steam…")
                : (fr ? "Fermeture de Steam macOS et lancement de CrossOver Steam…" : "Closing macOS Steam & launching CrossOver Steam…")

            if alreadyRunning {
                CrossOverInstaller.restartCrossOverSteam()
            } else {
                CrossOverInstaller.openCrossOverSteam(closeMacSteam: true)
            }

            let maxTicks = alreadyRunning ? 24 : 24
            for tick in 1...maxTicks {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let pct = 35.0 + (Double(tick) / Double(maxTicks)) * 65.0
                let running = await Task.detached { CrossOverInstaller.isCrossOverSteamRunning() }.value
                self.progressBar.doubleValue = pct
                if running {
                    self.progressLabel.stringValue = fr ? "CrossOver Steam démarré !" : "CrossOver Steam started!"
                }
                if running && tick >= 4 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    break
                }
            }

            self.setBusy(false)
        }
    }

    @objc private func doSync() {
        guard !isBusy else { return }
        let fr = L10n.isFrench
        setBusy(true, message: fr ? "Synchronisation vers CrossOver…" : "Syncing to CrossOver…", progress: 40)

        Task { [weak self] in
            await Task.detached {
                CrossOverInstaller.syncLuaFiles()
                try? await Task.sleep(nanoseconds: 350_000_000)
            }.value
            guard let self else { return }
            self.progressBar.doubleValue = 100
            self.setBusy(false)
        }
    }

    @objc private func doInstall() {
        guard !isBusy else { return }
        let fr = L10n.isFrench
        setBusy(true, message: fr ? "Installation de BetterSteamTools…" : "Installing BetterSteamTools…", progress: 20)

        Task { [weak self] in
            weak var vc = self
            do {
                try await Task.detached {
                    try CrossOverInstaller.install { step in
                        Task { @MainActor in
                            guard let vc else { return }
                            vc.progressLabel.stringValue = step
                            vc.progressBar.doubleValue = min(90, vc.progressBar.doubleValue + 18)
                        }
                    }
                }.value
                guard let self else { return }
                self.progressBar.doubleValue = 100
                self.setBusy(false)
            } catch {
                guard let self else { return }
                self.setBusy(false)
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = fr ? "Échec de l'installation" : "Installation failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

@MainActor
private func makeCrossOverFeatureCard(symbol: String, tint: NSColor, text: String) -> NSView {
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
