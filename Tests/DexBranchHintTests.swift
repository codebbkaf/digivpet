import Foundation
import XCTest

@testable import DigiVPet

/// US-111: tapping a Dex evolution candidate narrows the hint list to that branch.
///
/// Everything here goes through `DexHintList`, which is the whole selection behaviour as a pure
/// function of `(selection, candidates)` — no sheet presented, no store seeded, no clock. What a
/// test cannot reach is the `@State` the taps write to; that is `DexDetailView.selectedBranch`, and
/// the one claim it carries alone is that a dismissed sheet forgets its selection.
final class DexBranchHintTests: XCTestCase {

    // MARK: - Fixtures

    private func condition(
        _ metric: String,
        value: Double,
        hint: String,
        comparison: ConditionComparison = .atLeast,
        window: ConditionWindow = .stage
    ) -> EvolutionCondition {
        EvolutionCondition(
            metric: metric, window: window, comparison: comparison, value: value, hint: hint)
    }

    private func candidate(
        _ id: String,
        discovered: Bool = false,
        _ conditions: [EvolutionCondition],
        index: Int
    ) -> DexCandidate {
        let row = DexRow(
            id: id, displayName: id.capitalized, stage: .adult, spriteFile: id.capitalized,
            firstDiscovered: discovered ? Date(timeIntervalSince1970: 1) : nil)
        return DexCandidate(row: row, conditions: conditions, index: index)
    }

    /// The criterion both branches are gated on, at the SAME threshold — the one the flat list
    /// merges and neither selected branch may lose.
    private var shared: EvolutionCondition {
        condition("health.steps", value: 60_000, hint: "Walk with it most days")
    }

    /// Two conditioned branches sharing `shared`, plus an unconditional third.
    private var branches: [DexCandidate] {
        [
            candidate("greymon", [shared, condition("care.trainingSessions", value: 6, hint: "Train it often")], index: 0),
            candidate("meramon", [shared, condition("care.overfeeds", value: 2, hint: "Do not stuff it with food", comparison: .atMost)], index: 1),
            candidate("numemon", [], index: 2),
        ]
    }

    private func lines(selecting selection: DexCandidate.ID?, from candidates: [DexCandidate]) -> [DexHintList.Line] {
        DexHintList.list(selecting: selection, from: candidates)?.lines ?? []
    }

    private func conditions(selecting selection: DexCandidate.ID?, from candidates: [DexCandidate]) -> [EvolutionCondition] {
        lines(selecting: selection, from: candidates).compactMap {
            if case .condition(let condition) = $0 { return condition }
            return nil
        }
    }

    // MARK: - AC: the flat list merges, a selected branch does not

    /// AC13, both halves. Two branches share one criterion: the flat list says it once, and each
    /// branch on its own still says it — the deduplication is a property of merging, and a branch
    /// the player asked about was never merged with anything.
    func testASharedCriterionIsListedOnceFlatAndOnceOnEachBranch() {
        let all = branches

        XCTAssertEqual(conditions(selecting: nil, from: all).filter { $0 == shared }.count, 1,
                       "The flat list must mention a shared criterion once.")
        XCTAssertEqual(conditions(selecting: nil, from: all).count, 3,
                       "Three distinct criteria across the three branches.")

        XCTAssertEqual(conditions(selecting: all[0].id, from: all), all[0].conditions)
        XCTAssertEqual(conditions(selecting: all[1].id, from: all), all[1].conditions)
    }

    /// Two branches gated on the SAME metric at different thresholds are two things to know, so
    /// neither list may collapse them. Pinned here as well as in the flat list, because the
    /// deduplication key moved files in US-111.
    func testTheSameMetricAtDifferentThresholdsIsNotMerged() {
        let all = [
            candidate("greymon", [condition("health.steps", value: 10_000, hint: "Walk")], index: 0),
            candidate("meramon", [condition("health.steps", value: 60_000, hint: "Walk further")], index: 1),
        ]

        XCTAssertEqual(conditions(selecting: nil, from: all).map(\.value), [10_000, 60_000])
    }

    /// AC2: a selected branch's criteria come out in authored order, untouched.
    func testASelectedBranchKeepsItsAuthoredOrder() {
        let authored = [
            condition("care.overfeeds", value: 2, hint: "Do not stuff it", comparison: .atMost),
            condition("health.steps", value: 60_000, hint: "Walk with it most days"),
            condition("care.trainingSessions", value: 6, hint: "Train it often"),
        ]
        let all = [candidate("greymon", authored, index: 0)]

        XCTAssertEqual(conditions(selecting: all[0].id, from: all), authored)
    }

    // MARK: - AC: selecting, re-selecting, cross-selecting

    /// AC14. The three taps in sequence, each read as the list it produces. `toggle` in the view is
    /// two lines over this same state, so what is under test here is the whole of the behaviour.
    func testSelectingReselectingAndCrossSelectingProduceTheExpectedLists() {
        let all = branches
        var selection: DexCandidate.ID?

        func tap(_ candidate: DexCandidate) {
            selection = selection == candidate.id ? nil : candidate.id
        }

        XCTAssertEqual(DexHintList.list(selecting: selection, from: all)?.heading,
                       DexHintList.flatHeading, "It opens flat.")

        tap(all[0])
        XCTAssertEqual(conditions(selecting: selection, from: all), all[0].conditions)

        // Cross-select: straight from one branch to another, never through the flat list.
        tap(all[1])
        XCTAssertEqual(selection, all[1].id, "A tap on a different branch moves the selection.")
        XCTAssertEqual(conditions(selecting: selection, from: all), all[1].conditions)

        // AC4: the same one again clears it.
        tap(all[1])
        XCTAssertNil(selection)
        XCTAssertEqual(conditions(selecting: selection, from: all).count, 3,
                       "Deselecting returns the flat all-branches list.")
    }

