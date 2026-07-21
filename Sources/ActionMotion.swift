import CoreGraphics
import Foundation

/// A scripted nudge of the sprite while an action plays: the chew of a meal, the hop of a
/// celebration, the lunge of a landed blow.
///
/// A MOTION TRACK, not an animator. Nothing here starts a timer or holds state — the whole
/// displacement is `offset(for:elapsed:)`, a pure function of which motion and how long it has been
/// running, exactly as `MovementModel`'s path is a pure function of its seed and elapsed time. A
/// view samples it against a `TimelineView` date; a test samples it against dates it chose and
/// waits for nothing.
///
/// The value itself is only the two facts a view needs to sample the track — WHICH motion and WHEN
/// it began — so restarting a motion is assigning a new `start`, and a motion that has run out
/// keeps returning `.zero` until someone does.
struct ActionMotion: Hashable {

    /// The motions that exist. One case per action that moves the sprite; a new action adds a case
    /// here and a shape in `offset(for:elapsed:)`, and nothing else changes.
    enum Kind: Hashable, CaseIterable {
        /// A repeated downward dip: the Digimon leaning into its food.
        case chew
        /// Two arcs UP off the ground. Delight.
        case hop
        /// A thrust forward and back, fast out and slower home: a blow going in.
        case lunge
        /// A side-to-side wobble that ends where it started. A refusal, a "no".
        case shake
        /// Knocked BACKWARD and settling. The other side of a `lunge`.
        case recoil
    }

    var kind: Kind
    /// The instant the motion began. Elapsed time is measured from here.
    var start: Date

    init(kind: Kind, start: Date) {
        self.kind = kind
        self.start = start
    }

    // MARK: - Amplitudes

    /// Every amplitude below is in SPRITE PIXELS, not points, and every duration is in seconds.
    ///
    /// Pixels because the sprites are 16x16 drawn at a scale the caller picks: a hop written as "10
    /// points" would clear a fifth of the sprite at the main screen's 5x and half of it in the
    /// Dex's 2x. Written as "3 pixels" and multiplied by the view's scale at draw time, a hop is
    /// three pixels of its own body wherever it is drawn — the same motion, not the same distance.
    enum Amplitude {
        /// How far the head dips into the bowl.
        static let chewDip: CGFloat = 1
        /// How high a hop clears the ground.
        static let hopHeight: CGFloat = 3
        /// How far a lunge carries the sprite forward.
        static let lungeReach: CGFloat = 4
        /// How far a shake swings to EACH side.
        static let shakeSwing: CGFloat = 1.5
        /// How far a hit knocks the sprite back.
        static let recoilKick: CGFloat = 3
    }

    /// How long each motion runs before it is over and the sprite is home again.
    static func duration(of kind: Kind) -> TimeInterval {
        switch kind {
        case .chew: return 1.2
        case .hop: return 0.8
        case .lunge: return 0.45
        case .shake: return 0.6
        case .recoil: return 0.35
        }
    }

    /// How often a view should re-sample a motion.
    ///
    /// Far finer than `MovementModel.step`, and it has to be: the shortest motion here is 0.35s, so
    /// sampling it at the walk's quarter-second cadence would draw a recoil in one frame or none.
    /// The walk tolerates the faster tick because `MovementModel.advance(to:)` is idempotent within
    /// a step — extra samples redraw the same position rather than walking further.
    static let tick: TimeInterval = 1.0 / 30.0

    // MARK: - The track

