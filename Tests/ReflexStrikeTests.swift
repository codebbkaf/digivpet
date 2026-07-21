import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-080 — the reflex strike: where the wait before the signal comes from, and what a reaction to
/// it is worth.
///
/// Everything here is pure. No view is hosted and nothing is waited for — the delay is a draw from a
/// pinned `SeededGenerator` and a round is arithmetic on one reaction time, which is exactly what
/// "the delay uses the project's existing SeededGenerator so a test can pin it" has to buy.
///
/// The three thresholds are 0.25, 0.5 and 1.0, all exact in binary, so boundary assertions are ON
/// the number with no epsilon.

private func grade(_ latency: TimeInterval) -> TrainingResult {
    ReflexStrikeGame.grade(latency: latency)
}

// MARK: - AC3: the delay is drawn from a generator a test can pin

final class ReflexStrikeDelayTests: XCTestCase {

    /// The shipped wait: one to three seconds. Asserted by value so the tests below are reading a
    /// pinned range rather than agreeing with whatever the game happens to ship.
    func testTheShippedDelayIsOneToThreeSeconds() {
        let game = ReflexStrikeGame(onFinish: { _ in })
        XCTAssertEqual(game.delayRange.lowerBound, 1)
        XCTAssertEqual(game.delayRange.upperBound, 3)
    }

    /// The point of AC3: the same seed is the same wait, every time. Without this a test could never
    /// know when the signal was due, and so could never tell a false start from a fast reaction.
    func testTheSameSeedDrawsTheSameDelay() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)

        let first = ReflexStrikeGame.delay(using: &a, range: 1...3)
        let second = ReflexStrikeGame.delay(using: &b, range: 1...3)

        XCTAssertEqual(first, second)
    }

    /// …and a whole sequence of rounds off one generator repeats too, not just the first draw. A
    /// game that reset its generator every round would pass the test above and still hand the user
    /// the same wait five times running.
    func testAWholeSequenceOfRoundsRepeatsFromTheSameSeed() {
        var a = SeededGenerator(seed: 2024)
        var b = SeededGenerator(seed: 2024)

        let first = (0..<5).map { _ in ReflexStrikeGame.delay(using: &a, range: 1...3) }
        let second = (0..<5).map { _ in ReflexStrikeGame.delay(using: &b, range: 1...3) }

        XCTAssertEqual(first, second)
        // A sequence of five identical numbers would satisfy the equality above while being a
        // completely unrandomised wait, which is the thing `delayRange` exists to prevent.
        XCTAssertGreaterThan(Set(first).count, 1)
    }

    /// Different seeds are different waits — the randomisation is real, not a constant wearing a
    /// generator's clothes.
    func testDifferentSeedsDrawDifferentDelays() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)

        XCTAssertNotEqual(ReflexStrikeGame.delay(using: &a, range: 1...3),
                          ReflexStrikeGame.delay(using: &b, range: 1...3))
    }

    /// Every draw lands inside the range it was asked for, over enough seeds that a scaling bug
    /// would have to be very lucky to hide.
    func testEveryDrawLandsInsideTheRange() {
        for seed in UInt64(0)..<200 {
            var generator = SeededGenerator(seed: seed)
            let delay = ReflexStrikeGame.delay(using: &generator, range: 1...3)
            XCTAssertGreaterThanOrEqual(delay, 1, "seed \(seed) drew \(delay)")
            XCTAssertLessThanOrEqual(delay, 3, "seed \(seed) drew \(delay)")
        }
    }

    /// The range is injectable, so US-082 can hand a Digimon a longer or crueller wait. A draw from
    /// a different range has to actually respect it.
    func testTheRangeIsInjectable() {
        var generator = SeededGenerator(seed: 99)
        let delay = ReflexStrikeGame.delay(using: &generator, range: 5...6)
        XCTAssertGreaterThanOrEqual(delay, 5)
        XCTAssertLessThanOrEqual(delay, 6)
    }

    /// A degenerate range is the wait it names, rather than a trap. `Double.random(in:)` requires a
    /// non-empty range, and a demo that wants the signal NOW asks for exactly `0...0`.
    func testADegenerateRangeIsTheWaitItNames() {
        var generator = SeededGenerator(seed: 7)
        XCTAssertEqual(ReflexStrikeGame.delay(using: &generator, range: 0...0), 0)
        XCTAssertEqual(ReflexStrikeGame.delay(using: &generator, range: 2...2), 2)
    }

    /// A negative bound is a wait that already elapsed. Lifted to zero rather than drawn from, since
    /// a negative delay would put the signal in the past and make every tap a false start.
    func testANegativeBoundIsLiftedToZeroRatherThanTrapped() {
        var generator = SeededGenerator(seed: 3)
        XCTAssertEqual(ReflexStrikeGame.delay(using: &generator, range: -5 ... -1), 0)

        var other = SeededGenerator(seed: 3)
        let straddling = ReflexStrikeGame.delay(using: &other, range: -1...1)
        XCTAssertGreaterThanOrEqual(straddling, 0)
        XCTAssertLessThanOrEqual(straddling, 1)
    }
}

// MARK: - AC1/AC4: the grade at each threshold

final class ReflexStrikeGradeTests: XCTestCase {

    /// The three thresholds, by value, so the boundary tests below read a pinned set rather than
    /// whatever the code computes.
    func testTheThresholdsAreAQuarterAHalfAndOneSecond() {
        XCTAssertEqual(ReflexStrikeGame.perfectLatency, 0.25)
        XCTAssertEqual(ReflexStrikeGame.greatLatency, 0.5)
        XCTAssertEqual(ReflexStrikeGame.goodLatency, 1.0)
    }

