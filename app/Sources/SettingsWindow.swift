import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Pane: String, CaseIterable {
        case general, spaces, shortcuts

        var title: String {
            switch self {
            case .general: return "General"
            case .spaces: return "Spaces"
            case .shortcuts: return "Shortcuts"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .spaces: return "square.on.square"
            case .shortcuts: return "keyboard"
            }
        }
    }

    static let shared = SettingsWindowController()
    static let contentSize = NSSize(width: 720, height: 600)
    static let headerHeight: CGFloat = 64

    private var panes: [Pane: SettingsPane] = [:]
    private(set) var current: Pane = .general
    private let tabBar = SettingsTabBar(panes: Pane.allCases)
    private let host = NSView()

    private init() {
        let size = NSSize(width: Self.contentSize.width, height: Self.contentSize.height + Self.headerHeight)
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        tabBar.frame = NSRect(x: 0, y: 0, width: size.width, height: Self.headerHeight)
        tabBar.autoresizingMask = [.width]
        tabBar.onSelect = { [weak self] pane in
            guard let self, pane != self.current else { return }
            self.select(pane)
        }
        host.frame = NSRect(x: 0, y: Self.headerHeight, width: size.width, height: Self.contentSize.height)
        host.autoresizingMask = [.width, .height]
        root.addSubview(tabBar)
        root.addSubview(host)
        window.contentView = root
        select(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ pane: Pane? = nil) {
        if let pane { select(pane) }
        if window?.isVisible != true { centerOverBrowser() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func select(_ pane: Pane) {
        current = pane
        let controller = panes[pane] ?? makePane(pane)
        panes[pane] = controller
        tabBar.selected = pane
        controller.reload()
        host.subviews.forEach { $0.removeFromSuperview() }
        controller.view.frame = host.bounds
        controller.view.autoresizingMask = [.width, .height]
        host.addSubview(controller.view)
    }

    private func makePane(_ pane: Pane) -> SettingsPane {
        switch pane {
        case .general: return GeneralSettingsPane()
        case .spaces: return SpacesSettingsPane()
        case .shortcuts: return ShortcutsSettingsPane()
        }
    }

    private func centerOverBrowser() {
        guard let window else { return }
        guard let parent = BrowserWindowController.current?.window, parent.isVisible,
              let screen = (parent.screen ?? NSScreen.main)?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        var origin = NSPoint(x: parent.frame.midX - size.width / 2, y: parent.frame.midY - size.height / 2)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        window.setFrameOrigin(origin)
    }

    // Spaces and profiles can change in the browser window while this one sits behind it.
    func windowDidBecomeKey(_ notification: Notification) {
        panes[current]?.reload()
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        panes[current]?.reload()
    }
}

// Never becomes main, so menu commands keep reaching the browser window behind it.
@MainActor
final class SettingsWindow: NSWindow {
    override var canBecomeMain: Bool { false }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    // Centres the traffic lights on the tab row instead of the default 28pt title bar.
    private func positionTrafficLights() {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { standardWindowButton($0) }
        guard buttons.count == 3, let container = buttons[0].superview?.superview else { return }
        let height = SettingsWindowController.headerHeight
        var frame = container.frame
        if frame.height != height || frame.minY != self.frame.height - height {
            frame.size.height = height
            frame.origin.y = self.frame.height - height
            container.frame = frame
        }
        for button in buttons {
            let y = ((height - button.frame.height) / 2).rounded()
            if button.frame.minY != y { button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y)) }
        }
    }

    // Close Tab is bound to Command-W in the menu; here it should close this window instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if firstResponder is NSText { return }
        performClose(nil)
    }
}

@MainActor
final class SettingsTabBar: NSView {
    typealias Pane = SettingsWindowController.Pane
    var onSelect: ((Pane) -> Void)?
    var selected: Pane? { didSet { buttons.forEach { $0.isSelected = $0.pane == selected } } }
    private var buttons: [SettingsTabButton] = []

