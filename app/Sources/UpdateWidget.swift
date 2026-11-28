import AppKit

@MainActor
final class UpdateWidget: SidebarWidget {
    private let notesButton = IconButton(symbol: "doc.text", size: 12, toolTip: "Release Notes")
    private let laterButton = IconButton(symbol: "xmark", size: 11, toolTip: "Remind Me Later")

    override init(frame: NSRect) {
        super.init(frame: frame)
        primaryButton.action = { Updater.shared.apply() }
        notesButton.action = { [weak self] in self?.openReleaseNotes() }
        laterButton.action = { Updater.shared.dismiss() }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .updaterStateDidChange, object: nil)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() {
        var presented = true
        var interactive = false
        var fraction: Double?
        var tip: String?
        switch Updater.shared.state {
        case .idle:
            presented = false
        case .available(let update):
            interactive = true
            titleLabel.stringValue = "Argon \(update.version)"
            primaryButton.title = Updater.shared.canInstallInPlace ? "Install Argon \(update.version)" : "Download Argon \(update.version)"
            primaryButton.setSymbol("arrow.down.circle")
            setAccessories([notesButton, laterButton])
        case .downloading(_, let value):
            fraction = value
            primaryButton.title = "Downloading Update\u{2026} \(Int((value * 100).rounded()))%"
            primaryButton.setSymbol("arrow.down.circle")
        case .preparing:
            primaryButton.title = "Verifying Update\u{2026}"
            primaryButton.setSymbol("checkmark.shield")
        case .restarting:
            primaryButton.title = "Restarting\u{2026}"
            primaryButton.setSymbol("arrow.clockwise")
        case .failed(_, let reason):
            interactive = true
            titleLabel.stringValue = "Update Failed"
            primaryButton.title = "Retry Update"
            primaryButton.setSymbol("arrow.clockwise")
            setAccessories([notesButton, laterButton])
            tip = reason
        }
        primaryButton.isEnabled = interactive
        toolTip = tip
        progress = fraction
        canExpand = interactive
        isPresented = presented
        needsLayout = true
    }

    override func titleClicked() { openReleaseNotes() }

    private func openReleaseNotes() {
        guard let update = Updater.shared.update else { return }
        BrowserWindowController.current?.openTab(update.pageURL)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let update = Updater.shared.update else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Release Notes \u{2014} \(update.version)") { BrowserWindowController.current?.openTab(update.pageURL) })
        if update.downloadURL != nil {
            menu.addItem(ClosureMenuItem("Download Disk Image") {
                BrowserWindowController.current?.openTab(update.downloadURL ?? update.pageURL)
            })
        }
        if canExpand {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Remind Me Later") { Updater.shared.dismiss() })
            menu.addItem(ClosureMenuItem("Skip This Version") { UpdatePrompt.skip(update) })
        }
        return menu
    }
}
