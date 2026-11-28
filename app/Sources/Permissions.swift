import AppKit

extension PermissionRequest {
    private var systemBlocked: Bool { !blockedBySystem.isEmpty }

    var symbol: String {
        let kinds = systemBlocked ? blockedBySystem : kinds
        if kinds.contains([.camera, .microphone]) { return "video.fill" }
        if kinds.contains(.camera) { return "camera.fill" }
        if kinds.contains(.microphone) { return "mic.fill" }
        if kinds.contains(.location) { return "location.fill" }
        if kinds.contains(.notifications) { return "bell.fill" }
        return "hand.raised.fill"
    }

    var question: String {
        if systemBlocked {
            return "macOS has turned off \(Self.name(of: blockedBySystem)) for Stone. Turn it on in System Settings, then reload the page."
        }
        let host = site.hasPrefix("http://") ? String(site.dropFirst(7)) : site
        return "Allow \(host) to \(phrase)?"
    }

    var primaryTitle: String { systemBlocked ? "Open Settings" : "Allow" }

    func acceptPrimary() {
        if systemBlocked { openSystemSettings() } else { allow() }
    }

    private var phrase: String {
        if kinds.contains(.other) || kinds.isEmpty {
            let parts = descriptions.map { $0.prefix(1).lowercased() + $0.dropFirst() }
            return Self.list(parts.isEmpty ? ["use a feature of this device"] : parts)
        }
        var parts: [String] = []
        if kinds.contains([.camera, .microphone]) {
            parts.append("use your camera and microphone")
        } else if kinds.contains(.camera) {
            parts.append("access your camera")
        } else if kinds.contains(.microphone) {
            parts.append("access your microphone")
        }
        if kinds.contains(.location) { parts.append("know your location") }
        if kinds.contains(.notifications) { parts.append("send you notifications") }
        return Self.list(parts)
    }

    private static func name(of kinds: PermissionKinds) -> String {
        var names: [String] = []
        if kinds.contains(.camera) { names.append("the camera") }
        if kinds.contains(.microphone) { names.append("the microphone") }
        if kinds.contains(.location) { names.append("location") }
        if kinds.contains(.notifications) { names.append("notifications") }
        return list(names.isEmpty ? ["this"] : names)
    }

    private static func list(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
    }
}

// Arc-style prompt that hangs from the address pill's site controls button.
@MainActor
final class PermissionCard: OverlayPanel {
    static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    private static let arrowHeight: CGFloat = 8
    private static let arrowWidth: CGFloat = 18

    let request: PermissionRequest
    private let shape = CAShapeLayer()
    private let iconWell = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let notNow = PermissionCardButton(title: "Not Now", prominent: false)
    private let accept: PermissionCardButton
    private var arrowX: CGFloat?
    private var answered = false

