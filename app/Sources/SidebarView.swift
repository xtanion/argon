import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class SidebarView: NSView {
    weak var controller: BrowserWindowController?

    private let toggleButton = IconButton(symbol: "sidebar.left", size: 15, toolTip: "Hide Sidebar")
    private let backButton = IconButton(symbol: "arrow.left", size: 15, toolTip: "Back")
    private let forwardButton = IconButton(symbol: "arrow.right", size: 15, toolTip: "Forward")
    private let reloadButton = IconButton(symbol: "arrow.clockwise", size: 15, toolTip: "Reload")
    private let pill = URLPillView()
    private let spaceHeader = SpaceHeaderView()
    private var activeSpaceIndex = 0
    private var spaceCount = 0
    let newTabRow = NewTabRowView()
    private let tabScroll = SidebarScrollView()
    private let tabList = TabListView()
    private let spaceBar = SpaceBarView()
    private let spaceClip = FlippedView()
    private let spaceContent = FlippedView()
    private let favoritesGrid = FavoritesGridView()
    private var pageTop: CGFloat = 0
    private var gridFrame: NSRect { convert(favoritesGrid.frame, from: spaceContent) }
    private var zoneArmed = true
    private var zoneTimer: DispatchWorkItem?
    private var outgoingSnapshot: NSImageView?
    private var swipe: SpaceSwipe?
    private var swipeSettling = false
    private var swipeAxisLocked: Bool?

    private struct SpaceSwipe {
        var offset: CGFloat = 0
        var velocity: CGFloat = 0
        var target: Int?
        var direction = 0
        let snapshot: NSImageView
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        toggleButton.action = { [weak self] in self?.controller?.toggleSidebarPanel(nil) }
        backButton.action = { [weak self] in self?.controller?.goBack(nil) }
        forwardButton.action = { [weak self] in self?.controller?.goForward(nil) }
        reloadButton.action = { [weak self] in self?.controller?.reloadPage(nil) }
        pill.onClick = { [weak self] in self?.controller?.openLocation(nil) }
        pill.onCopy = { [weak self] in self?.controller?.copyURL(nil) }
        pill.onControls = { [weak self] in self?.toggleSiteControls() }
        newTabRow.onClick = { [weak self] in self?.controller?.newTab(nil) }

        tabScroll.drawsBackground = false
        tabScroll.hasVerticalScroller = true
        tabScroll.scrollerStyle = .overlay
        tabScroll.autohidesScrollers = true
        tabScroll.horizontalScrollElasticity = .none
        tabScroll.documentView = tabList
        tabScroll.contentView.drawsBackground = false
        tabList.sidebar = self
        spaceBar.sidebar = self
        favoritesGrid.sidebar = self
        favoritesGrid.list = tabList
        spaceHeader.onToggle = { [weak self] in self?.controller?.togglePinnedSection() }
        spaceHeader.menuProvider = { [weak self] anchor in self?.spaceMenu(relativeTo: anchor) }

        spaceClip.wantsLayer = true
        spaceClip.layer?.masksToBounds = true
        spaceContent.wantsLayer = true
        spaceClip.addSubview(spaceContent)
        tabList.newTabRow = newTabRow
        for view in [favoritesGrid, spaceHeader, tabScroll] as [NSView] {
            spaceContent.addSubview(view)
        }
        for view in [toggleButton, backButton, forwardButton, reloadButton, pill, spaceClip, spaceBar] as [NSView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setSidebarHovered(true) }
    override func mouseExited(with event: NSEvent) { setSidebarHovered(false) }

    private func setSidebarHovered(_ hovered: Bool) {
        pill.revealsCopy = hovered
        tabList.revealsClear = hovered
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let p = Metrics.padding
        let size = Metrics.toolbarButtonSize
        let y = (Metrics.titlebarHeight - size) / 2
        let lightsMaxX = (window as? BrowserWindow)?.trafficLightsMaxX ?? 67
        toggleButton.frame = NSRect(x: lightsMaxX + 6, y: y, width: size, height: size)
        reloadButton.frame = NSRect(x: w - 4 - size, y: y, width: size, height: size)
        forwardButton.frame = reloadButton.frame.offsetBy(dx: -Metrics.toolbarButtonPitch, dy: 0)
        backButton.frame = forwardButton.frame.offsetBy(dx: -Metrics.toolbarButtonPitch, dy: 0)
        let navHidden = backButton.frame.minX < toggleButton.frame.maxX + 4
        for b in [backButton, forwardButton, reloadButton] { b.isHidden = navHidden }

        pill.frame = NSRect(x: p, y: Metrics.titlebarHeight, width: w - 2 * p, height: Metrics.rowHeight)
        spaceBar.frame = NSRect(x: 0, y: bounds.height - Metrics.spaceBarHeight, width: w, height: Metrics.spaceBarHeight)
        let clipTop = pill.frame.maxY
        spaceClip.frame = NSRect(x: 0, y: clipTop, width: w, height: max(0, spaceBar.frame.minY - clipTop))
        if swipe == nil, !swipeSettling { spaceContent.frame = spaceClip.bounds }
        outgoingSnapshot?.frame.size = spaceClip.bounds.size
        let gridHeight = favoritesGrid.contentHeight
        favoritesGrid.frame = NSRect(x: p, y: gridHeight > 0 ? 8 : 0, width: w - 2 * p, height: gridHeight)
        pageTop = gridHeight > 0 ? favoritesGrid.frame.maxY + 2 : 0
        spaceHeader.frame = NSRect(x: p, y: pageTop + 7, width: w - 2 * p, height: Metrics.rowHeight)
        let listTop = spaceHeader.frame.maxY
        tabScroll.frame = NSRect(x: 0, y: listTop, width: w, height: max(0, spaceContent.bounds.height - listTop))
        tabList.layoutRows(width: w)
    }

    func update(spaces: [Space], activeIndex: Int, commandBarOpen: Bool, animated: Bool = false, preview: Bool = false) {
        guard spaces.indices.contains(activeIndex) else { return }
        let space = spaces[activeIndex]
        activeSpaceIndex = activeIndex
        spaceCount = spaces.count
        spaceHeader.configure(
            name: space.name,
            icon: space.symbol.isEmpty ? .symbol("circle.fill", size: 5)
                : .symbol(SpaceSymbols.displayName(space.symbol, active: true), size: Metrics.spaceIconSize),
            collapsed: space.pinnedCollapsed
        )
        newTabRow.isHighlighted = commandBarOpen
        tabList.update(space: space, active: commandBarOpen ? nil : space.activeTab, spaces: spaces, activeSpace: activeIndex,
                       animated: animated && !Motion.reduced)
        favoritesGrid.update(favorites: space.favorites, active: commandBarOpen ? nil : space.activeTab,
                             animated: animated && !preview && !Motion.reduced)
        guard !preview else {
            needsLayout = true
            return
        }
        spaceBar.update(spaces: spaces, activeIndex: activeIndex)
        updateToolbar(for: space.activeTab)
        needsLayout = true
    }

    func updateToolbar(for tab: BrowserTab?) {
        pill.url = tab?.url
        backButton.isEnabled = tab?.tab?.canGoBack ?? false
        forwardButton.isEnabled = tab?.tab?.canGoForward ?? false
        reloadButton.isEnabled = tab != nil
        reloadButton.setSymbol(tab?.isLoading == true ? "xmark" : "arrow.clockwise", size: 15)
    }

    func refresh(_ tab: BrowserTab) {
        tabList.refresh(tab)
        favoritesGrid.refresh(tab)
    }

    func relayout(animated: Bool) {
        needsLayout = true
        guard animated, !Motion.reduced, window != nil else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            context.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
        }
    }

    // MARK: Favorites drop target

    var listTop: CGFloat { spaceClip.frame.minY + pageTop }

    func addDragGhost(_ ghost: NSView) { addSubview(ghost, positioned: .above, relativeTo: nil) }

    // Returns the favorites index under the pointer, or nil when the drag belongs to the tab list.
    // With no favorites yet, the drop zone only opens after the pointer rests near the top for a moment.
    func favoritesDropIndex(for item: SidebarItem, at point: NSPoint, onReady: @escaping @MainActor () -> Void) -> Int? {
        guard case .tab(let tab) = item, point.y >= pill.frame.minY else {
            resetFavoritesDrag(keepZone: false)
            return nil
        }
        if favoritesGrid.favorites.isEmpty {
            if favoritesGrid.showsDropZone {
                if point.y <= gridFrame.maxY + 8 {
                    favoritesGrid.setDropZoneHighlighted(true)
                    return 0
                }
                favoritesGrid.setDropZoneHighlighted(false)
                favoritesGrid.setDropZoneVisible(false)
                zoneArmed = false
                return nil
            }
            let inTrigger = point.y < spaceClip.frame.minY + spaceHeader.frame.midY
            guard inTrigger else {
                zoneArmed = true
                zoneTimer?.cancel()
                zoneTimer = nil
                return nil
            }
            if zoneArmed, zoneTimer == nil {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.zoneTimer != nil else { return }
                        self.zoneTimer = nil
                        self.favoritesGrid.setDropZoneVisible(true)
                        onReady()
                    }
                }
                zoneTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
            return nil
        }
        guard point.y <= gridFrame.maxY + 6 else {
            favoritesGrid.setDragPreview(dragging: favoritesGrid.contains(tab) ? tab : nil, index: nil)
            return nil
        }
        let index = favoritesGrid.dropIndex(at: favoritesGrid.convert(point, from: self), dragging: tab)
        favoritesGrid.setDragPreview(dragging: tab, index: index)
        return index
    }

    func endFavoritesDrag() {
        resetFavoritesDrag(keepZone: false)
        zoneArmed = true
    }

    private func resetFavoritesDrag(keepZone: Bool) {
        zoneTimer?.cancel()
        zoneTimer = nil
        favoritesGrid.setDropZoneHighlighted(false)
        if !keepZone { favoritesGrid.setDropZoneVisible(false) }
        favoritesGrid.setDragPreview(dragging: nil, index: nil)
    }

    func showCopiedFeedback() { pill.showCopied() }

    private var siteControls: SiteControlsPanel?
    private var siteControlsClosedAt: CFTimeInterval = 0

    func toggleSiteControls() {
        if let panel = siteControls {
            panel.close()
            return
        }
        guard CACurrentMediaTime() - siteControlsClosedAt > 0.25, let controller, controller.activeTab?.url != nil,
              let root = sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? RootView }).first else { return }
        let panel = SiteControlsPanel(controller: controller)
        panel.fillColor = root.toastFill
        panel.onClose = { [weak self, weak panel] in
            guard let self, self.siteControls === panel else { return }
            self.siteControls = nil
            self.siteControlsClosedAt = CACurrentMediaTime()
            self.pill.controlsOpen = false
        }
        siteControls = panel
        pill.controlsOpen = true
        panel.present(in: root, below: pill, anchor: pill.controlsButton)
    }
    func toggleDownloads() { spaceBar.toggleDownloads() }
    func spaceAnchor(_ index: Int) -> NSView { spaceBar.button(forSpace: index) ?? spaceBar }

    private func spaceMenu(relativeTo anchor: NSView) -> NSMenu {
        let index = activeSpaceIndex
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Rename Space...") { [weak self] in self?.renameSpace(index) })
        menu.addItem(ClosureMenuItem("Change Icon...") { [weak self, weak anchor] in
            guard let anchor else { return }
            self?.editIcon(index, relativeTo: anchor)
        })
        menu.addItem(ClosureMenuItem("Edit Theme...") { [weak self, weak anchor] in
            guard let anchor else { return }
            self?.editTheme(index, relativeTo: anchor)
        })
        menu.addItem(.separator())
        let delete = ClosureMenuItem("Delete Space") { [weak self] in self?.deleteSpace(index) }
        delete.isEnabled = spaceCount > 1
        menu.addItem(delete)
        return menu
    }

    func beginRenaming(_ folder: SidebarFolder) { tabList.beginRenaming(folder) }

    func prepareSpaceChange() {
        outgoingSnapshot?.removeFromSuperview()
        outgoingSnapshot = nil
        guard !Motion.reduced, !spaceContent.bounds.isEmpty,
              let rep = spaceContent.bitmapImageRepForCachingDisplay(in: spaceContent.bounds) else { return }
        spaceContent.cacheDisplay(in: spaceContent.bounds, to: rep)
        let image = NSImage(size: spaceContent.bounds.size)
        image.addRepresentation(rep)
        let snapshot = NSImageView(frame: spaceContent.bounds)
        snapshot.image = image
        snapshot.imageScaling = .scaleNone
        snapshot.wantsLayer = true
        spaceClip.addSubview(snapshot)
        outgoingSnapshot = snapshot
    }

    func animateSpaceChange(direction: Int) {
        guard let snapshot = outgoingSnapshot, let snapLayer = snapshot.layer, let contentLayer = spaceContent.layer else { return }
        layoutSubtreeIfNeeded()
        let offset = spaceClip.bounds.width * CGFloat(direction)
        let timing = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
        func slide(_ layer: CALayer, from: CGFloat, to: CGFloat) {
            let anim = CABasicAnimation(keyPath: "transform.translation.x")
            anim.fromValue = from
            anim.toValue = to
            anim.duration = 0.4
            anim.timingFunction = timing
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "spaceSlide")
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak snapshot] in
            guard let self, let snapshot, self.outgoingSnapshot === snapshot else { return }
            snapshot.removeFromSuperview()
            self.outgoingSnapshot = nil
            self.spaceContent.layer?.removeAnimation(forKey: "spaceSlide")
        }
        slide(snapLayer, from: 0, to: -offset)
        slide(contentLayer, from: offset, to: 0)
        CATransaction.commit()
    }

    // Sidebar actions forwarded from subviews.
    func select(_ tab: BrowserTab) { controller?.select(tab) }
    func close(_ tab: BrowserTab) { controller?.close(tab) }
    func move(_ tab: BrowserTab, toSpace index: Int) { controller?.move(tab, toSpace: index) }
    func selectSpace(_ index: Int) { controller?.selectSpace(index) }
    func newSpace() { controller?.newSpace(nil) }
    func renameSpace(_ index: Int) { controller?.renameSpace(index) }
    func deleteSpace(_ index: Int) { controller?.deleteSpace(index) }
    func setSymbol(_ symbol: String, forSpace index: Int) { controller?.setSymbol(symbol, forSpace: index) }
    func editTheme(_ index: Int, relativeTo view: NSView) { controller?.showThemeEditor(forSpace: index, relativeTo: view) }
    func editIcon(_ index: Int, relativeTo view: NSView) { controller?.showIconPicker(forSpace: index, relativeTo: view) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            controller?.newTab(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.phase != [] || event.momentumPhase != [] else {
            super.scrollWheel(with: event)
            return
        }
        guard event.momentumPhase == [], !swipeSettling else { return }
        switch event.phase {
        case .began:
            cancelSwipe()
            swipeAxisLocked = nil
        case .changed:
            if swipeAxisLocked == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                swipeAxisLocked = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }
            if swipeAxisLocked == true { trackSwipe(by: event.scrollingDeltaX) }
        case .ended, .cancelled:
            endSwipe(cancelled: event.phase == .cancelled)
        default:
            break
        }
    }

    private var pageWidth: CGFloat { spaceClip.bounds.width }

    private func trackSwipe(by delta: CGFloat) {
        guard let controller, delta != 0 else { return }
        if swipe == nil {
            guard !spaceClip.bounds.isEmpty, let snapshot = makeSnapshot() else { return }
            outgoingSnapshot?.removeFromSuperview()
            outgoingSnapshot = nil
            spaceContent.layer?.removeAnimation(forKey: "spaceSlide")
            spaceClip.addSubview(snapshot)
            swipe = SpaceSwipe(snapshot: snapshot)
        }
        guard var current = swipe else { return }
        current.offset += delta
        current.velocity = delta
        let direction = current.offset > 0 ? -1 : (current.offset < 0 ? 1 : current.direction)
        if direction != current.direction {
            current.direction = direction
            let range = controller.spaceSwipeRange
            let index = range.active + direction
            current.target = (0..<range.count).contains(index) ? index : nil
            if let target = current.target {
                controller.previewSpace(target)
                spaceContent.isHidden = false
                layoutSubtreeIfNeeded()
            } else {
                spaceContent.isHidden = true
            }
        }
        swipe = current
        applySwipe(current)
    }

    private func applySwipe(_ swipe: SpaceSwipe) {
        let width = pageWidth
        let offset = swipe.target == nil ? rubberBand(swipe.offset, limit: width) : max(-width, min(width, swipe.offset))
        swipe.snapshot.setFrameOrigin(NSPoint(x: offset, y: 0))
        spaceContent.setFrameOrigin(NSPoint(x: offset + CGFloat(swipe.direction) * width, y: 0))
        if let target = swipe.target {
            controller?.previewSpaceColor(toward: target, progress: abs(offset) / max(width, 1))
        }
    }

    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = offset < 0 ? -1 : 1
        let x = abs(offset)
        return sign * (1 - 1 / (x * 0.55 / max(limit, 1) + 1)) * limit * 0.5
    }

    private func endSwipe(cancelled: Bool) {
        guard let current = swipe else { return }
        let width = pageWidth
        let flicked = abs(current.velocity) > 18 && (current.velocity < 0) == (current.offset < 0)
        let commit = !cancelled && current.target != nil && (abs(current.offset) > width * 0.35 || flicked)
        let snapshotX: CGFloat = commit ? -CGFloat(current.direction) * width : 0
        let contentX: CGFloat = commit ? 0 : CGFloat(current.direction) * width
        swipe = nil
        swipeSettling = true
        if commit, let target = current.target { controller?.previewSpaceColor(toward: target, progress: 1) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduced ? 0 : 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            current.snapshot.animator().setFrameOrigin(NSPoint(x: snapshotX, y: 0))
            spaceContent.animator().setFrameOrigin(NSPoint(x: contentX, y: 0))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                current.snapshot.removeFromSuperview()
                self.swipeSettling = false
                self.spaceContent.isHidden = false
                self.spaceContent.frame = self.spaceClip.bounds
                self.controller?.finishSpaceSwipe(to: commit ? current.target : nil)
            }
        })
    }

    private func cancelSwipe() {
        guard let current = swipe else { return }
        current.snapshot.removeFromSuperview()
        swipe = nil
        spaceContent.isHidden = false
        spaceContent.frame = spaceClip.bounds
        controller?.finishSpaceSwipe(to: nil)
    }

    private func makeSnapshot() -> NSImageView? {
        guard let rep = spaceContent.bitmapImageRepForCachingDisplay(in: spaceContent.bounds) else { return nil }
        spaceContent.cacheDisplay(in: spaceContent.bounds, to: rep)
        let image = NSImage(size: spaceContent.bounds.size)
        image.addRepresentation(rep)
        let snapshot = NSImageView(frame: spaceContent.bounds)
        snapshot.image = image
        snapshot.imageScaling = .scaleNone
        return snapshot
    }
}

