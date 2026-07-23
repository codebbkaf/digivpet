import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-181 — each Digimon remembers how much HealthKit sleep it has banked, so switching which one is
/// out shows the right sleep progress toward its evolution gate. Distinct from the nightly sleep
/// *energy*: that tops up `stageEnergy` and resets, this only ever grows.
///
/// The clock is injected and the reader is a fixture, so nothing here waits real time or asks live
/// HealthKit anything — the same discipline every other suite keeps.

// MARK: - The accumulation itself (pure)

/// The arithmetic on `GameState`, tested without a refresh so the conversion, the guard and the
/// per-Digimon independence hold on their own. Mirrors `BattleChargeCreditTests`.
final class SleepAccumulationCreditTests: XCTestCase {
    private func freshState() -> GameState {
        GameState(currentDigimonId: "hero", now: Date(timeIntervalSince1970: 0))
    }

    /// The headline: a night of 405 minutes is 6.75 accumulated hours.
    func testCreditingMinutesAccumulatesAndHoursFollow() {
        let state = freshState()
        XCTAssertEqual(state.accumulatedSleepMinutes, 0, "a fresh Digimon has slept nothing")
        XCTAssertEqual(state.accumulatedSleepHours, 0)

        state.creditSleep(minutes: 405)
        XCTAssertEqual(state.accumulatedSleepMinutes, 405)
        XCTAssertEqual(state.accumulatedSleepHours, 6.75, "the hours view is the minutes over sixty")
    }

    /// A health reading arrives as many small deltas across the Digimon's life; they add up, they are
    /// never capped, and the hours track the running minutes.
    func testCreditsAcrossManyReadsSumWithoutACap() {
        let state = freshState()
        state.creditSleep(minutes: 480) // 8 h
        state.creditSleep(minutes: 480) // another night
        state.creditSleep(minutes: 60)  // a nap read

        XCTAssertEqual(state.accumulatedSleepMinutes, 1_020)
        XCTAssertEqual(state.accumulatedSleepHours, 17, "no ceiling — it climbs past any gate")
    }

    /// Being told nothing is not being told to add zero: a non-positive delta is a no-op, so a night
    /// HealthKit could not describe never rewinds a total that is already banked.
    func testNonPositiveDeltasDoNothing() {
        let state = freshState()
        state.creditSleep(minutes: 405)
        state.creditSleep(minutes: 0)
        state.creditSleep(minutes: -100)
        XCTAssertEqual(state.accumulatedSleepMinutes, 405, "zero and negative leave it standing")
    }

    /// Per-Digimon by construction: the store lives on each `GameState`, so crediting one never
    /// touches another. This is the mechanism that makes a frozen Digimon — one that is simply never
    /// credited — accrue nothing (US-125).
    func testTwoDigimonAccumulateIndependently() {
        let sleeper = freshState()
        let other = freshState()
        sleeper.creditSleep(minutes: 405)

        XCTAssertEqual(sleeper.accumulatedSleepMinutes, 405)
        XCTAssertEqual(other.accumulatedSleepMinutes, 0, "the other Digimon slept none of it")
    }
}

// MARK: - Persistence across launches and switches

/// The accumulation lives on the saved record, so it survives a relaunch and switching which Digimon
/// is out is just reading a different record's value.
@MainActor
final class SleepAccumulationPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func url() -> URL { directory.appendingPathComponent("Sleep.store") }

    /// Banked, closed, reopened: the total is still there — it is a saved attribute, not in-memory
    /// state that a relaunch would forget.
    func testAccumulatedSleepSurvivesAReopen() throws {
        let seeding = try GameStore(url: url())
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Date(timeIntervalSince1970: 0))
        state.creditSleep(minutes: 405)
        try seeding.save()

        let reopened = try GameStore(url: url())
        let loaded = try XCTUnwrap(try reopened.savedState())
        XCTAssertEqual(loaded.accumulatedSleepMinutes, 405, "the reopened Digimon kept its sleep")
        XCTAssertEqual(loaded.accumulatedSleepHours, 6.75)
    }

    /// A box of two — the active Digimon carries its sleep, the frozen one carries its own — and both
    /// survive a reopen with their values kept apart. Switching which is active never mixes them.
    func testEachDigimonInABoxKeepsItsOwnSleepAcrossAReopen() throws {
        let seeding = try GameStore(url: url())
        let active = try seeding.loadOrCreate(digitamaId: "hero", now: Date(timeIntervalSince1970: 0))
        active.creditSleep(minutes: 405)
        // A frozen box-mate that slept a different amount — grantDigitama inserts it inactive.
        let frozen = try seeding.grantDigitama("agu_digitama", now: Date(timeIntervalSince1970: 0))
        frozen.creditSleep(minutes: 120)
        try seeding.save()

        let reopened = try GameStore(url: url())
        let states = try reopened.allStates()
        let hero = try XCTUnwrap(states.first { $0.currentDigimonId == "hero" })
        let egg = try XCTUnwrap(states.first { $0.currentDigimonId == "agu_digitama" })
        XCTAssertEqual(hero.accumulatedSleepMinutes, 405, "the active Digimon's own total")
        XCTAssertEqual(egg.accumulatedSleepMinutes, 120, "and the frozen one's, kept apart")
    }
}

