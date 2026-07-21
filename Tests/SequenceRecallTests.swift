import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-081 — sequence recall: where the pattern comes from, what stopping at the first mistake means,
/// and what a part-remembered pattern is worth.
///
/// Everything here is pure. No view is hosted and nothing is waited for — the pattern is a draw from
/// a pinned `SeededGenerator` and a round is arithmetic over one attempt, which is exactly what
/// "generation uses SeededGenerator" and "grade-from-correct-count is pure and unit-tested" have to
/// buy.

private func grade(_ correct: Int, of length: Int) -> TrainingResult {
    SequenceRecallGame.grade(correct: correct, length: length)
}

// MARK: - AC3: the pattern is drawn from a generator a test can pin

final class SequenceRecallGenerationTests: XCTestCase {

    /// The shipped pattern: four steps over four pads. Asserted by value so the tests below are
    /// reading a pinned shape rather than agreeing with whatever the game happens to ship.
    func testTheShippedPatternIsFourStepsOverFourPads() {
        let game = SequenceRecallGame(onFinish: { _ in })
        XCTAssertEqual(game.sequenceLength, 4)
        XCTAssertEqual(SequenceRecallGame.padCount, 4)
    }

    /// The point of AC3: the same seed is the same pattern, every time. Without this a test could
    /// never know what the round was asking for, and so could never stage an attempt against it.
    func testTheSameSeedDrawsTheSamePattern() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)

        XCTAssertEqual(SequenceRecallGame.sequence(using: &a, length: 4),
                       SequenceRecallGame.sequence(using: &b, length: 4))
    }

    /// …and a whole run of rounds off one generator repeats too, not just the first. A game that
    /// reset its generator every round would pass the test above and still ask for the same four
    /// pads five rounds running.
    func testAWholeRunOfRoundsRepeatsFromTheSameSeed() {
        var a = SeededGenerator(seed: 2024)
        var b = SeededGenerator(seed: 2024)

        let first = (0..<5).map { _ in SequenceRecallGame.sequence(using: &a, length: 4) }
        let second = (0..<5).map { _ in SequenceRecallGame.sequence(using: &b, length: 4) }

        XCTAssertEqual(first, second)
        // Five identical patterns would satisfy the equality above while being a completely
        // unrandomised round, which is the thing the generator exists to prevent.
        XCTAssertGreaterThan(Set(first).count, 1)
    }

    /// Different seeds are different patterns — the randomisation is real, not a constant wearing a
    /// generator's clothes.
    func testDifferentSeedsDrawDifferentPatterns() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)

        XCTAssertNotEqual(SequenceRecallGame.sequence(using: &a, length: 8),
                          SequenceRecallGame.sequence(using: &b, length: 8))
    }

    /// Every step is a pad that exists, over enough seeds that an off-by-one in the range would have
    /// to be very lucky to hide. A step of 4 would index past the pads and crash the round.
    func testEveryStepIsAPadThatExists() {
        for seed in UInt64(0)..<200 {
            var generator = SeededGenerator(seed: seed)
            for step in SequenceRecallGame.sequence(using: &generator, length: 6) {
                XCTAssertGreaterThanOrEqual(step, 0, "seed \(seed) drew \(step)")
                XCTAssertLessThan(step, SequenceRecallGame.padCount, "seed \(seed) drew \(step)")
            }
        }
    }

    /// The length is injectable, so US-082 can hand a Digimon a longer pattern, and the draw has to
    /// actually respect it.
    func testTheLengthIsInjectable() {
        for length in [1, 3, 12] {
            var generator = SeededGenerator(seed: 99)
            XCTAssertEqual(SequenceRecallGame.sequence(using: &generator, length: length).count,
                           length)
        }
    }

    /// A non-positive length is an empty pattern rather than a trap. `Int.random(in:)` requires a
    /// non-empty range, and `(0..<length)` for a negative length would crash.
    func testANonPositiveLengthIsAnEmptyPattern() {
        var generator = SeededGenerator(seed: 7)
        XCTAssertEqual(SequenceRecallGame.sequence(using: &generator, length: 0), [])
        XCTAssertEqual(SequenceRecallGame.sequence(using: &generator, length: -3), [])
    }

    /// Repeats are allowed — a pattern that could never light the same pad twice would leak what is
    /// coming. Over a long enough draw at least one has to appear, or the generator is quietly
    /// filtering them.
    func testAPatternMayLightTheSamePadTwiceInARow() {
        var generator = SeededGenerator(seed: 5)
        let steps = SequenceRecallGame.sequence(using: &generator, length: 60)

        XCTAssertTrue(zip(steps, steps.dropFirst()).contains { $0 == $1 },
                      "60 steps over 4 pads with no consecutive repeat means repeats are filtered")
    }
}

