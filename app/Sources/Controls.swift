import AppKit

// Base for sidebar views: flipped, layer-backed, hover-aware, never drags the
// window.
@MainActor
class HoverView: NSView {
    private(set) var isHovered = false
    var onHoverChange: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        needsDisplay = true
        hoverChanged()
        onHoverChange?(hovered)
    }

    func hoverChanged() {}
}

@MainActor
final class IconButton: HoverView {
    private let imageView = NSImageView()
    private var glyphLayer: CALayer?
    var action: (() -> Void)?
    var tint: NSColor = Palette.icon { didSet { imageView.contentTintColor = tint; needsDisplay = true } }
    var isEnabled = true {
        didSet { imageView.alphaValue = isEnabled ? 1 : 0.35; needsDisplay = true }
    }

    init(symbol: String, size: CGFloat, toolTip: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        imageView.image = .symbol(symbol, size: size)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        self.toolTip = toolTip
    }

    func setSymbol(_ symbol: String, size: CGFloat) {
        imageView.image = .symbol(symbol, size: size)
        needsDisplay = true
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        needsDisplay = true
    }

    // Moves the icon into a layer this view owns so it can rotate; AppKit resets a view's own transform.
    func rotateGlyph(to radians: CGFloat, animated: Bool) {
        let glyph = glyphLayer ?? {
            let glyph = CALayer()
            glyph.contentsGravity = .center
            layer?.addSublayer(glyph)
            glyphLayer = glyph
            imageView.isHidden = true
            updateGlyph()
            needsLayout = true
            return glyph
        }()
        Motion.rotate(glyph, to: radians, animated: animated)
    }

    private func updateGlyph() {
        guard let glyphLayer else { return }
        let color = NSColor(cgColor: tint.cgColor) ?? tint
        glyphLayer.contentsScale = window?.backingScaleFactor ?? 2
        glyphLayer.contents = imageView.image?.tinted(color)
        glyphLayer.opacity = isEnabled ? 1 : 0.35
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        guard let glyphLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        glyphLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.buttonRadius
        layer?.backgroundColor = (isHovered && isEnabled) ? Palette.tabHover.cgColor : nil
        updateGlyph()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = Palette.tabActive.cgColor
        Motion.press(self, scale: 0.9)
    }

    override func mouseUp(with event: NSEvent) {
        needsDisplay = true
        Motion.release(self)
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

@MainActor
final class HairlineView: NSView {
    var inset: CGFloat
    var color: NSColor

    init(inset: CGFloat = 10, color: NSColor = Palette.hairline) {
        self.inset = inset
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let mid = convertToBacking(NSPoint(x: 0, y: bounds.midY)).y
        let pixel = convertFromBacking(NSRect(x: 0, y: floor(mid), width: 1, height: 1)).standardized
        NSRect(x: inset, y: pixel.minY, width: bounds.width - inset * 2, height: pixel.height).fill()
    }
}

extension NSTextField {
    static func sidebarLabel(_ text: String = "", font: NSFont = Typography.sidebar, color: NSColor = Palette.text) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.maximumNumberOfLines = 1
        return label
    }
}

struct ToastAction {
    var symbol: String?
    var title: String?
    var toolTip: String?
    var isPrimary = false
    var handler: @MainActor (NSView) -> Void

    init(symbol: String, toolTip: String? = nil, handler: @escaping @MainActor (NSView) -> Void) {
        self.symbol = symbol
        self.toolTip = toolTip
        self.handler = handler
    }

    init(title: String, isPrimary: Bool = false, handler: @escaping @MainActor (NSView) -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.handler = handler
    }
}

// Transient notification pill shown over the page; present it through RootView.showToast.
@MainActor
final class ToastView: HoverView {
    private static let height: CGFloat = 44
    private static let inset: CGFloat = 16
    private static let actionSize: CGFloat = 30
    private static let actionSpacing: CGFloat = 6

    var onDismiss: (() -> Void)?
    var onHide: (() -> Void)?
    var wasReplaced = false
    var fillColor: NSColor = Palette.ink { didSet { needsDisplay = true } }

    private let label: NSTextField
    private let iconView = NSImageView()
    private var actionViews: [NSView] = []
    private let duration: TimeInterval
    private var dismissWork: DispatchWorkItem?

