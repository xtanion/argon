import AppKit

let contentInset: CGFloat = 24

// MARK: General

@MainActor
final class GeneralSettingsPane: SettingsPane {
    private let chip = DefaultBrowserChip()
    private let folderPopUp = SettingsPopUp { _ in }

    override func loadView() {
        super.loadView()
        chip.onMakeDefault = { [weak self] in
            DefaultBrowser.makeDefault { self?.reload() }
        }

        let quitting = SettingsCard([
            SettingsRow(title: "Warn before quitting", subtitle: "Press \u{2318}Q twice to quit Argon.",
                        badge: SettingsStyle.badge("power", color: .systemRed),
                        accessory: SettingsSwitch(isOn: Preferences.warnBeforeQuitting) { Preferences.warnBeforeQuitting = $0 }),
            SettingsRow(title: "Show sidebar on launch", subtitle: "Turn off to start with the sidebar hidden.",
                        badge: SettingsStyle.badge("sidebar.left", color: .systemBlue),
                        accessory: SettingsSwitch(isOn: Preferences.showSidebarOnLaunch) { Preferences.showSidebarOnLaunch = $0 }),
        ])

        let media = SettingsCard([
            SettingsRow(title: "Automatic Picture in Picture",
                        subtitle: "Videos keep playing in a floating window when you switch tabs or Spaces. Turn it off for one site from its site controls.",
                        badge: SettingsStyle.badge("pip.fill", color: .systemPink),
                        accessory: SettingsSwitch(isOn: Preferences.autoPictureInPicture) { Preferences.autoPictureInPicture = $0 },
                        wraps: true),
        ])

        folderPopUp.onSelect = { [weak self] item in self?.folderChosen(item) }
        let capture = SettingsCard([
            SettingsRow(title: "Save screenshots to", subtitle: "Used by Capture Page when you save the image.",
                        badge: SettingsStyle.badge("camera.viewfinder", color: .systemPurple), accessory: folderPopUp),
        ])

        let updates = SettingsCard([
            SettingsRow(title: "Check for updates automatically", subtitle: "Argon looks for new releases on GitHub every few hours.",
                        badge: SettingsStyle.badge("arrow.down.circle.fill", color: .systemTeal),
                        accessory: SettingsSwitch(isOn: Preferences.checkForUpdates) { Preferences.checkForUpdates = $0 }),
        ])

        let profile = SettingsCard([
            SettingsRow(title: "Search engine, passwords, site settings and downloads are set per profile.",
                        badge: SettingsStyle.badge("person.crop.circle.fill", color: .systemGreen),
                        accessory: SettingsButton("Spaces and Profiles\u{2026}") { SettingsWindowController.shared.select(.spaces) },
                        wraps: true),
        ])

        let column = NSStackView.settingsColumn([chip, quitting, updates, media, capture, profile])
        column.setCustomSpacing(20, after: chip)
        view.pinCentered(column, width: SettingsStyle.width, top: contentInset)

        let footer = makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
        ])
    }

    override func reload() {
        _ = view
        chip.isHidden = DefaultBrowser.isDefault
        rebuildFolderMenu()
    }

    private func makeFooter() -> NSView {
        var parts = ["Argon " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")]
        if let chromium = Self.chromiumVersion { parts.append("Chromium " + chromium) }
        let label = NSTextField(labelWithString: parts.joined(separator: "  \u{00B7}  "))
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .tertiaryLabelColor
        let link = SettingsButton("Chromium Settings\u{2026}") { [weak self] in
            self?.browser?.openChromePage("settings", profile: nil)
        }
        link.bezelStyle = .inline
        link.isBordered = false
        link.contentTintColor = .secondaryLabelColor
        link.font = .systemFont(ofSize: 11.5)
        let stack = NSStackView(views: [label, link])
        stack.spacing = 10
        return stack
    }

    private static var chromiumVersion: String? {
        guard let frameworks = Bundle.main.privateFrameworksURL,
              let bundle = Bundle(url: frameworks.appendingPathComponent("Chromium Framework.framework")) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func rebuildFolderMenu() {
        let menu = NSMenu()
        let current = Preferences.screenshotFolder
        menu.addItem(folderItem(current))
        menu.addItem(.separator())
        let downloads = Preferences.defaultScreenshotFolder
        if current.standardizedFileURL != downloads.standardizedFileURL {
            menu.addItem(folderItem(downloads))
        }
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
           current.standardizedFileURL != desktop.standardizedFileURL {
            menu.addItem(folderItem(desktop))
        }
        menu.addItem(withTitle: "Other\u{2026}", action: nil, keyEquivalent: "")
        folderPopUp.menu = menu
        folderPopUp.select(menu.items.first)
    }

    private func folderItem(_ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: FileManager.default.displayName(atPath: url.path), action: nil, keyEquivalent: "")
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        item.representedObject = url
        return item
    }

    private func folderChosen(_ item: NSMenuItem) {
        if let url = item.representedObject as? URL {
            Preferences.screenshotFolder = url
            rebuildFolderMenu()
            return
        }
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Preferences.screenshotFolder
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if response == .OK, let url = panel.url { Preferences.screenshotFolder = url }
                self?.rebuildFolderMenu()
            }
        }
    }
}

