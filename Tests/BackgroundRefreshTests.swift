import Foundation
import XCTest

@testable import DigiVPet

/// US-033 — keeping the game running while nobody is looking.
///
/// Two layers, and the second is the one that matters:
/// - `BackgroundRefreshCoordinatorTests` — the wake is scheduled, re-scheduled, and the observers
///   are registered for the right metrics; an observer update credits without a foregrounding.
/// - `ClosedAppRecomputeTests` — the app is SHUT for 48 hours and no background wake ever runs, and
///   the state it comes back to still matches the state it would have reached had it been open the
///   whole time. That is the acceptance criterion background refresh must never be trusted for:
///   watchOS grants wakes at its own discretion, so every one of them has to be an optimization.
///
/// The clock is injected and MOVED, never waited on. Nothing here sleeps.

// MARK: - Doubles

/// Records what was asked of watchOS instead of asking it. No test bundle can schedule a real
/// background task, let alone wait half an hour for it to fire.
@MainActor
private final class SpyScheduler: BackgroundRefreshScheduling {
    private(set) var requestedDates: [Date] = []

    func scheduleRefresh(at date: Date) {
        requestedDates.append(date)
    }
}

/// Stands in for `HKObserverQuery`: records which metrics were watched, and lets a test fire the
/// update HealthKit would have delivered. The Simulator has no health data, so a test against a
/// live observer would sit there proving nothing.
@MainActor
private final class SpyObserver: HealthUpdateObserving {
    private(set) var observedMetrics: [HealthMetric] = []
    private var onUpdate: (() -> Void)?

    private(set) var startCount = 0

    func startObserving(_ metrics: [HealthMetric], onUpdate: @escaping () -> Void) {
        startCount += 1
        observedMetrics = metrics
        self.onUpdate = onUpdate
    }

    /// Delivers the update HealthKit would have.
    func deliverUpdate() {
        onUpdate?()
    }
}

private final class EmptyBackgroundSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptyBackgroundSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// Steps recorded on whatever local day the read asks about, so a read at hour 0 and a read two days
/// later both come back with a real number rather than the fixture ageing out of the window.
///
/// `steps` is settable because crediting is a DELTA (US-014): re-reading the same total credits
/// nothing, so a test that wants to see new energy has to record new steps, exactly as a user would.
private final class DailyStepFetcher: HealthSampleFetching, @unchecked Sendable {
    var steps: Double

    init(steps: Double) {
        self.steps = steps
    }

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        guard metric == .steps else { return [] }
        let start = interval.start.addingTimeInterval(60 * 60)
        return [HealthSample(start: start, end: start.addingTimeInterval(60), value: steps)]
    }
}

// MARK: - A shared fixture game

/// One saved game on disk, one model over it, and a clock the test moves by hand.
@MainActor
private struct Fixture {
    let model: MainScreenModel
    let store: GameStore
    let state: GameState

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    /// Mid-morning: the fallback sleep window is 22:00-07:00, so the Digimon starts awake.
    static let start = date("2026-07-17 10:00")

    /// A Child with nowhere to evolve to, so nothing moves between the two runs for a reason that
    /// has nothing to do with elapsed time.
    static func graph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama"),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon")
        ])
    }

    /// The same game with somewhere to go: a Baby I that grows up on very little energy.
    static func evolvingGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama"),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Agumon",
                          // `requiredEnergy` is not optional off a hatched node — nil means "no
                          // dominant-type gate" and is only ever legal on a Digitama's hatch edge.
                          // Strength, because steps are what this fixture's health data records.
                          evolutions: [EvolutionEdge(to: "grown", requiredEnergy: .strength,
                                                     minEnergy: 1, maxCareMistakes: 99)]),
            EvolutionNode(id: "grown", displayName: "Grown", stage: .child, spriteFile: "Greymon")
        ])
    }

    /// - Parameter clock: read on every call, so a test moves time simply by assigning to its box.
    static func make(directory: URL,
                     name: String,
                     graph: EvolutionGraph? = nil,
                     fetcher: HealthSampleFetching = EmptyBackgroundSampleFetcher(),
                     clock: @escaping () -> Date) throws -> Fixture {
        let store = try GameStore(url: directory.appendingPathComponent("\(name).store"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: start)
        state.stage = .child
        // Every time-derived marker starts at the same instant in both runs, so the only thing that
        // can differ between them is how often anybody looked.
        state.birthDate = start
        state.stageEnteredDate = start
        state.hungerUpdatedAt = start
        state.healthDataLastSeen = start
        try store.save()

        let model = MainScreenModel(
            makeStore: { store },
            // Defaulted here rather than in the signature: a default argument is evaluated in the
            // caller's context, which is not this actor.
            graph: graph ?? self.graph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: fetcher, calendar: calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptyBackgroundSleepFetcher(),
                                                  calendar: calendar)
            ),
            calendar: calendar,
            now: clock,
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.01
        )
        return Fixture(model: model, store: store, state: state)
    }
}

