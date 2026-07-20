import Foundation
import XCTest

@testable import DigiVPet

/// US-065's hint vocabulary: that every metric has flavour text, that an edge can override it,
/// and — the load-bearing one — that no hint anywhere can leak the threshold it stands for.
final class ConditionHintTests: XCTestCase {

    private func condition(
        metric: String,
        hint: String,
        comparison: ConditionComparison = .atLeast,
        value: Double = 1
    ) -> EvolutionCondition {
        EvolutionCondition(
            metric: metric, window: .stage, comparison: comparison, value: value, hint: hint)
    }

    // MARK: - Every metric speaks

    /// AC1. `allCases` drives this rather than a hand-written list, so a metric added later fails
    /// here as well as at the switch — belt and braces, since the switch could be "fixed" by
    /// pasting a neighbour's line.
    func testEveryMetricHasANonEmptyDefaultHint() {
        for metric in ConditionMetric.allCases {
            let hint = metric.defaultHint
            XCTAssertFalse(
                hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(metric.rawValue) has no default hint")
        }
    }

    /// The five spelled out in the story, verbatim. They are the reference for the register every
    /// other default is written in, so they are pinned rather than paraphrased.
    func testTheNamedDefaultsReadAsAuthored() {
        XCTAssertEqual(ConditionMetric.healthSteps.defaultHint, "Restless. It wants to see the horizon.")
        XCTAssertEqual(ConditionMetric.healthHandwashing.defaultHint, "It flinches from grime.")
        XCTAssertEqual(ConditionMetric.healthMindfulMinutes.defaultHint, "It listens for stillness.")
        XCTAssertEqual(ConditionMetric.healthStandHours.defaultHint, "It cannot bear sitting still.")
        XCTAssertEqual(ConditionMetric.healthDaylight.defaultHint, "It turns toward the sun.")
    }

    /// Two metrics sharing one line would tell the player two different branches want the same
    /// thing, which is worse than no hint: it actively misdirects.
    func testNoTwoMetricsShareAHint() {
        let hints = ConditionMetric.allCases.map(\.defaultHint)
        XCTAssertEqual(Set(hints).count, hints.count, "two metrics share default flavour text")
    }

    // MARK: - No hint may leak a number

    /// AC3, and the reason this file exists. Covers the defaults, the fallback, and — the half
    /// that will actually catch a regression — every hint authored in the shipped graph, since
    /// that is the file a later story adds edges to.
    func testNoHintContainsADigit() {
        func assertNoDigit(_ hint: String, _ label: String) {
            let digits = hint.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            XCTAssertTrue(
                digits.isEmpty,
                "\(label) leaks a threshold: \"\(hint)\"")
        }

        for metric in ConditionMetric.allCases {
            assertNoDigit(metric.defaultHint, "default hint for \(metric.rawValue)")
        }
        assertNoDigit(ConditionHint.fallback, "the unknown-metric fallback")

        var authoredCount = 0
        for node in EvolutionGraph.bundled.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    authoredCount += 1
                    assertNoDigit(
                        condition.hint,
                        "authored hint on \(node.id) -> \(edge.to) (\(condition.metric))")
                    assertNoDigit(
                        ConditionHint.resolve(for: condition),
                        "resolved hint on \(node.id) -> \(edge.to) (\(condition.metric))")
                }
            }
        }
        XCTAssertGreaterThan(
            authoredCount, 0, "the shipped graph has no conditions — this test proved nothing")
    }

    // MARK: - Resolution

    /// AC2.
    func testAuthoredHintOverridesTheMetricDefault() {
        let resolved = ConditionHint.resolve(
            for: condition(metric: "health.steps", hint: "Stop once it has had enough."))

        XCTAssertEqual(resolved, "Stop once it has had enough.")
        XCTAssertNotEqual(resolved, ConditionMetric.healthSteps.defaultHint)
    }

    func testUnauthoredHintFallsBackToTheMetricDefault() {
        let resolved = ConditionHint.resolve(for: condition(metric: "health.daylight", hint: ""))

        XCTAssertEqual(resolved, ConditionMetric.healthDaylight.defaultHint)
    }

    /// A hint of nothing but whitespace is what the validator already calls blank. Resolution has
    /// to agree, or an edge could pass validation-by-a-space and draw the player an empty line.
    func testWhitespaceOnlyHintCountsAsUnauthored() {
        let resolved = ConditionHint.resolve(
            for: condition(metric: "care.overfeeds", hint: "   \n  "))

        XCTAssertEqual(resolved, ConditionMetric.careOverfeeds.defaultHint)
    }

    /// The surrounding whitespace goes, so a stray trailing space in the JSON cannot change how a
    /// line lays out in the detail sheet.
    func testAuthoredHintIsTrimmed() {
        let resolved = ConditionHint.resolve(
            for: condition(metric: "health.steps", hint: "  It paces.  "))

        XCTAssertEqual(resolved, "It paces.")
    }

    /// An unknown metric with no hint has nothing to fall back to but the fallback. It stays vague
    /// and stays true rather than becoming an empty row.
    func testUnknownMetricWithNoHintUsesTheFallback() {
        let unknown = condition(metric: "health.notAMetric", hint: "")

        XCTAssertNil(unknown.knownMetric)
        XCTAssertEqual(ConditionHint.resolve(for: unknown), ConditionHint.fallback)
    }

    /// An unknown metric that DOES carry a hint still shows it — the metric being unrecognised is
    /// the validator's problem, not a reason to discard the one line the author wrote.
    func testUnknownMetricStillHonoursItsAuthoredHint() {
        let resolved = ConditionHint.resolve(
            for: condition(metric: "health.notAMetric", hint: "It hungers for the unnameable."))

        XCTAssertEqual(resolved, "It hungers for the unnameable.")
    }

    /// AC4: resolution is a pure function — same input, same output, no view, no clock, no store.
    /// Two calls a whole test apart agree, and neither needed anything constructed.
    func testResolutionIsPure() {
        let sample = condition(metric: "care.battleWinRatio", hint: "")

        XCTAssertEqual(ConditionHint.resolve(for: sample), ConditionHint.resolve(for: sample))
        XCTAssertEqual(
            ConditionHint.resolve(for: sample), ConditionMetric.careBattleWinRatio.defaultHint)
    }
}
