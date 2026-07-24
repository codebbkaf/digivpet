import CoreGraphics
import Foundation
import XCTest

@testable import DigiVPet

/// US-036 — the horizontal wandering model.
///
/// No test waits real time. The "clock" is only ever chosen `Date`s a fixed distance apart, exactly
/// as `HungerTests` does it, and every path here is reproducible because the seed is fixed.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    static func after(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
}

/// A bound wide enough that the sprite can walk for a couple of seconds without hitting a wall, so
/// tests about walking are not secretly tests about bouncing.
private let wideBound: CGFloat = 60

final class MovementTests: XCTestCase {

    /// Every offset the model passes through, sampled once per simulation step.
    private func path(of model: inout MovementModel, steps: Int) -> [CGFloat] {
        (1...steps).map { step in
            model.advance(to: Clock.after(Double(step) * MovementModel.step))
            return model.offset
        }
    }

    // MARK: - AC: advancing time moves position

    /// The headline: hand the model a later date and the Digimon is somewhere else.
    func testAdvancingTimeMovesThePosition() {
        var model = MovementModel(bound: wideBound, seed: 42, start: Clock.start)
        XCTAssertEqual(model.offset, 0, "starts centred")

        model.advance(to: Clock.after(MovementModel.step))

        XCTAssertNotEqual(model.offset, 0, "a step of walking must leave the centre")
    }

    /// Advancing by less than one step does nothing yet — the model is not sub-step continuous.
    func testAdvancingLessThanOneStepDoesNotMove() {
        var model = MovementModel(bound: wideBound, seed: 42, start: Clock.start)

        model.advance(to: Clock.after(MovementModel.step - 0.01))

        XCTAssertEqual(model.offset, 0)
    }

    /// The part-worn step is CARRIED, not discarded: two advances of 0.2s must add up to the step
    /// that 0.4s earns. Dropping the remainder would mean a view redrawing faster than the step
    /// never moved the sprite at all.
    func testAPartialStepIsCarriedAcrossCalls() {
        var carried = MovementModel(bound: wideBound, seed: 7, start: Clock.start)
        carried.advance(to: Clock.after(0.2))
        carried.advance(to: Clock.after(0.4))

        var direct = MovementModel(bound: wideBound, seed: 7, start: Clock.start)
        direct.advance(to: Clock.after(0.4))

        XCTAssertEqual(carried.offset, direct.offset, "0.2 + 0.2 must equal 0.4")
    }

    /// What survives US-216's catch-up cap of the old "any chopping agrees" invariant: a view may
    /// redraw at any cadence up to the cap without changing the path. 0.5s is exactly the cap, so
    /// twenty of those must land where forty 0.25s ticks do.
    func testAdvancesChoppedWithinTheCapAgree() {
        var fine = MovementModel(bound: wideBound, seed: 99, start: Clock.start)
        for tick in 1...40 { fine.advance(to: Clock.after(Double(tick) * 0.25)) }

        var coarse = MovementModel(bound: wideBound, seed: 99, start: Clock.start)
        for tick in 1...20 { coarse.advance(to: Clock.after(Double(tick) * 0.5)) }

        XCTAssertEqual(fine.offset, coarse.offset)
        XCTAssertEqual(fine.facing, coarse.facing)
    }

    // MARK: - AC: hitting a bound reverses

    /// A wall turns the Digimon around: it never leaves the bound, and it does not lean on it.
    ///
    /// The bound is deliberately tiny so a walk in either direction reaches it within one step.
    func testReachingABoundReversesTravelAndNeverExceedsIt() {
        var model = MovementModel(bound: 5, seed: 3, start: Clock.start)
        let offsets = path(of: &model, steps: 400)

        XCTAssertTrue(offsets.contains(5) || offsets.contains(-5), "a tight bound must be reached")
        for offset in offsets {
            XCTAssertLessThanOrEqual(abs(offset), 5, "the sprite must never leave the bound")
        }

        // Having hit a wall, the very next move must come back inward rather than press on into it.
        guard let wallIndex = offsets.firstIndex(where: { abs($0) == 5 }),
              let next = offsets[(wallIndex + 1)...].first(where: { $0 != offsets[wallIndex] })
        else { return XCTFail("the sprite stayed pinned to the wall") }

        XCTAssertLessThan(abs(next), 5, "the step after a wall must move back toward centre")
    }

    /// Facing flips AT the wall, not on the next decision — otherwise the sprite would moonwalk
    /// away from the edge it just bumped.
    func testHittingABoundFlipsFacingImmediately() {
        var model = MovementModel(bound: 5, seed: 3, start: Clock.start)

        for step in 1...400 {
            model.advance(to: Clock.after(Double(step) * MovementModel.step))
            if model.offset == 5 {
                return XCTAssertEqual(model.facing, .left, "pinned right, so it must now look left")
            }
            if model.offset == -5 {
                return XCTAssertEqual(model.facing, .right, "pinned left, so it must now look right")
            }
        }
        XCTFail("never reached a bound")
    }

