import AppKit

@MainActor
final class UpdateChipView: HoverView {
    static let height: CGFloat = 32
    private static let expandedHeight: CGFloat = 108
    private static let expandedRadius: CGFloat = 12

    private let fill = CALayer()
    private let progressFill = CALayer()
    private let label = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12))
    private let titleLabel = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 13, weight: .semibold))
    private let installRow = UpdateCardRow(symbol: "arrow.down.circle", title: "Install Now") { Updater.shared.apply() }
    private let laterRow = UpdateCardRow(symbol: "clock", title: "Remind Me Later") { Updater.shared.dismiss() }
    private var progress: Double?
    private(set) var isExpanded = false
    var onLayoutChange: (() -> Void)?
    var onExpandChange: (() -> Void)?

    var isActive: Bool { Updater.shared.update != nil }
    var displayHeight: CGFloat { isExpanded ? Self.expandedHeight : Self.height }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.addSublayer(fill)
        layer?.addSublayer(progressFill)
        label.alignment = .center
        for field in [label, titleLabel] { field.allowsExpansionToolTips = false }
        for view in [label, titleLabel, installRow, laterRow] as [NSView] { addSubview(view) }
        for view in [titleLabel, installRow, laterRow] as [NSView] { view.isHidden = true }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .updaterStateDidChange, object: nil)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() {
        let wasHidden = isHidden
        progress = nil
        toolTip = nil
        switch Updater.shared.state {
        case .idle:
            isHidden = true
        case .available(let update):
            isHidden = false
            label.stringValue = "New Argon Version Available"
            titleLabel.stringValue = "Argon \(update.version) is available"
            installRow.title = Updater.shared.canInstallInPlace ? "Install Now" : "Download"
        case .downloading(_, let fraction):
            isHidden = false
            progress = fraction
            label.stringValue = "Downloading Update\u{2026} \(Int((fraction * 100).rounded()))%"
        case .preparing:
            isHidden = false
            label.stringValue = "Verifying Update\u{2026}"
        case .restarting:
            isHidden = false
            label.stringValue = "Restarting\u{2026}"
        case .failed(_, let reason):
            isHidden = false
            label.stringValue = "Update Failed"
            titleLabel.stringValue = "Update failed"
            installRow.title = "Retry"
            toolTip = reason
        }
        hoverChanged()
        needsLayout = true
        needsDisplay = true
        if wasHidden != isHidden { onLayoutChange?() }
    }

    private var isInteractive: Bool {
        switch Updater.shared.state {
        case .available, .failed: true
        default: false
        }
    }

    override func hoverChanged() {
        let expanded = isHovered && isInteractive && !isHidden
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        label.isHidden = expanded
        for view in [titleLabel, installRow, laterRow] as [NSView] { view.isHidden = !expanded }
        needsLayout = true
        needsDisplay = true
        onExpandChange?()
    }

    override func updateLayer() {
        var base: CGColor?
        var bar: CGColor?
        var border: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            base = (isExpanded ? Palette.tabActive : Palette.surface).cgColor
            bar = Palette.tabHover.cgColor
            border = Palette.white(0x1A).cgColor
        }
        layer?.cornerRadius = isExpanded ? Self.expandedRadius : Self.height / 2
        layer?.borderColor = border
        fill.backgroundColor = base
        progressFill.backgroundColor = bar
        label.textColor = Palette.text
        titleLabel.textColor = Palette.text
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(progress == nil)
        fill.frame = bounds
        progressFill.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(progress ?? 0), height: bounds.height)
        CATransaction.commit()
        let w = bounds.width
        let lineHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 10, y: bounds.height - (Self.height + lineHeight) / 2, width: max(0, w - 20), height: lineHeight)
        let titleHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(x: 14, y: 12, width: max(0, w - 28), height: titleHeight)
        let rowHeight: CGFloat = 28
        installRow.frame = NSRect(x: 6, y: titleLabel.frame.maxY + 8, width: max(0, w - 12), height: rowHeight)
        laterRow.frame = NSRect(x: 6, y: installRow.frame.maxY + 2, width: max(0, w - 12), height: rowHeight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let update = Updater.shared.update else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Release Notes \u{2014} \(update.version)") { BrowserWindowController.current?.openTab(update.pageURL) })
        if update.downloadURL != nil {
            menu.addItem(ClosureMenuItem("Download Disk Image") {
                BrowserWindowController.current?.openTab(update.downloadURL ?? update.pageURL)
            })
        }
        if isInteractive {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Remind Me Later") { Updater.shared.dismiss() })
            menu.addItem(ClosureMenuItem("Skip This Version") { UpdatePrompt.skip(update) })
        }
        return menu
    }
}

@MainActor
private final class UpdateCardRow: HoverView {
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12))
    private let action: () -> Void

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; needsLayout = true }
    }

    init(symbol: String, title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        icon.image = .symbol(symbol, size: 13)
        icon.imageScaling = .scaleNone
        label.stringValue = title
        label.allowsExpansionToolTips = false
        for view in [icon, label] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.buttonRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered ? Palette.tabHover.cgColor : nil
        icon.contentTintColor = Palette.icon
        label.textColor = Palette.text
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 8, y: (h - 16) / 2, width: 16, height: 16)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: icon.frame.maxX + 8, y: (h - labelHeight) / 2,
                             width: max(0, bounds.width - icon.frame.maxX - 16), height: labelHeight)
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Palette.tabActive.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        needsDisplay = true
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }
}
