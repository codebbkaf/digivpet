import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-024 — feeding, with refuse behaviour.
///
/// Two layers, as in US-023's suite: `FeedActionTests` pins the pure rule against a hand-built
/// `GameState`, and `FeedApplyTests` drives the real `MainScreenModel` and the real store, so the
/// animation, the haptic and the save are exercised through the code the screen actually calls.
///
/// No test waits real time: the clock is chosen `Date`s, and the model's action hold is injected at
/// milliseconds rather than the app's two seconds.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)
    static let hour: TimeInterval = 60 * 60

    static func after(_ hours: Double) -> Date { start.addingTimeInterval(hours * hour) }

    /// A fixed zone, so the day `recordRefusal` keys on is the same one wherever this runs.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// A saved game outside any store — enough for the pure rule, which only reads and writes fields.
private func makeState(hunger: Int, vitality: Int) -> GameState {
    let state = GameState(currentDigimonId: "hero", stage: .babyI, now: Clock.start)
    state.hunger = hunger
    state.stageEnergy[.vitality] = vitality
    return state
}

final class FeedActionTests: XCTestCase {

    // MARK: - AC1: costs Vitality, reduces hunger by one

    func testFeedingSpendsVitalityAndRemovesOneUnitOfHunger() {
        let state = makeState(hunger: 3, vitality: 20)

        let outcome = FeedAction.feed(state, isAsleep: false, now: Clock.after(1),
                                      calendar: Clock.calendar)

        XCTAssertEqual(outcome, .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(state.hunger, 2, "one unit, not all of it")
        XCTAssertEqual(state.stageEnergy[.vitality], 20 - FeedAction.vitalityCostPerFeed)
    }

    /// Only Vitality is spent. Feeding must not quietly drain the other three, which are what steer
    /// the evolution branch.
    func testFeedingSpendsNothingButVitality() {
        let state = makeState(hunger: 2, vitality: 20)
        state.stageEnergy[.strength] = 40
        state.stageEnergy[.spirit] = 30
        state.stageEnergy[.stamina] = 10

        FeedAction.feed(state, isAsleep: false, now: Clock.start, calendar: Clock.calendar)

        XCTAssertEqual(state.stageEnergy[.strength], 40)
        XCTAssertEqual(state.stageEnergy[.spirit], 30)
        XCTAssertEqual(state.stageEnergy[.stamina], 10)
    }

    /// `lifetimeEnergy` is the record of what was ever EARNED, so spending must not rewrite it —
    /// otherwise a well-fed Digimon would look like it had lived a less active life than it did.
    ///
    /// Since US-123 the total is on `PlayerProfile` and a feed is handed only the `GameState`, so
    /// the guarantee is structural rather than a rule anybody has to keep. Pinned anyway: it is the
    /// test that fails the day someone hands `FeedAction` the profile as well.
    func testFeedingDoesNotTakeBackLifetimeEnergy() {
        let state = makeState(hunger: 2, vitality: 20)
        let profile = PlayerProfile()
        profile.lifetimeEnergy[.vitality] = 90

        FeedAction.feed(state, isAsleep: false, now: Clock.start, calendar: Clock.calendar)

        XCTAssertEqual(profile.lifetimeEnergy[.vitality], 90)
    }

    /// The restamp US-023 said feeding owes it. `HungerClock` freezes `hungerUpdatedAt` at the moment
    /// hunger hit the maximum, so without this a feed at max would be undone by the very next
    /// `advanceHunger` and would look like it did nothing.
    func testFeedingAtMaximumHungerDoesNotImmediatelyReAccrue() {
        let state = makeState(hunger: HungerClock.maximumHunger, vitality: 20)
        // Frozen 12h ago, which is three intervals' worth of stale time.
        state.hungerUpdatedAt = Clock.start

        FeedAction.feed(state, isAsleep: false, now: Clock.after(12), calendar: Clock.calendar)
        XCTAssertEqual(state.hunger, HungerClock.maximumHunger - 1)

        state.advanceHunger(now: Clock.after(12))
        XCTAssertEqual(state.hunger, HungerClock.maximumHunger - 1,
                       "the feed stuck; the stale timestamp did not undo it")
    }

    // MARK: - AC3 / AC5: refusing at zero hunger

    /// The story's headline assertion: a Digimon with nothing to eat off turns the food down, is
    /// charged nothing for it, and the refusal is counted.
    func testFeedingAtZeroHungerConsumesNoEnergyAndCountsTheRefusal() {
        let state = makeState(hunger: 0, vitality: 20)

        let outcome = FeedAction.feed(state, isAsleep: false, now: Clock.start,
                                      calendar: Clock.calendar)

        XCTAssertEqual(outcome, .refused)
        XCTAssertEqual(state.stageEnergy[.vitality], 20, "a refusal is free")
        XCTAssertEqual(state.hunger, 0, "and hunger cannot go negative")
        XCTAssertEqual(state.refusalCount, 1)
    }

    /// Refusals accumulate within a day — this is the counter US-027's "3+ refusals in a day"
    /// overfeeding mistake will read.
    func testRefusalsAccumulateWithinADay() {
        let state = makeState(hunger: 0, vitality: 20)

        for hour in 0..<3 {
            FeedAction.feed(state, isAsleep: false, now: Clock.after(Double(hour)),
                            calendar: Clock.calendar)
        }

        XCTAssertEqual(state.refusalCount, 3)
        XCTAssertEqual(state.refusalDay, Clock.calendar.startOfDay(for: Clock.start))
    }

    /// And they roll over at midnight, so yesterday's refusals cannot trip today's mistake.
    func testRefusalsResetOnANewDay() {
        let state = makeState(hunger: 0, vitality: 20)
        FeedAction.feed(state, isAsleep: false, now: Clock.start, calendar: Clock.calendar)
        FeedAction.feed(state, isAsleep: false, now: Clock.after(1), calendar: Clock.calendar)
        XCTAssertEqual(state.refusalCount, 2)

        FeedAction.feed(state, isAsleep: false, now: Clock.after(30), calendar: Clock.calendar)

        XCTAssertEqual(state.refusalCount, 1, "a new day starts the count over")
        XCTAssertEqual(state.refusalDay, Clock.calendar.startOfDay(for: Clock.after(30)))
    }

    // MARK: - AC4: blocked while asleep

    func testFeedingIsBlockedWhileAsleep() {
        let state = makeState(hunger: 3, vitality: 20)

        let outcome = FeedAction.feed(state, isAsleep: true, now: Clock.start,
                                      calendar: Clock.calendar)

        guard case .blocked(let reason) = outcome else {
            return XCTFail("expected a block, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "the block has to be able to explain itself on screen")
        XCTAssertEqual(state.hunger, 3, "nothing was eaten")
        XCTAssertEqual(state.stageEnergy[.vitality], 20, "and nothing was spent")
    }

    /// Asleep is checked BEFORE hunger, so a sleeping Digimon that happens to be full is reported as
    /// asleep rather than being charged a refusal it never made.
    func testSleepingAndFullIsBlockedRatherThanCountedAsARefusal() {
        let state = makeState(hunger: 0, vitality: 20)

        let outcome = FeedAction.feed(state, isAsleep: true, now: Clock.start,
                                      calendar: Clock.calendar)

        guard case .blocked = outcome else { return XCTFail("expected a block, got \(outcome)") }
        XCTAssertEqual(state.refusalCount, 0)
    }

    // MARK: - Not enough energy

    /// Feeding is a purchase, so it can fail for want of funds — and that has to say so rather than
    /// silently doing nothing or driving Vitality negative.
    func testFeedingIsBlockedWithoutEnoughVitality() {
        let state = makeState(hunger: 3, vitality: FeedAction.vitalityCostPerFeed - 1)

        let outcome = FeedAction.feed(state, isAsleep: false, now: Clock.start,
                                      calendar: Clock.calendar)

        guard case .blocked = outcome else { return XCTFail("expected a block, got \(outcome)") }
        XCTAssertEqual(state.stageEnergy[.vitality], FeedAction.vitalityCostPerFeed - 1)
        XCTAssertEqual(state.hunger, 3)
    }

    /// Exactly the cost is enough — the guard is `>=`, not `>`.
    func testExactlyTheCostIsEnoughToFeed() {
        let state = makeState(hunger: 1, vitality: FeedAction.vitalityCostPerFeed)

        let outcome = FeedAction.feed(state, isAsleep: false, now: Clock.start,
                                      calendar: Clock.calendar)

        XCTAssertEqual(outcome, .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(state.stageEnergy[.vitality], 0)
    }
}

/// Fixtures for the apply layer. These fetchers exist because `HealthEnergySource` needs them and
/// the Simulator has no health data; every one hands back nothing, so no energy is ever credited
/// behind these tests' backs. Copied rather than shared — the ones in the other apply suites are
/// `private` to their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class FeedApplyTests: XCTestCase {
    private var storeDirectory: URL!
    private var hapticCount = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeedingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        hapticCount = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve and every change to the saved
    /// game is feeding's doing alone. The egg exists only because `start()` resolves a starting
    /// Digitama before it loads and throws `.noDigitama` without one — even when a saved game exists.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    private func makeModel(url: URL, now: Date) -> MainScreenModel {
        MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            calendar: Clock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            playFeedHaptic: { [weak self] in self?.hapticCount += 1 },
            // Milliseconds, so the revert to idle is observable without waiting out the app's 2s.
            actionDuration: 0.05
        )
    }

    /// Seeds a saved game at "hero" with the given hunger and Vitality, then hands back a started
    /// model reading it off disk.
    private func startedModel(named name: String, hunger: Int, vitality: Int) async throws
        -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.hunger = hunger
        state.stageEnergy[.vitality] = vitality
        try seeding.save()

        let model = makeModel(url: url, now: Clock.start)
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }

