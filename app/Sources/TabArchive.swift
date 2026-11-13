import AppKit

struct ArchivedTab: Codable, Sendable {
    var url: String
    var title: String
    var favicon: String?
    var spaceID: String
    var spaceName: String
    var archived: Date
}

@MainActor
final class TabArchive {
    static let shared = TabArchive()

    private static let limit = 500
    private static let keep: TimeInterval = 30 * 24 * 60 * 60

    private(set) var entries: [ArchivedTab] = []

    private let file: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Argon", isDirectory: true)
        .appendingPathComponent("Archive.json")

    private init() {
        if let file, let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            entries = (try? decoder.decode([ArchivedTab].self, from: data)) ?? []
        }
        prune()
    }

    func add(_ tabs: [ArchivedTab]) {
        guard !tabs.isEmpty else { return }
        let urls = Set(tabs.map(\.url))
        entries.removeAll { urls.contains($0.url) }
        entries.insert(contentsOf: tabs, at: 0)
        prune()
        save()
    }

    func remove(_ entry: ArchivedTab) {
        entries.removeAll { $0.url == entry.url && $0.archived == entry.archived }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func search(_ needle: String) -> [ArchivedTab] {
        let needle = needle.lowercased()
        guard !needle.isEmpty else { return [] }
        return entries.filter { ($0.title + " " + $0.url).lowercased().contains(needle) }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.keep)
        entries.removeAll { $0.archived < cutoff }
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    private func save() {
        guard let file else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

@MainActor
final class ArchiveMenu: NSObject, NSMenuDelegate {
    static let shared = ArchiveMenu()

    private static let shown = 30

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = TabArchive.shared.entries
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: Preferences.archiveAfter == nil ? "Auto-archive is off" : "No archived tabs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        var lastDay: String?
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        for entry in entries.prefix(Self.shown) {
            let day = Self.dayTitle(entry.archived)
            if day != lastDay {
                if lastDay != nil { menu.addItem(.separator()) }
                let header = NSMenuItem(title: day, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                lastDay = day
            }
            let title = entry.title.count > 60 ? String(entry.title.prefix(59)) + "\u{2026}" : entry.title
            let item = ClosureMenuItem(title.isEmpty ? entry.url : title) { ArchiveMenu.restore(entry) }
            item.image = NSImage.favicon(fromData: entry.favicon) ?? .symbol("globe", size: 12)
            item.toolTip = "\(entry.url)\n\(entry.spaceName) \u{00B7} archived \(formatter.localizedString(for: entry.archived, relativeTo: Date()))"
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Clear Archive") { TabArchive.shared.clear() })
    }

    static func restore(_ entry: ArchivedTab) {
        guard let controller = BrowserWindowController.current, let url = URL(string: entry.url) else { return }
        TabArchive.shared.remove(entry)
        controller.restoreArchived(url, spaceID: entry.spaceID)
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