// MARK: - AC2: the first wrong entry ends the round

final class SequenceRecallCorrectCountTests: XCTestCase {

    /// A complete, correct playback is the whole pattern remembered.
    func testAPerfectPlaybackCountsEveryStep() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [2, 0, 3, 1], against: [2, 0, 3, 1]), 4)
    }

    /// The rule itself: counting stops at the first mismatch. Two of the pattern were remembered, so
    /// two is what the round is worth however the rest of the attempt went.
    func testCountingStopsAtTheFirstWrongEntry() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [2, 0, 1], against: [2, 0, 3, 1]), 2)
    }

    /// Nothing after a mistake counts, even when it happens to match. Without this a wrong entry
    /// would be a free retry, and the game would reward guessing your way along the pattern.
    func testStepsAfterAMistakeDoNotCountEvenIfTheyMatch() {
        let attempt = [2, 1, 3, 1] // step 2 wrong; steps 3 and 4 happen to be right
        XCTAssertEqual(SequenceRecallGame.correctCount(of: attempt, against: [2, 0, 3, 1]), 1)
    }

    /// A wrong FIRST entry is a round worth nothing, which is the harshest form of the rule and the
    /// one the wrong-entry ending mostly hits.
    func testAWrongFirstEntryRemembersNothing() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [3], against: [2, 0, 3, 1]), 0)
    }

    /// A partial attempt counts what it has — this is what the round is graded on when `inputTimeout`
    /// ends it with the user mid-pattern.
    func testAPartialAttemptCountsWhatItHas() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [], against: [2, 0, 3, 1]), 0)
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [2, 0], against: [2, 0, 3, 1]), 2)
    }

    /// An attempt longer than the pattern stops at the pattern's end, rather than reading past it.
    /// The round ends the moment the last step lands, so this is a guard rather than a scenario.
    func testAnOverlongAttemptStopsAtThePatternsEnd() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [2, 0, 3, 1, 1, 1], against: [2, 0, 3, 1]),
                       4)
    }

    /// Nothing can be remembered of nothing. Reading an empty pattern must not be a full house.
    func testAnEmptyPatternRemembersNothing() {
        XCTAssertEqual(SequenceRecallGame.correctCount(of: [0, 1, 2], against: []), 0)
    }
}

// MARK: - AC1/AC2/AC4: the grade from the correct count

final class SequenceRecallGradeTests: XCTestCase {

    /// The shares each grade asks for, by value, so the boundary tests below read a pinned set rather
    /// than whatever the code computes.
    func testTheSharesAreHalfThreeQuartersAndAll() {
        XCTAssertEqual(SequenceRecallGame.requiredShare(for: .miss), 0)
        XCTAssertEqual(SequenceRecallGame.requiredShare(for: .good), 0.5)
        XCTAssertEqual(SequenceRecallGame.requiredShare(for: .great), 0.75)
        XCTAssertEqual(SequenceRecallGame.requiredShare(for: .perfect), 1)
    }

