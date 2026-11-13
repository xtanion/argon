import AppKit

@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate, BrowserTabObserver {
    private static var open: [LittleWindowController] = []
    private static let defaultSize = NSSize(width: 920, height: 660)
    private static let expandDuration: TimeInterval = 0.48
    private static let expandCurve = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)

    static func open(_ url: URL, space: Space, profile: Profile, browser: BrowserWindowController) {
        let page = BrowserTab(url: url)
        page.materialize(in: profile).isVisible = true
        present(LittleWindowController(page: page, space: space, browser: browser))
    }

    static func open(_ tab: Tab, space: Space, browser: BrowserWindowController) {
        tab.isVisible = true
        present(LittleWindowController(page: BrowserTab(tab: tab), space: space, browser: browser))
    }

    private static func present(_ controller: LittleWindowController) {
        open.append(controller)
        controller.present()
    }

    private let tab: BrowserTab
    private let space: Space
    private weak var browser: BrowserWindowController?
    private let root = LittleRootView()
    private var adopted = false
    private var tracksFrame = false
    private var picker: LittleSpacePicker?
    private var pickerMonitor: Any?
    private lazy var passwordOffers = PasswordOfferPresenter { [weak self] toast in self?.root.showToast(toast) }

    private init(page: BrowserTab, space: Space, browser: BrowserWindowController) {
        tab = page
        self.space = space
        self.browser = browser
        let window = BrowserWindow()
        window.minSize = NSSize(width: 420, height: 300)
        super.init(window: window)
        window.delegate = self
        window.contentView = root
        tab.observer = self
        if let view = tab.tab?.view { root.card.show(view) }
        root.setFrameColor(space.frameColor)
        window.appearance = NSAppearance(named: space.frameColor.isDarkFrame ? .darkAqua : .aqua)
        root.profileLabel.stringValue = space.profileIdentifier
        root.openButton.spaceName = space.name
        root.openButton.accent = Palette.accent(hue: space.hue, custom: space.customColor, on: space.frameColor)
        root.openButton.action = { [weak self] in self?.openInBrowser(space: nil) }
        root.spacesButton.action = { [weak self] in self?.toggleSpacePicker() }
        root.copyButton.action = { [weak self] in self?.copyURL(nil) }
        root.backButton.action = { [weak self] in self?.tab.tab?.goBack() }
        refreshHeader()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func present() {
        guard let window else { return }
        let target = initialFrame()
        let animated = !Motion.reduced
        window.setFrame(animated ? target.insetBy(dx: target.width * 0.06, dy: target.height * 0.06) : target, display: false)
        window.alphaValue = animated ? 0 : 1
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        tab.tab?.focus()
        guard animated else {
            tracksFrame = true
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.expandDuration
            context.timingFunction = Self.expandCurve
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.tracksFrame = true }
        })
    }

    // Little Argon comes back at the size and place it was last left, like any Mac window.
    private func initialFrame() -> NSRect {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let cascade = CGFloat(Self.open.count - 1) * 26
        if let saved = LittleArgon.lastFrame,
           let screen = NSScreen.screens.max(by: { Self.overlap(saved, $0.visibleFrame) < Self.overlap(saved, $1.visibleFrame) }),
           Self.overlap(saved, screen.visibleFrame) > 0.8 * saved.width * saved.height {
            return Self.fit(saved.offsetBy(dx: cascade, dy: -cascade), in: screen.visibleFrame)
        }
        let visible = mouseScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = LittleArgon.lastFrame?.size ?? Self.defaultSize
        let frame = NSRect(x: visible.midX - size.width / 2 + cascade, y: visible.midY - size.height / 2 - cascade,
                           width: size.width, height: size.height)
        return Self.fit(frame, in: visible)
    }

    private static func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    private static func fit(_ frame: NSRect, in visible: NSRect) -> NSRect {
        var frame = frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    private func rememberFrame() {
        guard tracksFrame, !adopted, let window, !window.styleMask.contains(.fullScreen) else { return }
        LittleArgon.lastFrame = window.frame
    }

    func windowDidResize(_ notification: Notification) { rememberFrame() }
    func windowDidMove(_ notification: Notification) { rememberFrame() }

    private func refreshHeader() {
        let host = tab.url.flatMap(LinkRouter.displayHost(of:)) ?? ""
        root.hostLabel.stringValue = host
        root.backButton.isHidden = !(tab.tab?.canGoBack ?? false)
        window?.title = tab.title.isEmpty ? host : tab.title
        root.needsLayout = true
    }

    // MARK: Moving to a Space

    private func toggleSpacePicker() {
        if picker != nil {
            dismissSpacePicker()
        } else {
            showSpacePicker()
        }
    }

    private func showSpacePicker() {
        guard picker == nil, let browser else { return }
        let picker = LittleSpacePicker(spaces: browser.allSpaces, frameColor: space.frameColor)
        picker.onChoose = { [weak self] space in
            self?.dismissSpacePicker()
            self?.move(to: space)
        }
        picker.onCancel = { [weak self] in self?.dismissSpacePicker() }
        self.picker = picker
        root.showPicker(picker)
        root.spacesButton.isActive = true
        pickerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let picker = self.picker else { return event }
            if event.window !== self.window {
                self.dismissSpacePicker()
                return event
            }
            let point = picker.convert(event.locationInWindow, from: nil)
            let onToggle = self.root.spacesButton.bounds.contains(self.root.spacesButton.convert(event.locationInWindow, from: nil))
            if !picker.bounds.contains(point), !onToggle { self.dismissSpacePicker() }
            return event
        }
    }

    private func dismissSpacePicker() {
        if let pickerMonitor { NSEvent.removeMonitor(pickerMonitor) }
        pickerMonitor = nil
        guard let picker else { return }
        self.picker = nil
        root.spacesButton.isActive = false
        picker.dismiss()
        tab.tab?.focus()
    }

    private func move(to target: Space) {
        guard let browser, browser.liveSpace(target) === target else { return }
        if target.profileIdentifier == space.profileIdentifier {
            openInBrowser(space: target)
            return
        }
        guard !LittleArgon.skipProfileWarning, let window else {
            reopen(in: target)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Move tab to \(target.name)?"
        alert.informativeText = "\(target.name) is using a different profile, so you might get logged out or lose your progress in this tab.\n\nThis can't be undone."
        alert.addButton(withTitle: "Move It")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                if alert.suppressionButton?.state == .on { LittleArgon.skipProfileWarning = true }
                self?.reopen(in: target)
            }
        }
    }

    // Pages can't cross profiles, so the address opens fresh in the other profile.
    private func reopen(in target: Space) {
        guard let browser, !adopted, let url = tab.url else { return }
        adopted = true
        browser.openTab(url, in: target)
        browser.bringToFront()
        tab.observer = nil
        tab.close()
        close()
    }

    private func openInBrowser(space target: Space?) {
        guard let browser, !adopted else { return }
        guard let destination = browser.liveSpace(target ?? space) else {
            NSSound.beep()
            return
        }
        rememberFrame()
        adopted = true
        dismissSpacePicker()
        let handOff: @MainActor () -> Void = { [weak self, weak browser] in
            guard let self, let browser else { return }
            let offer = self.passwordOffers.takePending()
            self.tab.observer = nil
            self.root.card.show(nil)
            browser.adopt(self.tab, into: destination)
            if let offer { browser.passwordOffers.present(offer) }
            if let url = self.tab.url, target != nil { browser.offerRule(for: url, space: destination) }
            self.close()
        }
        guard !Motion.reduced, let window, let landing = browser.pageFrameOnScreen else {
            handOff()
            return
        }
        browser.window?.orderFront(nil)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.expandDuration
            context.timingFunction = Self.expandCurve
            window.animator().setFrame(landing, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { handOff() }
        })
    }

    func windowWillClose(_ notification: Notification) {
        rememberFrame()
        if let pickerMonitor { NSEvent.removeMonitor(pickerMonitor) }
        pickerMonitor = nil
        if !adopted {
            tab.observer = nil
            tab.close()
        }
        Self.open.removeAll { $0 === self }
    }

    // MARK: Menu commands

    @objc func openFile(_ sender: Any?) { openInBrowser(space: nil) }
    @objc func moveToSpace(_ sender: Any?) { showSpacePicker() }
    @objc func newLittleWindow(_ sender: Any?) {
        guard let browser else { return }
        LittleLauncher.toggle(browser: browser)
    }

    @objc func closeTab(_ sender: Any?) { window?.performClose(sender) }
    @objc func goBack(_ sender: Any?) { tab.tab?.goBack() }
    @objc func goForward(_ sender: Any?) { tab.tab?.goForward() }
    @objc func reloadPage(_ sender: Any?) { tab.tab?.reload() }
    @objc func hardReload(_ sender: Any?) { tab.tab?.reloadBypassingCache() }
    @objc func stopLoading(_ sender: Any?) { tab.tab?.stop() }
    @objc func zoomIn(_ sender: Any?) { tab.tab?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { tab.tab?.zoomOut() }
    @objc func actualSize(_ sender: Any?) { tab.tab?.resetZoom() }
    @objc func printPage(_ sender: Any?) { tab.tab?.print() }
    @objc func savePage(_ sender: Any?) { tab.tab?.savePage() }
    @objc func toggleDevTools(_ sender: Any?) { tab.tab?.toggleDevTools() }
    @objc func showConsole(_ sender: Any?) { tab.tab?.showDevToolsConsole() }
    @objc func inspectElement(_ sender: Any?) { tab.tab?.inspectElement() }

    @objc func copyURL(_ sender: Any?) {
        guard let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        root.showToast(ToastView(message: "Copied Link", icon: "link", duration: 2))
    }

    @objc func newTab(_ sender: Any?) { forward { $0.newTab(sender) } }
    @objc func openLocation(_ sender: Any?) { forward { $0.openLocation(sender) } }
    @objc func newSpace(_ sender: Any?) { forward { $0.newSpace(sender) } }
    @objc func showHistory(_ sender: Any?) { forward { $0.showHistory(sender) } }
    @objc func toggleDownloads(_ sender: Any?) { forward { $0.toggleDownloads(sender) } }
    @objc func reopenClosedTab(_ sender: Any?) { forward { $0.reopenClosedTab(sender) } }

    private func forward(_ action: (BrowserWindowController) -> Void) {
        guard let browser else { return }
        browser.bringToFront()
        action(browser)
    }

    // MARK: BrowserTabObserver

    func browserTabDidChange(_ tab: BrowserTab) { refreshHeader() }

    func browserTab(_ tab: BrowserTab, didOpen newTab: Tab, disposition: TabOpenDisposition) {
        guard let browser else {
            newTab.close()
            return
        }
        browser.adoptOpened(newTab, in: space, disposition: disposition)
    }

    func browserTabDidRequestClose(_ tab: BrowserTab) { close() }

    func browserTab(_ tab: BrowserTab, didRequestFullscreen fullscreen: Bool) {
        guard let window, window.styleMask.contains(.fullScreen) != fullscreen else { return }
        window.toggleFullScreen(nil)
    }

    func browserTab(_ tab: BrowserTab, didUpdateFindMatches matches: Int, activeMatch: Int) {}
    func browserTabDidChangeMedia(_ tab: BrowserTab) {}

    func browserTab(_ tab: BrowserTab, didOfferPassword offer: PasswordOffer) { passwordOffers.present(offer) }

    func browserTab(_ tab: BrowserTab, didWithdrawPasswordOffer offer: PasswordOffer) { passwordOffers.withdraw(offer) }
}