    /// Shrinking the bound pulls a sprite that is now outside back in, so a layout change can never
    /// strand the Digimon off screen.
    func testShrinkingTheBoundPullsTheSpriteBackInside() {
        var model = MovementModel(bound: 200, seed: 11, start: Clock.start)
        _ = path(of: &model, steps: 3)
        XCTAssertGreaterThan(abs(model.offset), 10, "needs to be well out from centre to matter")

        model.bound = 10

        XCTAssertLessThanOrEqual(abs(model.offset), 10)
    }

    // MARK: - AC: facing matches direction of travel

    /// Facing is not decoration. Two rules, and the wall is the interesting one:
    ///
    /// - standing ON a bound, facing points INWARD, because that step was a turn. This is the one
    ///   case where facing deliberately disagrees with the direction just travelled — the sprite
    ///   walked right into the wall and is now looking back left, which is what a turn looks like.
    /// - otherwise a step looks the way it moved.
    ///
    /// Since US-216 there is no third rule for a rest, because there are no rests: every step off a
    /// wall moves, which is what the `XCTFail` below pins.
    func testFacingAlwaysMatchesTheDirectionOfTravel() {
        var model = MovementModel(bound: wideBound, seed: 5, start: Clock.start)
        var previousOffset = model.offset
        var sawLeft = false
        var sawRight = false
        var sawTurn = false

        for step in 1...400 {
            model.advance(to: Clock.after(Double(step) * MovementModel.step))
            let moved = model.offset - previousOffset

            if abs(model.offset) == wideBound {
                sawTurn = true
                XCTAssertEqual(model.facing, model.offset > 0 ? .left : .right,
                               "on a bound it must look back inward, at step \(step)")
            } else if moved > 0 {
                sawRight = true
                XCTAssertEqual(model.facing, .right, "moved right at step \(step)")
            } else if moved < 0 {
                sawLeft = true
                XCTAssertEqual(model.facing, .left, "moved left at step \(step)")
            } else {
                XCTFail("the walk never stands still off a wall, but step \(step) did")
            }

            previousOffset = model.offset
        }

        XCTAssertTrue(sawLeft && sawRight, "the walk must go both ways over 100 seconds")
        XCTAssertTrue(sawTurn, "100 seconds of walking must reach a bound at least once")
    }

    // MARK: - US-216: a deterministic edge-to-edge ping-pong

    /// Two models on the same seed walk the same path, step for step. This is what makes the exact
    /// path below assertable at all.
    func testTheSameSeedProducesTheSamePath() {
        var first = MovementModel(bound: wideBound, seed: 2024, start: Clock.start)
        var second = MovementModel(bound: wideBound, seed: 2024, start: Clock.start)

        XCTAssertEqual(path(of: &first, steps: 200), path(of: &second, steps: 200))
    }

    /// The seed's whole remaining job: which way the Digimon sets off. Two pets on one screen must
    /// not pace in lockstep, and an even/odd seed is now the only thing that tells them apart.
    func testTheSeedChoosesTheOpeningDirection() {
        var even = MovementModel(bound: wideBound, seed: 2, start: Clock.start)
        var odd = MovementModel(bound: wideBound, seed: 1, start: Clock.start)

        XCTAssertEqual(even.facing, .right)
        XCTAssertEqual(odd.facing, .left)

        let rightward = path(of: &even, steps: 200)
        let leftward = path(of: &odd, steps: 200)
        XCTAssertNotEqual(rightward, leftward)
        // Mirrored, in fact: the same pace, opened the other way.
        XCTAssertEqual(rightward, leftward.map { -$0 })
    }

    /// The exact path for seed 1, pinned as a literal.
    ///
    /// A regression guard rather than a specification, and after US-216 it reads as the story does:
    /// an odd seed sets off LEFT, eight steady 7.5pt strides to the wall at -60, a turn, and twelve
    /// more the other way. No pause, no mid-floor reversal, and every gap identical.
    func testTheExactPathForAFixedSeed() {
        var model = MovementModel(bound: wideBound, seed: 1, start: Clock.start)

        let expected: [CGFloat] = [
            -7.5, -15, -22.5, -30, -37.5, -45, -52.5, -60,
            -52.5, -45, -37.5, -30, -22.5, -15, -7.5, 0, 7.5, 15, 22.5, 30
        ]
        XCTAssertEqual(path(of: &model, steps: expected.count), expected)
    }

