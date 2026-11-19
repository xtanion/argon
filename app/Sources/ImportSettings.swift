import AppKit

@MainActor
final class ImportSettingsPane: SettingsPane {
    private let sourcePopUp = SettingsPopUp { _ in }
    private var options = ImportOptions()
    private var sidebarRow: SettingsRow?
    private lazy var sidebarSwitch = SettingsSwitch(isOn: true) { [weak self] in self?.options.sidebar = $0; self?.sync() }
    private lazy var historySwitch = SettingsSwitch(isOn: true) { [weak self] in self?.options.history = $0; self?.sync() }
    private lazy var passwordsSwitch = SettingsSwitch(isOn: true) { [weak self] in self?.options.passwords = $0; self?.sync() }
    private lazy var cookiesSwitch = SettingsSwitch(isOn: true) { [weak self] in self?.options.cookies = $0; self?.sync() }
    private let importButton = SettingsButton("Import", prominent: true)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let note = NSTextField(wrappingLabelWithString: "")

    private var sources: [ImportSource] { ImportSource.allCases.filter(\.isInstalled) }

    private var selected: ImportSource? {
        guard let item = sourcePopUp.selectedItem else { return nil }
        return ImportSource(rawValue: item.representedObject as? String ?? "")
    }

    override func loadView() {
        super.loadView()
        sourcePopUp.onSelect = { [weak self] _ in self?.sync() }

        let source = SettingsCard([
            SettingsRow(title: "Import from",
                        accessory: sourcePopUp),
        ])

        let sidebarRow = SettingsRow(title: "Spaces and tabs", subtitle: "Pinned tabs, folders and favorites", accessory: sidebarSwitch)
        self.sidebarRow = sidebarRow
        for label in [sidebarRow.titleLabel, sidebarRow.subtitleLabel] {
            label.maximumNumberOfLines = 1
            label.cell?.wraps = false
            label.lineBreakMode = .byTruncatingTail
        }
        let what = SettingsCard([
            sidebarRow,
            SettingsRow(title: "History", accessory: historySwitch),
            SettingsRow(title: "Passwords", accessory: passwordsSwitch),
            SettingsRow(title: "Cookies", subtitle: "Stay signed in to sites", accessory: cookiesSwitch),
        ])

        note.preferredMaxLayoutWidth = SettingsStyle.width
        status.preferredMaxLayoutWidth = SettingsStyle.width - 120
        status.maximumNumberOfLines = 3
        note.font = SettingsStyle.subtitle
        note.textColor = .secondaryLabelColor
        status.font = SettingsStyle.subtitle
        status.textColor = .secondaryLabelColor
        importButton.onPress = { [weak self] in self?.startImport() }
        let action = NSStackView(views: [importButton, status])
        action.spacing = 12
        action.alignment = .centerY

        let column = NSStackView.settingsColumn([source, what, action, note])
        view.pinScrolling(column, width: SettingsStyle.width, top: contentInset)
    }

    override func reload() {
        _ = view
        let previous = selected
        sourcePopUp.removeAllItems()
        for source in sources {
            sourcePopUp.addItem(withTitle: source.title)
            sourcePopUp.lastItem?.representedObject = source.rawValue
            if let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
                .map({ NSWorkspace.shared.icon(forFile: $0.path) }) {
                image.size = NSSize(width: 16, height: 16)
                sourcePopUp.lastItem?.image = image
            }
        }
        if sources.isEmpty {
            sourcePopUp.addItem(withTitle: "No browsers found")
            sourcePopUp.isEnabled = false
        } else {
            sourcePopUp.isEnabled = true
            if let previous, let index = sources.firstIndex(of: previous) { sourcePopUp.selectItem(at: index) }
        }
        sync()
    }

    private func sync() {
        let source = selected
        let sidebarText = source == .chrome
            ? ("Bookmarks", "One space per Chrome profile")
            : ("Spaces and tabs", "Pinned tabs, folders and favorites")
        sidebarRow?.titleLabel.stringValue = sidebarText.0
        sidebarRow?.subtitleLabel.stringValue = sidebarText.1
        var lines: [String] = []
        if let source, source.isRunning { lines.append("Quit \(source.title) first.") }
        if let source, options.passwords || options.cookies { lines.append("macOS will ask to allow access to \(source.title)'s saved passwords.") }
        note.stringValue = lines.joined(separator: " ")
        note.isHidden = lines.isEmpty
        let running = BrowserImporter.shared.isRunning
        importButton.isEnabled = source != nil && options.any && !running
        [sourcePopUp, sidebarSwitch, historySwitch, passwordsSwitch, cookiesSwitch].forEach { $0.isEnabled = !running && source != nil }
    }

    private func startImport() {
        guard let source = selected else { return }
        status.textColor = .secondaryLabelColor
        BrowserImporter.shared.run(source, options: options, progress: { [weak self] message in
            self?.status.stringValue = message
            self?.sync()
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let summary):
                self.status.textColor = .labelColor
                self.status.stringValue = ([summary.text] + summary.warnings).joined(separator: " ")
            case .failure(let error):
                self.status.textColor = .systemRed
                self.status.stringValue = error.localizedDescription
            }
            self.sync()
        })
        sync()
    }
}