// Passes horizontal swipes up to the sidebar so they switch spaces.
@MainActor
final class SidebarScrollView: NSScrollView {
    private var horizontalGesture: Bool?

    // The axis is decided by the first event that moves; a gesture's began event often has zero deltas.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == [] && event.momentumPhase == [] {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                superview?.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
            return
        }
        if event.phase == .began {
            horizontalGesture = nil
            superview?.scrollWheel(with: event)
            super.scrollWheel(with: event)
            return
        }
        if horizontalGesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            horizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        if horizontalGesture == true {
            superview?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

@MainActor
final class TabListView: NSView {
    private enum Entry {
        case tab(BrowserTab, depth: Int, parent: SidebarFolder?, index: Int)
        case folder(SidebarFolder, depth: Int, parent: SidebarFolder?, index: Int)
    }

    weak var sidebar: SidebarView?
    var newTabRow: NewTabRowView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let newTabRow { addSubview(newTabRow) }
        }
    }
    private let divider = HairlineView(inset: 0)
    private let clearButton = TextButton(title: "Clear")
    var revealsClear = false {
        didSet {
            guard revealsClear != oldValue else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = revealsClear ? 0.12 : 0.16
                clearButton.animator().alphaValue = revealsClear ? 1 : 0
            }
            layoutRows(width: superview?.bounds.width ?? bounds.width, animated: true)
        }
    }
    private var tabRows: [ObjectIdentifier: TabRowView] = [:]
    private var folderRows: [ObjectIdentifier: FolderRowView] = [:]
    private var entries: [Entry] = []
    private var todayTabs: [BrowserTab] = []
    private var rootCount = 0
    private let indicator = DropIndicatorView()
    private var ghost: DragGhostView?
    private var ghostOriginX: CGFloat = 0
    private var ghostFollowsPointer = false
    private var dropTarget: SidebarDrop?
    private var favoriteTarget: Int?
    private var lastDrag: (item: SidebarItem, event: NSEvent, grab: NSPoint)?
    private var feedbackKey: String?

    private func tick(_ key: String?) {
        guard key != feedbackKey else { return }
        feedbackKey = key
        if key != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }
    private weak var highlightedFolder: FolderRowView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        clearButton.toolTip = "Close all unpinned tabs"
        clearButton.alphaValue = 0
        clearButton.action = { [weak self] in self?.sidebar?.controller?.clearTodayTabs() }
        addSubview(divider)
        addSubview(clearButton)
        indicator.isHidden = true
        addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(space: Space, active: BrowserTab?, spaces: [Space], activeSpace: Int, animated: Bool) {
        var built: [Entry] = []
        func walk(_ items: [SidebarItem], depth: Int, parent: SidebarFolder?) {
            for (index, item) in items.enumerated() {
                switch item {
                case .tab(let tab):
                    built.append(.tab(tab, depth: depth, parent: parent, index: index))
                case .folder(let folder):
                    built.append(.folder(folder, depth: depth, parent: parent, index: index))
                    if folder.isExpanded { walk(folder.children, depth: depth + 1, parent: folder) }
                }
            }
        }
        walk(space.pinned, depth: 0, parent: nil)
        if space.pinnedCollapsed {
            built = built.filter { entry in
                if case .tab(let tab, _, _, _) = entry { return tab === active }
                return false
            }
        }
        rootCount = space.pinned.count
        entries = built
        todayTabs = space.tabs

        var liveTabs = Set<ObjectIdentifier>()
        var liveFolders = Set<ObjectIdentifier>()
        let spaceNames = spaces.enumerated().map { $0.offset == activeSpace ? nil : $0.element.name }
        let folders = space.folders
        var fresh: [NSView] = []

        func tabRow(_ tab: BrowserTab, depth: Int) {
            let id = ObjectIdentifier(tab)
            liveTabs.insert(id)
            let row = tabRows[id] ?? {
                let row = TabRowView(tab: tab)
                row.sidebar = sidebar
                row.list = self
                addSubview(row)
                tabRows[id] = row
                fresh.append(row)
                return row
            }()
            row.isActive = tab === active
            row.indent = CGFloat(depth) * Metrics.folderIndent
            row.spaceNames = spaceNames
            row.folders = folders
            row.refresh()
        }

        for entry in entries {
            switch entry {
            case .tab(let tab, let depth, _, _):
                tabRow(tab, depth: depth)
            case .folder(let folder, let depth, _, _):
                let id = ObjectIdentifier(folder)
                liveFolders.insert(id)
                let row = folderRows[id] ?? {
                    let row = FolderRowView(folder: folder)
                    row.sidebar = sidebar
                    row.list = self
                    addSubview(row)
                    folderRows[id] = row
                    fresh.append(row)
                    return row
                }()
                row.indent = CGFloat(depth) * Metrics.folderIndent
                row.folders = folders
                row.refresh()
            }
        }
        for tab in todayTabs { tabRow(tab, depth: 0) }

        var gone: [NSView] = []
        for (id, row) in tabRows where !liveTabs.contains(id) {
            gone.append(row)
            tabRows[id] = nil
        }
        for (id, row) in folderRows where !liveFolders.contains(id) {
            gone.append(row)
            folderRows[id] = nil
        }
        clearButton.isHidden = todayTabs.isEmpty

        guard animated else {
            gone.forEach { $0.removeFromSuperview() }
            layoutRows(width: superview?.bounds.width ?? bounds.width)
            return
        }
        layoutRows(width: superview?.bounds.width ?? bounds.width, animated: true, skipping: Set(fresh.map(ObjectIdentifier.init)))
        for view in fresh {
            view.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            fresh.forEach { $0.animator().alphaValue = 1 }
            gone.forEach { $0.animator().alphaValue = 0 }
            gone.forEach { Motion.shrinkOut($0) }
        } completionHandler: {
            MainActor.assumeIsolated { gone.forEach { $0.removeFromSuperview() } }
        }
    }

    func refresh(_ tab: BrowserTab) {
        tabRows[ObjectIdentifier(tab)]?.refresh()
    }

    func beginRenaming(_ folder: SidebarFolder) {
        guard let row = folderRows[ObjectIdentifier(folder)] else { return }
        row.scrollToVisible(row.bounds)
        row.beginRename()
    }

    func layoutRows(width: CGFloat, animated: Bool = false, skipping: Set<ObjectIdentifier> = []) {
        let p = Metrics.padding
        let rowWidth = width - 2 * p
        let step = Metrics.rowHeight + Metrics.tabSpacing
        var frames: [(NSView, NSRect)] = []
        var y: CGFloat = entries.isEmpty ? 0 : 4
        for entry in entries {
            let view = self.view(for: entry)
            if let view { frames.append((view, NSRect(x: p, y: y, width: rowWidth, height: Metrics.rowHeight))) }
            y += step
        }
        if !entries.isEmpty { y += 4 }
        y = max(y, 9)
        let clearWidth: CGFloat = clearButton.isHidden ? 0 : clearButton.fittingWidth
        let dividerInset: CGFloat = revealsClear && clearWidth > 0 ? clearWidth + 10 : 0
        frames.append((divider, NSRect(x: p, y: y, width: rowWidth - dividerInset, height: 1)))
        frames.append((clearButton, NSRect(x: p + rowWidth - clearWidth, y: y - 10, width: clearWidth, height: 18)))
        y += 11
        if let newTabRow {
            frames.append((newTabRow, NSRect(x: p, y: y, width: rowWidth, height: Metrics.rowHeight)))
            y += step
        }
        for tab in todayTabs {
            if let row = tabRows[ObjectIdentifier(tab)] {
                frames.append((row, NSRect(x: p, y: y, width: rowWidth, height: Metrics.rowHeight)))
            }
            y += step
        }
        let height = max(y, superview?.bounds.height ?? 0)
        setFrameSize(NSSize(width: width, height: height))

        guard animated else {
            for (view, frame) in frames { view.frame = frame }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            context.allowsImplicitAnimation = true
            for (view, frame) in frames {
                if skipping.contains(ObjectIdentifier(view)) || view.frame == .zero {
                    view.frame = frame
                } else {
                    view.animator().frame = frame
                }
            }
        }
    }

    private func view(for entry: Entry) -> NSView? {
        switch entry {
        case .tab(let tab, _, _, _): return tabRows[ObjectIdentifier(tab)]
        case .folder(let folder, _, _, _): return folderRows[ObjectIdentifier(folder)]
        }
    }

    // MARK: Drag and drop

    // Runs the drag loop after a mouse down on a row. Returns false when the
    // mouse was released without moving, so the row can treat it as a click.
    func trackDrag(of item: SidebarItem, row: NSView, mouseDown event: NSEvent) -> Bool {
        guard let window else { return false }
        let start = event.locationInWindow
        let grab = row.convert(start, from: nil)
        var dragging = false
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { next, stop in
            guard let next else {
                stop.pointee = true
                return
            }
            MainActor.assumeIsolated {
                if next.type == .leftMouseUp {
                    if dragging { self.endDrag(item, row: row) }
                    self.lastDrag = nil
                    stop.pointee = true
                    return
                }
                let point = next.locationInWindow
                if !dragging, hypot(point.x - start.x, point.y - start.y) > 4 {
                    dragging = true
                    self.feedbackKey = nil
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    self.beginDrag(item, row: row)
                }
                if dragging { self.updateDrag(item, event: next, grab: grab) }
            }
        }
        return dragging
    }

    private func beginDrag(_ item: SidebarItem, row: NSView) {
        guard let host = sidebar else { return }
        var favicon: NSImage?
        if case .tab(let tab) = item { favicon = tab.favicon }
        let container = DragGhostView(row: row, favicon: favicon)
        container.frame = host.convert(row.bounds, from: row)
        ghostOriginX = container.frame.minX
        ghostFollowsPointer = row is FavoriteCellView
        host.addDragGhost(container)
        ghost = container
        row.alphaValue = 0.35
    }

    private func redrag() {
        guard let lastDrag else { return }
        updateDrag(lastDrag.item, event: lastDrag.event, grab: lastDrag.grab)
    }

    private func updateDrag(_ item: SidebarItem, event: NSEvent, grab: NSPoint) {
        lastDrag = (item, event, grab)
        guard let host = sidebar else { return }
        let hostPoint = host.convert(event.locationInWindow, from: nil)
        if let index = host.favoritesDropIndex(for: item, at: hostPoint, onReady: { [weak self] in self?.redrag() }) {
            favoriteTarget = index
            dropTarget = nil
            clearListTarget()
            tick("favorite \(index)")
            if let ghost {
                ghost.setCompact(true)
                let side = FavoritesGridView.cellHeight
                ghost.frame = NSRect(x: hostPoint.x - side / 2, y: hostPoint.y - side / 2, width: side, height: side)
            }
            return
        }
        favoriteTarget = nil
        if let ghost {
            ghost.setCompact(false)
            let damping: CGFloat = ghostFollowsPointer ? 1 : 0.3
            ghost.frame = NSRect(origin: NSPoint(x: ghostOriginX + (hostPoint.x - grab.x - ghostOriginX) * damping, y: hostPoint.y - grab.y),
                                 size: ghost.rowSize)
        }
        guard hostPoint.y >= host.listTop else {
            dropTarget = nil
            clearListTarget()
            tick(nil)
            return
        }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let target = dropTarget(for: item, at: point)
        dropTarget = target?.drop
        if let folder = target?.folder {
            tick("folder \(ObjectIdentifier(folder).hashValue)")
        } else {
            tick(target?.y.map { "slot \(Int($0.rounded()))" })
        }
        if let folder = target?.folder, let row = folderRows[ObjectIdentifier(folder)] {
            if highlightedFolder !== row {
                highlightedFolder?.isDropTarget = false
                row.isDropTarget = true
                highlightedFolder = row
            }
            indicator.isHidden = true
        } else {
            highlightedFolder?.isDropTarget = false
            highlightedFolder = nil
            if let target, let y = target.y {
                let x = Metrics.padding + 4 + CGFloat(target.depth) * Metrics.folderIndent
                indicator.frame = NSRect(x: x, y: y - 5, width: bounds.width - Metrics.padding - 4 - x, height: 10)
                indicator.isHidden = false
            } else {
                indicator.isHidden = true
            }
        }
    }

    private func clearListTarget() {
        indicator.isHidden = true
        highlightedFolder?.isDropTarget = false
        highlightedFolder = nil
    }

    private func endDrag(_ item: SidebarItem, row: NSView) {
        ghost?.removeFromSuperview()
        ghost = nil
        clearListTarget()
        row.alphaValue = 1
        let target = dropTarget
        let favorite = favoriteTarget
        dropTarget = nil
        favoriteTarget = nil
        feedbackKey = nil
        if favorite != nil || target != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if let favorite, case .tab(let tab) = item {
            sidebar?.controller?.addFavorite(tab, at: favorite)
        } else if let target {
            sidebar?.controller?.drop(item, at: target)
        }
        sidebar?.endFavoritesDrag()
    }

    private struct DropCandidate {
        var drop: SidebarDrop
        var folder: SidebarFolder?
        var y: CGFloat?
        var depth: Int
    }

    private func dropTarget(for item: SidebarItem, at point: NSPoint) -> DropCandidate? {
        let half = Metrics.tabSpacing / 2
        var dragged: SidebarFolder?
        if case .folder(let folder) = item { dragged = folder }
        func allowed(_ parent: SidebarFolder?) -> Bool {
            guard let dragged, let parent else { return true }
            return !SidebarItem.folder(dragged).contains(parent)
        }
        let pinnedEnd = DropCandidate(
            drop: .pinned(parent: nil, index: rootCount),
            y: entries.last.flatMap { view(for: $0)?.frame.maxY }.map { $0 + half } ?? divider.frame.minY - 4,
            depth: 0
        )

        if point.y < divider.frame.minY + 6 || dragged != nil && point.y < divider.frame.maxY + Metrics.rowHeight {
            for entry in entries {
                guard let frame = view(for: entry)?.frame, point.y < frame.maxY + half else { continue }
                switch entry {
                case .folder(let folder, let depth, let parent, let index):
                    let quarter = frame.height / 4
                    if point.y > frame.minY + quarter, point.y < frame.maxY - quarter, allowed(folder) {
                        return DropCandidate(drop: .into(folder), folder: folder, depth: depth + 1)
                    }
                    if point.y < frame.midY {
                        return allowed(parent) ? DropCandidate(drop: .pinned(parent: parent, index: index), y: frame.minY - half, depth: depth) : nil
                    }
                    if folder.isExpanded, !folder.children.isEmpty {
                        return allowed(folder) ? DropCandidate(drop: .pinned(parent: folder, index: 0), y: frame.maxY + half, depth: depth + 1) : nil
                    }
                    return allowed(parent) ? DropCandidate(drop: .pinned(parent: parent, index: index + 1), y: frame.maxY + half, depth: depth) : nil
                case .tab(_, let depth, let parent, let index):
                    guard allowed(parent) else { return nil }
                    if point.y < frame.midY {
                        return DropCandidate(drop: .pinned(parent: parent, index: index), y: frame.minY - half, depth: depth)
                    }
                    return DropCandidate(drop: .pinned(parent: parent, index: index + 1), y: frame.maxY + half, depth: depth)
                }
            }
            return pinnedEnd
        }

        guard dragged == nil else { return pinnedEnd }
        for (index, tab) in todayTabs.enumerated() {
            guard let frame = tabRows[ObjectIdentifier(tab)]?.frame else { continue }
            if point.y < frame.midY { return DropCandidate(drop: .today(index: index), y: frame.minY - half, depth: 0) }
        }
        let lastY = todayTabs.last.flatMap { tabRows[ObjectIdentifier($0)]?.frame.maxY } ?? newTabRow?.frame.maxY ?? divider.frame.maxY
        return DropCandidate(drop: .today(index: todayTabs.count), y: lastY + half, depth: 0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            sidebar?.controller?.newTab(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("New Tab") { [weak self] in self?.sidebar?.controller?.newTab(nil) })
        menu.addItem(ClosureMenuItem("New Folder") { [weak self] in self?.sidebar?.controller?.newFolder() })
        return menu
    }
}

