import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-060 — the evolution engine evaluating an edge's US-056 `conditions`.
///
/// Everything here is pure and injected: hand-built nodes, a literal `ConditionContext`, and a
/// fixed calendar where a date is needed. Nothing reads HealthKit and nothing waits.
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

    static func condition(
        _ metric: ConditionMetric,
        _ comparison: ConditionComparison,
        _ value: Double,
        window: ConditionWindow = .stage
    ) -> EvolutionCondition {
        EvolutionCondition(metric: metric, window: window, comparison: comparison,
                           value: value, hint: "hint for \(metric.rawValue)")
    }

    /// A strength edge that qualifies on the four original gates for `EnergyTotals(strength: 50)`,
    /// so any failure a test sees comes from its conditions and nothing else.
    static func edge(
        to: String,
        conditions: [EvolutionCondition] = [],
        isDefault: Bool = false
    ) -> EvolutionEdge {
        EvolutionEdge(to: to, requiredEnergy: .strength, minEnergy: 40, maxCareMistakes: 99,
                      minBattleWins: nil, isDefault: isDefault, conditions: conditions)
    }

    /// The junk branch: ungated on energy (`minEnergy: 0`) and conditionless, so it qualifies on its
    /// own merits whenever the conditioned branch does not — and LOSES the `max(by: minEnergy)`
    /// tie-break to it whenever it does. That is how a real graph is authored, and it keeps the band
    /// test from depending on the order the edges happen to sit in.
    static func junk(to: String) -> EvolutionEdge {
        EvolutionEdge(to: to, requiredEnergy: .strength, minEnergy: 0, maxCareMistakes: 99,
                      minBattleWins: nil, isDefault: true, conditions: [])
    }

    /// A default edge that does NOT qualify on the four gates — it wants a different dominant type.
    /// Reaching it therefore proves the `isDefault` FALLBACK fired, not that it merely qualified.
    static func unqualifyingDefault(to: String) -> EvolutionEdge {
        EvolutionEdge(to: to, requiredEnergy: .spirit, minEnergy: 999, maxCareMistakes: 99,
                      minBattleWins: nil, isDefault: true, conditions: [])
    }

    static func hero(_ edges: [EvolutionEdge]) -> EvolutionNode {
        EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon",
                      evolutions: edges)
    }

    /// The engine's answer for `node` with the four original gates satisfied.
    static func target(_ node: EvolutionNode, _ context: ConditionContext) -> String? {
        EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 0, conditions: context)
    }

    /// A context that answers the stage totals and the care counters, and nothing else.
    static func context(
        stageSteps: Double = 0,
        trainingSessions: Int = 0,
        readings: [ConditionMetric: HealthReading] = [:]
    ) -> ConditionContext {
        var totals = MetricTotals.zero
        totals[.healthSteps] = stageSteps
        return ConditionContext(
            stageTotals: totals,
            lifetimeTotals: totals,
            bestDayThisStage: totals,
            trainingSessionsThisStage: trainingSessions,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesToday: 0,
            battlesLifetime: 0,
            battleWinRatioLifetime: 0,
            readings: readings)
    }
}

final class ConditionEvaluationTests: XCTestCase {

    // MARK: - AC1/AC3: a condition met, a condition unmet, and no conditions at all

