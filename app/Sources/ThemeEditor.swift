import AppKit

@MainActor
final class ThemeEditorController: NSViewController, NSTextFieldDelegate {
    static let palette: [UInt32] = [
        0xFFFFFF, 0xF5F5F4, 0xF2EFEA, 0xEDEDF2, 0xE8ECEF, 0xF3F0FF, 0xFFF1F2, 0xF0FDF4,
        0xFDE2E4, 0xFAD2E1, 0xFFF1E6, 0xE9EDC9, 0xE2ECE9, 0xBEE1E6, 0xCDDAFD, 0xDFE7FD,
        0xA1A1A1, 0x8E9AAF, 0x9AB0A6, 0x6B9080, 0x7FA7C9, 0xB392AC, 0xC9A27E, 0xD4A373,
        0x3D405B, 0x283044, 0x2F3E46, 0x2D3A3A, 0x3B2F4A, 0x3A2E39, 0x4A3F35, 0x33302E,
        0x1E2128, 0x1B1D2B, 0x221F1D, 0x232326, 0x1C1C1E, 0x141416, 0x0A0A0B, 0x000000,
    ]
    private static let columns = 8
    private static let swatchSize: CGFloat = 26
    private static let spacing: CGFloat = 6
    private static let inset: CGFloat = 16

    var onChange: ((NSColor?) -> Void)?
    var onOpacityChange: ((Double) -> Void)?

    private var color: NSColor?
    private let opacity: Double
    private var swatches: [SwatchView] = []
    private let titleLabel = NSTextField.sidebarLabel("Theme", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    private let hexField = NSTextField()
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let opacityLabel = NSTextField.sidebarLabel("Opacity", font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor)
    private let opacityValue = NSTextField.sidebarLabel("", font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
    private let opacitySlider = WaveSlider()

    init(color: NSColor?, opacity: Double = 1) {
        self.color = color
        self.opacity = opacity
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let size = Self.swatchSize, gap = Self.spacing, inset = Self.inset
        let gridWidth = CGFloat(Self.columns) * size + CGFloat(Self.columns - 1) * gap
        let rows = Self.palette.count / Self.columns
        let gridTop: CGFloat = 42
        let gridBottom = gridTop + CGFloat(rows) * size + CGFloat(rows - 1) * gap
        let footerY = gridBottom + gap + 6
        let opacityY = footerY + 24 + 16
        let sliderY = opacityY + 18
        let sliderHeight: CGFloat = 40
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: gridWidth + 2 * inset, height: sliderY + sliderHeight + inset - 6))

        titleLabel.frame = NSRect(x: inset, y: 14, width: gridWidth, height: 18)
        view.addSubview(titleLabel)

        for (index, value) in Self.palette.enumerated() {
            let swatchColor = Self.color(value)
            let swatch = SwatchView(color: swatchColor)
            swatch.frame = NSRect(x: inset + CGFloat(index % Self.columns) * (size + gap),
                                  y: gridTop + CGFloat(index / Self.columns) * (size + gap),
                                  width: size, height: size)
            swatch.toolTip = swatchColor.hexString
            swatch.onClick = { [weak self] in self?.apply(swatchColor) }
            view.addSubview(swatch)
            swatches.append(swatch)
        }

        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular
        resetButton.target = self
        resetButton.action = #selector(reset)
        resetButton.sizeToFit()
        let resetWidth = resetButton.frame.width
        resetButton.frame = NSRect(x: inset + gridWidth - resetWidth, y: footerY, width: resetWidth, height: 24)

        hexField.placeholderString = "#RRGGBB"
        hexField.bezelStyle = .roundedBezel
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.target = self
        hexField.action = #selector(commitHex)
        hexField.delegate = self
        hexField.frame = NSRect(x: inset, y: footerY + 1, width: gridWidth - resetWidth - 8, height: 22)

        view.addSubview(hexField)
        view.addSubview(resetButton)

        opacityLabel.frame = NSRect(x: inset, y: opacityY, width: gridWidth / 2, height: 16)
        opacityValue.alignment = .right
        opacityValue.frame = NSRect(x: inset + gridWidth / 2, y: opacityY, width: gridWidth / 2, height: 16)
        opacitySlider.frame = NSRect(x: inset, y: sliderY, width: gridWidth, height: sliderHeight)
        opacitySlider.minValue = Palette.minimumOpacity
        opacitySlider.maxValue = 1
        opacitySlider.label = "Opacity"
        opacitySlider.setValue(opacity)
        opacitySlider.onChange = { [weak self] value in
            self?.showOpacity(value)
            self?.onOpacityChange?(value)
        }
        showOpacity(opacity)
        view.addSubview(opacityLabel)
        view.addSubview(opacityValue)
        view.addSubview(opacitySlider)
        self.view = view
        refresh()
    }

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private func apply(_ newColor: NSColor?) {
        color = newColor
        refresh()
        onChange?(newColor)
    }

