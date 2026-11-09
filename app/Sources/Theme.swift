import AppKit

enum Metrics {
    static let sidebarWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 190
    static let sidebarMaxWidth: CGFloat = 420
    static let padding: CGFloat = 8
    static let titlebarHeight: CGFloat = 46
    static let rowHeight: CGFloat = 36
    static let tabSpacing: CGFloat = 5
    static let rowRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 6
    static let cardInset: CGFloat = 8
    static let cardRadius: CGFloat = 10
    static let trafficLightInset: CGFloat = 13
    static let toolbarButtonSize: CGFloat = 32
    static let toolbarButtonPitch: CGFloat = 34
    static let iconFrame: CGFloat = 24
    static let faviconSize: CGFloat = 16
    static let spaceBarHeight: CGFloat = 40
    static let spaceButtonSize: CGFloat = 28
    static let spaceButtonGap: CGFloat = 6
    static let spaceIconSize: CGFloat = 13
    static let spaceBarIconSize: CGFloat = 11
    static let titleX: CGFloat = 36
    static let folderIndent: CGFloat = 14
}

enum Palette {
    static let ink = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1)
    nonisolated(unsafe) static var frameIsVeryLight = false

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func dynamic(dark: NSColor, light: @escaping () -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in isDark(appearance) ? dark : light() }
    }

    static func white(_ alpha: Int) -> NSColor {
        let a = CGFloat(alpha) / 255
        return dynamic(dark: NSColor(white: 1, alpha: a)) { NSColor(white: 0, alpha: a) }
    }

    static let surface = dynamic(dark: NSColor(white: 1, alpha: CGFloat(0x1D) / 255)) {
        frameIsVeryLight ? NSColor(white: 0, alpha: CGFloat(0x10) / 255) : NSColor(white: 1, alpha: CGFloat(0x99) / 255)
    }
    static let tabActive = dynamic(dark: NSColor(white: 1, alpha: CGFloat(0x31) / 255)) {
        frameIsVeryLight ? NSColor(white: 0, alpha: CGFloat(0x14) / 255) : NSColor(white: 1, alpha: CGFloat(0xCC) / 255)
    }
    static let tabHover = dynamic(dark: NSColor(white: 1, alpha: CGFloat(0x1A) / 255)) {
        frameIsVeryLight ? NSColor(white: 0, alpha: CGFloat(0x0A) / 255) : NSColor(white: 1, alpha: CGFloat(0x66) / 255)
    }
    static let text = white(0xF0)
    static let pillText = white(0xC8)
    static let icon = white(0xAC)
    static let subtle = white(0x8A)
    static let faint = white(0x66)
    static let hairline = white(0x24)
    static let placeholder = dynamic(dark: NSColor(white: 1, alpha: CGFloat(0x2A) / 255)) { NSColor(white: 0, alpha: CGFloat(0x0F) / 255) }

    static let defaultIntensity = 0.3

    // Flattens a translucent palette color onto `base`, for surfaces drawn over page content.
    static func opaque(_ overlay: NSColor, on base: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = overlay
        appearance.performAsCurrentDrawingAppearance {
            resolved = overlay.usingColorSpace(.sRGB) ?? overlay
        }
        let solid = resolved.withAlphaComponent(1)
        return base.usingColorSpace(.sRGB)?.blended(withFraction: resolved.alphaComponent, of: solid) ?? base
    }

    static func swatch(hue: Double) -> NSColor {
        NSColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1)
    }

    static func frame(hue: Double, intensity: Double = defaultIntensity) -> NSColor {
        let tint = NSColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1)
        return ink.blended(withFraction: 0.04 + 0.4 * min(max(intensity, 0), 1), of: tint) ?? ink
    }

    static func commandBar(frame: NSColor) -> NSColor {
        frame.isDarkFrame
            ? frame.blended(withFraction: 0.08, of: .white) ?? ink
            : frame.blended(withFraction: 0.6, of: .white) ?? .white
    }
}

extension NSView {
    func cg(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    func redisplayTree() {
        needsDisplay = true
        subviews.forEach { $0.redisplayTree() }
    }
}

extension NSColor {
    var relativeLuminance: Double {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    var isDarkFrame: Bool { relativeLuminance < 0.18 }

    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

@MainActor
enum Typography {
    static let sidebar = NSFont.systemFont(ofSize: 13)
    static let sidebarEmphasis = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let commandField = NSFont.systemFont(ofSize: 19)
    static let commandTitle = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let commandSubtitle = NSFont.systemFont(ofSize: 13)
}

@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    nonisolated static func slide(_ t: Double) -> Double {
        cubicBezier(0.32, 0.72, 0, 1, t)
    }

    nonisolated static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        func bez(_ a: Double, _ b: Double, _ t: Double) -> Double {
            3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
        }
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if bez(x1, x2, t) < x { lo = t } else { hi = t }
        }
        return bez(y1, y2, t)
    }

