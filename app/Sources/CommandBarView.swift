import AppKit

// Arc-style command bar: a centred panel for new tabs, URL editing and
// switching to open tabs.
@MainActor
final class CommandBarView: NSView, NSTextFieldDelegate {
    enum Mode { case newTab, editURL }

    enum Suggestion {
        case open(URL, title: String, subtitle: String, symbol: String)
        case switchTo(BrowserTab, spaceName: String)
        case match(AutocompleteMatch, engine: String)
    }

    weak var controller: BrowserWindowController?
    let mode: Mode
    var frameColor: NSColor { didSet { updatePanelColor() } }

    private let panel = NSView()
    private let glyph = NSImageView()
    private let field = NSTextField()
    private let divider = HairlineView(inset: 0, color: Palette.white(0x1F))
    private let initialText: String
    private var rows: [CommandRowView] = []
    private var suggestions: [Suggestion] = []
    private var selected = 0
    private var typedText = ""
    private var inlineCompletion = ""
    private var inlineAllowed = true
    private var defaultCompletion = ""
    private var autocompleteStorage: Autocomplete?
    private var favicons: [String: NSImage] = [:]
    private var pendingFavicons: Set<String> = []

    init(mode: Mode, initialText: String, frameColor: NSColor) {
        self.mode = mode
        self.initialText = initialText
        self.frameColor = frameColor
        super.init(frame: .zero)

        panel.wantsLayer = true
        panel.layer?.cornerRadius = Metrics.cardRadius
        panel.layer?.cornerCurve = .continuous
        panel.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 40
            shadow.shadowOffset = NSSize(width: 0, height: -12)
            return shadow
        }()
        updatePanelColor()

        glyph.image = .symbol("magnifyingglass", size: 18)
        glyph.contentTintColor = Palette.subtle

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typography.commandField
        field.textColor = Palette.text
        field.placeholderAttributedString = NSAttributedString(
            string: "Search or Enter URL...",
            attributes: [.font: Typography.commandField, .foregroundColor: Palette.faint]
        )
        field.stringValue = initialText
        typedText = initialText
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        for view in [glyph, field, divider] as [NSView] { panel.addSubview(view) }
        addSubview(panel)
        rebuildSuggestions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func updatePanelColor() {
        panel.layer?.backgroundColor = Palette.commandBar(frame: frameColor).cgColor
    }

    func activate() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        guard !Motion.reduced else { return }
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    override func layout() {
        super.layout()
        let width = min(max(bounds.width * 0.4, 560), min(800, bounds.width - 40))
        let header: CGFloat = 62
        var height = header
        if !rows.isEmpty {
            height += 1 + 6 + CGFloat(rows.count) * 46 + CGFloat(rows.count - 1) * 4 + 7
        }
        let top = max(20, bounds.height * 0.34 - header)
        panel.frame = NSRect(x: (bounds.width - width) / 2, y: top, width: width, height: height)

        let ph = panel.bounds.height
        func flip(_ y: CGFloat, _ h: CGFloat) -> CGFloat { ph - y - h }
        glyph.frame = NSRect(x: 20, y: flip((header - 22) / 2, 22), width: 22, height: 22)
        field.frame = NSRect(x: 54, y: flip((header - 26) / 2, 26), width: width - 54 - 20, height: 26)
        divider.isHidden = rows.isEmpty
        divider.frame = NSRect(x: 0, y: flip(header, 1), width: width, height: 1)
        var y = header + 1 + 6
        for row in rows {
            row.frame = NSRect(x: 7, y: flip(y, 46), width: width - 14, height: 46)
            y += 46 + 4
        }
    }

    // MARK: Suggestions

    private var profile: Profile? { controller?.activeSpace.profile }

    private var autocomplete: Autocomplete? {
        if let autocompleteStorage { return autocompleteStorage }
        guard let profile else { return nil }
        let autocomplete = Autocomplete(profile: profile)
        autocomplete.onResultsChanged = { [weak self] _ in self?.rebuildSuggestions() }
        autocompleteStorage = autocomplete
        return autocomplete
    }

    private var isShowingInitialState: Bool {
        let query = typedText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || (mode == .editURL && typedText == initialText)
    }