    @objc private func commitHex() {
        let text = hexField.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return }
        guard let parsed = NSColor(hex: text) else {
            NSSound.beep()
            return
        }
        apply(parsed)
    }

    @objc private func reset() { apply(nil) }

    private func showOpacity(_ value: Double) {
        opacityValue.stringValue = "\(Int((value * 100).rounded()))%"
    }

    private func refresh() {
        let hex = color?.hexString
        hexField.stringValue = hex ?? ""
        for (index, swatch) in swatches.enumerated() {
            swatch.isSelected = hex == Self.color(Self.palette[index]).hexString
        }
        resetButton.isEnabled = color != nil
    }
}

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SwatchView: HoverView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSColor.labelColor
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 4.5, dy: 4.5))
        color.setFill()
        disc.fill()
        disc.lineWidth = 1
        ring.withAlphaComponent(0x33 / 255).setStroke()
        disc.stroke()
        if isSelected || isHovered {
            let halo = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
            halo.lineWidth = 2
            (isSelected ? ring : ring.withAlphaComponent(0x66 / 255)).setStroke()
            halo.stroke()
        }
    }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.88) }
}

@MainActor
final class IconPickerController: NSViewController {
    private static let columns = 8
    private static let cell: CGFloat = 31
    private static let inset: CGFloat = 11
    private static let header: CGFloat = 48

    var onPick: ((String) -> Void)?

    private var selected: String
    private var cells: [IconPickerCell] = []
    private let segmented = NSSegmentedControl(labels: ["Emoji", "Icon"], trackingMode: .selectOne, target: nil, action: nil)
    private let trash = IconButton(symbol: "trash", size: 15, toolTip: "Remove Icon")

    init(selected: String) {
        self.selected = selected
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var items: [String] { segmented.selectedSegment == 0 ? SpaceSymbols.emoji : SpaceSymbols.all }

    override func loadView() {
        let rows = (SpaceSymbols.all.count + Self.columns - 1) / Self.columns
        let width = Self.inset * 2 + CGFloat(Self.columns) * Self.cell
        let height = Self.header + CGFloat(rows) * Self.cell + Self.inset
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        segmented.font = .systemFont(ofSize: 13)
        segmented.segmentStyle = .rounded
        segmented.selectedSegmentBezelColor = .controlAccentColor
        segmented.setWidth(56, forSegment: 0)
        segmented.setWidth(56, forSegment: 1)
        segmented.selectedSegment = isEmoji(selected) ? 0 : 1
        segmented.target = self
        segmented.action = #selector(modeChanged)
        segmented.sizeToFit()
        let segmentWidth = segmented.frame.width
        segmented.frame.origin = NSPoint(x: (width - segmentWidth) / 2 - 15, y: 13)
        view.addSubview(segmented)

        trash.frame = NSRect(x: segmented.frame.maxX + 12, y: segmented.frame.midY - 13, width: 26, height: 26)
        trash.tint = Palette.text
        trash.action = { [weak self] in self?.pick("") }
        view.addSubview(trash)

        for index in 0..<(rows * Self.columns) {
            let cell = IconPickerCell()
            cell.frame = NSRect(
                x: Self.inset + CGFloat(index % Self.columns) * Self.cell,
                y: Self.header + CGFloat(index / Self.columns) * Self.cell,
                width: Self.cell, height: Self.cell
            )
            view.addSubview(cell)
            cells.append(cell)
        }
        self.view = view
        reload()
    }

    @objc private func modeChanged() { reload() }

    private func isEmoji(_ symbol: String) -> Bool {
        guard let first = symbol.first else { return false }
        return !first.isASCII
    }

    private func reload() {
        let items = items
        let emoji = segmented.selectedSegment == 0
        for (index, cell) in cells.enumerated() {
            guard items.indices.contains(index) else {
                cell.isHidden = true
                continue
            }
            let item = items[index]
            cell.isHidden = false
            cell.setImage(.symbol(item, size: emoji ? 19 : 14))
            cell.isSelected = item == selected
            cell.onClick = { [weak self] in self?.pick(item) }
        }
    }

    private func pick(_ symbol: String) {
        selected = symbol
        reload()
        onPick?(symbol)
    }
}

@MainActor
final class IconPickerCell: HoverView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private let imageView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = Palette.text
        addSubview(imageView)
    }

    func setImage(_ image: NSImage?) { imageView.image = image }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func updateLayer() {
        layer?.cornerRadius = 5
        layer?.backgroundColor = isSelected ? Palette.white(0x5A).withAlphaComponent(0.55).cgColor
            : isHovered ? Palette.white(0x5A).withAlphaComponent(0.3).cgColor : nil
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.88) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}

