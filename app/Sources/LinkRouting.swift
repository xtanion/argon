import AppKit

struct LinkRule: Codable, Equatable, Sendable {
    var id = UUID().uuidString
    var pattern: String
    var spaceID: String
}

enum ExternalLinkDestination: String {
    case littleArgon
    case activeSpace
}

extension Notification.Name {
    static let linkRulesDidChange = Notification.Name("ArgonLinkRulesDidChange")
}

@MainActor
enum LinkRouter {
    private static let rulesKey = "ArgonLinkRules"
    private static let destinationKey = "ArgonExternalLinkDestination"

    static var destination: ExternalLinkDestination {
        get { UserDefaults.standard.string(forKey: destinationKey).flatMap(ExternalLinkDestination.init) ?? .littleArgon }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: destinationKey) }
    }

    private static var cachedRules: [LinkRule]?

    static var rules: [LinkRule] {
        get {
            if let cachedRules { return cachedRules }
            let data = UserDefaults.standard.data(forKey: rulesKey)
            let rules = data.flatMap { try? JSONDecoder().decode([LinkRule].self, from: $0) } ?? []
            cachedRules = rules
            return rules
        }
        set {
            cachedRules = newValue
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: rulesKey) }
            NotificationCenter.default.post(name: .linkRulesDidChange, object: nil)
        }
    }

    static func addRule(pattern: String, spaceID: String) {
        guard let pattern = normalize(pattern) else { return }
        var all = rules.filter { $0.pattern != pattern }
        all.append(LinkRule(pattern: pattern, spaceID: spaceID))
        rules = all
    }

    static func removeRule(id: String) {
        rules = rules.filter { $0.id != id }
    }

    static func rule(for url: URL) -> LinkRule? {
        rules.filter { matches($0.pattern, url) }.max { $0.pattern.count < $1.pattern.count }
    }

    static func hasRule(forHost host: String) -> Bool {
        guard let pattern = normalize(host) else { return false }
        return rules.contains { $0.pattern == pattern }
    }

    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if text.hasPrefix("*.") { text.removeFirst(2) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<cut]) }
        while text.hasSuffix("/") { text.removeLast() }
        guard let authority = text.split(separator: "/").first, !text.contains(" "), !text.contains("*") else { return nil }
        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let host = parts.first, host.contains(".") || host == "localhost" else { return nil }
        if parts.count == 2, Int(parts[1]).map({ (1...65535).contains($0) }) != true { return nil }
        return text
    }

    static func displayHost(of url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func matches(_ pattern: String, _ url: URL) -> Bool {
        guard let host = displayHost(of: url) else { return false }
        let parts = pattern.split(separator: "/", maxSplits: 1)
        let authority = parts[0].split(separator: ":")
        let ruleHost = String(authority[0])
        guard host == ruleHost || host.hasSuffix("." + ruleHost) else { return false }
        if authority.count == 2, url.port.map(String.init) != String(authority[1]) { return false }
        guard parts.count > 1 else { return true }
        let prefix = "/" + parts[1]
        let path = url.path.lowercased()
        return path == prefix || path.hasPrefix(prefix + "/")
    }
}
