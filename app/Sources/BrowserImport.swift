import AppKit
import CommonCrypto
import Security
import SQLite3

enum ImportSource: String, CaseIterable, Sendable {
    case arc, chrome

    var title: String {
        switch self {
        case .arc: return "Arc"
        case .chrome: return "Google Chrome"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .arc: return "company.thebrowser.Browser"
        case .chrome: return "com.google.Chrome"
        }
    }

    var appRoot: URL {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        switch self {
        case .arc: return support.appendingPathComponent("Arc")
        case .chrome: return support.appendingPathComponent("Google/Chrome")
        }
    }

    var userData: URL {
        switch self {
        case .arc: return appRoot.appendingPathComponent("User Data")
        case .chrome: return appRoot
        }
    }

    var keychainService: String {
        switch self {
        case .arc: return "Arc Safe Storage"
        case .chrome: return "Chrome Safe Storage"
        }
    }

    var profilePrefix: String {
        switch self {
        case .arc: return "Arc "
        case .chrome: return "Chrome "
        }
    }

    @MainActor
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || FileManager.default.fileExists(atPath: userData.path)
    }

    @MainActor
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

struct ImportOptions: Sendable {
    var sidebar = true
    var history = true
    var passwords = true
    var cookies = true

    var needsKey: Bool { passwords || cookies }
    var any: Bool { sidebar || history || passwords || cookies }
}

struct ImportSummary: Sendable {
    var spaces = 0
    var favorites = 0
    var history = 0
    var passwords = 0
    var cookies = 0
    var warnings: [String] = []

    var text: String {
        var parts: [String] = []
        if spaces > 0 { parts.append("\(spaces) space\(spaces == 1 ? "" : "s")") }
        if favorites > 0 { parts.append("\(favorites) favorite\(favorites == 1 ? "" : "s")") }
        if history > 0 { parts.append("\(history) history entr\(history == 1 ? "y" : "ies")") }
        if passwords > 0 { parts.append("\(passwords) password\(passwords == 1 ? "" : "s")") }
        if cookies > 0 { parts.append("\(cookies) cookie\(cookies == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing new to import." : "Imported " + parts.joined(separator: ", ") + "."
    }
}

enum ImportError: LocalizedError {
    case notFound(ImportSource)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let source):
            return "Couldn't find \(source.title)'s data. Open \(source.title) once, or allow Argon to access data from other apps in System Settings \u{2192} Privacy & Security."
        case .unreadable(let what):
            return "Couldn't read \(what)."
        }
    }
}

// MARK: Plan

struct ImportedSpacePlan: Sendable {
    var id: String
    var name: String
    var symbol: String
    var color: String?
    var hue: Double
    var sourceProfile: String
    var pinned: [SavedState.SavedItem]
    var tabs: [SavedState.SavedTab]
}

struct ImportPlan: Sendable {
    var spaces: [ImportedSpacePlan] = []
    var favorites: [String: [SavedState.SavedTab]] = [:]
    var profiles: [String] = []
}

struct VisitRecord: Sendable {
    var url: String
    var title: String
    var visits: Int
    var typed: Int
    var last: Date
}

struct LoginRecord: Sendable {
    var url: String
    var action: String
    var realm: String
    var usernameElement: String
    var username: String
    var passwordElement: String
    var password: String
    var created: Date?
    var lastUsed: Date?
    var timesUsed: Int
}

struct CookieRecord: Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var created: Date
    var expires: Date?
    var lastAccess: Date
    var lastUpdate: Date
    var secure: Bool
    var httpOnly: Bool
    var sameSite: Int
    var priority: Int
    var sourceScheme: Int
    var sourcePort: Int
    var sourceType: Int
}

struct ProfileData: Sendable {
    var visits: [VisitRecord] = []
    var logins: [LoginRecord] = []
    var cookies: [CookieRecord] = []
}

// MARK: Arc sidebar

enum ArcSidebar {
    private static let referenceOffset: TimeInterval = 978_307_200

