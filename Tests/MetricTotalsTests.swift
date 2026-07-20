import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, so "midnight" means one thing wherever this
/// suite runs — the same fixture shape `EnergyCreditingTests` uses, and for the same reason.
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

    static func startOfDay(_ iso: String) -> Date {
        losAngeles.startOfDay(for: date(iso))
    }

    /// A fresh Digimon and a ledger opened on the same day — the state every credit runs against on
    /// a first launch.
    static func newGame(on day: String = "2026-07-17 08:00") -> (GameState, MetricLedger) {
        (
            GameState(currentDigimonId: "agu_digitama", now: date(day)),
            MetricLedger(day: startOfDay(day))
        )
    }
}

/// Every test here drives an injected `now` and an injected calendar. Nothing sleeps, and nothing
/// reads the wall clock — a suite that waited for midnight would take a day to run once.
final class MetricCreditingTests: XCTestCase {
    // MARK: - Accumulation

    /// The base case: a day's reading becomes a stage total and a lifetime total at once.
    func testCreditingAddsToStageAndLifetimeTotals() {
        let (state, ledger) = Fixture.newGame()

        let credited = MetricCreditor.credit(
            [.healthSteps: .value(4_000), .healthFlightsClimbed: .value(12)],
            to: state, ledger: ledger,
            now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(credited[.healthSteps], 4_000)
        XCTAssertEqual(credited[.healthFlightsClimbed], 12)
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 4_000)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 4_000)
        XCTAssertEqual(state.stageMetricTotals[.healthFlightsClimbed], 12)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthFlightsClimbed], 12)
    }

    /// A metric never credited reads as zero rather than as a missing key the caller must unwrap.
    func testAnUncreditedMetricReadsAsZero() {
        let (state, _) = Fixture.newGame()

        XCTAssertEqual(state.stageMetricTotals[.healthWorkouts], 0)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthWorkouts], 0)
        XCTAssertEqual(state.stageBestDayMetrics[.healthWorkouts], 0)
    }

    /// Days add up across a stage: this is what makes a `window: .stage` condition answerable at
    /// all, since no single day's reading could satisfy a stage-long criterion.
    func testTotalsAccumulateAcrossDays() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 20:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(6_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-18 20:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 10_000)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 10_000)
    }

    // MARK: - Idempotency

    /// THE AC: refreshing twice in one day does not double-count. The reading is a cumulative daily
    /// total, so the second read of an unchanged day must add nothing at all.
    func testRefreshingTwiceInADayDoesNotDoubleCount() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)
        let second = MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                                           now: Fixture.date("2026-07-17 13:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(second[.healthSteps], 0, "the same 4,000 steps must not be banked twice")
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 4_000)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 4_000)
    }

    /// A day that has grown since the last read is charged only for the DIFFERENCE.
    func testOnlyTheDeltaIsCreditedWhenADayGrows() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)
        let second = MetricCreditor.credit([.healthSteps: .value(7_500)], to: state, ledger: ledger,
                                           now: Fixture.date("2026-07-17 18:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(second[.healthSteps], 3_500)
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 7_500)
    }

    /// A reading that SHRINKS — data deleted in the Health app, or a source revising a sample —
    /// takes nothing back. Progress already earned is not un-earned.
    func testAShrinkingReadingNeverSubtracts() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(7_500)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)
        let second = MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                                           now: Fixture.date("2026-07-17 18:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(second[.healthSteps], 0)
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 7_500)
    }

    /// The baseline is per-DAY: a new local day starts over at zero, or today would not be credited
    /// until it out-walked yesterday. The clock is injected, so this crosses a midnight instantly.
    func testTheBaselineResetsAtLocalMidnight() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(9_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 23:00"), calendar: Fixture.losAngeles)
        let nextDay = MetricCreditor.credit([.healthSteps: .value(1_000)], to: state, ledger: ledger,
                                            now: Fixture.date("2026-07-18 07:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(nextDay[.healthSteps], 1_000, "a smaller new day is still a full new day")
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 10_000)
        XCTAssertEqual(ledger.day, Fixture.startOfDay("2026-07-18 07:00"))
    }

    /// Being told nothing is not being told zero: `noData` and `unavailable` bank nothing and, in
    /// particular, must not overwrite a real best day with a zero.
    func testNoDataAndUnavailableCreditNothing() {
        let (state, ledger) = Fixture.newGame()
        MetricCreditor.credit([.healthSteps: .value(9_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 20:00"), calendar: Fixture.losAngeles)

        let credited = MetricCreditor.credit(
            [.healthSteps: .noData, .healthFlightsClimbed: .unavailable],
            to: state, ledger: ledger,
            now: Fixture.date("2026-07-18 20:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(credited, .zero)
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 9_000)
        XCTAssertEqual(state.stageBestDayMetrics[.healthSteps], 9_000)
        XCTAssertEqual(state.stageMetricTotals[.healthFlightsClimbed], 0)
    }

    // MARK: - What may be accumulated

    /// A discrete measurement is NOT accumulated. Summing a resting heart rate over a stage gives a
    /// five-figure BPM that satisfies any criterion ever written — the exact trap US-057's
    /// `averageQuantity` exists to avoid. A condition on one of these reads its window directly.
    func testDiscreteQuantitiesAreNotAccumulated() {
        let (state, ledger) = Fixture.newGame()

        let credited = MetricCreditor.credit(
            [.healthRestingHeartRate: .value(58), .healthVO2Max: .value(42)],
            to: state, ledger: ledger,
            now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(credited, .zero)
        XCTAssertEqual(state.stageMetricTotals[.healthRestingHeartRate], 0)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthVO2Max], 0)
    }

    /// `care.*` counters are kept on `GameState` itself. Banking them here would create a second,
    /// disagreeing copy of the battle count.
    func testCareCountersAreNotAccumulated() {
        let (state, ledger) = Fixture.newGame()

        let credited = MetricCreditor.credit(
            [.careBattleCount: .value(3), .careTrainingSessions: .value(9)],
            to: state, ledger: ledger,
            now: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(credited, .zero)
        XCTAssertEqual(state.stageMetricTotals[.careBattleCount], 0)
    }

    /// Pins the whole vocabulary, so a metric added to `ConditionMetric` later cannot quietly land
    /// on the wrong side of the gate: every accumulating metric must be one whose aggregation adds
    /// up, and sleep — which is minutes — is the one readable-elsewhere exception.
    func testOnlyAdditiveMetricsAccumulate() {
        for metric in ConditionMetric.allCases {
            if metric == .healthSleep {
                XCTAssertTrue(metric.accumulatesOverTime, "sleep minutes add up")
                continue
            }
            guard let readable = ReadableHealthMetric(metric) else {
                XCTAssertFalse(metric.accumulatesOverTime, "\(metric.rawValue) has no HealthKit number to bank")
                continue
            }
            switch readable.aggregation {
            case .averageQuantity:
                XCTAssertFalse(metric.accumulatesOverTime, "\(metric.rawValue) is a measurement, not an amount")
            case .sumQuantity, .countEvents, .countStoodHours, .sumDurationMinutes:
                XCTAssertTrue(metric.accumulatesOverTime, "\(metric.rawValue) accumulates")
            }
        }
    }

    // MARK: - Best day (window: .day)

    /// THE AC: `window: .day` is the BEST day, not the current one. One good Tuesday still counts
    /// on Friday — and on a Wednesday spent on the sofa in between.
    func testTheBestDaySurvivesLaterWorseDays() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(12_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-14 22:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(300)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-15 22:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(1_100)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 22:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageBestDayMetrics[.healthSteps], 12_000)
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 13_400, "the stage total still counts every day")
    }

    /// A better day replaces the record, and the record tracks the day's growing total rather than
    /// the delta each read banked — three reads of one 12,000-step day are a 12,000-step day.
    func testABetterDayReplacesTheRecordAndTracksTheDaysTotal() {
        let (state, ledger) = Fixture.newGame()

        MetricCreditor.credit([.healthSteps: .value(5_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-14 22:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-15 10:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(9_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-15 16:00"), calendar: Fixture.losAngeles)
        MetricCreditor.credit([.healthSteps: .value(12_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-15 22:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageBestDayMetrics[.healthSteps], 12_000,
                       "the best day is one day's total, not the sum of its reads")
    }

    // MARK: - Evolution

    /// THE AC: stage totals reset when `stageEnteredDate` moves, and lifetime totals survive it.
    func testEnteringAStageClearsStageTotalsAndKeepsLifetimeOnes() {
        let (state, ledger) = Fixture.newGame()
        MetricCreditor.credit([.healthSteps: .value(12_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 22:00"), calendar: Fixture.losAngeles)
        state.stageEnergy = EnergyTotals(strength: 40, vitality: 0, spirit: 0, stamina: 0)

        let evolved = Fixture.date("2026-07-18 09:00")
        state.enterStage(at: evolved)

        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 0)
        XCTAssertEqual(state.stageBestDayMetrics[.healthSteps], 0, "a best day is earned per stage")
        XCTAssertEqual(state.stageEnergy, .zero)
        XCTAssertEqual(state.stageEnteredDate, evolved)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 12_000, "a lifetime total outlives the stage")
    }

    /// The lifetime total keeps growing THROUGH a reset rather than merely surviving it: the new
    /// stage's steps land on top of the old stage's, while the stage total starts from this stage.
    func testLifetimeTotalsKeepGrowingAcrossAStageReset() {
        let (state, ledger) = Fixture.newGame()
        MetricCreditor.credit([.healthSteps: .value(12_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 22:00"), calendar: Fixture.losAngeles)

        state.enterStage(at: Fixture.date("2026-07-18 09:00"))
        MetricCreditor.credit([.healthSteps: .value(5_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-19 22:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 5_000)
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 17_000)
    }

    /// Evolving mid-day must not hand the new stage the whole day again. The ledger is deliberately
    /// NOT reset by `enterStage`, so the morning's steps stay bought and only the afternoon's are
    /// credited to the new form.
    func testEvolvingMidDayDoesNotRebankTheMorning() {
        let (state, ledger) = Fixture.newGame()
        MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 11:00"), calendar: Fixture.losAngeles)

        state.enterStage(at: Fixture.date("2026-07-17 12:00"))
        MetricCreditor.credit([.healthSteps: .value(6_500)], to: state, ledger: ledger,
                              now: Fixture.date("2026-07-17 20:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 2_500,
                       "only the steps taken since the evolution belong to the new stage")
        XCTAssertEqual(state.lifetimeMetricTotals[.healthSteps], 6_500)
    }
}

/// Persistence: the totals are only useful if they outlive the process, since a `window: .stage`
/// condition spans days and every one of those days contains a cold launch.
@MainActor
final class MetricTotalsPersistenceTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("MetricTotals.store") }

    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MetricTotalsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// Writes all three totals, drops the container, then reads through a brand new one pointed at
    /// the same file — so what is asserted came off disk and not out of the first context's cache.
    func testTotalsRoundTripThroughTheStore() throws {
        do {
            let store = try GameStore(url: storeURL)
            let state = GameState(currentDigimonId: "greymon", stage: .adult, now: t0)
            state.stageMetricTotals[.healthSteps] = 12_000
            state.stageBestDayMetrics[.healthSteps] = 9_000
            state.lifetimeMetricTotals[.healthSteps] = 41_000
            state.lifetimeMetricTotals[.healthWorkouts] = 7
            store.container.mainContext.insert(state)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let loaded = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        XCTAssertEqual(loaded.stageMetricTotals[.healthSteps], 12_000)
        XCTAssertEqual(loaded.stageBestDayMetrics[.healthSteps], 9_000)
        XCTAssertEqual(loaded.lifetimeMetricTotals[.healthSteps], 41_000)
        XCTAssertEqual(loaded.lifetimeMetricTotals[.healthWorkouts], 7)
    }

    /// The ledger has to outlive the process too, or a cold launch would have no baseline and would
    /// bank today's steps a second time. This is the idempotency AC across a relaunch.
    func testTheLedgerBaselineSurvivesARelaunch() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000)
        do {
            let store = try GameStore(url: storeURL)
            let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: now)
            let ledger = try store.loadOrCreateMetricLedger(now: now)
            MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger, now: now)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let state = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: now)
        let ledger = try reopened.loadOrCreateMetricLedger(now: now)
        XCTAssertEqual(ledger.creditedToday[.healthSteps], 4_000, "the baseline came off disk")

        let credited = MetricCreditor.credit([.healthSteps: .value(4_000)], to: state, ledger: ledger, now: now)
        XCTAssertEqual(credited, .zero, "a cold launch must not re-bank the same day")
        XCTAssertEqual(state.stageMetricTotals[.healthSteps], 4_000)
    }
}
