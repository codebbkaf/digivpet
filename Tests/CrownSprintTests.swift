import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-079 — the crown sprint: how far one movement of the crown travelled, how full that leaves the
/// gauge, and what the round it adds up to is worth.
///
/// Everything here is pure. No view is hosted and no crown is turned — a sprint is arithmetic on a
/// distance, which is exactly what "the rotation target is injectable" has to buy.
///
/// The shipped target is 120 and the floors are a half and a quarter of it, so every threshold below
/// is exact in binary. Boundary assertions are ON the number, with no epsilon.

/// The shipped target, used throughout.
private let target = CrownSprintGame.defaultRotationTarget

private func grade(_ rotation: Double) -> TrainingResult {
    CrownSprintGame.grade(rotation: rotation, target: target)
}

// MARK: - AC4: the grade at each floor

final class CrownSprintGradeTests: XCTestCase {

    /// The three floors, by value. Asserted here so the boundary tests below are reading a pinned
    /// set of thresholds rather than agreeing with whatever the code happens to compute.
    func testTheFloorsAreAQuarterAHalfAndTheWholeTarget() {
        XCTAssertEqual(target, 120)
        XCTAssertEqual(target * CrownSprintGame.goodShare, 30)
        XCTAssertEqual(target * CrownSprintGame.greatShare, 60)
    }

    /// AC1/AC4 at every floor, from ONE table: on the number is that grade, and a hair below is the
    /// grade beneath it. `nextDown` is the smallest step that exists at these values, so this is the
    /// boundary itself and not a sample near it.
    func testEachFloorIsInclusiveAndAHairBelowIsTheGradeBeneath() {
        let floors: [(Double, TrainingResult, TrainingResult)] = [
            (30, .good, .miss),
            (60, .great, .good),
            (120, .perfect, .great)
        ]

        for (floor, expected, beneath) in floors {
            XCTAssertEqual(grade(floor), expected, "\(floor) should have been \(expected)")
            XCTAssertEqual(grade(floor.nextDown), beneath,
                           "just under \(floor) should have been \(beneath)")
        }
    }

    /// A crown nobody touched pays nothing, and so does one barely nudged.
    func testAnUntouchedOrBarelyNudgedCrownIsAMiss() {
        XCTAssertEqual(grade(0), .miss)
        XCTAssertEqual(grade(0.5), .miss)
        XCTAssertEqual(grade(29.9), .miss)
    }

    /// Spinning past the target cannot buy a fifth grade — there is no overshoot penalty here, which
    /// is the whole difference between this game and the power meter.
    func testSpinningPastTheTargetIsStillAPerfect() {
        XCTAssertEqual(grade(target), .perfect)
        XCTAssertEqual(grade(target * 3), .perfect)
        XCTAssertEqual(grade(.greatestFiniteMagnitude), .perfect)
    }

    /// The grade only ever climbs with the rotation. Swept across the whole range rather than
    /// sampled, so an inverted comparison anywhere in the ladder shows up here.
    func testTheGradeNeverFallsAsTheCrownTurnsFurther() {
        var best = TrainingResult.miss
        for step in 0...512 {
            let earned = grade(Double(step) * target / 256)
            XCTAssertGreaterThanOrEqual(earned.strengthGain, best.strengthGain,
                                        "the grade fell at \(step)")
            best = earned
        }
        XCTAssertEqual(best, .perfect)
    }

    /// AC3: the target is what decides the grade, so the same sprint is worth different things
    /// against different ones. This is the injection doing the deciding, not a re-derivation of it.
    func testTheSameRotationIsWorthDifferentThingsAgainstDifferentTargets() {
        let rotation = 60.0

        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: 60), .perfect)
        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: 120), .great)
        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: 240), .good)
        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: 1000), .miss)
    }

    /// A degenerate target must not hand out a perfect for doing nothing — 0 >= 0 is true, and that
    /// is exactly the bug the guard is there to stop.
    func testADegenerateTargetIsAMissWhateverTheRotation() {
        for target: Double in [0, -1, -1000] {
            XCTAssertEqual(CrownSprintGame.grade(rotation: 0, target: target), .miss, "\(target)")
            XCTAssertEqual(CrownSprintGame.grade(rotation: 500, target: target), .miss, "\(target)")
        }
    }
}

// MARK: - AC1: the gauge fills toward the target

final class CrownSprintGaugeTests: XCTestCase {

    /// The gauge is the rotation as a share of the target, clamped at both ends.
    func testTheGaugeFillsWithTheRotationAndClamps() {
        XCTAssertEqual(CrownSprintGame.progress(rotation: 0, target: 120), 0)
        XCTAssertEqual(CrownSprintGame.progress(rotation: 30, target: 120), 0.25)
        XCTAssertEqual(CrownSprintGame.progress(rotation: 60, target: 120), 0.5)
        XCTAssertEqual(CrownSprintGame.progress(rotation: 120, target: 120), 1)
        XCTAssertEqual(CrownSprintGame.progress(rotation: 400, target: 120), 1,
                       "the gauge cannot overfill")
        XCTAssertEqual(CrownSprintGame.progress(rotation: -5, target: 120), 0)
        XCTAssertEqual(CrownSprintGame.progress(rotation: 60, target: 0), 0,
                       "a target of zero must not divide")
    }