enum SpaceGlyph: String {
    case planet = "argon.planet"
    case pizza = "argon.pizza"
    case skull = "argon.skull"

    func image(size: CGFloat) -> NSImage {
        let side = (size * 1.2).rounded()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            let s = rect.width
            NSColor.black.setFill()
            NSColor.black.setStroke()
            switch self {
            case .planet: Self.drawPlanet(s, context)
            case .pizza: Self.drawPizza(s, context)
            case .skull: Self.drawSkull(s, context)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func clear(_ context: NSGraphicsContext, _ body: () -> Void) {
        context.saveGraphicsState()
        context.compositingOperation = .clear
        body()
        context.restoreGraphicsState()
    }

    private static func drawPlanet(_ s: CGFloat, _ context: NSGraphicsContext) {
        let transform = NSAffineTransform()
        transform.translateX(by: s / 2, yBy: s / 2)
        transform.rotate(byDegrees: -22)
        transform.concat()
        let r = s * 0.29
        NSBezierPath(ovalIn: NSRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).fill()
        let ring = NSBezierPath(ovalIn: NSRect(x: -s * 0.47, y: -s * 0.15, width: s * 0.94, height: s * 0.3))
        clear(context) {
            NSBezierPath(rect: NSRect(x: -s, y: 0, width: 2 * s, height: s)).addClip()
            ring.lineWidth = s * 0.2
            ring.stroke()
        }
        ring.lineWidth = s * 0.075
        ring.stroke()
    }

    private static func drawPizza(_ s: CGFloat, _ context: NSGraphicsContext) {
        NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.17), xRadius: s * 0.08, yRadius: s * 0.08).fill()
        let slice = NSBezierPath()
        slice.move(to: NSPoint(x: s * 0.19, y: s * 0.36))
        slice.line(to: NSPoint(x: s * 0.81, y: s * 0.36))
        slice.line(to: NSPoint(x: s * 0.5, y: s * 0.88))
        slice.close()
        slice.lineJoinStyle = .round
        slice.lineWidth = s * 0.06
        slice.fill()
        slice.stroke()
        clear(context) {
            for (x, y, r) in [(0.4, 0.46, 0.065), (0.6, 0.5, 0.055), (0.5, 0.67, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
                NSBezierPath(ovalIn: NSRect(x: s * (x - r), y: s * (y - r), width: s * 2 * r, height: s * 2 * r)).fill()
            }
        }
    }

    private static func drawSkull(_ s: CGFloat, _ context: NSGraphicsContext) {
        NSBezierPath(ovalIn: NSRect(x: s * 0.13, y: s * 0.06, width: s * 0.74, height: s * 0.64)).fill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.29, y: s * 0.5, width: s * 0.42, height: s * 0.42), xRadius: s * 0.08, yRadius: s * 0.08).fill()
        clear(context) {
            NSBezierPath(ovalIn: NSRect(x: s * 0.26, y: s * 0.34, width: s * 0.19, height: s * 0.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: s * 0.55, y: s * 0.34, width: s * 0.19, height: s * 0.2)).fill()
            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: s * 0.5, y: s * 0.57))
            nose.line(to: NSPoint(x: s * 0.45, y: s * 0.66))
            nose.line(to: NSPoint(x: s * 0.55, y: s * 0.66))
            nose.close()
            nose.fill()
            for x in [0.41, 0.555] as [CGFloat] {
                NSBezierPath(rect: NSRect(x: s * x, y: s * 0.76, width: s * 0.035, height: s * 0.16)).fill()
            }
        }
    }
}
