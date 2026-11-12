import AppKit

@MainActor
final class FindBarView: NSVisualEffectView, NSTextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    static let size = NSSize(width: 340, height: 40)

    private let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private lazy var previousButton = button("chevron.up", "Previous Match (⇧⌘G)", #selector(previousClicked))
    private lazy var nextButton = button("chevron.down", "Next Match (⌘G)", #selector(nextClicked))
    private lazy var closeButton = button("xmark", "Close (Esc)", #selector(closeClicked))

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        field.placeholderString = "Find in page"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .inter(13)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = self

        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        for view in [field, countLabel, previousButton, nextButton, closeButton] as [NSView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        let buttonSize: CGFloat = 24
        var x = bounds.width - 8 - buttonSize
        for button in [closeButton, nextButton, previousButton] {
            button.frame = NSRect(x: x, y: (h - buttonSize) / 2, width: buttonSize, height: buttonSize)
            x -= buttonSize + 2
        }
        let countWidth: CGFloat = 64
        countLabel.frame = NSRect(x: x - countWidth + buttonSize - 4, y: (h - 16) / 2, width: countWidth, height: 16)
        field.frame = NSRect(x: 12, y: (h - 18) / 2, width: countLabel.frame.minX - 18, height: 18)
    }

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func setMatches(_ matches: Int, active: Int) {
        if field.stringValue.isEmpty {
            countLabel.stringValue = ""
        } else if matches == 0 {
            countLabel.stringValue = "No results"
        } else {
            countLabel.stringValue = "\(max(active, 1)) of \(matches)"
        }
        countLabel.textColor = matches == 0 && !field.stringValue.isEmpty ? .systemRed : .secondaryLabelColor
    }

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.isEmpty { countLabel.stringValue = "" }
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func previousClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func closeClicked() { onClose?() }

    private func button(_ symbol: String, _ toolTip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = toolTip
        return button
    }
}