    init(panes: [Pane]) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        for pane in panes {
            let button = SettingsTabButton(pane: pane)
            button.onClick = { [weak self] in self?.onSelect?(pane) }
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        SettingsStyle.rowSeparator.setFill()
        let pixel = 1 / max(window?.backingScaleFactor ?? 2, 1)
        NSRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
final class SettingsTabButton: NSView {
    let pane: SettingsWindowController.Pane
    var onClick: (() -> Void)?
    var isSelected = false { didSet { refresh() } }
    private let iconView = NSImageView()
    private let label: NSTextField
    private var hovered = false

    init(pane: SettingsWindowController.Pane) {
        self.pane = pane
        label = NSTextField(labelWithString: pane.title)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        iconView.imageScaling = .scaleNone
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        for view in [iconView, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(pane.title)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    private func refresh() {
        let tint: NSColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        iconView.contentTintColor = tint
        label.textColor = tint
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isSelected ? SettingsStyle.selection.cgColor : hovered ? SettingsStyle.hover.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

@MainActor
class SettingsPane: NSViewController {
    var browser: BrowserWindowController? { BrowserWindowController.current }

    override func loadView() {
        view = FlippedView(frame: NSRect(origin: .zero, size: SettingsWindowController.contentSize))
    }

    func reload() {}
}

// MARK: Style

@MainActor
enum SettingsStyle {
    static let width: CGFloat = 580
    static let rowInset: CGFloat = 14
    static let rowHeight: CGFloat = 44

    static let cardFill = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.045)) { NSColor(white: 1, alpha: 0.7) }
    static let cardBorder = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.08)) { NSColor(white: 0, alpha: 0.09) }
    static let rowSeparator = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.07)) { NSColor(white: 0, alpha: 0.08) }
    static let keycapFill = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.09)) { NSColor(white: 0, alpha: 0.06) }
    static let selection = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.09)) { NSColor(white: 0, alpha: 0.07) }
    static let hover = Palette.dynamic(dark: NSColor(white: 1, alpha: 0.045)) { NSColor(white: 0, alpha: 0.035) }

    static let title = NSFont.systemFont(ofSize: 13)
    static let subtitle = NSFont.systemFont(ofSize: 11.5)
    static let header = NSFont.systemFont(ofSize: 12, weight: .medium)

    static func badge(_ symbol: String, color: NSColor, size: CGFloat = 22) -> NSImage {
        let isEmoji = symbol.first.map { !$0.isASCII } ?? false
        let glyph = NSImage.symbol(symbol, size: size * (isEmoji ? 0.62 : 0.5), weight: .semibold)
        let mark = isEmoji ? glyph : glyph?.tinted(.white)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let radius = size * 0.27
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            if let mark {
                let s = mark.size
                mark.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }

    static func accent(for space: Space) -> NSColor {
        guard let custom = space.customColor?.usingColorSpace(.sRGB) else {
            return NSColor(hue: space.hue, saturation: 0.58, brightness: 0.88, alpha: 1)
        }
        if custom.saturationComponent < 0.08 { return NSColor(white: 0.5, alpha: 1) }
        return NSColor(hue: custom.hueComponent, saturation: max(custom.saturationComponent, 0.45),
                       brightness: max(custom.brightnessComponent, 0.78), alpha: 1)
    }

    static func badge(for space: Space, size: CGFloat = 22) -> NSImage {
        let symbol = space.symbol.isEmpty ? "circle.fill" : SpaceSymbols.displayName(space.symbol, active: true)
        return badge(symbol, color: accent(for: space), size: size)
    }
}

// MARK: Components

@MainActor
class SettingsSurface: NSView {
    var radius: CGFloat = 10 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = SettingsStyle.cardFill.cgColor
        layer?.borderColor = SettingsStyle.cardBorder.cgColor
        layer?.borderWidth = 1 / max(window?.backingScaleFactor ?? 2, 1)
    }
}

@MainActor
final class SettingsCard: SettingsSurface {
    private let stack = NSStackView()

    init(_ rows: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setRows(rows)
    }