    convenience init(message: String, icon: String? = nil, action: ToastAction? = nil, duration: TimeInterval = 2.5) {
        self.init(message: message, icon: icon, actions: action.map { [$0] } ?? [], duration: duration)
    }

    init(message: String, icon: String? = nil, actions: [ToastAction], duration: TimeInterval = 2.5) {
        label = .sidebarLabel(message, font: .inter(14, weight: .semibold), color: Palette.text)
        label.lineBreakMode = .byClipping
        self.duration = duration
        super.init(frame: .zero)
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Metrics.shadowOpacity
        layer?.shadowRadius = Metrics.shadowRadius
        layer?.shadowOffset = Metrics.shadowOffset
        addSubview(label)
        if let icon {
            iconView.image = .symbol(icon, size: 14, weight: .semibold)
            iconView.contentTintColor = Palette.text
            iconView.imageScaling = .scaleNone
            addSubview(iconView)
        }
        for action in actions {
            let view = makeActionView(action)
            addSubview(view)
            actionViews.append(view)
        }
        setFrameSize(NSSize(width: ceil(contentWidth), height: Self.height))
    }

    private func makeActionView(_ action: ToastAction) -> NSView {
        if let title = action.title {
            let button = ToastTextButton(title: title, isPrimary: action.isPrimary)
            button.action = { [weak self, weak button] in
                guard let self, let button else { return }
                action.handler(button)
                self.dismiss()
            }
            return button
        }
        let background = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.cornerCurve = .continuous
        let button = IconButton(symbol: action.symbol ?? "", size: 14, toolTip: action.toolTip)
        button.tint = Palette.text
        button.action = { [weak self, weak button] in
            guard let self, let button else { return }
            action.handler(button)
            self.scheduleDismiss(after: 1.5)
        }
        background.addSubview(button)
        return background
    }

    private func actionWidth(_ view: NSView) -> CGFloat {
        (view as? ToastTextButton)?.fittingWidth ?? Self.actionSize
    }

    private var hasIcon: Bool { iconView.image != nil }
    private var textWidth: CGFloat { ceil(max(label.cell?.cellSize.width ?? 0, label.attributedStringValue.size().width + 4)) }
    private var textX: CGFloat { Self.inset + (hasIcon ? 22 : 0) }

    private var contentWidth: CGFloat {
        guard !actionViews.isEmpty else { return textX + textWidth + Self.inset }
        let actions = actionViews.reduce(0) { $0 + actionWidth($1) } + Self.actionSpacing * CGFloat(actionViews.count - 1)
        return textX + textWidth + 12 + actions + 7
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: Self.inset - 2, y: (h - 20) / 2, width: 20, height: 20)
        label.frame = NSRect(x: textX, y: (h - 18) / 2, width: textWidth, height: 18)
        var x = bounds.width - 7
        for view in actionViews.reversed() {
            let width = actionWidth(view)
            x -= width
            view.frame = NSRect(x: x, y: (h - Self.actionSize) / 2, width: width, height: Self.actionSize)
            view.subviews.first { $0 is IconButton }?.frame = view.bounds
            x -= Self.actionSpacing
        }
    }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = Palette.hairline.cgColor
        for view in actionViews where !(view is ToastTextButton) {
            view.layer?.backgroundColor = Palette.tabActive.cgColor
        }
    }

    override func hoverChanged() {
        if isHovered { dismissWork?.cancel() } else { scheduleDismiss(after: 1.2) }
    }

    override func mouseDown(with event: NSEvent) {}

    func present(in parent: NSView, at origin: NSPoint) {
        setFrameOrigin(origin)
        parent.addSubview(self)
        if !Motion.reduced, let layer {
            let move = CASpringAnimation(keyPath: "transform.translation.y")
            move.fromValue = -10
            move.toValue = 0
            move.stiffness = 260
            move.damping = 22
            move.duration = move.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.18
            layer.add(move, forKey: "in.move")
            layer.add(fade, forKey: "in.fade")
        }
        scheduleDismiss(after: duration)
    }

    func scheduleDismiss(after delay: TimeInterval) {
        dismissWork?.cancel()
        guard duration.isFinite else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        guard superview != nil else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduced ? 0 : 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview()
            self?.onDismiss?()
            self?.onHide?()
        })
    }
}