// Folder glyph in Arc's style: a solid folder with the chosen icon cut out of
// it, which tips its front flap open while the folder is expanded.
@MainActor
enum FolderIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(open: Bool, glyph: String, size: CGFloat) -> NSImage {
        image(progress: open ? 1 : 0, glyph: glyph, size: size)
    }

    // progress 0 is closed, 1 is open; in between the back panel leans left and the front shears right.
    static func image(progress: CGFloat, glyph: String, size: CGFloat) -> NSImage {
        let t = min(max(progress, 0), 1)
        let key = "\(Int((t * 100).rounded()))|\(glyph)|\(size)"
        if let cached = cache[key] { return cached }
        let mark = glyph.isEmpty ? nil : NSImage.symbol(glyph, size: size * 0.44, weight: .semibold)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            draw(t: t, s: rect.width, mark: mark, context: context)
            return true
        }
        image.isTemplate = true
        if t == 0 || t == 1 { cache[key] = image }
        return image
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
        NSPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }

    private static func roundedPolygon(_ points: [NSPoint], radii: [CGFloat]) -> NSBezierPath {
        let path = NSBezierPath()
        let n = points.count
        let start = NSPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2)
        path.move(to: start)
        for k in 0..<n {
            path.appendArc(from: points[k], to: points[(k + 1) % n], radius: radii[k])
        }
        path.close()
        return path
    }

    private static func draw(t: CGFloat, s: CGFloat, mark: NSImage?, context: NSGraphicsContext) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let lw = s * 0.085
        let r = s * 0.15

        let back = NSBezierPath()
        let tl = lerp(p(0.07, 0.1), p(0.1, 0.12), t)
        let tabEnd = lerp(p(0.4, 0.1), p(0.36, 0.12), t)
        let stepStart = lerp(p(0.52, 0.19), p(0.47, 0.2), t)
        let tr = lerp(p(0.93, 0.19), p(0.84, 0.2), t)
        let br = lerp(p(0.93, 0.92), p(0.8, 0.92), t)
        let bl = lerp(p(0.07, 0.92), p(0.28, 0.92), t)
        back.move(to: NSPoint(x: (bl.x + tl.x) / 2, y: (bl.y + tl.y) / 2))
        back.appendArc(from: tl, to: tabEnd, radius: r)
        back.line(to: tabEnd)
        back.curve(to: stepStart,
                   controlPoint1: NSPoint(x: tabEnd.x + (stepStart.x - tabEnd.x) * 0.5, y: tabEnd.y),
                   controlPoint2: NSPoint(x: tabEnd.x + (stepStart.x - tabEnd.x) * 0.5, y: stepStart.y))
        back.appendArc(from: tr, to: br, radius: r)
        back.appendArc(from: br, to: bl, radius: r)
        back.appendArc(from: bl, to: tl, radius: r)
        back.close()
        back.lineWidth = lw
        back.lineJoinStyle = .round
        NSColor.black.withAlphaComponent(0.45).setFill()
        back.fill()
        NSColor.black.setStroke()
        back.stroke()

        let front = [
            lerp(p(0.07, 0.33), p(0.37, 0.38), t),
            lerp(p(0.93, 0.33), p(0.99, 0.38), t),
            lerp(p(0.93, 0.92), p(0.84, 0.92), t),
            lerp(p(0.07, 0.92), p(0.22, 0.92), t),
        ]
        let topRadius = lerp(s * 0.01, s * 0.08, t)
        let frontPath = roundedPolygon(front, radii: [topRadius, topRadius, r, r])
        frontPath.lineWidth = lw
        frontPath.lineJoinStyle = .round
        context.saveGraphicsState()
        context.compositingOperation = .clear
        frontPath.fill()
        frontPath.stroke()
        context.restoreGraphicsState()
        frontPath.stroke()

        guard let mark else { return }
        let top = (front[0].y + front[1].y) / 2, bottom = (front[2].y + front[3].y) / 2
        let center = NSPoint(x: (front[0].x + front[1].x + front[2].x + front[3].x) / 4, y: (top + bottom) / 2)
        let shear = (front[0].x - front[3].x) / max(1, bottom - top)
        let w = mark.size.width, h = mark.size.height
        var proposed = NSRect(x: 0, y: 0, width: w, height: h)
        guard let glyph = mark.cgImage(forProposedRect: &proposed, context: context, hints: nil) else { return }
        // Sheared NSImage symbol drawing loses opacity, so draw the rasterized glyph through CG.
        let cg = context.cgContext
        cg.saveGState()
        cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -shear, d: 1, tx: center.x, ty: center.y))
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        cg.draw(glyph, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        cg.restoreGState()
    }
}