    func setRows(_ rows: [NSView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = SettingsSeparator()
                stack.addArrangedSubview(line)
                line.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: SettingsStyle.rowInset).isActive = true
                line.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -SettingsStyle.rowInset).isActive = true
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

@MainActor
final class SettingsSeparator: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        SettingsStyle.rowSeparator.setFill()
        let pixel = 1 / max(window?.backingScaleFactor ?? 2, 1)
        NSRect(x: 0, y: (bounds.height - pixel) / 2, width: bounds.width, height: pixel).fill()
    }
}

@MainActor
final class SettingsRow: NSView {
    let titleLabel: NSTextField
    let subtitleLabel: NSTextField
    var isEnabled = true {
        didSet {
            titleLabel.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
            (accessory as? NSControl)?.isEnabled = isEnabled
        }
    }
    private let accessory: NSView?

    init(title: String, subtitle: String? = nil, badge: NSImage? = nil, accessory: NSView? = nil, wraps: Bool = false) {
        titleLabel = NSTextField(wrappingLabelWithString: title)
        subtitleLabel = NSTextField(wrappingLabelWithString: subtitle ?? "")
        self.accessory = accessory
        super.init(frame: .zero)
        titleLabel.font = SettingsStyle.title
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = wraps ? 3 : 1
        titleLabel.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        titleLabel.isSelectable = false
        subtitleLabel.font = SettingsStyle.subtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isSelectable = false
        subtitleLabel.isHidden = subtitle == nil

        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(text)

        let inset = SettingsStyle.rowInset
        var textLeading = text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset)
        if let badge {
            let badgeView = NSImageView(image: badge)
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badgeView)
            NSLayoutConstraint.activate([
                badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
                badgeView.widthAnchor.constraint(equalToConstant: badge.size.width),
                badgeView.heightAnchor.constraint(equalToConstant: badge.size.height),
            ])
            textLeading = text.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 10)
        }
        var constraints = [
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsStyle.rowHeight),
            textLeading,
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
        ]
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(accessory)
            constraints += [
                accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                accessory.centerYAnchor.constraint(equalTo: centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -16),
            ]
        } else {
            constraints.append(text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
}

// A row that opens something; the whole row is the click target.
@MainActor
final class SettingsLinkRow: NSView {
    var onClick: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true; refresh() } }
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let arrow = NSImageView()
    private var hovered = false

    private let hasBadge: Bool

    init(title: String, symbol: String, color: NSColor? = nil, action: (() -> Void)? = nil) {
        titleLabel = NSTextField(labelWithString: title)
        onClick = action
        hasBadge = color != nil
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.font = SettingsStyle.title
        if let color {
            iconView.image = SettingsStyle.badge(symbol, color: color)
        } else {
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }
        iconView.imageScaling = .scaleNone
        arrow.image = NSImage(systemSymbolName: hasBadge ? "arrow.right" : "arrow.up.forward", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        arrow.imageScaling = .scaleNone
        for view in [iconView, titleLabel, arrow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = SettingsStyle.rowInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: hasBadge ? 40 : 38),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: hasBadge ? 22 : 18),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    private func refresh() {
        titleLabel.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
        iconView.contentTintColor = isEnabled ? .secondaryLabelColor : .quaternaryLabelColor
        iconView.alphaValue = isEnabled ? 1 : 0.4
        if !isEnabled {
            arrow.contentTintColor = .quaternaryLabelColor
        } else if hasBadge {
            arrow.contentTintColor = hovered ? .controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.75)
        } else {
            arrow.contentTintColor = hovered ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }

    override func updateLayer() {
        layer?.backgroundColor = hovered && isEnabled ? SettingsStyle.hover.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        hovered = value
        needsDisplay = true
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}

@MainActor
final class SettingsList<Item>: SettingsSurface {
    var items: [Item] = [] { didSet { rebuild() } }
    var selectedIndex: Int? { didSet { if selectedIndex != oldValue { updateSelection() } } }
    var onSelect: ((Int) -> Void)?
    var render: ((Item) -> (title: String, detail: String?, image: NSImage?)) = { _ in ("", nil, nil) }

    private let header: NSTextField
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let footer = NSStackView()
    private let footerLine = SettingsSeparator()
    private var footerHeight: NSLayoutConstraint?
    private var rows: [SettingsListRow] = []

    init(title: String) {
        header = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        header.font = SettingsStyle.header
        header.textColor = .secondaryLabelColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        footer.orientation = .horizontal
        footer.spacing = 0
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        let headerLine = SettingsSeparator()
        for view in [header, headerLine, scroll, footerLine, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsStyle.rowInset),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            headerLine.topAnchor.constraint(equalTo: topAnchor, constant: 36),
            headerLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerLine.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footerLine.topAnchor),
            footerLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLine.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        footerHeight = footer.heightAnchor.constraint(equalToConstant: 0)
        footerHeight?.isActive = true
        setFooter([])
    }

    func setFooter(_ buttons: [NSView]) {
        footer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hide = buttons.isEmpty
        footer.isHidden = hide
        footerLine.isHidden = hide
        footerHeight?.constant = hide ? 0 : 32
        for button in buttons { footer.addArrangedSubview(button) }
        footer.addArrangedSubview(NSView())
    }

    private func rebuild() {
        rows.forEach { $0.removeFromSuperview() }
        rows = items.enumerated().map { index, item in
            let content = render(item)
            let row = SettingsListRow(title: content.title, detail: content.detail, image: content.image)
            row.onClick = { [weak self] in
                self?.selectedIndex = index
                self?.onSelect?(index)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
            return row
        }
        updateSelection()
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() { row.isSelected = index == selectedIndex }
    }
}

@MainActor
final class SettingsListRow: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    private var hovered = false

    init(title: String, detail: String?, image: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = SettingsStyle.title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detailLabel = NSTextField(labelWithString: detail ?? "")
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let iconView = NSImageView()
        iconView.image = image
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor
        iconView.isHidden = image == nil
        for view in [iconView, titleLabel, detailLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let titleLeading = image == nil
            ? titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
            : titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            titleLeading,
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
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
final class SettingsSectionHeader: NSTextField {
    convenience init(_ title: String) {
        self.init(labelWithString: title)
        font = SettingsStyle.header
        textColor = .secondaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
    }
}

// MARK: Closure-backed controls

@MainActor
final class SettingsButton: NSButton {
    var onPress: (() -> Void)?

    convenience init(_ title: String, prominent: Bool = false, onPress: (() -> Void)? = nil) {
        self.init(title: title, target: nil, action: nil)
        self.onPress = onPress
        bezelStyle = .push
        controlSize = .regular
        if prominent { bezelColor = .controlAccentColor }
        target = self
        action = #selector(pressed)
    }

    @objc private func pressed() { onPress?() }
}

@MainActor
final class SettingsSwitch: NSSwitch {
    var onChange: ((Bool) -> Void)?

    convenience init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.init(frame: .zero)
        state = isOn ? .on : .off
        controlSize = .small
        self.onChange = onChange
        target = self
        action = #selector(changed)
    }

    @objc private func changed() { onChange?(state == .on) }
}

@MainActor
final class SettingsPopUp: NSPopUpButton {
    var onSelect: ((NSMenuItem) -> Void)?

    convenience init(onSelect: @escaping (NSMenuItem) -> Void) {
        self.init(frame: .zero, pullsDown: false)
        self.onSelect = onSelect
        target = self
        action = #selector(selected)
    }

    @objc private func selected() {
        guard let item = selectedItem else { return }
        onSelect?(item)
    }
}

extension NSView {
    func pinCentered(_ content: NSView, width: CGFloat, top: CGFloat, bottom: CGFloat? = nil) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        var constraints = [
            content.topAnchor.constraint(equalTo: topAnchor, constant: top),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.widthAnchor.constraint(equalToConstant: width),
        ]
        if let bottom { constraints.append(content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottom)) }
        NSLayoutConstraint.activate(constraints)
    }
}

extension NSStackView {
    static func settingsColumn(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views {
            stack.addArrangedSubview(view)
            if !(view is NSTextField) {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return stack
    }
}