    init(request: PermissionRequest) {
        self.request = request
        accept = PermissionCardButton(title: request.primaryTitle, prominent: true)
        super.init(frame: .zero)
        layer?.cornerRadius = 0
        layer?.borderWidth = 0
        layer?.insertSublayer(shape, at: 0)
        shape.lineWidth = 1

        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 20
        icon.image = NSImage(systemSymbolName: request.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        icon.contentTintColor = Palette.text
        iconWell.addSubview(icon)

        label.stringValue = request.question
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Palette.text
        label.maximumNumberOfLines = 4
        label.isSelectable = false

        notNow.action = { [weak self] in self?.answer { $0.notNow() } }
        accept.action = { [weak self] in self?.answer { $0.acceptPrimary() } }
        for view in [iconWell, label, notNow, accept] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var textX: CGFloat { Self.inset + 40 + 12 }

    private var contentHeight: CGFloat {
        let textWidth = Self.width - textX - Self.inset
        let text = ceil(label.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        return Self.arrowHeight + Self.inset + 2 + max(40, text) + 16 + 38 + Self.inset
    }

    // Hangs below `anchor` with the arrow pointing at it, or sits at `fallback`
    // when the anchor is not on screen.
    func present(in root: NSView, anchor: NSView?, fallback: NSPoint) {
        let height = contentHeight
        var frame: NSRect
        if let anchor {
            let rect = anchor.convert(anchor.bounds, to: root)
            let x = min(max(8, rect.midX - 48), root.bounds.width - Self.width - 8)
            frame = NSRect(x: x, y: rect.maxY + 4, width: Self.width, height: height)
            arrowX = min(max(Self.arrowWidth, rect.midX - x), Self.width - Self.arrowWidth)
        } else {
            frame = NSRect(x: fallback.x, y: fallback.y - Self.arrowHeight, width: Self.width, height: height)
            arrowX = nil
        }
        frame.origin.y = min(frame.origin.y, root.bounds.height - height - 8)
        attach(to: root, frame: frame, anchor: anchor ?? self, slideFrom: -6)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let top = Self.arrowHeight
        let textWidth = Self.width - textX - Self.inset
        let textHeight = ceil(label.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        iconWell.frame = NSRect(x: Self.inset, y: top + Self.inset + 2, width: 40, height: 40)
        icon.frame = iconWell.bounds
        label.frame = NSRect(x: textX, y: top + Self.inset + 2 + max(0, (40 - textHeight) / 2), width: textWidth, height: textHeight)
        let buttonsY = top + Self.inset + 2 + max(40, textHeight) + 16
        let buttonWidth = (Self.width - 2 * Self.inset - 10) / 2
        notNow.frame = NSRect(x: Self.inset, y: buttonsY, width: buttonWidth, height: 38)
        accept.frame = NSRect(x: Self.inset + buttonWidth + 10, y: buttonsY, width: buttonWidth, height: 38)
        shape.frame = bounds
        shape.path = outline()
        layer?.shadowPath = shape.path
    }

    private func outline() -> CGPath {
        let rect = NSRect(x: 0.5, y: Self.arrowHeight + 0.5, width: bounds.width - 1, height: bounds.height - Self.arrowHeight - 1)
        let radius: CGFloat = 16
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        if let arrowX {
            path.addLine(to: CGPoint(x: arrowX - Self.arrowWidth / 2, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: arrowX, y: 0.5), control: CGPoint(x: arrowX - 3, y: rect.minY - 1))
            path.addQuadCurve(to: CGPoint(x: arrowX + Self.arrowWidth / 2, y: rect.minY), control: CGPoint(x: arrowX + 3, y: rect.minY - 1))
        }
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }

    override func updateLayer() {
        layer?.backgroundColor = nil
        layer?.borderColor = nil
        shape.fillColor = fillColor.cgColor
        shape.strokeColor = Palette.divider.cgColor
        iconWell.layer?.backgroundColor = Palette.tabHover.cgColor
    }

    private func answer(_ decide: (PermissionRequest) -> Void) {
        answered = true
        decide(request)
        close()
    }

    // Closing without an answer, by clicking elsewhere or pressing Escape,
    // counts as Not Now.
    override func willClose() {
        if !answered, request.isPending { request.notNow() }
    }

    func withdraw() {
        answered = true
        close()
    }
}

@MainActor
final class PermissionCardButton: HoverView {
    var action: (() -> Void)?
    private let label: NSTextField
    private let prominent: Bool

    init(title: String, prominent: Bool) {
        label = .sidebarLabel(title, font: .systemFont(ofSize: 14, weight: .semibold), color: Palette.text)
        label.alignment = .center
        self.prominent = prominent
        super.init(frame: .zero)
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        addSubview(label)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 4, y: (bounds.height - 18) / 2, width: bounds.width - 8, height: 18)
    }

    override func updateLayer() {
        let base = prominent ? Palette.tabActive : Palette.surface
        layer?.backgroundColor = (isHovered ? base.blended(withFraction: 0.12, of: .white) ?? base : base).cgColor
        layer?.borderColor = Palette.hairline.cgColor
    }

    override func hoverChanged() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.97) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

// One permission card per window, for whichever of its tabs is asking.
@MainActor
final class PermissionPresenter {
    private let show: (PermissionCard) -> Void
    private weak var card: PermissionCard?
    var onChange: ((Bool) -> Void)?

    init(show: @escaping (PermissionCard) -> Void) {
        self.show = show
    }

    func present(_ request: PermissionRequest) {
        guard request.isPending else { return }
        card?.withdraw()
        let card = PermissionCard(request: request)
        card.onClose = { [weak self, weak card] in
            guard let self, self.card === card else { return }
            self.card = nil
            self.onChange?(false)
        }
        self.card = card
        show(card)
        onChange?(true)
    }

    func withdraw(_ request: PermissionRequest) {
        guard let card, card.request === request else { return }
        card.withdraw()
    }
}