    /// The number in the gauge rounds DOWN, so 100% means finished rather than nearly.
    func testThePercentLabelOnlyReadsFullWhenTheSprintIsFinished() {
        XCTAssertEqual(CrownSprintGame.percentLabel(rotation: 0, target: 120), "0%")
        XCTAssertEqual(CrownSprintGame.percentLabel(rotation: 60, target: 120), "50%")
        XCTAssertEqual(CrownSprintGame.percentLabel(rotation: 119.9, target: 120), "99%")
        XCTAssertEqual(CrownSprintGame.percentLabel(rotation: 120, target: 120), "100%")
    }

    /// AC3: the window is injectable and it is what drains the timer bar. Inherited from
    /// `TrainingMinigame` since US-079, so this also pins that the sprint gets the same bar the
    /// masher does.
    func testTheTimerDrainsAcrossWhateverWindowIsInjected() {
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 0, window: 4), 1)
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 1, window: 4), 0.75)
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 4, window: 4), 0)
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 9, window: 4), 0)
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 1, window: 0.5), 0,
                       "a shorter window runs out sooner")
        XCTAssertEqual(CrownSprintGame.remainingFraction(at: 1, window: 8), 0.875,
                       "a longer window barely moves")
    }
}

// MARK: - AC1: rotation accumulates, in either direction, across a wrapping binding

final class CrownDeltaTests: XCTestCase {

    private func delta(_ old: Double, _ new: Double) -> Double {
        CrownSprintGame.crownDelta(from: old, to: new, range: CrownSprintGame.crownRange)
    }

    /// Turning either way counts the same. The crown does not say which way is forward, and a
    /// sprint that only counted one direction would be a dexterity test rather than a speed one.
    func testTurningEitherWayCountsTheSameDistance() {
        XCTAssertEqual(delta(100, 130), 30)
        XCTAssertEqual(delta(130, 100), 30)
        XCTAssertEqual(delta(500, 500), 0, "a binding that did not move travelled nothing")
    }

    /// The binding is continuous, so it wraps from the top of its range straight back to the bottom.
    /// A wrap is a tiny movement that looks like an enormous one; counted raw, ONE wrap would win
    /// the round outright — 999 units against a target of 120.
    func testAWrapCountsAsTheShortWayRoundAndNotTheWholeRange() {
        XCTAssertEqual(delta(999, 1), 2, "over the top: 999 -> 1000/0 -> 1")
        XCTAssertEqual(delta(1, 999), 2, "and back under it")

        // The wrap is worth almost nothing, and nothing like enough to buy a grade.
        XCTAssertEqual(CrownSprintGame.grade(rotation: delta(999, 1), target: target), .miss)
    }

    /// Exactly half the range is the furthest an unwrapped movement can be, and the boundary itself
    /// must not flip to the short way round.
    func testHalfTheRangeIsTheFurthestASingleMovementCounts() {
        XCTAssertEqual(delta(0, 500), 500)
        XCTAssertEqual(delta(0, 501), 499, "past halfway the short way round is shorter")
        XCTAssertEqual(delta(0, 500.nextUp), (500.0).nextDown)
    }

    /// A whole sprint is the sum of its movements, wraps included — which is what "accumulates
    /// toward a target" means.
    func testASprintIsTheSumOfItsMovements() {
        let path: [Double] = [0, 40, 80, 20, 980, 940, 990, 30]
        var rotation = 0.0
        for (old, new) in zip(path, path.dropFirst()) {
            rotation += delta(old, new)
        }

        // 40 + 40 + 60 (backwards) + 40 (over the bottom) + 40 + 50 + 40 = 310.
        XCTAssertEqual(rotation, 310)
        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: target), .perfect)
        XCTAssertEqual(CrownSprintGame.grade(rotation: rotation, target: 1000), .good,
                       "the same path against a longer target")
    }

    /// A degenerate range cannot wrap, so the movement is taken at face value rather than divided
    /// by zero.
    func testADegenerateRangeTakesTheMovementAtFaceValue() {
        XCTAssertEqual(CrownSprintGame.crownDelta(from: 10, to: 40, range: 0), 30)
        XCTAssertEqual(CrownSprintGame.crownDelta(from: 40, to: 10, range: -5), 30)
    }
}

// MARK: - The game as a minigame

@MainActor
final class CrownSprintGameTests: XCTestCase {

    /// It is a `TrainingMinigame` in the way US-075 means: buildable knowing only the protocol.
    func testItIsBuildableThroughTheProtocolAlone() {
        func build<Game: TrainingMinigame>(_ type: Game.Type) -> Game {
            Game(onFinish: { _ in })
        }

        _ = build(CrownSprintGame.self)
        XCTAssertEqual(CrownSprintGame.title, "Crown Sprint")
    }

    /// AC3: both knobs are stored properties with the shipped defaults, and both take an override.
    func testTheTargetAndWindowAreInjectable() {
        var game = CrownSprintGame(onFinish: { _ in })
        XCTAssertEqual(game.rotationTarget, CrownSprintGame.defaultRotationTarget)
        XCTAssertEqual(game.window, 5)

        game.rotationTarget = 40
        game.window = 0.01
        XCTAssertEqual(game.rotationTarget, 40)
        XCTAssertEqual(game.window, 0.01)
        XCTAssertEqual(CrownSprintGame.grade(rotation: 40, target: game.rotationTarget), .perfect,
                       "a sprint that would only be a miss at the shipped target")
    }
}