@MainActor
final class ToastTextButton: HoverView {
    var action: (() -> Void)?
    private let label: NSTextField
    private let isPrimary: Bool

    private let fill = AccentFill()

    init(title: String, isPrimary: Bool) {
        label = .sidebarLabel(title, font: .inter(13, weight: isPrimary ? .semibold : .medium),
                              color: isPrimary ? .white : Palette.pillText)
        label.alignment = .center
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        if isPrimary { fill.install(in: self) }
        addSubview(label)
    }

    var fittingWidth: CGFloat { ceil(label.attributedStringValue.size().width) + 22 }

    override func layout() {
        super.layout()
        needsDisplay = true
        label.frame = NSRect(x: 0, y: (bounds.height - 17) / 2, width: bounds.width, height: 17)
    }

    override func updateLayer() {
        if isPrimary {
            fill.update(in: self, accent: Palette.accent, hovered: isHovered)
        } else {
            layer?.backgroundColor = isHovered ? Palette.tabHover.cgColor : nil
        }
    }

    override func hoverChanged() {
        if !isPrimary { label.textColor = isHovered ? Palette.text : Palette.pillText }
    }

    override func mouseDown(with event: NSEvent) {
        Motion.press(self, scale: 0.95)
    }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

@MainActor
final class AccentFill {
    private let gradient = CAGradientLayer()

    func install(in view: NSView) {
        view.wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerCurve = .continuous
        view.layer?.insertSublayer(gradient, at: 0)
        view.layer?.masksToBounds = false
    }

    func update(in view: NSView, accent: NSColor, hovered: Bool) {
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = layer.bounds
        gradient.cornerRadius = layer.cornerRadius
        gradient.colors = Palette.accentGradient(accent)
        CATransaction.commit()
        layer.backgroundColor = nil
        layer.shadowColor = accent.cgColor
        layer.shadowOpacity = hovered ? 0.4 : 0.3
        layer.shadowRadius = hovered ? 12 : 8
        layer.shadowOffset = CGSize(width: 0, height: hovered ? -8 : -4)
    }
}

struct ActionMenuItem {
    var title: String
    var symbol: String
    var shortcut: String?
    var handler: @MainActor () -> Void
}

enum ActionMenuEntry {
    case item(ActionMenuItem)
    case separator
}

// Arc-style popover menu of large icon rows; show it with ActionMenu.show(_:relativeTo:).
@MainActor
final class ActionMenu: NSObject, NSPopoverDelegate {
    private static let width: CGFloat = 228
    private static let rowHeight: CGFloat = 40
    private static let inset: CGFloat = 8

    var onClose: (() -> Void)?
    private let popover = NSPopover()
    private(set) var closedAt: CFTimeInterval = 0

    var isShown: Bool { popover.isShown }

    init(entries: [ActionMenuEntry]) {
        super.init()
        let content = ActionMenuContentView()
        var y = Self.inset
        for entry in entries {
            switch entry {
            case .item(let item):
                let row = ActionMenuRow(item: item)
                row.frame = NSRect(x: Self.inset, y: y, width: Self.width - 2 * Self.inset, height: Self.rowHeight)
                row.onSelect = { [weak self] in
                    self?.popover.performClose(nil)
                    item.handler()
                }
                content.addSubview(row)
                y += Self.rowHeight
            case .separator:
                let line = HairlineView(inset: 0)
                line.frame = NSRect(x: Self.inset + 10, y: y + 5, width: Self.width - 2 * Self.inset - 20, height: 1)
                content.addSubview(line)
                y += 11
            }
        }
        content.frame = NSRect(x: 0, y: 0, width: Self.width, height: y + Self.inset)
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = !Motion.reduced
        popover.delegate = self
        content.onCancel = { [weak self] in self?.close() }
    }

    func show(relativeTo view: NSView, edge: NSRectEdge = .minY) {
        popover.appearance = view.effectiveAppearance
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
        let content = popover.contentViewController?.view
        content?.window?.makeKey()
        content?.window?.makeFirstResponder(content)
    }