    private func textDidChange() {
        let text = field.stringValue
        let deleted = text.count <= typedText.count && typedText.hasPrefix(text)
        typedText = text
        inlineCompletion = ""
        if isShowingInitialState {
            autocomplete?.stop()
        } else {
            let editor = field.currentEditor()
            let caretAtEnd = editor.map { $0.selectedRange.location == (text as NSString).length } ?? true
            inlineAllowed = !(deleted || !caretAtEnd)
            autocomplete?.start(text: text, preventInlineAutocomplete: !inlineAllowed)
        }
        rebuildSuggestions()
    }

    private func rebuildSuggestions() {
        let query = typedText.trimmingCharacters(in: .whitespaces)
        var result: [Suggestion] = []
        let recent = controller?.tabsInRecentOrder() ?? []

        if isShowingInitialState {
            if mode == .editURL, let current = controller?.activeTab, let url = current.url {
                result.append(.open(url, title: current.title, subtitle: url.displayHost, symbol: "globe"))
            }
            for entry in recent where entry.tab !== controller?.activeTab {
                result.append(.switchTo(entry.tab, spaceName: entry.space.name))
                if result.count >= (mode == .editURL ? 5 : 4) { break }
            }
        } else {
            let needle = query.lowercased()
            let openTabs = recent.filter { entry in
                let haystack = entry.tab.title.lowercased() + " " + (entry.tab.url?.absoluteString.lowercased() ?? "")
                return haystack.contains(needle)
            }
            let (matches, completion) = Self.rank((autocomplete?.matches ?? []).filter { $0.destinationURL != nil }, typed: query)
            defaultCompletion = inlineAllowed ? completion : ""
            if matches.isEmpty {
                if let url = AddressInput.directURL(query) {
                    result.append(.open(url, title: query, subtitle: "Open Page", symbol: "globe"))
                } else if let url = AddressInput.url(from: query, profile: profile) {
                    result.append(.open(url, title: query, subtitle: "Search \(AddressInput.searchEngineName(for: profile))", symbol: "magnifyingglass"))
                }
                result += openTabs.prefix(5).map { .switchTo($0.tab, spaceName: $0.space.name) }
            } else {
                let engine = AddressInput.searchEngineName(for: profile)
                var shownTabs: [BrowserTab] = []
                func openTab(for match: AutocompleteMatch) -> (tab: BrowserTab, space: Space)? {
                    guard let key = match.destinationURL.map(Self.key) else { return nil }
                    return recent.first { $0.tab.url.map(Self.key) == key }
                }
                result.append(.match(matches[0], engine: engine))
                for entry in openTabs.prefix(3) where openTab(for: matches[0])?.tab !== entry.tab {
                    result.append(.switchTo(entry.tab, spaceName: entry.space.name))
                    shownTabs.append(entry.tab)
                }
                for match in matches.dropFirst() {
                    if result.count >= 8 { break }
                    if let entry = openTab(for: match) {
                        if shownTabs.contains(where: { $0 === entry.tab }) { continue }
                        result.append(.switchTo(entry.tab, spaceName: entry.space.name))
                        shownTabs.append(entry.tab)
                    } else {
                        result.append(.match(match, engine: engine))
                    }
                }
            }
        }

        suggestions = result
        selected = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = result.enumerated().map { index, suggestion in
            let row = CommandRowView(suggestion: suggestion)
            row.onHover = { [weak self] in self?.select(index) }
            row.onClick = { [weak self] in self?.execute(index) }
            if case .match(let match, _) = suggestion { loadFavicon(for: match, into: row) }
            panel.addSubview(row)
            return row
        }
        updateSelection()
        applyInlineCompletion()
        needsLayout = true
    }

    private func applyInlineCompletion() {
        guard let editor = field.currentEditor() as? NSTextView, field.stringValue.hasPrefix(typedText) else { return }
        var completion = ""
        if selected == 0, case .match? = suggestions.first, !isShowingInitialState {
            completion = defaultCompletion
        }
        guard completion != inlineCompletion || field.stringValue != typedText + completion else { return }
        inlineCompletion = completion
        let typedLength = (typedText as NSString).length
        editor.string = typedText + completion
        editor.setSelectedRange(NSRange(location: typedLength, length: (completion as NSString).length))
    }

