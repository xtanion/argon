import AppKit

@MainActor
protocol BrowserTabObserver: AnyObject {
    func browserTabDidChange(_ tab: BrowserTab)
    func browserTab(_ tab: BrowserTab, didOpen newTab: Tab, disposition: TabOpenDisposition)
    func browserTabDidRequestClose(_ tab: BrowserTab)
    func browserTab(_ tab: BrowserTab, didRequestFullscreen fullscreen: Bool)
    func browserTab(_ tab: BrowserTab, didUpdateFindMatches matches: Int, activeMatch: Int)
}

// A sidebar tab. The web page is created lazily, so restored tabs cost nothing
// until they are first shown.
@MainActor
final class BrowserTab: NSObject, TabDelegate {
    private(set) var tab: Tab?
    private var savedURL: URL?
    private var savedTitle: String
    weak var observer: BrowserTabObserver?
    var lastActive = Date.distantPast
    private(set) var pinnedURL: URL?
    private(set) var pinnedTitle = ""
    var cachedFavicon: NSImage?

    init(url: URL?, title: String = "") {
        savedURL = url
        savedTitle = title
    }

    init(pinnedURL: URL, title: String, favicon: NSImage?) {
        savedURL = pinnedURL
        savedTitle = title
        self.pinnedURL = pinnedURL
        pinnedTitle = title
        cachedFavicon = favicon
    }

    var isPinned: Bool { pinnedURL != nil }

    var hasLeftPinnedURL: Bool {
        guard let pinnedURL, let url else { return false }
        return url != pinnedURL
    }

    func pin() {
        pinnedURL = url
        pinnedTitle = title
    }

    func unpin() {
        pinnedURL = nil
        pinnedTitle = ""
    }

    // Pinned tabs stay in the sidebar when closed; the page is dropped and the
    // next click starts again from the pinned address.
    func unload() {
        savedURL = pinnedURL ?? url
        savedTitle = pinnedTitle.isEmpty ? title : pinnedTitle
        tab?.delegate = nil
        tab?.close()
        tab = nil
    }

    func returnToPinnedURL() {
        guard let pinnedURL else { return }
        tab?.load(pinnedURL)
    }

    init(tab: Tab) {
        self.tab = tab
        savedTitle = ""
        super.init()
        tab.delegate = self
    }

    var isLoaded: Bool { tab != nil }

    var url: URL? { tab?.url ?? savedURL }

    var title: String {
        if let tab, !tab.title.isEmpty { return tab.title }
        if !savedTitle.isEmpty { return savedTitle }
        return url?.displayHost ?? "New Tab"
    }

    var favicon: NSImage? { tab?.favicon ?? cachedFavicon }
    var isLoading: Bool { tab?.isLoading ?? false }
    var loadProgress: Double { tab?.loadProgress ?? 0 }

    @discardableResult
    func materialize(in profile: Profile) -> Tab {
        if let tab { return tab }
        let created = profile.createTab(url: nil)
        created.delegate = self
        tab = created
        if let savedURL { created.load(savedURL) }
        return created
    }

    func close() {
        tab?.delegate = nil
        tab?.close()
        tab = nil
    }

    func tabDidChangeTitle(_ tab: Tab) { observer?.browserTabDidChange(self) }
    func tabDidChangeURL(_ tab: Tab) { observer?.browserTabDidChange(self) }
    func tabDidChangeLoading(_ tab: Tab) { observer?.browserTabDidChange(self) }
    func tabDidChangeNavigationState(_ tab: Tab) { observer?.browserTabDidChange(self) }
    func tabDidChangeFavicon(_ tab: Tab) {
        if let favicon = tab.favicon { cachedFavicon = favicon }
        observer?.browserTabDidChange(self)
    }

    func tab(_ tab: Tab, didRequestNewTab newTab: Tab, disposition: TabOpenDisposition) {
        observer?.browserTab(self, didOpen: newTab, disposition: disposition)
    }

    func tabDidRequestClose(_ tab: Tab) { observer?.browserTabDidRequestClose(self) }

    func tab(_ tab: Tab, didRequestFullscreen fullscreen: Bool) {
        observer?.browserTab(self, didRequestFullscreen: fullscreen)
    }