@MainActor
final class LittleRootView: NSView {
    let card = ContentCardView()
    let backButton = IconButton(symbol: "chevron.left", size: 13, weight: .medium, toolTip: "Back")
    let address = LittleAddressView()
    let profileLabel = NSTextField.sidebarLabel("", font: .inter(11, weight: .semibold), color: Palette.subtle)
    let hostLabel = NSTextField.sidebarLabel("", font: .inter(12, weight: .medium), color: Palette.pillText)
    let copyButton = IconButton(symbol: "link", size: 12, toolTip: "Copy Link")
    let openButton = LittleOpenButton()
    let spacesButton = LittleChevronButton()
    private let profilePill = NSView()
    private let profileIcon = NSImageView()
    private var frameColor: NSColor = Palette.ink
    private var toast: ToastView?
    private weak var picker: LittleSpacePicker?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.isFullBleed = true
        hostLabel.alignment = .center
        hostLabel.lineBreakMode = .byTruncatingMiddle
        profileLabel.lineBreakMode = .byTruncatingTail
        profilePill.wantsLayer = true
        profilePill.layer?.cornerRadius = 6
        profilePill.layer?.cornerCurve = .continuous
        profileIcon.image = .symbol("face.smiling", size: 11, weight: .medium)
        profileIcon.contentTintColor = Palette.subtle
        profileIcon.imageScaling = .scaleNone
        profilePill.addSubview(profileIcon)
        profilePill.addSubview(profileLabel)
        backButton.isHidden = true
        for view in [profilePill, hostLabel, copyButton] as [NSView] { address.addSubview(view) }
        for view in [card, backButton, address, openButton, spacesButton] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setFrameColor(_ color: NSColor) {
        frameColor = color
        layer?.backgroundColor = color.cgColor
        toast?.fillColor = toastFill
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            profilePill.layer?.backgroundColor = Palette.tabHover.cgColor
        }
    }

    private var toastFill: NSColor { Palette.opaque(Palette.surface, on: frameColor, appearance: effectiveAppearance) }

    override func layout() {
        super.layout()
        let header = Metrics.titlebarHeight
        let w = bounds.width
        let inset: CGFloat = 8
        let lightsMaxX = (window as? BrowserWindow)?.trafficLightsMaxX ?? 67
        let center = header / 2
        let height: CGFloat = 30
        let top = center - height / 2

        spacesButton.frame = NSRect(x: w - inset - 26, y: top, width: 26, height: height)
        let openWidth = openButton.fittingWidth
        openButton.frame = NSRect(x: spacesButton.frame.minX - 4 - openWidth, y: top, width: openWidth, height: height)

        var x = lightsMaxX + 14
        if !backButton.isHidden {
            backButton.frame = NSRect(x: x, y: top, width: 28, height: height)
            x = backButton.frame.maxX + 4
        }
        address.frame = NSRect(x: x, y: top, width: max(0, openButton.frame.minX - 6 - x), height: height)

        let aw = address.bounds.width
        let profileWidth = min(ceil(profileLabel.intrinsicContentSize.width) + 32, aw * 0.3)
        profilePill.frame = NSRect(x: 5, y: 5, width: profileWidth, height: height - 10)
        profileIcon.frame = NSRect(x: 6, y: (profilePill.bounds.height - 14) / 2, width: 14, height: 14)
        profileLabel.frame = NSRect(x: 22, y: (profilePill.bounds.height - 15) / 2, width: profileWidth - 27, height: 15)
        copyButton.frame = NSRect(x: aw - 4 - 24, y: (height - 24) / 2, width: 24, height: 24)
        let side = max(profilePill.frame.maxX, aw - copyButton.frame.minX) + 8
        hostLabel.frame = NSRect(x: side, y: (height - 16) / 2, width: max(0, aw - 2 * side), height: 16)

        card.frame = NSRect(x: 0, y: header, width: w, height: max(0, bounds.height - header))
        if let picker { picker.place(below: spacesButton.frame, in: bounds) }
        if let toast { toast.setFrameOrigin(toastOrigin(for: toast)) }
    }

    func showPicker(_ picker: LittleSpacePicker) {
        self.picker = picker
        addSubview(picker)
        picker.place(below: spacesButton.frame, in: bounds)
        picker.present()
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

    private func toastOrigin(for toast: ToastView) -> NSPoint {
        NSPoint(x: card.frame.maxX - 14 - toast.frame.width, y: card.frame.minY + 14)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

@MainActor
final class LittleAddressView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = Palette.surface.cgColor }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

@MainActor
final class LittleOpenButton: HoverView {
    var action: (() -> Void)?
    var spaceName = "" { didSet { updateText() } }
    var accent = Palette.accent { didSet { updateText() } }
    private let label = NSTextField.sidebarLabel("")
    private let keycap = NSTextField.sidebarLabel("\u{2318}O", font: .inter(10, weight: .semibold), color: Palette.subtle)
    private let keycapBox = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        keycapBox.wantsLayer = true
        keycapBox.layer?.cornerRadius = 4
        keycapBox.layer?.cornerCurve = .continuous
        keycap.alignment = .center
        keycapBox.addSubview(keycap)
        addSubview(label)
        addSubview(keycapBox)
        toolTip = "Move this page into the Space"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateText() {
        let text = NSMutableAttributedString(string: "Open in ", attributes: [.font: NSFont.inter(12, weight: .medium), .foregroundColor: Palette.subtle])
        text.append(NSAttributedString(string: spaceName, attributes: [.font: NSFont.inter(12, weight: .semibold), .foregroundColor: accent]))
        label.attributedStringValue = text
        superview?.needsLayout = true
    }

    var fittingWidth: CGFloat { ceil(min(label.attributedStringValue.size().width, 200)) + 12 + 8 + 28 + 6 }

    override func layout() {
        super.layout()
        let labelWidth = bounds.width - 12 - 8 - 28 - 6
        label.frame = NSRect(x: 12, y: (bounds.height - 16) / 2, width: max(0, labelWidth), height: 16)
        keycapBox.frame = NSRect(x: bounds.width - 6 - 28, y: (bounds.height - 18) / 2, width: 28, height: 18)
        keycap.frame = NSRect(x: 0, y: 2, width: 28, height: 14)
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = (isHovered ? Palette.tabActive : Palette.surface).cgColor
        keycapBox.layer?.backgroundColor = Palette.tabHover.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateText()
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.96) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

@MainActor
final class LittleChevronButton: HoverView {
    var action: (() -> Void)?
    var isActive = false { didSet { needsDisplay = true } }
    private let icon = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        icon.image = .symbol("chevron.down", size: 10, weight: .semibold)
        icon.contentTintColor = Palette.subtle
        icon.imageScaling = .scaleNone
        addSubview(icon)
        toolTip = "Open in Another Space (\u{2325}\u{2318}O)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        icon.frame = bounds
    }

    override func updateLayer() {
        layer?.backgroundColor = (isHovered || isActive ? Palette.tabActive : Palette.surface).cgColor
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.94) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

@MainActor
final class LittleSpacePicker: NSView, NSTextFieldDelegate {
    var onChoose: ((Space) -> Void)?
    var onCancel: (() -> Void)?
    private let spaces: [Space]
    private let frost = FrostView()
    private let glyph = NSImageView()
    private let field = NSTextField()
    private let divider = HairlineView(inset: 0, color: Palette.white(0x1F))
    private var rows: [LittleSpaceRow] = []
    private var shown: [Space] = []
    private var selected = 0
    private static let width: CGFloat = 248
    private static let rowHeight: CGFloat = 34
    private static let fieldHeight: CGFloat = 40

    init(spaces: [Space], frameColor: NSColor) {
        self.spaces = spaces
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        frost.cornerRadius = 10
        frost.tint = Palette.commandBar(frame: frameColor)
        frost.washOpacity = 0.86
        frost.autoresizingMask = [.width, .height]
        addSubview(frost)
        glyph.image = .symbol("magnifyingglass", size: 12, weight: .medium)
        glyph.contentTintColor = Palette.subtle
        glyph.imageScaling = .scaleNone
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .inter(13)
        field.textColor = Palette.text
        field.placeholderAttributedString = NSAttributedString(
            string: "Search Spaces\u{2026}", attributes: [.font: NSFont.inter(13), .foregroundColor: Palette.faint])
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        for view in [glyph, field, divider] as [NSView] { addSubview(view) }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var contentHeight: CGFloat {
        Self.fieldHeight + 1 + 6 + CGFloat(max(rows.count, 1)) * Self.rowHeight + 6
    }

    func place(below anchor: NSRect, in container: NSRect) {
        let height = min(contentHeight, container.height - anchor.maxY - 16)
        frame = NSRect(x: anchor.maxX - Self.width, y: anchor.maxY + 6, width: Self.width, height: height)
    }

    func present() {
        window?.makeFirstResponder(field)
        guard !Motion.reduced else { return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard !Motion.reduced else {
            removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        })
    }

    override func layout() {
        super.layout()
        frost.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        glyph.frame = NSRect(x: 12, y: (Self.fieldHeight - 16) / 2, width: 16, height: 16)
        field.frame = NSRect(x: 34, y: (Self.fieldHeight - 18) / 2, width: bounds.width - 46, height: 18)
        divider.frame = NSRect(x: 0, y: Self.fieldHeight, width: bounds.width, height: 1)
        var y = Self.fieldHeight + 1 + 6
        for row in rows {
            row.frame = NSRect(x: 6, y: y, width: bounds.width - 12, height: Self.rowHeight)
            y += Self.rowHeight
        }
    }

    private func rebuild() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = query.isEmpty ? spaces : spaces.filter { $0.name.lowercased().contains(query) }
        rows.forEach { $0.removeFromSuperview() }
        rows = shown.enumerated().map { index, space in
            let row = LittleSpaceRow(space: space)
            row.onHover = { [weak self] in self?.select(index) }
            row.onClick = { [weak self] in self?.choose(index) }
            addSubview(row)
            return row
        }
        selected = 0
        updateSelection()
        if let superview { place(below: NSRect(x: frame.maxX - Self.width, y: frame.minY - 6, width: Self.width, height: 0), in: superview.bounds) }
        needsLayout = true
    }

    private func select(_ index: Int) {
        selected = index
        updateSelection()
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() { row.isSelected = index == selected }
    }

    private func choose(_ index: Int) {
        guard shown.indices.contains(index) else { return }
        onChoose?(shown[index])
    }

    func controlTextDidChange(_ notification: Notification) { rebuild() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if !rows.isEmpty { select(min(selected + 1, rows.count - 1)) }
        case #selector(NSResponder.moveUp(_:)):
            select(max(selected - 1, 0))
        case #selector(NSResponder.insertNewline(_:)):
            choose(selected)
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        default:
            return false
        }
        return true
    }
}

@MainActor
final class LittleSpaceRow: HoverView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private let badge = NSImageView()
    private let name = NSTextField.sidebarLabel("", font: .inter(13, weight: .medium))

    init(space: Space) {
        super.init(frame: .zero)
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        badge.image = SettingsStyle.badge(for: space, size: 22)
        badge.imageScaling = .scaleProportionallyDown
        name.stringValue = space.name
        name.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        badge.frame = NSRect(x: 6, y: (bounds.height - 22) / 2, width: 22, height: 22)
        name.frame = NSRect(x: 38, y: (bounds.height - 17) / 2, width: bounds.width - 46, height: 17)
    }

    override func updateLayer() {
        layer?.backgroundColor = isSelected ? Palette.tabHover.cgColor : NSColor.clear.cgColor
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}