    private func loadFavicon(for match: AutocompleteMatch, into row: CommandRowView) {
        guard match.kind != .search, match.kind != .searchHistory, let url = match.destinationURL else { return }
        let key = url.absoluteString
        if let image = favicons[key] {
            row.setFavicon(image)
            return
        }
        guard !pendingFavicons.contains(key) else { return }
        pendingFavicons.insert(key)
        autocomplete?.favicon(for: url) { [weak self] image in
            guard let self else { return }
            self.pendingFavicons.remove(key)
            guard let image else { return }
            self.favicons[key] = image
            for (index, suggestion) in self.suggestions.enumerated() {
                if case .match(let other, _) = suggestion, other.destinationURL?.absoluteString == key,
                   self.rows.indices.contains(index) {
                    self.rows[index].setFavicon(image)
                }
            }
        }
    }

    private static func rank(_ matches: [AutocompleteMatch], typed: String) -> ([AutocompleteMatch], String) {
        guard let first = matches.first else { return ([], "") }
        if first.allowedToBeDefault, !first.inlineAutocompletion.isEmpty, first.kind != .search {
            return (matches, first.inlineAutocompletion)
        }
        let needle = typed.lowercased()
        func address(_ match: AutocompleteMatch) -> String {
            var text = match.contents.lowercased()
            for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
            return text
        }
        let sites = matches.filter { ($0.kind == .history || $0.kind == .bookmark) && address($0).hasPrefix(needle) }
        let site = sites.first { !address($0).dropFirst(needle.count).contains("/") } ?? sites.first
        guard let site, !needle.contains(" ") else {
            return (matches, first.allowedToBeDefault ? first.inlineAutocompletion : "")
        }
        let rest = matches.filter { $0 !== site }
        return ([site] + rest, String(address(site).dropFirst(needle.count)))
    }

    private static func key(_ url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path + (url.query.map { "?" + $0 } ?? "")
    }

    private func select(_ index: Int, fromKeyboard: Bool = false) {
        guard rows.indices.contains(index) else { return }
        selected = index
        updateSelection()
        guard fromKeyboard, !isShowingInitialState, let editor = field.currentEditor() as? NSTextView else { return }
        if index == 0 {
            inlineCompletion = ""
            applyInlineCompletion()
        } else if field.stringValue != typedText {
            inlineCompletion = ""
            editor.string = typedText
            editor.setSelectedRange(NSRange(location: (typedText as NSString).length, length: 0))
        }
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() { row.isSelected = index == selected }
    }