    /// AC1/AC4 at every threshold, from ONE table: on the number is that grade, and a hair past it
    /// is the grade beneath. `nextUp` is the smallest step that exists at these values, so this is
    /// the boundary itself and not a sample near it.
    func testEachThresholdIsInclusiveAndAHairPastIsTheGradeBeneath() {
        let thresholds: [(TimeInterval, TrainingResult, TrainingResult)] = [
            (0.25, .perfect, .great),
            (0.5, .great, .good),
            (1.0, .good, .miss)
        ]

        for (threshold, expected, beneath) in thresholds {
            XCTAssertEqual(grade(threshold), expected, "\(threshold)s should have been \(expected)")
            XCTAssertEqual(grade(threshold.nextUp), beneath,
                           "just past \(threshold)s should have been \(beneath)")
        }
    }

    /// Faster than the perfect threshold is still a perfect. There is no fifth grade to win by being
    /// superhuman, and no penalty for it either — the false start rule is about tapping BEFORE the
    /// signal, not about being quick after it.
    func testFasterThanPerfectIsStillPerfect() {
        XCTAssertEqual(grade(0.001), .perfect)
        XCTAssertEqual(grade(0.1), .perfect)
        XCTAssertEqual(grade(TimeInterval.leastNonzeroMagnitude), .perfect)
    }

    /// A reaction slower than the good threshold buys nothing. This is also the grade a round nobody
    /// answers ends on — see `ReflexStrikeGame.reactionTimeout`.
    func testASlowReactionIsAMiss() {
        XCTAssertEqual(grade(1.5), .miss)
        XCTAssertEqual(grade(2), .miss)
        XCTAssertEqual(grade(30), .miss)
    }
}

// MARK: - AC2: the false start

final class ReflexStrikeFalseStartTests: XCTestCase {

    /// The rule the whole game rests on: a tap before the signal is a miss, however early or late it
    /// was. A negative latency is literally "you answered before it was asked".
    func testTappingBeforeTheSignalIsAMissHoweverEarly() {
        XCTAssertEqual(grade(-0.001), .miss)
        XCTAssertEqual(grade(-0.2), .miss)
        XCTAssertEqual(grade(-2.9), .miss)
        XCTAssertEqual(grade(-TimeInterval.leastNonzeroMagnitude), .miss)
    }

    /// The exact moment the signal is due is not a reaction to it either. Zero is where the false
    /// start rule has to fall on the miss side, or a tap timed by luck to the microsecond would out-
    /// earn every honest reaction on screen.
    func testTappingExactlyOnTheSignalIsAFalseStartRatherThanAPerfect() {
        XCTAssertEqual(grade(0), .miss)
        XCTAssertEqual(grade(-0.0), .miss)
    }

    /// Mashing cannot beat reacting. A guesser taps early every round; the false start rule is what
    /// makes that worth strictly less than the slowest honest answer.
    func testGuessingEarnsStrictlyLessThanTheSlowestHonestReaction() {
        let guessed = grade(-0.05).strengthGain
        let honest = grade(ReflexStrikeGame.goodLatency).strengthGain

        XCTAssertEqual(guessed, 0)
        XCTAssertGreaterThan(honest, guessed)
    }
}

// MARK: - The protocol contract

final class ReflexStrikeContractTests: XCTestCase {

    /// It is a `TrainingMinigame` (US-075) — the same protocol the other four conform to, so US-083
    /// can open it without knowing which game it opened.
    func testItIsATrainingMinigameWithATitle() {
        XCTAssertEqual(ReflexStrikeGame.title, "Reflex Strike")

        let game: any TrainingMinigame = ReflexStrikeGame(onFinish: { _ in })
        XCTAssertTrue(game is ReflexStrikeGame)
    }

    /// The round's own timings are stored properties with defaults, in the manner of the other four,
    /// so a caller drives a whole round in milliseconds and never waits one.
    func testTheRoundTimingsAreInjectable() {
        var game = ReflexStrikeGame(onFinish: { _ in })
        XCTAssertEqual(game.reactionTimeout, 2)
        XCTAssertEqual(game.resultDuration, 1.0)

        game.reactionTimeout = 0.01
        game.resultDuration = 0.01
        game.delayRange = 0...0
        XCTAssertEqual(game.reactionTimeout, 0.01)
        XCTAssertEqual(game.resultDuration, 0.01)
        XCTAssertEqual(game.delayRange, 0...0)
    }

    /// The generator is injectable, and the game draws its wait from the one it was handed — the
    /// delay a pinned generator produces is the delay `delay(using:range:)` produces from the same
    /// seed, which is what makes the wait knowable in a test.
    func testTheGameDrawsItsWaitFromTheGeneratorItWasHanded() {
        var game = ReflexStrikeGame(onFinish: { _ in })
        game.makeGenerator = { SeededGenerator(seed: 4242) }

        var expected = SeededGenerator(seed: 4242)
        var actual = game.makeGenerator()

        XCTAssertEqual(ReflexStrikeGame.delay(using: &actual, range: game.delayRange),
                       ReflexStrikeGame.delay(using: &expected, range: game.delayRange))
    }

    /// Two rounds of the SHIPPED game do not wait the same length, so the beat cannot be learned.
    /// The default generator is seeded randomly; this is what stops a copy-paste of the injected one
    /// from shipping.
    func testTheShippedGameDoesNotWaitTheSameLengthTwice() {
        let delays = (0..<8).map { _ -> TimeInterval in
            let game = ReflexStrikeGame(onFinish: { _ in })
            var generator = game.makeGenerator()
            return ReflexStrikeGame.delay(using: &generator, range: game.delayRange)
        }

        XCTAssertGreaterThan(Set(delays).count, 1)
    }
}