    /// What the shipped four-step pattern costs, step by step. Counts are integers, so these are the
    /// thresholds themselves and not samples near them.
    func testTheShippedFourStepPatternCostsTwoThreeAndFour() {
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .good, length: 4), 2)
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .great, length: 4), 3)
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .perfect, length: 4), 4)
    }

    /// AC1/AC4 at every threshold of the shipped pattern: on the number is that grade, and one step
    /// short is the grade beneath.
    func testEachThresholdIsInclusiveAndOneStepShortIsTheGradeBeneath() {
        let thresholds: [(Int, TrainingResult, TrainingResult)] = [
            (4, .perfect, .great),
            (3, .great, .good),
            (2, .good, .miss)
        ]

        for (correct, expected, beneath) in thresholds {
            XCTAssertEqual(grade(correct, of: 4), expected,
                           "\(correct) of 4 should have been \(expected)")
            XCTAssertEqual(grade(correct - 1, of: 4), beneath,
                           "\(correct - 1) of 4 should have been \(beneath)")
        }
    }

    /// AC2's premise, at any length: the whole pattern is a perfect and one step short never is.
    /// This is the rule the game is built on, so it is asserted across lengths rather than at four.
    func testOnlyAFullyCorrectPatternIsPerfect() {
        for length in 1...20 {
            XCTAssertEqual(grade(length, of: length), .perfect, "all \(length) should be perfect")
            XCTAssertNotEqual(grade(length - 1, of: length), .perfect,
                              "\(length - 1) of \(length) must not be perfect")
        }
    }

    /// The requirement is a share, so a longer pattern asks for proportionally more — this is what
    /// stops US-082's longer patterns from being easier than the shipped one.
    func testALongerPatternAsksForProportionallyMore() {
        XCTAssertEqual(grade(6, of: 12), .good)
        XCTAssertEqual(grade(9, of: 12), .great)
        XCTAssertEqual(grade(11, of: 12), .great)
        XCTAssertEqual(grade(12, of: 12), .perfect)
        XCTAssertEqual(grade(5, of: 12), .miss)
    }

    /// Rounding is UP, so a fractional requirement is never met by falling short of it. A three-step
    /// pattern asks for 1.5 steps of `good` and 2.25 of `great`; both round up.
    func testAFractionalRequirementRoundsUp() {
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .good, length: 3), 2)
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .great, length: 3), 3)
        XCTAssertEqual(grade(1, of: 3), .miss)
        XCTAssertEqual(grade(2, of: 3), .good)
        XCTAssertEqual(grade(3, of: 3), .perfect)
    }

    /// Remembering nothing buys nothing, at any length. This is the grade an untouched round ends on
    /// when `inputTimeout` elapses, and the one a wrong first entry earns.
    func testRememberingNothingIsAMiss() {
        for length in 1...10 {
            XCTAssertEqual(grade(0, of: length), .miss)
        }
    }

    /// A grade never asks for zero steps, however short the pattern. A one-step pattern must not hand
    /// a `good` to someone who never touched a pad.
    func testAShortPatternStillAsksForAtLeastOneStep() {
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .good, length: 1), 1)
        XCTAssertEqual(SequenceRecallGame.requiredCorrect(for: .great, length: 1), 1)
        XCTAssertEqual(grade(0, of: 1), .miss)
        XCTAssertEqual(grade(1, of: 1), .perfect)
    }

    /// A pattern with no steps is a miss rather than a free perfect: remembering all of nothing is
    /// not a round that was played. Reachable only through an injected `sequenceLength` of zero.
    func testAnEmptyPatternIsAMissRatherThanAFreePerfect() {
        XCTAssertEqual(grade(0, of: 0), .miss)
        XCTAssertEqual(grade(3, of: 0), .miss)
        XCTAssertEqual(grade(0, of: -2), .miss)
    }

    /// Counts outside the pattern are clamped rather than trusted — a negative count cannot drop
    /// below a miss, and an impossible one cannot buy more than a perfect.
    func testCountsOutsideThePatternAreClamped() {
        XCTAssertEqual(grade(-5, of: 4), .miss)
        XCTAssertEqual(grade(99, of: 4), .perfect)
    }
}

// MARK: - The protocol contract

final class SequenceRecallContractTests: XCTestCase {

    /// It is a `TrainingMinigame` (US-075) — the same protocol the other five conform to, so US-083
    /// can open it without knowing which game it opened.
    func testItIsATrainingMinigameWithATitle() {
        XCTAssertEqual(SequenceRecallGame.title, "Sequence Recall")

        let game: any TrainingMinigame = SequenceRecallGame(onFinish: { _ in })
        XCTAssertTrue(game is SequenceRecallGame)
    }

