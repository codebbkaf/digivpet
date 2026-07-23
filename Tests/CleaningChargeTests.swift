import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-178 — cleaning poop costs a global handwash charge.
///
/// The last arm of the care loop to draw on a real-world action: clearing the mess spends a charge
/// walked up from HealthKit handwashing, capped at two and shared across the whole box of Digimon
/// rather than banked on one. This suite is about three things — the charge arithmetic on the
/// profile, `clean()` spending exactly one and refusing at zero, and a real refresh crediting washes
/// off an injected fixture reader (the Simulator has no handwashing data, so a live query would test
/// nothing).
///
/// No test waits real time or queries live HealthKit: the clock is a chosen `Date` and the washes
/// come from a fixture `HealthMetricSampleFetching`.

private enum Clock {
    /// Mid-afternoon in the zone below, so nothing here is caught inside the fallback sleep window,
    /// and comfortably clear of midnight so the day's handwashing window holds every fixture sample.
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// Empty energy readers: this suite is about handwashing, and steps/calories/sleep must credit
/// nothing so the only currency moving is the one under test.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// Hands back `count` handwashing events on `day`, and nothing for any other metric. The category
/// rule counts samples and ignores their value, so the value is a filler zero. Ignores the interval
/// like `FixtureMetricFetcher` does — the window rule is the reader's, not the fetcher's.
private final class HandwashFetcher: HealthMetricSampleFetching, @unchecked Sendable {
    let count: Int
    let day: Date

    init(count: Int, day: Date) {
        self.count = count
        self.day = day
    }

    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample] {
        guard metric.metric == .healthHandwashing else { return [] }
        return (0..<count).map { i in
            let start = day.addingTimeInterval(Double(i) * 60)
            return HealthSample(start: start, end: start.addingTimeInterval(20), value: 0)
        }
    }
}

