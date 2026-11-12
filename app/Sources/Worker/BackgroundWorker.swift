import AppKit

enum JobTrigger: Sendable {
    case scheduled
    case manual
}

struct JobContext: Sendable {
    let trigger: JobTrigger
    let lastSuccess: Date?
}

// Errors that know when the work may be retried, such as a rate limit reset.
protocol RetryAfterError: Error {
    var retryAfter: Date? { get }
}

// A unit of background work. run executes off the main actor; deliver and fail run on it.
protocol BackgroundJob: Sendable {
    associatedtype Output: Sendable

    var identifier: String { get }
    var interval: TimeInterval { get }
    var runsAtLaunch: Bool { get }
    @MainActor var isEnabled: Bool { get }

    func run(_ context: JobContext) async throws -> Output
    @MainActor func deliver(_ output: Output, context: JobContext)
    @MainActor func fail(_ error: Error, context: JobContext)
}

extension BackgroundJob {
    var runsAtLaunch: Bool { false }
    @MainActor var isEnabled: Bool { true }
    @MainActor func fail(_ error: Error, context: JobContext) {}
}

struct JobRecord: Codable, Sendable {
    var lastRun: Date?
    var lastSuccess: Date?
    var nextRun: Date?
    var lastError: String?
    var failures = 0
}

@MainActor
final class BackgroundWorker {
    static let shared = BackgroundWorker()

    private struct Entry {
        let interval: TimeInterval
        let runsAtLaunch: Bool
        let isEnabled: @MainActor () -> Bool
        let perform: @MainActor (JobContext) async -> Error?
    }

    private static let defaultsPrefix = "ArgonWorker."
    private static let coalescingWindow: TimeInterval = 60
    private static let minimumBackoff: TimeInterval = 5 * 60

    var launchDelay: TimeInterval = 20
    var wakeDelay: TimeInterval = 30

    private var entries: [String: Entry] = [:]
    private var due: [String: Date] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var manualRequests: Set<String> = []
    private var timer: Timer?
    private var started = false
    private var asleep = false

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundWorker.shared.willSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundWorker.shared.didWake() }
        }
    }

    func register<Job: BackgroundJob>(_ job: Job) {
        entries[job.identifier] = Entry(
            interval: job.interval,
            runsAtLaunch: job.runsAtLaunch,
            isEnabled: { job.isEnabled },
            perform: { context in
                let result = await Task.detached(priority: .utility) { try await job.run(context) }.result
                switch result {
                case .success(let output):
                    job.deliver(output, context: context)
                    return nil
                case .failure(let error):
                    job.fail(error, context: context)
                    return error
                }
            }
        )
        if started { due[job.identifier] = initialDue(for: job.identifier, launch: Date().addingTimeInterval(launchDelay)) }
        arm()
    }

    func start() {
        guard !started else { return }
        started = true
        let launch = Date().addingTimeInterval(launchDelay)
        for id in entries.keys { due[id] = initialDue(for: id, launch: launch) }
        arm()
    }

    func runNow(_ identifier: String) {
        guard entries[identifier] != nil else { return }
        manualRequests.insert(identifier)
        if running[identifier] == nil { launch(identifier) }
    }

    // Call after a job's isEnabled changes so the timer picks it up or drops it.
    func reschedule() { arm() }

    func record(for identifier: String) -> JobRecord {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsPrefix + identifier),
              let record = try? JSONDecoder().decode(JobRecord.self, from: data) else { return JobRecord() }
        return record
    }

    private func save(_ record: JobRecord, for identifier: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsPrefix + identifier)
    }

    private func initialDue(for identifier: String, launch: Date) -> Date {
        guard let entry = entries[identifier] else { return launch }
        let record = record(for: identifier)
        if entry.runsAtLaunch && record.failures == 0 { return launch }
        let scheduled = [record.nextRun, record.lastRun?.addingTimeInterval(entry.interval)].compactMap { $0 }.min()
        return max(launch, scheduled ?? launch)
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        guard started, !asleep else { return }
        let pending = due.filter { running[$0.key] == nil && entries[$0.key]?.isEnabled() == true }
        guard let next = pending.values.min() else { return }
        let delay = max(1, next.timeIntervalSinceNow)
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { BackgroundWorker.shared.fire() }
        }
        timer.tolerance = min(Self.coalescingWindow, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        timer = nil
        let horizon = Date().addingTimeInterval(Self.coalescingWindow)
        for (id, date) in due where date <= horizon && running[id] == nil && entries[id]?.isEnabled() == true {
            launch(id)
        }
        arm()
    }

    private func launch(_ identifier: String) {
        guard let entry = entries[identifier] else { return }
        let trigger: JobTrigger = manualRequests.remove(identifier) != nil ? .manual : .scheduled
        var record = record(for: identifier)
        let context = JobContext(trigger: trigger, lastSuccess: record.lastSuccess)
        record.lastRun = Date()
        save(record, for: identifier)
        running[identifier] = Task { @MainActor in
            let error = await entry.perform(context)
            self.finish(identifier, interval: entry.interval, error: error)
        }
        arm()
    }

    private func finish(_ identifier: String, interval: TimeInterval, error: Error?) {
        running[identifier] = nil
        var record = record(for: identifier)
        let now = Date()
        if let error {
            record.failures += 1
            record.lastError = String(describing: error)
            let backoff = min(interval, Self.minimumBackoff * pow(2, Double(record.failures - 1)))
            let retry = (error as? RetryAfterError)?.retryAfter ?? now.addingTimeInterval(backoff)
            record.nextRun = max(retry, now.addingTimeInterval(Self.coalescingWindow))
        } else {
            record.failures = 0
            record.lastError = nil
            record.lastSuccess = now
            record.nextRun = now.addingTimeInterval(interval)
        }
        save(record, for: identifier)
        due[identifier] = record.nextRun
        if manualRequests.contains(identifier) { launch(identifier) }
        arm()
    }

    private func willSleep() {
        asleep = true
        arm()
    }

    // Timers stall during sleep; overdue jobs wait a moment after wake for the network to return.
    private func didWake() {
        asleep = false
        let earliest = Date().addingTimeInterval(wakeDelay)
        for (id, date) in due where date < earliest { due[id] = earliest }
        arm()
    }
}