    /// The round's own timings are stored properties with defaults, in the manner of the other five,
    /// so a caller drives a whole round in milliseconds and never waits one. `stepDuration` and
    /// `stepGap` together are AC3's injectable playback speed.
    func testTheRoundTimingsAreInjectable() {
        var game = SequenceRecallGame(onFinish: { _ in })
        XCTAssertEqual(game.stepDuration, 0.45)
        XCTAssertEqual(game.stepGap, 0.18)
        XCTAssertEqual(game.inputTimeout, 12)
        XCTAssertEqual(game.resultDuration, 1.0)

        game.stepDuration = 0.01
        game.stepGap = 0.01
        game.inputTimeout = 0.01
        game.resultDuration = 0.01
        game.sequenceLength = 2
        XCTAssertEqual(game.stepDuration, 0.01)
        XCTAssertEqual(game.stepGap, 0.01)
        XCTAssertEqual(game.inputTimeout, 0.01)
        XCTAssertEqual(game.resultDuration, 0.01)
        XCTAssertEqual(game.sequenceLength, 2)
    }

    /// The gap between two lit pads is never zero in the shipped game: it is the only thing that
    /// makes a repeated pad readable as two steps, and repeats are allowed.
    func testTheShippedGapIsNonZeroSoARepeatedPadIsReadable() {
        let game = SequenceRecallGame(onFinish: { _ in })
        XCTAssertGreaterThan(game.stepGap, 0)
    }

    /// The generator is injectable, and the game draws its pattern from the one it was handed — the
    /// pattern a pinned generator produces is the pattern `sequence(using:length:)` produces from the
    /// same seed, which is what makes the round knowable in a test.
    func testTheGameDrawsItsPatternFromTheGeneratorItWasHanded() {
        var game = SequenceRecallGame(onFinish: { _ in })
        game.makeGenerator = { SeededGenerator(seed: 4242) }

        var expected = SeededGenerator(seed: 4242)
        var actual = game.makeGenerator()

        XCTAssertEqual(SequenceRecallGame.sequence(using: &actual, length: game.sequenceLength),
                       SequenceRecallGame.sequence(using: &expected, length: game.sequenceLength))
    }

    /// Two rounds of the SHIPPED game do not ask for the same pattern, so it cannot be learned. The
    /// default generator is seeded randomly; this is what stops a copy-paste of the injected one from
    /// shipping.
    func testTheShippedGameDoesNotAskForTheSamePatternTwice() {
        let patterns = (0..<8).map { _ -> [Int] in
            let game = SequenceRecallGame(onFinish: { _ in })
            var generator = game.makeGenerator()
            return SequenceRecallGame.sequence(using: &generator, length: game.sequenceLength)
        }

        XCTAssertGreaterThan(Set(patterns).count, 1)
    }

    /// Every pad has a colour and a symbol of its own. The symbol is what makes the four
    /// distinguishable without colour vision, so duplicates here would be an unplayable round for
    /// some users rather than a cosmetic slip.
    func testEveryPadLooksDifferent() {
        let pads = 0..<SequenceRecallGame.padCount
        XCTAssertEqual(Set(pads.map { SequenceRecallGame.symbol(for: $0) }).count,
                       SequenceRecallGame.padCount)
        XCTAssertEqual(Set(pads.map { SequenceRecallGame.tint(for: $0).description }).count,
                       SequenceRecallGame.padCount)
    }

    /// The demo's wrong entry is genuinely wrong, for every pad. It is what makes a staged screenshot
    /// end on the real wrong-entry rule rather than on an asserted grade.
    func testTheStagedWrongEntryIsNeverTheRightOne() {
        for pad in 0..<SequenceRecallGame.padCount {
            let wrong = SequenceRecallGame.wrongPad(insteadOf: pad)
            XCTAssertNotEqual(wrong, pad)
            XCTAssertGreaterThanOrEqual(wrong, 0)
            XCTAssertLessThan(wrong, SequenceRecallGame.padCount)
        }
    }
}