    static func plan(root: URL) throws -> ImportPlan {
        let url = root.appendingPathComponent("StorableSidebar.json")
        guard let data = try? Data(contentsOf: url) else { throw ImportSource.arc.missing }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = json["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]],
              let container = containers.first(where: { $0["spaces"] != nil })
        else { throw ImportError.unreadable("Arc's sidebar") }

        var items: [String: [String: Any]] = [:]
        for case let item as [String: Any] in container["items"] as? [Any] ?? [] {
            if let id = item["id"] as? String { items[id] = item }
        }

        func children(of id: String) -> [String] { items[id]?["childrenIds"] as? [String] ?? [] }

        func tab(_ item: [String: Any]) -> SavedState.SavedTab? {
            guard let data = item["data"] as? [String: Any], let tab = data["tab"] as? [String: Any],
                  let url = tab["savedURL"] as? String, !url.isEmpty else { return nil }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tab["savedTitle"] as? String ?? ""
            let viewed = (tab["timeLastActiveAt"] as? Double).map { $0 + referenceOffset }
            return SavedState.SavedTab(url: url, title: title, favicon: nil, viewed: viewed)
        }

        func tree(_ ids: [String]) -> [SavedState.SavedItem] {
            ids.flatMap { id -> [SavedState.SavedItem] in
                guard let item = items[id] else { return [] }
                if let saved = tab(item) { return [SavedState.SavedItem(tab: saved)] }
                let data = item["data"] as? [String: Any] ?? [:]
                if let list = data["list"] as? [String: Any] {
                    let info = list["customInfo"] as? [String: Any]
                    let folder = SavedState.SavedFolder(
                        name: (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Folder",
                        symbol: info.flatMap { symbol(from: $0["iconType"]) } ?? "",
                        expanded: true,
                        children: tree(children(of: id))
                    )
                    return [SavedState.SavedItem(folder: folder)]
                }
                return tree(children(of: id))
            }
        }

        func flatTabs(_ ids: [String]) -> [SavedState.SavedTab] {
            ids.flatMap { id -> [SavedState.SavedTab] in
                guard let item = items[id] else { return [] }
                if let saved = tab(item) { return [saved] }
                return flatTabs(children(of: id))
            }
        }

        var plan = ImportPlan()
        var hueIndex = 0
        for case let space as [String: Any] in container["spaces"] as? [Any] ?? [] {
            guard let id = space["id"] as? String else { continue }
            let profile = profileDirectory(space["profile"])
            var pinnedID: String?
            var unpinnedID: String?
            var marker: String?
            for entry in (space["newContainerIDs"] ?? space["containerIDs"]) as? [Any] ?? [] {
                if let string = entry as? String {
                    if string == "pinned" || string == "unpinned" {
                        marker = string
                    } else if let current = marker {
                        if current == "pinned" { pinnedID = string } else { unpinnedID = string }
                        marker = nil
                    }
                } else if let dict = entry as? [String: Any] {
                    marker = dict["pinned"] != nil ? "pinned" : dict["unpinned"] != nil ? "unpinned" : nil
                }
            }
            let info = space["customInfo"] as? [String: Any] ?? [:]
            let rgb = (info["windowTheme"] as? [String: Any]).flatMap { firstColor(in: $0["background"]) }
            let hues = [0.62, 0.08, 0.38, 0.76, 0.9, 0.5, 0.14, 0.0]
            var hue = hues[hueIndex % hues.count]
            hueIndex += 1
            var hex: String?
            if let rgb {
                let color = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
                hex = color.hexString
                if color.saturationComponent > 0.08 { hue = Double(color.hueComponent) }
            }
            plan.spaces.append(ImportedSpacePlan(
                id: "arc-" + id,
                name: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space",
                symbol: symbol(from: info["iconType"]) ?? "star.fill",
                color: hex,
                hue: hue,
                sourceProfile: profile,
                pinned: pinnedID.map { tree(children(of: $0)) } ?? [],
                tabs: unpinnedID.map { flatTabs(children(of: $0)) } ?? []
            ))
        }

        let top = container["topAppsContainerIDs"] as? [Any] ?? []
        var index = 0
        while index + 1 < top.count {
            if let id = top[index + 1] as? String {
                let profile = profileDirectory(top[index])
                plan.favorites[profile, default: []] += flatTabs(children(of: id))
            }
            index += 2
        }

        var profiles: [String] = []
        for profile in plan.spaces.map(\.sourceProfile) where !profiles.contains(profile) {
            profiles.append(profile)
        }
        plan.profiles = profiles
        plan.favorites = plan.favorites.filter { profiles.contains($0.key) }
        return plan
    }

    private static func profileDirectory(_ value: Any?) -> String {
        guard let dict = value as? [String: Any],
              let custom = dict["custom"] as? [String: Any],
              let inner = custom["_0"] as? [String: Any],
              let name = inner["directoryBasename"] as? String
        else { return "Default" }
        return name
    }

    private static func firstColor(in value: Any?) -> (CGFloat, CGFloat, CGFloat)? {
        if let dict = value as? [String: Any] {
            if let r = dict["red"] as? Double, let g = dict["green"] as? Double, let b = dict["blue"] as? Double {
                return (CGFloat(min(max(r, 0), 1)), CGFloat(min(max(g, 0), 1)), CGFloat(min(max(b, 0), 1)))
            }
            for key in dict.keys.sorted() {
                if let found = firstColor(in: dict[key]) { return found }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = firstColor(in: element) { return found }
            }
        }
        return nil
    }

    private static let iconNames: [String: String] = [
        "planet": SpaceGlyph.planet.rawValue,
        "pizza": SpaceGlyph.pizza.rawValue,
        "skull": SpaceGlyph.skull.rawValue,
        "terminal": "apple.terminal.fill",
        "code": "chevron.left.forwardslash.chevron.right",
        "briefcase": "briefcase.fill",
        "book": "book.fill",
        "music": "music.note",
        "plane": "airplane",
        "paint": "paintpalette.fill",
        "fire": "flame.fill",
    ]

    private static func symbol(from value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let emoji = dict["emoji_v2"] as? String, !emoji.isEmpty { return emoji }
        if let scalar = dict["emoji"] as? Int, let unicode = Unicode.Scalar(scalar) { return String(Character(unicode)) }
        guard let name = dict["icon"] as? String else { return nil }
        if let mapped = iconNames[name] { return mapped }
        for candidate in [name + ".fill", name] where NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
            return candidate
        }
        return nil
    }
}

// MARK: Chrome bookmarks

enum ChromeBookmarks {
    static func plan(userData: URL) throws -> ImportPlan {
        let localState = userData.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState) else { throw ImportSource.chrome.missing }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let cache = ((json?["profile"] as? [String: Any])?["info_cache"] as? [String: Any]) ?? [:]
        let directories = cache.keys.sorted { a, b in
            a == "Default" ? true : b == "Default" ? false : a.localizedStandardCompare(b) == .orderedAscending
        }
        var plan = ImportPlan()
        let symbols = ["bookmark.fill", "globe", "star.fill", "flag.fill", "bolt.fill", "heart.fill"]
        let hues = [0.62, 0.08, 0.38, 0.76, 0.9, 0.5]
        for (index, directory) in directories.enumerated() {
            let info = cache[directory] as? [String: Any]
            let profileName = info?["name"] as? String ?? directory
            var pinned: [SavedState.SavedItem] = []
            if let bookmarks = try? Data(contentsOf: userData.appendingPathComponent(directory).appendingPathComponent("Bookmarks")),
               let root = (try? JSONSerialization.jsonObject(with: bookmarks)) as? [String: Any],
               let roots = root["roots"] as? [String: Any] {
                pinned = convert((roots["bookmark_bar"] as? [String: Any])?["children"])
                for (key, title) in [("other", "Other Bookmarks"), ("synced", "Mobile Bookmarks")] {
                    let children = convert((roots[key] as? [String: Any])?["children"])
                    if !children.isEmpty {
                        pinned.append(SavedState.SavedItem(folder: SavedState.SavedFolder(name: title, symbol: "", expanded: false, children: children)))
                    }
                }
            }
            plan.spaces.append(ImportedSpacePlan(
                id: "chrome-" + directory,
                name: directories.count == 1 ? "Chrome" : profileName,
                symbol: symbols[index % symbols.count],
                color: nil,
                hue: hues[index % hues.count],
                sourceProfile: directory,
                pinned: pinned,
                tabs: []
            ))
            plan.profiles.append(directory)
        }
        return plan
    }

