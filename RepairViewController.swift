// Repair pane (LuaTools Screenshot 3 style)
import AppKit

final class RepairViewController: NSViewController {

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var stateBadge: PillBadge!
    private var currentBuildPill: PillBadge!
    private var targetBuildPill: PillBadge!

    private var repairButton: NSButton!
    private var openButton: NSButton!
    private var spinner: NSProgressIndicator!

    override func loadView() {
        let scroll = makeScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let fr = L10n.isFrench
        titleLabel = NSTextField(labelWithString: L10n.tr("sidebar.repair"))
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        subtitleLabel = NSTextField(wrappingLabelWithString: fr
            ? "Restaure un client Steam officiel signé par Valve en cas de problème."
            : "Restores a clean Valve-signed Steam bundle if anything goes wrong.")
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = .secondaryLabelColor

        let stateCard = NSView()
        stateCard.applyCardSurface()
        stateCard.translatesAutoresizingMaskIntoConstraints = false

        let cardIcon = NSImageView()
        cardIcon.image = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)
        cardIcon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        cardIcon.contentTintColor = .systemOrange

        let stateHeading = NSTextField(labelWithString: fr ? "État" : "Status")
        stateHeading.font = .systemFont(ofSize: 15, weight: .bold)
        stateBadge = PillBadge(text: "—", tint: .systemPurple)

        let stateTopRow = NSStackView(views: [cardIcon, stateHeading, stateBadge, NSView()])
        stateTopRow.orientation = .horizontal
        stateTopRow.alignment = .centerY
        stateTopRow.spacing = 8

        currentBuildPill = PillBadge(text: "—", tint: .secondaryLabelColor)
        targetBuildPill = PillBadge(text: MacCrab.supportedVersion, symbol: "checkmark.seal", tint: .systemGreen)

        let rowsCard = SettingsCard(rows: [
            SettingRow(title: fr ? "Build Steam actuel" : "Current Steam Build", control: currentBuildPill),
            SettingRow(title: fr ? "Build supporté" : "Supported Build", control: targetBuildPill),
        ])

        repairButton = makeButton(title: fr ? "Réparer Steam" : "Repair Steam", target: self, action: #selector(doRepair))
        repairButton.bezelColor = .controlAccentColor
        repairButton.keyEquivalent = "\r"
        openButton = makeButton(title: fr ? "Ouvrir Steam" : "Open Steam", target: self, action: #selector(openSteam))

        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let btnRow = NSStackView(views: [repairButton, openButton, spinner, NSView()])
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

        let mainStack = NSStackView(views: [titleLabel, subtitleLabel, stateCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.setCustomSpacing(4, after: titleLabel)
        mainStack.setCustomSpacing(16, after: subtitleLabel)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        doc.addSubview(mainStack)
        stateCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

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

    // MARK: - Rendering

    private func refresh() {
        let status = MacCrab.status()
        let steamPresent = status != .steamMissing
        let fr = L10n.isFrench

        if steamPresent {
            switch status {
            case .supported:
                let v = MacCrab.detectedVersion() ?? MacCrab.supportedVersion
                stateBadge.update(text: fr ? "Compatible" : "Supported", tint: .systemGreen)
                currentBuildPill.update(text: v, symbol: "checkmark.circle.fill", tint: .systemGreen)
            case .unsupported(let v):
                stateBadge.update(text: fr ? "Version différente" : "Different build", tint: .systemOrange)
                currentBuildPill.update(text: v, symbol: "exclamationmark.triangle.fill", tint: .systemOrange)
            case .unknown, .steamMissing:
                stateBadge.update(text: fr ? "Inconnu" : "Unknown", tint: .secondaryLabelColor)
                currentBuildPill.update(text: fr ? "Inconnu" : "Unknown", symbol: "questionmark.circle", tint: .secondaryLabelColor)
            }
        } else {
            stateBadge.update(text: fr ? "Steam introuvable" : "Steam missing", tint: .systemRed)
            currentBuildPill.update(text: fr ? "Absent" : "Missing", symbol: "xmark.circle.fill", tint: .systemRed)
        }

        repairButton.isEnabled = steamPresent
        openButton.isEnabled = steamPresent
    }

    // MARK: - Actions

    @objc private func doRepair() {
        let alert = NSAlert()
        alert.messageText = "Reinstall Steam at the latest build?"
        alert.informativeText = "This will remove macSteam and download a clean copy of Steam. "
            + "This can take a few minutes."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Repair")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runRepair()
    }

    @objc private func openSteam() {
        NSWorkspace.shared.open(Paths.steamApp)
    }

    private func runRepair() {
        setBusy(true)
        spinner.startAnimation(nil)
        stateBadge.update(text: "Preparing…", tint: .controlAccentColor)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Void, Error> = Result {
                try MacCrab.repairToStock(progress: { step in
                    DispatchQueue.main.async { self?.stateBadge.update(text: step, tint: .controlAccentColor) }
                })
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimation(nil)
                self.setBusy(false)
                switch result {
                case .success:
                    self.stateBadge.update(text: L10n.isFrench ? "Réparé ✓" : "Repaired ✓", tint: .systemGreen)
                case .failure(let error):
                    if error is SteamInstaller.PermissionDenied {
                        presentAppManagementAlert()
                    } else {
                        presentAlert("Couldn't repair", error.localizedDescription, style: .warning)
                    }
                    self.refresh()
                }
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        repairButton.isEnabled = !busy
        openButton.isEnabled = !busy
    }
}
