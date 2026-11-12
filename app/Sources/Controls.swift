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

    init(symbol: String, size: CGFloat, weight: NSFont.Weight = .regular, toolTip: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        imageView.image = .symbol(symbol, size: size, weight: weight)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        self.toolTip = toolTip
    }

    func setSymbol(_ symbol: String, size: CGFloat, weight: NSFont.Weight = .regular) {
        imageView.image = .symbol(symbol, size: size, weight: weight)
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
        label = .sidebarLabel(message, font: .systemFont(ofSize: 14, weight: .semibold), color: Palette.text)
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
        label = .sidebarLabel(title, font: .systemFont(ofSize: 13, weight: isPrimary ? .semibold : .medium),
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
    var shortcut: String?
    var handler: @MainActor () -> Void
}

enum ActionMenuEntry {
    case item(ActionMenuItem)
    case separator
}

@MainActor
final class ActionMenu: NSObject, NSMenuDelegate {
    var onClose: (() -> Void)?
    private let menu = NSMenu()
    private(set) var isShown = false
    private(set) var closedAt: CFTimeInterval = 0

    private static let modifiers: [(Character, NSEvent.ModifierFlags)] = [
        ("\u{2303}", .control), ("\u{2325}", .option), ("\u{21E7}", .shift), ("\u{2318}", .command),
    ]

    init(entries: [ActionMenuEntry]) {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        for entry in entries {
            switch entry {
            case .item(let item):
                let handler = item.handler
                let menuItem = ClosureMenuItem(item.title) { DispatchQueue.main.async { handler() } }
                if let shortcut = item.shortcut { Self.apply(shortcut, to: menuItem) }
                menu.addItem(menuItem)
            case .separator:
                menu.addItem(.separator())
            }
        }
    }

    private static func apply(_ shortcut: String, to item: NSMenuItem) {
        var mask: NSEvent.ModifierFlags = []
        var key = Substring(shortcut)
        while let first = key.first, let flag = modifiers.first(where: { $0.0 == first })?.1 {
            mask.insert(flag)
            key = key.dropFirst()
        }
        guard !key.isEmpty else { return }
        item.keyEquivalent = mask.contains(.shift) && key.count == 1 ? key.uppercased() : key.lowercased()
        item.keyEquivalentModifierMask = mask.subtracting(key.count == 1 ? .shift : [])
    }

    func show(relativeTo view: NSView, edge: NSRectEdge = .minY) {
        let below = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        let above = view.isFlipped ? view.bounds.minY - 4 : view.bounds.maxY + 4
        menu.appearance = view.effectiveAppearance
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: edge == .maxY ? above : below), in: view)
    }

    func show(at point: NSPoint, in view: NSView, edge: NSRectEdge) {
        menu.appearance = view.effectiveAppearance
        var origin = point
        if edge == .minX { origin.x -= menu.size.width }
        menu.popUp(positioning: nil, at: origin, in: view)
    }

    func close() { menu.cancelTracking() }

    func menuWillOpen(_ menu: NSMenu) { isShown = true }

    func menuDidClose(_ menu: NSMenu) {
        isShown = false
        closedAt = CACurrentMediaTime()
        onClose?()
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

@MainActor
final class FrostView: NSView {
    private let blur = NSVisualEffectView()
    private let wash = NSView()

    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            wash.layer?.cornerRadius = cornerRadius
            wash.layer?.cornerCurve = .continuous
            blur.maskImage = cornerRadius > 0 ? Self.mask(radius: cornerRadius) : nil
        }
    }

    var tint: NSColor = .clear { didSet { if tint != oldValue { applyTint() } } }
    var washOpacity: CGFloat = 0.72 { didSet { if washOpacity != oldValue { applyTint() } } }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = 2 * radius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        blur.blendingMode = .withinWindow
        blur.material = .hudWindow
        blur.state = .active
        wash.wantsLayer = true
        wash.layer?.masksToBounds = true
        for view in [blur, wash] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func accessibilityChanged() { applyTint() }

    private func applyTint() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        blur.isHidden = opaque
        blur.appearance = NSAppearance(named: tint.isDarkFrame ? .darkAqua : .aqua)
        wash.layer?.backgroundColor = tint.withAlphaComponent(opaque ? 1 : washOpacity).cgColor
    }
}
