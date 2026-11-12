import AppKit

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, BrowserTabObserver {
    private(set) var spaces: [Space]
    private(set) var activeIndex: Int
    private let root = RootView()
    private var displayedTab: BrowserTab?
    private var findBar: FindBarView?
    private var recentlyClosed: [(url: URL, space: ObjectIdentifier)] = []
    private var enteredFullscreenForContent = false
    private var saveTask: Task<Void, Never>?

    var activeSpace: Space { spaces[activeIndex] }
    var activeTab: BrowserTab? { activeSpace.activeTab }
    private var sidebar: SidebarView { root.sidebar }

    init(spaces: [Space], activeIndex: Int) {
        self.spaces = spaces
        self.activeIndex = min(max(0, activeIndex), spaces.count - 1)
        let window = BrowserWindow()
        super.init(window: window)
        window.delegate = self
        root.sidebarHidden = !Preferences.showSidebarOnLaunch
        root.setSidebarOnRight(Preferences.sidebarOnRight, animated: false)
        window.contentView = root
        window.setFrameAutosaveName("ArgonBrowserWindow")
        if !window.setFrameUsingName("ArgonBrowserWindow") { window.center() }
        sidebar.controller = self
        root.resizeHandle.onDrag = { [weak self] x in self?.resizeSidebar(to: x) }
        root.resizeHandle.onEnd = { [weak self] in self?.endSidebarResize() }
        root.sidebarWidth = CGFloat(UserDefaults.standard.double(forKey: "ArgonSidebarWidth")).nonZero ?? Metrics.sidebarWidth
        for space in spaces {
            for tab in space.allTabs { tab.observer = self }
        }
        showActiveTab()
        refreshSidebar()
        applyFrame(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged(_:)), name: .downloadsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarSideChanged(_:)), name: .sidebarSideDidChange, object: nil)
    }

    @objc private func sidebarSideChanged(_ notification: Notification) {
        root.setSidebarOnRight(Preferences.sidebarOnRight, animated: true)
    }

    @objc private func downloadsChanged(_ notification: Notification) {
        guard window?.isMainWindow == true || NSApp.mainWindow == nil,
              let event = notification.userInfo?["event"] as? DownloadEvent else { return }
        switch event {
        case .finished(let download):
            root.showToast("Downloaded \(Self.shortName(download.fileName))", icon: "arrow.down.circle",
                           action: ToastAction(symbol: "magnifyingglass", toolTip: "Show in Finder") { _ in download.showInFinder() },
                           duration: 4)
        case .failed(let download):
            root.showToast("Couldn't download \(Self.shortName(download.fileName))", icon: "exclamationmark.circle", duration: 4)
        case .started, .changed:
            break
        }
    }

    private static func shortName(_ name: String) -> String {
        guard name.count > 28 else { return name }
        let ext = (name as NSString).pathExtension
        let keep = 28 - ext.count - 2
        return String(name.prefix(max(keep, 8))) + "\u{2026}" + (ext.isEmpty ? "" : "." + ext)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tabs

    func select(_ tab: BrowserTab) {
        guard let index = spaceIndex(of: tab) else { return }
        if index != activeIndex { switchToSpace(index) }
        dismissCommandBar()
        activeSpace.activeTab = tab
        showActiveTab()
        refreshSidebar()
        scheduleSave()
    }

    @discardableResult
    func openTab(_ url: URL?, in space: Space? = nil, foreground: Bool = true) -> BrowserTab {
        let space = space ?? activeSpace
        let tab = BrowserTab(url: url)
        tab.observer = self
        space.tabs.insert(tab, at: 0)
        if foreground {
            select(tab)
        } else {
            refreshSidebar()
            scheduleSave()
        }
        return tab
    }

    func close(_ tab: BrowserTab) {
        guard let index = spaceIndex(of: tab) else { return }
        let space = spaces[index]
        if let url = tab.url, url.scheme != "about" {
            recentlyClosed.append((url, ObjectIdentifier(space)))
            if recentlyClosed.count > 25 { recentlyClosed.removeFirst() }
        }
        if !tab.isPinned { space.tabs.removeAll { $0 === tab } }
        if space.activeTab === tab {
            space.activeTab = space.allTabs.filter { $0 !== tab && ($0.isLoaded || !$0.isPinned) }
                .max { $0.lastActive < $1.lastActive }
        }
        if displayedTab === tab {
            root.card.show(nil)
            displayedTab = nil
        }
        if tab.isPinned { tab.unload() } else { tab.close() }
        if index == activeIndex { showActiveTab() }
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func move(_ tab: BrowserTab, toSpace index: Int) {
        guard spaces.indices.contains(index) else { return }
        let url = tab.url
        if tab.isPinned, let source = spaceIndex(of: tab) {
            spaces[source].removeFromPinned(tab)
            tab.unpin()
            spaces[source].tabs.insert(tab, at: 0)
        }
        close(tab)
        openTab(url, in: spaces[index], foreground: false)
    }

    private func showActiveTab() {
        let tab = activeSpace.activeTab
        if displayedTab !== tab {
            closeFindBar(focusPage: false)
            enterAutoPictureInPicture(leaving: displayedTab)
            displayedTab?.captureSnapshot()
            displayedTab?.tab?.isVisible = false
            displayedTab = tab
            exitAutoPictureInPicture(returningTo: tab)
        }
        guard let tab, let profile = activeSpace.profile else {
            root.card.show(nil)
            sidebar.updateToolbar(for: nil)
            return
        }
        tab.lastActive = Date()
        let page = tab.materialize(in: profile)
        root.card.show(page.view)
        page.isVisible = true
        if root.commandBar == nil { page.focus() }
        sidebar.updateToolbar(for: tab)
    }

    // Favorites are shared by every space on the same profile, so the active space wins.
    private func spaceIndex(of tab: BrowserTab) -> Int? {
        if activeSpace.allTabs.contains(where: { $0 === tab }) { return activeIndex }
        return spaces.firstIndex { space in space.allTabs.contains { $0 === tab } }
    }

    private func refreshSidebar(animated: Bool = false) {
        sidebar.update(spaces: spaces, activeIndex: activeIndex, commandBarOpen: root.commandBar?.mode == .newTab, animated: animated)
        updateNowPlaying()
    }

    // MARK: Now playing

    private var nowPlaying: BrowserTab?
    private var dismissedPlayer: BrowserTab?

    func browserTabDidChangeMedia(_ tab: BrowserTab) {
        guard let page = tab.tab else { return }
        if tab === dismissedPlayer {
            guard page.isPlayingMedia else {
                dismissedPlayerPaused = true
                return
            }
            guard dismissedPlayerPaused else { return }
            dismissedPlayer = nil
        }
        if page.hasMedia, page.isPlayingMedia {
            nowPlaying = tab
        } else if tab === nowPlaying, !page.hasMedia {
            nowPlaying = nil
        }
        updateNowPlaying()
    }

    private var dismissedPlayerPaused = false

    private func updateNowPlaying() {
        if let tab = nowPlaying, tab.tab?.hasMedia != true || spaceIndex(of: tab) == nil {
            nowPlaying = nil
        }
        sidebar.updateNowPlaying(nowPlaying === activeTab ? nil : nowPlaying)
    }

    func dismissNowPlaying() {
        guard let tab = nowPlaying else { return }
        tab.tab?.pauseMedia()
        dismissedPlayer = tab
        dismissedPlayerPaused = false
        nowPlaying = nil
        updateNowPlaying()
    }

    // MARK: Spaces

    func selectSpace(_ index: Int) {
        guard spaces.indices.contains(index), index != activeIndex else { return }
        let direction = index > activeIndex ? 1 : -1
        sidebar.prepareSpaceChange()
        switchToSpace(index)
        showActiveTab()
        refreshSidebar()
        sidebar.animateSpaceChange(direction: direction)
        scheduleSave()
    }

    // MARK: Interactive space swipe

    var spaceSwipeRange: (active: Int, count: Int) { (activeIndex, spaces.count) }

    func previewSpace(_ index: Int) {
        guard spaces.indices.contains(index) else { return }
        sidebar.update(spaces: spaces, activeIndex: index, commandBarOpen: false, preview: true)
    }

    func previewSpaceColor(toward index: Int, progress: CGFloat) {
        guard spaces.indices.contains(index) else { return }
        let from = activeSpace.frameColor.usingColorSpace(.sRGB) ?? activeSpace.frameColor
        let to = spaces[index].frameColor.usingColorSpace(.sRGB) ?? spaces[index].frameColor
        let t = min(max(progress, 0), 1)
        let opacity = activeSpace.opacity + (spaces[index].opacity - activeSpace.opacity) * Double(t)
        root.previewFrameColor(from.blended(withFraction: t, of: to) ?? from, opacity: CGFloat(opacity))
    }

    func finishSpaceSwipe(to index: Int?) {
        if let index, spaces.indices.contains(index), index != activeIndex {
            switchToSpace(index)
            showActiveTab()
            scheduleSave()
        } else {
            applyFrame()
        }
        refreshSidebar()
    }

    // A video playing in the tab you leave moves to picture in picture, and
    // comes back when you return. PiP the user started themselves is left alone.
    private func enterAutoPictureInPicture(leaving tab: BrowserTab?) {
        guard Preferences.autoPictureInPicture, let tab, let page = tab.tab, page.isPlayingMedia,
              page.canEnterPictureInPicture, !page.isInPictureInPicture, page.autoPictureInPictureAllowed else { return }
        page.togglePictureInPicture()
        tab.autoEnteredPictureInPicture = true
    }

    private func exitAutoPictureInPicture(returningTo tab: BrowserTab?) {
        guard let tab, tab.autoEnteredPictureInPicture else { return }
        tab.autoEnteredPictureInPicture = false
        if let page = tab.tab, page.isInPictureInPicture { page.togglePictureInPicture() }
    }

    func switchSpace(by delta: Int) {
        selectSpace(min(max(0, activeIndex + delta), spaces.count - 1))
    }

    private func switchToSpace(_ index: Int) {
        enterAutoPictureInPicture(leaving: displayedTab)
        displayedTab?.tab?.isVisible = false
        displayedTab = nil
        root.card.show(nil)
        activeIndex = index
        applyFrame()
    }

    @objc func newSpace(_ sender: Any?) {
        addSpace { [weak self] space in
            guard let self, let index = self.spaces.firstIndex(where: { $0 === space }) else { return }
            self.renameSpace(index)
        }
    }

    func addSpace(completion: (@MainActor (Space) -> Void)? = nil) {
        let used = Set(spaces.map(\.symbol))
        let symbol = SpaceSymbols.all.first { !used.contains($0) } ?? "circle"
        let hues = [0.62, 0.08, 0.38, 0.76, 0.9, 0.5, 0.14, 0.0]
        let hue = hues[spaces.count % hues.count]
        let identifier = "Space " + UUID().uuidString.prefix(8)
        let name = "Space \(spaces.count + 1)"
        Application.shared.loadProfile(identifier: identifier) { [weak self] profile in
            guard let self, let profile else { return }
            let space = Space(name: name, symbol: symbol, hue: hue, profileIdentifier: identifier)
            space.profile = profile
            self.spaces.append(space)
            self.selectSpace(self.spaces.count - 1)
            completion?(space)
        }
    }

    func setName(_ name: String, forSpace index: Int) {
        guard spaces.indices.contains(index), !name.isEmpty, spaces[index].name != name else { return }
        spaces[index].name = name
        refreshSidebar()
        scheduleSave()
    }

    func togglePinnedSection() {
        activeSpace.pinnedCollapsed.toggle()
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func renameSpace(_ index: Int) {
        guard spaces.indices.contains(index), let window else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Space"
        alert.informativeText = "Each space has its own profile: cookies, logins, history and extensions stay separate."
        let field = NSTextField(string: spaces[index].name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let self else { return }
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, self.spaces.indices.contains(index) else { return }
                self.spaces[index].name = name
                self.refreshSidebar()
                self.scheduleSave()
            }
        }
    }

    func deleteSpace(_ index: Int, presentingIn sheetWindow: NSWindow? = nil, completion: (@MainActor () -> Void)? = nil) {
        guard spaces.count > 1, spaces.indices.contains(index), let window = sheetWindow ?? window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(spaces[index].name)?"
        alert.informativeText = "Its tabs will close. The space's profile data stays on disk."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let self, self.spaces.indices.contains(index) else { return }
                let space = self.spaces[index]
                if index == self.activeIndex {
                    self.switchToSpace(index == 0 ? 1 : index - 1)
                }
                let sharesProfile = self.spaces.contains { $0 !== space && $0.profileIdentifier == space.profileIdentifier }
                (sharesProfile ? space.pinnedTabs + space.tabs : space.allTabs).forEach { $0.close() }
                self.spaces.remove(at: index)
                if self.activeIndex > index { self.activeIndex -= 1 }
                self.applyFrame()
                self.showActiveTab()
                self.refreshSidebar()
                self.scheduleSave()
                completion?()
            }
        }
    }

    func setSymbol(_ symbol: String, forSpace index: Int) {
        guard spaces.indices.contains(index) else { return }
        spaces[index].symbol = symbol
        refreshSidebar()
        scheduleSave()
    }

    func setColor(_ color: NSColor?, forSpace index: Int) {
        guard spaces.indices.contains(index) else { return }
        spaces[index].customColor = color
        if index == activeIndex { applyFrame() }
        root.commandBar?.frameColor = activeSpace.frameColor
        scheduleSave()
    }

    func setOpacity(_ opacity: Double, forSpace index: Int) {
        guard spaces.indices.contains(index) else { return }
        let opacity = min(max(opacity, Palette.minimumOpacity), 1)
        guard spaces[index].opacity != opacity else { return }
        spaces[index].opacity = opacity
        if index == activeIndex { applyFrame(animated: false) }
        scheduleSave()
    }

    private func applyFrame(animated: Bool = true) {
        root.setFrameColor(activeSpace.frameColor, opacity: CGFloat(activeSpace.opacity), animated: animated)
    }

    func showThemeEditor(forSpace index: Int, relativeTo view: NSView) {
        guard spaces.indices.contains(index) else { return }
        if index != activeIndex { selectSpace(index) }
        let editor = ThemeEditorController(color: spaces[index].customColor, opacity: spaces[index].opacity)
        editor.onChange = { [weak self] color in self?.setColor(color, forSpace: index) }
        editor.onOpacityChange = { [weak self] opacity in self?.setOpacity(opacity, forSpace: index) }
        let popover = NSPopover()
        popover.contentViewController = editor
        popover.behavior = .transient
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    func showIconPicker(forSpace index: Int, relativeTo view: NSView) {
        guard spaces.indices.contains(index) else { return }
        let picker = IconPickerController(selected: spaces[index].symbol)
        picker.onPick = { [weak self] symbol in self?.setSymbol(symbol, forSpace: index) }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    // MARK: Pinned tabs and folders

    func pin(_ tab: BrowserTab, in folder: SidebarFolder? = nil) {
        guard let index = spaceIndex(of: tab) else { return }
        let space = spaces[index]
        if space.removeFavorite(tab) {
        } else if tab.isPinned {
            space.removeFromPinned(tab)
        } else {
            space.tabs.removeAll { $0 === tab }
            tab.pin()
        }
        if let folder {
            folder.children.append(.tab(tab))
            folder.isExpanded = true
        } else {
            space.pinned.append(.tab(tab))
        }
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func drop(_ item: SidebarItem, at target: SidebarDrop) {
        let space = activeSpace
        let source = space.pinnedLocation(of: item)
        var todayIndex: Int?
        if let source {
            space.removePinned(parent: source.parent, index: source.index)
        } else if case .tab(let tab) = item, space.removeFavorite(tab) {
        } else if case .tab(let tab) = item, let index = space.tabs.firstIndex(where: { $0 === tab }) {
            space.tabs.remove(at: index)
            todayIndex = index
        } else {
            return
        }
        switch target {
        case .pinned(let parent, var index):
            if let source, source.parent === parent, source.index < index { index -= 1 }
            if case .tab(let tab) = item, !tab.isPinned { tab.pin() }
            space.insertPinned(item, parent: parent, index: index)
        case .into(let folder):
            if case .tab(let tab) = item, !tab.isPinned { tab.pin() }
            folder.children.append(item)
            folder.isExpanded = true
        case .today(var index):
            guard case .tab(let tab) = item else {
                space.pinned.append(item)
                break
            }
            if let todayIndex, todayIndex < index { index -= 1 }
            if tab.isPinned { tab.unpin() }
            space.tabs.insert(tab, at: min(max(0, index), space.tabs.count))
        }
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func unpin(_ tab: BrowserTab) {
        guard let index = spaceIndex(of: tab), tab.isPinned else { return }
        let space = spaces[index]
        if !space.removeFavorite(tab) { space.removeFromPinned(tab) }
        tab.unpin()
        if tab.isLoaded {
            space.tabs.insert(tab, at: 0)
        } else {
            if space.activeTab === tab { space.activeTab = nil }
            tab.close()
        }
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func addFavorite(_ tab: BrowserTab, at index: Int = .max) {
        guard let spaceIndex = spaceIndex(of: tab) else { return }
        let space = spaces[spaceIndex]
        if space.removeFavorite(tab) {
        } else if tab.isPinned {
            space.removeFromPinned(tab)
        } else {
            space.tabs.removeAll { $0 === tab }
            tab.pin()
        }
        var favorites = space.favorites
        favorites.insert(tab, at: min(max(0, index), favorites.count))
        space.favorites = favorites
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func returnToPinnedURL(_ tab: BrowserTab) {
        tab.returnToPinnedURL()
    }

    func replacePinnedURL(_ tab: BrowserTab) {
        guard tab.isPinned, tab.url != nil else { return }
        tab.pin()
        refreshSidebar()
        scheduleSave()
    }

    func newFolder(in parent: SidebarFolder? = nil, containing tab: BrowserTab? = nil) {
        let folder = SidebarFolder(name: "New Folder")
        if let parent {
            parent.children.append(.folder(folder))
            parent.isExpanded = true
        } else {
            activeSpace.pinned.append(.folder(folder))
        }
        if let tab { pin(tab, in: folder) }
        refreshSidebar(animated: true)
        sidebar.beginRenaming(folder)
        scheduleSave()
    }

    func rename(_ folder: SidebarFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { folder.name = trimmed }
        refreshSidebar()
        scheduleSave()
    }

    func toggle(_ folder: SidebarFolder) {
        folder.isExpanded.toggle()
        refreshSidebar(animated: true)
        scheduleSave()
    }

    func showIconPicker(for folder: SidebarFolder, relativeTo view: NSView) {
        let picker = IconPickerController(selected: folder.symbol)
        picker.onPick = { [weak self] symbol in
            folder.symbol = symbol
            self?.refreshSidebar()
            self?.scheduleSave()
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
    }

    func delete(_ folder: SidebarFolder) {
        guard let space = spaces.first(where: { $0.contains(folder) }), let window else { return }
        let tabs = SidebarItem.folder(folder).tabs
        let remove = { [weak self] in
            guard let self else { return }
            space.removeFolder(folder)
            for tab in tabs {
                if space.activeTab === tab { space.activeTab = nil }
                if self.displayedTab === tab {
                    self.root.card.show(nil)
                    self.displayedTab = nil
                }
                tab.close()
            }
            if space === self.activeSpace { self.showActiveTab() }
            self.refreshSidebar(animated: true)
            self.scheduleSave()
        }
        guard !tabs.isEmpty else {
            remove()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(folder.name)\"?"
        alert.informativeText = tabs.count == 1 ? "The pinned tab inside it will be removed." : "The \(tabs.count) pinned tabs inside it will be removed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { remove() }
            }
        }
    }

    func clearTodayTabs() {
        let space = activeSpace
        let tabs = space.tabs
        guard !tabs.isEmpty else { return }
        space.tabs.removeAll()
        if let active = space.activeTab, tabs.contains(where: { $0 === active }) {
            space.activeTab = space.pinnedTabs.filter(\.isLoaded).max { $0.lastActive < $1.lastActive }
        }
        if let shown = displayedTab, tabs.contains(where: { $0 === shown }) {
            root.card.show(nil)
            displayedTab = nil
        }
        tabs.forEach { $0.close() }
        showActiveTab()
        refreshSidebar(animated: true)
        scheduleSave()
    }

    // MARK: Command bar

    private func showCommandBar(_ mode: CommandBarView.Mode) {
        let text = mode == .editURL ? (activeTab?.url?.absoluteString ?? "") : ""
        let bar = CommandBarView(mode: mode, initialText: text, frameColor: activeSpace.frameColor)
        bar.controller = self
        root.commandBar = bar
        refreshSidebar()
        bar.activate()
    }

    func dismissCommandBar() {
        guard root.commandBar != nil else { return }
        root.commandBar = nil
        refreshSidebar()
        activeTab?.tab?.focus()
    }

    func commandBar(_ bar: CommandBarView, open url: URL) {
        let mode = bar.mode
        dismissCommandBar()
        if mode == .editURL, let tab = activeTab, let page = tab.tab {
            page.load(url)
            page.focus()
        } else if let existing = openTab(matching: url) {
            select(existing)
        } else {
            openTab(url)
        }
    }

    func commandBar(_ bar: CommandBarView, switchTo tab: BrowserTab) {
        dismissCommandBar()
        select(tab)
    }

    func tabsInRecentOrder() -> [(tab: BrowserTab, space: Space)] {
        var seen = Set<ObjectIdentifier>()
        return spaces.flatMap { space in space.allTabs.map { (tab: $0, space: space) } }
            .filter { seen.insert(ObjectIdentifier($0.tab)).inserted }
            .sorted { $0.tab.lastActive > $1.tab.lastActive }
    }

    private func openTab(matching url: URL) -> BrowserTab? {
        func key(_ url: URL?) -> String? {
            guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            components.fragment = nil
            if components.scheme == "http" { components.scheme = "https" }
            return components.string
        }
        let target = key(url)
        return activeSpace.allTabs.first { key($0.url) == target }
    }

    // MARK: Actions (menu and toolbar)

    @objc func newTab(_ sender: Any?) {
        if root.commandBar?.mode == .newTab { dismissCommandBar() } else { showCommandBar(.newTab) }
    }

    @objc func openLocation(_ sender: Any?) {
        showCommandBar(activeTab == nil ? .newTab : .editURL)
    }

    @objc func closeTab(_ sender: Any?) {
        if root.commandBar != nil {
            dismissCommandBar()
        } else if let tab = activeTab {
            close(tab)
        }
    }

    @objc func goBack(_ sender: Any?) { activeTab?.tab?.goBack() }
    @objc func goForward(_ sender: Any?) { activeTab?.tab?.goForward() }

    @objc func reloadPage(_ sender: Any?) {
        guard let page = activeTab?.tab else { return }
        if page.isLoading { page.stop() } else { page.reload() }
    }

    @objc func toggleDevTools(_ sender: Any?) {
        activeTab?.tab?.toggleDevTools()
    }

    @objc func showConsole(_ sender: Any?) { activeTab?.tab?.showDevToolsConsole() }
    @objc func inspectElement(_ sender: Any?) { activeTab?.tab?.inspectElement() }

    @objc func viewSource(_ sender: Any?) {
        guard let url = activeTab?.url, url.scheme != "view-source",
              let source = URL(string: "view-source:" + url.absoluteString) else { return }
        openTab(source)
    }

    @objc func hardReload(_ sender: Any?) { activeTab?.tab?.reloadBypassingCache() }
    @objc func stopLoading(_ sender: Any?) { activeTab?.tab?.stop() }
    @objc func zoomIn(_ sender: Any?) { activeTab?.tab?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { activeTab?.tab?.zoomOut() }
    @objc func actualSize(_ sender: Any?) { activeTab?.tab?.resetZoom() }
    @objc func printPage(_ sender: Any?) { activeTab?.tab?.print() }
    @objc func printUsingSystemDialog(_ sender: Any?) { activeTab?.tab?.printUsingSystemDialog() }
    @objc func savePage(_ sender: Any?) { activeTab?.tab?.savePage() }

    @objc func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { self.openTab(url) }
        }
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        guard let (url, spaceID) = recentlyClosed.popLast() else { NSSound.beep(); return }
        let space = spaces.first { ObjectIdentifier($0) == spaceID } ?? activeSpace
        if space !== activeSpace, let index = spaces.firstIndex(where: { $0 === space }) { selectSpace(index) }
        openTab(url, in: space)
    }

    @objc func togglePin(_ sender: Any?) {
        guard let tab = activeTab else { return }
        if tab.isPinned { unpin(tab) } else { pin(tab) }
    }

    @objc func clearUnpinnedTabs(_ sender: Any?) { clearTodayTabs() }

    @objc func copyURLAsMarkdown(_ sender: Any?) {
        guard let tab = activeTab, let url = tab.url else { return }
        let title = tab.title.isEmpty ? url.absoluteString : tab.title
        let escaped = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(escaped)](\(url.absoluteString))", forType: .string)
        root.showToast("Copied URL as Markdown")
    }

    @objc func showHistory(_ sender: Any?) { openChromePage("history") }
    @objc func showExtensions(_ sender: Any?) { openChromePage("extensions") }
    @objc func clearBrowsingData(_ sender: Any?) { openChromePage("settings", path: "/clearBrowserData") }
    @objc func toggleDownloads(_ sender: Any?) { sidebar.toggleDownloads() }
    @objc func showSiteControls(_ sender: Any?) { sidebar.toggleSiteControls() }

    func openExtensionStore() {
        openTab(URL(string: "https://chromewebstore.google.com"))
    }

    func openSiteSettings() {
        guard let url = activeTab?.url, let scheme = url.scheme, let host = url.host else {
            openChromePage("settings", path: "/content")
            return
        }
        let origin = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        let encoded = origin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? origin
        openChromePage("settings", path: "/content/siteDetails?site=\(encoded)")
    }

    func captureScreenshot() {
        guard let browserTab = activeTab, let page = browserTab.tab else { return }
        guard page.responds(to: #selector(Tab.captureVisibleContent(completion:))) else {
            root.showToast("Capture needs a newer ArgonCore build", icon: "exclamationmark.circle")
            return
        }
        page.captureVisibleContent { [weak self] image in
            guard let self else { return }
            guard let image, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                self.root.showToast("Couldn't Capture Page", icon: "exclamationmark.circle")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            let name = (browserTab.url?.displayHost ?? "Page") + " " + Self.timestamp() + ".png"
            self.root.showToast("Copied Screenshot", icon: "camera", action: ToastAction(symbol: "square.and.arrow.down", toolTip: "Save to \(FileManager.default.displayName(atPath: Preferences.screenshotFolder.path))") { _ in
                let folder = Preferences.screenshotFolder
                let file = folder.appendingPathComponent(name)
                guard (try? png.write(to: file)) != nil else { return }
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }, duration: 4)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    // With a profile, the page opens in a space that uses it, switching spaces if needed.
    func openChromePage(_ host: String, path: String = "", profile identifier: String?) {
        if let identifier, activeSpace.profileIdentifier != identifier,
           let index = spaces.firstIndex(where: { $0.profileIdentifier == identifier }) {
            selectSpace(index)
        }
        openChromePage(host, path: path)
        window?.makeKeyAndOrderFront(nil)
    }

    private func openChromePage(_ host: String, path: String = "") {
        if let existing = activeSpace.allTabs.first(where: { $0.url?.scheme == "chrome" && $0.url?.host == host }) {
            select(existing)
            if !path.isEmpty, let url = URL(string: "chrome://\(host)\(path)") { existing.tab?.load(url) }
        } else if let url = URL(string: "chrome://\(host)\(path)") {
            openTab(url)
        }
    }

    // MARK: Find in page

    @objc func performFind(_ sender: Any?) {
        guard let page = activeTab?.tab else { return }
        let bar = findBar ?? makeFindBar()
        if bar.text.isEmpty { bar.text = page.findText }
        bar.focus()
        if !bar.text.isEmpty { page.find(bar.text, forward: true, caseSensitive: false) }
    }

    @objc func findNext(_ sender: Any?) { stepFind(forward: true) }
    @objc func findPrevious(_ sender: Any?) { stepFind(forward: false) }

    private func stepFind(forward: Bool) {
        guard let page = activeTab?.tab else { return }
        let bar = findBar ?? makeFindBar()
        if bar.text.isEmpty { bar.text = page.findText }
        guard !bar.text.isEmpty else { bar.focus(); return }
        page.find(bar.text, forward: forward, caseSensitive: false)
    }

    private func makeFindBar() -> FindBarView {
        let bar = FindBarView()
        let card = root.card
        let size = FindBarView.size
        bar.frame = NSRect(x: card.bounds.width - size.width - 12, y: card.bounds.height - size.height - 12,
                           width: size.width, height: size.height)
        bar.autoresizingMask = [.minXMargin, .minYMargin]
        bar.onChange = { [weak self] text in
            self?.activeTab?.tab?.find(text, forward: true, caseSensitive: false)
        }
        bar.onNext = { [weak self] in self?.stepFind(forward: true) }
        bar.onPrevious = { [weak self] in self?.stepFind(forward: false) }
        bar.onClose = { [weak self] in self?.closeFindBar(focusPage: true) }
        card.addSubview(bar)
        findBar = bar
        return bar
    }

    private func closeFindBar(focusPage: Bool) {
        guard let bar = findBar else { return }
        bar.removeFromSuperview()
        findBar = nil
        displayedTab?.tab?.stopFinding(clearSelection: false)
        if focusPage { displayedTab?.tab?.focus() }
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    static var current: BrowserWindowController? {
        let windows = [NSApp.mainWindow, NSApp.keyWindow].compactMap { $0 } + NSApp.windows
        return windows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
    }

    func showToast(_ toast: ToastView) {
        root.showToast(toast)
    }

    func showQuitHint(duration: TimeInterval) {
        root.showToast("Press \u{2318}Q again to quit", duration: duration)
    }

    // Links from other apps follow the link rules, then open in Little Argon or the active space.
    func open(_ urls: [URL]) {
        var openedHere = false
        for url in urls {
            if let rule = LinkRouter.rule(for: url), let space = spaces.first(where: { $0.id == rule.spaceID }) {
                openTab(url, in: space)
                openedHere = true
            } else if LinkRouter.destination == .littleArgon, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let profile = activeSpace.profile {
                LittleWindowController.open(url, space: activeSpace, profile: profile, browser: self)
            } else {
                openTab(url)
                openedHere = true
            }
        }
        if openedHere { bringToFront() }
    }

    func bringToFront() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var allSpaces: [Space] { spaces }

    func liveSpace(_ space: Space) -> Space? {
        if spaces.contains(where: { $0 === space }) { return space }
        return spaces.first { $0.profileIdentifier == space.profileIdentifier }
    }

    func adopt(_ tab: BrowserTab, into space: Space) {
        tab.observer = self
        space.tabs.insert(tab, at: 0)
        select(tab)
        bringToFront()
    }

    func adoptOpened(_ newTab: Tab, in space: Space, disposition: TabOpenDisposition) {
        guard let space = liveSpace(space) else {
            newTab.close()
            return
        }
        insertOpened(newTab, in: space, at: 0, disposition: disposition)
        if disposition != .background { bringToFront() }
    }

    func offerRule(for url: URL, space: Space) {
        guard let host = LinkRouter.displayHost(of: url), !LinkRouter.hasRule(forHost: host) else { return }
        let actions = [
            ToastAction(title: "Not Now") { _ in },
            ToastAction(title: "Always", isPrimary: true) { [weak self] _ in
                LinkRouter.addRule(pattern: host, spaceID: space.id)
                self?.root.showToast("\(host) links will open in \(space.name)", icon: "arrow.triangle.branch", duration: 3)
            },
        ]
        root.showToast(ToastView(message: "Always open \(host) in \(space.name)?", icon: "arrow.triangle.branch",
                                 actions: actions, duration: 12))
    }

    @objc func copyURL(_ sender: Any?) {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        sidebar.showCopiedFeedback()
        root.showToast("Copied Current URL", action: ToastAction(symbol: "square.and.arrow.up", toolTip: "Share") { anchor in
            NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        })
    }

    @objc func toggleSidebarPanel(_ sender: Any?) {
        root.sidebarHidden.toggle()
    }

    @objc func selectSpaceFromMenu(_ sender: NSMenuItem) { selectSpace(sender.tag) }

    @objc func selectTabFromMenu(_ sender: NSMenuItem) {
        let tabs = activeSpace.visibleTabs
        guard !tabs.isEmpty else { return }
        select(sender.tag >= 8 ? tabs[tabs.count - 1] : tabs[min(sender.tag, tabs.count - 1)])
    }

    @objc func nextTab(_ sender: Any?) { cycleTab(by: 1) }
    @objc func previousTab(_ sender: Any?) { cycleTab(by: -1) }

    private var tabSwitcher: TabSwitcher?

    @objc func nextRecentTab(_ sender: Any?) { switchRecentTab(forward: true) }
    @objc func previousRecentTab(_ sender: Any?) { switchRecentTab(forward: false) }

    private func switchRecentTab(forward: Bool) {
        if let tabSwitcher {
            tabSwitcher.step(forward: forward)
            return
        }
        activeTab?.captureSnapshot()
        let switcher = TabSwitcher(tabs: recentTabs(), forward: forward, host: root, fill: root.toastFill) { [weak self] tab in
            self?.tabSwitcher = nil
            if let tab, tab !== self?.activeTab { self?.select(tab) }
        }
        tabSwitcher = switcher
        switcher?.begin()
    }

    private func recentTabs() -> [BrowserTab] {
        var seen = Set<ObjectIdentifier>()
        let current = activeTab
        let tabs = activeSpace.allTabs
            .filter { ($0 === current || $0.lastActive > .distantPast) && seen.insert(ObjectIdentifier($0)).inserted }
            .sorted { $0 === current || ($1 !== current && $0.lastActive > $1.lastActive) }
        return Array(tabs.prefix(TabSwitcher.limit))
    }

    private func cycleTab(by delta: Int) {
        let tabs = activeSpace.visibleTabs
        guard !tabs.isEmpty else { return }
        let current = activeTab.flatMap { tab in tabs.firstIndex { $0 === tab } } ?? 0
        select(tabs[(current + delta + tabs.count) % tabs.count])
    }

    @objc func nextSpace(_ sender: Any?) { switchSpace(by: 1) }
    @objc func renameActiveSpace(_ sender: Any?) { renameSpace(activeIndex) }
    @objc func editActiveSpaceTheme(_ sender: Any?) {
        showThemeEditor(forSpace: activeIndex, relativeTo: sidebar.spaceAnchor(activeIndex))
    }
    @objc func changeActiveSpaceProfile(_ sender: NSMenuItem) {
        changeProfile(of: activeSpace, to: sender.representedObject as? String)
    }

    var spaceList: (spaces: [Space], active: Int) { (spaces, activeIndex) }

    // Pages are rebuilt in the new profile, so each tab reloads with that profile's cookies and logins.
    func changeProfile(of space: Space, to identifier: String?, completion: (@MainActor () -> Void)? = nil) {
        let target = identifier ?? "Space " + UUID().uuidString.prefix(8)
        guard target != space.profileIdentifier else { return }
        Application.shared.loadProfile(identifier: target) { [weak self] profile in
            guard let self, let profile, let index = self.spaces.firstIndex(where: { $0 === space }) else { return }
            let isActive = index == self.activeIndex
            if isActive {
                self.displayedTab?.tab?.isVisible = false
                self.displayedTab = nil
                self.root.card.show(nil)
            }
            let sharesProfile = self.spaces.contains { $0 !== space && $0.profileIdentifier == space.profileIdentifier }
            (sharesProfile ? space.pinnedTabs + space.tabs : space.allTabs).forEach { $0.suspend() }
            space.profileIdentifier = target
            space.profile = profile
            space.favorites.forEach { $0.observer = self }
            if let active = space.activeTab, !space.allTabs.contains(where: { $0 === active }) { space.activeTab = nil }
            if isActive { self.showActiveTab() }
            self.refreshSidebar()
            self.scheduleSave()
            completion?()
        }
    }
    @objc func previousSpace(_ sender: Any?) { switchSpace(by: -1) }

    // MARK: Sidebar resizing

    private func resizeSidebar(to location: CGFloat) {
        let x = root.sidebarOnRight ? root.bounds.width - location : location
        if x < Metrics.sidebarMinWidth - 40 {
            if !root.sidebarHidden { toggleSidebarPanel(nil) }
            return
        }
        root.sidebarWidth = min(max(x, Metrics.sidebarMinWidth), Metrics.sidebarMaxWidth)
    }

    private func endSidebarResize() {
        UserDefaults.standard.set(Double(root.sidebarWidth), forKey: "ArgonSidebarWidth")
    }

    // MARK: BrowserTabObserver

    func browserTabDidChange(_ tab: BrowserTab) {
        sidebar.refresh(tab)
        if tab === activeTab { sidebar.updateToolbar(for: tab) }
        scheduleSave()
    }

    func browserTab(_ tab: BrowserTab, didOpen newTab: Tab, disposition: TabOpenDisposition) {
        guard let index = spaceIndex(of: tab) else {
            newTab.close()
            return
        }
        let space = spaces[index]
        let position = (space.tabs.firstIndex { $0 === tab } ?? -1) + 1
        insertOpened(newTab, in: space, at: disposition == .background ? position : 0, disposition: disposition)
    }

    private func insertOpened(_ newTab: Tab, in space: Space, at position: Int, disposition: TabOpenDisposition) {
        let opened = BrowserTab(tab: newTab)
        opened.observer = self
        space.tabs.insert(opened, at: min(position, space.tabs.count))
        if disposition == .background {
            newTab.isVisible = false
            refreshSidebar()
            scheduleSave()
        } else {
            select(opened)
        }
    }

    func browserTabDidRequestClose(_ tab: BrowserTab) { close(tab) }

    lazy var passwordOffers = PasswordOfferPresenter { [weak self] toast in self?.root.showToast(toast) }

    func browserTab(_ tab: BrowserTab, didOfferPassword offer: PasswordOffer) { passwordOffers.present(offer) }

    func browserTab(_ tab: BrowserTab, didWithdrawPasswordOffer offer: PasswordOffer) { passwordOffers.withdraw(offer) }

    func browserTab(_ tab: BrowserTab, didUpdateFindMatches matches: Int, activeMatch: Int) {
        guard tab === displayedTab else { return }
        findBar?.setMatches(matches, active: activeMatch)
    }

    func browserTab(_ tab: BrowserTab, didRequestFullscreen fullscreen: Bool) {
        guard let window, tab === activeTab else { return }
        root.contentFullscreen = fullscreen
        let isFullscreen = window.styleMask.contains(.fullScreen)
        if fullscreen, !isFullscreen {
            enteredFullscreenForContent = true
            window.toggleFullScreen(nil)
        } else if !fullscreen, enteredFullscreenForContent {
            enteredFullscreenForContent = false
            if isFullscreen { window.toggleFullScreen(nil) }
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        (window as? BrowserWindow)?.positionTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? BrowserWindow)?.positionTrafficLights()
        if root.contentFullscreen {
            root.contentFullscreen = false
            enteredFullscreenForContent = false
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        (window as? BrowserWindow)?.positionTrafficLights()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveNow()
        Application.shared.quit()
        return false
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private static func save(_ items: [SidebarItem]) -> [SavedState.SavedItem] {
        items.compactMap { item in
            switch item {
            case .tab(let tab):
                guard let url = tab.pinnedURL else { return nil }
                return SavedState.SavedItem(tab: SavedState.SavedTab(
                    url: url.absoluteString,
                    title: tab.pinnedTitle.isEmpty ? tab.title : tab.pinnedTitle,
                    favicon: tab.favicon?.faviconData
                ))
            case .folder(let folder):
                return SavedState.SavedItem(folder: SavedState.SavedFolder(
                    name: folder.name, symbol: folder.symbol, expanded: folder.isExpanded, children: save(folder.children)
                ))
            }
        }
    }

    func saveNow() {
        let state = SavedState(
            spaces: spaces.map { space in
                SavedState.SavedSpace(
                    name: space.name,
                    symbol: space.symbol,
                    hue: space.hue,
                    intensity: space.intensity,
                    color: space.customColor?.hexString,
                    profile: space.profileIdentifier,
                    pinned: Self.save(space.pinned),
                    tabs: space.tabs.compactMap { tab in
                        guard let url = tab.url else { return nil }
                        return SavedState.SavedTab(url: url.absoluteString, title: tab.title, favicon: tab.favicon?.faviconData)
                    },
                    active: space.activeTab.flatMap { active in
                        (space.pinnedTabs + space.tabs.filter { $0.url != nil }).firstIndex { $0 === active }
                    },
                    pinnedCollapsed: space.pinnedCollapsed,
                    opacity: space.opacity < 1 ? space.opacity : nil,
                    id: space.id
                )
            },
            activeSpace: activeIndex,
            favorites: FavoritesStore.shared.all.mapValues { tabs in
                tabs.compactMap { tab in
                    guard let url = tab.pinnedURL ?? tab.url else { return nil }
                    return SavedState.SavedTab(url: url.absoluteString, title: tab.pinnedTitle.isEmpty ? tab.title : tab.pinnedTitle,
                                               favicon: tab.favicon?.faviconData)
                }
            }
        )
        state.save()
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
