import CoreGraphics
import Foundation

/// Where the Digimon is standing and which way it is looking.
///
/// A MODEL, not a view: it holds an offset in points from centre and is advanced by handing it a
/// `Date`, exactly as `HungerClock` ages hunger against one. Nothing here starts a timer — US-037's
/// `TimelineView` is what will call `advance(to:)`, and a test calls it with dates it chose. That is
/// also what makes the walk assertable: the whole path is a pure function of the seed and the
/// elapsed time, with no randomness the caller cannot reproduce.
struct MovementModel {

    /// Which way the sprite is looking, i.e. whether US-037 flips it.
    enum Facing {
        case left, right
    }

    /// What the Digimon is doing for the current stretch of steps.
    ///
    /// `resting` is a standing pause — the classic V-Pet walks in bursts rather than sliding wall
    /// to wall forever. A rest HOLDS the previous `facing` rather than picking one, so a resting
    /// sprite does not spin on the spot.
    private enum Heading {
        case left, right, resting
    }

    /// The simulation step.
    ///
    /// Movement is integrated in whole steps of this length rather than over whatever happened to
    /// elapse since the last call, so the path depends only on the seed and the TOTAL time:
    /// advancing ten times by 1s lands in exactly the same place as advancing once by 10s. Without
    /// that the walk would drift with the view's redraw cadence, and no test could pin a path that
    /// the running app would also produce.
    static let step: TimeInterval = 0.25

    /// Points per second while walking. About one sprite-width every two seconds at the main
    /// screen's 4x scale, which reads as a stroll rather than a scuttle.
    static let pointsPerSecond: CGFloat = 30

    /// How long an absence can be before the walk is abandoned rather than caught up.
    ///
    /// Simulating a backgrounded night one 0.25s step at a time is hundreds of thousands of
    /// iterations to decide where a 16px sprite stands. Past this the position is simply kept and
    /// the clock restamped: nobody watched the walk that was missed. Contrast `HungerClock`, which
    /// must catch up in full because unwatched hunger still happened — an unwatched WALK did not.
    static let maximumCatchUp: TimeInterval = 60

    /// Points from centre; negative is left. Never outside `-bound...bound`.
    private(set) var offset: CGFloat = 0

    /// Which way the sprite is looking. Starts facing right, and changes only when the Digimon
    /// actually walks the other way.
    private(set) var facing: Facing = .right

    /// The furthest from centre the sprite may stand, in points.
    ///
    /// The caller owns this because only the view knows the screen width and the sprite's own size.
    /// Shrinking it pulls a sprite that was already outside back in, so a resize can never strand
    /// the Digimon off screen.
    var bound: CGFloat {
        didSet { offset = min(max(offset, -bound), bound) }
    }

    private var heading: Heading = .resting
    private var generator: SeededGenerator
    /// Steps remaining before the next heading is drawn. Zero means "decide on the next step".
    private var stepsUntilDecision = 0
    /// The instant `offset` is correct for. Moves by APPLIED steps only, so a part-worn step is
    /// carried rather than dropped — same reasoning as `HungerClock.advance`, and the reason many
    /// small advances agree with one large one.
    private var updatedAt: Date

    /// - Parameters:
    ///   - bound: the furthest from centre the sprite may stand, in points.
    ///   - seed: the RNG seed behind every direction change. Fixed by a test so it can assert an
    ///     exact path; varied by the app so two sessions do not pace identically.
    ///   - start: the instant `offset` of 0 is correct for. Every later `advance(to:)` is measured
    ///     from here.
    init(bound: CGFloat, seed: UInt64, start: Date) {
        self.bound = bound
        self.generator = SeededGenerator(seed: seed)
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
        guard elapsed <= Self.maximumCatchUp else {
            updatedAt = now
            return
        }

        let steps = Int((elapsed / Self.step).rounded(.down))
        guard steps >= 1 else { return }

        for _ in 0..<steps { advanceOneStep() }
        updatedAt = updatedAt.addingTimeInterval(Double(steps) * Self.step)
    }

    private mutating func advanceOneStep() {
        if stepsUntilDecision <= 0 { decide() }
        stepsUntilDecision -= 1

        let distance = Self.pointsPerSecond * CGFloat(Self.step)
        switch heading {
        case .resting:
            return
        case .left:
            facing = .left
            offset -= distance
        case .right:
            facing = .right
            offset += distance
        }

        // A bound is a wall, not a clamp: walking into it turns the Digimon around rather than
        // leaving it leaning on the edge until the next decision. Flipping `heading` too — not just
        // `facing` — is what makes the next step carry it back inward.
        //
        // The comparison is `>=`, not `>`: a step that lands EXACTLY on the bound has still reached
        // the wall. With `>` such a step would not turn, and the sprite would spend a second step
        // pinned to the edge before overshooting and finally turning — a visible stutter, and one
        // that only appears when the bound happens to be a whole multiple of the step distance.
        if offset >= bound {
            offset = bound
            heading = .left
            facing = .left
        } else if offset <= -bound {
            offset = -bound
            heading = .right
            facing = .right
        }
    }

    private mutating func decide() {
        // 3 in 8 each way and 2 in 8 resting, so the Digimon is walking about three quarters of the
        // time — enough that the screen reads as alive, not so much that it never stands still.
        switch Int.random(in: 0..<8, using: &generator) {
        case 0..<3: heading = .left
        case 3..<6: heading = .right
        default: heading = .resting
        }
        // 4 to 12 steps, i.e. 1s to 3s in one heading. Short enough to look restless, long enough
        // that the sprite covers ground before changing its mind.
        stepsUntilDecision = Int.random(in: 4...12, using: &generator)
    }
}
