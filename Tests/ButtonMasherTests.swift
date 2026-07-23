import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-077 — the button masher: how many taps a round needs, and what a count is worth.
///
/// Everything here is pure. No view is hosted and nothing waits a window — the window is arithmetic
/// on a count, which is exactly what "the window duration is injectable" has to buy.

// MARK: - AC1 / AC4: the grade at each threshold

final class ButtonMasherThresholdTests: XCTestCase {

    /// The window used throughout: the shipped five seconds, whose thresholds are 15 / 23 / 30.
    private let window: TimeInterval = 5

    /// The three thresholds, by value. Asserted here so the boundary tests below are reading a
    /// pinned pace rather than agreeing with whatever the code happens to compute.
    func testTheThresholdsAreThreeFourAndAHalfAndSixTapsASecond() {
        XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .good, window: window), 15)
        XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .great, window: window), 23)
        XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .perfect, window: window), 30)
    }

    /// A miss asks for nothing — it is where every round starts, not something to reach.
    func testAMissAsksForNoTapsAtAll() {
        XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .miss, window: window), 0)
        XCTAssertEqual(ButtonMasherGame.grade(taps: 0, window: window), .miss)
    }

    /// AC4 at every threshold, from ONE table: on the number is that grade, one tap short is the
    /// grade below. Counts are integers, so "just short" is exactly one less — there is no epsilon
    /// here and no boundary that floating point can move.
    func testEachThresholdIsInclusiveAndOneTapShortIsTheGradeBelow() {
        let below: [TrainingResult: TrainingResult] = [.good: .miss, .great: .good, .perfect: .great]

        for (grade, lower) in below {
            let required = ButtonMasherGame.requiredTaps(for: grade, window: window)
            XCTAssertEqual(ButtonMasherGame.grade(taps: required, window: window), grade,
                           "\(required) taps should have been \(grade)")
            XCTAssertEqual(ButtonMasherGame.grade(taps: required - 1, window: window), lower,
                           "\(required - 1) taps should have been \(lower)")
        }
    }

    /// AC1 across the whole range: every count from nothing to well past a perfect grades, and the
    /// grades come in order with no band skipped and none out of sequence.
    func testTheGradeOnlyEverImprovesAsYouTapMore() {
        let grades = (0...40).map { ButtonMasherGame.grade(taps: $0, window: window) }

        XCTAssertEqual(grades.reduce(into: [TrainingResult]()) { runs, grade in
            if runs.last != grade { runs.append(grade) }
        }, [.miss, .good, .great, .perfect])
    }

    /// Mashing past the top threshold is still a perfect, not a wrap-around.
    func testThereIsNoCeilingAboveAPerfect() {
        for taps in [30, 45, 100, 1_000] {
            XCTAssertEqual(ButtonMasherGame.grade(taps: taps, window: window), .perfect,
                           "\(taps) taps")
        }
    }
}

// MARK: - AC2: the window is injectable, and it is what the count is read against

final class ButtonMasherWindowTests: XCTestCase {

    /// AC2: the SAME count is a different grade in a different window. This is the whole reason the
    /// thresholds are a rate — twenty taps is a great round in five seconds and a miss in ten.
    func testTheSameCountIsWorthDifferentThingsInDifferentWindows() {
        XCTAssertEqual(ButtonMasherGame.grade(taps: 20, window: 2), .perfect)
        XCTAssertEqual(ButtonMasherGame.grade(taps: 20, window: 5), .good)
        XCTAssertEqual(ButtonMasherGame.grade(taps: 20, window: 10), .miss)
    }