@MainActor
final class DropIndicatorView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.height / 2
        Palette.text.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: mid - 3.5, width: 7, height: 7))
        ring.lineWidth = 1.5
        ring.stroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 8, y: mid))
        line.line(to: NSPoint(x: bounds.width - 1, y: mid))
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.stroke()
    }
}

@MainActor
final class TextButton: HoverView {
    var action: (() -> Void)?
    private let label: NSTextField

    init(title: String) {
        label = NSTextField.sidebarLabel(title, font: .systemFont(ofSize: 10.5, weight: .medium), color: Palette.faint)
        super.init(frame: .zero)
        addSubview(label)
    }

    var fittingWidth: CGFloat { ceil(label.attributedStringValue.size().width) + 4 }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 15) / 2, width: bounds.width, height: 15)
        label.alignment = .right
    }

    override func hoverChanged() { label.textColor = isHovered ? Palette.text : Palette.faint }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }
}

@MainActor
final class FolderRowView: HoverView, NSTextFieldDelegate {
    let folder: SidebarFolder
    weak var sidebar: SidebarView?
    weak var list: TabListView?
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }
    var indent: CGFloat = 0 { didSet { if indent != oldValue { needsLayout = true } } }
    var folders: [(folder: SidebarFolder, depth: Int)] = []

    private let iconView = NSImageView()
    private let titleLabel = NSTextField.sidebarLabel(font: Typography.sidebarEmphasis)
    private let titleField = NSTextField()
    private var renaming = false
    private var shownExpanded: Bool?
    private var openProgress: CGFloat = 0
    private var openTicker: FrameTicker?

    init(folder: SidebarFolder) {
        self.folder = folder
        super.init(frame: .zero)
        iconView.imageScaling = .scaleNone
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.font = Typography.sidebarEmphasis
        titleField.textColor = Palette.text
        titleField.delegate = self
        titleField.isHidden = true
        titleField.cell?.isScrollable = true
        titleField.cell?.wraps = false
        for view in [iconView, titleLabel, titleField] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 5 + indent, y: (h - Metrics.iconFrame) / 2, width: Metrics.iconFrame, height: Metrics.iconFrame)
        let x = Metrics.titleX + indent
        titleLabel.frame = NSRect(x: x, y: (h - 17) / 2, width: max(0, bounds.width - x - 10), height: 17)
        titleField.frame = NSRect(x: x - 2, y: (h - 20) / 2, width: max(0, bounds.width - x - 6), height: 20)
    }

    func refresh() {
        titleLabel.stringValue = folder.name
        toolTip = folder.name
        let symbol = folder.symbol
        if let first = symbol.first, !first.isASCII {
            iconView.image = .symbol(symbol, size: 15)
            iconView.contentTintColor = nil
        } else {
            iconView.contentTintColor = Palette.text
            let target: CGFloat = folder.isExpanded ? 1 : 0
            if let shownExpanded, shownExpanded != folder.isExpanded, window != nil {
                animateOpen(to: target)
            } else if openTicker == nil {
                openProgress = target
                iconView.image = FolderIcon.image(progress: target, glyph: symbol, size: 18)
            }
        }
        shownExpanded = folder.isExpanded
        needsLayout = true
    }

    private func animateOpen(to target: CGFloat) {
        openTicker?.stop()
        let from = openProgress
        openTicker = Motion.tween(on: self, duration: 0.26) { [weak self] t in
            guard let self else { return }
            self.openProgress = from + (target - from) * t
            self.iconView.image = FolderIcon.image(progress: self.openProgress, glyph: self.folder.symbol, size: 18)
            if t >= 1 { self.openTicker = nil }
        }
    }

    func beginRename() {
        guard let window else { return }
        renaming = true
        titleField.stringValue = folder.name
        titleField.isHidden = false
        titleLabel.isHidden = true
        window.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    private func endRename(commit: Bool) {
        guard renaming else { return }
        renaming = false
        titleField.isHidden = true
        titleLabel.isHidden = false
        if commit {
            sidebar?.controller?.rename(folder, to: titleField.stringValue)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Re-focusing the field fires a stale end-editing while it is becoming first responder again;
        // genuine ends (Return, Tab, clicking away) have already moved focus off the field editor.
        if let editor = titleField.currentEditor(), window?.firstResponder === editor { return }
        endRename(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endRename(commit: false)
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isDropTarget ? Palette.tabActive.cgColor
            : isHovered && !renaming ? Palette.tabHover.cgColor : nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if renaming, let hit, hit === titleField || hit.isDescendant(of: titleField) { return hit }
        return hit == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !renaming else { return }
        if event.clickCount == 2 {
            sidebar?.controller?.toggle(folder)
            beginRename()
            return
        }
        let dragged = list?.trackDrag(of: .folder(folder), row: self, mouseDown: event) ?? false
        if !dragged { sidebar?.controller?.toggle(folder) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Rename...") { [weak self] in self?.beginRename() })
        menu.addItem(ClosureMenuItem("Change Icon...") { [weak self] in
            guard let self else { return }
            self.sidebar?.controller?.showIconPicker(for: self.folder, relativeTo: self.iconView)
        })
        menu.addItem(ClosureMenuItem("New Folder Inside") { [weak self] in
            guard let self else { return }
            self.sidebar?.controller?.newFolder(in: self.folder)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Delete Folder") { [weak self] in
            guard let self else { return }
            self.sidebar?.controller?.delete(self.folder)
        })
        return menu
    }
}

@MainActor
final class TabRowView: HoverView {
    let tab: BrowserTab
    weak var sidebar: SidebarView?
    weak var list: TabListView?
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true; updateCloseButton() } } }
    var indent: CGFloat = 0 { didSet { if indent != oldValue { needsLayout = true } } }
    var spaceNames: [String?] = []
    var folders: [(folder: SidebarFolder, depth: Int)] = []

    private let iconView = NSImageView()
    private let spinner = LoadingRing()
    private let titleLabel = NSTextField.sidebarLabel()
    private let closeButton = IconButton(symbol: "xmark", size: 11, toolTip: "Close Tab")

    init(tab: BrowserTab) {
        self.tab = tab
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        closeButton.isHidden = true
        closeButton.action = { [weak self] in
            guard let self else { return }
            self.sidebar?.close(self.tab)
        }
        for view in [iconView, spinner, titleLabel, closeButton] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let icon = Metrics.faviconSize
        iconView.frame = NSRect(x: 9 + indent, y: (h - icon) / 2, width: icon, height: icon)
        spinner.frame = iconView.frame
        let closeSize = Metrics.iconFrame
        closeButton.frame = NSRect(x: bounds.width - 6 - closeSize, y: (h - closeSize) / 2, width: closeSize, height: closeSize)
        let titleRight = closeButton.isHidden ? bounds.width - 10 : closeButton.frame.minX - 4
        let titleX = Metrics.titleX + indent
        titleLabel.frame = NSRect(x: titleX, y: (h - 17) / 2, width: max(0, titleRight - titleX), height: 17)
    }

    func refresh() {
        titleLabel.stringValue = tab.title
        toolTip = tab.url?.absoluteString
        if tab.isLoading {
            iconView.isHidden = true
            spinner.start(progress: CGFloat(tab.loadProgress))
        } else {
            if spinner.isAnimating {
                spinner.finish { [weak self] in self?.iconView.isHidden = false }
            } else {
                iconView.isHidden = false
            }
            if let favicon = tab.favicon {
                iconView.image = favicon
                iconView.contentTintColor = nil
            } else {
                iconView.image = .symbol("globe", size: 13)
                iconView.contentTintColor = Palette.icon
            }
        }
        needsLayout = true
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isActive ? Palette.tabActive.cgColor : (isHovered ? Palette.tabHover.cgColor : nil)
    }

    override func hoverChanged() { updateCloseButton() }

    private func updateCloseButton() {
        closeButton.isHidden = !isHovered || (tab.isPinned && !tab.isLoaded)
        closeButton.toolTip = tab.isPinned ? "Unload Tab" : "Close Tab"
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        Motion.press(self, scale: 0.98)
        sidebar?.select(tab)
        _ = list?.trackDrag(of: .tab(tab), row: self, mouseDown: event)
        Motion.release(self)
    }

    override func mouseUp(with event: NSEvent) { Motion.release(self) }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { sidebar?.close(tab) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let controller = sidebar?.controller
        menu.addItem(ClosureMenuItem("Add to Favorites") { [weak self] in
            guard let self else { return }
            controller?.addFavorite(self.tab)
        })
        if tab.isPinned {
            menu.addItem(ClosureMenuItem("Unpin Tab") { [weak self] in
                guard let self else { return }
                controller?.unpin(self.tab)
            })
            if tab.hasLeftPinnedURL {
                menu.addItem(ClosureMenuItem("Go to Pinned Page") { [weak self] in
                    guard let self else { return }
                    controller?.returnToPinnedURL(self.tab)
                })
            }
        } else {
            menu.addItem(ClosureMenuItem("Pin Tab") { [weak self] in
                guard let self else { return }
                controller?.pin(self.tab)
            })
        }
        let folderItem = NSMenuItem(title: tab.isPinned ? "Move to Folder" : "Add to Folder", action: nil, keyEquivalent: "")
        let folderMenu = NSMenu()
        for (folder, depth) in folders {
            let item = ClosureMenuItem(folder.name) { [weak self] in
                guard let self else { return }
                controller?.pin(self.tab, in: folder)
            }
            item.indentationLevel = depth
            item.image = .symbol(folder.symbol.isEmpty ? "folder" : folder.symbol, size: 12)
            folderMenu.addItem(item)
        }
        if !folders.isEmpty { folderMenu.addItem(.separator()) }
        folderMenu.addItem(ClosureMenuItem("New Folder") { [weak self] in
            guard let self else { return }
            controller?.newFolder(containing: self.tab)
        })
        folderItem.submenu = folderMenu
        menu.addItem(folderItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy Link") { [weak self] in
            guard let url = self?.tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        })
        let move = NSMenuItem(title: "Move to Space", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, name) in spaceNames.enumerated() {
            guard let name else { continue }
            submenu.addItem(ClosureMenuItem(name) { [weak self] in
                guard let self else { return }
                self.sidebar?.move(self.tab, toSpace: index)
            })
        }
        move.submenu = submenu
        move.isEnabled = !submenu.items.isEmpty
        menu.addItem(move)
        menu.addItem(.separator())
        if !tab.isPinned || tab.isLoaded {
            menu.addItem(ClosureMenuItem(tab.isPinned ? "Unload Tab" : "Close Tab") { [weak self] in
                guard let self else { return }
                self.sidebar?.close(self.tab)
            })
        }
        return menu
    }
}