    /// AC3: the heading has to change, or a narrower list looks like the same list with less in it.
    func testTheHeadingSaysWhichListThisIs() {
        let all = branches

        XCTAssertEqual(DexHintList.list(selecting: nil, from: all)?.heading, "It wants")
        XCTAssertEqual(DexHintList.list(selecting: all[0].id, from: all)?.heading, "To become this")
        XCTAssertNotEqual(DexHintList.flatHeading, DexHintList.branchHeading)
    }

    /// Two edges may name the same target under different criteria, which is why a candidate's id
    /// carries its index. Selecting one of that pair must not answer for the other.
    func testTwoEdgesToTheSameTargetSelectSeparately() {
        let first = condition("health.steps", value: 10_000, hint: "Walk")
        let second = condition("care.trainingSessions", value: 6, hint: "Train it often")
        let all = [
            candidate("greymon", [first], index: 0),
            candidate("greymon", [second], index: 1),
        ]

        XCTAssertNotEqual(all[0].id, all[1].id)
        XCTAssertEqual(conditions(selecting: all[0].id, from: all), [first])
        XCTAssertEqual(conditions(selecting: all[1].id, from: all), [second])
    }

    // MARK: - AC: an unconditional branch still answers

    /// AC8. The flat list drops an unconditional branch — it contributes nothing to flatten — but a
    /// branch the player has tapped has to say something, and a heading over nothing reads as a bug.
    func testASelectedUnconditionalBranchSaysItNeedsNothing() {
        let all = branches
        let unconditional = all[2]

        let list = DexHintList.list(selecting: unconditional.id, from: all)

        XCTAssertEqual(list?.lines, [.plain(DexHintList.nothingRequired)])
        XCTAssertEqual(list?.heading, DexHintList.branchHeading)
        XCTAssertFalse(DexHintList.nothingRequired.isEmpty)
    }

    /// The plain line sits among the hints, so it lives under the same rule: no hint may leak a
    /// threshold, and this one has no threshold to leak.
    func testTheNothingRequiredLineCarriesNoDigit() {
        let digits = DexHintList.nothingRequired.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }

        XCTAssertTrue(digits.isEmpty, "\"\(DexHintList.nothingRequired)\" leaks a number")
    }

    /// The section is drawn only when it has something to say. A node whose every branch is gated
    /// on energy and care alone — most of the shipped graph — still gets no heading.
    func testTheFlatListIsAbsentWhenNoBranchHasAnyCriterion() {
        let all = [candidate("numemon", [], index: 0), candidate("sukamon", [], index: 1)]

        XCTAssertNil(DexHintList.list(selecting: nil, from: all))
        XCTAssertNotNil(DexHintList.list(selecting: all[0].id, from: all),
                        "A tapped branch answers even when the flat list would not.")
    }

    /// A selection naming no candidate degrades to the default view rather than to an empty screen.
    func testAStaleSelectionFallsBackToTheFlatList() {
        let all = branches

        XCTAssertEqual(DexHintList.list(selecting: "9-gabumon", from: all)?.heading,
                       DexHintList.flatHeading)
    }

    // MARK: - AC: selecting reveals nothing about the candidate

    /// AC15, and the one that would make the whole story a net loss if it broke: the Dex exists to
    /// make the player go and find the thing. Reads every string the section draws — heading and
    /// each warmed-up line — for the withheld name, at every reveal level, since the warm qualifier
    /// is the newest thing that could ever have carried one.
    func testASelectedUndiscoveredCandidatesNameAppearsNowhereInTheText() {
        let all = [
            candidate("greymon", [shared, condition("care.trainingSessions", value: 6, hint: "Train it often")], index: 0),
            candidate("meramon", [], index: 1),
        ]
        let contexts: [ConditionContext] = [
            .unknown,                                                                    // far
            ConditionContext(stageTotals: MetricTotals(values: ["health.steps": 39_000]),
                             trainingSessionsThisStage: 2),                              // close
            ConditionContext(stageTotals: MetricTotals(values: ["health.steps": 99_000]),
                             trainingSessionsThisStage: 9),                              // met
        ]

        for candidate in all {
            XCTAssertFalse(candidate.row.isDiscovered, "The fixture must be a \"?\" to prove anything.")
            let name = candidate.row.displayName
            for context in contexts {
                let text = DexHintList.list(selecting: candidate.id, from: all)?.text(in: context) ?? []
                XCTAssertFalse(text.isEmpty, "A selected branch always says something.")
                for line in text {
                    XCTAssertFalse(
                        line.localizedCaseInsensitiveContains(name),
                        "Selecting \(candidate.id) leaked its name: \"\(line)\"")
                }
            }
        }
    }

    /// The text a line draws is `ConditionReveal`'s, unchanged — US-111 changes which conditions
    /// are listed and never how one is worded.
    func testALineIsWordedExactlyAsConditionRevealWordsIt() {
        let context = ConditionContext(stageTotals: MetricTotals(values: ["health.steps": 39_000]))

        XCTAssertEqual(DexHintList.Line.condition(shared).text(in: context),
                       ConditionReveal.line(for: shared, in: context))
        XCTAssertEqual(DexHintList.Line.plain("It sleeps.").text(in: context), "It sleeps.")
    }
}
