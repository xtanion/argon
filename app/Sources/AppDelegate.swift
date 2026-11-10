import AppKit

@MainActor
final class AppDelegate: NSObject, ApplicationDelegate {
    private var controller: BrowserWindowController?

    func applicationDidStart(_ application: Application) {
        let state = SavedState.load()
        for (profile, saved) in state.favorites ?? [:] {
            FavoritesStore.shared[profile] = saved.compactMap { saved in
                URL(string: saved.url).map { BrowserTab(pinnedURL: $0, title: saved.title, favicon: .favicon(fromData: saved.favicon)) }
            }
        }
        let spaces = state.spaces.map { saved in
            let space = Space(name: saved.name, symbol: saved.symbol, hue: saved.hue, profileIdentifier: saved.profile)
            space.intensity = saved.intensity ?? Palette.defaultIntensity
            space.customColor = saved.color.flatMap { NSColor(hex: $0) }
            space.pinned = Self.restore(saved.pinned ?? [])
            space.pinnedCollapsed = saved.pinnedCollapsed ?? false
            space.tabs = saved.tabs.map { saved in
                let tab = BrowserTab(url: URL(string: saved.url), title: saved.title)
                tab.cachedFavicon = .favicon(fromData: saved.favicon)
                return tab
            }
            let ordered = space.pinnedTabs + space.tabs
            if let active = saved.active, ordered.indices.contains(active) {
                space.activeTab = ordered[active]
            }
            return space
        }
        load(spaces, index: 0, application: application) { [weak self] in
            let loaded = spaces.filter { $0.profile != nil }
            guard let self, !loaded.isEmpty else { return }
            NSApp.mainMenu = MainMenu.build()
            let controller = BrowserWindowController(spaces: loaded, activeIndex: state.activeSpace)
            self.controller = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ application: Application, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { controller?.showWindow(nil) }
        return false
    }

    func applicationWillShutDown(_ application: Application) {
        controller?.saveNow()
    }

    private static func restore(_ items: [SavedState.SavedItem]) -> [SidebarItem] {
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
