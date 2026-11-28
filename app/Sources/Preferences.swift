import AppKit

@MainActor
enum Preferences {
    private static let warnBeforeQuittingKey = "StoneWarnBeforeQuitting"
    private static let showSidebarOnLaunchKey = "StoneShowSidebarOnLaunch"
    private static let screenshotFolderKey = "StoneScreenshotFolder"
    private static let autoPictureInPictureKey = "StoneAutoPictureInPicture"
    private static let checkForUpdatesKey = "StoneCheckForUpdates"
    private static let sidebarOnRightKey = "StoneSidebarOnRight"
    private static let archiveAfterKey = "StoneArchiveAfterHours"
    private static let framelessKey = "StoneFrameless"

    static var frameless: Bool {
        get { UserDefaults.standard.bool(forKey: framelessKey) }
        set {
            guard newValue != frameless else { return }
            UserDefaults.standard.set(newValue, forKey: framelessKey)
            NotificationCenter.default.post(name: .framelessDidChange, object: nil)
        }
    }

    static let archiveChoices: [(hours: Int, title: String)] = [(12, "12 Hours"), (24, "24 Hours"), (168, "7 Days"), (720, "30 Days"), (0, "Never")]

    static var archiveAfterHours: Int {
        get { UserDefaults.standard.object(forKey: archiveAfterKey) as? Int ?? 12 }
        set { UserDefaults.standard.set(newValue, forKey: archiveAfterKey) }
    }

    static var archiveAfter: TimeInterval? {
        archiveAfterHours > 0 ? TimeInterval(archiveAfterHours) * 60 * 60 : nil
    }

    static let sleepChoices: [(minutes: Int, title: String)] = [(15, "15 Minutes"), (30, "30 Minutes"), (60, "1 Hour"), (120, "2 Hours"), (0, "Never")]

    static var sleepTabsAfterMinutes: Int {
        get { UserDefaults.standard.object(forKey: "StoneSleepTabsAfterMinutes") as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: "StoneSleepTabsAfterMinutes") }
    }

    static var sleepTabsAfter: TimeInterval? {
        sleepTabsAfterMinutes > 0 ? TimeInterval(sleepTabsAfterMinutes) * 60 : nil
    }

    static var sidebarOnRight: Bool {
        get { UserDefaults.standard.bool(forKey: sidebarOnRightKey) }
        set {
            guard newValue != sidebarOnRight else { return }
            UserDefaults.standard.set(newValue, forKey: sidebarOnRightKey)
            NotificationCenter.default.post(name: .sidebarSideDidChange, object: nil)
        }
    }

    static var appIcon: AppIconStyle {
        get { UserDefaults.standard.string(forKey: "StoneAppIcon").flatMap(AppIconStyle.init(rawValue:)) ?? .blue }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "StoneAppIcon") }
    }

    static var checkForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: checkForUpdatesKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: checkForUpdatesKey)
            BackgroundWorker.shared.reschedule()
        }
    }

    static var autoPictureInPicture: Bool {
        get { UserDefaults.standard.object(forKey: autoPictureInPictureKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoPictureInPictureKey) }
    }

    static var warnBeforeQuitting: Bool {
        get { UserDefaults.standard.object(forKey: warnBeforeQuittingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: warnBeforeQuittingKey) }
    }

    static var showSidebarOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: showSidebarOnLaunchKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showSidebarOnLaunchKey) }
    }

    static var defaultScreenshotFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var screenshotFolder: URL {
        get {
            guard let path = UserDefaults.standard.string(forKey: screenshotFolderKey) else { return defaultScreenshotFolder }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return defaultScreenshotFolder
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if newValue.standardizedFileURL == defaultScreenshotFolder.standardizedFileURL {
                UserDefaults.standard.removeObject(forKey: screenshotFolderKey)
            } else {
                UserDefaults.standard.set(newValue.path, forKey: screenshotFolderKey)
            }
        }
    }
}

extension Notification.Name {
    static let sidebarSideDidChange = Notification.Name("StoneSidebarSideDidChange")
    static let framelessDidChange = Notification.Name("StoneFramelessDidChange")
}

@MainActor
enum DefaultBrowser {
    private static let probe = URL(string: "https://example.com")!

    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
            || Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    // macOS asks the user to confirm each scheme; completion runs once both answers are in.
    static func makeDefault(completion: @escaping @MainActor () -> Void) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { _ in
                DispatchQueue.main.async { completion() }
            }
        }
    }
}

// The first Command-Q shows a hint; a second one within the window quits.
@MainActor
enum QuitGuard {
    private static let window: CFTimeInterval = 2
    private static var armedAt: CFTimeInterval = 0

    static func requestQuit() {
        let event = NSApp.currentEvent
        let fromKeyboard = event?.type == .keyDown
        guard Preferences.warnBeforeQuitting, fromKeyboard, let controller = BrowserWindowController.current,
              controller.window?.isVisible == true else {
            Application.shared.quit()
            return
        }
        if event?.isARepeat == true { return }
        let now = CACurrentMediaTime()
        if now - armedAt < window {
            armedAt = 0
            Application.shared.quit()
            return
        }
        armedAt = now
        controller.showQuitHint(duration: window)
    }
}
