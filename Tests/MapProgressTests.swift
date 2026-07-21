import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-118 — the steps you walk accrue to the map you chose.
///
/// A fixed-timezone calendar and hand-written instants, as in the other suites: a test that passed
/// only in the machine's own zone would be no test at all. No test here waits real time or asks
/// HealthKit anything — the clock is injected and every reading comes from a fixture fetcher.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static let morning = date("2026-07-17 08:00")
    static let evening = date("2026-07-17 21:00")
    static let nextMorning = date("2026-07-18 08:00")

    /// Two short maps, so a finish is a hundred fixture steps away rather than three thousand.
    /// Deliberately NOT the shipped catalog: a test that walked `01_grassland`'s real 3,000 steps
    /// would start failing the day someone retunes it, which is a data edit and not a bug.
    static let catalog = MapCatalog(maps: [
        AdventureMap(id: "first", displayName: "First", assetName: "01_grassland",
                     tier: 1, totalSteps: 1_000),
        AdventureMap(id: "second", displayName: "Second", assetName: "02_river",
                     tier: 2, totalSteps: 2_000, unlockedBy: "first"),
    ])
}

private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - The accrual rule (pure)

final class MapStepCreditorTests: XCTestCase {
    private func progress(selecting id: String?) -> MapProgress {
        MapProgress(selectedMapId: id)
    }

    /// THE AC: steps go to the map that is selected.
    func testStepsAccrueToTheSelectedMap() {
        let progress = progress(selecting: "first")

        MapStepCreditor.credit(steps: 250, to: progress, catalog: Fixture.catalog,
                               now: Fixture.morning)

        XCTAssertEqual(progress.recorded(forMap: "first"), 250)
        XCTAssertEqual(progress.recorded(forMap: "second"), 0, "the other map is untouched")
    }

    /// Steps accumulate across reads rather than replacing each other — the counter is a total,
    /// not the last thing that happened.
    func testStepsAccumulateAcrossReads() {
        let progress = progress(selecting: "first")

        MapStepCreditor.credit(steps: 250, to: progress, catalog: Fixture.catalog, now: Fixture.morning)
        MapStepCreditor.credit(steps: 300, to: progress, catalog: Fixture.catalog, now: Fixture.evening)

        XCTAssertEqual(progress.recorded(forMap: "first"), 550)
    }

    /// AC: with no map selected the game is fully playable and the delta simply has nowhere to go.
    /// The tempting wrong answer is banking it against the first map, which would credit a place
    /// the player has never chosen.
    func testNothingAccruesWithNoMapSelected() {
        let progress = progress(selecting: nil)

        XCTAssertEqual(MapStepCreditor.credit(steps: 400, to: progress, catalog: Fixture.catalog,
                                              now: Fixture.morning), 0)
        XCTAssertEqual(progress.recordedByMap, [:])
    }

    /// A selection the catalog does not know — a map removed from `maps.json` by a later build —
    /// credits nothing rather than opening a counter under an id nothing can ever show.
    func testNothingAccruesToAMapTheCatalogDoesNotKnow() {
        let progress = progress(selecting: "atlantis")

        XCTAssertEqual(MapStepCreditor.credit(steps: 400, to: progress, catalog: Fixture.catalog,
                                              now: Fixture.morning), 0)
        XCTAssertEqual(progress.recordedByMap, [:])
    }

    /// THE AC: finished the first time recorded >= totalSteps, WITH a timestamp. Checked at the
    /// boundary in both directions, so the rule is pinned to 1,000 rather than to "something near
    /// a thousand".
    func testAMapIsFinishedTheFirstTimeItsTotalIsReached() {
        let progress = progress(selecting: "first")

        MapStepCreditor.credit(steps: 999, to: progress, catalog: Fixture.catalog, now: Fixture.morning)
        XCTAssertFalse(progress.isFinished(forMap: "first"), "999 of 1,000 is not across")
        XCTAssertNil(progress.finishedAt(forMap: "first"))

        MapStepCreditor.credit(steps: 1, to: progress, catalog: Fixture.catalog, now: Fixture.evening)
        XCTAssertTrue(progress.isFinished(forMap: "first"), "exactly the total finishes it")
        XCTAssertEqual(progress.finishedAt(forMap: "first"), Fixture.evening)
    }