@MainActor
final class NewTabRowView: HoverView {
    var onClick: (() -> Void)?
    var isHighlighted = false { didSet { if isHighlighted != oldValue { needsDisplay = true; updateColors() } } }
    private let plus = NSImageView()
    private let label = NSTextField.sidebarLabel("New Tab", color: Palette.subtle)

    override init(frame: NSRect) {
        super.init(frame: frame)
        plus.image = .symbol("plus", size: 12, weight: .medium)
        plus.imageScaling = .scaleNone
        addSubview(plus)
        addSubview(label)
        updateColors()
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        plus.frame = NSRect(x: 5, y: (h - Metrics.iconFrame) / 2, width: Metrics.iconFrame, height: Metrics.iconFrame)
        label.frame = NSRect(x: Metrics.titleX, y: (h - 17) / 2, width: bounds.width - Metrics.titleX - 10, height: 17)
    }

    private func updateColors() {
        let color = isHighlighted ? Palette.text : Palette.subtle
        plus.contentTintColor = color
        label.textColor = color
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHighlighted ? Palette.tabActive.cgColor : (isHovered ? Palette.tabHover.cgColor : nil)
    }

    override func mouseDown(with event: NSEvent) {
        Motion.press(self, scale: 0.97)
        onClick?()
    }

    override func mouseUp(with event: NSEvent) { Motion.release(self) }
}

@MainActor
final class URLPillView: HoverView {
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onControls: (() -> Void)?
    var url: URL? { didSet { if url != oldValue { updateText(); updateCopyVisibility() } } }
    var revealsCopy = false { didSet { if revealsCopy != oldValue { updateCopyVisibility() } } }

    private let label = NSTextField.sidebarLabel(color: Palette.pillText)
    private let searchIcon = NSImageView()
    private let copyButton = IconButton(symbol: "link", size: 13, toolTip: "Copy Link")
    let controlsButton = IconButton(symbol: "switch.2", size: 13, toolTip: "Site Controls")
    var controlsOpen = false { didSet { if controlsOpen != oldValue { updateCopyVisibility() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        searchIcon.image = .symbol("magnifyingglass", size: 12)
        searchIcon.contentTintColor = Palette.subtle
        copyButton.alphaValue = 0
        copyButton.action = { [weak self] in self?.onCopy?() }
        copyButton.wantsLayer = true
        controlsButton.setImage(Self.controlsGlyph)
        controlsButton.alphaValue = 0
        controlsButton.action = { [weak self] in self?.onControls?() }
        for view in [searchIcon, label, copyButton, controlsButton] as [NSView] { addSubview(view) }
        updateText()
    }

    // Two outlined toggles, drawn to match the line weight of the other pill icons.
    private static let controlsGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 14), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.3
            path.lineCapStyle = .round
            path.appendOval(in: NSRect(x: 2.25, y: 7.6, width: 3.6, height: 3.6))
            path.move(to: NSPoint(x: 7.3, y: 9.4))
            path.line(to: NSPoint(x: 13.75, y: 9.4))
            path.move(to: NSPoint(x: 2.25, y: 4.6))
            path.line(to: NSPoint(x: 8.7, y: 4.6))
            path.appendOval(in: NSRect(x: 10.15, y: 2.8, width: 3.6, height: 3.6))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func updateText() {
        if let url {
            label.stringValue = url.displayHost
            label.textColor = Palette.pillText
            searchIcon.isHidden = true
        } else {
            label.stringValue = "Search or Enter URL..."
            label.textColor = Palette.subtle
            searchIcon.isHidden = false
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        searchIcon.frame = NSRect(x: 12, y: (h - 14) / 2, width: 14, height: 14)
        controlsButton.frame = NSRect(x: bounds.width - 4 - 28, y: (h - 28) / 2, width: 28, height: 28)
        copyButton.frame = controlsButton.frame.offsetBy(dx: -28, dy: 0)
        let x: CGFloat = url == nil ? searchIcon.frame.maxX + 9 : 10
        label.frame = NSRect(x: x, y: (h - 17) / 2, width: copyButton.frame.minX - x - 4, height: 17)
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.surface.cgColor
    }

    private var copiedWork: DispatchWorkItem?

    func showCopied() {
        copiedWork?.cancel()
        swapCopySymbol("checkmark")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.copiedWork = nil
            self.swapCopySymbol("link")
            self.hoverChanged()
        }
        copiedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func swapCopySymbol(_ symbol: String) {
        copyButton.setSymbol(symbol, size: 13)
        Motion.crossfade(copyButton)
    }

    override func hoverChanged() { updateCopyVisibility() }

    private func updateCopyVisibility() {
        let visible = ((isHovered || revealsCopy) && url != nil) || copiedWork != nil || controlsOpen
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.12 : 0.16
            copyButton.animator().alphaValue = visible ? 1 : 0
            controlsButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if copyButton.alphaValue > 0, copyButton.frame.contains(point) {
            copyButton.mouseDown(with: event)
            return
        }
        if controlsButton.alphaValue > 0, controlsButton.frame.contains(point) {
            controlsButton.mouseDown(with: event)
            return
        }
        Motion.press(self, scale: 0.98)
        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        let point = convert(event.locationInWindow, from: nil)
        if copyButton.alphaValue > 0, copyButton.frame.contains(point) {
            copyButton.mouseUp(with: event)
        } else if controlsButton.alphaValue > 0, controlsButton.frame.contains(point) {
            controlsButton.mouseUp(with: event)
        }
    }
}

@MainActor
final class SpaceBarView: NSView {
    weak var sidebar: SidebarView?
    private var buttons: [IconButton] = []
    private let addButton = IconButton(symbol: "plus", size: 14, toolTip: "New...")
    private var addMenu: ActionMenu?
    private let downloadsButton = IconButton(symbol: "", size: 14, toolTip: "Downloads")
    private let downloadGlyph = DownloadGlyph()
    private var downloadsPanel: DownloadsPanel?
    private var panelClosedAt: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.action = { [weak self] in self?.toggleAddMenu() }
        addSubview(addButton)
        downloadsButton.action = { [weak self] in self?.toggleDownloads() }
        downloadsButton.addSubview(downloadGlyph)
        addSubview(downloadsButton)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged), name: .downloadsDidChange, object: nil)
        updateDownloads()
    }

    @objc private func downloadsChanged() { updateDownloads() }

    private func updateDownloads() {
        downloadGlyph.setProgress(DownloadCenter.shared.activeProgress)
    }

    func showDownloads() {
        guard downloadsPanel == nil, let root = sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? RootView }).first else { return }
        let panel = DownloadsPanel()
        panel.fillColor = root.toastFill
        panel.onClose = { [weak self, weak panel] in
            guard let self, self.downloadsPanel === panel else { return }
            self.downloadsPanel = nil
            self.panelClosedAt = CACurrentMediaTime()
        }
        downloadsPanel = panel
        panel.present(in: root, above: self, toggle: downloadsButton, width: bounds.width - 2 * Metrics.padding)
    }

    func toggleDownloads() {
        if let panel = downloadsPanel {
            panel.close()
            return
        }
        guard CACurrentMediaTime() - panelClosedAt > 0.25 else { return }
        showDownloads()
    }

    private func toggleAddMenu() {
        if let addMenu, addMenu.isShown || CACurrentMediaTime() - addMenu.closedAt < 0.25 {
            addMenu.close()
            return
        }
        let controller = sidebar?.controller
        let menu = ActionMenu(entries: [
            .item(ActionMenuItem(title: "New Space", symbol: "plus.square.on.square", shortcut: "\u{2318}N") { controller?.newSpace(nil) }),
            .item(ActionMenuItem(title: "New Folder", symbol: "folder", shortcut: nil) { controller?.newFolder() }),
            .separator,
            .item(ActionMenuItem(title: "New Tab", symbol: "plus.square", shortcut: "\u{2318}T") { controller?.newTab(nil) }),
        ])
        menu.onClose = { [weak self] in self?.addButton.rotateGlyph(to: 0, animated: true) }
        addMenu = menu
        addButton.rotateGlyph(to: .pi / 4, animated: true)
        menu.show(relativeTo: addButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func button(forSpace index: Int) -> NSView? {
        guard buttons.indices.contains(index), !buttons[index].isHidden, buttons[index].window != nil else { return nil }
        return buttons[index]
    }

    func update(spaces: [Space], activeIndex: Int) {
        while buttons.count > spaces.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < spaces.count {
            let button = IconButton(symbol: "circle", size: 15)
            addSubview(button)
            buttons.append(button)
        }
        for (index, space) in spaces.enumerated() {
            let button = buttons[index]
            if space.symbol.isEmpty {
                button.setSymbol("circle.fill", size: 5)
            } else {
                button.setSymbol(SpaceSymbols.displayName(space.symbol, active: index == activeIndex), size: Metrics.spaceBarIconSize)
            }
            button.tint = index == activeIndex ? Palette.text : Palette.faint
            button.toolTip = space.name
            button.action = { [weak self] in self?.sidebar?.selectSpace(index) }
            button.menu = spaceMenu(for: index, space: space, canDelete: spaces.count > 1)
        }
        needsLayout = true
    }

    private func spaceMenu(for index: Int, space: Space, canDelete: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Rename Space...") { [weak self] in self?.sidebar?.renameSpace(index) })
        let button = buttons[index]
        menu.addItem(ClosureMenuItem("Change Icon...") { [weak self, weak button] in
            guard let button else { return }
            self?.sidebar?.editIcon(index, relativeTo: button)
        })
        menu.addItem(ClosureMenuItem("Edit Theme...") { [weak self, weak button] in
            guard let button else { return }
            self?.sidebar?.editTheme(index, relativeTo: button)
        })
        menu.addItem(.separator())
        let delete = ClosureMenuItem("Delete Space") { [weak self] in self?.sidebar?.deleteSpace(index) }
        delete.isEnabled = canDelete
        menu.addItem(delete)
        return menu
    }

    override func layout() {
        super.layout()
        let size = Metrics.spaceButtonSize
        let y = bounds.height - Metrics.spaceBarBottomInset - size
        let total = CGFloat(buttons.count) * size + CGFloat(max(0, buttons.count - 1)) * Metrics.spaceButtonGap
        var x = (bounds.width - total) / 2
        for button in buttons {
            button.frame = NSRect(x: x, y: y, width: size, height: size)
            x += size + Metrics.spaceButtonGap
        }
        addButton.frame = NSRect(x: bounds.width - Metrics.padding - size, y: y, width: size, height: size)
        downloadsButton.frame = NSRect(x: Metrics.padding, y: y, width: size, height: size)
        downloadGlyph.frame = downloadsButton.bounds
    }
}

@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

@MainActor
final class SpaceHeaderView: HoverView {
    var onToggle: (() -> Void)?
    var menuProvider: ((NSView) -> NSMenu?)?

    private var symbolImage: NSImage?
    private var collapsed = false
    private let iconView = NSImageView()
    private let chevron = CALayer()
    private let titleLabel = NSTextField.sidebarLabel(font: Typography.sidebarEmphasis, color: Palette.subtle)
    private let moreButton = IconButton(symbol: "ellipsis", size: 13, toolTip: "Space Options")

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.imageScaling = .scaleNone
        iconView.contentTintColor = Palette.subtle
        moreButton.tint = Palette.subtle
        moreButton.isHidden = true
        moreButton.action = { [weak self] in self?.showMenu() }
        for view in [iconView, titleLabel, moreButton] as [NSView] { addSubview(view) }
        chevron.contentsGravity = .center
        chevron.isHidden = true
        layer?.addSublayer(chevron)
    }

    func configure(name: String, icon: NSImage?, collapsed: Bool) {
        titleLabel.stringValue = name
        symbolImage = icon
        let changed = collapsed != self.collapsed
        self.collapsed = collapsed
        updateIcon(animated: changed)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 5, y: (h - Metrics.iconFrame) / 2, width: Metrics.iconFrame, height: Metrics.iconFrame)
        moreButton.frame = NSRect(x: bounds.width - 4 - 28, y: (h - 28) / 2, width: 28, height: 28)
        let right = isHovered ? moreButton.frame.minX - 4 : bounds.width - 10
        titleLabel.frame = NSRect(x: Metrics.titleX, y: (h - 18) / 2, width: max(0, right - Metrics.titleX), height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.bounds = CGRect(origin: .zero, size: iconView.frame.size)
        chevron.position = CGPoint(x: iconView.frame.midX, y: iconView.frame.midY)
        CATransaction.commit()
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered ? Palette.tabHover.cgColor : nil
        chevron.contentsScale = window?.backingScaleFactor ?? 2
        let tint = NSColor(cgColor: Palette.subtle.cgColor) ?? Palette.subtle
        chevron.contents = NSImage.symbol("chevron.right", size: 12, weight: .semibold)?.tinted(tint)
    }

    override func hoverChanged() {
        moreButton.isHidden = !isHovered
        updateIcon(animated: false)
        needsLayout = true
    }

    private func updateIcon(animated: Bool) {
        iconView.image = symbolImage
        iconView.isHidden = isHovered
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.isHidden = !isHovered
        CATransaction.commit()
        Motion.rotate(chevron, to: collapsed ? 0 : .pi / 2, animated: animated && isHovered)
    }

    private func showMenu() {
        guard let menu = menuProvider?(moreButton) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY + 4), in: moreButton)
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(self) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, !moreButton.isHidden, hit === moreButton || hit.isDescendant(of: moreButton) { return hit }
        return hit == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onToggle?()
    }
}

