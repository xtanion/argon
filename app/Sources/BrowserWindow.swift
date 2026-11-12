import AppKit

// Window with the traffic lights centred on the sidebar's first row.
@MainActor
final class BrowserWindow: NSWindow {
    private var buttonPitch: CGFloat?

    var trafficLightsMaxX: CGFloat {
        let width = standardWindowButton(.zoomButton)?.frame.width ?? 14
        return Metrics.trafficLightInset + 2 * (buttonPitch ?? 20) + width
    }
    var trafficLightsHidden = false { didSet { if trafficLightsHidden != oldValue { positionTrafficLights() } } }
    var trafficLightOffset: NSPoint = .zero { didSet { if trafficLightOffset != oldValue { positionTrafficLights() } } }
    var isTranslucent = false {
        didSet {
            guard isTranslucent != oldValue else { return }
            isOpaque = !isTranslucent
            backgroundColor = isTranslucent ? .clear : .windowBackgroundColor
            invalidateShadow()
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        minSize = NSSize(width: 640, height: 420)
        collectionBehavior.insert(.fullScreenPrimary)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    func positionTrafficLights() {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { standardWindowButton($0) }
        guard buttons.count == 3, let container = buttons[0].superview?.superview else { return }
        if buttonPitch == nil {
            buttonPitch = buttons[1].frame.minX - buttons[0].frame.minX
            (contentView as? RootView)?.sidebar.needsLayout = true
        }
        for button in buttons { button.isHidden = trafficLightsHidden }
        guard !styleMask.contains(.fullScreen) else { return }
        let height = Metrics.titlebarHeight
        var frame = container.frame
        if frame.height != height || frame.minY != self.frame.height - height {
            frame.size.height = height
            frame.origin.y = self.frame.height - height
            container.frame = frame
        }
        for (index, button) in buttons.enumerated() {
            let origin = NSPoint(
                x: Metrics.trafficLightInset + trafficLightOffset.x + CGFloat(index) * (buttonPitch ?? 20),
                y: (height - button.frame.height) / 2 - trafficLightOffset.y
            )
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

@MainActor
final class ContentCardView: NSView {
    private(set) var pageView: NSView?
    var isFullBleed = false { didSet { updateLayer() } }
    // Set while the frame is translucent, so the empty card stays solid instead of showing the desktop.
    var solidBase: NSColor? { didSet { if solidBase != oldValue { updateLayer() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = isFullBleed ? 0 : Metrics.cardRadius
        if let solidBase {
            layer?.backgroundColor = Palette.opaque(Palette.placeholder, on: solidBase, appearance: effectiveAppearance).cgColor
        } else {
            layer?.backgroundColor = Palette.placeholder.cgColor
        }
    }

    func show(_ view: NSView?) {
        guard view !== pageView else { return }
        pageView?.removeFromSuperview()
        pageView = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view, positioned: .below, relativeTo: nil)
    }
}

@MainActor
final class FrameBackdropView: NSView {
    private let tint = NSView()
    private var blur: NSVisualEffectView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        tint.wantsLayer = true
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var tintColor: CGColor? {
        get { tint.layer?.backgroundColor }
        set { tint.layer?.backgroundColor = newValue }
    }

    var blursBehindWindow = false {
        didSet {
            guard blursBehindWindow != oldValue else { return }
            if blursBehindWindow, blur == nil {
                let view = NSVisualEffectView(frame: bounds)
                view.autoresizingMask = [.width, .height]
                view.blendingMode = .behindWindow
                view.material = .underWindowBackground
                view.state = .active
                addSubview(view, positioned: .below, relativeTo: tint)
                blur = view
            }
            blur?.isHidden = !blursBehindWindow
        }
    }
}

@MainActor
final class SidebarResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) { onEnd?() }
}

// Geometry-only tracking region: never hit-tested, so clicks pass through.
@MainActor
final class TrackingRegionView: NSView {
    private let assumeInside: Bool
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    init(assumeInside: Bool = false) {
        self.assumeInside = assumeInside
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        if assumeInside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    var containsMouse: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

@MainActor
final class RootView: NSView {
    let sidebar = SidebarView()
    let card = ContentCardView()
    private let backdrop = FrameBackdropView()
    let resizeHandle = SidebarResizeHandle()
    private let edgeTracker = TrackingRegionView()
    private let peekTracker = TrackingRegionView(assumeInside: true)
    private var hideWork: DispatchWorkItem?
    private(set) var sidebarPeeking = false
    var commandBar: CommandBarView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let commandBar { addSubview(commandBar) }
            if commandBar == nil, sidebarPeeking, !peekTracker.containsMouse { schedulePeekHide() }
            needsLayout = true
        }
    }
    var sidebarWidth = Metrics.sidebarWidth { didSet { needsLayout = true } }
    private(set) var sidebarOnRight = false
    private var pendingSide: Bool?

    func setSidebarOnRight(_ right: Bool, animated: Bool) {
        guard right != (pendingSide ?? sidebarOnRight) else { return }
        endPeek(animated: false)
        guard animated, !sidebarHidden, !contentFullscreen, !Motion.reduced, window != nil else {
            commitSide(right)
            return
        }
        let sliding = pendingSide != nil
        pendingSide = right
        guard !sliding else { return }
        animateDock(to: 0, keepingPendingSide: true) { [weak self] in
            guard let self else { return }
            self.commitPendingSide()
            self.animateDock(to: self.sidebarHidden ? 0 : 1)
        }
    }

    private func commitSide(_ right: Bool) {
        pendingSide = nil
        sidebarOnRight = right
        sidebar.isOnRight = right
        needsLayout = true
    }

    private func commitPendingSide() {
        if let pendingSide { commitSide(pendingSide) }
    }
    var sidebarHidden = false {
        didSet {
            guard sidebarHidden != oldValue else { return }
            let fromPeek = sidebarPeeking && !sidebarHidden
            endPeek(animated: false)
            dockFromPeek = fromPeek
            animateDock(to: sidebarHidden ? 0 : 1)
        }
    }
    private var dockProgress: CGFloat = 1
    private var dockFromPeek = false
    private var dockTicker: FrameTicker?
    var contentFullscreen = false { didSet { needsLayout = true; card.isFullBleed = contentFullscreen } }
    private(set) var frameColor: NSColor = Palette.ink
    private(set) var frameOpacity: CGFloat = 1
    private var shownOpacity: CGFloat = 1
    private var toast: ToastView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backdrop.tintColor = frameColor.cgColor
        addSubview(backdrop)
        addSubview(card)
        addSubview(sidebar)
        addSubview(resizeHandle)
        addSubview(edgeTracker)
        addSubview(peekTracker)
        sidebar.wantsLayer = true
        edgeTracker.onEnter = { [weak self] in self?.beginPeek() }
        peekTracker.onEnter = { [weak self] in self?.cancelPeekHide() }
        peekTracker.onExit = { [weak self] in
            guard let self, self.commandBar == nil else { return }
            self.schedulePeekHide()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setFrameColor(_ color: NSColor, opacity: CGFloat = 1, animated: Bool = true) {
        frameColor = color
        frameOpacity = min(max(opacity, Palette.minimumOpacity), 1)
        Palette.frameIsVeryLight = color.relativeLuminance > 0.85
        if let window {
            let name: NSAppearance.Name = color.isDarkFrame ? .darkAqua : .aqua
            if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
        }
        redisplayTree()
        styleSidebar(floating: sidebarPeeking)
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !Motion.reduced ? 0.25 : 0)
        CATransaction.setDisableActions(!animated || Motion.reduced)
        // Stay translucent until a fade back to opaque has finished.
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.updateTranslucency() }
        }
        applyTint(color, opacity: frameOpacity)
        toast?.fillColor = toastFill
        if sidebarPeeking { sidebar.layer?.backgroundColor = color.cgColor }
        CATransaction.commit()
    }

    // Cheap per-frame tint used while a space swipe is in flight; setFrameColor applies it fully.
    func previewFrameColor(_ color: NSColor, opacity: CGFloat = 1) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyTint(color, opacity: min(max(opacity, Palette.minimumOpacity), 1))
        if sidebarPeeking { sidebar.layer?.backgroundColor = color.cgColor }
        CATransaction.commit()
    }

    private func applyTint(_ color: NSColor, opacity: CGFloat) {
        shownOpacity = opacity
        if opacity < 1 { setTranslucent(true) }
        backdrop.tintColor = opacity < 1 ? color.withAlphaComponent(opacity).cgColor : color.cgColor
        card.solidBase = opacity < 1 ? color : nil
    }

    private func updateTranslucency() {
        if shownOpacity >= 1 { setTranslucent(false) }
    }

    private func setTranslucent(_ translucent: Bool) {
        backdrop.blursBehindWindow = translucent
        (window as? BrowserWindow)?.isTranslucent = translucent
    }

    override func layout() {
        super.layout()
        let inset = Metrics.cardInset
        let w = sidebarWidth
        let h = bounds.height
        sidebar.isHidden = contentFullscreen || (!sidebarPeeking && dockProgress == 0)
        resizeHandle.isHidden = contentFullscreen || sidebarHidden || dockProgress < 1
        edgeTracker.isHidden = !sidebarHidden || contentFullscreen || sidebarPeeking
        peekTracker.isHidden = !sidebarPeeking
        let floating = NSRect(x: inset, y: inset, width: w, height: h - 2 * inset)
        let fullCard = bounds.insetBy(dx: inset, dy: inset)
        backdrop.frame = bounds
        if contentFullscreen {
            card.frame = bounds
        } else if sidebarPeeking {
            card.frame = fullCard
            sidebar.frame = mirrored(floating)
            sidebar.layer?.shadowPath = CGPath(roundedRect: sidebar.bounds, cornerWidth: Metrics.cardRadius, cornerHeight: Metrics.cardRadius, transform: nil)
        } else {
            let docked = NSRect(x: 0, y: 0, width: w, height: h)
            let dockedCard = NSRect(x: w, y: inset, width: bounds.width - w - inset, height: h - 2 * inset)
            let hidden = dockFromPeek ? floating : NSRect(x: -w, y: 0, width: w, height: h)
            sidebar.frame = mirrored(Self.lerp(hidden, docked, dockProgress))
            card.frame = mirrored(Self.lerp(fullCard, dockedCard, dockProgress).integral)
            resizeHandle.frame = mirrored(NSRect(x: w - 3, y: Metrics.titlebarHeight, width: 6, height: h - Metrics.titlebarHeight))
        }
        edgeTracker.frame = mirrored(NSRect(x: 0, y: 0, width: inset + 4, height: h))
        let reach = sidebarOnRight ? bounds.width - sidebar.frame.minX : sidebar.frame.maxX
        peekTracker.frame = mirrored(NSRect(x: 0, y: 0, width: reach + 16, height: h))
        commandBar?.frame = bounds
        if let toast { toast.setFrameOrigin(toastOrigin(for: toast)) }
        updateChrome()
    }

    private func mirrored(_ rect: NSRect) -> NSRect {
        guard sidebarOnRight else { return rect }
        return NSRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    private var peekOffset: CGFloat {
        sidebarOnRight ? bounds.width - sidebar.frame.minX + 20 : -(sidebar.frame.maxX + 20)
    }

    func showToast(_ message: String, icon: String? = nil, action: ToastAction? = nil, duration: TimeInterval = 2.5) {
        showToast(ToastView(message: message, icon: icon, action: action, duration: duration))
    }

    func showToast(_ newToast: ToastView) {
        toast?.wasReplaced = true
        toast?.dismiss()
        toast = newToast
        newToast.fillColor = toastFill
        newToast.onDismiss = { [weak self, weak newToast] in
            if self?.toast === newToast { self?.toast = nil }
        }
        newToast.present(in: self, at: toastOrigin(for: newToast))
    }

    var toastFill: NSColor { Palette.opaque(Palette.surface, on: frameColor, appearance: effectiveAppearance) }

    private func toastOrigin(for toast: ToastView) -> NSPoint {
        NSPoint(x: card.frame.maxX - 14 - toast.frame.width, y: card.frame.minY + 14)
    }

    private static func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    private func animateDock(to target: CGFloat, keepingPendingSide: Bool = false, completion: (() -> Void)? = nil) {
        if !keepingPendingSide { commitPendingSide() }
        dockTicker?.stop()
        dockTicker = nil
        let start = dockProgress
        guard !Motion.reduced, window != nil, start != target else {
            dockProgress = target
            dockFromPeek = false
            needsLayout = true
            completion?()
            return
        }
        let duration = 0.2 * Double(abs(target - start))
        let began = CACurrentMediaTime()
        dockTicker = FrameTicker(view: self) { [weak self] now in
            guard let self else { return false }
            let t = min(1, (now - began) / duration)
            self.dockProgress = start + (target - start) * CGFloat(Motion.slide(t))
            if t >= 1 {
                self.dockProgress = target
                self.dockFromPeek = false
                self.dockTicker = nil
            }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            if t >= 1 { completion?() }
            return t < 1
        }
    }

    // MARK: Sidebar peek

    private func beginPeek() {
        cancelPeekHide()
        guard sidebarHidden, !contentFullscreen, !sidebarPeeking else { return }
        sidebarPeeking = true
        styleSidebar(floating: true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateChrome()
        sidebar.layer?.removeAnimation(forKey: "peek")
        guard !Motion.reduced, let layer = sidebar.layer else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = peekOffset
        slide.toValue = 0
        slide.duration = 0.22
        slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer.add(slide, forKey: "peek")
    }

    private func schedulePeekHide() {
        cancelPeekHide()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.sidebarPeeking else { return }
                if self.peekTracker.containsMouse { return }
                if let window = self.window, window.attachedSheet != nil || !(window.childWindows ?? []).isEmpty {
                    self.schedulePeekHide()
                    return
                }
                self.endPeek(animated: true)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelPeekHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func endPeek(animated: Bool) {
        cancelPeekHide()
        guard sidebarPeeking else { return }
        let finish = { [weak self] in
            guard let self else { return }
            self.sidebar.layer?.removeAnimation(forKey: "peek")
            self.sidebarPeeking = false
            self.styleSidebar(floating: false)
            self.needsLayout = true
            self.updateChrome()
        }
        guard animated, !Motion.reduced, let layer = sidebar.layer else {
            finish()
            return
        }
        (window as? BrowserWindow)?.trafficLightsHidden = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { finish() } }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = 0
        slide.toValue = peekOffset
        slide.duration = 0.18
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        slide.fillMode = .forwards
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: "peek")
        CATransaction.commit()
    }

    private func styleSidebar(floating: Bool) {
        guard let layer = sidebar.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = floating ? frameColor.cgColor : nil
        layer.cornerRadius = floating ? Metrics.cardRadius : 0
        layer.cornerCurve = .continuous
        layer.borderWidth = floating ? 0.5 : 0
        layer.borderColor = sidebar.cg(Palette.white(0x24))
        layer.shadowOpacity = floating ? Metrics.shadowOpacity : 0
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = Metrics.shadowRadius
        layer.shadowOffset = Metrics.shadowOffset
        layer.masksToBounds = false
        CATransaction.commit()
    }

    private func updateChrome() {
        guard let window = window as? BrowserWindow else { return }
        let visible = !sidebar.isHidden && !contentFullscreen
        window.trafficLightOffset = visible ? sidebar.frame.origin : .zero
        window.trafficLightsHidden = !visible
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? BrowserWindow)?.isTranslucent = shownOpacity < 1
        updateChrome()
    }
}
