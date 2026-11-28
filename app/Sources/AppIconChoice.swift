import AppKit

enum AppIconStyle: String, CaseIterable {
    case argon = "blue", ocean, meadow, dusk, sunset, tide

    var title: String {
        switch self {
        case .argon: "Argon"
        case .ocean: "Ocean"
        case .meadow: "Meadow"
        case .dusk: "Dusk"
        case .sunset: "Sunset"
        case .tide: "Tide"
        }
    }

    // Logo stroke on the light tile, then on the dark tile.
    var stroke: (light: UInt32, dark: UInt32) {
        switch self {
        case .argon: (0x2A2723, 0xEDE8E0)
        case .ocean: (0x0A84FF, 0x409CFF)
        case .meadow: (0x28B44C, 0x30D158)
        case .dusk: (0x4D62D6, 0x8F9BEB)
        case .sunset: (0xF4782E, 0xFCA03F)
        case .tide: (0x204D62, 0x94C7A7)
        }
    }

    var wash: [UInt32] {
        let (light, dark) = stroke
        return [dark, light, dark]
    }

    func mark(dark: Bool) -> NSImage? {
        NSImage(data: Data(AppIcon.logo(stroke: dark ? stroke.dark : stroke.light).utf8))
    }
}

@MainActor
enum AppIcon {
    private static var appearanceObservation: NSKeyValueObservation?

    static func start() {
        apply()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in apply() }
        }
    }

    static func apply() {
        let style = Preferences.appIcon
        NSApp.applicationIconImage = style == .argon
            ? nil
            : image(style, dark: Palette.isDark(NSApp.effectiveAppearance), size: 512)
    }

    // Same art as Resources/AppIcon.icon/Assets/logo-*.svg (docs/logo/argon-logo.svg on the 1024 canvas).
    nonisolated static func logo(stroke: UInt32) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        <g transform="translate(110.88 105.82) scale(33.7079)" fill="none" stroke="#\(String(format: "%06X", stroke))" stroke-linecap="round">
        <path stroke-width="1.8" d="M3.2 13.6C3 8.6 6.6 4.4 12.1 4.1c5.2-.3 8.8 3 8.7 7.6-.1 5-4.2 8.4-9.4 8.3-4.5-.1-8-2.6-8.2-6.4z"/>
        <path stroke-width="1.3" d="M7.4 13.1c-.1-2.6 2-4.7 5-4.8 2.7-.1 4.6 1.6 4.5 3.9-.1 2.5-2.3 4.1-5 4-2.5 0-4.4-1.2-4.5-3.1z"/>
        <path stroke-width="1.3" d="M11 12.3c0-.8.7-1.4 1.6-1.4.8 0 1.4.5 1.3 1.2 0 .7-.7 1.2-1.5 1.2-.8 0-1.4-.4-1.4-1z"/>
        </g>
        </svg>
        """
    }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // The full macOS icon: the rounded tile inside Apple's 1024 grid on the system's default
    // icon background (what AppIcon.icon gets with no fill of its own), with the mark on it.
    static func image(_ style: AppIconStyle, dark: Bool, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let unit = rect.width / 1024
            let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
            let radius = 185.4 * unit
            let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 10 * unit
            shadow.shadowOffset = NSSize(width: 0, height: -6 * unit)
            shadow.set()
            NSColor.white.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            let fill = dark ? (top: color(0x3C3C41), bottom: color(0x1A1A1D)) : (top: color(0xFFFFFF), bottom: color(0xE6E6EB))
            NSGradient(starting: fill.top, ending: fill.bottom)?.draw(in: shape, angle: 90)

            style.mark(dark: dark)?.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
    }
}

// Header card on the General pane: the icon choices on a wash of the chosen
// icon's own colours.
@MainActor
final class AppIconBanner: NSView {
    private var tiles: [AppIconTile] = []
    private let wash = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        wash.startPoint = CGPoint(x: 0, y: 1)
        wash.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(wash)

        let title = NSTextField(labelWithString: "App Icon")
        title.font = .inter(13, weight: .semibold)
        title.textColor = .labelColor
        let subtitle = NSTextField(labelWithString: "Shown in the Dock while Argon is running. Follows light and dark mode.")
        subtitle.font = SettingsStyle.subtitle
        subtitle.textColor = .secondaryLabelColor

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .equalSpacing
        for style in AppIconStyle.allCases {
            let tile = AppIconTile(style: style) { [weak self] in self?.choose(style) }
            tiles.append(tile)
            row.addArrangedSubview(tile)
        }
        for view in [title, subtitle, row] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            row.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = bounds
        CATransaction.commit()
    }

    private func choose(_ style: AppIconStyle) {
        Preferences.appIcon = style
        AppIcon.apply()
        sync()
    }

    private func sync() {
        let style = Preferences.appIcon
        for tile in tiles { tile.isSelected = tile.style == style }
        let dark = Palette.isDark(effectiveAppearance)
        let picks = style.wash
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        wash.colors = picks.map { AppIcon.color($0).withAlphaComponent(dark ? 0.32 : 0.38).cgColor }
        CATransaction.commit()
        var border: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { border = SettingsStyle.cardBorder.cgColor }
        layer?.borderColor = border
        layer?.borderWidth = 1 / max(window?.backingScaleFactor ?? 2, 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        tiles.forEach { $0.refresh() }
        sync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sync()
    }
}

@MainActor
private final class AppIconTile: NSView {
    let style: AppIconStyle
    var isSelected = false { didSet { update() } }
    private let onClick: () -> Void
    private let imageView = NSImageView()
    private let tick = NSImageView()
    private let label: NSTextField

    init(style: AppIconStyle, onClick: @escaping () -> Void) {
        self.style = style
        self.onClick = onClick
        label = NSTextField(labelWithString: style.title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = style.title
        imageView.imageScaling = .scaleProportionallyUpOrDown
        tick.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Selected")?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)
                .applying(.init(paletteColors: [.white, .controlAccentColor])))
        tick.imageScaling = .scaleNone
        label.font = SettingsStyle.subtitle
        label.alignment = .center
        for view in [imageView, label, tick] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 68),
            imageView.heightAnchor.constraint(equalToConstant: 68),
            tick.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            tick.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 72),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        imageView.image = AppIcon.image(style, dark: Palette.isDark(effectiveAppearance), size: 152)
        update()
    }

    private func update() {
        tick.isHidden = !isSelected
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.font = .inter(11.5, weight: isSelected ? .medium : .regular)
    }

    override func mouseDown(with event: NSEvent) { onClick() }
}
