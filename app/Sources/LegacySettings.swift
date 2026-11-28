import Foundation

// Settings saved before the rename from Helium live under the old bundle id.
enum LegacySettings {
    private static let legacyDomain = "net.imput.helium.native"
    private static let doneKey = "ArgonMigratedHeliumSettings"
    private static let keys = [
        ("HeliumBrowserState", "ArgonBrowserState"),
        ("HeliumSidebarWidth", "ArgonSidebarWidth"),
        ("NSWindow Frame HeliumBrowserWindow", "NSWindow Frame ArgonBrowserWindow"),
    ]

    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let legacy = UserDefaults(suiteName: legacyDomain) {
            for (old, new) in keys where defaults.object(forKey: new) == nil {
                if let value = legacy.object(forKey: old) {
                    defaults.set(value, forKey: new)
                }
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