    /// The thresholds scale with the window, so the game asks for the same PACE however long it
    /// runs. Without this, a round driven in milliseconds by a test could not be graded at all.
    func testTheThresholdsScaleWithTheWindow() {
        for window: TimeInterval in [1, 2, 4, 8] {
            XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .good, window: window),
                           Int(3 * window))
            XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .perfect, window: window),
                           Int(6 * window))
        }
    }

    /// A fractional requirement is rounded UP: 4.5 taps a second over three seconds is 13.5, and
    /// thirteen taps must not buy a great by falling half a tap short of it.
    func testAFractionalRequirementIsRoundedUp() {
        XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .great, window: 3), 14)
        XCTAssertEqual(ButtonMasherGame.grade(taps: 13, window: 3), .good)
        XCTAssertEqual(ButtonMasherGame.grade(taps: 14, window: 3), .great)
    }

    /// A window too short to ask for a whole tap still asks for one, so a round nobody touched
    /// cannot come out a perfect on an arithmetic technicality.
    func testADegenerateWindowStillAsksForAtLeastOneTap() {
        for window: TimeInterval in [0.01, 0, -5] {
            XCTAssertEqual(ButtonMasherGame.requiredTaps(for: .perfect, window: window), 1)
            XCTAssertEqual(ButtonMasherGame.grade(taps: 0, window: window), .miss, "window \(window)")
        }
    }

    /// The timer bar drains from full to empty over the window and stops at both ends.
    func testTheTimerDrainsAcrossTheWindowAndClampsAtBothEnds() {
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 0, window: 4), 1)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 1, window: 4), 0.75)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 2, window: 4), 0.5)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 4, window: 4), 0)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 9, window: 4), 0)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: -1, window: 4), 1)
        XCTAssertEqual(ButtonMasherGame.remainingFraction(at: 1, window: 0), 0)
    }
}

// MARK: - The game as a minigame

@MainActor
final class ButtonMasherGameTests: XCTestCase {

    /// It is a `TrainingMinigame` in the way US-075 means: buildable knowing only the protocol.
    func testItConformsThroughTheProtocolAlone() {
        let game = makeGame(ButtonMasherGame.self) { _ in }

        XCTAssertEqual(type(of: game).title, "Button Masher")
        XCTAssertGreaterThan(game.window, 0, "a window nothing can be tapped in")
    }

    /// AC2: the knobs are settable at the call site, so a round can be driven in milliseconds
    /// without a second initialiser.
    func testTheWindowAndPacingAreInjectable() {
        var game = makeGame(ButtonMasherGame.self) { _ in }
        XCTAssertEqual(game.window, 5)
        XCTAssertEqual(game.resultDuration, 1.0)
        XCTAssertEqual(game.idleTimeout, 12)

        game.window = 0.05
        game.resultDuration = 0.01
        game.idleTimeout = 0.02

        XCTAssertEqual(game.window, 0.05)
        XCTAssertEqual(game.resultDuration, 0.01)
        XCTAssertEqual(game.idleTimeout, 0.02)
    }

    /// The shipped round is neither impossible nor automatic: a perfect wants six taps a second,
    /// which is fast but human, and idly poking the screen a couple of times a second earns
    /// nothing. Guards against a later tweak quietly making the masher free.
    func testTheShippedRoundIsNeitherImpossibleNorAutomatic() {
        let game = makeGame(ButtonMasherGame.self) { _ in }

        XCTAssertEqual(ButtonMasherGame.grade(taps: Int(2 * game.window), window: game.window),
                       .miss, "two taps a second is a training session")
        XCTAssertEqual(ButtonMasherGame.grade(taps: Int(6 * game.window), window: game.window),
                       .perfect, "six taps a second is not a perfect")
        XCTAssertLessThanOrEqual(ButtonMasherGame.tapsPerSecond(for: .perfect), 8,
                                 "faster than a person can tap")
    }

    /// The grade the masher produces is a value `TrainAction` already knows how to pay out — the
    /// game itself knows nothing about energy or stats.
    func testAGradeOffTheCounterIsWhatTheActionPaysOut() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: Date(timeIntervalSinceReferenceDate: 600_000))
        state.trainCharges = 1
        TrainAction.begin(state, isAsleep: false)

        TrainAction.finish(state, result: ButtonMasherGame.grade(taps: 30, window: 5))

        XCTAssertEqual(state.strengthStat, TrainingResult.perfect.strengthGain)
        XCTAssertEqual(state.stageTrainingSessions, 1)
    }

    private func makeGame<Game: TrainingMinigame>(
        _ type: Game.Type, onFinish: @escaping (TrainingResult) -> Void
    ) -> Game {
        Game(onFinish: onFinish)
    }
}
