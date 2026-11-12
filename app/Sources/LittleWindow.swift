import AppKit

@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate, BrowserTabObserver {
    private static var open: [LittleWindowController] = []
    private static let size = NSSize(width: 920, height: 660)

    static func open(_ url: URL, space: Space, profile: Profile, browser: BrowserWindowController) {
        let controller = LittleWindowController(url: url, space: space, profile: profile, browser: browser)
        open.append(controller)
        controller.present()
    }

    private let tab: BrowserTab
    private let space: Space
    private weak var browser: BrowserWindowController?
    private let root = LittleRootView()
    private var adopted = false
    private lazy var passwordOffers = PasswordOfferPresenter { [weak self] toast in self?.root.showToast(toast) }

    private init(url: URL, space: Space, profile: Profile, browser: BrowserWindowController) {
        self.space = space
        self.browser = browser
        tab = BrowserTab(url: url)
        let window = BrowserWindow()
        window.minSize = NSSize(width: 420, height: 300)
        super.init(window: window)
        window.delegate = self
        window.contentView = root
        tab.observer = self
        let page = tab.materialize(in: profile)
        root.card.show(page.view)
        page.isVisible = true
        root.setFrameColor(space.frameColor)
        let name: NSAppearance.Name = space.frameColor.isDarkFrame ? .darkAqua : .aqua
        window.appearance = NSAppearance(named: name)
        root.openButton.title = "Open in \(space.name)"
        root.openButton.action = { [weak self] in self?.openInBrowser(space: nil) }
        root.copyButton.action = { [weak self] in self?.copyURL(nil) }
        root.menuButton.action = { [weak self] in self?.showMenu() }
        refreshHeader()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func present() {
        guard let window else { return }
        let screen = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(Self.size.width, screen.width - 40), height: min(Self.size.height, screen.height - 40))
        let cascade = CGFloat(Self.open.count - 1) * 26
        var origin = NSPoint(x: screen.midX - size.width / 2 + cascade, y: screen.midY - size.height / 2 - cascade)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        tab.tab?.focus()
    }

    private func refreshHeader() {
        root.titleLabel.stringValue = tab.title.isEmpty ? (tab.url.flatMap(LinkRouter.displayHost(of:)) ?? "") : tab.title
        root.hostLabel.stringValue = tab.url.flatMap(LinkRouter.displayHost(of:)) ?? ""
        root.favicon = tab.favicon
        window?.title = root.titleLabel.stringValue
        root.needsLayout = true
    }

    private func showMenu() {
        guard let browser else { return }
        var entries: [ActionMenuEntry] = [
            .item(ActionMenuItem(title: "Copy Link", symbol: "link", shortcut: nil) { [weak self] in self?.copyURL(nil) }),
            .separator,
        ]
        for space in browser.allSpaces where space.profileIdentifier == self.space.profileIdentifier {
            let symbol = space.symbol.isEmpty ? "circle" : SpaceSymbols.displayName(space.symbol, active: false)
            entries.append(.item(ActionMenuItem(title: "Open in \(space.name)", symbol: symbol, shortcut: nil) { [weak self] in
                self?.openInBrowser(space: space)
            }))
        }
        entries += [
            .separator,
            .item(ActionMenuItem(title: "Link Routing\u{2026}", symbol: "arrow.triangle.branch", shortcut: nil) {
                SettingsWindowController.shared.show(.links)
            }),
        ]
        let menu = ActionMenu(entries: entries)
        root.actionMenu = menu
        menu.show(relativeTo: root.menuButton)
    }

    private func openInBrowser(space target: Space?) {
        guard let browser, !adopted else { return }
        guard let destination = browser.liveSpace(target ?? space) else {
            NSSound.beep()
            return
        }
        adopted = true
        let offer = passwordOffers.takePending()
        tab.observer = nil
        root.card.show(nil)
        browser.adopt(tab, into: destination)
        if let offer { browser.passwordOffers.present(offer) }
        if let url = tab.url, target != nil { browser.offerRule(for: url, space: destination) }
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if !adopted {
            tab.observer = nil
            tab.close()
        }
        Self.open.removeAll { $0 === self }
    }

    // MARK: Menu commands

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
    let titleLabel = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 13, weight: .semibold))
    let hostLabel = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12), color: Palette.faint)
    let copyButton = IconButton(symbol: "link", size: 14, toolTip: "Copy Link")
    let menuButton = IconButton(symbol: "ellipsis", size: 14, toolTip: "More")
    let openButton = LittleOpenButton()
    var actionMenu: ActionMenu?
    var favicon: NSImage? { didSet { iconView.image = favicon ?? .symbol("globe", size: 13) } }
    private let iconView = NSImageView()
    private var frameColor: NSColor = Palette.ink
    private var toast: ToastView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = Palette.icon
        titleLabel.lineBreakMode = .byTruncatingTail
        hostLabel.lineBreakMode = .byTruncatingTail
        for view in [card, iconView, titleLabel, hostLabel, copyButton, menuButton, openButton] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setFrameColor(_ color: NSColor) {
        frameColor = color
        layer?.backgroundColor = color.cgColor
        toast?.fillColor = toastFill
    }

    private var toastFill: NSColor { Palette.opaque(Palette.surface, on: frameColor, appearance: effectiveAppearance) }

    override func layout() {
        super.layout()
        let inset = Metrics.cardInset
        let header = Metrics.titlebarHeight
        let w = bounds.width
        let lightsMaxX = (window as? BrowserWindow)?.trafficLightsMaxX ?? 67
        let center = header / 2
        let openWidth = openButton.fittingWidth
        openButton.frame = NSRect(x: w - inset - openWidth, y: center - 14, width: openWidth, height: 28)
        menuButton.frame = NSRect(x: openButton.frame.minX - 32, y: center - 14, width: 28, height: 28)
        copyButton.frame = NSRect(x: menuButton.frame.minX - 30, y: center - 14, width: 28, height: 28)
        iconView.frame = NSRect(x: lightsMaxX + 16, y: center - 8, width: 16, height: 16)
        let textX = iconView.frame.maxX + 8
        let available = max(0, copyButton.frame.minX - 12 - textX)
        let titleWidth = min(ceil(titleLabel.attributedStringValue.size().width) + 4, available * 0.65)
        titleLabel.frame = NSRect(x: textX, y: center - 9, width: titleWidth, height: 18)
        hostLabel.frame = NSRect(x: titleLabel.frame.maxX + 8, y: center - 8, width: max(0, available - titleWidth - 8), height: 16)
        card.frame = NSRect(x: inset, y: header, width: w - 2 * inset, height: bounds.height - header - inset)
        if let toast { toast.setFrameOrigin(toastOrigin(for: toast)) }
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
final class LittleOpenButton: HoverView {
    var action: (() -> Void)?
    var title = "" {
        didSet {
            label.stringValue = title
            superview?.needsLayout = true
        }
    }
    private let label = NSTextField.sidebarLabel("", font: .systemFont(ofSize: 12, weight: .semibold))
    private let icon = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        icon.image = .symbol("arrow.up.left.and.arrow.down.right", size: 11, weight: .semibold)
        icon.contentTintColor = Palette.text
        icon.imageScaling = .scaleNone
        label.alignment = .left
        addSubview(icon)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var fittingWidth: CGFloat { ceil(label.attributedStringValue.size().width) + 44 }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 30, y: (bounds.height - 16) / 2, width: bounds.width - 38, height: 16)
    }

    override func updateLayer() {
        layer?.backgroundColor = (isHovered ? Palette.tabHover : Palette.tabActive).cgColor
    }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.95) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}