    func tab(_ tab: Tab, didUpdateFindMatches matches: Int, activeMatch: Int) {
        observer?.browserTab(self, didUpdateFindMatches: matches, activeMatch: activeMatch)
    }
}

@MainActor
final class SidebarFolder {
    var name: String
    var symbol: String
    var isExpanded: Bool
    var children: [SidebarItem] = []

    init(name: String, symbol: String = "", isExpanded: Bool = true) {
        self.name = name
        self.symbol = symbol
        self.isExpanded = isExpanded
    }
}

@MainActor
enum SidebarItem {
    case tab(BrowserTab)
    case folder(SidebarFolder)

    func contains(_ tab: BrowserTab) -> Bool {
        switch self {
        case .tab(let item): return item === tab
        case .folder(let folder): return folder.children.contains { $0.contains(tab) }
        }
    }

    func contains(_ folder: SidebarFolder) -> Bool {
        guard case .folder(let item) = self else { return false }
        return item === folder || item.children.contains { $0.contains(folder) }
    }

    func isSame(_ other: SidebarItem) -> Bool {
        switch (self, other) {
        case (.tab(let a), .tab(let b)): return a === b
        case (.folder(let a), .folder(let b)): return a === b
        default: return false
        }
    }

    var tabs: [BrowserTab] {
        switch self {
        case .tab(let tab): return [tab]
        case .folder(let folder): return folder.children.flatMap(\.tabs)
        }
    }
}

enum SidebarDrop {
    case pinned(parent: SidebarFolder?, index: Int)
    case into(SidebarFolder)
    case today(index: Int)
}

@MainActor
final class Space {
    var name: String
    var symbol: String
    var hue: Double
    var intensity = Palette.defaultIntensity
    var customColor: NSColor?
    let profileIdentifier: String
    var profile: Profile? {
        didSet { if let profile { DownloadCenter.shared.track(profile) } }
    }
    var pinned: [SidebarItem] = []
    var pinnedCollapsed = false
    var tabs: [BrowserTab] = []
    var activeTab: BrowserTab?

    var pinnedTabs: [BrowserTab] { pinned.flatMap(\.tabs) }
    var allTabs: [BrowserTab] { pinnedTabs + tabs }

    // Tabs in sidebar order, skipping those inside collapsed folders.
    var visibleTabs: [BrowserTab] {
        func walk(_ items: [SidebarItem]) -> [BrowserTab] {
            items.flatMap { item -> [BrowserTab] in
                switch item {
                case .tab(let tab): return [tab]
                case .folder(let folder): return folder.isExpanded ? walk(folder.children) : []
                }
            }
        }
        return walk(pinned) + tabs
    }

    var folders: [(folder: SidebarFolder, depth: Int)] {
        func walk(_ items: [SidebarItem], depth: Int) -> [(folder: SidebarFolder, depth: Int)] {
            items.flatMap { item -> [(folder: SidebarFolder, depth: Int)] in
                guard case .folder(let folder) = item else { return [] }
                return [(folder, depth)] + walk(folder.children, depth: depth + 1)
            }
        }
        return walk(pinned, depth: 0)
    }

    @discardableResult
    func removeFromPinned(_ tab: BrowserTab) -> Bool {
        func remove(from items: inout [SidebarItem]) -> Bool {
            if let index = items.firstIndex(where: { if case .tab(let item) = $0 { return item === tab } else { return false } }) {
                items.remove(at: index)
                return true
            }
            for item in items {
                if case .folder(let folder) = item, remove(from: &folder.children) { return true }
            }
            return false
        }
        return remove(from: &pinned)
    }

    func removeFolder(_ folder: SidebarFolder) {
        func remove(from items: inout [SidebarItem]) -> Bool {
            if let index = items.firstIndex(where: { if case .folder(let item) = $0 { return item === folder } else { return false } }) {
                items.remove(at: index)
                return true
            }
            for item in items {
                if case .folder(let child) = item, remove(from: &child.children) { return true }
            }
            return false
        }
        _ = remove(from: &pinned)
    }

    func contains(_ folder: SidebarFolder) -> Bool {
        pinned.contains { $0.contains(folder) }
    }

