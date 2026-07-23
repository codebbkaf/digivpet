import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-179 — wire the metric ledger into the health-read flow.
///
/// Before this, `MetricCreditor.credit` was called only in tests and `ConditionContext.readings` was
/// always empty, so every `health.*` evolution condition was dead: an `atLeast` could never pass, an
/// `atMost` passed for free, and a standing measurement (resting heart rate, VO2 max) was forced to
/// `.unknown`. Two layers here: pure tests prove a credited total and a supplied reading reach
/// `ConditionEvaluator`, and model tests drive the real `refresh()` so the wiring itself — that
/// `MetricCreditor` is actually called, and that its readings reach `evolveIfReady` — is exercised
/// end to end. No test waits real time or queries live HealthKit: the clock is injected and every
/// reading comes from a fixture fetcher.

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

    static func startOfDay(_ iso: String) -> Date { losAngeles.startOfDay(for: date(iso)) }

    static let morning = date("2026-07-17 08:00")
    static let lastStage = date("2026-07-01 08:00")
}

/// Empty energy readers: these suites are about the metric ledger, so steps/calories/sleep read
/// nothing unless a test asks for it, and the only currency moving is the one under test.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// Hands back one sample carrying `values[metric]` on `day`, and nothing for any other metric, so a
/// refresh reads exactly the day totals a test names. One sample so an `averageQuantity` metric reads
/// its value straight through rather than being blended — enough for the standing-metric case. The
/// interval is ignored, like `HandwashFetcher`'s: the window rule is the reader's, not the fetcher's.
private final class FixtureMetricFetcher: HealthMetricSampleFetching, @unchecked Sendable {
    let values: [ConditionMetric: Double]
    let day: Date

    init(values: [ConditionMetric: Double], day: Date) {
        self.values = values
        self.day = day
    }

    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample] {
        guard let value = values[metric.metric] else { return [] }
        let start = day.addingTimeInterval(60 * 60)
        return [HealthSample(start: start, end: start.addingTimeInterval(60), value: value)]
    }
}

// MARK: - The data reaches ConditionEvaluator (AC4, AC5)

final class MetricConditionReachTests: XCTestCase {
    /// AC4: a credited `health.sleep` total reaches an `atLeast` and an `atMost` condition. 480
    /// credited minutes satisfy `atLeast 400` and, being ABOVE 400, fail `atMost 400` — so the
    /// number really flows through `MetricCreditor` → the stage total → `ConditionContext` →
    /// `ConditionEvaluator`, which is the whole point of the wiring.
    func testACreditedSleepTotalReachesAtLeastAndAtMostConditions() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Fixture.morning)
        let ledger = MetricLedger(day: Fixture.startOfDay("2026-07-17 08:00"))
        MetricCreditor.credit([.healthSleep: .value(480)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)
        XCTAssertEqual(state.stageMetricTotals[.healthSleep], 480, "the sleep minutes were banked")

        let context = ConditionContext(state: state, now: Fixture.date("2026-07-17 12:00"),
                                       calendar: Fixture.losAngeles)
        let atLeast = EvolutionCondition(metric: .healthSleep, window: .stage,
                                         comparison: .atLeast, value: 400, hint: "Sleep 400 minutes")
        let atMost = EvolutionCondition(metric: .healthSleep, window: .stage,
                                        comparison: .atMost, value: 400, hint: "Sleep at most 400 minutes")

        XCTAssertTrue(ConditionEvaluator.isSatisfied(atLeast, in: context),
                      "480 credited minutes clears the 400 floor")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(atMost, in: context),
                       "480 is above the 400 ceiling, so the atMost gate is not met")
    }

    /// AC5: a standing measurement supplied via `readings` is answerable — not forced to `.unknown`.
    /// A resting heart rate does not accumulate, so a running total can never answer it; only a
    /// direct read can, which is exactly what `readings` carries.
    func testAStandingMetricSuppliedViaReadingsIsAnswerable() {
        let answered = ConditionContext(stageTotals: .zero, lifetimeTotals: .zero,
                                        bestDayThisStage: .zero,
                                        readings: [.healthRestingHeartRate: .value(52)])
        let atMost = EvolutionCondition(metric: .healthRestingHeartRate, window: .lifetime,
                                        comparison: .atMost, value: 60, hint: "Rest below 60 bpm")
        let atLeast = EvolutionCondition(metric: .healthRestingHeartRate, window: .lifetime,
                                         comparison: .atLeast, value: 60, hint: "Rest above 60 bpm")

        XCTAssertTrue(ConditionEvaluator.isSatisfied(atMost, in: answered),
                      "a supplied 52 bpm answers the atMost gate")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(atLeast, in: answered),
                       "and 52 is below the 60 floor")

        // Without the reading it is unanswerable — `.unknown`, which fails either way. This is the
        // dead behaviour US-179 fixes: an empty `readings` could never answer a standing metric.
        let empty = ConditionContext(stageTotals: .zero, lifetimeTotals: .zero, bestDayThisStage: .zero)
        XCTAssertFalse(ConditionEvaluator.isSatisfied(atMost, in: empty),
                       "no read supplied → unknown → the gate stays shut")
    }
}

// MARK: - The wiring, through a real refresh (AC1, AC2, AC3)

