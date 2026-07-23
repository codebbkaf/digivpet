import Foundation
import XCTest

@testable import DigiVPet

/// US-185 — the `care.lightOff` evolution condition: a dark-side branch that opens only while the
/// room light is out (`LightState.off`), evaluated against `ConditionContext.lightState`.
///
/// Pure and injected throughout: hand-built nodes and literal `ConditionContext` values, no clock,
/// no HealthKit, no store.
final class LightOffConditionTests: XCTestCase {

    private static func condition(_ window: ConditionWindow = .stage) -> EvolutionCondition {
        EvolutionCondition(metric: .careLightOff, window: window, comparison: .atLeast,
                           value: 1, hint: "It comes alive in the dark")
    }

    private static func context(light: LightState?) -> ConditionContext {
        ConditionContext(lightState: light)
    }

    // MARK: - AC2: satisfied only while the light is off

    func testSatisfiedOnlyWhenLightIsOff() {
        let condition = Self.condition()
        XCTAssertTrue(ConditionEvaluator.isSatisfied(condition, in: Self.context(light: .off)),
                      "lights out satisfies the condition")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(condition, in: Self.context(light: .on)),
                       "full light does not")
        XCTAssertFalse(ConditionEvaluator.isSatisfied(condition, in: Self.context(light: .semi)),
                       "the night light is not lights-out, matching LightsOutRule")
    }

    /// An unknown light — a save from before the light was tracked, or the default `.unknown`
    /// context — fails, like every other unknown value in the vocabulary.
    func testAnUnknownLightFails() {
        XCTAssertFalse(ConditionEvaluator.isSatisfied(Self.condition(), in: Self.context(light: nil)))
        XCTAssertFalse(ConditionEvaluator.isSatisfied(Self.condition(), in: .unknown))
    }

    // MARK: - The window is a NOW reading: answerable only over .stage

    func testAnswerableOnlyOverTheStageWindow() {
        XCTAssertEqual(ConditionMetric.careLightOff.answerableWindows, [.stage])
        XCTAssertTrue(ConditionMetric.careLightOff.canBeAnswered(over: .stage))
        XCTAssertFalse(ConditionMetric.careLightOff.canBeAnswered(over: .day))
        XCTAssertFalse(ConditionMetric.careLightOff.canBeAnswered(over: .lifetime))

        // Windowed anywhere but .stage it reads unknown even with the light off, so the condition
        // fails — which is why the validator rejects such an edge (US-184).
        XCTAssertFalse(
            ConditionEvaluator.isSatisfied(Self.condition(.lifetime), in: Self.context(light: .off)))
    }

    // MARK: - AC4: the edge evolves with the light off and is blocked with it on, all else equal

    func testEdgeEvolvesInTheDarkAndIsBlockedInTheLight() {
        let node = EvolutionNode(
            id: "devimon", displayName: "Devimon", stage: .adult, spriteFile: "Devimon",
            evolutions: [
                EvolutionEdge(to: "neodevimon", requiredEnergy: .strength, minEnergy: 40,
                              maxCareMistakes: 99, conditions: [Self.condition()]),
                // The junk fallback: ungated on energy and conditionless, so it is where a blocked
                // dark branch drops to — proving the light, and only the light, decided.
                EvolutionEdge(to: "numemon", requiredEnergy: .strength, minEnergy: 0,
                              maxCareMistakes: 99, isDefault: true),
            ])

        func target(light: LightState) -> String? {
            EvolutionEngine.evolutionTarget(
                for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
                careMistakes: 0, battleWins: 0, conditions: Self.context(light: light))
        }

        XCTAssertEqual(target(light: .off), "neodevimon", "dark: the gated branch wins")
        XCTAssertEqual(target(light: .on), "numemon", "lit: the same run falls to the fallback")
        XCTAssertEqual(target(light: .semi), "numemon", "dimmed is not dark enough")
    }

    // MARK: - AC3: the shipped graph uses it and validates clean

    func testBundledGraphUsesLightOffAndValidatesClean() {
        let graph = EvolutionGraph.bundled

        let lightOffEdges = graph.nodes.flatMap { node in
            node.evolutions.filter { edge in
                edge.conditions.contains { $0.metric == ConditionMetric.careLightOff.rawValue }
            }
        }
        XCTAssertGreaterThanOrEqual(lightOffEdges.count, 3,
                                    "a handful of dark-line edges gate on care.lightOff")

        // The condition never contributes a HealthKit grant — it is the game's own state.
        XCTAssertFalse(EvolutionGraph.bundled.conditionHealthMetrics.contains(.careLightOff))

        XCTAssertEqual(graph.validate(spriteExists: { _ in true }), [],
                       "the graph, care.lightOff edges included, is sound")
    }
}