    func pinnedLocation(of item: SidebarItem) -> (parent: SidebarFolder?, index: Int)? {
        func search(_ items: [SidebarItem], parent: SidebarFolder?) -> (parent: SidebarFolder?, index: Int)? {
            for (index, candidate) in items.enumerated() {
                if candidate.isSame(item) { return (parent, index) }
                if case .folder(let folder) = candidate, let found = search(folder.children, parent: folder) { return found }
            }
            return nil
        }
        return search(pinned, parent: nil)
    }

    func removePinned(parent: SidebarFolder?, index: Int) {
        if let parent { parent.children.remove(at: index) } else { pinned.remove(at: index) }
    }

    func insertPinned(_ item: SidebarItem, parent: SidebarFolder?, index: Int) {
        if let parent {
            parent.children.insert(item, at: min(max(0, index), parent.children.count))
        } else {
            pinned.insert(item, at: min(max(0, index), pinned.count))
        }
    }

    var frameColor: NSColor { customColor ?? Palette.frame(hue: hue, intensity: intensity) }

    init(name: String, symbol: String, hue: Double, profileIdentifier: String) {
        self.name = name
        self.symbol = symbol
        self.hue = hue
        self.profileIdentifier = profileIdentifier
    }
}

struct SavedState: Codable {
    struct SavedTab: Codable {
        var url: String
        var title: String
        var favicon: String?
    }

    struct SavedItem: Codable {
        var tab: SavedTab?
        var folder: SavedFolder?
    }

    struct SavedFolder: Codable {
        var name: String
        var symbol: String
        var expanded: Bool
        var children: [SavedItem]
    }

    struct SavedSpace: Codable {
        var name: String
        var symbol: String
        var hue: Double
        var intensity: Double?
        var color: String?
        var profile: String
        var pinned: [SavedItem]?
        var tabs: [SavedTab]
        var active: Int?
        var pinnedCollapsed: Bool? = nil
    }

    var spaces: [SavedSpace]
    var activeSpace: Int

    private static let key = "ArgonBrowserState"

    static let initial = SavedState(
        spaces: [
            SavedSpace(name: "Personal", symbol: "house", hue: 0.62, intensity: nil, color: nil, profile: "Default", pinned: nil, tabs: [], active: nil),
            SavedSpace(name: "Work", symbol: "briefcase", hue: 0.08, intensity: nil, color: nil, profile: "Space Work", pinned: nil, tabs: [], active: nil),
        ],
        activeSpace: 0
    )

    static func load() -> SavedState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(SavedState.self, from: data),
              !state.spaces.isEmpty
        else { return initial }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension NSImage {
    // Small PNG for persisting favicons, so restored tabs show their icon
    // before the page loads.
    var faviconData: String? {
        let side: CGFloat = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])?.base64EncodedString()
    }

    static func favicon(fromData string: String?) -> NSImage? {
        guard let string, let data = Data(base64Encoded: string), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

enum SpaceSymbols {
    static let all = [
        "star.fill", "bookmark.fill", "heart.fill", "flag.fill", "bolt.fill", "triangle.fill", "asterisk", "bell.fill",
        "lightbulb.fill", "square.on.circle.fill", "square.grid.2x2.fill", "circle.grid.3x3.fill", "square.stack.3d.up.fill", "cylinder.split.1x2.fill", "archivebox.fill", "square.on.square.fill",
        "folder.fill", "tray.fill", "calendar", "envelope.fill", "checkmark.square.fill", "doc.fill", "book.fill", "ellipsis.bubble.fill",
        "person.2.fill", "apple.terminal.fill", "wrench.and.screwdriver.fill", "square.fill", "oval.portrait.fill", "circle.fill", "moon.fill", "sun.max.fill",
        SpaceGlyph.planet.rawValue, "leaf.fill", "cloud.fill", "pawprint.fill", "basket.fill", "gift.fill", "bed.double.fill", "fork.knife",
        "dumbbell.fill", "airplane", "music.note", "paintpalette.fill", "video.fill", "bandage.fill", "chevron.left.forwardslash.chevron.right", "baseball.fill",
        "cloud", "map.fill", "flame.fill", SpaceGlyph.pizza.rawValue, SpaceGlyph.skull.rawValue, "scroll.fill", "hand.thumbsup.fill", "tram.fill",
    ]

    static let emoji = [
        "😀", "😎", "🤓", "🥳", "😴", "🤔", "🤖", "👻",
        "❤️", "🔥", "⭐️", "⚡️", "🌈", "☀️", "🌙", "❄️",
        "🌱", "🌸", "🍀", "🌊", "🏔️", "🌍", "🪐", "🚀",
        "🐶", "🐱", "🦊", "🐼", "🐸", "🦄", "🐝", "🐙",
        "🍕", "🍔", "🍣", "🍩", "☕️", "🍺", "🍎", "🥑",
        "💼", "📚", "🎓", "💻", "🎨", "🎵", "🎮", "📷",
        "🏠", "✈️", "🛒", "💰", "🏋️", "⚽️", "🎯", "💡",
    ]

    static func displayName(_ symbol: String, active: Bool) -> String {
        guard active, NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) != nil else { return symbol }
        return symbol + ".fill"
    }
}

