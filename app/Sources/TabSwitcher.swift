import AppKit

@MainActor
final class TabSwitcher {
    static let limit = 5
    private static let revealDelay: TimeInterval = 0.12

    private let tabs: [BrowserTab]
    private(set) var selection: Int
    private let view: TabSwitcherView
    private weak var host: NSView?
    private var monitor: Any?
    private var revealWork: DispatchWorkItem?
    private let onCommit: (BrowserTab?) -> Void

    init?(tabs: [BrowserTab], forward: Bool, host: NSView, fill: NSColor, onCommit: @escaping (BrowserTab?) -> Void) {
        guard tabs.count > 1 else { return nil }
        self.tabs = tabs
        self.host = host
        self.onCommit = onCommit
        selection = forward ? 1 : tabs.count - 1
        view = TabSwitcherView(tabs: tabs, fill: fill)
        view.onPick = { [weak self] index in
            self?.selection = index
            self?.finish(commit: true)
        }
    }

    func begin() {
        guard NSEvent.modifierFlags.contains(.control) else {
            finish(commit: true)
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged, !event.modifierFlags.contains(.control) {
                self.finish(commit: true)
                return event
            }
            if event.type == .keyDown, event.keyCode == 53 {
                self.finish(commit: false)
                return nil
            }
            return event
        }
        let work = DispatchWorkItem { [weak self] in self?.reveal() }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealDelay, execute: work)
    }

    func step(forward: Bool) {
        selection = (selection + (forward ? 1 : -1) + tabs.count) % tabs.count
        view.selection = selection
        if view.superview == nil { reveal() }
    }

    private func reveal() {
        revealWork?.cancel()
        guard monitor != nil, let host, view.superview == nil else { return }
        view.selection = selection
        view.present(in: host)
    }

    private func finish(commit: Bool) {
        revealWork?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        view.dismiss()
        onCommit(commit && tabs.indices.contains(selection) ? tabs[selection] : nil)
    }
}

@MainActor
final class TabSwitcherView: NSView {
    private static let cardSize = NSSize(width: 184, height: 150)
    private static let spacing: CGFloat = 10
    private static let padding: CGFloat = 14

    var onPick: ((Int) -> Void)?
    var selection = 0 { didSet { cards.enumerated().forEach { $0.element.isSelected = $0.offset == selection } } }
    private var cards: [TabSwitcherCard] = []
    private let fill: NSColor

    init(tabs: [BrowserTab], fill: NSColor) {
        self.fill = fill
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Metrics.shadowOpacity
        layer?.shadowRadius = Metrics.shadowRadius
        layer?.shadowOffset = Metrics.shadowOffset
        for (index, tab) in tabs.enumerated() {
            let card = TabSwitcherCard(tab: tab)
            card.onClick = { [weak self] in self?.onPick?(index) }
            addSubview(card)
            cards.append(card)
        }
        let count = CGFloat(tabs.count)
        setFrameSize(NSSize(width: 2 * Self.padding + count * Self.cardSize.width + (count - 1) * Self.spacing,
                            height: 2 * Self.padding + Self.cardSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = Palette.hairline.cgColor
    }

    override func layout() {
        super.layout()
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: Self.padding + CGFloat(index) * (Self.cardSize.width + Self.spacing), y: Self.padding,
                                width: Self.cardSize.width, height: Self.cardSize.height)
        }
    }

    func present(in host: NSView) {
        let width = min(frame.width, host.bounds.width - 40)
        frame = NSRect(x: (host.bounds.width - width) / 2, y: (host.bounds.height - frame.height) / 2, width: width, height: frame.height)
        autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        host.addSubview(self)
        guard !Motion.reduced, let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.96
        scale.toValue = 1
        scale.stiffness = 400
        scale.damping = 30
        scale.duration = scale.settlingDuration
        layer.add(fade, forKey: "in.fade")
        layer.add(scale, forKey: "in.scale")
    }

    func dismiss() {
        guard superview != nil else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduced ? 0 : 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        })
    }
}

@MainActor
final class TabSwitcherCard: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    private let preview = NSImageView()
    private let placeholder = NSImageView()
    private let iconView = NSImageView()
    private let titleLabel: NSTextField

    init(tab: BrowserTab) {
        titleLabel = .sidebarLabel(tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title,
                                   font: .inter(12, weight: .medium))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        titleLabel.lineBreakMode = .byTruncatingTail
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.cornerCurve = .continuous
        preview.layer?.masksToBounds = true
        preview.imageScaling = .scaleAxesIndependently
        preview.image = tab.snapshot
        placeholder.image = tab.favicon ?? .symbol("globe", size: 28)
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.contentTintColor = Palette.icon
        placeholder.isHidden = tab.snapshot != nil
        iconView.image = tab.favicon ?? .symbol("globe", size: 12)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = Palette.icon
        for view in [preview, placeholder, iconView, titleLabel] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        preview.frame = NSRect(x: inset, y: inset, width: bounds.width - 2 * inset, height: bounds.height - 2 * inset - 26)
        placeholder.frame = NSRect(x: preview.frame.midX - 18, y: preview.frame.midY - 18, width: 36, height: 36)
        iconView.frame = NSRect(x: inset + 2, y: preview.frame.maxY + 7, width: 14, height: 14)
        titleLabel.frame = NSRect(x: iconView.frame.maxX + 6, y: preview.frame.maxY + 5, width: bounds.width - iconView.frame.maxX - 6 - inset, height: 17)
    }

    override func updateLayer() {
        layer?.backgroundColor = isSelected ? Palette.tabActive.cgColor : nil
        layer?.borderWidth = isSelected ? 1.5 : 0
        layer?.borderColor = Palette.accent.cgColor
        preview.layer?.backgroundColor = Palette.placeholder.cgColor
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}
