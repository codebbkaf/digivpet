import Foundation
import XCTest

@testable import DigiVPet

/// US-066's progress-based reveal: which of the three levels a condition sits at, that the
/// boundaries land where the story says, and — as in US-065 — that nothing shown ever carries the
/// number it stands for.
final class ConditionRevealTests: XCTestCase {

    /// A steps condition, because steps accumulate and so can be answered straight off a
    /// `stageTotals` literal — no clock, no store, no HealthKit.
    private func steps(
        atLeast value: Double,
        hint: String = "Walk with it"
    ) -> EvolutionCondition {
        EvolutionCondition(
            metric: .healthSteps, window: .stage, comparison: .atLeast, value: value, hint: hint)
    }

    private func context(steps walked: Double) -> ConditionContext {
        ConditionContext(stageTotals: MetricTotals(values: [ConditionMetric.healthSteps.rawValue: walked]))
    }

    // MARK: - The three levels and their boundaries (AC1, AC4)

    /// AC4's three named boundaries: just under 50%, exactly 50%, exactly met. 4,999 of 10,000 is
    /// the last value that is still cold; 5,000 is the first that is warm.
    func testTheBoundariesLandWhereTheStorySaysTheyDo() {
        let condition = steps(atLeast: 10_000)

        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 4_999)), .far)
        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 5_000)), .close)
        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 10_000)), .met)
    }

    /// One step past `met` stays met rather than wrapping or clamping to something else, and zero
    /// is the coldest end.
    func testTheEndsOfTheRange() {
        let condition = steps(atLeast: 10_000)

        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 0)), .far)
        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 999_999)), .met)
        XCTAssertEqual(ConditionReveal.progress(of: condition, in: context(steps: 999_999)), 1)
    }

    /// `met` is decided by `ConditionEvaluator`, so a checkmark and the evolution engine can never
    /// disagree about the same condition and the same numbers.
    func testMetAgreesWithTheEvaluatorAtEveryStep() {
        let condition = steps(atLeast: 100)
        for walked in stride(from: 0.0, through: 200.0, by: 5) {
            let scenario = context(steps: walked)
            XCTAssertEqual(
                ConditionReveal.level(of: condition, in: scenario) == .met,
                ConditionEvaluator.isSatisfied(condition, in: scenario),
                "disagreed at \(walked)")
        }
    }

    // MARK: - Progress refuses to warm up on things it cannot see

    /// A context that can answer nothing must read as `far`, not as warm. A denied metric warming
    /// a hint up would tell the player to keep doing something the app cannot see them doing.
    func testAnUnknownValueIsTheColdestLevel() {
        let condition = steps(atLeast: 10_000)
        XCTAssertEqual(ConditionReveal.progress(of: condition, in: .unknown), 0)
        XCTAssertEqual(ConditionReveal.level(of: condition, in: .unknown), .far)
    }

    /// An unsatisfied `atMost` is spent, not partly earned: it starts met and can only be broken,
    /// so it must never warm back up as the player does more of the wrong thing.
    func testAnOvershotAtMostIsFarAndNotGraded() {
        let cap = EvolutionCondition(
            metric: .careOverfeeds, window: .stage, comparison: .atMost, value: 2,
            hint: "Do not stuff it")

        XCTAssertEqual(ConditionReveal.level(of: cap, in: ConditionContext(overfeedsThisStage: 2)), .met)
        XCTAssertEqual(ConditionReveal.level(of: cap, in: ConditionContext(overfeedsThisStage: 3)), .far)
        XCTAssertEqual(ConditionReveal.progress(of: cap, in: ConditionContext(overfeedsThisStage: 3)), 0)
        // Further over is no different — no gradient in either direction.
        XCTAssertEqual(ConditionReveal.progress(of: cap, in: ConditionContext(overfeedsThisStage: 99)), 0)
    }

    /// A metric outside the vocabulary cannot be answered, so it is cold — the same call
    /// `ConditionEvaluator` makes, which keeps the edge shut.
    func testAnUnknownMetricIsFar() {
        let condition = EvolutionCondition(
            metric: "health.notAThing", window: .stage, comparison: .atLeast, value: 10,
            hint: "Do the impossible")
        XCTAssertEqual(ConditionReveal.level(of: condition, in: context(steps: 10_000)), .far)
    }

    // MARK: - The line the player reads (AC1, AC2)

    /// `far` shows the flavour text alone; `close` shows it plus a warmer qualifier; `met` adds no
    /// words at all, because the checkmark has already said it.
    func testTheLineWarmsUpAndThenStopsTalking() {
        let condition = steps(atLeast: 10_000, hint: "Walk with it most days")

        XCTAssertEqual(
            ConditionReveal.line(for: condition, in: context(steps: 100)),
            "Walk with it most days")
        // Punctuated when — and only when — a qualifier follows it, so the two read as two
        // sentences rather than as one run-on.
        XCTAssertEqual(
            ConditionReveal.line(for: condition, in: context(steps: 7_000)),
            "Walk with it most days. \(RevealLevel.close.qualifier ?? "")")
        // A hint that already ends in a full stop does not collect a second one.
        let punctuated = steps(atLeast: 10_000, hint: "It turns toward the sun.")
        XCTAssertEqual(
            ConditionReveal.line(for: punctuated, in: context(steps: 7_000)),
            "It turns toward the sun. \(RevealLevel.close.qualifier ?? "")")
        XCTAssertEqual(
            ConditionReveal.line(for: condition, in: context(steps: 10_000)),
            "Walk with it most days")
    }

    /// The line goes through `ConditionHint.resolve`, so an unauthored hint still falls back to
    /// its metric's default rather than drawing an empty row.
    func testAnUnauthoredHintStillFallsBackToTheMetricDefault() {
        let condition = EvolutionCondition(
            metric: .healthDaylight, window: .stage, comparison: .atLeast, value: 60, hint: "   ")
        XCTAssertEqual(
            ConditionReveal.line(for: condition, in: .unknown),
            ConditionMetric.healthDaylight.defaultHint)
    }

    /// AC2, the load-bearing one. Nothing the reveal adds may carry a digit, at ANY level, for ANY
    /// condition shipped in `evolutions.json` — which is where a leaked threshold would actually
    /// reach a player. US-065 pins the hints themselves; this pins what warming them up appends.
    func testNoRevealedLineContainsADigit() {
        for qualifier in RevealLevel.allCases.compactMap(\.qualifier) {
            XCTAssertNil(
                qualifier.rangeOfCharacter(from: .decimalDigits),
                "qualifier leaks a number: \(qualifier)")
        }

        var checked = 0
        for node in EvolutionGraph.bundled.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    // Every level, not just the one these numbers happen to produce: the same
                    // condition is read at all three as the player progresses.
                    let scenarios: [ConditionContext] = [
                        .unknown,
                        context(steps: condition.value / 2),
                        context(steps: condition.value * 10),
                    ]
                    for scenario in scenarios {
                        let line = ConditionReveal.line(for: condition, in: scenario)
                        XCTAssertNil(
                            line.rangeOfCharacter(from: .decimalDigits),
                            "\(node.id) -> \(edge.to) leaks a number: \(line)")
                        checked += 1
                    }
                }
            }
        }
        // So this cannot pass by checking nothing if the graph ever loads empty.
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - A candidate you have earned (AC3)

    func testAllMetNeedsEveryCondition() {
        let walk = steps(atLeast: 10_000)
        let train = EvolutionCondition(
            metric: .careTrainingSessions, window: .stage, comparison: .atLeast, value: 6,
            hint: "Train it")

        let bothMet = ConditionContext(
            stageTotals: MetricTotals(values: [ConditionMetric.healthSteps.rawValue: 12_000]),
            trainingSessionsThisStage: 6)
        let oneMet = ConditionContext(
            stageTotals: MetricTotals(values: [ConditionMetric.healthSteps.rawValue: 12_000]),
            trainingSessionsThisStage: 5)

        XCTAssertTrue(ConditionReveal.allMet([walk, train], in: bothMet))
        XCTAssertFalse(ConditionReveal.allMet([walk, train], in: oneMet))
        XCTAssertFalse(ConditionReveal.allMet([walk, train], in: .unknown))
    }

    /// An edge with no conditions has no criterion left to satisfy, so it is all-met — including
    /// against a context that knows nothing, since there is nothing to know.
    func testAnEdgeWithNoConditionsIsAllMet() {
        XCTAssertTrue(ConditionReveal.allMet([], in: .unknown))
    }

    // MARK: - Purity (AC4)

    /// Every call above ran against value literals — no store, no clock, no HealthKit, no view.
    /// This pins that the same inputs give the same answer however many times they are asked.
    func testResolutionIsPure() {
        let condition = steps(atLeast: 10_000)
        let scenario = context(steps: 5_000)
        let first = ConditionReveal.line(for: condition, in: scenario)
        for _ in 0..<10 {
            XCTAssertEqual(ConditionReveal.line(for: condition, in: scenario), first)
            XCTAssertEqual(ConditionReveal.level(of: condition, in: scenario), .close)
        }
    }

    // MARK: - What the detail sheet builds its cells from

    /// The candidate list still carries the criteria of the edge that reaches each target, which
    /// is the only way the sheet can mark one branch earned and its sibling not.
    func testCandidatesCarryTheirEdgeConditions() {
        let graph = EvolutionGraph.bundled
        let candidates = DexRow.candidates(of: "agumon", in: graph, resolvedAgainst: [:])

        XCTAssertEqual(candidates.map(\.row.id), ["greymon", "meramon", "numemon"])
        // Agumon's two gated branches each carry criteria; the junk default carries none.
        XCTAssertFalse(candidates[0].conditions.isEmpty)
        XCTAssertFalse(candidates[1].conditions.isEmpty)
        XCTAssertTrue(candidates[2].conditions.isEmpty)
        // Unchanged for every caller that only wanted the rows.
        XCTAssertEqual(
            DexRow.evolutionCandidates(of: "agumon", in: graph, resolvedAgainst: [:]).map(\.id),
            candidates.map(\.row.id))
    }

    /// The exact scenario `-dexRevealDemo` puts on screen, asserted here so the screenshot is
    /// checking the layout and not the arithmetic: Greymon's steps warm, its training cold, and
    /// both of Meramon's criteria met so its cell draws as earned and Greymon's does not.
    func testTheDemoScenarioProducesAllThreeLevels() {
        let candidates = DexRow.candidates(of: "agumon", in: .bundled, resolvedAgainst: [:])
        let scenario = ConditionContext(
            stageTotals: MetricTotals(values: [
                ConditionMetric.healthSteps.rawValue: 39_000,
                ConditionMetric.healthActiveEnergy.rawValue: 1_500,
            ]),
            trainingSessionsThisStage: 2,
            overfeedsThisStage: 0)

        let greymon = candidates[0]
        XCTAssertEqual(greymon.conditions.map { ConditionReveal.level(of: $0, in: scenario) },
                       [.close, .far])
        XCTAssertFalse(ConditionReveal.allMet(greymon.conditions, in: scenario))

        let meramon = candidates[1]
        XCTAssertEqual(meramon.conditions.map { ConditionReveal.level(of: $0, in: scenario) },
                       [.met, .met])
        XCTAssertTrue(ConditionReveal.allMet(meramon.conditions, in: scenario))
    }
}
