import Foundation
import XCTest

@testable import DigiVPet

/// US-130 — the Jogress validator, against hand-built broken catalogs, plus the AC's run over the
/// REAL shipped `jogress.json`.
///
/// Two different jobs in one file, exactly as `MapCatalogValidatorTests` and
/// `EvolutionGraphValidatorTests` do it: the fixtures prove each rule FIRES (a validator that
/// returned [] always would sail through a green-file test), and the real-file test is what fails
/// the build the day US-131 authors a recipe naming a Digimon that is not there.
final class JogressCatalogValidatorTests: XCTestCase {

    // MARK: - Fixtures

    /// A roster small enough to read: two Ultimates that fuse, the thing they fuse into, a Child to
    /// test the ladder rule with, and one idle-only Digimon.
    private func fixtureRoster() -> Roster {
        Roster(entries: [
            RosterEntry(
                id: "war", displayName: "WarGreymon", stage: .ultimate, spriteFile: "WarGreymon"),
            RosterEntry(
                id: "metal", displayName: "MetalGarurumon", stage: .ultimate,
                spriteFile: "MetalGarurumon"),
            RosterEntry(
                id: "omega", displayName: "Omegamon", stage: .ultimate, spriteFile: "Omegamon"),
            RosterEntry(id: "kid", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            RosterEntry(
                id: "idle_only", displayName: "Idle Only", stage: .ultimate, spriteFile: "Poyomon",
                dexOnly: true),
            RosterEntry(
                id: "armor", displayName: "Armor", stage: .armorHybrid, spriteFile: "Flamedramon"),
        ])
    }

    /// A minimal SOUND catalog: one recipe, two real Ultimate parents, a real Ultimate result, one
    /// well-formed condition. Every fixture below is this with exactly one thing broken, so a
    /// reported error can only be the thing that was broken.
    private func soundCatalog() -> JogressCatalog {
        JogressCatalog(recipes: [sound()])
    }

    private func sound(
        parentA: String = "war",
        parentB: String = "metal",
        result: String = "omega",
        conditions: [EvolutionCondition]? = nil
    ) -> JogressRecipe {
        JogressRecipe(
            parentA: parentA, parentB: parentB, result: result,
            conditions: conditions ?? [EvolutionCondition(
                metric: .careBattleCount, window: .lifetime, comparison: .atLeast, value: 20,
                hint: "Fight 20 battles")])
    }

    private func errors(_ catalog: JogressCatalog) -> [JogressValidationError] {
        catalog.validate(roster: fixtureRoster())
    }

    /// The control. Without it, every "exactly one error" assertion below could be passing because
    /// the validator flags something unrelated in the baseline.
    func testASoundCatalogHasNoErrors() {
        XCTAssertEqual(errors(soundCatalog()), [])
    }

    /// And a recipe with no conditions at all is sound — a fusion gated only on owning both parents
    /// is the ordinary Color-device case, not a missing gate.
    func testARecipeWithNoConditionsIsSound() {
        XCTAssertEqual(errors(JogressCatalog(recipes: [sound(conditions: [])])), [])
    }

    // MARK: - A parent or result absent from the roster

    func testAParentThatNamesNoRosterEntryIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(parentB: "nobody")])

        XCTAssertEqual(
            errors(catalog),
            [.unknownParent(pair: JogressPair("war", "nobody"), parent: "nobody")])
    }

    func testAResultThatNamesNoRosterEntryIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(result: "nobody")])

        XCTAssertEqual(
            errors(catalog),
            [.unknownResult(pair: JogressPair("war", "metal"), result: "nobody")])
    }

    // MARK: - A parent or result marked dexOnly

    func testADexOnlyParentIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(parentB: "idle_only")])

        XCTAssertEqual(
            errors(catalog),
            [.dexOnlyParent(pair: JogressPair("war", "idle_only"), parent: "idle_only")])
    }

    func testADexOnlyResultIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(result: "idle_only")])

        XCTAssertEqual(
            errors(catalog),
            [.dexOnlyResult(pair: JogressPair("war", "metal"), result: "idle_only")])
    }

    // MARK: - parentA == parentB

    func testARecipeFusingADigimonWithItselfIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(parentA: "war", parentB: "war")])

        XCTAssertEqual(errors(catalog), [.sameParents(parent: "war")])
    }

    // MARK: - A result below a parent's rung

    func testAResultBelowAParentIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(result: "kid")])

        XCTAssertEqual(
            errors(catalog),
            [
                .resultBelowParent(
                    pair: JogressPair("war", "metal"), result: "kid", resultStage: .child,
                    parent: "war", parentStage: .ultimate),
                .resultBelowParent(
                    pair: JogressPair("war", "metal"), result: "kid", resultStage: .child,
                    parent: "metal", parentStage: .ultimate),
            ])
    }

    /// Reported per PARENT, not per recipe: a result below one parent and level with the other is
    /// still one finding, and the author is told which parent it is below.
    func testAResultBelowOnlyOneParentIsRejectedOnceForThatParent() {
        let catalog = JogressCatalog(recipes: [sound(parentB: "kid", result: "kid")])

        XCTAssertEqual(
            errors(catalog),
            [.resultBelowParent(
                pair: JogressPair("war", "kid"), result: "kid", resultStage: .child,
                parent: "war", parentStage: .ultimate)])
    }

    /// The boundary, in the direction that must NOT fire: the Color devices fuse two Ultimates into
    /// an Ultra, which this roster files at the same stage, so EQUAL is sound. An accidental `<=`
    /// would reject every real recipe US-131 is about to write.
    func testAResultLevelWithItsParentsIsSound() {
        XCTAssertEqual(errors(soundCatalog()), [])
        XCTAssertEqual(
            errors(JogressCatalog(recipes: [sound(parentA: "kid", parentB: "war", result: "war")])),
            [])
    }

    /// Armor-Hybrid has no rung (`ladderIndex` is nil), so it is neither above nor below anything —
    /// the same treatment `invalidStageTransition` gives it. Checked from BOTH sides, since the rule
    /// reads a rung off the result and off each parent.
    func testStagesOffTheLadderAreNotLadderChecked() {
        let asResult = JogressCatalog(recipes: [sound(result: "armor")])
        let asParent = JogressCatalog(recipes: [sound(parentB: "armor", result: "kid")])

        XCTAssertEqual(errors(asResult), [])
        XCTAssertEqual(
            errors(asParent),
            [.resultBelowParent(
                pair: JogressPair("armor", "war"), result: "kid", resultStage: .child,
                parent: "war", parentStage: .ultimate)])
    }

    // MARK: - A duplicate parent pair, in either order

    func testTheSamePairAuthoredTwiceIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(), sound()])

        XCTAssertEqual(errors(catalog), [.duplicatePair(JogressPair("war", "metal"), count: 2)])
    }

    /// THE AC's own wording: a file listing both A+B and B+A. It is the SAME finding as the
    /// duplicate above, because `JogressPair` makes the two one key — which is the point of the type
    /// and the reason there is no separate `reversedPair` rule to forget to write.
    func testAPairAuthoredInBothOrdersIsRejected() {
        let catalog = JogressCatalog(recipes: [
            sound(parentA: "war", parentB: "metal"),
            sound(parentA: "metal", parentB: "war"),
        ])

        XCTAssertEqual(errors(catalog), [.duplicatePair(JogressPair("war", "metal"), count: 2)])
    }

    /// Reported ONCE with a count, however many times the pair appears — the author wants to know
    /// how many to go and delete, not to read the same line three times.
    func testAPairAuthoredThreeTimesIsReportedOnceWithItsCount() {
        let catalog = JogressCatalog(recipes: [
            sound(), sound(parentA: "metal", parentB: "war"), sound(result: "war"),
        ])

        XCTAssertEqual(
            errors(catalog).filter {
                if case .duplicatePair = $0 { return true } else { return false }
            },
            [.duplicatePair(JogressPair("war", "metal"), count: 3)])
    }

    /// Two different pairs sharing a parent are not duplicates — the ordinary shape of a roster
    /// where one Ultimate fuses with several others.
    func testTwoPairsSharingAParentAreNotDuplicates() {
        let catalog = JogressCatalog(recipes: [
            sound(parentA: "war", parentB: "metal", result: "omega"),
            sound(parentA: "war", parentB: "kid", result: "omega"),
        ])

        XCTAssertEqual(errors(catalog), [])
    }

    // MARK: - Conditions

    func testAConditionWithABlankHintIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(conditions: [EvolutionCondition(
            metric: .careBattleCount, window: .lifetime, comparison: .atLeast, value: 20,
            hint: "   \n ")])])

        XCTAssertEqual(
            errors(catalog),
            [.emptyConditionHint(
                pair: JogressPair("war", "metal"),
                metric: ConditionMetric.careBattleCount.rawValue)])
    }

    func testAConditionOnAnUnknownMetricIsRejected() {
        let catalog = JogressCatalog(recipes: [sound(conditions: [EvolutionCondition(
            metric: "health.vibes", window: .day, comparison: .atLeast, value: 1,
            hint: "Feel good")])])

        XCTAssertEqual(
            errors(catalog),
            [.unknownConditionMetric(pair: JogressPair("war", "metal"), metric: "health.vibes")])
    }

    /// A condition's own faults are collected BEFORE the roster lookup, so a broken id does not hide
    /// them and the author fixes both in one run — the same ordering, and the same reason, as the
    /// map validator's slots.
    func testABrokenIdDoesNotHideItsConditionsFaults() {
        let catalog = JogressCatalog(recipes: [sound(
            result: "nobody",
            conditions: [EvolutionCondition(
                metric: "health.vibes", window: .day, comparison: .atLeast, value: 1, hint: "")])])

        XCTAssertEqual(
            errors(catalog),
            [
                .emptyConditionHint(pair: JogressPair("war", "metal"), metric: "health.vibes"),
                .unknownConditionMetric(pair: JogressPair("war", "metal"), metric: "health.vibes"),
                .unknownResult(pair: JogressPair("war", "metal"), result: "nobody"),
            ])
    }

    // MARK: - The shipped file

    /// THE AC (US-130 and again US-131): the validator reports ZERO findings over the shipped
    /// `jogress.json`, against the REAL roster rather than a stub.
    ///
    /// US-130 wrote this over an empty file, where it was true but vacuous. US-131 authored the
    /// recipes, so it now sweeps real data — every parent and result resolving to a playable roster
    /// entry, no pair authored twice in either order, no result below a parent's rung.
    func testTheShippedFileHasNoValidationErrors() throws {
        let catalog = try JogressCatalog.load()

        XCTAssertEqual(catalog.validate().map(\.description), [])
        XCTAssertFalse(catalog.recipes.isEmpty, "an empty file would make the sweep above vacuous")
    }

    /// And the real roster the shipped file is validated against is a real check, not a permissive
    /// one — otherwise the zero above could mean "nothing was looked up". A recipe over ids that are
    /// definitely absent must be rejected by it.
    func testTheRealRosterRejectsIdsThatAreNotInIt() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "not_a_digimon", parentB: "also_not", result: "nor_this")
        ])

        XCTAssertEqual(catalog.validate(roster: .bundled).count, 3)
    }
}
