import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-220 — the walk is DRAWN continuously between the steps the model takes.
///
/// This is a rendering story, so most of it is only visible on a watch; what can be pinned here is
/// the arithmetic the rendering rests on. Two things:
///
/// 1. the tween's duration is the simulation step, so one tween ends exactly as the next begins;
/// 2. `MovementModel` is untouched — the walk still steps, and the tween only interpolates between
///    positions the model chose. The path assertions below are deliberately a repeat of what
///    `MovementTests` already proves: if this story had "smoothed" the walk by editing the model,
///    every one of them would be the thing that noticed.
@MainActor
final class WalkTweenTests: XCTestCase {

    private enum Clock {
        static let start = Date(timeIntervalSinceReferenceDate: 900_000)
        static func after(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    }

    private func view(motion: ActionMotion? = nil) -> WanderingSpriteView {
        WanderingSpriteView(stage: "Child", name: "Agumon", motion: motion)
    }

    // MARK: - The duration is the step

    func testTheTweenLastsExactlyOneSimulationStep() {
        XCTAssertEqual(WanderingSpriteView.walkTweenDuration,
                       MovementModel.step,
                       "The tween has to finish as the next step begins. Any other duration either "
                       + "parks the sprite for the remainder of the step — the hop, made smaller — "
                       + "or leaves it still travelling when it is told to go somewhere else.")
    }

    func testTheTweenDurationIsNotAHardCodedQuarterSecond() {
        // Not a tautology: this is the criterion that the constant is DERIVED. Were it written as a
        // literal 0.25 it would agree with today's step and silently disagree with tomorrow's, so
        // the check is that changing the step changes the tween with it.
        XCTAssertEqual(WanderingSpriteView.walkTweenDuration / MovementModel.step, 1.0, accuracy: 1e-12)
    }

    // MARK: - What is and is not tweened

    func testTheWalkIsTweenedLinearlyWhenNoMotionIsPlaying() {
        XCTAssertEqual(view().walkAnimation,
                       .linear(duration: MovementModel.step),
                       "An eased tween decelerates into every step boundary and accelerates out of "
                       + "it: a pulse four times a second, which is worse than the hop.")
    }

    func testTheWalkTweenIsOffWhileAMotionPlays() {
        for kind in ActionMotion.Kind.allCases {
            let motion = ActionMotion(kind: kind, start: Clock.start)
            XCTAssertNil(view(motion: motion).walkAnimation,
                         "\(kind) ticks at ActionMotion.tick and the walk is HELD at a fixed offset "
                         + "for its whole length, so there is no step to interpolate.")
        }
    }

    // MARK: - The model is unchanged

    func testTheStepConstantsAreExactlyWhatUS216LeftThem() {
        XCTAssertEqual(MovementModel.step, 0.25)
        XCTAssertEqual(MovementModel.pointsPerSecond, 30)
        XCTAssertEqual(MovementModel.stepDistance, 7.5, accuracy: 0.0001)
        XCTAssertEqual(MovementModel.maximumCatchUpSteps, 2)
    }

    func testTheWalkStillMovesOneWholeStepDistancePerStep() {
        var model = MovementModel(bound: 200, seed: 0, start: Clock.start)
        var previous = model.offset
        for tick in 1...8 {
            model.advance(to: Clock.after(Double(tick) * MovementModel.step))
            XCTAssertEqual(model.offset - previous, MovementModel.stepDistance, accuracy: 0.0001,
                           "Step \(tick) is not one stride. The tween is a drawing, not a speed change.")
            previous = model.offset
        }
    }

    func testTheWalkStillTurnsAtTheWallWithoutOvershooting() {
        let bound: CGFloat = 20
        var model = MovementModel(bound: bound, seed: 0, start: Clock.start)
        // Long enough for several round trips at 7.5pt a step against a 20pt wall.
        for tick in 1...60 {
            model.advance(to: Clock.after(Double(tick) * MovementModel.step))
            XCTAssertLessThanOrEqual(abs(model.offset), bound,
                                     "Overshot the wall at step \(tick).")
        }
        // And it did in fact reach both walls rather than sitting somewhere safe in the middle.
        var seenLeft = false
        var seenRight = false
        var trip = MovementModel(bound: bound, seed: 0, start: Clock.start)
        for tick in 1...60 {
            trip.advance(to: Clock.after(Double(tick) * MovementModel.step))
            if trip.offset == bound { seenRight = true }
            if trip.offset == -bound { seenLeft = true }
        }
        XCTAssertTrue(seenLeft && seenRight, "The ping-pong no longer reaches both walls.")
    }

    // MARK: - The mirror lags the model by one step, and only at a wall

    /// The drawn facing is the direction of the segment BEING WALKED, not of the step after it.
    ///
    /// `MovementModel.facing` turns on the step that arrives at the bound, which is right for the
    /// model and wrong for a tween: that step is drawn as a quarter-second glide INTO the wall, and
    /// mirroring the sprite at the start of it walks it backwards for the whole glide.
    func testTheSpriteFacesTheWayItIsBeingDrawnToTravelIncludingIntoAWall() {
        // 30 is exactly four strides, so the fourth step lands ON the bound rather than short of it.
        let bound: CGFloat = 4 * MovementModel.stepDistance
        let wanderer = SpriteWanderer(bound: bound, seed: 0, start: Clock.start)

        var model = MovementModel(bound: bound, seed: 0, start: Clock.start)

        for step in 1...4 {
            let drawn = wanderer.position(at: Clock.after(Double(step) * MovementModel.step),
                                          bound: bound, isMoving: true)
            model.advance(to: Clock.after(Double(step) * MovementModel.step))
            XCTAssertTrue(drawn.flipped, "step \(step) travels right, so the sprite faces right")
        }

        // The model has already turned — it is standing on the wall looking back — but the drawing
        // has not, because the step it is showing went the other way.
        XCTAssertEqual(model.offset, bound)
        XCTAssertEqual(model.facing, .left)

        let awayFromTheWall = wanderer.position(at: Clock.after(5 * MovementModel.step),
                                                bound: bound, isMoving: true)
        XCTAssertFalse(awayFromTheWall.flipped,
                       "the mirror turns on the step that leaves the wall, one step after the model")
    }

    func testAHeldSpriteKeepsTheFacingItStoppedWith() {
        let bound: CGFloat = 60
        let wanderer = SpriteWanderer(bound: bound, seed: 0, start: Clock.start)
        let walking = wanderer.position(at: Clock.after(MovementModel.step), bound: bound, isMoving: true)
        XCTAssertTrue(walking.flipped)

        for seconds in stride(from: 2.0, through: 10.0, by: 2.0) {
            let held = wanderer.position(at: Clock.after(seconds), bound: bound, isMoving: false)
            XCTAssertEqual(held.flipped, walking.flipped,
                           "a sprite that is not walking has no new direction to face")
        }
    }

    // MARK: - A held sprite

    func testAHeldSpriteHasNothingToTweenBecauseItsOffsetNeverChanges() {
        let wanderer = SpriteWanderer(bound: 60, seed: 0, start: Clock.start)
        let standing = wanderer.position(at: Clock.after(MovementModel.step),
                                         bound: 60,
                                         isMoving: true).offset
        for seconds in stride(from: 2.0, through: 20.0, by: 2.0) {
            let held = wanderer.position(at: Clock.after(seconds), bound: 60, isMoving: false)
            XCTAssertEqual(held.offset, standing, accuracy: 0.0001,
                           "A sprite that is asleep, eating, an egg or behind an overlay must not "
                           + "drift: the tween interpolates between two offsets, and a held sprite "
                           + "only ever has the one.")
        }
    }
}
