import AppKit

@MainActor
enum Preferences {
    private static let warnBeforeQuittingKey = "ArgonWarnBeforeQuitting"
    private static let showSidebarOnLaunchKey = "ArgonShowSidebarOnLaunch"
    private static let screenshotFolderKey = "ArgonScreenshotFolder"
    private static let autoPictureInPictureKey = "ArgonAutoPictureInPicture"

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