    /// The heart of the story: every step covers exactly the same ground, and the direction only
    /// ever changes ON a wall. A single mid-screen reversal or one oversized stride fails this.
    ///
    /// `wideBound` is a whole number of strides from centre, so no step is ever cut short by the
    /// clamp at the wall and "every stride identical" is exactly true.
    func testThePaceIsConstantAndTurnsOnlyAtAWall() {
        var model = MovementModel(bound: wideBound, seed: 4, start: Clock.start)
        let offsets = [0] + path(of: &model, steps: 400)

        var previousDirection: CGFloat = 0
        for index in 1..<offsets.count {
            let moved = offsets[index] - offsets[index - 1]
            XCTAssertEqual(abs(moved), MovementModel.stepDistance, accuracy: 0.0001,
                           "every stride is the same length, at step \(index)")

            let direction: CGFloat = moved > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                XCTAssertEqual(abs(offsets[index - 1]), wideBound,
                               "a reversal may only happen standing on a wall, at step \(index)")
            }
            previousDirection = direction
        }
    }

    // MARK: - Clock robustness

    /// A clock that jumped backwards must not move the sprite, and must not leave `updatedAt` in
    /// the future where it would freeze the walk until real time caught up.
    func testAClockGoingBackwardsDoesNotMoveTheSprite() {
        var model = MovementModel(bound: wideBound, seed: 8, start: Clock.start)
        model.advance(to: Clock.after(10))
        let settled = model.offset

        model.advance(to: Clock.after(4))
        XCTAssertEqual(model.offset, settled, "a backwards clock is not a walk")

        // Restamped to the earlier date, so a step measured from THERE moves again.
        model.advance(to: Clock.after(9))
        XCTAssertNotEqual(model.offset, settled, "the walk resumes rather than freezing")
    }

    /// US-216's headline: no gap, however long, can move the sprite more than the cap.
    ///
    /// A backgrounded night used to be simulated in full up to a minute's worth of steps and then
    /// abandoned; either way the sprite arrived somewhere it had visibly not walked to. Now the same
    /// two strides apply whether the gap was a second, an hour or a night.
    func testALongGapMovesNoFurtherThanTheCap() {
        let cap = CGFloat(MovementModel.maximumCatchUpSteps) * MovementModel.stepDistance

        for gap in [MovementModel.maximumCatchUp + 0.25, 10, 3_600, 86_400] as [TimeInterval] {
            var model = MovementModel(bound: wideBound, seed: 8, start: Clock.start)
            model.advance(to: Clock.after(gap))

            XCTAssertLessThanOrEqual(abs(model.offset), cap,
                                     "a \(gap)s gap must not sprint the sprite")
        }
    }

    /// And the surplus is forgiven, not banked: the advance after a long gap is one ordinary step,
    /// not the rest of the debt paid off two strides at a time.
    func testALongGapIsNotRepaidOnLaterAdvances() {
        var model = MovementModel(bound: wideBound, seed: 8, start: Clock.start)
        model.advance(to: Clock.after(86_400))
        let afterTheGap = model.offset

        model.advance(to: Clock.after(86_400 + MovementModel.step))
        XCTAssertEqual(abs(model.offset - afterTheGap), MovementModel.stepDistance, accuracy: 0.0001,
                       "one step's worth of time is one step of travel, gap or no gap")
    }

    // MARK: - US-037: suspending the walk

    /// The defect `hold(at:)` exists to prevent: a suspension that only SKIPS advancing leaves the
    /// clock behind, and the first advance afterwards applies the whole pause at once. Held
    /// properly, a paused stretch costs exactly the steps it lasted and no more.
    func testHoldingSuspendsTheWalkWithoutBankingIt() {
        var held = MovementModel(bound: wideBound, seed: 3, start: Clock.start)
        held.advance(to: Clock.after(2))
        let paused = held.offset

        // Five seconds asleep, eating, or behind an overlay.
        for second in 3...7 { held.hold(at: Clock.after(Double(second))) }
        XCTAssertEqual(held.offset, paused, "a held sprite does not walk")

        // One step after resuming is ONE step of travel, not twenty banked up.
        held.advance(to: Clock.after(7 + MovementModel.step))
        XCTAssertLessThanOrEqual(
            abs(held.offset - paused),
            MovementModel.pointsPerSecond * CGFloat(MovementModel.step),
            "resuming must not teleport the sprite across the screen"
        )
    }

    /// A held pause costs the walk nothing but time: what resumes is the same path the same seed
    /// would have walked, just later. This is what lets the sprite pick up where it stood.
    ///
    /// Both walks are driven one step at a time, because a pause is only interesting against a walk
    /// that actually happened — handing either model a multi-second jump would just measure the
    /// catch-up cap on both sides.
    func testAHeldPauseDoesNotChangeThePathThatFollows() {
        var uninterrupted = MovementModel(bound: wideBound, seed: 11, start: Clock.start)
        for tick in 1...16 { uninterrupted.advance(to: Clock.after(Double(tick) * MovementModel.step)) }

        var interrupted = MovementModel(bound: wideBound, seed: 11, start: Clock.start)
        for tick in 1...8 { interrupted.advance(to: Clock.after(Double(tick) * MovementModel.step)) }
        // Thirty seconds asleep, then eight more steps measured from the far side of the pause.
        interrupted.hold(at: Clock.after(30))
        for tick in 1...8 { interrupted.advance(to: Clock.after(30 + Double(tick) * MovementModel.step)) }

        XCTAssertEqual(interrupted.offset, uninterrupted.offset,
                       "sixteen steps of walking is sixteen steps of walking, paused or not")
        XCTAssertEqual(interrupted.facing, uninterrupted.facing)
    }
}
