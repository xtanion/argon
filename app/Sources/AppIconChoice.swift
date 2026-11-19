import AppKit

enum AppIconStyle: String, CaseIterable {
    case blue, beijing, tokyo, perth, newYork

    var title: String {
        switch self {
        case .blue: "Argon"
        case .beijing: "Daybreak"
        case .tokyo: "Dusk"
        case .perth: "Sunset"
        case .newYork: "Tide"
        }
    }

    var gradient: [UInt32]? {
        switch self {
        case .blue: nil
        case .beijing: [0x1A78F0, 0x308FEC, 0x56A0CF, 0x9BB3A7, 0xDECD93, 0xFBE2A1]
        case .tokyo: [0x4D62D6, 0x6C7FDB, 0x8F8FCB, 0xB798A1, 0xDFAB7C, 0xF6C377]
        case .perth: [0xA9C3F0, 0xC7D0EA, 0xD8C2CA, 0xE6A189, 0xF4914E, 0xFCA03F]
        case .newYork: [0x122941, 0x1B3A57, 0x204D62, 0x3B6D6E, 0x699E88, 0x94C7A7]
        }
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
        NSApp.applicationIconImage = style == .blue
            ? nil
            : image(style, dark: Palette.isDark(NSApp.effectiveAppearance), size: 512)
    }

    // Level per cell of the top-left quadrant of the 12x12 pixel grid; the
    // other quadrants mirror it.
    private static let quadrant: [[Int]] = [
        [0, 0, 0, 0, 1, 1],
        [0, 0, 1, 1, 2, 3],
        [0, 1, 2, 4, 5, 6],
        [0, 1, 4, 6, 7, 8],
        [1, 2, 5, 7, 9, 10],
        [1, 3, 6, 8, 10, 11],
    ]
    private static let opacity: [CGFloat] = [0, 0.22, 0.35, 0.48, 0.6, 0.75, 0.9, 1, 1, 1, 1, 1]
    private static let blue: [UInt32] = [0, 0x1549F8, 0x1549F8, 0x1A4DF8, 0x1F50F9, 0x2A58F9, 0x305DFA,
                                         0x3D67FB, 0x456DFB, 0x4F74FC, 0x5A7DFD, 0x6E8BFE]
    private static let edges: [CGFloat] = [104, 172, 240, 308, 376, 444, 512, 580, 648, 716, 784, 852, 920]

    // Cells are premixed with the tile colour and overlap slightly: translucent
    // abutting squares let the background bleed through as hairline seams.
    private static func level(_ column: Int, _ row: Int) -> Int {
        quadrant[row < 6 ? row : 11 - row][column < 6 ? column : 11 - column]
    }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func sample(_ stops: [UInt32], _ t: CGFloat) -> NSColor {
        let scaled = min(1, max(0, t)) * CGFloat(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        return color(stops[index]).blended(withFraction: scaled - CGFloat(index), of: color(stops[index + 1])) ?? color(stops[index])
    }

    // Draws the full macOS icon: the rounded tile inside Apple's 1024 grid,
    // with the pixel blob filling it the way the bundled icon does.
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
            let background = dark ? NSColor(srgbRed: 0.004, green: 0, blue: 0.031, alpha: 1) : NSColor.white
            background.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let scale = tile.width / 1024
            func position(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }
            for row in 0..<12 {
                for column in 0..<12 {
                    let level = level(column, row)
                    guard level > 0 else { continue }
                    let base = style.gradient.map { sample($0, (CGFloat(row) + 0.5) / 12) } ?? color(blue[level])
                    (base.blended(withFraction: 1 - opacity[level], of: background) ?? base).setFill()
                    let x0 = position(edges[column]), x1 = position(edges[column + 1])
                    let y0 = position(edges[row]), y1 = position(edges[row + 1])
                    NSRect(x: tile.minX + x0, y: tile.minY + y0, width: x1 - x0 + unit, height: y1 - y0 + unit).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
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
        row.spacing = 12
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
        let stops = style.gradient ?? [0x6E8BFE, 0x8FA6FE, 0xBFD0FF]
        let dark = Palette.isDark(effectiveAppearance)
        let picks = [stops[0], stops[stops.count / 2], stops[stops.count - 1]]
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
            imageView.widthAnchor.constraint(equalToConstant: 76),
            imageView.heightAnchor.constraint(equalToConstant: 76),
            tick.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            tick.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 80),
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