@MainActor
enum AddressInput {
    static func url(from text: String, profile: Profile?) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = directURL(trimmed) { return url }
        if let url = profile?.searchURL(for: trimmed) { return url }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    static func searchEngineName(for profile: Profile?) -> String {
        profile?.searchEngineName ?? "DuckDuckGo"
    }

    static func directURL(_ text: String) -> URL? {
        if text.contains(" ") { return nil }
        if let scheme = text.split(separator: ":").first,
           ["http", "https", "file", "about", "chrome", "data"].contains(scheme.lowercased()),
           let url = URL(string: text) {
            return url
        }
        if text.hasPrefix("localhost") || text.contains("."),
           let url = URL(string: (text.hasPrefix("localhost") ? "http://" : "https://") + text),
           url.host != nil {
            return url
        }
        return nil
    }
}

extension Notification.Name {
    static let downloadsDidChange = Notification.Name("ArgonDownloadsDidChange")
}

enum DownloadEvent {
    case started(Download)
    case finished(Download)
    case failed(Download)
    case changed
}

// Merges downloads from every loaded profile; posts .downloadsDidChange with the event under "event".
@MainActor
final class DownloadCenter: NSObject, ProfileDownloadDelegate {
    static let shared = DownloadCenter()

    private var profiles: [ObjectIdentifier: Profile] = [:]
    private var lastStates: [String: DownloadState] = [:]
    private(set) var downloads: [Download] = []

    var active: [Download] { downloads.filter { $0.state == .inProgress } }

    // Byte-weighted progress of in-progress downloads; nil when nothing is downloading.
    var activeProgress: CGFloat? {
        let running = active
        guard !running.isEmpty else { return nil }
        let known = running.filter { $0.totalBytes > 0 }
        guard !known.isEmpty else { return 0 }
        let received = known.reduce(Int64(0)) { $0 + $1.receivedBytes }
        let total = known.reduce(Int64(0)) { $0 + $1.totalBytes }
        return CGFloat(Double(received) / Double(max(total, 1)))
    }

    func track(_ profile: Profile) {
        let key = ObjectIdentifier(profile)
        guard profiles[key] == nil else { return }
        profiles[key] = profile
        profile.downloadDelegate = self
        for download in profile.downloads { lastStates[download.identifier] = download.state }
        rebuild()
        post(.changed)
    }

    private func rebuild() {
        downloads = profiles.values.flatMap(\.downloads).sorted { $0.startDate > $1.startDate }
    }

    private func post(_ event: DownloadEvent) {
        NotificationCenter.default.post(name: .downloadsDidChange, object: self, userInfo: ["event": event])
    }

    func profile(_ profile: Profile, didAdd download: Download, isNew: Bool) {
        lastStates[download.identifier] = download.state
        rebuild()
        post(isNew ? .started(download) : .changed)
    }

    func profile(_ profile: Profile, didUpdate download: Download) {
        let previous = lastStates[download.identifier]
        lastStates[download.identifier] = download.state
        if previous != download.state {
            rebuild()
            switch download.state {
            case .complete where previous == .inProgress: post(.finished(download))
            case .interrupted where previous == .inProgress: post(.failed(download))
            default: post(.changed)
            }
        } else {
            post(.changed)
        }
    }

    func profile(_ profile: Profile, didRemove download: Download) {
        lastStates[download.identifier] = nil
        rebuild()
        post(.changed)
    }
}