/// The fields that must not depend on how often the app was opened.
///
/// `sickSince` and `diedAt` are deliberately absent — they record WHEN THE APP NOTICED, not when the
/// state became due, and `testAnIllnessThatBeganWhileClosedIsDatedFromTheReopen` pins that
/// separately rather than leaving it unstated.
private struct ElapsedTimeState: Equatable, CustomStringConvertible {
    var digimonId: String
    var stage: Stage
    var hunger: Int
    var hungerUpdatedAt: Date?
    var careMistakeCount: Int
    var starvationMistakesCharged: Int
    var healthDataLastSeen: Date?
    var healthStatus: HealthStatus
    var stageEnergy: EnergyTotals
    var lifetimeEnergy: EnergyTotals
    var battlesFoughtToday: Int

    @MainActor
    init(_ state: GameState, lifetimeEnergy: EnergyTotals, now: Date, calendar: Calendar) {
        digimonId = state.currentDigimonId
        stage = state.stage
        hunger = state.hunger
        hungerUpdatedAt = state.hungerUpdatedAt
        careMistakeCount = state.careMistakeCount
        starvationMistakesCharged = state.starvationMistakesCharged
        healthDataLastSeen = state.healthDataLastSeen
        healthStatus = state.healthStatus
        stageEnergy = state.stageEnergy
        // Off the PROFILE since US-123, and passed in for that reason: it is the player's total,
        // not this Digimon's, so the state cannot answer for it.
        self.lifetimeEnergy = lifetimeEnergy
        battlesFoughtToday = state.battlesFought(now: now, calendar: calendar)
    }

    var description: String {
        """
        \(digimonId) (\(stage.rawValue)) hunger \(hunger) @ \(String(describing: hungerUpdatedAt)), \
        mistakes \(careMistakeCount) (starvation \(starvationMistakesCharged)), \
        data last seen \(String(describing: healthDataLastSeen)), \(healthStatus), \
        stage energy \(stageEnergy.total), lifetime \(lifetimeEnergy.total), \
        battles today \(battlesFoughtToday)
        """
    }
}

// MARK: - Scheduling and observing