// Arc-style downloads list floating above the space bar; no popover arrow.
@MainActor
class OverlayPanel: HoverView {
    var onClose: (() -> Void)?
    var fillColor: NSColor = Palette.ink { didSet { needsDisplay = true } }
    private var monitor: Any?
    private weak var anchor: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = Palette.hairline.cgColor
    }

    override func mouseDown(with event: NSEvent) {}

    // Clicks on `anchor` are left to its own action, so it can toggle the panel.
    func attach(to root: NSView, frame: NSRect, anchor: NSView, slideFrom offset: CGFloat) {
        self.anchor = anchor
        self.frame = frame
        root.addSubview(self)
        if !Motion.reduced, let layer {
            let move = CASpringAnimation(keyPath: "transform.translation.y")
            move.fromValue = offset
            move.toValue = 0
            move.stiffness = 300
            move.damping = 24
            move.duration = move.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.15
            layer.add(move, forKey: "in.move")
            layer.add(fade, forKey: "in.fade")
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let isKey = event.type == .keyDown
            // keyCode raises an exception on mouse events, so read it only for key events.
            let keyCode: UInt16 = isKey ? event.keyCode : 0
            let location = event.locationInWindow
            let windowNumber = event.windowNumber
            let swallow = MainActor.assumeIsolated {
                self?.handleOutsideEvent(isKey: isKey, keyCode: keyCode, location: location, windowNumber: windowNumber) ?? false
            }
            return swallow ? nil : event
        }
    }

    private func handleOutsideEvent(isKey: Bool, keyCode: UInt16, location: NSPoint, windowNumber: Int) -> Bool {
        if isKey {
            if keyCode == 53 { close(); return true }
            return false
        }
        guard windowNumber == window?.windowNumber else { close(); return false }
        if bounds.contains(convert(location, from: nil)) { return false }
        if let anchor, anchor.bounds.contains(anchor.convert(location, from: nil)) { return false }
        close()
        return false
    }

    func willClose() {}

    func close() {
        guard superview != nil, monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        willClose()
        onClose?()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduced ? 0 : 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview()
        })
    }
}

@MainActor
final class DownloadsPanel: OverlayPanel {
    private static let rowHeight: CGFloat = 56
    private static let inset: CGFloat = 6
    private static let maxRows = 6

    private let scrollView = NSScrollView()
    private let list = FlippedView()
    private var rows: [String: DownloadRow] = [:]
    private var refreshTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.documentView = list
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.cornerRadius = 10
        scrollView.contentView.layer?.cornerCurve = .continuous
        addSubview(scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged), name: .downloadsDidChange, object: nil)
    }

    // `bar` positions the panel; clicks on `toggle` are left to its own action.
    func present(in root: NSView, above bar: NSView, toggle: NSView, width: CGFloat) {
        let height = reload(width: width)
        let barRect = bar.convert(bar.bounds, to: root)
        attach(to: root, frame: NSRect(x: barRect.minX + (barRect.width - width) / 2, y: barRect.minY - 2 - height, width: width, height: height),
               anchor: toggle, slideFrom: 8)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rows.values.forEach { $0.refresh() } }
        }
    }

    override func willClose() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func downloadsChanged() {
        guard superview != nil else { return }
        let bottom = frame.maxY
        let height = reload(width: bounds.width)
        frame = NSRect(x: frame.minX, y: bottom - height, width: frame.width, height: height)
    }

    @discardableResult
    private func reload(width panelWidth: CGFloat) -> CGFloat {
        let downloads = DownloadCenter.shared.downloads
        var next: [String: DownloadRow] = [:]
        for download in downloads {
            let row = rows[download.identifier] ?? DownloadRow(download: download)
            row.panel = self
            row.refresh()
            next[download.identifier] = row
        }
        for (id, row) in rows where next[id] == nil { row.removeFromSuperview() }
        rows = next
        let width = panelWidth - 2 * Self.inset
        var y: CGFloat = 0
        for download in downloads {
            guard let row = rows[download.identifier] else { continue }
            if row.superview !== list { list.addSubview(row) }
            row.frame = NSRect(x: 0, y: y, width: width, height: Self.rowHeight)
            y += Self.rowHeight
        }
        list.frame = NSRect(x: 0, y: 0, width: width, height: y)
        let visible = min(y, CGFloat(Self.maxRows) * Self.rowHeight)
        scrollView.frame = NSRect(x: Self.inset, y: Self.inset, width: width, height: visible)
        if downloads.isEmpty {
            let empty = rows.isEmpty ? emptyLabel : nil
            empty?.frame = NSRect(x: 0, y: 18, width: panelWidth, height: 18)
            return 54
        }
        emptyLabel.removeFromSuperview()
        return visible + 2 * Self.inset
    }

    private lazy var emptyLabel: NSTextField = {
        let label = NSTextField.sidebarLabel("No Downloads", font: .systemFont(ofSize: 13, weight: .medium), color: Palette.faint)
        label.alignment = .center
        addSubview(label)
        return label
    }()
}

@MainActor
final class DownloadRow: HoverView, NSDraggingSource {
    weak var panel: DownloadsPanel?
    let download: Download

    private static var thumbnails: [URL: NSImage] = [:]
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private let thumbnail = ThumbnailView()
    private let nameLabel = NSTextField.sidebarLabel(font: .systemFont(ofSize: 14, weight: .medium), color: Palette.text)
    private let detailLabel = NSTextField.sidebarLabel(font: .systemFont(ofSize: 12.5), color: Palette.faint)
    private let ring = LoadingRing()
    private var thumbnailURL: URL?
    private var mouseDownEvent: NSEvent?

