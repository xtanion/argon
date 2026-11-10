import AppKit

struct ShortcutCombo: Equatable {
    var caps: [String]
    var text: String { caps.joined() }
}

struct ShortcutEntry {
    var title: String
    var menu: String
    var combos: [ShortcutCombo]
    var keys: [String] { combos.map(\.text) }
}

struct ShortcutGroup {
    var title: String
    var entries: [ShortcutEntry]
}

// Read from the live main menu so the list always matches what the keys actually do.
@MainActor
enum ShortcutCatalog {
    static func groups() -> [ShortcutGroup] {
        guard let main = NSApp.mainMenu else { return [] }
        var groups: [ShortcutGroup] = []
        for top in main.items {
            guard let menu = top.submenu else { continue }
            menu.delegate?.menuNeedsUpdate?(menu)
            var entries: [ShortcutEntry] = []
            collect(menu, path: [top.title], into: &entries)
            let title = top.title == "Argon" ? "App" : top.title
            if !entries.isEmpty { groups.append(ShortcutGroup(title: title, entries: entries)) }
        }
        return groups
    }

    private static func collect(_ menu: NSMenu, path: [String], into entries: inout [ShortcutEntry]) {
        var spacesAdded = false
        var tabsAdded = false
        let menuPath = path.joined(separator: " \u{203A} ")
        for item in menu.items {
            if let submenu = item.submenu, item.title != "Change Profile" {
                collect(submenu, path: path + [item.title], into: &entries)
                continue
            }
            guard !item.isSeparatorItem, !item.keyEquivalent.isEmpty else { continue }
            if item.action == #selector(BrowserWindowController.selectSpaceFromMenu(_:)) {
                guard !spacesAdded else { continue }
                spacesAdded = true
                entries.append(ShortcutEntry(title: "Switch to Space 1\u{2013}9", menu: menuPath, combos: [combo(item, key: "1\u{2013}9")]))
                continue
            }
            if item.action == #selector(BrowserWindowController.selectTabFromMenu(_:)) {
                if item.tag == 8 {
                    entries.append(ShortcutEntry(title: "Last Tab", menu: menuPath, combos: [combo(item)]))
                } else if !tabsAdded {
                    tabsAdded = true
                    entries.append(ShortcutEntry(title: "Switch to Tab 1\u{2013}8", menu: menuPath, combos: [combo(item, key: "1\u{2013}8")]))
                }
                continue
            }
            let keys = combo(item)
            if let index = entries.firstIndex(where: { $0.title == item.title }) {
                if !entries[index].combos.contains(keys) { entries[index].combos.append(keys) }
            } else {
                entries.append(ShortcutEntry(title: item.title, menu: menuPath, combos: [keys]))
            }
        }
    }

    static func format(_ item: NSMenuItem, key override: String? = nil) -> String {
        combo(item, key: override).text
    }

    static func combo(_ item: NSMenuItem, key override: String? = nil) -> ShortcutCombo {
        var modifiers = item.keyEquivalentModifierMask
        let raw = item.keyEquivalent
        if override == nil, raw.count == 1, let char = raw.first, char.isLetter, char.isUppercase {
            modifiers.insert(.shift)
        }
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("\u{2303}") }
        if modifiers.contains(.option) { caps.append("\u{2325}") }
        if modifiers.contains(.shift) { caps.append("\u{21E7}") }
        if modifiers.contains(.command) { caps.append("\u{2318}") }
        caps.append(override ?? keyName(raw))
        return ShortcutCombo(caps: caps)
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return "" }
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: return "\u{2191}"
        case NSDownArrowFunctionKey: return "\u{2193}"
        case NSLeftArrowFunctionKey: return "\u{2190}"
        case NSRightArrowFunctionKey: return "\u{2192}"
        case NSBackspaceCharacter, NSDeleteCharacter: return "\u{232B}"
        case NSTabCharacter: return "\u{21E5}"
        case NSCarriageReturnCharacter, NSEnterCharacter: return "\u{21A9}"
        case 0x1B: return "\u{238B}"
        case 0x20: return "Space"
        default: return key.uppercased()
        }
    }
}