@MainActor
final class BackgroundRefreshCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var currentTime = Fixture.start

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        currentTime = Fixture.start
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeCoordinator(
        name: String = "Background",
        fetcher: HealthSampleFetching = EmptyBackgroundSampleFetcher()
    ) throws -> (BackgroundRefreshCoordinator, SpyScheduler, SpyObserver, Fixture) {
        let fixture = try Fixture.make(directory: directory, name: name, fetcher: fetcher,
                                       clock: { [weak self] in self?.currentTime ?? Fixture.start })
        let scheduler = SpyScheduler()
        let observer = SpyObserver()
        let coordinator = BackgroundRefreshCoordinator(
            model: fixture.model,
            scheduler: scheduler,
            observer: observer,
            now: { [weak self] in self?.currentTime ?? Fixture.start }
        )
        return (coordinator, scheduler, observer, fixture)
    }

    /// AC1: launching asks watchOS for a wake, at the interval this app runs on.
    func testLaunchingSchedulesTheFirstBackgroundRefresh() throws {
        let (coordinator, scheduler, _, _) = try makeCoordinator()

        coordinator.begin()

        XCTAssertEqual(scheduler.requestedDates,
                       [currentTime.addingTimeInterval(BackgroundRefreshSchedule.interval)])
    }

    /// AC1: each wake asks for the next one. A chain that stopped re-arming itself would run exactly
    /// once per launch, which looks identical to working for the first half hour.
    func testHandlingAWakeAsksForTheNextOne() async throws {
        let (coordinator, scheduler, _, fixture) = try makeCoordinator()
        await fixture.model.start()
        coordinator.begin()

        currentTime = Fixture.start.addingTimeInterval(BackgroundRefreshSchedule.interval)
        await coordinator.performRefresh()

        XCTAssertEqual(scheduler.requestedDates.count, 2)
        XCTAssertEqual(scheduler.requestedDates.last,
                       currentTime.addingTimeInterval(BackgroundRefreshSchedule.interval))
    }

    /// AC1: the wake really updates the game — it runs the same `refresh()` a foregrounding does, so
    /// hunger accrued while the app was away is charged without anyone opening it.
    func testAWakeAdvancesTheGameWithoutTheAppBeingOpened() async throws {
        let (coordinator, _, _, fixture) = try makeCoordinator()
        await fixture.model.start()
        XCTAssertEqual(fixture.state.hunger, 0)

        // Four hours: exactly one unit of hunger, and no screen was ever brought to the front.
        currentTime = Fixture.start.addingTimeInterval(HungerClock.secondsPerHungerUnit)
        await coordinator.performRefresh()

        XCTAssertEqual(fixture.state.hunger, 1)
    }

    /// AC1: a wake also evaluates sickness. Three care mistakes are charged by the audit the wake
    /// runs, and the Digimon is ill by the time it ends — nobody has opened the app.
    func testAWakeEvaluatesSickness() async throws {
        let (coordinator, _, _, fixture) = try makeCoordinator()
        await fixture.model.start()
        XCTAssertEqual(fixture.state.healthStatus, .healthy)

        // Starving since hour 16, then three eight-hour spells: 16 + 24 = 40 hours.
        currentTime = Fixture.start.addingTimeInterval(40 * 60 * 60)
        await coordinator.performRefresh()

        XCTAssertEqual(fixture.state.hunger, HungerClock.maximumHunger)
        XCTAssertGreaterThanOrEqual(fixture.state.careMistakeCount, Sickness.careMistakesUntilSick)
        XCTAssertEqual(fixture.state.healthStatus, .sick,
                       "a background wake settles sickness, not just the foreground")
    }

    /// AC1: a wake evaluates EVOLUTION too, so a Digimon that came of age overnight is already its
    /// new form the next time the screen is looked at.
    ///
    /// A Baby I rather than the Child the other tests use, because the stage gate for a Child is 72
    /// hours (`EvolutionTiming.matureMinimumStageDuration`) and 72 hours of unfed neglect makes the
    /// Digimon sick, which pauses evolution for a reason that has nothing to do with this test.
    func testAWakeEvolvesADigimonThatCameOfAgeWhileTheAppWasAway() async throws {
        let fixture = try Fixture.make(directory: directory, name: "Evolve",
                                       graph: Fixture.evolvingGraph(),
                                       fetcher: DailyStepFetcher(steps: 8_000),
                                       clock: { [weak self] in self?.currentTime ?? Fixture.start })
        fixture.state.stage = .babyI
        // US-101: with the light left on, the one bedtime this test's 25 hours crosses is a fifth
        // mistake, and three is the sickness threshold — a Digimon that falls ill does not evolve,
        // for a reason that has nothing to do with the stage gate under test. Put out at hour 0.
        fixture.state.setLight(.off, now: Fixture.start)
        let coordinator = BackgroundRefreshCoordinator(model: fixture.model,
                                                       scheduler: SpyScheduler(),
                                                       observer: SpyObserver(),
                                                       now: { [weak self] in self?.currentTime ?? Fixture.start })
        await fixture.model.start()
        XCTAssertEqual(fixture.state.currentDigimonId, "hero", "still a baby before the gate opens")

        // Just past the 24h a Baby I owes its stage, and still short of the three care mistakes that
        // would pause evolution by making it ill.
        currentTime = Fixture.start.addingTimeInterval(EvolutionTiming.babyMinimumStageDuration + 3600)
        await coordinator.performRefresh()

        XCTAssertEqual(fixture.state.healthStatus, .healthy)
        XCTAssertEqual(fixture.state.currentDigimonId, "grown",
                       "a background wake evolves, with nobody watching")
        XCTAssertEqual(fixture.state.stage, .child)
    }

    /// AC2: the observers are registered for stepCount and activeEnergyBurned.
    func testTheObserversWatchStepsAndActiveEnergy() throws {
        let (coordinator, _, observer, _) = try makeCoordinator()

        coordinator.beginObservingHealthUpdates()

        XCTAssertEqual(observer.observedMetrics, [.steps, .activeEnergy])
        XCTAssertEqual(BackgroundRefreshSchedule.observedMetrics, [.steps, .activeEnergy])
    }

    /// AC2: launching does NOT observe. Registration waits for the authorization gate, because an
    /// observer started before the user has answered the prompt fails with "Authorization not
    /// determined" — seen in the Simulator on a first launch — and is never retried.
    func testLaunchingDoesNotObserveBeforeAuthorizationHasBeenAnswered() throws {
        let (coordinator, scheduler, observer, _) = try makeCoordinator()

        coordinator.begin()

        XCTAssertEqual(observer.observedMetrics, [], "no observer until the prompt is answered")
        XCTAssertEqual(scheduler.requestedDates.count, 1, "but the wake is scheduled regardless")
    }

    /// The screen behind the gate can appear more than once, and each appearance runs its `.task`.
    /// Registering a second set of observers over the first would double every update.
    func testObservingTwiceRegistersOneSetOfObservers() throws {
        let (coordinator, _, observer, fixture) = try makeCoordinator()
        coordinator.beginObservingHealthUpdates()
        coordinator.beginObservingHealthUpdates()

        XCTAssertEqual(observer.startCount, 1)
        XCTAssertEqual(fixture.state.hunger, 0)
    }

    /// AC2: an observed update credits the new samples straight away, rather than waiting for the
    /// next scheduled wake. Driven through the callback the real `HKObserverQuery` invokes.
    func testAnObservedUpdateCreditsWithoutWaitingForTheNextWake() async throws {
        let fetcher = DailyStepFetcher(steps: 2_000)
        let (coordinator, scheduler, observer, fixture) = try makeCoordinator(
            name: "Observed", fetcher: fetcher
        )
        await fixture.model.start()
        coordinator.begin()
        coordinator.beginObservingHealthUpdates()
        let atLaunch = fixture.state.stageEnergy.total
        XCTAssertGreaterThan(atLaunch, 0)

        // The walk the observer is telling the app about. New STEPS, not a re-read: crediting is a
        // delta, so reporting the same total again is correctly worth nothing.
        fetcher.steps = 6_000
        observer.deliverUpdate()
        await coordinator.pendingHealthRefresh?.value

        XCTAssertGreaterThan(fixture.state.stageEnergy.total, atLaunch,
                             "an observed update should credit the steps it was told about")
        XCTAssertEqual(scheduler.requestedDates.count, 1,
                       "an update must not push the guaranteed wake further out")
    }
}