    private static func convert(_ value: Any?) -> [SavedState.SavedItem] {
        (value as? [[String: Any]] ?? []).compactMap { node in
            switch node["type"] as? String {
            case "url":
                guard let url = node["url"] as? String, !url.isEmpty else { return nil }
                return SavedState.SavedItem(tab: SavedState.SavedTab(url: url, title: node["name"] as? String ?? "", favicon: nil))
            case "folder":
                return SavedState.SavedItem(folder: SavedState.SavedFolder(
                    name: node["name"] as? String ?? "Folder", symbol: "", expanded: false, children: convert(node["children"])))
            default:
                return nil
            }
        }
    }
}

private extension ImportSource {
    var missing: ImportError { .notFound(self) }
}

// MARK: Chromium profile databases

enum ChromiumProfileReader {
    // Chromium stores times as microseconds since 1601-01-01.
    private static let windowsEpochOffset: Double = 11_644_473_600

    static func date(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(value) / 1_000_000 - windowsEpochOffset)
    }

    // The Safe Storage password is the same for every profile; macOS asks the user once.
    static func encryptionKey(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let password = result as? Data else { return nil }
        var key = Data(count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128
                )
            }
        }
        return status == kCCSuccess ? key : nil
    }

    static func decrypt(_ blob: Data, key: Data) -> Data? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else { return nil }
        let payload = blob.dropFirst(3)
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        let capacity = output.count
        var length = 0
        let status = output.withUnsafeMutableBytes { outBytes in
            payload.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, iv,
                            inBytes.baseAddress, payload.count,
                            outBytes.baseAddress, capacity, &length)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(length)
    }

    // Browsers keep their databases open, so read a copy that includes the write-ahead log.
    private static func withCopy<T>(of database: URL, _ body: (OpaquePointer) -> T) -> T? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: database.path) else { return nil }
        let folder = manager.temporaryDirectory.appendingPathComponent("ArgonImport-" + UUID().uuidString)
        defer { try? manager.removeItem(at: folder) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent("db")
            try manager.copyItem(at: database, to: copy)
            for suffix in ["-wal", "-journal"] {
                let side = URL(fileURLWithPath: database.path + suffix)
                if manager.fileExists(atPath: side.path) {
                    try? manager.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
            var handle: OpaquePointer?
            guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
                sqlite3_close(handle)
                return nil
            }
            defer { sqlite3_close(handle) }
            return body(handle)
        } catch {
            return nil
        }
    }

    private static func rows(_ db: OpaquePointer, _ sql: String, _ each: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { each(statement) }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    static func history(profile: URL) -> [VisitRecord] {
        withCopy(of: profile.appendingPathComponent("History")) { db in
            var result: [VisitRecord] = []
            rows(db, "SELECT url, title, visit_count, typed_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT 100000") { row in
                let url = text(row, 0)
                guard url.hasPrefix("http"), let last = date(sqlite3_column_int64(row, 4)) else { return }
                result.append(VisitRecord(url: url, title: text(row, 1), visits: Int(sqlite3_column_int(row, 2)),
                                          typed: Int(sqlite3_column_int(row, 3)), last: last))
            }
            return result
        } ?? []
    }

    static func logins(profile: URL, key: Data) -> [LoginRecord] {
        withCopy(of: profile.appendingPathComponent("Login Data")) { db in
            var result: [LoginRecord] = []
            rows(db, "SELECT origin_url, action_url, signon_realm, username_element, username_value, password_element, password_value, date_created, date_last_used, times_used FROM logins WHERE blacklisted_by_user = 0") { row in
                guard let plain = decrypt(blob(row, 6), key: key), let password = String(data: plain, encoding: .utf8), !password.isEmpty else { return }
                result.append(LoginRecord(
                    url: text(row, 0), action: text(row, 1), realm: text(row, 2),
                    usernameElement: text(row, 3), username: text(row, 4), passwordElement: text(row, 5),
                    password: password, created: date(sqlite3_column_int64(row, 7)), lastUsed: date(sqlite3_column_int64(row, 8)),
                    timesUsed: Int(sqlite3_column_int(row, 9))
                ))
            }
            return result
        } ?? []
    }

    static func cookies(profile: URL, key: Data) -> [CookieRecord] {
        let direct = profile.appendingPathComponent("Cookies")
        let file = FileManager.default.fileExists(atPath: direct.path) ? direct : profile.appendingPathComponent("Network/Cookies")
        return withCopy(of: file) { db in
            var version = 0
            rows(db, "SELECT value FROM meta WHERE key = 'version'") { row in version = Int(text(row, 0)) ?? 0 }
            let now = Date()
            var result: [CookieRecord] = []
            rows(db, """
                SELECT host_key, name, value, encrypted_value, path, creation_utc, expires_utc, last_access_utc, last_update_utc,
                       is_secure, is_httponly, samesite, priority, source_scheme, source_port, source_type, has_expires
                FROM cookies WHERE top_frame_site_key = ''
                """) { row in
                var value = text(row, 2)
                let encrypted = blob(row, 3)
                if !encrypted.isEmpty {
                    // Since database version 24 the plaintext starts with a SHA-256 of the cookie's domain.
                    guard var plain = decrypt(encrypted, key: key) else { return }
                    if version >= 24 { plain = plain.count >= 32 ? plain.dropFirst(32) : Data() }
                    guard let decoded = String(data: plain, encoding: .utf8) else { return }
                    value = decoded
                }
                let expires = sqlite3_column_int(row, 16) != 0 ? date(sqlite3_column_int64(row, 6)) : nil
                if let expires, expires < now { return }
                let created = date(sqlite3_column_int64(row, 5)) ?? now
                let lastAccess = date(sqlite3_column_int64(row, 7)) ?? created
                result.append(CookieRecord(
                    name: text(row, 1), value: value, domain: text(row, 0), path: text(row, 4),
                    created: created, expires: expires, lastAccess: lastAccess,
                    lastUpdate: date(sqlite3_column_int64(row, 8)) ?? lastAccess,
                    secure: sqlite3_column_int(row, 9) != 0, httpOnly: sqlite3_column_int(row, 10) != 0,
                    sameSite: Int(sqlite3_column_int(row, 11)), priority: Int(sqlite3_column_int(row, 12)),
                    sourceScheme: Int(sqlite3_column_int(row, 13)), sourcePort: Int(sqlite3_column_int(row, 14)),
                    sourceType: Int(sqlite3_column_int(row, 15))
                ))
            }
            return result
        } ?? []
    }
}

