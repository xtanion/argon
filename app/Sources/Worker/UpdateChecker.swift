import AppKit

struct AvailableUpdate: Sendable {
    let version: SemanticVersion
    let pageURL: URL
    let downloadURL: URL?
    let archiveURL: URL?
}

struct UpdateCheckJob: BackgroundJob {
    static let jobIdentifier = "updates"
    static let repository = "xtanion/argon"

    private struct Release: Decodable, Sendable {
        let tagName: String
        let htmlUrl: URL
        let draft: Bool
        let assets: [Asset]
    }

    private struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadUrl: URL
    }

    var identifier: String { Self.jobIdentifier }
    let interval: TimeInterval = 4 * 60 * 60
    let runsAtLaunch = true
    let currentVersion: SemanticVersion?

    init(currentVersion: SemanticVersion? = SemanticVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) {
        self.currentVersion = currentVersion
    }

    @MainActor var isEnabled: Bool { Preferences.checkForUpdates }

    func run(_ context: JobContext) async throws -> AvailableUpdate? {
        let releases = try await GitHubClient.shared.get("/repos/\(Self.repository)/releases",
                                                         query: [URLQueryItem(name: "per_page", value: "30")],
                                                         as: [Release].self)
        let candidates = releases.compactMap { release -> (SemanticVersion, Release)? in
            guard !release.draft, let version = SemanticVersion(release.tagName) else { return nil }
            return (version, release)
        }
        guard let (version, release) = candidates.max(by: { $0.0 < $1.0 }),
              currentVersion.map({ version > $0 }) ?? true else { return nil }
        return AvailableUpdate(version: version, pageURL: release.htmlUrl,
                               downloadURL: Self.asset("dmg", in: release.assets), archiveURL: Self.asset("zip", in: release.assets))
    }

    private static func asset(_ suffix: String, in assets: [Asset]) -> URL? {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return assets.first { $0.name.hasSuffix("-\(architecture).\(suffix)") }?.browserDownloadUrl
    }

    @MainActor func deliver(_ update: AvailableUpdate?, context: JobContext) {
        UpdatePrompt.present(update, manual: context.trigger == .manual)
    }

    @MainActor func fail(_ error: Error, context: JobContext) {
        guard context.trigger == .manual else { return }
        UpdatePrompt.showFailure(error)
    }
}

@MainActor
enum UpdatePrompt {
    private static let skippedVersionKey = "ArgonUpdateSkippedVersion"

    static func checkNow() {
        BrowserWindowController.current?.showToast(ToastView(message: "Checking for Updates\u{2026}", icon: "arrow.triangle.2.circlepath", duration: 10))
        BackgroundWorker.shared.runNow(UpdateCheckJob.jobIdentifier)
    }

    static func present(_ update: AvailableUpdate?, manual: Bool) {
        if let update, UserDefaults.standard.string(forKey: skippedVersionKey) != update.version.description || manual {
            Updater.shared.offer(update)
        }
        guard manual, let controller = BrowserWindowController.current, controller.window?.isVisible == true else { return }
        guard let update else {
            let version = UpdateCheckJob().currentVersion.map { " \($0)" } ?? ""
            controller.showToast(ToastView(message: "You're up to date", icon: "checkmark.circle", duration: 3)
                .withToolTip("Argon\(version) is the newest version."))
            return
        }
        let actions = [
            ToastAction(title: "Later") { _ in },
            ToastAction(title: "Update", isPrimary: true) { _ in Updater.shared.apply() },
        ]
        controller.showToast(ToastView(message: "Argon \(update.version) is available", icon: "arrow.down.circle",
                                       actions: actions, duration: 8))
    }

    static func skip(_ update: AvailableUpdate) {
        UserDefaults.standard.set(update.version.description, forKey: skippedVersionKey)
        Updater.shared.dismiss()
    }

    static func showFailure(_ error: Error) {
        let message = (error as? GitHubError)?.isRateLimit == true ? "Update check is rate limited" : "Couldn't check for updates"
        BrowserWindowController.current?.showToast(ToastView(message: message, icon: "exclamationmark.circle", duration: 4)
            .withToolTip(error.localizedDescription))
    }
}

private extension GitHubError {
    var isRateLimit: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

private extension NSView {
    func withToolTip(_ text: String) -> Self {
        toolTip = text
        return self
    }
}
