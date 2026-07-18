import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-023 — hunger that increases over real time.
///
/// Two layers, like US-020's suite: `HungerClockTests` pins the pure rule with a mock clock, and
/// `HungerApplyTests` drives the real `refresh()` and the real store, so the rule is exercised
/// through the code that actually reads and saves `GameState.hungerUpdatedAt`.
///
/// No test waits real time. The "clock" is only ever two chosen `Date`s a fixed distance apart.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)
    static let hour: TimeInterval = 60 * 60

    static func after(_ hours: Double) -> Date { start.addingTimeInterval(hours * hour) }
}

final class HungerClockTests: XCTestCase {

    // MARK: - AC1: one unit per 4h

    /// AC4, and the story's headline number: 12 elapsed hours is exactly 3 units, not 2 and not 4.
    func testTwelveElapsedHoursAddsExactlyThreeHungerUnits() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start, now: Clock.after(12))
        XCTAssertEqual(advanced.hunger, 3)
    }

    /// AC1 across the interval boundary. 3h59m is worth nothing and 4h is worth one, so the unit is
    /// really 4h — a rate of "roughly every few hours" would pass the 12h case above by accident.
    func testHungerAccruesOnlyOnWholeFourHourIntervals() {
        let cases: [(hours: Double, expected: Int)] = [
            (0, 0), (3.98, 0), (4, 1), (7.9, 1), (8, 2), (11.9, 2), (12, 3), (16, 4)
        ]
        for (hours, expected) in cases {
            let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start,
                                               now: Clock.after(hours))
            XCTAssertEqual(advanced.hunger, expected, "after \(hours)h")
        }
    }

    /// The part-worn interval is CARRIED, not discarded. Two 3h sessions must add the unit that six
    /// hours earned; stamping the timestamp to `now` on every call would leave hunger at 0 forever
    /// for anyone who opens the app more often than every four hours.
    func testAPartialIntervalIsCarriedAcrossCalls() {
        let first = HungerClock.advance(hunger: 0, lastUpdated: Clock.start, now: Clock.after(3))
        XCTAssertEqual(first.hunger, 0, "3h alone is not a unit")

        let second = HungerClock.advance(hunger: first.hunger, lastUpdated: first.updatedAt,
                                         now: Clock.after(6))
        XCTAssertEqual(second.hunger, 1, "the first 3h was kept, so 6h total is one unit")
    }

    /// Calling repeatedly inside one interval is a no-op, which is what lets the main screen call
    /// this on every refresh without hunger tracking how often the app is opened.
    func testRepeatedCallsWithinAnIntervalChangeNothing() {
        var hunger = 0
        var updated: Date? = Clock.start
        for hours in stride(from: 0.0, through: 3.5, by: 0.5) {
            let advanced = HungerClock.advance(hunger: hunger, lastUpdated: updated,
                                               now: Clock.after(hours))
            hunger = advanced.hunger
            updated = advanced.updatedAt
        }
        XCTAssertEqual(hunger, 0)
        XCTAssertEqual(updated, Clock.start, "the timestamp never moved, so nothing was consumed")
    }

    // MARK: - AC2: capped at the constant

    /// AC2. Well past four intervals, and hunger stops at the constant rather than running away.
    func testHungerIsCappedAtTheMaximum() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start,
                                           now: Clock.after(1_000))
        XCTAssertEqual(advanced.hunger, HungerClock.maximumHunger)
    }

    /// The cap is honoured from a partly-hungry start too: 3 + 12h would be 6 uncapped.
    func testHungerAlreadyPartlyFullStillStopsAtTheMaximum() {
        let advanced = HungerClock.advance(hunger: 3, lastUpdated: Clock.start, now: Clock.after(12))
        XCTAssertEqual(advanced.hunger, HungerClock.maximumHunger)
    }

    /// At the cap the timestamp freezes at the instant hunger REACHED the cap — 16h in from empty,
    /// not the 100h "now". US-027's "hunger at max for 8h+" care mistake reads the gap between that
    /// instant and now, so this is the property it depends on.
    func testTheTimestampStopsAtTheInstantHungerHitTheMaximum() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start,
                                           now: Clock.after(100))
        XCTAssertEqual(advanced.updatedAt, Clock.after(16),
                       "4 units x 4h after the start is when it became starving")

        // And it stays there: an already-maxed Digimon does not push the timestamp forward, or the
        // "how long has it been starving" answer would reset on every app open.
        let again = HungerClock.advance(hunger: advanced.hunger, lastUpdated: advanced.updatedAt,
                                        now: Clock.after(200))
        XCTAssertEqual(again.hunger, HungerClock.maximumHunger)
        XCTAssertEqual(again.updatedAt, Clock.after(16))
    }

    // MARK: - AC3: correct after days closed, and clock edge cases

    /// AC3. Three whole days of elapsed time computed in ONE call, with no intervening ticks — the
    /// shape of an app that was closed all weekend. It arrives at the same place as a timer that ran
    /// the whole time would have: the cap.
    func testHungerIsCorrectAfterTheAppWasClosedForDays() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start,
                                           now: Clock.after(72))
        XCTAssertEqual(advanced.hunger, HungerClock.maximumHunger)
    }

    /// AC3 below the cap, where elapsed time is doing real arithmetic rather than just saturating —
    /// the test above would pass even if any long gap simply pinned hunger to the maximum.
    func testALongGapBelowTheCapIsComputedFromElapsedTimeNotTicks() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Clock.start, now: Clock.after(8))
        XCTAssertEqual(advanced.hunger, 2, "8h closed = 2 units, computed in one shot")
        XCTAssertEqual(advanced.updatedAt, Clock.after(8))
    }

    /// A save from before hunger was tracked has no baseline. It starts the clock rather than
    /// inventing elapsed hunger from `birthDate`, which would double-count against the hunger the
    /// save already holds.
    func testAnAbsentTimestampStartsTheClockWithoutAddingHunger() {
        let advanced = HungerClock.advance(hunger: 2, lastUpdated: nil, now: Clock.after(500))
        XCTAssertEqual(advanced.hunger, 2, "no baseline, so nothing is owed")
        XCTAssertEqual(advanced.updatedAt, Clock.after(500), "but the clock starts now")
    }

    /// A backwards clock (the user changed the time, or a timezone moved) must not leave the
    /// timestamp in the future, where hunger would freeze until the wall clock caught up.
    func testABackwardsClockRestampsRatherThanFreezingHunger() {
        let advanced = HungerClock.advance(hunger: 1, lastUpdated: Clock.after(10),
                                           now: Clock.after(2))
        XCTAssertEqual(advanced.hunger, 1, "time going backwards does not un-hunger a Digimon")
        XCTAssertEqual(advanced.updatedAt, Clock.after(2))
    }

    /// An absurd elapsed time must saturate, not trap. `Int(Double)` traps outside Int's range and
    /// the elapsed value is only as trustworthy as the device clock.
    func testAnAbsurdElapsedTimeSaturatesRatherThanTrapping() {
        let advanced = HungerClock.advance(hunger: 0, lastUpdated: Date.distantPast,
                                           now: Date.distantFuture)
        XCTAssertEqual(advanced.hunger, HungerClock.maximumHunger)
    }
}