// MARK: Importer

@MainActor
final class BrowserImporter {
    static let shared = BrowserImporter()
    private(set) var isRunning = false

    func run(_ source: ImportSource, options: ImportOptions, progress: @escaping @MainActor (String) -> Void,
             completion: @escaping @MainActor (Result<ImportSummary, Error>) -> Void) {
        guard !isRunning, options.any, let controller = BrowserWindowController.current else { return }
        isRunning = true
        progress("Reading \(source.title)\u{2026}")
        let finish: @MainActor (Result<ImportSummary, Error>) -> Void = { [weak self] result in
            self?.isRunning = false
            completion(result)
        }
        Task.detached(priority: .userInitiated) {
            do {
                let (plan, data, warnings) = try Self.read(source, options: options)
                await MainActor.run {
                    self.apply(plan, data: data, source: source, options: options, controller: controller,
                               summary: ImportSummary(warnings: warnings), progress: progress) { summary in finish(.success(summary)) }
                }
            } catch {
                await MainActor.run { finish(.failure(error)) }
            }
        }
    }

    nonisolated private static func read(_ source: ImportSource, options: ImportOptions) throws -> (ImportPlan, [String: ProfileData], [String]) {
        guard FileManager.default.fileExists(atPath: source.userData.path) else { throw ImportError.notFound(source) }
        let plan: ImportPlan
        switch source {
        case .arc: plan = try ArcSidebar.plan(root: source.appRoot)
        case .chrome: plan = try ChromeBookmarks.plan(userData: source.userData)
        }
        var warnings: [String] = []
        var key: Data?
        if options.needsKey {
            key = ChromiumProfileReader.encryptionKey(service: source.keychainService)
            if key == nil { warnings.append("Passwords and cookies were skipped because access to \(source.keychainService) wasn't allowed.") }
        }
        var data: [String: ProfileData] = [:]
        for profile in plan.profiles {
            let folder = source.userData.appendingPathComponent(profile)
            var entry = ProfileData()
            if options.history { entry.visits = ChromiumProfileReader.history(profile: folder) }
            if let key {
                if options.passwords { entry.logins = ChromiumProfileReader.logins(profile: folder, key: key) }
                if options.cookies { entry.cookies = ChromiumProfileReader.cookies(profile: folder, key: key) }
            }
            data[profile] = entry
        }
        return (plan, data, warnings)
    }

