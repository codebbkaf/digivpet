import CoreGraphics
import Foundation
import XCTest

@testable import DigiVPet

/// US-095 — the scripted motion tracks behind the action poses.
///
/// No test waits real time: `ActionMotion.offset(for:elapsed:)` is a pure function of an elapsed
/// interval, so every instant below is a number this file chose. Nothing here touches a view.

final class ActionMotionTests: XCTestCase {

    /// The largest displacement a motion reaches, found by walking its whole duration finely.
    ///
    /// Sampled rather than evaluated at a hand-derived peak time, so a test does not have to
    /// re-implement the shape it is checking — if the peak moves, this still finds it, and only a
    /// changed AMPLITUDE fails the assertion.
    private func extremes(of kind: ActionMotion.Kind) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let duration = ActionMotion.duration(of: kind)
        let samples = 2000
        var minX: CGFloat = 0, maxX: CGFloat = 0, minY: CGFloat = 0, maxY: CGFloat = 0
        for sample in 0...samples {
            let point = ActionMotion.offset(for: kind, elapsed: duration * Double(sample) / Double(samples))
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return (minX, maxX, minY, maxY)
    }

    // MARK: - AC: every motion starts and ends where the sprite stood

    /// The property the whole type rests on. Checked for EVERY kind through `CaseIterable`, so a
    /// motion added later cannot quietly skip it.
    func testEveryMotionIsZeroAtItsStartAndAtItsEnd() {
        for kind in ActionMotion.Kind.allCases {
            let duration = ActionMotion.duration(of: kind)

            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: 0), .zero,
                           "\(kind) must begin where the sprite stands")
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: duration), .zero,
                           "\(kind) must end where the sprite stands")
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: duration + 5), .zero,
                           "\(kind) must stay home long after it is over")
        }
    }

    /// A motion left in place forever cannot strand the Digimon: the tail is flat, not merely zero
    /// at the one instant the duration names.
    func testAMotionLeftRunningStaysHome() {
        for kind in ActionMotion.Kind.allCases {
            let duration = ActionMotion.duration(of: kind)
            for elapsed in stride(from: duration, through: duration + 60, by: 0.37) {
                XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: elapsed), .zero,
                               "\(kind) moved again \(elapsed - duration)s after it finished")
            }
        }
    }

    /// Total, not merely pure: an elapsed time nobody expected is answered rather than trapped.
    /// A motion whose start is in the future has simply not begun.
    func testUnexpectedElapsedTimesAreAnswered() {
        for kind in ActionMotion.Kind.allCases {
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: -1), .zero, "\(kind) before its start")
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: -.infinity), .zero, "\(kind) at -infinity")
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: .infinity), .zero, "\(kind) at +infinity")
            XCTAssertEqual(ActionMotion.offset(for: kind, elapsed: .nan), .zero, "\(kind) at NaN")
        }
    }

    /// Something has to happen in between, or "always zero" would pass everything above.
    func testEveryMotionActuallyMovesTheSprite() {
        for kind in ActionMotion.Kind.allCases {
            let reach = extremes(of: kind)
            let furthest = max(abs(reach.minX), reach.maxX, abs(reach.minY), reach.maxY)
            XCTAssertGreaterThan(furthest, 0.5, "\(kind) never leaves the spot it started on")
        }
    }

    // MARK: - AC: peak amplitude and sign, per motion

    /// A hop goes UP, and up is negative y. Two arcs, each clearing the full height.
    func testAHopGoesUpByItsFullHeight() {
        let reach = extremes(of: .hop)

        XCTAssertEqual(reach.minY, -ActionMotion.Amplitude.hopHeight, accuracy: 0.001,
                       "the peak of a hop is its named height, upward")
        XCTAssertEqual(reach.maxY, 0, accuracy: 0.001, "a hop never sinks below the ground")
        XCTAssertEqual(reach.minX, 0, "a hop is vertical")
        XCTAssertEqual(reach.maxX, 0, "a hop is vertical")

        // Two arcs, so the sprite is back on the ground halfway through and up again after.
        let duration = ActionMotion.duration(of: .hop)
        XCTAssertEqual(ActionMotion.offset(for: .hop, elapsed: duration / 2).y, 0, accuracy: 0.001,
                       "the first hop lands before the second begins")
        XCTAssertLessThan(ActionMotion.offset(for: .hop, elapsed: duration * 0.75).y, -0.5,
                          "the second hop leaves the ground")
    }

    /// A chew dips DOWN — the opposite sign to a hop — by its named depth.
    func testAChewDipsDownward() {
        let reach = extremes(of: .chew)

        XCTAssertEqual(reach.maxY, ActionMotion.Amplitude.chewDip, accuracy: 0.001,
                       "the deepest point of a chew is its named dip, downward")
        XCTAssertEqual(reach.minY, 0, accuracy: 0.001, "a chew never rises above where it started")
        XCTAssertEqual(reach.minX, 0, "a chew is vertical")
        XCTAssertEqual(reach.maxX, 0, "a chew is vertical")
    }

    /// A lunge carries the sprite FORWARD, which for this pack's left-facing art is negative x.
    func testALungeReachesForwardAndComesHome() {
        let reach = extremes(of: .lunge)

        XCTAssertEqual(reach.minX, -ActionMotion.Amplitude.lungeReach, accuracy: 0.001,
                       "the far point of a lunge is its named reach, forward")
        XCTAssertEqual(reach.maxX, 0, accuracy: 0.001, "a lunge never backs away")
        XCTAssertEqual(reach.minY, 0, "a lunge is horizontal")
        XCTAssertEqual(reach.maxY, 0, "a lunge is horizontal")

        // Out fast, home slower: the far point falls in the first half of the motion.
        let duration = ActionMotion.duration(of: .lunge)
        let peak = (0...2000)
            .map { duration * Double($0) / 2000 }
            .min { ActionMotion.offset(for: .lunge, elapsed: $0).x < ActionMotion.offset(for: .lunge, elapsed: $1).x }!
        XCTAssertLessThan(peak, duration / 2, "the weight of a lunge is in the going, not the returning")
    }

    /// A recoil is knocked BACKWARD, i.e. the opposite sign to a lunge.
    func testARecoilIsKnockedBackward() {
        let reach = extremes(of: .recoil)

        XCTAssertEqual(reach.maxX, ActionMotion.Amplitude.recoilKick, accuracy: 0.001,
                       "the far point of a recoil is its named kick, backward")
        XCTAssertEqual(reach.minX, 0, accuracy: 0.001, "a recoil never advances")
        XCTAssertEqual(reach.minY, 0, "a recoil is horizontal")
        XCTAssertEqual(reach.maxY, 0, "a recoil is horizontal")

        XCTAssertGreaterThan(ActionMotion.offset(for: .recoil, elapsed: 0.05).x, 0,
                             "a recoil is sudden — it is already moving 50ms in")
    }

    /// A shake goes BOTH ways, which is what tells it apart from every other motion here.
    func testAShakeSwingsToBothSides() {
        let reach = extremes(of: .shake)

        XCTAssertEqual(reach.maxX, ActionMotion.Amplitude.shakeSwing, accuracy: 0.001,
                       "a shake swings its full width one way")
        XCTAssertEqual(reach.minX, -ActionMotion.Amplitude.shakeSwing, accuracy: 0.001,
                       "and its full width the other")
        XCTAssertEqual(reach.minY, 0, "a shake is horizontal")
        XCTAssertEqual(reach.maxY, 0, "a shake is horizontal")
    }

    // MARK: - AC: amplitudes are in sprite pixels

    /// Sprite pixels, not points: every amplitude is small enough to be a fraction of a 16px body.
    /// A constant that had drifted into points would be an order of magnitude larger than this.
    func testAmplitudesAreSpritePixels() {
        for kind in ActionMotion.Kind.allCases {
            let reach = extremes(of: kind)
            let furthest = max(abs(reach.minX), reach.maxX, abs(reach.minY), reach.maxY)
            XCTAssertLessThanOrEqual(furthest, CGFloat(SpriteSheet.frameSize) / 2,
                                     "\(kind) moves further than half a sprite — is it in points?")
        }
    }

    // MARK: - The date-based sampling a view uses

    /// The value form and the raw form agree: a motion sampled at a date is the same thing as its
    /// kind sampled at the interval since its start.
    ///
    /// To an ACCURACY, not bit-for-bit, and the difference is the point: `start + elapsed` handed
    /// back through `timeIntervalSince(start)` is not the same `Double` it went in as — a `Date` is
    /// an absolute time, so the addition rounds against a reference-date magnitude of 600,000 and
    /// the last bit or two of a fractional second do not survive. Which is exactly why the shapes
    /// are written against an elapsed INTERVAL and only the view converts a date into one.
    func testSamplingAtADateMatchesSamplingTheElapsedTime() {
        let start = Date(timeIntervalSinceReferenceDate: 600_000)
        let motion = ActionMotion(kind: .hop, start: start)

        for elapsed in stride(from: -0.5, through: ActionMotion.duration(of: .hop) + 0.5, by: 0.017) {
            let atDate = ActionMotion.offset(for: motion, at: start.addingTimeInterval(elapsed))
            let atElapsed = ActionMotion.offset(for: .hop, elapsed: elapsed)

            XCTAssertEqual(atDate.x, atElapsed.x, accuracy: 0.0001, "x at \(elapsed)s")
            XCTAssertEqual(atDate.y, atElapsed.y, accuracy: 0.0001, "y at \(elapsed)s")
        }
    }

    /// `isRunning` brackets the stretch over which the sprite is displaced.
    ///
    /// The END is asserted a tick past the duration rather than on it, for the same reason the test
    /// above needs an accuracy: `start.addingTimeInterval(duration)` measures back as a hair UNDER
    /// `duration`, so the exact end instant is not a thing a `Date` can express here. Nothing rests
    /// on it — `offset` at that hair is already home to within a millionth of a pixel, and the only
    /// cost of one extra `true` is one redraw that draws the sprite where it already is.
    func testAMotionRunsForRoughlyItsDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 600_000)
        for kind in ActionMotion.Kind.allCases {
            let motion = ActionMotion(kind: kind, start: start)
            let duration = ActionMotion.duration(of: kind)

            XCTAssertFalse(ActionMotion.isRunning(motion, at: start.addingTimeInterval(-0.1)), "\(kind) before")
            XCTAssertFalse(ActionMotion.isRunning(motion, at: start), "\(kind) at its start instant")
            XCTAssertTrue(ActionMotion.isRunning(motion, at: start.addingTimeInterval(duration / 2)), "\(kind) midway")
            XCTAssertFalse(ActionMotion.isRunning(motion, at: start.addingTimeInterval(duration + ActionMotion.tick)),
                           "\(kind) a tick past its end")
        }
    }

    /// The tick a view samples at is fine enough to draw the SHORTEST motion as a motion rather
    /// than a flicker. Pinned because the walk's own cadence is four times coarser and picking the
    /// wrong one is invisible in a build.
    func testTheSamplingTickResolvesTheShortestMotion() {
        let shortest = ActionMotion.Kind.allCases.map(ActionMotion.duration(of:)).min()!

        XCTAssertGreaterThanOrEqual(shortest / ActionMotion.tick, 8,
                                    "the shortest motion must get at least eight frames")
        XCTAssertLessThan(ActionMotion.tick, MovementModel.step,
                          "a motion needs a finer tick than the walk")
    }
}