    static let pressDuration: CFTimeInterval = 0.1

    static func press(_ view: NSView, scale: CGFloat = 0.97) {
        guard let layer = view.layer, !reduced else { return }
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
        anim.toValue = NSValue(caTransform3D: centeredScale(layer, scale))
        anim.duration = pressDuration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.removeAnimation(forKey: "release")
        layer.add(anim, forKey: "press")
        layer.setValue(CACurrentMediaTime(), forKey: "pressStart")
        // Rows run a synchronous drag-tracking loop right after pressing, which
        // would otherwise hold the press uncommitted until mouse up.
        CATransaction.flush()
    }

    // Quick clicks wait for the press to bottom out so the dip is always visible.
    static func release(_ view: NSView) {
        guard let layer = view.layer, let press = layer.animation(forKey: "press") as? CABasicAnimation else { return }
        let start = layer.value(forKey: "pressStart") as? CFTimeInterval ?? 0
        let delay = max(0, pressDuration - (CACurrentMediaTime() - start))
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = delay > 0 ? press.toValue : NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = 220
        spring.damping = 18
        spring.duration = spring.settlingDuration
        spring.beginTime = layer.convertTime(CACurrentMediaTime() + delay, from: nil)
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in
            guard let layer, layer.animation(forKey: "release") != nil else { return }
            layer.removeAnimation(forKey: "press")
            layer.removeAnimation(forKey: "release")
        }
        layer.add(spring, forKey: "release")
        CATransaction.commit()
    }

    // Drives `update` with eased progress 0...1 each frame; keep the returned ticker alive.
    static func tween(on view: NSView, duration: CFTimeInterval, curve: @escaping (Double) -> Double = slide,
                      update: @escaping (CGFloat) -> Void) -> FrameTicker? {
        guard !reduced else {
            update(1)
            return nil
        }
        let start = CACurrentMediaTime()
        update(0)
        return FrameTicker(view: view) { now in
            let t = min(1, (now - start) / duration)
            update(CGFloat(curve(t)))
            return t < 1
        }
    }

    static func shrinkOut(_ view: NSView, to scale: CGFloat = 0.9, duration: CFTimeInterval = 0.22) {
        guard !reduced, let layer = view.layer else { return }
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        anim.toValue = NSValue(caTransform3D: centeredScale(layer, scale))
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "shrinkOut")
    }

    static func crossfade(_ view: NSView, duration: CFTimeInterval = 0.18) {
        guard !reduced, let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        layer.add(transition, forKey: "crossfade")
    }

    // Only for standalone sublayers; AppKit owns the transform of a view's backing layer.
    static func rotate(_ layer: CALayer, to radians: CGFloat, animated: Bool) {
        let current = (layer.presentation() ?? layer).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(radians, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        guard animated, !reduced, current != radians else {
            layer.removeAnimation(forKey: "rotate")
            return
        }
        let spring = CASpringAnimation(keyPath: "transform.rotation.z")
        spring.fromValue = current
        spring.toValue = radians
        spring.mass = 1
        spring.stiffness = 300
        spring.damping = 24
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "rotate")
    }

    private static func centeredScale(_ layer: CALayer, _ s: CGFloat) -> CATransform3D {
        let cx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let cy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var t = CATransform3DMakeTranslation(cx, cy, 0)
        t = CATransform3DScale(t, s, s, 1)
        return CATransform3DTranslate(t, -cx, -cy, 0)
    }
}

extension NSImage {
    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        if let glyph = SpaceGlyph(rawValue: name) { return glyph.image(size: size) }
        if let first = name.first, !first.isASCII { return emoji(name, size: size) }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func tinted(_ color: NSColor) -> NSImage {
        let source = self
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }

    static func emoji(_ text: String, size: CGFloat) -> NSImage {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let textSize = string.size()
        let side = max(textSize.width, textSize.height).rounded(.up)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            string.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
            return true
        }
    }
}

extension URL {
    var displayHost: String {
        guard let host = host(percentEncoded: false) else { return absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

@MainActor
final class FrameTicker: NSObject {
    private let tick: (CFTimeInterval) -> Bool
    private var displayLink: AnyObject?
    private var timer: Timer?

    init(view: NSView, tick: @escaping (CFTimeInterval) -> Bool) {
        self.tick = tick
        super.init()
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func step() {
        if !tick(CACurrentMediaTime()) { stop() }
    }

    func stop() {
        if #available(macOS 14.0, *) { (displayLink as? CADisplayLink)?.invalidate() }
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }
}