    /// Where the sprite sits, in SPRITE PIXELS from where it was standing, `elapsed` seconds into
    /// `kind`. Positive x is right and positive y is DOWN, as everywhere else in SwiftUI.
    ///
    /// TOTAL: any `elapsed` at all is answerable, including negative ones (a motion whose start is
    /// in the future has not begun), non-finite ones, and any time past the end.
    ///
    /// ALWAYS `.zero` AT BOTH ENDS. This is the property the whole type rests on: a motion may
    /// carry the sprite anywhere in between, but at `elapsed == 0` and at every `elapsed` past its
    /// duration it puts the sprite back exactly where it stood. A view can therefore leave a
    /// finished motion in place forever and the Digimon is not stranded a few pixels off centre,
    /// and a motion that is interrupted at its end frame does not jump.
    ///
    /// FACING: x is expressed for a sprite drawn UNMIRRORED, which in this pack means facing LEFT —
    /// so a `lunge` is negative x and a `recoil` positive. A caller drawing a mirrored sprite (see
    /// `DigimonSpriteView.flipped`) negates x along with it.
    static func offset(for kind: Kind, elapsed: TimeInterval) -> CGPoint {
        let duration = duration(of: kind)
        guard elapsed.isFinite, elapsed > 0, elapsed < duration else { return .zero }
        let progress = elapsed / duration

        switch kind {
        case .chew:
            // Down, not up: the Digimon leans INTO the bowl. Three dips over the motion, which at
            // 1.2s is one per 0.4s — near enough the eat loop's own 0.5s frame that the bob reads
            // as belonging to the chewing rather than running against it.
            return CGPoint(x: 0, y: Amplitude.chewDip * arcs(3, progress))
        case .hop:
            // NEGATIVE y is up. Two arcs, because one hop reads as a stumble and three as a jitter.
            return CGPoint(x: 0, y: -Amplitude.hopHeight * arcs(2, progress))
        case .lunge:
            // Out fast and home slower — the weight of the blow is in the going, not the returning.
            return CGPoint(x: -Amplitude.lungeReach * thrust(progress, out: 0.35), y: 0)
        case .shake:
            // A true oscillation rather than the arcs above: a refusal has to go BOTH ways, and
            // `sin` of a whole number of cycles is zero at both ends on its own.
            return CGPoint(x: Amplitude.shakeSwing * sin(2 * .pi * 2 * progress), y: 0)
        case .recoil:
            // Backward, i.e. the opposite sign to `lunge`, and snapped back almost at once: being
            // hit is sudden in a way that swinging is not.
            return CGPoint(x: Amplitude.recoilKick * thrust(progress, out: 0.25), y: 0)
        }
    }

    /// The displacement of the motion at `date`, in sprite pixels.
    static func offset(for motion: ActionMotion, at date: Date) -> CGPoint {
        offset(for: motion.kind, elapsed: date.timeIntervalSince(motion.start))
    }

    /// Whether the motion still has anywhere to put the sprite at `date`.
    ///
    /// Not consulted by `offset` — a finished motion already answers `.zero`. It is here for a
    /// caller that wants to stop scheduling redraws once the motion is spent.
    static func isRunning(_ motion: ActionMotion, at date: Date) -> Bool {
        let elapsed = date.timeIntervalSince(motion.start)
        return elapsed.isFinite && elapsed > 0 && elapsed < duration(of: motion.kind)
    }

    // MARK: - Shapes

    /// `count` humps between 0 and 1, each rising from 0 to exactly 1 and back.
    ///
    /// The absolute value is what keeps every hump on the SAME side: a plain sine of several cycles
    /// would send the second hop as far below the ground as the first went above it.
    private static func arcs(_ count: Int, _ progress: Double) -> CGFloat {
        CGFloat(abs(sin(.pi * Double(count) * progress)))
    }

    /// One asymmetric out-and-back: 0 up to exactly 1 at `out`, then back down to 0 at 1.
    ///
    /// Both halves are quarter-sines rather than straight lines, so the sprite eases into the far
    /// point instead of arriving at full speed and stopping dead.
    private static func thrust(_ progress: Double, out: Double) -> CGFloat {
        if progress < out {
            return CGFloat(sin(.pi / 2 * (progress / out)))
        }
        return CGFloat(cos(.pi / 2 * ((progress - out) / (1 - out))))
    }
}
