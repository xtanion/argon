import AppKit

// Keeps memory down without the user noticing: background tabs are discarded
// after a while (their snapshot stays in the sidebar and switcher, and showing
// them reloads), tabs are frozen in Low Power Mode, memory pressure discards
// the oldest tabs early, and profiles nobody has used for a while unload.
@MainActor
final class TabSleep {
    static let shared = TabSleep()

    private static let tick: TimeInterval = 60
    private static let freezeAfter: TimeInterval = 5 * 60
    private static let pressureGrace: TimeInterval = 60
    private static let profileIdleAfter: TimeInterval = 30 * 60

    private weak var controller: BrowserWindowController?
    private var timer: Timer?
    private var pressure: DispatchSourceMemoryPressure?
    private var profileLastUsed: [String: Date] = [:]

    func start(controller: BrowserWindowController) {
        self.controller = controller
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { _ in
            MainActor.assumeIsolated { TabSleep.shared.run() }
        }
        timer?.tolerance = 10
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            let event = source.data
            MainActor.assumeIsolated { TabSleep.shared.relieve(critical: event.contains(.critical)) }
        }
        source.activate()
        pressure = source
    }

    func run() {
        guard let controller else { return }
        let now = Date()
        let candidates = sleepable(in: controller)
        if let after = Preferences.sleepTabsAfter {
            for tab in candidates where now.timeIntervalSince(tab.lastViewed) >= after {
                discard(tab)
            }
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            for tab in candidates where now.timeIntervalSince(tab.lastViewed) >= Self.freezeAfter {
                tab.tab?.isFrozen = true
            }
        }
        unloadIdleProfiles(in: controller, now: now)
    }

    // The system is short of memory: discard the oldest background tabs, half
    // of them on a warning and all of them when it is critical.
    private func relieve(critical: Bool) {
        guard let controller else { return }
        let now = Date()
        let oldestFirst = sleepable(in: controller)
            .filter { now.timeIntervalSince($0.lastViewed) >= Self.pressureGrace }
            .sorted { $0.lastViewed < $1.lastViewed }
        let count = critical ? oldestFirst.count : (oldestFirst.count + 1) / 2
        oldestFirst.prefix(count).forEach(discard)
    }

    // Loaded, hidden, not already discarded, and not doing something the user
    // would miss: playing or capturing media, in Picture in Picture, or holding
    // unsent form input.
    private func sleepable(in controller: BrowserWindowController) -> [BrowserTab] {
        var seen = Set<ObjectIdentifier>()
        return controller.spaces.flatMap(\.allTabs).filter { tab in
            guard seen.insert(ObjectIdentifier(tab)).inserted, let page = tab.tab else { return false }
            guard !page.isVisible, !page.isDiscarded else { return false }
            guard let scheme = page.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
            return !(page.isAudible || page.isPlayingMedia || page.isInPictureInPicture || page.isCapturing || page.hasUserEdits)
        }
    }

    private func discard(_ tab: BrowserTab) {
        guard let page = tab.tab else { return }
        if tab.snapshot == nil { tab.captureSnapshot() }
        page.discard()
    }

    // A profile is idle when none of its spaces is active, no Little Argon
    // window uses it, nothing is downloading, and every page it had is closed or
    // discarded. After the idle period its pages close and it unloads.
    private func unloadIdleProfiles(in controller: BrowserWindowController, now: Date) {
        let inLittleWindows = LittleWindowController.profilesInUse
        for identifier in Set(controller.spaces.map(\.profileIdentifier)) {
            let group = controller.spaces.filter { $0.profileIdentifier == identifier }
            guard let profile = group.lazy.compactMap(\.profile).first else {
                profileLastUsed[identifier] = nil
                continue
            }
            let running = group.flatMap(\.allTabs).contains { tab in
                guard let page = tab.tab else { return false }
                return !page.isDiscarded || page.isAudible || page.isCapturing
            }
            let busy = group.contains { $0 === controller.activeSpace }
                || inLittleWindows.contains(identifier)
                || running
                || profile.downloads.contains { $0.state == .inProgress }
            if busy {
                profileLastUsed[identifier] = now
                continue
            }
            let last = profileLastUsed[identifier] ?? now
            profileLastUsed[identifier] = last
            if now.timeIntervalSince(last) >= Self.profileIdleAfter {
                profileLastUsed[identifier] = nil
                controller.unloadProfile(identifier)
            }
        }
    }
}

