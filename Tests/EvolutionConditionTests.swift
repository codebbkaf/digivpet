import Foundation
import XCTest

@testable import DigiVPet

/// US-056's condition vocabulary: that it decodes, that it defaults to absent on every edge
/// authored before it existed, and that the validator rejects the four ways of authoring one wrong.
final class EvolutionConditionTests: XCTestCase {
    private let allSpritesExist: EvolutionGraph.SpriteExistsCheck = { _ in true }

    // MARK: - The vocabulary

    /// Both families are present under their prefixes, and `careMistakes` is deliberately not —
    /// the edge's `maxCareMistakes` field already gates on it, and a second spelling would invite
    /// a later iteration to delete one of them.
    func testMetricVocabularySpansBothFamilies() {
        let raws = Set(ConditionMetric.allCases.map(\.rawValue))

        XCTAssertTrue(raws.contains("health.steps"))
        XCTAssertTrue(raws.contains("health.sleep"))
        XCTAssertTrue(raws.contains("health.workouts"))

        for care in ["care.trainingSessions", "care.overfeeds", "care.sleepDisturbances",
                     "care.battleCount", "care.battleWinRatio"] {
            XCTAssertTrue(raws.contains(care), "missing \(care)")
        }

        XCTAssertNil(ConditionMetric(rawValue: "care.careMistakes"))
        XCTAssertTrue(raws.allSatisfy { $0.hasPrefix("health.") || $0.hasPrefix("care.") })
    }

    func testIsHealthMetricSplitsTheFamilies() {
        XCTAssertTrue(ConditionMetric.healthSteps.isHealthMetric)
        XCTAssertFalse(ConditionMetric.careBattleWinRatio.isHealthMetric)
    }

    // MARK: - Decoding

    private func decodeEdge(_ json: String) throws -> EvolutionEdge {
        try JSONDecoder().decode(EvolutionEdge.self, from: Data(json.utf8))
    }

    func testConditionsDecodeFromAnEdge() throws {
        let edge = try decodeEdge("""
        {
          "to": "greymon", "requiredEnergy": "strength", "minEnergy": 60, "maxCareMistakes": 2,
          "conditions": [
            { "metric": "health.steps", "window": "day", "comparison": "atLeast",
              "value": 10000, "hint": "Walk 10,000 steps a day" }
          ]
        }
        """)

        XCTAssertEqual(edge.conditions.count, 1)
        let condition = try XCTUnwrap(edge.conditions.first)
        XCTAssertEqual(condition.knownMetric, .healthSteps)
        XCTAssertEqual(condition.window, .day)
        XCTAssertEqual(condition.comparison, .atLeast)
        XCTAssertEqual(condition.value, 10000)
        XCTAssertEqual(condition.hint, "Walk 10,000 steps a day")
    }

    /// The point of the whole story: an edge written before conditions existed still decodes.
    func testOmittedConditionsDefaultToEmpty() throws {
        let edge = try decodeEdge("""
        {"to": "greymon", "requiredEnergy": "strength", "minEnergy": 60, "maxCareMistakes": 2}
        """)
        XCTAssertEqual(edge.conditions, [])
    }

    func testAllThreeWindowsDecode() throws {
        for window in ["stage", "day", "lifetime"] {
            let edge = try decodeEdge("""
            {"to": "x", "minEnergy": 1, "maxCareMistakes": 1, "conditions": [
              {"metric": "care.overfeeds", "window": "\(window)", "comparison": "atMost",
               "value": 3, "hint": "Do not overfeed"}]}
            """)
            XCTAssertEqual(edge.conditions.first?.window.rawValue, window)
        }
    }

    /// `window` and `comparison` are closed sets, so they decode strictly — unlike `metric`, whose
    /// vocabulary grows and which the validator reports on instead.
    func testUnknownWindowAndComparisonFailToDecode() {
        XCTAssertThrowsError(try decodeEdge("""
        {"to": "x", "minEnergy": 1, "maxCareMistakes": 1, "conditions": [
          {"metric": "health.steps", "window": "fortnight", "comparison": "atLeast",
           "value": 1, "hint": "h"}]}
        """))

        XCTAssertThrowsError(try decodeEdge("""
        {"to": "x", "minEnergy": 1, "maxCareMistakes": 1, "conditions": [
          {"metric": "health.steps", "window": "day", "comparison": "exactly",
           "value": 1, "hint": "h"}]}
        """))
    }

