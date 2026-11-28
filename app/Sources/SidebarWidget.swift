import AppKit

// A card stacked above the space bar. Its bottom row is always visible; hovering an
// expandable widget grows the card upward over the tab list to reveal a header
// (title and accessory buttons) and an optional body between the header and the row.
@MainActor
class SidebarWidget: HoverView {
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 30
    static let spacing: CGFloat = 6
    static let radius: CGFloat = 10

    let titleLabel = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12.5, weight: .medium))
    private let progressFill = CALayer()
    private var accessories: [IconButton] = []
    private var bodyViews: [NSView] = []
    private(set) var isExpanded = false
    var onPresentationChange: (() -> Void)?
    var onExpansionChange: (() -> Void)?

    var isPresented = false {
        didSet {
            guard oldValue != isPresented else { return }
            if !isPresented { setExpanded(false) }
            onPresentationChange?()
        }
    }

    var canExpand = false {
        didSet { if oldValue != canExpand { hoverChanged() } }
    }

    var progress: Double? {
        didSet { if oldValue != progress { needsLayout = true } }
    }

    var bodyHeight: CGFloat { 0 }
    var expandedHeight: CGFloat { Self.rowHeight + Self.headerHeight + bodyHeight }
    var displayHeight: CGFloat { isExpanded ? expandedHeight : Self.rowHeight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.addSublayer(progressFill)
        titleLabel.allowsExpansionToolTips = false
        titleLabel.alphaValue = 0
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setAccessories(_ buttons: [IconButton]) {
        accessories.forEach { $0.removeFromSuperview() }
        accessories = buttons
        for button in buttons {
            button.alphaValue = isExpanded ? 1 : 0
            addSubview(button)
        }
        needsLayout = true
    }

    func addBodyView(_ view: NSView) {
        view.alphaValue = isExpanded ? 1 : 0
        bodyViews.append(view)
        addSubview(view)
    }

    func layoutRow(in rect: NSRect) {}
    func layoutBody(in rect: NSRect) {}
    func titleClicked() {}

    override func hoverChanged() {
        setExpanded(isHovered && canExpand && isPresented)
    }

    private func setExpanded(_ value: Bool) {
        guard value != isExpanded else { return }
        isExpanded = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduced || window == nil ? 0 : 0.2
            for view in [titleLabel] + accessories + bodyViews as [NSView] {
                view.animator().alphaValue = value ? 1 : 0
            }
        }
        needsDisplay = true
        onExpansionChange?()
    }

    override func updateLayer() {
        layer?.cornerRadius = Self.radius
        layer?.backgroundColor = Palette.widget.cgColor
        layer?.borderColor = Palette.widgetBorder.cgColor
        progressFill.backgroundColor = Palette.tabHover.cgColor
        titleLabel.textColor = Palette.text
    }

    // Everything is placed from the bottom edge so the row stays still while the card grows.
    override func layout() {
        super.layout()
        let w = bounds.width
        let row = NSRect(x: 0, y: bounds.height - Self.rowHeight, width: w, height: Self.rowHeight)
        let header = NSRect(x: 0, y: bounds.height - expandedHeight, width: w, height: Self.headerHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(progress == nil)
        progressFill.frame = NSRect(x: 0, y: row.minY, width: w * CGFloat(progress ?? 0), height: row.height)
        CATransaction.commit()

        let size: CGFloat = 24
        var x = w - 5
        for button in accessories.reversed() {
            x -= size
            button.frame = NSRect(x: x, y: header.minY + (header.height - size) / 2 + 2, width: size, height: size)
            x -= 2
        }
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(x: 12, y: header.minY + (header.height - labelHeight) / 2 + 2,
                                  width: max(0, x - 16), height: labelHeight)
        layoutBody(in: NSRect(x: 0, y: header.maxY, width: w, height: max(0, row.minY - header.maxY)))
        layoutRow(in: row)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 1, isExpanded else { return }
        let point = convert(event.locationInWindow, from: nil)
        if titleLabel.frame.insetBy(dx: 0, dy: -4).contains(point) { titleClicked() }
    }
}

// A full-width action inside a widget: an icon and a label, highlighted on hover.
@MainActor
final class SidebarWidgetButton: HoverView {
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12))
    var action: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; needsLayout = true }
    }

    init(symbol: String, title: String, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        icon.imageScaling = .scaleNone
        setSymbol(symbol)
        label.stringValue = title
        label.allowsExpansionToolTips = false
        for view in [icon, label] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ symbol: String) {
        icon.image = .symbol(symbol, size: 13)
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.buttonRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered && isEnabled ? Palette.tabHover.cgColor : nil
        icon.contentTintColor = Palette.icon
        label.textColor = Palette.text
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 7, y: (h - 16) / 2, width: 16, height: 16)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: icon.frame.maxX + 7, y: (h - labelHeight) / 2,
                             width: max(0, bounds.width - icon.frame.maxX - 14), height: labelHeight)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = Palette.tabActive.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        needsDisplay = true
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}
