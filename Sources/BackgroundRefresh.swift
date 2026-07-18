import Foundation
import OSLog
#if canImport(WatchKit)
import WatchKit
#endif

/// When the app asks watchOS to wake it, and which metrics are worth being woken for.
///
/// **Background refresh is an optimization, never the source of truth** (PRD: "Do not assume
/// background refresh runs on schedule; recompute from elapsed time on launch"). Everything
/// time-derived — hunger, care mistakes, sickness, death, the battle allowance — already recomputes
/// from an injected clock against a saved marker, so a wake that never happens costs nothing but
/// freshness. What a wake actually buys is the one thing elapsed time cannot reconstruct: HEALTH
/// DATA, which is only ever read for the day it is read on.
enum BackgroundRefreshSchedule {
    /// How long after one refresh the next is asked for: thirty minutes.
    ///
    /// A request, not a promise — watchOS budgets these and will hand out fewer. Half an hour is
    /// chosen against the slowest thing a refresh can miss: one unit of hunger takes four hours
    /// (`HungerClock.secondsPerHungerUnit`), so even a heavily throttled schedule keeps the screen
    /// and the complication inside a fraction of the smallest step the game can take.
    static let interval: TimeInterval = 30 * 60

    /// The metrics worth a background wake: steps and active calories.
    ///
    /// Not all four. Sleep arrives in one block once a night and exercise minutes trail the other
    /// two, so observing them would spend wakes on data that the next steps update would have
    /// brought in anyway — and every metric observed is another chance for watchOS to throttle the
    /// app. These two are also the two that move all day, which is what makes them worth watching.
    static let observedMetrics: [HealthMetric] = [.steps, .activeEnergy]

    /// The moment the next wake is requested for.
    static func next(after now: Date) -> Date {
        now.addingTimeInterval(interval)
    }
}

/// Asking watchOS for a background wake, behind a protocol so a test can assert that one was asked
/// for without a real `WKApplication` — nothing in a test bundle can schedule a real background task
/// or wait out half an hour for it.
@MainActor
protocol BackgroundRefreshScheduling {
    func scheduleRefresh(at date: Date)
}

/// Watching for new health samples, behind a protocol for the same reason `HealthAuthorizing` is
/// one: the Simulator has no health data, so a test against a live `HKObserverQuery` proves nothing.
@MainActor
protocol HealthUpdateObserving {
    /// Starts watching `metrics` and calls `onUpdate` whenever new samples land, background delivery
    /// included. Called once per launch; calling it again replaces nothing.
    func startObserving(_ metrics: [HealthMetric], onUpdate: @escaping () -> Void)
}

/// The real scheduler: `WKApplication.scheduleBackgroundRefresh`.
struct WatchBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "background")

    func scheduleRefresh(at date: Date) {
        #if canImport(WatchKit)
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: nil) { error in
            if let error {
                // Not fatal and not worth a screen: a refused schedule means the next foregrounding
                // does the work instead, which is exactly what the elapsed-time recompute is for.
                Self.log.error("Could not schedule a background refresh: \(String(describing: error))")
            }
        }
        #endif
    }
}

/// Drives the game forward while the app is not in front: a repeating background refresh, plus
/// HealthKit observers that ask for one as soon as new steps or calories are recorded.
///
/// Holds the SAME `MainScreenModel` the screen does — see `GameSession`. A second model would open a
/// second `GameStore` on the same file and the two would credit energy against separate in-memory
/// ledgers, which is how the same steps get paid for twice.
///
/// Every path here ends in `MainScreenModel.refresh()`, the one that already credits energy, audits
/// care mistakes, settles sickness and death, and hatches or evolves. So a background wake and a
/// foregrounding do exactly the same work — there is no second, weaker version of the rules that
/// only runs in the background and could drift from the real one.
@MainActor
final class BackgroundRefreshCoordinator {
    let model: MainScreenModel

    private let scheduler: BackgroundRefreshScheduling
    private let observer: HealthUpdateObserving
    private let now: () -> Date

    /// The refresh an observer update started, while it is still running.
    ///
    /// Held only so a test can await it. An observer callback is fire-and-forget in the app — it
    /// arrives on HealthKit's own schedule and nothing waits on it — so without this there is
    /// nothing to tell a test when the work an update kicked off has actually finished.
    private(set) var pendingHealthRefresh: Task<Void, Never>?

    private var isObserving = false

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "background")

    /// - Parameters:
    ///   - scheduler: nil for the real `WKApplication` one. Nil rather than a default value because
    ///     a default argument is evaluated in the CALLER's context, which is not this actor — the
    ///     real ones are `@MainActor`, so they can only be built inside this body.
    ///   - observer: nil for the real HealthKit one, for the same reason.
    init(model: MainScreenModel,
         scheduler: BackgroundRefreshScheduling? = nil,
         observer: HealthUpdateObserving? = nil,
         now: @escaping () -> Date = Date.init) {
        self.model = model
        self.scheduler = scheduler ?? WatchBackgroundRefreshScheduler()
        self.observer = observer ?? HealthKitUpdateObserver()
        self.now = now
    }

    /// Asks for the first background wake. Called at launch, before anything else — scheduling
    /// needs no permission from anyone.
    func begin() {
        scheduleNext()
    }

    /// Starts watching for new steps and calories.
    ///
    /// Separate from `begin()` and called LATER, once the user has answered the health prompt.
    /// Registering an observer before that fails with "Authorization not determined" — observed in
    /// the Simulator, where a first launch logged exactly that for both metrics — and a failed
    /// observer is not retried, so a first-run app would go its whole life unwatched.
    ///
    /// Guarded rather than idempotent by luck: this is driven by a `.task` on the screen behind the
    /// authorization gate, and that can run again on a later appearance.
    func beginObservingHealthUpdates() {
        guard !isObserving else { return }
        isObserving = true
        observer.startObserving(BackgroundRefreshSchedule.observedMetrics) { [weak self] in
            self?.healthDataChanged()
        }
    }

    /// Runs one background refresh and asks for the next one.
    ///
    /// The reschedule comes AFTER the refresh and is unconditional: a chain of wakes that only
    /// re-arms itself on success would stop dead at the first read that failed, and nothing would
    /// ever wake the app again until the user opened it.
    func performRefresh() async {
        await model.refresh()
        scheduleNext()
    }

    /// New steps or calories have been recorded, so credit them without waiting for the next wake.
    ///
    /// Deliberately does NOT reschedule: an observer that re-armed the timer would push the next
    /// guaranteed wake half an hour further out every time the user took a walk, so a busy day would
    /// starve the schedule of exactly the wake it was there to guarantee.
    private func healthDataChanged() {
        Self.log.info("Health data changed; refreshing")
        pendingHealthRefresh = Task { await model.refresh() }
    }

    private func scheduleNext() {
        scheduler.scheduleRefresh(at: BackgroundRefreshSchedule.next(after: now()))
    }
}