    private func execute(_ index: Int) {
        guard let controller else { return }
        guard suggestions.indices.contains(index) else {
            if let url = AddressInput.url(from: field.stringValue, profile: profile) {
                controller.commandBar(self, open: url)
            } else if mode == .newTab {
                controller.dismissCommandBar()
                controller.openTab(nil)
            }
            return
        }
        switch suggestions[index] {
        case .open(let url, _, _, _):
            controller.commandBar(self, open: url)
        case .switchTo(let tab, _):
            controller.commandBar(self, switchTo: tab)
        case .match(let match, _):
            guard let url = match.destinationURL else { return }
            autocomplete?.didOpen(match)
            controller.commandBar(self, open: url)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        textDidChange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            select(min(selected + 1, rows.count - 1), fromKeyboard: true)
        case #selector(NSResponder.moveUp(_:)):
            select(max(selected - 1, 0), fromKeyboard: true)
        case #selector(NSResponder.insertNewline(_:)):
            execute(selected)
        case #selector(NSResponder.cancelOperation(_:)):
            controller?.dismissCommandBar()
        default:
            return false
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !panel.frame.contains(point) { controller?.dismissCommandBar() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePanelColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePanelColor()
        if window != nil, controller != nil, suggestions.isEmpty {
            rebuildSuggestions()
        }
    }
}

@MainActor
final class CommandRowView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { updateColors() } } }

    private let icon = NSImageView()
    private let title = NSTextField.sidebarLabel(font: Typography.commandTitle)
    private let subtitle = NSTextField.sidebarLabel(font: Typography.commandSubtitle, color: Palette.subtle)
    private let switchLabel = NSTextField.sidebarLabel("Switch to Tab", font: .systemFont(ofSize: 12, weight: .medium), color: Palette.subtle)
    private let arrowBox = NSView()
    private let arrow = NSImageView()
    private let isTab: Bool

    init(suggestion: CommandBarView.Suggestion) {
        switch suggestion {
        case .open(_, let titleText, let subtitleText, let symbol):
            isTab = false
            title.stringValue = titleText
            subtitle.stringValue = subtitleText
            icon.image = .symbol(symbol, size: 14)
            icon.contentTintColor = Palette.icon
        case .switchTo(let tab, let spaceName):
            isTab = true
            title.stringValue = tab.title
            subtitle.stringValue = [tab.url?.displayHost, spaceName].compactMap { $0 }.joined(separator: " · ")
            if let favicon = tab.favicon {
                icon.image = favicon
            } else {
                icon.image = .symbol("globe", size: 14)
                icon.contentTintColor = Palette.icon
            }
        case .match(let match, let engine):
            isTab = false
            let symbol: String
            switch match.kind {
            case .search:
                title.stringValue = match.contents
                subtitle.stringValue = "Search \(engine)"
                symbol = "magnifyingglass"
            case .searchHistory:
                title.stringValue = match.contents
                subtitle.stringValue = "Search \(engine)"
                symbol = "clock.arrow.circlepath"
            case .URL:
                title.stringValue = match.contents
                subtitle.stringValue = "Open Page"
                symbol = "globe"
            case .bookmark:
                title.stringValue = match.matchDescription.isEmpty ? match.contents : match.matchDescription
                subtitle.stringValue = match.matchDescription.isEmpty ? "" : match.contents
                symbol = "star"
            default:
                title.stringValue = match.matchDescription.isEmpty ? match.contents : match.matchDescription
                subtitle.stringValue = match.matchDescription.isEmpty ? "" : match.contents
                symbol = "globe"
            }
            icon.image = .symbol(symbol, size: 14)
            icon.contentTintColor = Palette.icon
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.buttonRadius
        icon.imageScaling = .scaleProportionallyUpOrDown
        arrowBox.wantsLayer = true
        arrowBox.layer?.cornerRadius = Metrics.buttonRadius
        arrow.image = .symbol("arrow.right", size: 12, weight: .semibold)
        arrowBox.addSubview(arrow)
        arrowBox.isHidden = !isTab
        switchLabel.isHidden = !isTab
        for view in [icon, title, subtitle, switchLabel, arrowBox] as [NSView] { addSubview(view) }
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setFavicon(_ image: NSImage) {
        icon.image = image
        icon.contentTintColor = nil
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
        arrowBox.frame = NSRect(x: bounds.width - 12 - 24, y: (h - 24) / 2, width: 24, height: 24)
        arrow.frame = arrowBox.bounds
        let switchWidth = ceil(switchLabel.attributedStringValue.size().width) + 4
        switchLabel.frame = NSRect(x: arrowBox.frame.minX - 8 - switchWidth, y: (h - 16) / 2, width: switchWidth, height: 16)
        let right = isTab ? switchLabel.frame.minX - 12 : bounds.width - 12
        let x: CGFloat = 40
        let titleWidth = min(ceil(title.attributedStringValue.size().width) + 4, min(320, right - x))
        title.frame = NSRect(x: x, y: (h - 18) / 2, width: titleWidth, height: 18)
        let subX = title.frame.maxX + 10
        subtitle.frame = NSRect(x: subX, y: (h - 17) / 2, width: max(0, right - subX), height: 17)
    }

    private func updateColors() {
        layer?.backgroundColor = isSelected ? cg(Palette.white(0x1A)) : nil
        arrowBox.layer?.backgroundColor = isSelected ? cg(Palette.text) : cg(Palette.white(0x14))
        arrow.contentTintColor = isSelected ? Palette.dynamic(dark: Palette.ink) { .white } : Palette.icon
        switchLabel.textColor = isSelected ? Palette.text : Palette.subtle
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