    /// THE AC: crossing the total again does not re-fire. The stamp is the moment it was FIRST
    /// crossed — a stamp rewritten on every later refresh would tell the player they finished the
    /// grassland this morning, forever.
    func testCrossingTheTotalAgainDoesNotRestampTheFinish() {
        let progress = progress(selecting: "first")

        MapStepCreditor.credit(steps: 1_000, to: progress, catalog: Fixture.catalog, now: Fixture.morning)
        MapStepCreditor.credit(steps: 5_000, to: progress, catalog: Fixture.catalog, now: Fixture.evening)
        MapStepCreditor.credit(steps: 5_000, to: progress, catalog: Fixture.catalog,
                               now: Fixture.nextMorning)

        XCTAssertEqual(progress.finishedAt(forMap: "first"), Fixture.morning,
                       "the first crossing, not the last")
    }

    /// THE AC: the counter is not capped at the total. `totalSteps` is a finish line, not a
    /// ceiling — a capped counter would make a finished map's progress figure stop moving, which
    /// US-119 draws.
    func testRecordedStepsAreNotCappedAtTheTotal() {
        let progress = progress(selecting: "first")

        MapStepCreditor.credit(steps: 4_500, to: progress, catalog: Fixture.catalog, now: Fixture.morning)

        XCTAssertEqual(progress.recorded(forMap: "first"), 4_500, "past the 1,000 total, uncapped")
        XCTAssertTrue(progress.isFinished(forMap: "first"))
    }

    /// A zero or negative delta is not progress. Nothing produces a negative one — `claim` floors
    /// at zero — but a counter that could be walked backwards by a revised HealthKit sample is the
    /// bug that rule exists to prevent, so it is pinned here too.
    func testAnEmptyDeltaChangesNothing() {
        let progress = progress(selecting: "first")

        XCTAssertEqual(MapStepCreditor.credit(steps: 0, to: progress, catalog: Fixture.catalog,
                                              now: Fixture.morning), 0)
        XCTAssertEqual(MapStepCreditor.credit(steps: -50, to: progress, catalog: Fixture.catalog,
                                              now: Fixture.morning), 0)
        XCTAssertEqual(progress.recordedByMap, [:])
    }

    /// Switching the selection moves where NEW steps go, and nothing else. This is the rule at its
    /// smallest; `MapAccrualTests` proves it through a real refresh.
    func testSwitchingTheSelectionLeavesTheAlreadyCreditedStepsWhereTheyWere() {
        let progress = progress(selecting: "first")
        MapStepCreditor.credit(steps: 600, to: progress, catalog: Fixture.catalog, now: Fixture.morning)

        progress.selectedMapId = "second"
        MapStepCreditor.credit(steps: 400, to: progress, catalog: Fixture.catalog, now: Fixture.evening)

        XCTAssertEqual(progress.recorded(forMap: "first"), 600, "banked steps never move")
        XCTAssertEqual(progress.recorded(forMap: "second"), 400)
    }
}

// MARK: - The de-duplication the accrual is credited from

final class MetricLedgerClaimTests: XCTestCase {
    private func ledger(on day: String = "2026-07-17 00:00") -> MetricLedger {
        MetricLedger(day: Fixture.losAngeles.startOfDay(for: Fixture.date(day)))
    }

