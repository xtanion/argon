import Foundation

// Settings and app data saved before the rename from Argon live under the old
// bundle id. Their keys used the Argon prefix; copy them across once.
enum LegacySettings {
    private static let legacyDomain = "dev.argon.browser"
    private static let doneKey = "StoneMigratedArgonSettings"

    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let legacy = defaults.persistentDomain(forName: legacyDomain) {
            for (key, value) in legacy {
                let renamed = key.replacingOccurrences(of: "Argon", with: "Stone")
                if defaults.object(forKey: renamed) == nil {
                    let moved = (value as? String).map { $0.replacingOccurrences(of: "Argon", with: "Stone") } ?? value
                    defaults.set(moved, forKey: renamed)
                }
            }
        }
        copyApplicationSupport()
        defaults.set(true, forKey: doneKey)
    }

    private static func copyApplicationSupport() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundle = Bundle.main.bundleIdentifier else { return }
        let old = support.appendingPathComponent(legacyDomain, isDirectory: true)
        let new = support.appendingPathComponent(bundle, isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.copyItem(at: old, to: new)
    }
}