@MainActor
final class CleaningChargeTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CleaningChargeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    // MARK: - The charge arithmetic on the profile

    /// One wash at one-per-charge is one charge — the shipped rate.
    func testOneWashBuysOneCharge() {
        let profile = PlayerProfile()
        profile.creditCleanCharges(events: 1, eventsPerCharge: 1, maxCharges: 2)
        XCTAssertEqual(profile.cleanCharges, 1)
    }

    /// Never past the cap, and the excess is dropped rather than held toward an uncollectable charge.
    func testWashesCapAtMaxAndDropTheRemainder() {
        let profile = PlayerProfile()
        profile.creditCleanCharges(events: 5, eventsPerCharge: 1, maxCharges: 2)
        XCTAssertEqual(profile.cleanCharges, 2, "capped, not five")
        XCTAssertEqual(profile.handwashProgress, 0, "no remainder is held at the cap")
    }

    /// Sub-threshold washing is not thrown away between reads when a charge costs more than one
    /// event — the same remainder the step path keeps.
    func testSubThresholdWashesAccumulateAcrossReads() {
        let profile = PlayerProfile()
        profile.creditCleanCharges(events: 2, eventsPerCharge: 3, maxCharges: 2)
        XCTAssertEqual(profile.cleanCharges, 0, "two of three is not yet a charge")
        profile.creditCleanCharges(events: 2, eventsPerCharge: 3, maxCharges: 2)
        XCTAssertEqual(profile.cleanCharges, 1, "and the two reads together cross the threshold")
    }

    /// Spending is the one way a charge leaves, and a spend at zero is refused.
    func testSpendingAChargeDecrementsAndRefusesAtZero() {
        let profile = PlayerProfile(cleanCharges: 1)
        XCTAssertTrue(profile.spendCleanCharge())
        XCTAssertEqual(profile.cleanCharges, 0)
        XCTAssertFalse(profile.spendCleanCharge(), "nothing to spend")
        XCTAssertEqual(profile.cleanCharges, 0)
    }

    // MARK: - AC2/AC4: clean() spends a charge, and refuses at zero

    /// AC4's zero case, THE headline: cleaning at zero charges is a no-op that leaves the mess where
    /// it is and says why — the same "go" affordance the battle currency uses.
    func testCleaningAtZeroChargesIsANoOpAndSaysSo() async throws {
        let model = try await startedModel(named: "zero", handwashes: 0)
        try stagePoop(in: model)
        XCTAssertEqual(model.cleanCharges, 0, "no washes were read")

        XCTAssertFalse(model.clean(), "cleaning is unavailable")
        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops, "the mess is untouched")
        XCTAssertEqual(model.actionMessage, "No charge — go wash.")
    }

    /// AC4's other case: with a charge in hand, cleaning zeroes the mess and spends exactly one.
    func testCleaningAtOneChargeDecrementsAndZeroesPoop() async throws {
        let model = try await startedModel(named: "one", handwashes: 0)
        try stagePoop(in: model)
        model.profile?.cleanCharges = 1

        XCTAssertTrue(model.clean())
        XCTAssertEqual(model.poopCount, 0, "the mess is cleared")
        XCTAssertEqual(model.cleanCharges, 0, "exactly one charge, spent on the clean")
    }

    /// The two ends of AC4 in one run, so the decrement is a difference and not a coincidence: two
    /// charges, two cleans, and the third clean finds nothing left to spend.
    func testEachCleanSpendsOneChargeUntilThereAreNone() async throws {
        let model = try await startedModel(named: "twice", handwashes: 0)
        model.profile?.cleanCharges = 2

        try stagePoop(in: model)
        XCTAssertTrue(model.clean())
        XCTAssertEqual(model.cleanCharges, 1)

        try stagePoop(in: model)
        XCTAssertTrue(model.clean())
        XCTAssertEqual(model.cleanCharges, 0)

        try stagePoop(in: model)
        XCTAssertFalse(model.clean(), "no charge left")
        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops)
    }

    // MARK: - AC1: washes credit charges through a real refresh

    /// The wiring end to end: a refresh that reads two handwashes banks two cleaning charges on the
    /// GLOBAL profile — not on the Digimon — so the whole box cleans out of one larder of washes.
    func testARefreshCreditsHandwashingToTheProfile() async throws {
        let model = try await startedModel(named: "credit", handwashes: 2)

        XCTAssertEqual(model.profile?.cleanCharges, 2, "two washes, two charges")
        XCTAssertEqual(model.cleanCharges, 2, "and the bar reads them off the profile")
    }

    /// A day's washes are counted once, however many times the app refreshes — the same
    /// `MetricLedger` de-duplication the step and calorie paths lean on. A second refresh of the same
    /// day's single wash must not hand out a second charge.
    func testRefreshingTwiceCreditsTheSameWashesOnce() async throws {
        let model = try await startedModel(named: "dedup", handwashes: 1)
        XCTAssertEqual(model.cleanCharges, 1, "one wash, one charge")

        await model.refresh()

        XCTAssertEqual(model.cleanCharges, 1, "the same wash is not counted twice")
    }

    // MARK: - AC3: the bar reads the profile and the config

    /// The DashBar's two inputs: the count off the profile and the total off the shipped config, so a
    /// retune of `maxCleanCharges` moves the bar without a code change.
    func testTheBarReadsTheProfileCountAndTheConfigCap() async throws {
        let model = try await startedModel(named: "bar", handwashes: 0)
        XCTAssertEqual(model.cleanChargeCap, ConsumptionConfig.bundled.maxCleanCharges)
        XCTAssertEqual(model.cleanChargeCap, 8, "US-199 raised the handwash goal to 8")

        model.profile?.cleanCharges = 1
        XCTAssertEqual(model.cleanCharges, 1)
    }

    // MARK: - Helpers

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// Winds the poop clock back half a day and runs the SHIPPED rule, filling the screen to clean.
    private func stagePoop(in model: MainScreenModel) throws {
        let state = try XCTUnwrap(model.state)
        state.poopUpdatedAt = Clock.start.addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: false, now: Clock.start)
        XCTAssertEqual(state.poopCount, PoopClock.maximumPoops, "staged a full screen to clean")
    }

    /// A Child in the shipped `agumon` line with no outgoing edges, so nothing here can evolve. The
    /// egg exists only because `start()` resolves a starting Digitama before it loads.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, line: "dmc-v1",
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, line: "dmc-v1",
                          spriteFile: "Agumon")
        ])
    }

    /// A started model reading a saved "hero" off disk, its refresh fed `handwashes` washes on the
    /// clock's day from a fixture reader.
    private func startedModel(named name: String, handwashes: Int) async throws -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .child
        // US-027: without these the audit charges a mistake per day since the epoch and could sicken
        // the Digimon before a single clean.
        state.healthDataLastSeen = Clock.start
        state.hungerUpdatedAt = Clock.start
        state.stageEnteredDate = Clock.start
        try seeding.save()

        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            // Deliberately EMPTY: "hero" is in the fixture graph, which carries both its line and its
            // stage, so a roster consulted at all would be a bug.
            roster: Roster(entries: []),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            metricReader: HealthMetricReader(fetcher: HandwashFetcher(count: handwashes,
                                                                      day: Clock.start)),
            calendar: Clock.calendar,
            now: { Clock.start },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }
}