    // MARK: - AC2: the eat loop and the light haptic

    func testFeedingPlaysTheEatLoopWithAHapticAndThenReturnsToIdle() async throws {
        let model = try await startedModel(named: "eat", hunger: 3, vitality: 20)

        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.animation, .eat, "the eat loop, i.e. frames eat1 <-> eat2")
        XCTAssertEqual(model.animation.stageFrames, [.eat1, .eat2])
        XCTAssertEqual(hapticCount, 1)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle, "the pose is held, not stuck")
    }

    // MARK: - AC3: the refuse frame

    /// Frame index 6 by name AND by number, because the number is the thing the sheet layout pins
    /// down — `.refuse` naming a different index would draw the wrong art and still read fine here.
    func testRefusingHoldsTheRefuseFrameAndPlaysNoHaptic() async throws {
        let model = try await startedModel(named: "refuse", hunger: 0, vitality: 20)

        XCTAssertEqual(model.feed(), .refused)
        XCTAssertEqual(model.animation, .pose(.refuse))
        XCTAssertEqual(SpriteFrame.refuse.rawValue, 6)
        XCTAssertEqual(hapticCount, 0, "nothing was eaten, so nothing taps")
    }

    /// AC5 through the real model and the real store: the refusal is not just counted in memory, it
    /// survives to the next launch, which is what US-027 will read it on.
    func testARefusalIsPersisted() async throws {
        let model = try await startedModel(named: "persist", hunger: 0, vitality: 20)
        XCTAssertEqual(model.feed(), .refused)
        XCTAssertEqual(model.state?.stageEnergy[.vitality], 20, "still free through the model")

        let reopened = try GameStore(url: storeURL("persist"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.refusalCount, 1)
        XCTAssertEqual(saved.stageEnergy[.vitality], 20)
    }

    // MARK: - AC1 persistence

    func testAFedHungerAndItsCostArePersisted() async throws {
        let model = try await startedModel(named: "fed", hunger: 3, vitality: 20)
        model.feed()

        let reopened = try GameStore(url: storeURL("fed"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.hunger, 2)
        XCTAssertEqual(saved.stageEnergy[.vitality], 20 - FeedAction.vitalityCostPerFeed)
        XCTAssertEqual(saved.hungerUpdatedAt, Clock.start, "restamped at the feed")
    }

    // MARK: - US-110: a sleeping Digimon is woken and then fed

    /// US-024 AC4 used to read "blocked while asleep, with a visible reason". US-110 reversed it: the
    /// user was being charged a care mistake and handed nothing back, so the tap now WAKES the
    /// Digimon and the meal is eaten. What survives from the old test is that the disturbance is
    /// still charged — that half was never the problem.
    func testFeedingWhileAsleepWakesTheDigimonAndFeedsIt() async throws {
        let model = try await startedModel(named: "asleep", hunger: 3, vitality: 20)
        model.isAsleep = true
        let mistakesBefore = try XCTUnwrap(model.state?.careMistakeCount)

        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertFalse(model.isAsleep, "prodding it woke it")
        XCTAssertEqual(model.animation, .eat, "and it is eating, not lying in the sleep loop")
        XCTAssertEqual(hapticCount, 1)
        XCTAssertEqual(model.state?.hunger, 2, "a unit of hunger really came off")
        XCTAssertEqual(model.state?.careMistakeCount, mistakesBefore + 1,
                       "the disturbance is still a mistake")
        XCTAssertEqual(model.state?.stageSleepDisturbances, 1)
    }

    /// The grace period is what makes the wake stick: the marker is on the SAVED game, and a second
    /// tap inside it is not a second disturbance.
    func testTheWokenDigimonStaysAwakeForTheGracePeriodAndIsNotDisturbedTwice() async throws {
        let model = try await startedModel(named: "grace", hunger: 3, vitality: 20)
        model.isAsleep = true

        model.feed()
        let awakeUntil = try XCTUnwrap(model.state?.awakeUntil)
        XCTAssertEqual(awakeUntil, Clock.start.addingTimeInterval(SleepSchedule.wakeGracePeriod))
        let mistakes = try XCTUnwrap(model.state?.careMistakeCount)

        model.feed()
        XCTAssertEqual(model.state?.stageSleepDisturbances, 1, "already awake, so not disturbed again")
        XCTAssertEqual(model.state?.careMistakeCount, mistakes)
        XCTAssertEqual(model.state?.awakeUntil, awakeUntil, "and the grace is not extended")
    }
}