// MARK: - 48 hours shut, with no background refresh at all

@MainActor
final class ClosedAppRecomputeTests: XCTestCase {
    private var directory: URL!
    private var openClock = Fixture.start
    private var closedClock = Fixture.start

    /// Two whole local days, so the closure crosses two midnights — a day boundary is where the
    /// battle allowance rolls over and where a missed day of health data is charged.
    private static let closure: TimeInterval = 48 * 60 * 60
    private static let hour: TimeInterval = 60 * 60

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        openClock = Fixture.start
        closedClock = Fixture.start
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// AC3 + AC4: THE HEADLINE. One app is open the whole time and refreshes every hour for 48
    /// hours; the other is shut at hour 0, gets no background wake at all, and is opened again 48
    /// hours later. They must arrive at the same place.
    ///
    /// This is what makes background refresh an optimization rather than the source of truth: every
    /// field below is recomputed from an elapsed interval against a saved marker, so 48 missed wakes
    /// cost nothing. Hunger caps and freezes its timestamp, starvation is charged by the eight-hour
    /// spell, the missed day of health data is charged once, sickness follows from the count, and
    /// the battle allowance rolls over on a read rather than at midnight.
    ///
    /// US-053's uncleaned-poop mistake is charged once per spell rather than as a rate PRECISELY so
    /// that it can hold here. Sleep pauses poop only when a refresh runs to observe it, so the open
    /// run below skips hours the closed run cannot know to skip; as a rate that scored 2 mistakes
    /// against 6 for the very same 48 hours. See `secondsAtMaximumPoopBeforeMistake`.
    ///
    /// US-101's light goes the other way for the same reason. It IS charged per night, because
    /// nothing about it is observation-dependent — each night's verdict is `lightStateChangedAt`
    /// against that night's deadline, recoverable days later — so the open run's two nights and the
    /// shut run's two nights are the same two. That is why `auditLights` walks back over every
    /// unaudited night instead of charging only the one the refresh landed after.
    func testFortyEightHoursShutMatchesFortyEightHoursOpen() async throws {
        let openGame = try Fixture.make(directory: directory, name: "Open",
                                        clock: { [weak self] in self?.openClock ?? Fixture.start })
        let closedGame = try Fixture.make(directory: directory, name: "Closed",
                                          clock: { [weak self] in self?.closedClock ?? Fixture.start })

        // Both are opened once at hour 0, so they start from the same observation.
        await openGame.model.start()
        await closedGame.model.start()

        // The app that stayed open: a refresh an hour, all 48 of them.
        for hour in 1...48 {
            openClock = Fixture.start.addingTimeInterval(Double(hour) * Self.hour)
            await openGame.model.refresh()
        }

        // The app that was shut: nothing ran. No wake, no observer, no refresh — just the clock.
        closedClock = Fixture.start.addingTimeInterval(Self.closure)
        await closedGame.model.refresh()

        let open = ElapsedTimeState(openGame.state, lifetimeEnergy: openGame.model.lifetimeEnergy,
                                    now: openClock, calendar: Fixture.calendar)
        let closed = ElapsedTimeState(closedGame.state, lifetimeEnergy: closedGame.model.lifetimeEnergy,
                                      now: closedClock, calendar: Fixture.calendar)
        XCTAssertEqual(closed, open, "48h shut should land exactly where 48h open did")

        // Spelled out as well as compared, so a change that broke BOTH runs identically — the one
        // thing an equality assertion cannot catch — still fails here.
        XCTAssertEqual(closed.hunger, HungerClock.maximumHunger)
        XCTAssertEqual(closed.hungerUpdatedAt,
                       Fixture.start.addingTimeInterval(16 * Self.hour),
                       "the timestamp freezes at the moment hunger maxed, 4 units x 4h in")
        XCTAssertEqual(closed.starvationMistakesCharged, 4,
                       "starving from hour 16 to hour 48 is four whole eight-hour spells")
        XCTAssertEqual(closed.careMistakeCount, 8,
                       """
                       four starvation spells, the one whole day that went by with no data, one \
                       for the screen of poop that filled at hour 12 and was never cleaned, and one \
                       for each of the two bedtimes these 48 hours crossed with the light left on
                       """)
        XCTAssertEqual(closed.healthStatus, .sick, "five mistakes is well past the threshold")
    }