    func show(at point: NSPoint, in view: NSView, edge: NSRectEdge) {
        popover.appearance = view.effectiveAppearance
        popover.show(relativeTo: NSRect(x: point.x, y: point.y, width: 1, height: 1), of: view, preferredEdge: edge)
        let content = popover.contentViewController?.view
        content?.window?.makeKey()
        content?.window?.makeFirstResponder(content)
    }

    func close() { popover.performClose(nil) }

    func popoverWillClose(_ notification: Notification) {
        closedAt = CACurrentMediaTime()
        onClose?()
    }
}

@MainActor
final class ActionMenuContentView: NSView {
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class ActionMenuRow: HoverView {
    var onSelect: (() -> Void)?
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let shortcutLabel: NSTextField

    init(item: ActionMenuItem) {
        titleLabel = .sidebarLabel(item.title, font: .inter(14, weight: .semibold), color: Palette.text)
        shortcutLabel = .sidebarLabel(item.shortcut ?? "", font: .inter(13), color: Palette.faint)
        shortcutLabel.alignment = .right
        super.init(frame: .zero)
        iconView.image = .symbol(item.symbol, size: 16, weight: .medium)
        iconView.contentTintColor = Palette.text
        iconView.imageScaling = .scaleNone
        for view in [iconView, titleLabel, shortcutLabel] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 8, y: (h - 24) / 2, width: 24, height: 24)
        shortcutLabel.frame = NSRect(x: bounds.width - 60, y: (h - 17) / 2, width: 50, height: 17)
        let titleEnd = shortcutLabel.stringValue.isEmpty ? bounds.width - 10 : shortcutLabel.frame.minX - 4
        titleLabel.frame = NSRect(x: 42, y: (h - 18) / 2, width: titleEnd - 42, height: 18)
    }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered ? Palette.tabHover.cgColor : nil
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.97) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect?()
    }
}

final class LoadingRing: NSView {
    var lineWidth: CGFloat = 1.5 { didSet { needsLayout = true } }
    var color: NSColor = Palette.icon { didSet { needsDisplay = true } }
    var spins = true

    private let spin = CALayer()
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private(set) var isAnimating = false
    private var progress: CGFloat = 0
    private var finishWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineCap = .round
            spin.addSublayer(shape)
        }
        arc.strokeEnd = 0
        layer?.addSublayer(spin)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        spin.bounds = CGRect(origin: .zero, size: rect.size)
        spin.position = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (side - lineWidth) / 2 - 1
        let center = CGPoint(x: side / 2, y: side / 2)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        for shape in [track, arc] {
            shape.frame = spin.bounds
            shape.path = path
            shape.lineWidth = lineWidth
        }
        CATransaction.commit()
    }

    override func updateLayer() {
        let cg = color.cgColor
        track.strokeColor = cg.copy(alpha: cg.alpha * 0.3)
        arc.strokeColor = cg
    }

    func start(progress initial: CGFloat) {
        let wasFinishing = finishWork != nil
        finishWork?.cancel()
        finishWork = nil
        alphaValue = 1
        if !isAnimating || wasFinishing {
            isAnimating = true
            isHidden = false
            alphaValue = 1
            progress = 0
            setStroke(0, animated: false)
        }
        if spins, spin.animation(forKey: "spin") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = 2 * CGFloat.pi
            rotation.duration = 2
            rotation.repeatCount = .infinity
            spin.add(rotation, forKey: "spin")
        }
        setProgress(initial)
    }

    func setProgress(_ value: CGFloat) {
        let clamped = min(max(value, 0.08), 1)
        guard clamped > progress else { return }
        progress = clamped
        setStroke(clamped, animated: true)
    }

    func finish(completion: @escaping @MainActor () -> Void) {
        guard isAnimating else { completion(); return }
        if finishWork != nil { return }
        progress = 1
        setStroke(1, animated: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 0
            }
            let done = DispatchWorkItem { [weak self] in
                guard let self, self.finishWork != nil else { return }
                self.stop()
                completion()
            }
            self.finishWork = done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: done)
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop() {
        finishWork?.cancel()
        finishWork = nil
        isAnimating = false
        isHidden = true
        alphaValue = 1
        spin.removeAnimation(forKey: "spin")
        progress = 0
        setStroke(0, animated: false)
    }

    private func setStroke(_ value: CGFloat, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        arc.strokeEnd = value
        CATransaction.commit()
    }
}