    private func apply(_ plan: ImportPlan, data: [String: ProfileData], source: ImportSource, options: ImportOptions,
                       controller: BrowserWindowController, summary: ImportSummary,
                       progress: @escaping @MainActor (String) -> Void, completion: @escaping @MainActor (ImportSummary) -> Void) {
        var result = summary
        let target: (String) -> String = { profile in
            options.sidebar ? source.profilePrefix + profile : controller.activeSpace.profileIdentifier
        }
        let importData = { [weak self] in
            self?.importProfiles(plan.profiles, data: data, target: target, options: options, summary: result,
                                 progress: progress, completion: completion)
        }
        guard options.sidebar else {
            importData()
            return
        }
        progress("Adding spaces\u{2026}")
        let spaces = plan.spaces.map { saved in
            let space = Space(id: saved.id, name: saved.name, symbol: saved.symbol, hue: saved.hue, profileIdentifier: target(saved.sourceProfile))
            space.customColor = saved.color.flatMap { NSColor(hex: $0) }
            space.pinned = AppDelegate.restore(saved.pinned)
            space.tabs = saved.tabs.compactMap { saved in
                guard let url = URL(string: saved.url) else { return nil }
                let tab = BrowserTab(url: url, title: saved.title)
                if let viewed = saved.viewed { tab.lastViewed = Date(timeIntervalSince1970: min(viewed, Date().timeIntervalSince1970)) }
                return tab
            }
            return space
        }
        var favorites: [String: [BrowserTab]] = [:]
        for (profile, tabs) in plan.favorites {
            favorites[target(profile)] = tabs.compactMap { saved in
                URL(string: saved.url).map { BrowserTab(pinnedURL: $0, title: saved.title, favicon: nil) }
            }
        }
        let before = favorites.values.reduce(0) { $0 + $1.count }
        controller.addImportedSpaces(spaces, favorites: favorites) { added in
            result.spaces = added
            result.favorites = before
            importData()
        }
    }