    /// AC3: the day's battle count is one of the things that recomputes on a READ, so a day spent
    /// shut reads as zero battles with nothing having run at midnight to reset it. Since US-108 the
    /// count gates nothing — but `ConditionEvaluator` asks it for `.day`-window battle conditions,
    /// and a stale count would open or close an evolution edge that should not have moved.
    func testTheDaysBattleCountRollsOverWhileTheAppIsShut() async throws {
        let game = try Fixture.make(directory: directory, name: "Allowance",
                                    clock: { [weak self] in self?.closedClock ?? Fixture.start })
        await game.model.start()
        // The Simulator's own problem, in a test: no health data means no energy, and since US-108 a
        // battle has to be paid for. Funded here so the fights below actually happen.
        game.state.stageEnergy[.strength] = 100
        // US-176: a battle also spends a charge walked up from steps; the empty readers walk none, so
        // stock the five this test fights.
        game.state.battleCharges = ConsumptionConfig.bundled.maxBattleCharges

        for _ in 0..<5 {
            game.model.battle()
            // US-093: the tap opens the pre-battle round; grading it is what fights the fight.
            game.model.finishBattleRound(.good)
            game.model.finishBattle()
        }
        XCTAssertEqual(game.state.battlesFought(now: closedClock, calendar: Fixture.calendar), 5)

        // Shut for two days. Nothing runs; the clock simply moves.
        closedClock = Fixture.start.addingTimeInterval(Self.closure)

        XCTAssertEqual(game.state.battlesFought(now: closedClock, calendar: Fixture.calendar), 0,
                       "a new local day, read rather than reset")
    }

