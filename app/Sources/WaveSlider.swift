import AppKit

@MainActor
final class WaveSlider: NSView {
    var onChange: ((Double) -> Void)?
    var minValue = 0.0
    var maxValue = 1.0
    var detentStep = 0.1
    var keyStep = 0.05
    var label = "" { didSet { setAccessibilityLabel(label) } }

    private(set) var value = 1.0
    private var shown = 1.0
    private var tween: FrameTicker?
    private var dragOffset: CGFloat?
    private var isDragging = false { didSet { if isDragging != oldValue { needsDisplay = true } } }

    private static let trackHeight: CGFloat = 14
    private static let thumbSize = NSSize(width: 14, height: 32)
    private static let minAmplitude: CGFloat = 0.8
    private static let maxAmplitude: CGFloat = 5.5
    private static let wavelength: CGFloat = 26
    private static let lineWidth: CGFloat = 3.2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.thumbSize.height + 8) }

    func setValue(_ newValue: Double, animated: Bool = false) {
        value = clamp(newValue)
        animated ? animateShown() : snapShown()
    }

    private var track: NSRect {
        NSRect(x: bounds.minX, y: bounds.midY - Self.trackHeight / 2, width: bounds.width, height: Self.trackHeight)
    }

    private var travel: ClosedRange<CGFloat> {
        let inset = Self.trackHeight / 2
        return (bounds.minX + inset)...max(bounds.minX + inset, bounds.maxX - inset)
    }

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((v - minValue) / max(maxValue - minValue, .ulpOfOne))
    }

    private func position(for v: Double) -> CGFloat {
        travel.lowerBound + (travel.upperBound - travel.lowerBound) * min(max(fraction(v), 0), 1)
    }

    private func value(at x: CGFloat) -> Double {
        let width = max(travel.upperBound - travel.lowerBound, 1)
        let t = Double(min(max((x - travel.lowerBound) / width, 0), 1))
        return minValue + (maxValue - minValue) * t
    }

    private func thumbRect(at x: CGFloat) -> NSRect {
        let size = Self.thumbSize
        return NSRect(x: x - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, minValue), maxValue) }

    override func draw(_ dirtyRect: NSRect) {
        let dark = Palette.isDark(effectiveAppearance)
        let ink: NSColor = dark ? .white : .black
        let track = track
        let x = position(for: shown)

        let capsule = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        ink.withAlphaComponent(dark ? 0.08 : 0.06).setFill()
        capsule.fill()

        let amplitude = Self.minAmplitude + (Self.maxAmplitude - Self.minAmplitude) * min(max(fraction(shown), 0), 1)
        let wave = Self.wave(from: travel.lowerBound, to: travel.upperBound, midY: track.midY, amplitude: amplitude)
        wave.lineWidth = Self.lineWidth
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        for (rect, alpha) in [(NSRect(x: bounds.minX, y: bounds.minY, width: x - bounds.minX, height: bounds.height), dark ? 0.62 : 0.46),
                              (NSRect(x: x, y: bounds.minY, width: bounds.maxX - x, height: bounds.height), dark ? 0.2 : 0.14)] {
            NSGraphicsContext.saveGraphicsState()
            rect.clip()
            ink.withAlphaComponent(alpha).setStroke()
            wave.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }

        let thumb = thumbRect(at: x).insetBy(dx: isDragging ? -0.5 : 0, dy: isDragging ? -1 : 0)
        let pill = NSBezierPath(roundedRect: thumb, xRadius: thumb.width / 2, yRadius: thumb.width / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.22)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()
        if !dark {
            NSColor.black.withAlphaComponent(0.1).setStroke()
            pill.lineWidth = 0.5
            pill.stroke()
        }
    }

    private static func wave(from start: CGFloat, to end: CGFloat, midY: CGFloat, amplitude: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let step: CGFloat = 1
        var x = start
        path.move(to: NSPoint(x: x, y: midY))
        while x < end {
            x = min(x + step, end)
            path.line(to: NSPoint(x: x, y: midY - amplitude * sin((x - start) / wavelength * 2 * .pi)))
        }
        return path
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = position(for: value)
        if thumbRect(at: x).insetBy(dx: -6, dy: -4).contains(point) {
            dragOffset = point.x - x
        } else {
            dragOffset = 0
            update(to: value(at: point.x), haptics: false)
            animateShown()
        }
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOffset else { return }
        let point = convert(event.locationInWindow, from: nil)
        update(to: value(at: point.x - dragOffset), haptics: true)
        if tween == nil { snapShown() }
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = nil
        isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard dx != 0 || dy != 0 else { return }
        var delta = abs(dx) > abs(dy) ? -dx : dy
        if event.isDirectionInvertedFromDevice { delta = -delta }
        let width = max(travel.upperBound - travel.lowerBound, 1)
        let change = event.hasPreciseScrollingDeltas
            ? Double(delta / width) * (maxValue - minValue)
            : (delta > 0 ? 1 : -1) * keyStep
        update(to: value + change, haptics: true)
        tween?.stop()
        tween = nil
        snapShown()
    }

    override func keyDown(with event: NSEvent) {
        let amount = event.modifierFlags.contains(.option) ? 0.01 : keyStep
        switch event.specialKey {
        case .leftArrow?, .downArrow?: step(by: -amount)
        case .rightArrow?, .upArrow?: step(by: amount)
        case .home?: step(by: minValue - value)
        case .end?: step(by: maxValue - value)
        default: super.keyDown(with: event)
        }
    }

    private func step(by amount: Double) {
        update(to: value + amount, haptics: false)
        animateShown()
    }

    private func update(to newValue: Double, haptics: Bool) {
        let old = value
        let new = clamp(newValue)
        guard new != old else { return }
        value = new
        if haptics { playHaptics(from: old, to: new) }
        setAccessibilityValue(accessibilityValueText)
        NSAccessibility.post(element: self, notification: .valueChanged)
        onChange?(new)
    }

    private func playHaptics(from old: Double, to new: Double) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        if new == minValue || new == maxValue {
            performer.perform(.levelChange, performanceTime: .now)
            return
        }
        guard detentStep > 0 else { return }
        func detent(_ v: Double) -> Int { Int(((v - minValue) / detentStep + 1e-6).rounded(.down)) }
        if detent(old) != detent(new) { performer.perform(.alignment, performanceTime: .now) }
    }

    private func snapShown() {
        tween?.stop()
        tween = nil
        shown = value
        setAccessibilityValue(accessibilityValueText)
        needsDisplay = true
    }

    private func animateShown() {
        tween?.stop()
        let from = shown
        tween = Motion.tween(on: self, duration: 0.24) { [weak self] t in
            guard let self else { return }
            self.shown = from + (self.value - from) * Double(t)
            self.needsDisplay = true
            if t >= 1 { self.tween = nil }
        }
        if tween == nil {
            shown = value
            needsDisplay = true
        }
    }

    private var accessibilityValueText: String { "\(Int((value * 100).rounded()))%" }

    override func accessibilityMinValue() -> Any? { minValue }
    override func accessibilityMaxValue() -> Any? { maxValue }

    override func accessibilityPerformIncrement() -> Bool {
        step(by: keyStep)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        step(by: -keyStep)
        return true
    }
}
