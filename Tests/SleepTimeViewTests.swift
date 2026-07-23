import SwiftUI
import XCTest

@testable import DigiVPet

/// US-213 — the screen behind the grid's Sleep button.
///
/// What can be asserted here is the arithmetic the screen speaks with: the clamp, the "fully rested"
/// condition, and that the numbers it is built from are the SAME pair the button's ring is drawn
/// from. That the screen actually pushes and reads well on a watch is a Simulator screenshot,
/// recorded in progress.txt rather than faked here. US-214's per-Digimon schedule is tested as a
/// pure function in `SleepRoutineTests`; what is asserted here is only that this screen shows the
/// ACTIVE Digimon's one.
@MainActor
final class SleepTimeViewTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("SleepTime.store") }
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// AC4's other half: the screen a tap opens spells out exactly what the ring showed. Driven
    /// through the very expressions `ContentView` hands both — `model.sleepHours` and
    /// `model.sleepHoursCap` — so a call site that started feeding the screen a different number from
    /// the button would fail here rather than only under someone's thumb.
    func testTheScreenIsBuiltFromTheSameNumbersAsTheRing() async throws {
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: now)
        state.currentDigimonId = "agumon"
        state.stage = .child
        state.creditSleep(minutes: 6 * 60)
        try store.save()

        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher()),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher())
            ),
            now: { [now] in now }
        )
        await model.start()

        let view = SleepTimeView(sleptHours: model.sleepHours, goalHours: model.sleepHoursCap)
        let ring = DashRing(filled: model.sleepHours, total: model.sleepHoursCap, tint: .indigo)

        XCTAssertEqual(view.sleptHours, 6)
        XCTAssertEqual(view.goalHours, MainScreenModel.sleepHoursDisplayCap)
        XCTAssertEqual(ring.solid, DashRingLayout.solidSegments(filled: view.sleptHours,
                                                                total: view.goalHours),
                       "the ring and the screen it opens are the same fraction")
    }

    /// The headline number is bounded by the ceiling it is read against — a Digimon that banked more
    /// than a full night reads as rested rather than as "19 of 16", the same clamp the ring and the
    /// spoken value apply.
    func testTheHeadlineHoursAreBoundedByTheGoal() {
        XCTAssertEqual(SleepTimeView(sleptHours: 6, goalHours: 16).clampedHours, 6)
        XCTAssertEqual(SleepTimeView(sleptHours: 0, goalHours: 16).clampedHours, 0)
        XCTAssertEqual(SleepTimeView(sleptHours: 19, goalHours: 16).clampedHours, 16)
        XCTAssertEqual(SleepTimeView(sleptHours: -1, goalHours: 16).clampedHours, 0)
        XCTAssertEqual(SleepTimeView(sleptHours: 6, goalHours: 0).clampedHours, 0,
                       "no ceiling is an empty screen, not a negative one")
    }

    /// US-214: the schedule under the total belongs to the Digimon that is OUT. Driven through
    /// `model.activeDigimonId`, the expression `ContentView` hands the screen, and asserted against
    /// the routine that id derives — so a call site that started passing the wrong id (or the egg's
    /// id after a hatch) shows the wrong bedtime here rather than only on someone's wrist.
    func testTheScheduleIsTheActiveDigimonsOwn() async throws {
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: now)
        state.currentDigimonId = "gabumon"
        state.stage = .child
        try store.save()

        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher()),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher())
            ),
            now: { [now] in now }
        )
        await model.start()

        XCTAssertEqual(model.activeDigimonId, "gabumon")
        let view = SleepTimeView(sleptHours: model.sleepHours, goalHours: model.sleepHoursCap,
                                 digimonId: model.activeDigimonId)
        XCTAssertEqual(view.routine, SleepRoutine.forDigimon(id: "gabumon"))
        XCTAssertEqual(view.routine.bedtime.formatted, "21:45")
        XCTAssertNotEqual(view.routine, SleepRoutine.forDigimon(id: "agumon"),
                          "a different Digimon would be shown different hours")
    }

    /// A screen built without an id still has a schedule: `SleepRoutine` is total, so the half of
    /// this view US-214 added is never blank — the default is simply the empty id's own routine.
    func testTheScheduleHalfIsNeverBlank() {
        let view = SleepTimeView(sleptHours: 6, goalHours: 16)
        XCTAssertEqual(view.digimonId, "")
        XCTAssertEqual(view.routine, SleepRoutine.forDigimon(id: ""))
        XCTAssertGreaterThan(view.routine.totalMinutes, 0)
    }

    /// "Fully rested" is the caption at the goal and past it, and nothing before it — including on a
    /// save with no ceiling at all, where a Digimon that has slept nothing must not be congratulated.
    func testFullyRestedStartsAtTheGoalAndNotBefore() {
        XCTAssertFalse(SleepTimeView(sleptHours: 15, goalHours: 16).isFullyRested)
        XCTAssertTrue(SleepTimeView(sleptHours: 16, goalHours: 16).isFullyRested)
        XCTAssertTrue(SleepTimeView(sleptHours: 19, goalHours: 16).isFullyRested)
        XCTAssertFalse(SleepTimeView(sleptHours: 0, goalHours: 0).isFullyRested)
    }
}

// MARK: - No health data

/// The Simulator has no HealthKit history, and this screen is about STORED sleep in any case: the
/// hours are credited into the saved record directly above, so nothing here should be read live.
/// Both fetchers return nothing, which is what every other model-level suite does.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