    /// AC3: energy is the ONE thing elapsed time cannot reconstruct — it is read from HealthKit for
    /// the day it is read on — so the reopen must still credit the day it comes back to. This is
    /// what the missed wakes actually cost, and why the schedule exists at all.
    func testTheReopenAfterAClosureStillCreditsTodaysHealthData() async throws {
        let game = try Fixture.make(directory: directory, name: "Credit",
                                    fetcher: DailyStepFetcher(steps: 4_000),
                                    clock: { [weak self] in self?.closedClock ?? Fixture.start })
        await game.model.start()
        let atLaunch = game.model.lifetimeEnergy.total
        XCTAssertGreaterThan(atLaunch, 0)

        closedClock = Fixture.start.addingTimeInterval(Self.closure)
        await game.model.refresh()

        XCTAssertGreaterThan(game.model.lifetimeEnergy.total, atLaunch,
                             "the day the app came back to is credited, not skipped")
    }

    /// US-176: walking is what earns battles. A refresh that reads steps banks battle charges on the
    /// Digimon that walked them — 300 steps to a charge — off the SAME read the energy came from, so
    /// the wiring in `creditMapSteps` is exercised end to end and not just the arithmetic under it.
    func testWalkingCreditsBattleChargesToTheDigimon() async throws {
        let game = try Fixture.make(directory: directory, name: "Charges",
                                    fetcher: DailyStepFetcher(steps: 900),
                                    clock: { Fixture.start })
        await game.model.start()

        XCTAssertEqual(game.state.battleCharges, 3, "nine hundred steps is three charges")
        XCTAssertEqual(game.model.battleCharges, 3, "and the bar reads them off the active Digimon")
    }

    /// The known, deliberate exception to the headline test, pinned so it cannot change unnoticed.
    ///
    /// `sickSince` is stamped when the app NOTICES the illness, not when the neglect that caused it
    /// crossed the threshold — the care mistakes are derived from elapsed time, but the moment the
    /// count crossed three is not saved anywhere to derive from. So a Digimon that fell ill while
    /// the app was shut starts its 72-hour death countdown from the reopen. That errs towards
    /// LENIENCY (the countdown starts later, never earlier), which is the right way for it to be
    /// wrong, and it is the reason `ElapsedTimeState` leaves the marker out.
    func testAnIllnessThatBeganWhileClosedIsDatedFromTheReopen() async throws {
        let game = try Fixture.make(directory: directory, name: "Onset",
                                    clock: { [weak self] in self?.closedClock ?? Fixture.start })
        await game.model.start()

        closedClock = Fixture.start.addingTimeInterval(Self.closure)
        await game.model.refresh()

        XCTAssertEqual(game.state.healthStatus, .sick)
        XCTAssertEqual(game.state.sickSince, closedClock,
                       "dated from the moment it was noticed, not from the hour it became due")
    }
}