    /// THE AC, at the level it is actually decided: a day's step total read twice is claimed once.
    /// A health reading is cumulative — 1,000 steps at noon is still those same 1,000 at 18:00 —
    /// so a second claim of the same total must be worth nothing.
    func testTheSameDayTotalIsClaimedOnce() {
        let ledger = ledger()

        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.morning,
                                    calendar: Fixture.losAngeles), 1_000)
        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.evening,
                                    calendar: Fixture.losAngeles), 0)
    }

    /// A day that grew claims only the growth.
    func testOnlyTheNewPartOfADayTotalIsClaimed() {
        let ledger = ledger()

        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.morning,
                                    calendar: Fixture.losAngeles), 1_000)
        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 1_600, now: Fixture.evening,
                                    calendar: Fixture.losAngeles), 600)
    }

    /// A reading that went DOWN — deleted from the Health app, or revised by its source — claims
    /// nothing and takes nothing back.
    func testAReadingThatWentDownClaimsNothing() {
        let ledger = ledger()
        _ = ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.morning, calendar: Fixture.losAngeles)

        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 400, now: Fixture.evening,
                                    calendar: Fixture.losAngeles), 0)
        XCTAssertEqual(ledger.creditedToday[.healthSteps], 1_000, "and the baseline does not shrink")
    }

    /// Midnight starts the baseline over, because the READING started over: yesterday's 1,000-step
    /// baseline against today's fresh count would refuse to credit today until it out-walked
    /// yesterday.
    func testANewDayStartsTheBaselineOver() {
        let ledger = ledger()
        _ = ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.morning, calendar: Fixture.losAngeles)

        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 300, now: Fixture.nextMorning,
                                    calendar: Fixture.losAngeles), 300)
        XCTAssertEqual(ledger.day, Fixture.losAngeles.startOfDay(for: Fixture.nextMorning))
    }

    /// Metrics claim independently — banking steps must not spend the day's exercise minutes.
    func testEachMetricHasItsOwnBaseline() {
        let ledger = ledger()

        XCTAssertEqual(ledger.claim(.healthSteps, dayTotal: 1_000, now: Fixture.morning,
                                    calendar: Fixture.losAngeles), 1_000)
        XCTAssertEqual(ledger.claim(.healthExerciseMinutes, dayTotal: 30, now: Fixture.morning,
                                    calendar: Fixture.losAngeles), 30)
    }
}

// MARK: - Accrual through a real refresh, persisted

