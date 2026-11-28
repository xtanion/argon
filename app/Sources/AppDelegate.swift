import AppKit

@MainActor
final class AppDelegate: NSObject, ApplicationDelegate {
    private var controller: BrowserWindowController?
    private var pendingURLs: [URL] = []

    func applicationDidStart(_ application: Application) {
        AppIcon.start()
        let state = SavedState.load()
        for (profile, saved) in state.favorites ?? [:] {
            FavoritesStore.shared[profile] = saved.compactMap { saved in
                URL(string: saved.url).map { BrowserTab(pinnedURL: $0, title: saved.title, favicon: .favicon(fromData: saved.favicon)) }
            }
        }
        let spaces = state.spaces.map { saved in
            let space = Space(id: saved.id ?? UUID().uuidString, name: saved.name, symbol: saved.symbol, hue: saved.hue, profileIdentifier: saved.profile)
            space.intensity = saved.intensity ?? Palette.defaultIntensity
            space.customColor = saved.color.flatMap { NSColor(hex: $0) }
            space.opacity = min(max(saved.opacity ?? 1, Palette.minimumOpacity), 1)
            space.pinned = Self.restore(saved.pinned ?? [])
            space.pinnedCollapsed = saved.pinnedCollapsed ?? false
            space.tabs = saved.tabs.map { saved in
                let tab = BrowserTab(url: URL(string: saved.url), title: saved.title)
                tab.cachedFavicon = .favicon(fromData: saved.favicon)
                if let viewed = saved.viewed { tab.lastViewed = Date(timeIntervalSince1970: min(viewed, Date().timeIntervalSince1970)) }
                return tab
            }
            let ordered = space.pinnedTabs + space.tabs
            if let active = saved.active, ordered.indices.contains(active) {
                space.activeTab = ordered[active]
            }
            return space
        }
        let activeIndex = spaces.indices.contains(state.activeSpace) ? state.activeSpace : 0
        guard spaces.indices.contains(activeIndex) else { return }
        let identifier = spaces[activeIndex].profileIdentifier
        application.loadProfile(identifier: identifier) { [weak self] profile in
            guard let self else { return }
            guard let profile else {
                self.load(spaces, index: 0, application: application) { [weak self] in
                    self?.start(spaces.filter { $0.profile != nil }, activeIndex: 0)
                }
                return
            }
            for space in spaces where space.profileIdentifier == identifier { space.profile = profile }
            self.start(spaces, activeIndex: activeIndex)
        }
    }

    // Only the active space's profile loads before the window opens; the rest
    // load when their space is first shown.
    private func start(_ spaces: [Space], activeIndex: Int) {
        guard !spaces.isEmpty else { return }
        NSApp.mainMenu = MainMenu.build()
        LittleStone.updateHotKey()
        let application = Application.shared
        let controller = BrowserWindowController(spaces: spaces, activeIndex: activeIndex)
        self.controller = controller
        application.extensionTabsDelegate = controller
        application.extensionWindowsDidChange()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        BackgroundWorker.shared.register(UpdateCheckJob())
        if !pendingURLs.isEmpty {
            controller.open(pendingURLs)
            pendingURLs = []
        }
    }

    func application(_ application: Application, profileWillUnload profile: Profile) {
        controller?.profileWillUnload(profile)
    }

    func applicationShouldHandleReopen(_ application: Application, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { controller?.showWindow(nil) }
        return false
    }

    // Profiles load asynchronously at launch, so links can arrive before the window exists.
    func application(_ application: Application, open urls: [URL]) {
        guard let controller else {
            pendingURLs += urls
            return
        }
        controller.open(urls)
    }

    func applicationWillShutDown(_ application: Application) {
        controller?.saveNow()
    }

    static func restore(_ items: [SavedState.SavedItem]) -> [SidebarItem] {
        items.compactMap { item in
            if let saved = item.tab, let url = URL(string: saved.url) {
                return .tab(BrowserTab(pinnedURL: url, title: saved.title, favicon: .favicon(fromData: saved.favicon)))
            }
            if let saved = item.folder {
                let folder = SidebarFolder(name: saved.name, symbol: saved.symbol, isExpanded: saved.expanded)
                folder.children = restore(saved.children)
                return .folder(folder)
            }
            return nil
        }
    }

    private func load(_ spaces: [Space], index: Int, application: Application, completion: @escaping @MainActor () -> Void) {
        guard index < spaces.count else {
            completion()
            return
        }
        application.loadProfile(identifier: spaces[index].profileIdentifier) { [weak self] profile in
            spaces[index].profile = profile
            self?.load(spaces, index: index + 1, application: application, completion: completion)
        }
    }
}