@MainActor
final class DefaultBrowserChip: NSView {
    var onMakeDefault: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let surface = SettingsSurface()
        surface.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "Argon isn\u{2019}t your default browser")
        label.font = SettingsStyle.title
        label.textColor = .secondaryLabelColor
        let button = SettingsButton("Set as Default", prominent: true) { [weak self] in self?.onMakeDefault?() }
        button.controlSize = .small
        let stack = NSStackView(views: [label, button])
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            surface.centerXAnchor.constraint(equalTo: centerXAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])
        surface.radius = 19
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: Spaces and Profiles

@MainActor
final class SpacesSettingsPane: SettingsPane, NSTextFieldDelegate {
    private static let pages: [(title: String, symbol: String, color: NSColor, host: String, path: String)] = [
        ("Privacy and Security", "lock.fill", .systemBlue, "settings", "/privacy"),
        ("Passwords", "key.fill", .systemGreen, "password-manager", "/passwords"),
        ("Autofill and Payments", "creditcard.fill", .systemYellow, "settings", "/autofill"),
        ("Site Settings", "slider.horizontal.3", .systemIndigo, "settings", "/content"),
        ("Downloads", "arrow.down", .systemTeal, "settings", "/downloads"),
        ("Extensions", "puzzlepiece.extension.fill", .systemPurple, "extensions", ""),
        ("History", "clock.fill", .systemOrange, "history", ""),
        ("Clear Browsing Data", "trash.fill", .systemRed, "settings", "/clearBrowserData"),
    ]

    private let list = SettingsList<Space>(title: "Your Spaces")
    private let nameField = NSTextField()
    private let iconButton = SettingsButton("")
    private let themeButton = SettingsButton("")
    private let profilePopUp = SettingsPopUp { _ in }
    private let profileRow: SettingsRow
    private let searchRow: SettingsRow
    private let removeButton = NSButton()
    private let scroll = NSScrollView()

