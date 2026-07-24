import CoreGraphics
import Foundation

/// Where the Digimon is standing and which way it is looking.
///
/// A MODEL, not a view: it holds an offset in points from centre and is advanced by handing it a
/// `Date`, exactly as `HungerClock` ages hunger against one. Nothing here starts a timer — US-037's
/// `TimelineView` is what will call `advance(to:)`, and a test calls it with dates it chose.
///
/// The walk itself (US-216) is a plain ping-pong: one constant speed, straight to a wall, turn,
/// straight back. There is no randomness inside the step at all — the seed only picks which way the
/// Digimon sets off — so the path is fully determined by that parity, the bound and the number of
/// steps applied. It used to draw a fresh heading every 1–3s, which put mid-screen reversals and
/// standing pauses in the middle of the floor and read as darting about rather than pacing.
struct MovementModel {

    /// Which way the sprite is looking, i.e. whether US-037 flips it.
    ///
    /// Also the direction of travel: since US-216 removed resting there is nothing the Digimon can
    /// be doing except walking the way it faces, so one value says both.
    enum Facing {
        case left, right
    }

    /// The simulation step.
    ///
    /// Movement is integrated in whole steps of this length rather than over whatever happened to
    /// elapse since the last call, so a view redrawing at any cadence up to `maximumCatchUpSteps`
    /// per frame walks the same path: four advances of 0.25s land exactly where two of 0.5s do.
    /// Beyond that cap the surplus is dropped rather than paid out — see `advance(to:)`.
    static let step: TimeInterval = 0.25

    /// Points per second while walking. About one sprite-width every two seconds at the main
    /// screen's 4x scale, which reads as a stroll rather than a scuttle.
    static let pointsPerSecond: CGFloat = 30

    /// Distance covered by one simulation step.
    static var stepDistance: CGFloat { pointsPerSecond * CGFloat(step) }

    /// The most steps one `advance(to:)` may apply, however much time it is handed.
    ///
    /// The point is that the speed on screen is CONSTANT. A view that misses a redraw — coming back
    /// from the background, a scroll, an overlay dismissed — hands over a gap of seconds or hours,
    /// and paying it back in full makes the sprite sprint or teleport, which is the defect US-216
    /// is about. Two steps is 15pt at the main screen's scale: one ordinary stride plus a spare, so
    /// a dropped frame still looks like walking and anything longer than that is simply forgotten.
    /// Contrast `HungerClock`, which must catch up in full because unwatched hunger still
    /// happened — an unwatched WALK did not.
    static let maximumCatchUpSteps = 2

    /// The wall-clock length of `maximumCatchUpSteps`. Any gap longer than this is dropped.
    static var maximumCatchUp: TimeInterval { Double(maximumCatchUpSteps) * step }

    /// Points from centre; negative is left. Never outside `-bound...bound`.
    private(set) var offset: CGFloat = 0

    /// Which way the sprite is looking, and walking. Set from the seed at birth, and changed only
    /// by a wall.
    private(set) var facing: Facing

    /// The furthest from centre the sprite may stand, in points.
    ///
    /// The caller owns this because only the view knows the screen width and the sprite's own size.
    /// Shrinking it pulls a sprite that was already outside back in, so a resize can never strand
    /// the Digimon off screen.
    var bound: CGFloat {
        didSet { offset = min(max(offset, -bound), bound) }
    }

    /// The instant `offset` is correct for. Moves by APPLIED steps, so a part-worn step is carried
    /// rather than dropped — same reasoning as `HungerClock.advance`, and the reason a run of small
    /// advances agrees with a run of larger ones. The one exception is a gap past the catch-up cap,
    /// which is forgiven outright rather than banked.
    private var updatedAt: Date

    /// - Parameters:
    ///   - bound: the furthest from centre the sprite may stand, in points.
    ///   - seed: picks the opening direction, and nothing else — the walk after that is a fixed
    ///     ping-pong. Varied by the app so two Digimon on one screen do not pace in lockstep;
    ///     fixed by a test that wants a known path (even seed sets off right, odd left).
    ///   - start: the instant `offset` of 0 is correct for. Every later `advance(to:)` is measured
    ///     from here.
    init(bound: CGFloat, seed: UInt64, start: Date) {
        self.bound = bound
        self.facing = seed.isMultiple(of: 2) ? .right : .left
        self.updatedAt = start
    }

    /// Walks the Digimon forward to `now`.
    ///
    /// Idempotent within a step, so a view may call it on every redraw without the walk tracking
    /// how often it is redrawn.
    mutating func advance(to now: Date) {
        let elapsed = now.timeIntervalSince(updatedAt)
        // Backwards means the wall clock or the timezone moved, not that the Digimon un-walked.
        // Restamping keeps `updatedAt` out of the future, where it would freeze the sprite until
        // real time caught up.
        guard elapsed > 0 else {
            updatedAt = now
            return
        }

        let due = Int((elapsed / Self.step).rounded(.down))
        guard due >= 1 else { return }

        let steps = min(due, Self.maximumCatchUpSteps)
        for _ in 0..<steps { advanceOneStep() }

        if steps < due {
            // The surplus is DROPPED and the clock restamped to `now`, not carried. Carrying it
            // would pay the same debt back two steps per redraw until it cleared, which is the
            // sprint again, only in slow motion and lasting as long as the absence did.
            updatedAt = now
        } else {
            updatedAt = updatedAt.addingTimeInterval(Double(steps) * Self.step)
        }
    }

    /// Keeps the Digimon where it is and moves its clock to `now` without walking it.
    ///
    /// For the stretches US-037 suspends movement over — asleep, eating, sick, dead, or an overlay
    /// up. Without this the model would still be stamped at the moment movement stopped, and the
    /// first `advance(to:)` after a five-second eat loop would apply twenty steps at once: the
    /// sprite would teleport across the screen the instant it finished its meal. Holding says the
    /// same thing `maximumCatchUp` says about a long absence — a walk nobody took did not happen —
    /// but says it for pauses far too short to trip that limit.
    mutating func hold(at now: Date) {
        updatedAt = now
    }

    /// One stride, always in the direction the Digimon faces.
    ///
    /// RESTING: there isn't any. The Digimon walks every single step, wall to wall, forever. A
    /// standing pause was the other half of what made the old walk read as jittery — it stopped
    /// dead mid-floor and then set off again, which looks like hesitation rather than calm — and
    /// there is nothing on this screen that a pause would communicate. The pace reads as alive
    /// because it never stops; it reads as calm because `pointsPerSecond` is a stroll, about seven
    /// seconds for a full round trip on a 46mm watch.
    private mutating func advanceOneStep() {
        // No floor to walk on: a sprite wider than the screen leaves `bound` at 0, and without
        // this the wall checks below would flip `facing` on every step and the sprite would
        // shimmer left/right on the spot.
        guard bound > 0 else { return }

        switch facing {
        case .left: offset -= Self.stepDistance
        case .right: offset += Self.stepDistance
        }

        // A bound is a wall, not a clamp: walking into it turns the Digimon around rather than
        // leaving it leaning on the edge. Facing IS the heading, so flipping it here is what
        // carries the next step back inward.
        //
        // The comparison is `>=`, not `>`: a step that lands EXACTLY on the bound has still reached
        // the wall. With `>` such a step would not turn, and the sprite would spend a second step
        // pinned to the edge before overshooting and finally turning — a visible stutter, and one
        // that only appears when the bound happens to be a whole multiple of the step distance.
        if offset >= bound {
            offset = bound
            facing = .left
        } else if offset <= -bound {
            offset = -bound
            facing = .right
        }
    }
}