@MainActor
final class MetricLedgerWiringTests: XCTestCase {
    private var storeDirectory: URL!
    private func storeURL(_ name: String) -> URL { storeDirectory.appendingPathComponent("\(name).store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MetricWiringTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// A Child "hero" whose strength branch also carries a standing-metric condition, so a test can
    /// prove `readings` reach the evolution check: the branch opens only when a resting heart rate is
    /// supplied and low enough. The spirit branch is an ordinary control.
    private func fixtureGraph(restingHeartRateAtMost: Double? = nil) -> EvolutionGraph {
        var conditions: [EvolutionCondition] = []
        if let ceiling = restingHeartRateAtMost {
            conditions = [EvolutionCondition(metric: .healthRestingHeartRate, window: .lifetime,
                                             comparison: .atMost, value: ceiling,
                                             hint: "A resting pulse under \(Int(ceiling))")]
        }
        return EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, line: "dmc-v1",
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, line: "dmc-v1",
                          spriteFile: "Agumon",
                          evolutions: [
                              EvolutionEdge(to: "greymon", requiredEnergy: .strength, minEnergy: 40,
                                            maxCareMistakes: 3, conditions: conditions),
                          ]),
            EvolutionNode(id: "greymon", displayName: "Greymon", stage: .adult, line: "dmc-v1",
                          spriteFile: "Greymon"),
        ])
    }

    /// A terminal "hero" — no outgoing edges, so it never evolves. The credit tests use this so the
    /// stage totals `MetricCreditor` writes are not immediately wiped by `enterStage`; the evolution
    /// tests want the branching graph above instead.
    private func terminalGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, line: "dmc-v1",
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, line: "dmc-v1",
                          spriteFile: "Agumon"),
        ])
    }

    /// A saved game already at "hero", strength-dominant so the branch's energy gate is met, over a
    /// store shared with the returned model. `metrics` is what the injected `HealthMetricReader` reads
    /// as today's totals. The care/light history is stamped so the fortnight this fixture spans charges
    /// no mistake — the same discipline `EvolutionApplyTests` keeps — so a blocked evolution can only
    /// be the condition under test.
    private func makeModelAtHero(
        storeName: String,
        graph: EvolutionGraph,
        metrics: [ConditionMetric: Double]
    ) throws -> (store: GameStore, model: MainScreenModel) {
        let url = storeURL(storeName)
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: Fixture.lastStage)
        state.stage = .child
        state.stageEnergy = EnergyTotals(strength: 60)
        state.careMistakeCount = 0
        state.healthDataLastSeen = Fixture.morning
        state.hungerUpdatedAt = Fixture.morning
        state.setLight(.off, now: Fixture.lastStage)
        state.stageEnteredDate = Fixture.lastStage
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: graph,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(), calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(), calendar: Fixture.losAngeles)
            ),
            metricReader: HealthMetricReader(fetcher: FixtureMetricFetcher(
                values: metrics, day: Fixture.startOfDay("2026-07-17 08:00"))),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first }
        )
        return (store, model)
    }

    /// AC1: a refresh calls `MetricCreditor.credit`, writing the day's reading into the stage,
    /// lifetime AND best-day totals — the three fields every `health.*` condition reads. Before this
    /// story these stayed empty because nothing in `Sources/` ever called the creditor.
    func testARefreshCreditsAnAccumulatingMetricToAllThreeTotals() async throws {
        let (_, model) = try makeModelAtHero(storeName: "credit", graph: terminalGraph(),
                                             metrics: [.healthFlightsClimbed: 12])
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.stageMetricTotals[.healthFlightsClimbed], 12, "stage total credited")
        XCTAssertEqual(state.lifetimeMetricTotals[.healthFlightsClimbed], 12, "lifetime total credited")
        XCTAssertEqual(state.stageBestDayMetrics[.healthFlightsClimbed], 12, "best day recorded")
    }

    /// AC3: refreshing twice in one day does not double-credit — the reading is a cumulative day
    /// total, de-duplicated through the shared `MetricLedger` the energy path already leans on. The
    /// second read of an unchanged day banks nothing.
    func testRefreshingTwiceInADayCreditsTheMetricOnce() async throws {
        let (_, model) = try makeModelAtHero(storeName: "dedup", graph: terminalGraph(),
                                             metrics: [.healthFlightsClimbed: 12])
        await model.start()
        await model.refresh()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.stageMetricTotals[.healthFlightsClimbed], 12,
                       "the same 12 flights are not banked as 24")
    }

    /// AC2 + AC5, end to end: `readings` reach `evolveIfReady`. The strength branch also needs a
    /// resting pulse at most 60; with 52 supplied through the metric reader the branch opens and the
    /// Digimon evolves — a standing metric no running total can hold, answered only because the
    /// refresh's read was handed to the condition check.
    func testAStandingMetricReadDrivesAConditionGatedEvolution() async throws {
        let (_, model) = try makeModelAtHero(
            storeName: "evolve", graph: fixtureGraph(restingHeartRateAtMost: 60),
            metrics: [.healthRestingHeartRate: 52])
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "greymon",
                       "a supplied 52 bpm met the atMost-60 gate and the branch opened")
        XCTAssertEqual(model.state?.stage, .adult)
    }

    /// The other side of AC2: with the pulse ABOVE the ceiling the condition fails and the branch
    /// stays shut — the read really decides it, rather than the edge opening regardless. A control for
    /// the test above, so a passing evolution cannot be a coincidence of the energy gate alone.
    func testAStandingMetricAboveTheCeilingBlocksTheEvolution() async throws {
        let (_, model) = try makeModelAtHero(
            storeName: "block", graph: fixtureGraph(restingHeartRateAtMost: 60),
            metrics: [.healthRestingHeartRate: 72])
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "hero",
                       "72 bpm fails the atMost-60 gate, so the Digimon does not evolve")
        XCTAssertEqual(model.state?.stage, .child)
    }
}
