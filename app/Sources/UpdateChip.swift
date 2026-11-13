import AppKit

@MainActor
final class UpdateChipView: HoverView {
    static let height: CGFloat = 32

    private let fill = CALayer()
    private let progressFill = CALayer()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12.5, weight: .medium))
    private let detail = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 11.5), color: Palette.subtle)
    private var progress: Double?
    var onLayoutChange: (() -> Void)?

    var isActive: Bool { Updater.shared.update != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = true
        layer?.cornerRadius = Metrics.cardRadius
        layer?.cornerCurve = .continuous
        layer?.addSublayer(fill)
        layer?.addSublayer(progressFill)
        icon.imageScaling = .scaleNone
        label.lineBreakMode = .byTruncatingTail
        detail.alignment = .right
        for view in [icon, label, detail] { addSubview(view) }
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
            show("arrow.down.circle.fill", "Update Argon", detail: update.version.description)
            toolTip = Updater.shared.canInstallInPlace ? "Download Argon \(update.version) and restart" : "Download Argon \(update.version)"
        case .downloading(_, let fraction):
            isHidden = false
            progress = fraction
            show("arrow.down.circle", "Downloading Update", detail: "\(Int((fraction * 100).rounded()))%")
        case .preparing:
            isHidden = false
            show("checkmark.shield", "Verifying Update", detail: "")
        case .restarting:
            isHidden = false
            show("arrow.clockwise.circle", "Restarting\u{2026}", detail: "")
        case .failed(_, let reason):
            isHidden = false
            show("exclamationmark.circle", "Update Failed", detail: "Retry")
            toolTip = reason
        }
        needsLayout = true
        needsDisplay = true
        if wasHidden != isHidden { onLayoutChange?() }
    }

    private func show(_ symbol: String, _ title: String, detail text: String) {
        icon.image = .symbol(symbol, size: 13, weight: .medium)
        label.stringValue = title
        detail.stringValue = text
    }

    override func updateLayer() {
        var base: CGColor?
        var bar: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            base = (isHovered && isInteractive ? Palette.tabActive : Palette.surface).cgColor
            bar = Palette.tabHover.cgColor
        }
        fill.backgroundColor = base
        progressFill.backgroundColor = bar
        icon.contentTintColor = Palette.text
    }

    private var isInteractive: Bool {
        switch Updater.shared.state {
        case .available, .failed: true
        default: false
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(progress == nil)
        fill.frame = bounds
        progressFill.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(progress ?? 0), height: bounds.height)
        CATransaction.commit()
        let h = bounds.height
        icon.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)
        let detailWidth = ceil(detail.intrinsicContentSize.width) + 4
        let labelHeight = label.intrinsicContentSize.height
        detail.frame = NSRect(x: bounds.width - 10 - detailWidth, y: (h - detail.intrinsicContentSize.height) / 2,
                              width: detailWidth, height: detail.intrinsicContentSize.height)
        label.frame = NSRect(x: icon.frame.maxX + 8, y: (h - labelHeight) / 2,
                             width: max(0, detail.frame.minX - icon.frame.maxX - 14), height: labelHeight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard isInteractive, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        Updater.shared.apply()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let update = Updater.shared.update else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Release Notes") { BrowserWindowController.current?.openTab(update.pageURL) })
        if update.downloadURL != nil {
            menu.addItem(ClosureMenuItem("Download Disk Image") {
                BrowserWindowController.current?.openTab(update.downloadURL ?? update.pageURL)
            })
        }
        if isInteractive {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Skip This Version") { UpdatePrompt.skip(update) })
        }
        return menu
    }
}
