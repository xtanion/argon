import AppKit
import Security

extension Notification.Name {
    static let updaterStateDidChange = Notification.Name("ArgonUpdaterStateDidChange")
}

enum UpdateError: Error, LocalizedError {
    case noArchive
    case unpack
    case untrusted(OSStatus)
    case notNewer
    case install(String)

    var errorDescription: String? {
        switch self {
        case .noArchive: "This release has no update archive for this Mac."
        case .unpack: "The update couldn't be unpacked."
        case .untrusted(let status): "The update isn't signed by the same developer as this copy of Argon (\(status))."
        case .notNewer: "The downloaded app isn't newer than this one."
        case .install(let reason): reason
        }
    }
}

// Downloads the release zip, checks it is signed like the running app, then
// swaps the bundle in place from a helper that outlives Argon and relaunches it.
@MainActor
final class Updater {
    static let shared = Updater()

    enum State {
        case idle
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, Double)
        case preparing(AvailableUpdate)
        case restarting(AvailableUpdate)
        case failed(AvailableUpdate, String)
    }

    private(set) var state: State = .idle {
        didSet { NotificationCenter.default.post(name: .updaterStateDidChange, object: nil) }
    }

    private var download: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    var update: AvailableUpdate? {
        switch state {
        case .idle: nil
        case .available(let u), .downloading(let u, _), .preparing(let u), .restarting(let u), .failed(let u, _): u
        }
    }

    var canInstallInPlace: Bool {
        #if DEBUG
        return false
        #else
        let bundle = Bundle.main.bundleURL
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: bundle.path)
        #endif
    }

    func offer(_ update: AvailableUpdate) {
        switch state {
        case .downloading, .preparing, .restarting:
            return
        case .available(let current), .failed(let current, _):
            if current.version >= update.version { return }
        case .idle:
            break
        }
        state = .available(update)
    }

    func dismiss() {
        download?.cancel()
        download = nil
        state = .idle
    }

    func apply() {
        switch state {
        case .available(let update), .failed(let update, _):
            guard canInstallInPlace, let archive = update.archiveURL else {
                BrowserWindowController.current?.openTab(update.downloadURL ?? update.pageURL)
                return
            }
            start(update, archive: archive)
        case .idle, .downloading, .preparing, .restarting:
            return
        }
    }

    private func start(_ update: AvailableUpdate, archive: URL) {
        state = .downloading(update, 0)
        var request = URLRequest(url: archive)
        request.setValue("Argon", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: request) { location, response, error in
            let staged: Result<URL, Error>
            if let location, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false {
                staged = Result { try Self.stage(location, version: update.version) }
            } else {
                staged = .failure(error ?? UpdateError.noArchive)
            }
            Task { @MainActor in Updater.shared.downloaded(update, result: staged) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard case .downloading(let current, _) = Updater.shared.state, current.version == update.version else { return }
                Updater.shared.state = .downloading(current, fraction)
            }
        }
        download = task
        task.resume()
    }

    private func downloaded(_ update: AvailableUpdate, result: Result<URL, Error>) {
        progressObservation = nil
        download = nil
        switch result {
        case .failure(let error):
            if (error as? URLError)?.code == .cancelled { return }
            state = .failed(update, error.localizedDescription)
        case .success(let zip):
            state = .preparing(update)
            Task.detached(priority: .userInitiated) {
                let result = Result { try Self.unpackAndVerify(zip, version: update.version) }
                await MainActor.run { Updater.shared.verified(update, result: result) }
            }
        }
    }

    private func verified(_ update: AvailableUpdate, result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            state = .failed(update, error.localizedDescription)
        case .success(let app):
            do {
                try Self.launchInstaller(newApp: app)
                state = .restarting(update)
                BrowserWindowController.current?.saveNow()
                Application.shared.quit()
            } catch {
                state = .failed(update, error.localizedDescription)
            }
        }
    }

    nonisolated private static var stagingRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Argon", isDirectory: true)
            .appendingPathComponent("Update", isDirectory: true)
    }

    nonisolated private static func stage(_ location: URL, version: SemanticVersion) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: stagingRoot)
        let directory = stagingRoot.appendingPathComponent(version.description, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent("Argon.zip")
        try fm.moveItem(at: location, to: zip)
        return zip
    }

    nonisolated private static func unpackAndVerify(_ zip: URL, version: SemanticVersion) throws -> URL {
        let directory = zip.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, directory.path]
        try ditto.run()
        ditto.waitUntilExit()
        try? FileManager.default.removeItem(at: zip)
        guard ditto.terminationStatus == 0,
              let name = try FileManager.default.contentsOfDirectory(atPath: directory.path).first(where: { $0.hasSuffix(".app") })
        else { throw UpdateError.unpack }
        let app = directory.appendingPathComponent(name, isDirectory: true)

        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let newVersion = SemanticVersion(shortVersion), newVersion >= version,
              let current = SemanticVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
              newVersion > current
        else { throw UpdateError.notNewer }

        try checkSignature(of: app)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", app.path]
        try? xattr.run()
        xattr.waitUntilExit()
        return app
    }

    // The new bundle must satisfy the running app's designated requirement,
    // which pins the same bundle id and signing certificate.
    nonisolated private static func checkSignature(of app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var status = SecCodeCopySelf([], &selfCode)
        if status == errSecSuccess, let selfCode { status = SecCodeCopyStaticCode(selfCode, [], &selfStatic) }
        if status == errSecSuccess, let selfStatic { status = SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) }
        guard status == errSecSuccess, let requirement else { throw UpdateError.untrusted(status) }

        var newCode: SecStaticCode?
        status = SecStaticCodeCreateWithPath(app as CFURL, [], &newCode)
        guard status == errSecSuccess, let newCode else { throw UpdateError.untrusted(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(newCode, flags, requirement)
        guard status == errSecSuccess else { throw UpdateError.untrusted(status) }
    }

    private static func launchInstaller(newApp: URL) throws {
        let target = Bundle.main.bundleURL
        let backup = target.deletingLastPathComponent().appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-previous.app")
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$4"
        if /bin/mv "$2" "$4"; then
          if /bin/mv "$3" "$2"; then /bin/rm -rf "$4"; else /bin/mv "$4" "$2"; fi
        fi
        /usr/bin/open "$2"
        """
        let arguments = ["/bin/sh", "-c", script, "argon-update", String(getpid()), target.path, newApp.path, backup.path]

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sh", nil, &attributes, &argv, environ)
        guard result == 0 else { throw UpdateError.install("Couldn't start the installer (\(result)).") }
    }
}
