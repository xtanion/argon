import AppKit
import Carbon.HIToolbox

@MainActor
enum LittleArgon {
    private static let hotKeyKey = "ArgonLittleHotKey"
    private static let modifierClickKey = "ArgonLittleModifierClick"
    private static let skipProfileWarningKey = "ArgonLittleSkipProfileWarning"
    private static let frameKey = "ArgonLittleFrame"

    static var hotKeyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: hotKeyKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: hotKeyKey)
            updateHotKey()
        }
    }

    static var modifierClickEnabled: Bool {
        get { UserDefaults.standard.object(forKey: modifierClickKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: modifierClickKey) }
    }

    static var skipProfileWarning: Bool {
        get { UserDefaults.standard.bool(forKey: skipProfileWarningKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipProfileWarningKey) }
    }

    static var lastFrame: NSRect? {
        get { UserDefaults.standard.string(forKey: frameKey).map(NSRectFromString).flatMap { $0.width > 0 ? $0 : nil } }
        set { UserDefaults.standard.set(newValue.map(NSStringFromRect), forKey: frameKey) }
    }

    static var modifierClickHeld: Bool {
        modifierClickEnabled && NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.command, .option])
    }

    static func updateHotKey() {
        if hotKeyEnabled {
            GlobalHotKey.shared.register(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey)) {
                guard let browser = BrowserWindowController.current else { return }
                LittleLauncher.toggle(browser: browser)
            }
        } else {
            GlobalHotKey.shared.unregister()
        }
    }
}

@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        unregister()
        self.onPress = onPress
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { GlobalHotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4152_4C41), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        onPress = nil
    }
}

// The ⌥⌘N search: a command bar floating over whatever app is in front. What it opens goes to Little Argon.
@MainActor
final class LittleLauncher: NSObject, CommandBarHost, NSWindowDelegate {
    private static var current: LittleLauncher?

    static func toggle(browser: BrowserWindowController) {
        if let current {
            current.dismissCommandBar()
            return
        }
        guard browser.activeSpace.profile != nil else { return }
        let launcher = LittleLauncher(browser: browser)
        current = launcher
        launcher.present()
    }

    private let panel: LauncherPanel
    private let bar: CommandBarView
    private weak var browser: BrowserWindowController?
    private let space: Space

    private init(browser: BrowserWindowController) {
        self.browser = browser
        space = browser.activeSpace
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        panel = LauncherPanel(contentRect: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bar = CommandBarView(mode: .newTab, initialText: "", frameColor: space.frameColor)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: space.frameColor.isDarkFrame ? .darkAqua : .aqua)
        panel.delegate = self
        bar.blursBehindWindow = true
        bar.controller = self
        panel.contentView = bar
    }

    private func present() {
        panel.makeKeyAndOrderFront(nil)
        bar.activate()
    }

    func windowDidResignKey(_ notification: Notification) { dismissCommandBar() }

    var commandBarProfile: Profile? { space.profile }
    var activeTab: BrowserTab? { nil }

    func tabsInRecentOrder() -> [(tab: BrowserTab, space: Space)] { browser?.tabsInRecentOrder() ?? [] }

    func commandBar(_ bar: CommandBarView, open url: URL) {
        dismissCommandBar()
        guard let browser, let profile = space.profile else { return }
        LittleWindowController.open(url, space: browser.liveSpace(space) ?? browser.activeSpace, profile: profile, browser: browser)
    }

    func commandBar(_ bar: CommandBarView, switchTo tab: BrowserTab) {
        dismissCommandBar()
        browser?.select(tab)
        browser?.bringToFront()
    }

    func commandBarOpenBlank() { dismissCommandBar() }

    func dismissCommandBar() {
        guard Self.current === self else { return }
        Self.current = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