@MainActor
final class ShortcutsSettingsPane: SettingsPane, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No shortcuts match")
    private let detail = ShortcutDetailView()
    private var groups: [ShortcutGroup] = []
    private var rows: [ShortcutRow] = []
    private var selectedTitle: String?

    override func loadView() {
        super.loadView()
        searchField.placeholderString = "Search actions or keys"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged)
        searchField.focusRingType = .none

        let card = SettingsSurface()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        emptyLabel.font = SettingsStyle.title
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = true

        let searchLine = SettingsSeparator()
        for view in [card, detail] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        for view in [searchField, searchLine, scroll, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(view)
        }
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor, constant: contentInset),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInset),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -contentInset),
            card.widthAnchor.constraint(equalToConstant: 380),
            searchField.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            searchLine.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            searchLine.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            searchLine.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchLine.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -1),
            emptyLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: searchLine.bottomAnchor, constant: 40),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            detail.topAnchor.constraint(equalTo: card.topAnchor),
            detail.leadingAnchor.constraint(equalTo: card.trailingAnchor, constant: 24),
            detail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInset),
            detail.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    override func reload() {
        _ = view
        groups = ShortcutCatalog.groups()
        rebuild()
    }

    func controlTextDidChange(_ notification: Notification) { rebuild() }

    @objc private func filterChanged() { rebuild() }

    // Up and Down in the search field move the selection through the list.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let step: Int
        switch selector {
        case #selector(NSResponder.moveDown(_:)): step = 1
        case #selector(NSResponder.moveUp(_:)): step = -1
        default: return false
        }
        guard !rows.isEmpty else { return true }
        let current = rows.firstIndex { $0.isSelected } ?? (step > 0 ? -1 : rows.count)
        select(rows[min(max(current + step, 0), rows.count - 1)])
        return true
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows = []
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        for group in groups {
            let entries = query.isEmpty ? group.entries : group.entries.filter { entry in
                entry.title.lowercased().contains(query) || group.title.lowercased().contains(query)
                    || entry.keys.contains { $0.lowercased().contains(query) }
            }
            guard !entries.isEmpty else { continue }
            let header = SettingsSectionHeader(group.title)
            let headerRow = NSView()
            headerRow.translatesAutoresizingMaskIntoConstraints = false
            headerRow.addSubview(header)
            NSLayoutConstraint.activate([
                headerRow.heightAnchor.constraint(equalToConstant: 30),
                header.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 10),
                header.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: -5),
            ])
            add(headerRow)
            for entry in entries {
                let row = ShortcutRow(entry: entry)
                row.onClick = { [weak self, weak row] in
                    guard let self, let row else { return }
                    self.select(row)
                }
                add(row)
                rows.append(row)
            }
        }
        emptyLabel.isHidden = !rows.isEmpty
        let match = rows.first { $0.entry.title == selectedTitle } ?? rows.first
        if let match { select(match, scroll: false) } else { detail.entry = nil }
    }

    private func select(_ row: ShortcutRow, scroll: Bool = true) {
        for other in rows { other.isSelected = other === row }
        selectedTitle = row.entry.title
        detail.entry = row.entry
        if scroll { row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -8)) }
    }

    private func add(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
    }
}

@MainActor
final class ShortcutRow: NSView {
    let entry: ShortcutEntry
    var onClick: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private var hovered = false