    /// An unknown metric must survive the decode, or `EvolutionGraph.bundled` traps at launch and
    /// takes the whole suite with it instead of the validator naming the typo.
    func testUnknownMetricDecodesAndIsReportedAsUnknownRatherThanTrapping() throws {
        let edge = try decodeEdge("""
        {"to": "x", "minEnergy": 1, "maxCareMistakes": 1, "conditions": [
          {"metric": "health.stpes", "window": "day", "comparison": "atLeast",
           "value": 1, "hint": "h"}]}
        """)
        XCTAssertEqual(edge.conditions.first?.metric, "health.stpes")
        XCTAssertNil(edge.conditions.first?.knownMetric)
    }

    func testConditionsRoundTripThroughEncodeAndDecode() throws {
        let original = EvolutionEdge(
            to: "greymon", requiredEnergy: .strength, minEnergy: 60, maxCareMistakes: 2,
            conditions: [EvolutionCondition(
                metric: .careTrainingSessions, window: .stage, comparison: .atLeast,
                value: 8, hint: "Train at least 8 times")])

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(EvolutionEdge.self, from: data), original)
    }

    // MARK: - The band idiom

    /// The Digital Monster Color pattern: training 8–31 earns the good branch, while 0–7 AND 32+
    /// both fall to the junk one. Two conditions on one metric say it; there is no `between`.
    func testABandIsTwoConditionsOnOneMetric() throws {
        let edge = try decodeEdge("""
        {
          "to": "greymon", "requiredEnergy": "strength", "minEnergy": 60, "maxCareMistakes": 2,
          "conditions": [
            {"metric": "care.trainingSessions", "window": "stage", "comparison": "atLeast",
             "value": 8, "hint": "Train at least 8 times"},
            {"metric": "care.trainingSessions", "window": "stage", "comparison": "atMost",
             "value": 31, "hint": "But do not train more than 31 times"}
          ]
        }
        """)

        XCTAssertEqual(edge.conditions.count, 2)
        XCTAssertEqual(edge.conditions.map(\.comparison), [.atLeast, .atMost])
        XCTAssertEqual(edge.conditions.map(\.value), [8, 31])
        XCTAssertEqual(Set(edge.conditions.map(\.metric)), ["care.trainingSessions"])
        XCTAssertEqual(errors(graph(with: edge.conditions)), [])
    }

    /// DMC's "15+ battles at 80%+ wins" — the thing `minBattleWins` cannot express, because a win
    /// COUNT alone would let 15 wins in 200 battles through.
    func testBattleWinRatioExpressesARatioGateAlongsideMinBattleWins() throws {
        let edge = try decodeEdge("""
        {
          "to": "greymon", "requiredEnergy": "strength", "minEnergy": 60, "maxCareMistakes": 2,
          "minBattleWins": 3,
          "conditions": [
            {"metric": "care.battleCount", "window": "stage", "comparison": "atLeast",
             "value": 15, "hint": "Fight at least 15 battles"},
            {"metric": "care.battleWinRatio", "window": "stage", "comparison": "atLeast",
             "value": 0.8, "hint": "Win 80% of them"}
          ]
        }
        """)

        // Both gates coexist on one edge: the old field keeps working, the ratio adds to it.
        XCTAssertEqual(edge.minBattleWins, 3)
        XCTAssertEqual(edge.conditions.last?.value, 0.8)
        XCTAssertEqual(errors(graph(with: edge.conditions)), [])
    }

    // MARK: - Validation

    /// A sound two-node graph whose one gated edge carries `conditions`, so a reported error can
    /// only come from the conditions.
    private func graph(with conditions: [EvolutionCondition]) -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(
                    to: "toddler", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                    isDefault: true, conditions: conditions)]),
            EvolutionNode(id: "toddler", displayName: "Toddler", stage: .babyII, spriteFile: "Koromon"),
        ])
    }

    private func errors(_ graph: EvolutionGraph) -> [GraphValidationError] {
        graph.validate(spriteExists: allSpritesExist)
    }

    /// The control: the fixture is sound before anything is broken in it.
    func testAnEdgeWithNoConditionsHasNoConditionErrors() {
        XCTAssertEqual(errors(graph(with: [])), [])
    }

    func testValidConditionPasses() {
        let condition = EvolutionCondition(
            metric: .healthSteps, window: .day, comparison: .atLeast,
            value: 10000, hint: "Walk 10,000 steps a day")
        XCTAssertEqual(errors(graph(with: [condition])), [])
    }

    func testRejectsUnknownMetric() {
        let condition = EvolutionCondition(
            metric: "health.stpes", window: .day, comparison: .atLeast, value: 1, hint: "h")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .unknownConditionMetric(from: "baby", to: "toddler", metric: "health.stpes"),
        ])
    }

    func testRejectsNegativeValue() {
        let condition = EvolutionCondition(
            metric: .careTrainingSessions, window: .stage, comparison: .atLeast,
            value: -1, hint: "Train")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .negativeConditionValue(
                from: "baby", to: "toddler", metric: "care.trainingSessions", value: -1),
        ])
    }

    func testRejectsEmptyHint() {
        let condition = EvolutionCondition(
            metric: .healthSteps, window: .day, comparison: .atLeast, value: 10000, hint: "   ")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .emptyConditionHint(from: "baby", to: "toddler", metric: "health.steps"),
        ])
    }

    /// `80` is the mistake: it is a fraction, so an edge gated on it could never be taken.
    func testRejectsBattleWinRatioAboveOne() {
        let condition = EvolutionCondition(
            metric: .careBattleWinRatio, window: .stage, comparison: .atLeast,
            value: 80, hint: "Win 80% of battles")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .battleWinRatioOutOfRange(from: "baby", to: "toddler", value: 80),
        ])
    }

    /// A negative ratio is one error naming the real rule, not two naming half of it each.
    func testRejectsNegativeBattleWinRatioAsARangeErrorOnly() {
        let condition = EvolutionCondition(
            metric: .careBattleWinRatio, window: .stage, comparison: .atLeast,
            value: -0.5, hint: "Win battles")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .battleWinRatioOutOfRange(from: "baby", to: "toddler", value: -0.5),
        ])
    }

    func testAcceptsBattleWinRatioAtBothBounds() {
        for value in [0.0, 1.0] {
            let condition = EvolutionCondition(
                metric: .careBattleWinRatio, window: .stage, comparison: .atLeast,
                value: value, hint: "Win battles")
            XCTAssertEqual(errors(graph(with: [condition])), [], "ratio \(value) should be legal")
        }
    }

    /// An unknown metric has no unit, so `value` cannot be judged against one — the author is
    /// pointed at the metric, not sent to fix a field that may be right.
    func testUnknownMetricSuppressesTheRangeRules() {
        let condition = EvolutionCondition(
            metric: "health.nonsense", window: .day, comparison: .atLeast, value: -5, hint: "h")

        XCTAssertEqual(errors(graph(with: [condition])), [
            .unknownConditionMetric(from: "baby", to: "toddler", metric: "health.nonsense"),
        ])
    }

    /// A dead `to` must not hide a condition error, or the author fixes the target and meets the
    /// condition error only on a second run.
    func testConditionErrorsAreReportedEvenWhenTheEdgeTargetIsUnknown() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(
                    to: "nosuchmon", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                    isDefault: true,
                    conditions: [EvolutionCondition(
                        metric: "care.nonsense", window: .stage, comparison: .atLeast,
                        value: 1, hint: "h")])]),
        ])

        XCTAssertEqual(errors(graph), [
            .unknownConditionMetric(from: "baby", to: "nosuchmon", metric: "care.nonsense"),
            .unknownEdgeTarget(from: "baby", to: "nosuchmon"),
        ])
    }

    // MARK: - The real file

    /// The shipped file really carries conditions, and every one of them decodes into a whole
    /// `EvolutionCondition` — a known metric, a real threshold, a hint.
    ///
    /// This replaces US-056's `testEveryBundledEdgeDecodesWithNoConditions`, which pinned the file
    /// as it stood BEFORE any criterion was authored. US-061 authored them, so that assertion is
    /// now the opposite of the truth; the guard it was really providing — that `conditions` decodes
    /// faithfully rather than silently defaulting to `[]` — is what is kept here.
    func testEveryBundledConditionDecodesIntoAKnownMetric() throws {
        let conditions = EvolutionGraph.bundled.nodes
            .flatMap(\.evolutions)
            .flatMap(\.conditions)

        XCTAssertFalse(conditions.isEmpty, "US-061 authors criteria; an empty file means they were lost")
        for condition in conditions {
            XCTAssertNotNil(condition.knownMetric, "'\(condition.metric)' is not in the vocabulary")
            XCTAssertGreaterThanOrEqual(condition.value, 0, "\(condition.metric) has a negative threshold")
            XCTAssertFalse(condition.hint.isEmpty, "\(condition.metric) has no hint")
        }
    }

    /// An edge with no `conditions` key still decodes as `[]` rather than failing. Most of the
    /// shipped file is still conditionless — every junk fallback is, deliberately — so this is not
    /// a hypothetical.
    func testBundledEdgesWithoutConditionsStillDecodeAsEmpty() throws {
        let bare = EvolutionGraph.bundled.nodes
            .flatMap(\.evolutions)
            .filter { $0.conditions.isEmpty }

        XCTAssertFalse(bare.isEmpty, "the junk fallbacks are conditionless by design")
    }
}
