import AppKit

// Each space is one window to extensions, so "the current window" is the
// space on screen.
extension BrowserWindowController: ExtensionTabsDelegate {
    func extensionWindows(for profile: Profile) -> [ExtensionWindow] {
        var seen = Set<ObjectIdentifier>()
        let ordered = [activeSpace] + spaces.filter { $0 !== activeSpace }
        let windows = ordered.filter { $0.profile === profile }.map { space -> (Space, ExtensionWindow) in
            let tabs = space.allTabs.filter { seen.insert(ObjectIdentifier($0)).inserted }
            let pinned = (space.favorites + space.pinnedTabs).compactMap(\.tab)
            let entry = ExtensionWindow(key: space, tabs: tabs.compactMap(\.tab), activeTab: space.activeTab?.tab,
                                         pinnedTabs: pinned, focused: space === activeSpace && window?.isVisible == true)
            return (space, entry)
        }
        return spaces.compactMap { space in windows.first { $0.0 === space }?.1 }
    }

    func extensionOpenTab(with url: URL?, inWindow windowKey: Any?, profile: Profile, active: Bool, pinned: Bool) -> Tab? {
        let space: Space
        if let key = windowKey as? Space, spaces.contains(where: { $0 === key }) {
            space = key
        } else if activeSpace.profile === profile {
            space = activeSpace
        } else if let match = spaces.first(where: { $0.profile === profile }) {
            space = match
        } else {
            return nil
        }
        let tab = openTab(url, in: space, foreground: active)
        if pinned { pin(tab) }
        if let page = tab.tab { return page }
        let page = tab.materialize(in: profile)
        page.isVisible = false
        return page
    }

    func extensionActivate(_ tab: Tab) {
        guard let target = spaces.lazy.flatMap(\.allTabs).first(where: { $0.tab === tab }) else { return }
        select(target)
    }
}