    init(entry: ShortcutEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        let title = NSTextField(labelWithString: entry.title)
        title.font = SettingsStyle.title
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let keys = NSStackView(views: entry.keys.prefix(2).map { KeycapView($0) })
        keys.spacing = 6
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [title, keys] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            keys.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            keys.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isSelected ? SettingsStyle.selection.cgColor : hovered ? SettingsStyle.hover.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

@MainActor
final class ShortcutDetailView: NSView {
    var entry: ShortcutEntry? { didSet { refresh() } }
    private let caps = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let menuLabel = NSTextField(wrappingLabelWithString: "")
    private let alsoLabel = NSTextField(wrappingLabelWithString: "")
    private let content = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        caps.spacing = 8
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        menuLabel.font = SettingsStyle.title
        menuLabel.textColor = .secondaryLabelColor
        alsoLabel.font = SettingsStyle.title
        alsoLabel.textColor = .secondaryLabelColor

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        for view in [caps, titleLabel, menuLabel, alsoLabel] as [NSView] { content.addArrangedSubview(view) }
        content.setCustomSpacing(22, after: caps)

        let line = SettingsSeparator()
        let note = NSTextField(wrappingLabelWithString:
            "To change a shortcut, add it for Argon in System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts \u{203A} App Shortcuts, using the exact menu name.")
        note.font = SettingsStyle.subtitle
        note.textColor = .secondaryLabelColor
        let open = SettingsButton("Open Keyboard Settings\u{2026}") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        for view in [content, line, note, open] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            menuLabel.widthAnchor.constraint(equalTo: widthAnchor),
            alsoLabel.widthAnchor.constraint(equalTo: widthAnchor),
            open.leadingAnchor.constraint(equalTo: leadingAnchor),
            open.bottomAnchor.constraint(equalTo: bottomAnchor),
            note.leadingAnchor.constraint(equalTo: leadingAnchor),
            note.trailingAnchor.constraint(equalTo: trailingAnchor),
            note.bottomAnchor.constraint(equalTo: open.topAnchor, constant: -10),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -14),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func refresh() {
        caps.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let entry, let first = entry.combos.first else {
            content.isHidden = true
            return
        }
        content.isHidden = false
        for cap in first.caps { caps.addArrangedSubview(LargeKeycapView(cap)) }
        titleLabel.stringValue = entry.title
        menuLabel.stringValue = "In the menu bar under " + entry.menu + "."
        let others = entry.keys.dropFirst()
        alsoLabel.stringValue = others.isEmpty ? "" : "Also " + others.joined(separator: ", ") + "."
        alsoLabel.isHidden = others.isEmpty
    }
}

// The big keycap in the shortcut detail panel: white on dark, black on light.
@MainActor
final class LargeKeycapView: NSView {
    private let text: String

    init(_ text: String) {
        self.text = text
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let width = max(58, Self.attributed(text, color: .white).size().width + 30)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width.rounded(.up)),
            heightAnchor.constraint(equalToConstant: 58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private static func attributed(_ text: String, color: NSColor) -> NSAttributedString {
        let size: CGFloat = text.count > 2 ? 17 : 26
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = Palette.isDark(effectiveAppearance)
        let rim = NSColor(white: dark ? 0.72 : 0.08, alpha: 1)
        let top = NSColor(white: dark ? 0.98 : 0.24, alpha: 1)
        let bottom = NSColor(white: dark ? 0.88 : 0.16, alpha: 1)
        let ink = NSColor(white: dark ? 0.08 : 0.97, alpha: 1)
        let outer = NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13)
        rim.setFill()
        outer.fill()
        let faceRect = NSRect(x: 3, y: 2, width: bounds.width - 6, height: bounds.height - 8)
        let face = NSBezierPath(roundedRect: faceRect, xRadius: 10, yRadius: 10)
        NSGradient(starting: top, ending: bottom)?.draw(in: face, angle: 90)
        let label = Self.attributed(text, color: ink)
        let size = label.size()
        label.draw(at: NSPoint(x: faceRect.midX - size.width / 2, y: faceRect.midY - size.height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class KeycapView: NSView {
    init(_ text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = SettingsStyle.keycapFill.cgColor
    }
}