    init(download: Download) {
        self.download = download
        super.init(frame: .zero)
        ring.spins = false
        ring.lineWidth = 2
        ring.color = Palette.text
        for view in [thumbnail, ring, nameLabel, detailLabel] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        thumbnail.frame = NSRect(x: 8, y: (h - 40) / 2, width: 40, height: 40)
        ring.frame = thumbnail.frame.insetBy(dx: 8, dy: 8)
        let x = thumbnail.frame.maxX + 12
        nameLabel.frame = NSRect(x: x, y: h / 2 - 19, width: bounds.width - x - 8, height: 18)
        detailLabel.frame = NSRect(x: x, y: h / 2 + 1, width: bounds.width - x - 8, height: 17)
    }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered ? Palette.tabHover.cgColor : nil
    }

    func refresh() {
        nameLabel.stringValue = download.fileName
        detailLabel.stringValue = detailText
        toolTip = download.fileURL?.path
        let running = download.state == .inProgress
        if running {
            let progress = download.totalBytes > 0 ? CGFloat(download.receivedBytes) / CGFloat(download.totalBytes) : 0
            ring.start(progress: progress)
        } else if ring.isAnimating {
            ring.finish {}
        }
        thumbnail.alphaValue = running || !download.fileExists ? 0.45 : 1
        loadThumbnail()
    }

    private var detailText: String {
        let bytes = Self.byteFormatter
        switch download.state {
        case .inProgress:
            let received = bytes.string(fromByteCount: download.receivedBytes)
            let amount = download.totalBytes > 0 ? "\(received) of \(bytes.string(fromByteCount: download.totalBytes))" : received
            return download.isPaused ? "Paused \u{00B7} \(amount)" : amount
        case .complete:
            guard download.fileExists else { return "Deleted" }
            let date = download.endDate ?? download.startDate
            if Date().timeIntervalSince(date) < 60 { return "Just now" }
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        case .cancelled:
            return "Cancelled"
        case .interrupted:
            return download.canResume ? "Failed \u{00B7} Click to retry" : "Failed"
        @unknown default:
            return ""
        }
    }

    private func loadThumbnail() {
        guard let url = download.fileURL else {
            thumbnail.setIcon(NSWorkspace.shared.icon(for: .data))
            return
        }
        let done = download.state == .complete && download.fileExists
        if let cached = Self.thumbnails[url], done {
            thumbnail.setThumbnail(cached)
            return
        }
        if thumbnailURL != url || thumbnail.image == nil {
            thumbnail.setIcon(NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data))
        }
        guard done, thumbnailURL != url else { return }
        thumbnailURL = url
        let scale = window?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation, representation.type == .thumbnail else { return }
            let image = representation.nsImage
            DispatchQueue.main.async { [weak self] in
                Self.thumbnails[url] = image
                guard let self, self.download.fileURL == url else { return }
                self.thumbnail.setThumbnail(image)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        Motion.press(self, scale: 0.97)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let url = download.fileURL, download.state == .complete, download.fileExists else { return }
        let a = start.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 4 else { return }
        mouseDownEvent = nil
        Motion.release(self)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(convert(thumbnail.frame, to: self), contents: thumbnail.image)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        guard mouseDownEvent != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        mouseDownEvent = nil
        activate()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    private func activate() {
        switch download.state {
        case .complete where download.fileExists:
            panel?.close()
            download.open()
        case .inProgress:
            if download.isPaused { download.resume() } else { download.pause() }
        case .interrupted where download.canResume:
            download.resume()
        default:
            break
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let download = self.download
        let available = download.state == .complete && download.fileExists
        if available {
            menu.addItem(ClosureMenuItem("Open") { download.open() })
            menu.addItem(ClosureMenuItem("Show in Finder") { download.showInFinder() })
            menu.addItem(ClosureMenuItem("Copy") {
                guard let url = download.fileURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            })
            menu.addItem(.separator())
        }
        if download.state == .inProgress {
            if download.isPaused {
                menu.addItem(ClosureMenuItem("Resume") { download.resume() })
            } else {
                menu.addItem(ClosureMenuItem("Pause") { download.pause() })
            }
            menu.addItem(ClosureMenuItem("Cancel") { download.cancel() })
            menu.addItem(.separator())
        }
        if download.state == .interrupted && download.canResume {
            menu.addItem(ClosureMenuItem("Retry") { download.resume() })
            menu.addItem(.separator())
        }
        if let source = download.sourceURL {
            menu.addItem(ClosureMenuItem("Copy Download Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source.absoluteString, forType: .string)
            })
        }
        if download.state != .inProgress {
            menu.addItem(ClosureMenuItem("Remove from List") { download.remove() })
        }
        return menu
    }
}

// File previews fill a rounded square like Arc's; generic file icons stay unclipped.
@MainActor
final class ThumbnailView: NSView {
    private(set) var image: NSImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setIcon(_ icon: NSImage) {
        apply(icon, gravity: .resizeAspect, clip: false)
    }

    func setThumbnail(_ thumbnail: NSImage) {
        apply(thumbnail, gravity: .resizeAspectFill, clip: true)
    }

    private func apply(_ newImage: NSImage, gravity: CALayerContentsGravity, clip: Bool) {
        guard newImage !== image else { return }
        image = newImage
        guard let layer else { return }
        layer.contentsGravity = gravity
        layer.masksToBounds = clip
        layer.borderWidth = clip ? 0.5 : 0
        layer.borderColor = Palette.hairline.cgColor
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.contents = newImage.layerContents(forContentsScale: layer.contentsScale)
    }
}

// Arrow-to-line glyph drawn in layers: the arrow drops in a loop while downloading and the line fills with progress.
@MainActor
final class DownloadGlyph: NSView {
    var color: NSColor = Palette.icon { didSet { needsDisplay = true } }

    private let arrow = CAShapeLayer()
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private(set) var isDownloading = false
    private var finishWork: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [arrow, track, fill] {
            shape.fillColor = nil
            shape.lineWidth = 1.35
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
        fill.strokeEnd = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: c.x, y: c.y - 4.8))
        arrowPath.addLine(to: CGPoint(x: c.x, y: c.y + 1.6))
        arrowPath.move(to: CGPoint(x: c.x - 3.2, y: c.y - 1.6))
        arrowPath.addLine(to: CGPoint(x: c.x, y: c.y + 1.6))
        arrowPath.addLine(to: CGPoint(x: c.x + 3.2, y: c.y - 1.6))
        arrow.frame = bounds
        arrow.path = arrowPath
        let line = CGMutablePath()
        line.move(to: CGPoint(x: c.x - 4.8, y: c.y + 4.8))
        line.addLine(to: CGPoint(x: c.x + 4.8, y: c.y + 4.8))
        for shape in [track, fill] {
            shape.frame = bounds
            shape.path = line
        }
        CATransaction.commit()
    }

    override func updateLayer() {
        let cg = color.cgColor
        arrow.strokeColor = cg
        fill.strokeColor = cg
        track.strokeColor = isDownloading ? cg.copy(alpha: cg.alpha * 0.3) : cg
    }

    func setProgress(_ progress: CGFloat?) {
        guard let progress else {
            if isDownloading { finish() }
            return
        }
        finishWork?.cancel()
        finishWork = nil
        if !isDownloading {
            isDownloading = true
            setFill(0, animated: false)
            needsDisplay = true
            startDropping()
        }
        setFill(max(0.06, min(progress, 1)), animated: true)
    }

    private func startDropping() {
        guard !Motion.reduced else { return }
        let move = CAKeyframeAnimation(keyPath: "transform.translation.y")
        move.values = [0, 3, -3, 0, 0]
        move.keyTimes = [0, 0.35, 0.351, 0.65, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0, 0, 1, 1]
        fade.keyTimes = [0, 0.35, 0.351, 0.65, 1]
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = 1.2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arrow.add(group, forKey: "drop")
    }

    private func finish() {
        guard finishWork == nil else { return }
        setFill(1, animated: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finishWork = nil
            self.isDownloading = false
            self.arrow.removeAnimation(forKey: "drop")
            self.needsDisplay = true
            self.setFill(0, animated: false)
            if !Motion.reduced {
                let pop = CASpringAnimation(keyPath: "transform.translation.y")
                pop.fromValue = -3
                pop.toValue = 0
                pop.stiffness = 400
                pop.damping = 14
                pop.duration = pop.settlingDuration
                self.arrow.add(pop, forKey: "land")
            }
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func setFill(_ value: CGFloat, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        fill.strokeEnd = value
        CATransaction.commit()
    }
}

@MainActor
final class FavoritesGridView: NSView {
    static let cellHeight: CGFloat = 46
    static let gap: CGFloat = 8
    static let zoneHeight: CGFloat = 96

    weak var sidebar: SidebarView?
    weak var list: TabListView?
    private(set) var favorites: [BrowserTab] = []
    private var active: BrowserTab?
    private var cells: [ObjectIdentifier: FavoriteCellView] = [:]
    private let dropZone = FavoritesDropZoneView()
    private(set) var showsDropZone = false
    private var dragged: BrowserTab?
    private var placeholder: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dropZone.alphaValue = 0
        dropZone.isHidden = true
        addSubview(dropZone)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(favorites: [BrowserTab], active: BrowserTab?, animated: Bool) {
        self.favorites = favorites
        self.active = active
        var live = Set<ObjectIdentifier>()
        for tab in favorites {
            let id = ObjectIdentifier(tab)
            live.insert(id)
            let cell = cells[id] ?? {
                let cell = FavoriteCellView(tab: tab)
                cell.sidebar = sidebar
                cell.list = list
                cell.alphaValue = animated ? 0 : 1
                addSubview(cell)
                cells[id] = cell
                return cell
            }()
            cell.isActive = tab === active
            cell.refresh()
        }
        var gone: [FavoriteCellView] = []
        for (id, cell) in cells where !live.contains(id) {
            gone.append(cell)
            cells[id] = nil
        }
        if !favorites.isEmpty, showsDropZone { setDropZoneVisible(false) }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                gone.forEach { $0.animator().alphaValue = 0 }
                cells.values.forEach { $0.animator().alphaValue = 1 }
            } completionHandler: {
                MainActor.assumeIsolated { gone.forEach { $0.removeFromSuperview() } }
            }
        } else {
            gone.forEach { $0.removeFromSuperview() }
        }
        needsLayout = true
    }

    func refresh(_ tab: BrowserTab) {
        cells[ObjectIdentifier(tab)]?.refresh()
    }

    func contains(_ tab: BrowserTab) -> Bool { favorites.contains { $0 === tab } }

    private var slots: [BrowserTab?] {
        guard let placeholder else { return favorites }
        var result: [BrowserTab?] = favorites.filter { $0 !== dragged }
        result.insert(nil, at: min(placeholder, result.count))
        return result
    }

    // One row up to four, then whichever of three or four columns leaves fewer gaps.
    static func columns(for count: Int) -> Int {
        guard count > 4 else { return max(count, 1) }
        let gaps3 = (3 - count % 3) % 3
        let gaps4 = (4 - count % 4) % 4
        return gaps3 < gaps4 ? 3 : 4
    }

    var contentHeight: CGFloat {
        if favorites.isEmpty { return showsDropZone ? Self.zoneHeight : 0 }
        let count = slots.count
        let rows = (count + Self.columns(for: count) - 1) / Self.columns(for: count)
        return CGFloat(rows) * Self.cellHeight + CGFloat(max(0, rows - 1)) * Self.gap
    }

    private func frames(count: Int, width: CGFloat) -> [NSRect] {
        let columns = Self.columns(for: count)
        let cellWidth = (width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)
        return (0..<count).map { index in
            NSRect(x: CGFloat(index % columns) * (cellWidth + Self.gap), y: CGFloat(index / columns) * (Self.cellHeight + Self.gap),
                   width: cellWidth, height: Self.cellHeight)
        }
    }

    override func layout() {
        super.layout()
        dropZone.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.zoneHeight)
        let slots = slots
        let frames = frames(count: slots.count, width: bounds.width)
        for (index, tab) in slots.enumerated() {
            guard let tab, let cell = cells[ObjectIdentifier(tab)] else { continue }
            cell.isHidden = false
            if cell.frame == .zero {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    cell.frame = frames[index]
                }
            } else {
                cell.frame = frames[index]
            }
        }
        if placeholder != nil, let dragged { cells[ObjectIdentifier(dragged)]?.isHidden = true }
    }

    func dropIndex(at point: NSPoint, dragging tab: BrowserTab) -> Int {
        let others = favorites.filter { $0 !== tab }.count
        let count = others + 1
        let columns = Self.columns(for: count)
        let rows = (count + columns - 1) / columns
        let cellWidth = (bounds.width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)
        let column = min(max(0, Int(point.x / (cellWidth + Self.gap))), columns - 1)
        let row = min(max(0, Int(point.y / (Self.cellHeight + Self.gap))), rows - 1)
        return min(row * columns + column, others)
    }

    func setDragPreview(dragging tab: BrowserTab?, index: Int?) {
        guard dragged !== tab || placeholder != index else { return }
        dragged = tab
        placeholder = index
        needsLayout = true
        sidebar?.relayout(animated: true)
    }

    func setDropZoneVisible(_ visible: Bool) {
        guard showsDropZone != visible else { return }
        showsDropZone = visible
        dropZone.isHidden = false
        needsLayout = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.2 : 0.15
            dropZone.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.showsDropZone else { return }
                self.dropZone.isHidden = true
            }
        }
        sidebar?.relayout(animated: true)
    }

    func setDropZoneHighlighted(_ highlighted: Bool) { dropZone.isHighlighted = highlighted }
}

@MainActor
final class FavoriteCellView: HoverView {
    let tab: BrowserTab
    weak var sidebar: SidebarView?
    weak var list: TabListView?
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }

    private let iconView = NSImageView()
    private let spinner = LoadingRing()
    private weak var accentSource: NSImage?
    private var accent: NSColor?

    init(tab: BrowserTab) {
        self.tab = tab
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let size: CGFloat = 16
        iconView.frame = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        spinner.frame = iconView.frame
    }

    func refresh() {
        toolTip = tab.title
        if tab.isLoading {
            iconView.isHidden = true
            spinner.start(progress: CGFloat(tab.loadProgress))
        } else {
            if spinner.isAnimating {
                spinner.finish { [weak self] in self?.iconView.isHidden = false }
            } else {
                iconView.isHidden = false
            }
            if let favicon = tab.favicon {
                iconView.image = favicon
                iconView.contentTintColor = nil
            } else {
                iconView.image = .symbol("globe", size: 15)
                iconView.contentTintColor = Palette.icon
            }
        }
        if let favicon = tab.favicon, favicon !== accentSource {
            accentSource = favicon
            accent = favicon.accentColor
            needsDisplay = true
        }
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        let fill: NSColor
        let border: NSColor
        if let accent {
            fill = Palette.favoriteActive(accent: accent)
            border = Palette.favoriteActiveBorder(accent: accent)
        } else {
            fill = Palette.favoriteActive
            border = Palette.favoriteActiveBorder
        }
        layer?.backgroundColor = (isActive ? fill : (isHovered ? Palette.favoriteHover : Palette.favorite)).cgColor
        layer?.borderWidth = isActive ? 1.75 : 0
        layer?.borderColor = border.cgColor
    }

    override func hoverChanged() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        Motion.press(self, scale: 0.96)
        sidebar?.select(tab)
        _ = list?.trackDrag(of: .tab(tab), row: self, mouseDown: event)
        Motion.release(self)
    }

    override func mouseUp(with event: NSEvent) { Motion.release(self) }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { sidebar?.close(tab) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let controller = sidebar?.controller
        menu.addItem(ClosureMenuItem("Remove from Favorites") { [weak self] in
            guard let self else { return }
            controller?.unpin(self.tab)
        })
        if tab.hasLeftPinnedURL {
            menu.addItem(ClosureMenuItem("Go to Favorited Page") { [weak self] in
                guard let self else { return }
                controller?.returnToPinnedURL(self.tab)
            })
        }
        menu.addItem(ClosureMenuItem("Copy Link") { [weak self] in
            guard let url = self?.tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        })
        if tab.isLoaded {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Unload Tab") { [weak self] in
                guard let self else { return }
                self.sidebar?.close(self.tab)
            })
        }
        return menu
    }
}

@MainActor
final class FavoritesDropZoneView: NSView {
    var isHighlighted = false { didSet { if isHighlighted != oldValue { needsDisplay = true } } }
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drag to add Favorites")
    private let detailLabel = NSTextField(wrappingLabelWithString: "Favorites keep your most used sites and apps close")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        iconView.image = .symbol("star.circle.fill", size: 16)
        iconView.contentTintColor = Palette.icon
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.alignment = .center
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = Palette.subtle
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2
        for view in [iconView, titleLabel, detailLabel] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let width = bounds.width - 32
        iconView.frame = NSRect(x: (bounds.width - 18) / 2, y: 14, width: 18, height: 18)
        titleLabel.frame = NSRect(x: 16, y: 38, width: width, height: 17)
        detailLabel.preferredMaxLayoutWidth = width
        detailLabel.frame = NSRect(x: 16, y: 57, width: width, height: 30)
    }

    override func updateLayer() {
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.favorite.cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = (isHighlighted ? Palette.favoriteActiveBorder : Palette.hairline).cgColor
    }
}