// MARK: - Hunger applied through the model

// File-private copies, as every other apply-suite keeps: the Simulator has no HealthKit data, so
// the readers hand back nothing and any change to the saved game is hunger's doing.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// The same rule through the real model, the real store and the real save path.
@MainActor
final class HungerApplyTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HungerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve and any change to the saved game
    /// is hunger's doing alone. The egg exists only because `start()` needs a Digitama to seed a new
    /// game from; every test below saves a game at "hero" first, so it is never actually used.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    private func makeModel(store: GameStore, now: @escaping () -> Date) -> MainScreenModel {
        MainScreenModel(
            makeStore: { store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(), calendar: .current),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(), calendar: .current)
            ),
            calendar: .current,
            now: now,
            chooseStartingDigitama: { $0.first }
        )
    }

    /// AC1/AC3 end to end: a game last seen 12h ago comes back 3 hunger heavier, through the same
    /// `refresh()` the app runs when it comes to the front.
    func testRefreshAgesHungerByTheElapsedTime() async throws {
        let store = try GameStore(url: storeURL("Refresh"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.stage = .babyI
        try store.save()
        XCTAssertEqual(state.hunger, 0, "a new game starts fed")

        let model = makeModel(store: store, now: { Clock.after(12) })
        await model.start()

        XCTAssertEqual(model.state?.hunger, 3)
        XCTAssertEqual(model.state?.currentDigimonId, "hero", "and nothing else moved")
    }

    /// AC3 as the user meets it: the app is CLOSED for the elapsed time. The container is dropped
    /// and reopened, so the 12h is measured against a timestamp that came off disk rather than one
    /// held live in memory.
    func testHungerIsCorrectAcrossAnAppRestart() async throws {
        let url = storeURL("Restart")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: Clock.start)
            state.stage = .babyI
            try store.save()
        }

        let reopened = try GameStore(url: url)
        let model = makeModel(store: reopened, now: { Clock.after(12) })
        await model.start()

        XCTAssertEqual(model.state?.hunger, 3, "computed from the persisted timestamp")
    }

    /// The advanced hunger and its timestamp are actually FLUSHED. Without this, a save that ages
    /// in memory would re-age from the old timestamp on the next launch and double-count.
    func testAgedHungerAndItsTimestampArePersisted() async throws {
        let url = storeURL("Persist")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: Clock.start)
            state.stage = .babyI
            try store.save()

            let model = makeModel(store: store, now: { Clock.after(12) })
            await model.start()
        }

        let reopened = try GameStore(url: url)
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.after(12))
        XCTAssertEqual(saved.hunger, 3)
        XCTAssertEqual(saved.hungerUpdatedAt, Clock.after(12),
                       "the consumed intervals were saved too, so a re-open does not re-charge them")
    }
}
