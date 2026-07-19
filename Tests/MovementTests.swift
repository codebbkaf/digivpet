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
    ///
    /// Sampled over several seconds rather than one step because a rest is a legal first heading —
    /// asserting after a single step would fail whenever the seed opened with a pause, which would
    /// be a flaky test rather than a real defect.
    func testAdvancingTimeMovesThePosition() {
        var model = MovementModel(bound: wideBound, seed: 42, start: Clock.start)
        XCTAssertEqual(model.offset, 0, "starts centred")

        model.advance(to: Clock.after(5))

        XCTAssertNotEqual(model.offset, 0, "five seconds of walking must leave the centre")
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

    /// The invariant that lets the view redraw at whatever cadence it likes: the path depends on
    /// total elapsed time and the seed, never on how the caller chopped that time up.
    func testManySmallAdvancesMatchOneLargeAdvance() {
        var stepwise = MovementModel(bound: wideBound, seed: 99, start: Clock.start)
        for tick in 1...40 { stepwise.advance(to: Clock.after(Double(tick) * 0.25)) }

        var oneShot = MovementModel(bound: wideBound, seed: 99, start: Clock.start)
        oneShot.advance(to: Clock.after(10))

        XCTAssertEqual(stepwise.offset, oneShot.offset)
        XCTAssertEqual(stepwise.facing, oneShot.facing)
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
        model.advance(to: Clock.after(20))
        XCTAssertGreaterThan(abs(model.offset), 10, "needs to be well out from centre to matter")

        model.bound = 10

        XCTAssertLessThanOrEqual(abs(model.offset), 10)
    }

    // MARK: - AC: facing matches direction of travel

    /// Facing is not decoration. Three rules, and the wall is the interesting one:
    ///
    /// - standing ON a bound, facing points INWARD, because that step was a turn. This is the one
    ///   case where facing deliberately disagrees with the direction just travelled — the sprite
    ///   walked right into the wall and is now looking back left, which is what a turn looks like.
    /// - otherwise a step that moved looks the way it moved,
    /// - and a step that rested holds the previous look rather than picking a new one.
    func testFacingAlwaysMatchesTheDirectionOfTravel() {
        var model = MovementModel(bound: wideBound, seed: 5, start: Clock.start)
        var previousOffset = model.offset
        var previousFacing = model.facing
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
                XCTAssertEqual(model.facing, previousFacing, "a rest must hold facing")
            }

            previousOffset = model.offset
            previousFacing = model.facing
        }

        XCTAssertTrue(sawLeft && sawRight, "the walk must go both ways over 100 seconds")
        XCTAssertTrue(sawTurn, "100 seconds of walking must reach a bound at least once")
    }

    // MARK: - AC: deterministic given a seed

    /// Two models on the same seed walk the same path, step for step. This is what makes the exact
    /// path below assertable at all.
    func testTheSameSeedProducesTheSamePath() {
        var first = MovementModel(bound: wideBound, seed: 2024, start: Clock.start)
        var second = MovementModel(bound: wideBound, seed: 2024, start: Clock.start)

        XCTAssertEqual(path(of: &first, steps: 200), path(of: &second, steps: 200))
    }

    /// A different seed is a different Digimon: two pets on screen must not pace in lockstep.
    func testADifferentSeedProducesADifferentPath() {
        var first = MovementModel(bound: wideBound, seed: 1, start: Clock.start)
        var second = MovementModel(bound: wideBound, seed: 2, start: Clock.start)

        XCTAssertNotEqual(path(of: &first, steps: 200), path(of: &second, steps: 200))
    }

    /// The exact path for seed 1, pinned as a literal.
    ///
    /// A regression guard rather than a specification: the numbers are whatever the algorithm
    /// produces, and the point is that a change to the stepping, the speed or the RNG draw ORDER
    /// cannot slip through silently — every other test here would still pass after such a change.
    func testTheExactPathForAFixedSeed() {
        var model = MovementModel(bound: wideBound, seed: 1, start: Clock.start)

        // Readable as a walk: out to the right wall, a turn, two steps back, a seven-step rest at
        // 45, then off to the right again.
        let expected: [CGFloat] = [
            7.5, 15, 22.5, 30, 37.5, 45, 52.5, 60,
            52.5, 45,
            45, 45, 45, 45, 45, 45, 45,
            52.5, 60, 52.5
        ]
        XCTAssertEqual(path(of: &model, steps: expected.count), expected)
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

    /// A long absence is abandoned, not simulated: a backgrounded night must not cost hundreds of
    /// thousands of steps to decide where a 16px sprite stands.
    func testALongAbsenceIsNotSimulated() {
        var model = MovementModel(bound: wideBound, seed: 8, start: Clock.start)
        model.advance(to: Clock.after(10))
        let settled = model.offset

        model.advance(to: Clock.after(10 + MovementModel.maximumCatchUp + 1))
        XCTAssertEqual(model.offset, settled, "the missed walk is dropped, the position kept")

        // And the clock was restamped, so the walk picks up from the new now.
        model.advance(to: Clock.after(10 + MovementModel.maximumCatchUp + 6))
        XCTAssertNotEqual(model.offset, settled, "walking resumes after the gap")
    }
}
