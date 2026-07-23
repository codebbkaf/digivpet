import XCTest

@testable import DigiVPet

/// US-183 — accumulated sleep as an evolution gate, and the detail-view dash bar that draws it.
///
/// The gate is honoured by the ordinary evolution pipeline (US-179/180/181 fill and read the
/// lifetime `health.sleep` total); this file proves the shipped Agumon edge really blocks below its
/// requirement and opens at it, and that `SleepGate` turns the same authored minutes into a bar
/// whose solid count is the progress the gate has made. Everything is pure and injected — no
/// HealthKit, no waiting.
final class SleepGateTests: XCTestCase {
    private let graph = EvolutionGraph.bundled

    /// Minutes for a whole number of hours, so a test reads in the unit the requirement is spoken in.
    private func hours(_ h: Double) -> Double { h * 60 }

    /// A context whose only answer is a lifetime `health.sleep` total, in minutes.
    private func sleep(minutes: Double) -> ConditionContext {
        ConditionContext(lifetimeTotals: MetricTotals(values: ["health.sleep": minutes]))
    }

    // MARK: - AC1: the gate is honoured — below the requirement the edge is blocked

    func testAnAccumulatedSleepGateIsUnmetBelowItAndMetAtIt() {
        let gate = EvolutionCondition(
            metric: .healthSleep, window: .lifetime, comparison: .atLeast,
            value: hours(16), hint: "Let it bank a good long stretch of sleep")

        XCTAssertFalse(ConditionEvaluator.isSatisfied(gate, in: sleep(minutes: hours(6))),
                       "six hours does not meet a sixteen-hour gate")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(gate, in: sleep(minutes: hours(15.9))),
                       "just short is still short")
        XCTAssertTrue(ConditionEvaluator.isSatisfied(gate, in: sleep(minutes: hours(16))),
                      "exactly sixteen hours meets it — atLeast is inclusive")
        XCTAssertTrue(ConditionEvaluator.isSatisfied(gate, in: sleep(minutes: hours(20))),
                      "more than enough still meets it")
    }

    /// A never-credited sleep total (the Simulator, or a pre-US-181 save) reads `.unknown`, not a
    /// free zero, so the gate stays shut rather than opening for a Digimon that has slept nothing.
    func testAnUncreditedSleepTotalLeavesTheGateShut() {
        let gate = EvolutionCondition(
            metric: .healthSleep, window: .lifetime, comparison: .atLeast,
            value: hours(16), hint: "sleep")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(gate, in: .unknown))
    }

    // MARK: - AC3: the shipped file authors a sleep requirement, and the graph validates

    func testTheShippedGraphAuthorsAtLeastOneAccumulatedSleepGate() {
        let accumulated = graph.nodes.flatMap(\.evolutions).flatMap(\.conditions).filter {
            $0.knownMetric == .healthSleep && $0.window == .lifetime && $0.comparison == .atLeast
        }
        XCTAssertFalse(accumulated.isEmpty,
                       "no edge gates on accumulated sleep — US-183's exemplar is missing")
        for gate in accumulated {
            XCTAssertFalse(gate.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "an accumulated-sleep gate the player cannot discover")
        }
    }

    func testAddingTheSleepGateLeavesTheGraphValid() {
        XCTAssertEqual(graph.validate(spriteExists: { _ in true }), [],
                       "the accumulated-sleep gate broke the validator")
    }

    // MARK: - AC1/AC4: the shipped Agumon -> Greymon edge requires sixteen hours

    private func agumonToGreymon() throws -> EvolutionEdge {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        return try XCTUnwrap(agumon.evolutions.first { $0.to == "greymon" },
                             "Agumon no longer evolves to Greymon")
    }

    func testAgumonToGreymonCarriesASixteenHourAccumulatedSleepGate() throws {
        let edge = try agumonToGreymon()
        let sleepGate = try XCTUnwrap(
            edge.conditions.first {
                $0.knownMetric == .healthSleep && $0.window == .lifetime
            },
            "Agumon -> Greymon has no accumulated-sleep gate")
        XCTAssertEqual(sleepGate.comparison, .atLeast)
        XCTAssertEqual(sleepGate.value, hours(16), "the requirement is not sixteen hours")
    }

    /// The engine's view: a well-raised Agumon that has NOT slept enough falls to its junk Champion,
    /// and the same Agumon with sixteen hours banked reaches Greymon.
    func testAgumonReachesGreymonOnlyOnceItHasSleptEnough() throws {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))

        func target(sleepMinutes: Double) -> String? {
            let context = ConditionContext(
                stageTotals: MetricTotals(values: ["health.steps": 100_000]),
                lifetimeTotals: MetricTotals(values: ["health.sleep": sleepMinutes]),
                trainingSessionsThisStage: 6)
            return EvolutionEngine.evolutionTarget(
                for: agumon, stageEnergy: EnergyTotals(strength: 60), dominant: .strength,
                careMistakes: 0, battleWins: 0, conditions: context)
        }

        XCTAssertEqual(target(sleepMinutes: hours(6)), "numemon",
                       "an under-slept Agumon must fall to its junk fallback, not reach Greymon")
        XCTAssertEqual(target(sleepMinutes: hours(16)), "greymon",
                       "a well-raised, well-rested Agumon reaches Greymon")
    }

    // MARK: - AC2/AC4: the detail bar reports filled == earned, total == required

    func testTheDashBarFillsEarnedOfRequired() throws {
        let edge = try agumonToGreymon()

        let required = try XCTUnwrap(SleepGate.requiredHours(in: edge.conditions))
        XCTAssertEqual(required, 16, "the bar's total is the requirement in whole hours")

        XCTAssertEqual(SleepGate.earnedHours(in: sleep(minutes: hours(6))), 6)
        XCTAssertEqual(SleepGate.earnedHours(in: sleep(minutes: hours(16))), 16)

        // The bar the view draws: `earned` solid, the rest outline, `required` dashes in all.
        let earned = SleepGate.earnedHours(in: sleep(minutes: hours(6)))
        let dashes = DashBarLayout.dashes(filled: earned, total: required)
        XCTAssertEqual(dashes.count, required, "total == required")
        XCTAssertEqual(dashes.filter { $0 == .solid }.count, earned, "filled == earned")
        XCTAssertEqual(dashes.filter { $0 == .outline }.count, required - earned)
    }

    /// A Digimon with no accumulated-sleep gate draws no bar at all.
    func testNoBarWhenNothingGatesOnSleep() {
        XCTAssertNil(SleepGate.requiredHours(in: [
            EvolutionCondition(metric: .healthSteps, window: .stage, comparison: .atLeast,
                               value: 1000, hint: "walk"),
        ]))
        XCTAssertNil(SleepGate.requiredHours(in: []))
    }

    /// An `atMost` sleep ceiling (a stay-up-late branch) is not a fill-toward bar and must not draw
    /// one; only an `atLeast` accumulated gate counts.
    func testAtMostSleepIsNotABar() {
        XCTAssertNil(SleepGate.requiredHours(in: [
            EvolutionCondition(metric: .healthSleep, window: .stage, comparison: .atMost,
                               value: 600, hint: "keep it up late"),
        ]))
    }

    /// Earned hours FLOOR — a partial hour has not been banked as a whole dash yet.
    func testEarnedHoursFloorAPartialHour() {
        XCTAssertEqual(SleepGate.earnedHours(in: sleep(minutes: hours(6) + 59)), 6,
                       "fifty-nine extra minutes is not a seventh hour")
        XCTAssertEqual(SleepGate.earnedHours(in: .unknown), 0,
                       "no data is no hours, not a phantom dash")
    }
}