    private var selectedSpace: Space? {
        guard let index = list.selectedIndex, list.items.indices.contains(index) else { return nil }
        return list.items[index]
    }

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        profileRow = SettingsRow(title: "Profile", subtitle: "", accessory: profilePopUp)
        searchRow = SettingsRow(title: "Search engine", subtitle: "", accessory: SettingsButton("Search Settings\u{2026}"))
        super.init(nibName: nibName, bundle: bundle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        let intro = NSTextField(wrappingLabelWithString:
            "Each Space uses a Profile, which keeps history, logins, cookies and extensions separate. Several Spaces can share one Profile.")
        intro.font = SettingsStyle.title
        intro.textColor = .secondaryLabelColor

        list.render = { space in (space.name, nil, SettingsStyle.badge(for: space, size: 20)) }
        list.onSelect = { [weak self] _ in self?.refreshDetail() }
        let add = Self.footerButton("plus", toolTip: "New Space") { [weak self] in self?.addSpace() }
        Self.configureFooterButton(removeButton, symbol: "minus", toolTip: "Delete Space")
        removeButton.target = self
        removeButton.action = #selector(removeSpace)
        list.setFooter([add, removeButton])

        nameField.bezelStyle = .roundedBezel
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(commitName)
        nameField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        iconButton.imagePosition = .imageOnly
        iconButton.onPress = { [weak self] in self?.showIconPicker() }
        iconButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        themeButton.imagePosition = .imageLeading
        themeButton.onPress = { [weak self] in self?.showThemeEditor() }
        profilePopUp.onSelect = { [weak self] item in self?.profileChosen(item) }
        let searchButton = searchRow.subviews.compactMap { $0 as? SettingsButton }.first
        searchButton?.onPress = { [weak self] in self?.open("settings", path: "/search") }

        let links = Self.pages.map { page in
            SettingsLinkRow(title: page.title, symbol: page.symbol, color: page.color) { [weak self] in
                self?.open(page.host, path: page.path)
            }
        }
        let spaceHeader = SettingsSectionHeader("Space")
        let profileHeader = SettingsSectionHeader("Profile")
        let dataHeader = SettingsSectionHeader("Your Data and Settings")
        let column = NSStackView.settingsColumn([
            spaceHeader,
            SettingsCard([
                SettingsRow(title: "Name", accessory: nameField),
                SettingsRow(title: "Icon", accessory: iconButton),
                SettingsRow(title: "Theme", accessory: themeButton),
            ]),
            profileHeader,
            SettingsCard([profileRow, searchRow]),
            dataHeader,
            SettingsCard(links),
        ], spacing: 8)
        column.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        for (header, gap) in [(spaceHeader, CGFloat(0)), (profileHeader, 18), (dataHeader, 18)] {
            header.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: SettingsStyle.rowInset).isActive = true
            if let index = column.arrangedSubviews.firstIndex(of: header), index > 0 {
                column.setCustomSpacing(gap, after: column.arrangedSubviews[index - 1])
            }
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        for view in [intro, list, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInset),
            intro.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInset),
            intro.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInset),
            list.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 16),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -contentInset),
            list.widthAnchor.constraint(equalToConstant: 220),
            scroll.leadingAnchor.constraint(equalTo: list.trailingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInset),
            scroll.topAnchor.constraint(equalTo: list.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: document.topAnchor),
            column.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }

    override func reload() {
        _ = view
        guard let browser else { return }
        let previous = selectedSpace
        list.items = browser.spaces
        list.selectedIndex = previous.flatMap { space in browser.spaces.firstIndex { $0 === space } }
            ?? (browser.spaces.isEmpty ? nil : browser.activeIndex)
        refreshDetail()
    }

    private func reloadList() {
        guard let browser else { return }
        let selected = list.selectedIndex
        list.items = browser.spaces
        list.selectedIndex = selected.map { min($0, browser.spaces.count - 1) }
    }

    private func refreshDetail() {
        guard let space = selectedSpace else {
            scroll.isHidden = true
            return
        }
        scroll.isHidden = false
        if nameField.currentEditor() == nil { nameField.stringValue = space.name }
        if let image = Self.icon(for: space, size: 15) {
            iconButton.image = image
            iconButton.title = ""
            iconButton.imagePosition = .imageOnly
        } else {
            iconButton.image = nil
            iconButton.title = "None"
            iconButton.imagePosition = .noImage
        }
        themeButton.image = Self.swatch(space.frameColor)
        themeButton.title = space.customColor?.hexString ?? "Default"
        rebuildProfileMenu(for: space)
        let others = (browser?.spaces ?? []).filter { $0 !== space && $0.profileIdentifier == space.profileIdentifier }
        profileRow.subtitleLabel.stringValue = others.isEmpty
            ? "Only this Space uses it."
            : "Shared with " + ListFormatter.localizedString(byJoining: others.map(\.name)) + "."
        profileRow.subtitleLabel.isHidden = false
        searchRow.subtitleLabel.stringValue = space.profile?.searchEngineName ?? "Unknown"
        searchRow.subtitleLabel.isHidden = false
        removeButton.isEnabled = (browser?.spaces.count ?? 0) > 1
    }

    private func rebuildProfileMenu(for space: Space) {
        guard let browser else { return }
        let menu = NSMenu()
        var order: [String] = []
        var names: [String: [String]] = [:]
        for other in browser.spaces {
            if names[other.profileIdentifier] == nil { order.append(other.profileIdentifier) }
            names[other.profileIdentifier, default: []].append(other.name)
        }
        for identifier in order {
            let item = menu.addItem(withTitle: names[identifier, default: []].joined(separator: ", "), action: nil, keyEquivalent: "")
            item.representedObject = identifier
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Profile", action: nil, keyEquivalent: "")
        profilePopUp.menu = menu
        profilePopUp.select(menu.items.first { $0.representedObject as? String == space.profileIdentifier })
    }

    private func profileChosen(_ item: NSMenuItem) {
        guard let space = selectedSpace else { return }
        let identifier = item.representedObject as? String
        if identifier == space.profileIdentifier { return }
        browser?.changeProfile(of: space, to: identifier) { [weak self] in self?.reload() }
    }

    private func open(_ host: String, path: String) {
        guard let space = selectedSpace else { return }
        browser?.openChromePage(host, path: path, profile: space.profileIdentifier)
    }

    @objc private func commitName() {
        guard let browser, let index = list.selectedIndex else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            refreshDetail()
            return
        }
        browser.setName(name, forSpace: index)
        reloadList()
    }

    func controlTextDidEndEditing(_ notification: Notification) { commitName() }

    private func showIconPicker() {
        guard let space = selectedSpace, let index = list.selectedIndex else { return }
        let picker = IconPickerController(selected: space.symbol)
        picker.onPick = { [weak self] symbol in
            self?.browser?.setSymbol(symbol, forSpace: index)
            self?.reloadList()
            self?.refreshDetail()
        }
        present(picker, relativeTo: iconButton)
    }

    private func showThemeEditor() {
        guard let space = selectedSpace, let index = list.selectedIndex else { return }
        let editor = ThemeEditorController(color: space.customColor)
        editor.onChange = { [weak self] color in
            self?.browser?.setColor(color, forSpace: index)
            self?.reloadList()
            self?.refreshDetail()
        }
        present(editor, relativeTo: themeButton)
    }

    private func present(_ controller: NSViewController, relativeTo anchor: NSView) {
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    private func addSpace() {
        browser?.addSpace { [weak self] space in
            guard let self, let browser = self.browser else { return }
            self.list.items = browser.spaces
            self.list.selectedIndex = browser.spaces.firstIndex { $0 === space }
            self.refreshDetail()
            self.view.window?.makeFirstResponder(self.nameField)
            self.nameField.selectText(nil)
        }
    }

    @objc private func removeSpace() {
        guard let index = list.selectedIndex, let window = view.window else { return }
        browser?.deleteSpace(index, presentingIn: window) { [weak self] in
            self?.list.selectedIndex = nil
            self?.reload()
        }
    }

    static func icon(for space: Space, size: CGFloat = 13) -> NSImage? {
        guard !space.symbol.isEmpty else { return size > 13 ? nil : NSImage.symbol("circle.fill", size: 6) }
        return NSImage.symbol(SpaceSymbols.displayName(space.symbol, active: true), size: size)
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            disc.fill()
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            return true
        }
    }

    static func footerButton(_ symbol: String, toolTip: String, action: @escaping () -> Void) -> NSButton {
        let button = SettingsButton("", onPress: action)
        configureFooterButton(button, symbol: symbol, toolTip: toolTip)
        return button
    }

    static func configureFooterButton(_ button: NSButton, symbol: String, toolTip: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = toolTip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
}