@MainActor
final class MapAccrualTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("MapAccrual.store") }
    private var steps: FixtureSampleFetcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        steps = FixtureSampleFetcher()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// Today's step total, as HealthKit would report it: one cumulative figure that grows through
    /// the day and is re-read whole every refresh.
    private func walked(_ count: Double) {
        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 07:00"),
                         end: Fixture.date("2026-07-17 07:30"),
                         value: count)
        ]
    }

    private func makeModel(now: @escaping () -> Date = { Fixture.morning }) -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            maps: Fixture.catalog,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: now,
            chooseStartingDigitama: { $0.first }
        )
    }

    /// THE AC: two overlapping reads of the same 1,000 steps credit the map 1,000, not 2,000.
    /// This is the one that would have shipped as a doubled counter if the accrual had been
    /// credited the reading instead of the delta.
    func testTwoOverlappingReadsCreditTheMapOnce() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        walked(1_000)
        await model.refresh()
        await model.refresh()

        let progress = try XCTUnwrap(model.mapProgress)
        XCTAssertEqual(progress.recorded(forMap: "first"), 1_000)
    }

    /// And a day that grew credits only the growth: 1,000 in the morning and 1,600 by the evening
    /// is a 1,600-step day, not a 2,600-step one.
    func testALaterReadCreditsOnlyTheNewSteps() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        walked(1_000)
        await model.refresh()

        walked(1_600)
        await model.refresh()

        XCTAssertEqual(try XCTUnwrap(model.mapProgress).recorded(forMap: "first"), 1_600)
    }

    /// AC: only steps read WHILE a map is selected accrue to it. Steps walked before anywhere was
    /// chosen are gone from the map's point of view — they were banked against the day, and
    /// choosing a map does not reach back for them.
    func testStepsWalkedBeforeAMapWasChosenDoNotAccrue() async throws {
        walked(1_000)
        let model = makeModel()
        await model.start()          // refreshes once, with no map selected

        model.selectMap("first")
        await model.refresh()

        XCTAssertEqual(try XCTUnwrap(model.mapProgress).recorded(forMap: "first"), 0)
    }

    /// THE AC: switching maps mid-day leaves already-credited steps exactly where they were, and
    /// only what is read afterwards goes to the new map.
    func testSwitchingMapsMidDayLeavesTheCreditedStepsWhereTheyWere() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        walked(600)
        await model.refresh()

        model.selectMap("second")
        walked(1_000)                // 400 more steps, walked in the second map
        await model.refresh()

        let progress = try XCTUnwrap(model.mapProgress)
        XCTAssertEqual(progress.recorded(forMap: "first"), 600, "banked steps never move")
        XCTAssertEqual(progress.recorded(forMap: "second"), 400, "only the new ones follow")
    }

    /// AC: recorded steps and the finish stamp persist across launches. A second model over the
    /// same store file is what a cold launch is.
    func testProgressAndSelectionSurviveALaunch() async throws {
        let first = makeModel()
        await first.start()
        first.selectMap("first")

        walked(1_200)
        await first.refresh()
        let finishedAt = try XCTUnwrap(first.mapProgress?.finishedAt(forMap: "first"))

        let second = makeModel()
        await second.start()

        let progress = try XCTUnwrap(second.mapProgress)
        XCTAssertEqual(progress.recorded(forMap: "first"), 1_200)
        XCTAssertEqual(progress.selectedMapId, "first", "and the player is still where they were")
        XCTAssertEqual(progress.finishedAt(forMap: "first"), finishedAt)
        XCTAssertEqual(second.selectedMapAsset, "01_grassland",
                       "so US-115 draws the saved map on a cold launch")
    }

    /// The finish fires through the real path, once, and the counter keeps climbing past it.
    func testAMapFinishesOnceAndKeepsCounting() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        walked(1_000)
        await model.refresh()
        let stamp = try XCTUnwrap(model.mapProgress?.finishedAt(forMap: "first"))

        walked(4_000)
        await model.refresh()

        let progress = try XCTUnwrap(model.mapProgress)
        XCTAssertEqual(progress.finishedAt(forMap: "first"), stamp, "not re-stamped")
        XCTAssertEqual(progress.recorded(forMap: "first"), 4_000, "and not capped at 1,000")
    }

    /// A save that has never chosen a map plays exactly as it did before this story: the refresh
    /// credits energy as usual and no counter is opened.
    func testWithNoMapSelectedNothingIsRecordedAndTheGameStillCreditsEnergy() async throws {
        walked(1_000)
        let model = makeModel()
        await model.start()

        await model.refresh()

        XCTAssertEqual(try XCTUnwrap(model.mapProgress).recordedByMap, [:])
        XCTAssertNil(model.selectedMapAsset, "and nothing is drawn behind the Digimon")
        XCTAssertEqual(model.state?.stageEnergy.strength, 10, "1,000 steps at 1 per 100")
    }

    /// The map outlives the Digimon: a death and a fresh egg must not send the player back to the
    /// start of the grassland. `resetGame` deletes the `GameState` and nothing else, which is why.
    func testMapProgressSurvivesARebirth() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        walked(1_000)
        await model.refresh()

        let store = try GameStore(url: storeURL)
        try store.rebirth(digitamaId: "agu_digitama", now: Fixture.evening)
        let progress = try store.loadOrCreateMapProgress()

        XCTAssertEqual(progress.recorded(forMap: "first"), 1_000)
        XCTAssertEqual(progress.selectedMapId, "first")
    }

    /// Selecting a map is what puts its art behind the Digimon (the US-115 seam), and selecting
    /// nowhere takes it away again.
    func testSelectingAMapPublishesItsBackgroundAsset() async throws {
        let model = makeModel()
        await model.start()
        XCTAssertNil(model.selectedMapAsset)

        model.selectMap("second")
        XCTAssertEqual(model.selectedMapAsset, "02_river")

        model.selectMap(nil)
        XCTAssertNil(model.selectedMapAsset)
    }
}