    func testAMetConditionLetsTheEdgeQualify() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [Fixture.condition(.healthSteps, .atLeast, 10_000)])
        ])

        XCTAssertEqual(Fixture.target(node, Fixture.context(stageSteps: 12_000)), "greymon")
    }

    func testAnUnmetConditionBlocksAnOtherwiseQualifyingEdge() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [Fixture.condition(.healthSteps, .atLeast, 10_000)])
        ])

        // The four original gates all pass here — only the condition fails.
        XCTAssertNil(Fixture.target(node, Fixture.context(stageSteps: 9_999)))
    }

    func testTheThresholdIsInclusiveOnBothSides() {
        let atLeast = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [Fixture.condition(.healthSteps, .atLeast, 10_000)])
        ])
        let atMost = Fixture.hero([
            Fixture.edge(to: "numemon", conditions: [Fixture.condition(.healthSteps, .atMost, 10_000)])
        ])

        XCTAssertEqual(Fixture.target(atLeast, Fixture.context(stageSteps: 10_000)), "greymon",
                       "atLeast is >=, so exactly the threshold qualifies")
        XCTAssertEqual(Fixture.target(atMost, Fixture.context(stageSteps: 10_000)), "numemon",
                       "atMost is <=, so exactly the threshold qualifies")
    }

    /// The story's AC3: an edge with `conditions == []` is decided by the four original gates alone.
    /// `EvolutionTests` asserts this at length without ever passing a context; this pins the same
    /// thing from the conditions side, including that the default `.unknown` context — which fails
    /// every condition it is asked — cannot block an edge that asks nothing.
    func testAConditionlessEdgeIsUnaffectedByAnEmptyContext() {
        let node = Fixture.hero([Fixture.edge(to: "greymon")])

        XCTAssertEqual(Fixture.target(node, .unknown), "greymon")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(
                for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
                careMistakes: 0, battleWins: 0),
            "greymon",
            "the context argument is defaulted, so the old call site compiles and behaves the same")
    }

    // MARK: - AC2: the four original gates still decide

    func testTheOriginalGatesStillFailEvenWithEveryConditionMet() {
        let node = Fixture.hero([
            EvolutionEdge(to: "greymon", requiredEnergy: .strength, minEnergy: 40,
                          maxCareMistakes: 0, minBattleWins: 5, isDefault: false,
                          conditions: [Fixture.condition(.healthSteps, .atLeast, 1)])
        ])
        let context = Fixture.context(stageSteps: 99_999)

        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .spirit,
            careMistakes: 0, battleWins: 9, conditions: context), "dominant type still gates")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 20), dominant: .strength,
            careMistakes: 0, battleWins: 9, conditions: context), "minEnergy still gates")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 3, battleWins: 9, conditions: context), "maxCareMistakes still gates")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 2, conditions: context), "minBattleWins still gates")
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 9, conditions: context), "greymon",
            "and all four together with the condition met still qualifies")
    }

    // MARK: - AC4: multiple conditions are conjunctive

    func testEveryConditionMustPassForTheEdgeToQualify() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [
                Fixture.condition(.healthSteps, .atLeast, 10_000),
                Fixture.condition(.careTrainingSessions, .atLeast, 8),
            ])
        ])

        XCTAssertEqual(
            Fixture.target(node, Fixture.context(stageSteps: 12_000, trainingSessions: 8)),
            "greymon")
        XCTAssertNil(
            Fixture.target(node, Fixture.context(stageSteps: 12_000, trainingSessions: 7)),
            "the second condition fails, so the edge does not qualify")
        XCTAssertNil(
            Fixture.target(node, Fixture.context(stageSteps: 500, trainingSessions: 8)),
            "the first condition fails, so the edge does not qualify")
    }

    // MARK: - AC6: a band is a closed interval

    /// The Digital Monster Color pattern: 8–31 sessions earns the good branch, 0–7 and 32+ both
    /// fall to the junk one. Overtraining is punished exactly as much as undertraining.
    func testABandIsAClosedIntervalAndOvertrainingFallsToTheJunkBranch() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [
                Fixture.condition(.careTrainingSessions, .atLeast, 8),
                Fixture.condition(.careTrainingSessions, .atMost, 31),
            ]),
            Fixture.junk(to: "numemon"),
        ])

        func branch(sessions: Int) -> String? {
            EvolutionEngine.scheduledEvolutionTarget(
                for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
                careMistakes: 0, battleWins: 0,
                stageEnteredAt: Fixture.date("2026-07-01 08:00"), now: Fixture.morning,
                conditions: Fixture.context(trainingSessions: sessions))
        }

        XCTAssertEqual(branch(sessions: 7), "numemon", "undertrained: below the band")
        XCTAssertEqual(branch(sessions: 8), "greymon", "the lower bound is inside the band")
        XCTAssertEqual(branch(sessions: 20), "greymon", "inside the band")
        XCTAssertEqual(branch(sessions: 31), "greymon", "the upper bound is inside the band")
        XCTAssertEqual(branch(sessions: 32), "numemon", "overtrained: above the band")
    }

    // MARK: - AC5: the isDefault fallback still fires

    func testTheDefaultEdgeFiresWhenEveryConditionedEdgeFails() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [Fixture.condition(.healthSteps, .atLeast, 10_000)]),
            Fixture.edge(to: "tyrannomon", conditions: [Fixture.condition(.careTrainingSessions, .atLeast, 40)]),
            Fixture.unqualifyingDefault(to: "numemon"),
        ])

        XCTAssertNil(Fixture.target(node, Fixture.context()),
                     "the pure chooser reports no qualifying branch...")
        XCTAssertEqual(
            EvolutionEngine.scheduledEvolutionTarget(
                for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
                careMistakes: 0, battleWins: 0,
                stageEnteredAt: Fixture.date("2026-07-01 08:00"), now: Fixture.morning,
                conditions: Fixture.context()),
            "numemon",
            "...and the timed path takes the isDefault edge, so nothing is ever stuck")
    }

    // MARK: - AC4 (unavailable): an unreadable metric never hands out a branch

    /// The trap US-059's notes flagged: `.unavailable` flattens to 0 everywhere downstream, and 0
    /// SATISFIES an `atMost` gate. A denial must not buy the "you barely did this" branch.
    func testAnUnavailableMetricFailsItsConditionInBothDirections() {
        let atLeast = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [Fixture.condition(.healthSteps, .atLeast, 10_000)])
        ])
        let atMost = Fixture.hero([
            Fixture.edge(to: "numemon", conditions: [Fixture.condition(.healthSteps, .atMost, 500)])
        ])
        // Steps are banked in the ledger and read zero; the caller knows the read itself failed.
        let denied = Fixture.context(stageSteps: 0, readings: [.healthSteps: .unavailable])

        XCTAssertNil(Fixture.target(atLeast, denied))
        XCTAssertNil(Fixture.target(atMost, denied),
                     "an unreadable metric must not satisfy an atMost gate by reading as zero")
        XCTAssertEqual(Fixture.target(atMost, Fixture.context(stageSteps: 0)), "numemon",
                       "a genuinely zero — readable — total still satisfies it")
    }

    /// A standing measurement (`accumulatesOverTime == false`) is answerable only from a direct
    /// read: no total means anything for a resting heart rate. Absent or `noData`, it is unknown
    /// and its condition fails.
    func testAStandingMeasurementNeedsADirectReadingAndFailsWithout() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon",
                         conditions: [Fixture.condition(.healthRestingHeartRate, .atMost, 60)])
        ])

        XCTAssertNil(Fixture.target(node, Fixture.context()),
                     "no reading at all: unknown, so it fails even this atMost gate")
        XCTAssertNil(Fixture.target(node, Fixture.context(readings: [.healthRestingHeartRate: .noData])),
                     "noData is not zero — nobody measured it")
        XCTAssertEqual(
            Fixture.target(node, Fixture.context(readings: [.healthRestingHeartRate: .value(55)])),
            "greymon")
        XCTAssertNil(
            Fixture.target(node, Fixture.context(readings: [.healthRestingHeartRate: .value(70)])),
            "a real reading above the gate fails it")
    }

    /// A metric name outside the vocabulary is a validator error, and until one is caught it must
    /// keep the edge SHUT rather than open a branch nothing can check.
    func testAnUnknownMetricNameFailsItsCondition() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", conditions: [
                EvolutionCondition(metric: "health.vibes", window: .stage, comparison: .atMost,
                                   value: 10, hint: "Be chill")
            ])
        ])

        XCTAssertNil(Fixture.target(node, Fixture.context()))
    }

    // MARK: - AC7: the windows read the right ledgers

    func testEachWindowReadsItsOwnTotal() {
        var stage = MetricTotals.zero
        stage[.healthSteps] = 100
        var lifetime = MetricTotals.zero
        lifetime[.healthSteps] = 5_000
        var bestDay = MetricTotals.zero
        bestDay[.healthSteps] = 900
        let context = ConditionContext(stageTotals: stage, lifetimeTotals: lifetime,
                                       bestDayThisStage: bestDay)

        XCTAssertEqual(context.value(for: .healthSteps, window: .stage), .known(100))
        XCTAssertEqual(context.value(for: .healthSteps, window: .lifetime), .known(5_000))
        XCTAssertEqual(context.value(for: .healthSteps, window: .day), .known(900))
    }

    /// AC7's other half: `care.*` reads the US-084 counters, and reads them off a real `GameState`
    /// rather than off numbers the test made up.
    func testCareConditionsReadTheUS084CountersFromGameState() {
        let state = GameState(currentDigimonId: "greymon", stage: .adult, now: Fixture.morning)
        state.trainCharges = 2
        TrainAction.train(state, isAsleep: false)
        TrainAction.train(state, isAsleep: false)
        state.recordRefusal(now: Fixture.morning, calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.morning, calendar: Fixture.losAngeles)
        state.recordBattleStarted(now: Fixture.morning, calendar: Fixture.losAngeles)
        state.battleWins = 1

        let context = ConditionContext(state: state, now: Fixture.morning,
                                       calendar: Fixture.losAngeles)

        XCTAssertEqual(context.value(for: .careTrainingSessions, window: .stage), .known(2))
        XCTAssertEqual(context.value(for: .careOverfeeds, window: .stage), .known(1))
        XCTAssertEqual(context.value(for: .careSleepDisturbances, window: .stage), .known(1))
        XCTAssertEqual(context.value(for: .careBattleCount, window: .day), .known(1))
        XCTAssertEqual(context.value(for: .careBattleWinRatio, window: .lifetime), .known(1))
    }

    /// A `care.*` counter asked about a window it does not keep answers `.unknown`, not the nearest
    /// number it does keep — an edge must never silently gate on something other than what it says.
    func testACareCounterAskedAboutAWindowItDoesNotKeepIsUnknown() {
        let context = Fixture.context(trainingSessions: 12)

        XCTAssertEqual(context.value(for: .careTrainingSessions, window: .stage), .known(12))
        XCTAssertEqual(context.value(for: .careTrainingSessions, window: .lifetime), .unknown)
        XCTAssertEqual(context.value(for: .careTrainingSessions, window: .day), .unknown)
        XCTAssertEqual(context.value(for: .careBattleWinRatio, window: .stage), .unknown,
                       "the ratio is lifetime only — US-084 note 4")
    }

    // MARK: - US-180: no data is unknown, not zero

    /// `MetricTotals.known(_:)` — the accessor the condition path reads through — tells "never
    /// credited" (nil -> `.unknown`) apart from "credited to zero" (`.known(0)`). The subscript
    /// cannot: it flattens both to 0.
    func testMetricTotalsKnownDistinguishesUncreditedFromZero() {
        var totals = MetricTotals.zero
        XCTAssertNil(totals.known(.healthSteps), "never credited: nil")
        XCTAssertEqual(totals[.healthSteps], 0, "the subscript still reads it as 0 for arithmetic")

        totals[.healthSteps] = 0
        XCTAssertEqual(totals.known(.healthSteps), 0, "a credited 0 is a real, known 0")
    }

    /// `healthValue(for:window:)` returns `.unknown` for a metric that was never credited, even when
    /// the totals themselves are present — so an `atMost` health gate is NOT satisfied on no data.
    /// A metric credited to 0 stays `.known(0)` and does satisfy it.
    func testAnUncreditedAccumulatingMetricIsUnknownEvenWithTotalsPresent() {
        // Totals present (not the `.unknown` context), but this metric was never written into them.
        let uncredited = ConditionContext(stageTotals: .zero, lifetimeTotals: .zero,
                                          bestDayThisStage: .zero)
        XCTAssertEqual(uncredited.value(for: .healthSteps, window: .stage), .unknown)
        XCTAssertEqual(uncredited.value(for: .healthSteps, window: .lifetime), .unknown)
        XCTAssertEqual(uncredited.value(for: .healthSteps, window: .day), .unknown)

        var zero = MetricTotals.zero
        zero[.healthSteps] = 0
        let credited = ConditionContext(stageTotals: zero)
        XCTAssertEqual(credited.value(for: .healthSteps, window: .stage), .known(0),
                       "a credited 0 is known, distinct from never credited")
    }

    /// The story's test, stated on the gate: with no credit both an `atLeast` and an `atMost` health
    /// condition fail (unknown); with a credited 0, `atMost` passes and `atLeast(> 0)` fails.
    func testUncreditedFailsBothGatesWhileACreditedZeroSatisfiesAtMost() {
        let uncredited = ConditionContext(stageTotals: .zero)
        XCTAssertFalse(
            ConditionEvaluator.isSatisfied(Fixture.condition(.healthSteps, .atLeast, 1), in: uncredited),
            "no data: atLeast fails")
        XCTAssertFalse(
            ConditionEvaluator.isSatisfied(Fixture.condition(.healthSteps, .atMost, 500), in: uncredited),
            "no data: atMost must NOT pass for free")

        var zero = MetricTotals.zero
        zero[.healthSteps] = 0
        let creditedZero = ConditionContext(stageTotals: zero)
        XCTAssertTrue(
            ConditionEvaluator.isSatisfied(Fixture.condition(.healthSteps, .atMost, 500), in: creditedZero),
            "a real, credited 0 satisfies atMost")
        XCTAssertFalse(
            ConditionEvaluator.isSatisfied(Fixture.condition(.healthSteps, .atLeast, 1), in: creditedZero),
            "a credited 0 does not reach an atLeast(> 0) gate")
    }

    /// The default context answers nothing, so an omitted context can never hand out a branch —
    /// including through an `atMost` condition, which is the direction an omission would otherwise
    /// pass by accident.
    func testTheUnknownContextFailsEveryCondition() {
        for metric in ConditionMetric.allCases {
            for window in [ConditionWindow.stage, .day, .lifetime] {
                XCTAssertEqual(ConditionContext.unknown.value(for: metric, window: window), .unknown,
                               "\(metric.rawValue) over \(window)")
                XCTAssertFalse(
                    ConditionEvaluator.isSatisfied(
                        Fixture.condition(metric, .atMost, 1_000_000, window: window), in: .unknown),
                    "\(metric.rawValue) over \(window) must not pass an atMost gate on nothing")
            }
        }
    }
}