@MainActor
final class DragGhostView: NSView {
    private let snapshot = NSImageView()
    private let icon = NSImageView()
    let rowSize: NSSize
    private(set) var isCompact = false

    init(row: NSView, favicon: NSImage?) {
        rowSize = row.bounds.size
        super.init(frame: NSRect(origin: .zero, size: row.bounds.size))
        wantsLayer = true
        layer?.cornerRadius = Metrics.rowRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = cg(Palette.tabActive)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        if let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds) {
            row.cacheDisplay(in: row.bounds, to: rep)
            let image = NSImage(size: row.bounds.size)
            image.addRepresentation(rep)
            snapshot.image = image
        }
        snapshot.imageScaling = .scaleNone
        snapshot.frame = bounds
        snapshot.autoresizingMask = [.width, .height]
        icon.image = favicon ?? .symbol("globe", size: 15)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.isHidden = true
        addSubview(snapshot)
        addSubview(icon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setCompact(_ compact: Bool) {
        guard compact != isCompact else { return }
        isCompact = compact
        snapshot.isHidden = compact
        icon.isHidden = !compact
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }
}


@MainActor
final class SiteControlsPanel: OverlayPanel {
    static let width: CGFloat = 260
    private static let inset: CGFloat = 12

    private weak var controller: BrowserWindowController?
    private var zoomLabel: NSTextField?
    private var resetZoomButton: TextButton?
    private var contentHeight: CGFloat = 0

    init(controller: BrowserWindowController) {
        self.controller = controller
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present(in root: NSView, below pill: NSView, anchor: NSView) {
        let anchorRect = anchor.convert(anchor.bounds, to: root)
        let pillRect = pill.convert(pill.bounds, to: root)
        let x = min(max(8, anchorRect.midX - Self.width / 2), root.bounds.width - Self.width - 8)
        attach(to: root, frame: NSRect(x: x, y: pillRect.maxY + 6, width: Self.width, height: contentHeight), anchor: anchor, slideFrom: -8)
    }

    private var tab: Tab? { controller?.activeTab?.tab }
    private var url: URL? { controller?.activeTab?.url }

    private func build() {
        let inner = Self.width - 2 * Self.inset
        var y = Self.inset

        let actions: [(String, String, () -> Void)] = [
            ("square.and.arrow.up", "Share", { [weak self] in self?.share() }),
            ("camera", "Capture Page", { [weak self] in self?.controller?.captureScreenshot(); self?.close() }),
            ("text.magnifyingglass", "Find on Page", { [weak self] in self?.close(); self?.controller?.performFind(nil) }),
            ("hammer", "Developer Tools", { [weak self] in self?.close(); self?.controller?.toggleDevTools(nil) }),
        ]
        let gap: CGFloat = 8
        let tile = (inner - gap * CGFloat(actions.count - 1)) / CGFloat(actions.count)
        for (index, action) in actions.enumerated() {
            let button = PanelTileButton(symbol: action.0, toolTip: action.1, action: action.2)
            button.frame = NSRect(x: Self.inset + CGFloat(index) * (tile + gap), y: y, width: tile, height: 40)
            addSubview(button)
            shareAnchor = shareAnchor ?? button
        }
        y += 40 + 14

        y = addHeader("Zoom", y: y)
        let zoomRow = FlippedView(frame: NSRect(x: Self.inset, y: y, width: inner, height: 32))
        let minus = PanelTileButton(symbol: "minus", toolTip: "Zoom Out") { [weak self] in self?.controller?.zoomOut(nil); self?.updateZoom() }
        let plus = PanelTileButton(symbol: "plus", toolTip: "Zoom In") { [weak self] in self?.controller?.zoomIn(nil); self?.updateZoom() }
        minus.frame = NSRect(x: 0, y: 0, width: 44, height: 32)
        plus.frame = NSRect(x: inner - 44, y: 0, width: 44, height: 32)
        let label = NSTextField.sidebarLabel("100%", font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium), color: Palette.text)
        label.alignment = .center
        label.frame = NSRect(x: 44, y: 7, width: inner - 88, height: 18)
        let reset = TextButton(title: "Reset")
        reset.action = { [weak self] in self?.controller?.actualSize(nil); self?.updateZoom() }
        for view in [minus, plus, label, reset] as [NSView] { zoomRow.addSubview(view) }
        addSubview(zoomRow)
        zoomLabel = label
        resetZoomButton = reset
        y += 32 + 14

        y = addHeader("Extensions", y: y)
        let extensionTiles: [(String, String, () -> Void)] = [
            ("puzzlepiece.extension", "Manage Extensions", { [weak self] in self?.close(); self?.controller?.showExtensions(nil) }),
            ("plus", "Get Extensions", { [weak self] in self?.close(); self?.controller?.openExtensionStore() }),
        ]
        for (index, item) in extensionTiles.enumerated() {
            let button = PanelTileButton(symbol: item.0, toolTip: item.1, action: item.2)
            button.frame = NSRect(x: Self.inset + CGFloat(index) * (tile + gap), y: y, width: tile, height: 36)
            addSubview(button)
        }
        y += 36 + 14

        y = addHeader("Settings", y: y)
        let host = url?.host ?? "this site"
        let rows: [(String, String, String, () -> Void)] = [
            ("slider.horizontal.3", "Site Settings", "Permissions for \(host)", { [weak self] in self?.close(); self?.controller?.openSiteSettings() }),
            ("trash", "Clear Browsing Data", "History, cookies and cache", { [weak self] in self?.close(); self?.controller?.clearBrowsingData(nil) }),
        ]
        for row in rows {
            let view = PanelSettingRow(symbol: row.0, title: row.1, detail: row.2, action: row.3)
            view.frame = NSRect(x: Self.inset - 6, y: y, width: inner + 12, height: 44)
            addSubview(view)
            y += 44
        }
        y += 6

        let divider = HairlineView(inset: 0)
        divider.frame = NSRect(x: Self.inset, y: y, width: inner, height: 1)
        addSubview(divider)
        y += 1 + 10

        let security = SecurityPill(url: url) { [weak self] in self?.close(); self?.controller?.openSiteSettings() }
        security.frame = NSRect(x: Self.inset, y: y, width: security.fittingWidth, height: 30)
        addSubview(security)
        let more = PanelTileButton(symbol: "ellipsis", toolTip: "More") { [weak self] in self?.showMoreMenu() }
        more.isCircular = true
        more.frame = NSRect(x: Self.width - Self.inset - 30, y: y, width: 30, height: 30)
        addSubview(more)
        moreButton = more
        y += 30 + Self.inset

        contentHeight = y
        updateZoom()
    }

    private weak var shareAnchor: NSView?
    private weak var moreButton: NSView?

    private func addHeader(_ title: String, y: CGFloat) -> CGFloat {
        let label = NSTextField.sidebarLabel(title, font: .systemFont(ofSize: 12, weight: .semibold), color: Palette.subtle)
        label.frame = NSRect(x: Self.inset + 2, y: y, width: Self.width - 2 * Self.inset, height: 16)
        addSubview(label)
        return y + 16 + 8
    }

    private func updateZoom() {
        // Older ArgonCore builds lack zoomPercent; show the controls without a value.
        let percent = tab.flatMap { $0.responds(to: #selector(getter: Tab.zoomPercent)) ? $0.zoomPercent : nil } ?? 100
        zoomLabel?.stringValue = tab?.responds(to: #selector(getter: Tab.zoomPercent)) == false ? "Zoom" : "\(percent)%"
        guard let zoomLabel, let resetZoomButton else { return }
        resetZoomButton.isHidden = percent == 100
        let width = resetZoomButton.fittingWidth
        resetZoomButton.frame = NSRect(x: zoomLabel.frame.midX + 26, y: 7, width: width, height: 18)
    }

    private func share() {
        guard let url, let shareAnchor else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: shareAnchor.bounds, of: shareAnchor, preferredEdge: .minY)
    }

    private func showMoreMenu() {
        guard let moreButton else { return }
        let controller = controller
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Copy URL as Markdown") { controller?.copyURLAsMarkdown(nil) })
        menu.addItem(ClosureMenuItem("Hard Reload") { controller?.hardReload(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Print...") { controller?.printPage(nil) })
        menu.addItem(ClosureMenuItem("Save Page As...") { controller?.savePage(nil) })
        menu.addItem(ClosureMenuItem("View Source") { controller?.viewSource(nil) })
        menu.addItem(ClosureMenuItem("JavaScript Console") { controller?.showConsole(nil) })
        close()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY + 4), in: moreButton)
    }
}

@MainActor
final class PanelTileButton: HoverView {
    private let imageView = NSImageView()
    private let action: () -> Void
    var isCircular = false { didSet { needsDisplay = true } }

    init(symbol: String, toolTip: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        self.toolTip = toolTip
        imageView.image = .symbol(symbol, size: 15)
        imageView.contentTintColor = Palette.text
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func updateLayer() {
        layer?.cornerRadius = isCircular ? bounds.height / 2 : 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = (isHovered ? Palette.favoriteHover : Palette.favorite).cgColor
    }

    override func hoverChanged() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.94) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

@MainActor
final class PanelSettingRow: HoverView {
    private let iconBackground = NSView()
    private let imageView = NSImageView()
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let action: () -> Void

    init(symbol: String, title: String, detail: String, action: @escaping () -> Void) {
        self.action = action
        titleLabel = .sidebarLabel(title, font: .systemFont(ofSize: 13, weight: .medium), color: Palette.text)
        detailLabel = .sidebarLabel(detail, font: .systemFont(ofSize: 11.5), color: Palette.subtle)
        super.init(frame: .zero)
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 15
        imageView.image = .symbol(symbol, size: 13)
        imageView.contentTintColor = Palette.text
        imageView.imageScaling = .scaleNone
        for view in [iconBackground, imageView, titleLabel, detailLabel] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        iconBackground.frame = NSRect(x: 6, y: (bounds.height - 30) / 2, width: 30, height: 30)
        imageView.frame = iconBackground.frame
        let x = iconBackground.frame.maxX + 10
        titleLabel.frame = NSRect(x: x, y: 5, width: bounds.width - x - 6, height: 17)
        detailLabel.frame = NSRect(x: x, y: 23, width: bounds.width - x - 6, height: 15)
    }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovered ? Palette.favorite.cgColor : nil
        iconBackground.layer?.backgroundColor = Palette.favoriteHover.cgColor
    }

    override func hoverChanged() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.98) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

// Reflects the scheme only; certificate errors are not reported by the core yet.
@MainActor
final class SecurityPill: HoverView {
    private let imageView = NSImageView()
    private let label: NSTextField
    private let action: () -> Void

    init(url: URL?, action: @escaping () -> Void) {
        self.action = action
        let scheme = url?.scheme ?? ""
        let (symbol, text): (String, String) = switch scheme {
        case "https": ("lock.fill", "Secure")
        case "http": ("exclamationmark.triangle.fill", "Not Secure")
        case "file": ("doc.fill", "Local File")
        case "chrome", "about": ("gearshape.fill", "Argon Page")
        default: ("info.circle.fill", "Site Info")
        }
        label = .sidebarLabel(text, font: .systemFont(ofSize: 13, weight: .medium), color: Palette.text)
        super.init(frame: .zero)
        toolTip = "Site Settings"
        imageView.image = .symbol(symbol, size: 11)
        imageView.contentTintColor = scheme == "http" ? .systemOrange : Palette.text
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var fittingWidth: CGFloat { 10 + 14 + 6 + ceil(label.intrinsicContentSize.width) + 12 }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 10, y: (bounds.height - 14) / 2, width: 14, height: 14)
        label.frame = NSRect(x: 30, y: (bounds.height - 17) / 2, width: bounds.width - 36, height: 17)
    }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = (isHovered ? Palette.favoriteHover : Palette.favorite).cgColor
    }

    override func hoverChanged() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) { Motion.press(self, scale: 0.96) }

    override func mouseUp(with event: NSEvent) {
        Motion.release(self)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