// MARK: - End to end through a refresh

private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    var samples: [SleepSample] = []
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { samples }
}

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

/// A refresh that reads last night's sleep off HealthKit banks it on the Digimon that is out, off the
/// same US-179 `MetricLedger` delta everything else spends — so it is de-duplicated once and a frozen
/// box-mate accrues nothing.
@MainActor
final class SleepAccumulationRefreshTests: XCTestCase {
    private var directory: URL!

    /// Los Angeles, well away from UTC, so a window computed in the wrong zone is caught.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    /// The morning after: last night's window is 18:00 the 10th to 12:00 the 11th, and the fixture
    /// night of 23:30–06:15 (405 minutes) falls wholly inside it.
    private var morning: Date { at("2026-03-11 09:00") }
    private var night: SleepSample {
        SleepSample(start: at("2026-03-10 23:30"), end: at("2026-03-11 06:15"), category: .asleepCore)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A Child with nowhere to evolve, so the sleep energy this read also credits cannot move the
    /// fixture and cloud the accumulation being asserted.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "agu_digitama", displayName: "Agu Digitama", stage: .digitama,
                          spriteFile: "Agu_Digitama"),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
        ])
    }

    /// A store seeded with an awake `hero` child, and a model over it fed `samples` for last night.
    /// The same store instance is returned so the box can be read back without opening a second one.
    private func makeModel(name: String, samples: [SleepSample]) throws -> (MainScreenModel, GameStore) {
        let store = try GameStore(url: directory.appendingPathComponent("\(name).store"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: morning)
        state.stage = .child
        state.currentDigimonId = "hero"
        // US-027: without these the audit charges a mistake per day since the epoch.
        state.healthDataLastSeen = morning
        state.hungerUpdatedAt = morning
        state.stageEnteredDate = morning
        try store.save()

        let fetcher = FixtureSleepFetcher()
        fetcher.samples = samples
        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            roster: Roster(entries: []),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(), calendar: calendar),
                sleepReader: LastNightSleepReader(fetcher: fetcher, calendar: calendar)
            ),
            calendar: calendar,
            now: { self.morning },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
        return (model, store)
    }

    /// AC1/AC3: the read credits the active Digimon 405 minutes / 6.75 hours, and the UI (the model's
    /// active state) reads them off it.
    func testARefreshCreditsLastNightsSleepToTheActiveDigimon() async throws {
        let (model, _) = try makeModel(name: "Credit", samples: [night])
        await model.start()

        XCTAssertEqual(model.state?.accumulatedSleepMinutes, 405, "the whole 405-minute block banked")
        XCTAssertEqual(model.state?.accumulatedSleepHours, 6.75)
    }

    /// AC3 (de-duplication): a second refresh of the SAME night does not bank it twice — the shared
    /// `MetricLedger` has already spent last night's minutes.
    func testASecondRefreshOfTheSameNightDoesNotDoubleCount() async throws {
        let (model, _) = try makeModel(name: "Dedup", samples: [night])
        await model.start()
        XCTAssertEqual(model.state?.accumulatedSleepMinutes, 405)

        await model.refresh()
        XCTAssertEqual(model.state?.accumulatedSleepMinutes, 405, "read again, but banked once")
    }

    /// AC2 (frozen does not accrue, consistent with US-125): a box-mate that is not the active
    /// Digimon is never refreshed, so a night's sleep lands only on the one that is out.
    func testAFrozenBoxMateAccruesNoSleep() async throws {
        let (model, store) = try makeModel(name: "Frozen", samples: [night])
        // A frozen, inactive egg joins the box before the refresh.
        try store.grantDigitama("agu_digitama", now: morning)
        await model.start()

        let states = try store.allStates()
        let active = try XCTUnwrap(states.first(where: \.isActive))
        let frozen = try XCTUnwrap(states.first { !$0.isActive })
        XCTAssertEqual(active.currentDigimonId, "hero")
        XCTAssertEqual(active.accumulatedSleepMinutes, 405, "the Digimon out banked the night")
        XCTAssertEqual(frozen.accumulatedSleepMinutes, 0, "the frozen one slept none of it")
    }
}