    private func importProfiles(_ profiles: [String], data: [String: ProfileData], target: @escaping (String) -> String,
                                options: ImportOptions, summary: ImportSummary,
                                progress: @escaping @MainActor (String) -> Void, completion: @escaping @MainActor (ImportSummary) -> Void) {
        var summary = summary
        guard let first = profiles.first else {
            completion(summary)
            return
        }
        let rest = Array(profiles.dropFirst())
        guard let entry = data[first], !(entry.visits.isEmpty && entry.logins.isEmpty && entry.cookies.isEmpty) else {
            importProfiles(rest, data: data, target: target, options: options, summary: summary, progress: progress, completion: completion)
            return
        }
        progress("Importing \(first)\u{2026}")
        Application.shared.loadProfile(identifier: target(first)) { [weak self] profile in
            guard let self, let profile else {
                self?.importProfiles(rest, data: data, target: target, options: options, summary: summary, progress: progress, completion: completion)
                return
            }
            profile.importHistory(entry.visits.compactMap(Self.visit))
            summary.history += entry.visits.count
            let logins = entry.logins.compactMap(Self.login)
            profile.importLogins(logins) {
                summary.passwords += logins.count
                profile.importCookies(entry.cookies.map(Self.cookie)) { imported in
                    summary.cookies += imported
                    self.importProfiles(rest, data: data, target: target, options: options, summary: summary, progress: progress, completion: completion)
                }
            }
        }
    }

    private static func visit(_ record: VisitRecord) -> ImportedVisit? {
        guard let url = URL(string: record.url) else { return nil }
        let visit = ImportedVisit()
        visit.url = url
        visit.title = record.title
        visit.visitCount = record.visits
        visit.typedCount = record.typed
        visit.lastVisit = record.last
        return visit
    }

    private static func login(_ record: LoginRecord) -> ImportedLogin? {
        guard let url = URL(string: record.url) else { return nil }
        let login = ImportedLogin()
        login.url = url
        login.actionURL = URL(string: record.action)
        login.signonRealm = record.realm
        login.usernameElement = record.usernameElement
        login.username = record.username
        login.passwordElement = record.passwordElement
        login.password = record.password
        login.dateCreated = record.created
        login.dateLastUsed = record.lastUsed
        login.timesUsed = record.timesUsed
        return login
    }

    private static func cookie(_ record: CookieRecord) -> ImportedCookie {
        let cookie = ImportedCookie()
        cookie.name = record.name
        cookie.value = record.value
        cookie.domain = record.domain
        cookie.path = record.path
        cookie.creation = record.created
        cookie.expiration = record.expires
        cookie.lastAccess = record.lastAccess
        cookie.lastUpdate = record.lastUpdate
        cookie.secure = record.secure
        cookie.httpOnly = record.httpOnly
        cookie.sameSite = record.sameSite
        cookie.priority = record.priority
        cookie.sourceScheme = record.sourceScheme
        cookie.sourcePort = record.sourcePort
        cookie.sourceType = record.sourceType
        return cookie
    }
}
