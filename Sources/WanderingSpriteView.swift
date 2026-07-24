import CoreGraphics
import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// Holds the walk between redraws.
///
/// A reference type in `@State` rather than an `ObservableObject`, and deliberately publishing
/// NOTHING: the `TimelineView` above it is already the thing scheduling redraws, so a second
/// change-notification path would only add "Publishing changes from within view updates" warnings
/// for a repaint that was going to happen anyway. The view asks it where the Digimon is; it
/// answers; nobody is observing it.
///
/// Safe to drive from `body` because `MovementModel.advance(to:)` is idempotent within a step —
/// asking twice for the same date returns the same position, so a body SwiftUI chooses to
/// re-evaluate does not walk the Digimon twice as far.
@MainActor
final class SpriteWanderer {
    private var model: MovementModel

    /// Which way the sprite is DRAWN facing, which is the direction of the segment currently being
    /// walked rather than the direction of the next step.
    ///
    /// The two differ for exactly one step, and only at a wall. `MovementModel.facing` turns on the
    /// step that ARRIVES at the bound — correct for the model, since that is where the Digimon goes
    /// next — but US-220 draws that step as a quarter-second glide INTO the wall, and a sprite
    /// mirrored at the start of it moonwalks the last few points backwards. Lagging the mirror by
    /// one step puts the turn where the eye expects it: at the wall, as the sprite arrives.
    private var drawnFacing: MovementModel.Facing

    init(bound: CGFloat, seed: UInt64 = .random(in: .min ... .max), start: Date = .now) {
        self.model = MovementModel(bound: bound, seed: seed, start: start)
        self.drawnFacing = model.facing
    }

    /// Where to draw the sprite at `date`, walking it there first unless movement is suspended.
    ///
    /// `bound` is re-applied on every call because it comes from the screen, and the screen is only
    /// known once the view has been laid out — the first call can genuinely carry a different bound
    /// from the one this was constructed with.
    ///
    /// - Parameter holdsAtCentre: for the suspension that is a different sprite rather than a pause
    ///   in this one's day — an unhatched Digitama (US-217). Asserted on every call rather than on
    ///   the transition into it, so there is no frame in which the egg is drawn at the position the
    ///   Digimon before it died on.
    func position(at date: Date,
                  bound: CGFloat,
                  isMoving: Bool,
                  holdsAtCentre: Bool = false) -> (offset: CGFloat, flipped: Bool) {
        model.bound = bound
        if isMoving {
            let before = model.offset
            model.advance(to: date)
            // Read off the DISTANCE just covered rather than off `model.facing`, for two reasons.
            // It is the direction actually being drawn, which is the point; and it updates only
            // when a step was really applied, so the repeat calls a redraw makes within one step —
            // and there is one every time the tween's own state change re-runs this closure —
            // leave it alone instead of flipping the sprite mid-glide.
            if model.offset != before { drawnFacing = model.offset > before ? .right : .left }
        } else {
            // Not simply skipping the advance: see `MovementModel.hold(at:)`. A skipped advance
            // leaves the clock behind, and the walk would then be caught up in one jump the moment
            // the Digimon woke, finished eating, or the battle came down. That is exactly why an
            // egg holds rather than opting out: the walk it resumes with when it hatches is one
            // step long, not the whole incubation paid back at once.
            if holdsAtCentre { model.recentre() }
            model.hold(at: date)
        }
        // The pack's art faces left, so a rightward heading is the one that needs mirroring.
        return (model.offset, drawnFacing == .right)
    }
}

/// The main screen's Digimon: `DigimonSpriteView` with US-036's walk driving it.
///
/// Split out of `ContentView` so the walk's plumbing — the schedule, the box, the bound — sits in
/// one place, and so `DigimonSpriteView` itself stays a thing that draws a sprite where it is told
/// rather than a thing that decides where the sprite goes.
struct WanderingSpriteView: View {
    let stage: String
    let name: String
    var animation: SpriteAnimation = .idle
    var scale: CGFloat = 5
    /// False while the Digimon is asleep, eating, sick, dead, still an egg, or behind an overlay.
    /// The sprite stays exactly where it stood and resumes from there — see
    /// `MainScreenModel.isWandering`. The egg is the one case that also goes back to centre first,
    /// because it is a new sprite rather than a pause in this one's day.
    var isMoving: Bool = true
    /// A scripted nudge running on top of wherever the walk left the sprite, or nil for none.
    ///
    /// ADDED to the walk position rather than replacing it, and it is safe to add precisely because
    /// the two cannot both be live: an action that plays a motion also passes `isMoving: false`, so
    /// the walk is held at a fixed offset for the motion's whole length and the motion is the only
    /// thing moving. If they ever did overlap the sprite would still be somewhere sane — a walk
    /// with a bob on it — rather than fighting over the position.
    var motion: ActionMotion?

    /// How long the drawn offset takes to slide from one simulation step's position to the next.
    ///
    /// EQUAL to `MovementModel.step` by construction rather than by coincidence, which is why it is
    /// written as that constant and not as 0.25: each tween has to finish exactly as the next step
    /// begins. Shorter and the sprite arrives early and stands still for the remainder — the hop
    /// US-220 is about, merely smaller. Longer and it is still in transit when it is told to go
    /// somewhere else, so it never covers a full stride and the walk quietly slows down.
    static let walkTweenDuration: TimeInterval = MovementModel.step

    /// The tween applied to the walk offset, or nil for the stretches that must not be tweened.
    ///
    /// LINEAR, never eased. `.easeInOut` decelerates into every step boundary and accelerates out
    /// of it, which puts a visible pulse on the walk four times a second — the exact opposite of the
    /// constant pace US-216 established, and more obviously wrong than the hopping it replaces.
    ///
    /// Off while a motion is playing: the walk is held at a fixed offset for a motion's whole length
    /// (see `motion`), so there is no step to tween, and a live animation would only smear the
    /// mirroring that `ActionMotion` applies to a lunge as the sprite turns.
    /// Not private so a test can read it: "the tween is off while a motion plays" is a rule about
    /// this value and nothing else, and there is no way to see it from a rendered view.
    var walkAnimation: Animation? {
        motion == nil ? .linear(duration: Self.walkTweenDuration) : nil
    }

    /// The motion's displacement at `date`, in POINTS: `ActionMotion` speaks in sprite pixels, and
    /// this is the one place that turns them into the screen distance this `scale` makes them.
    private func motionOffset(at date: Date) -> CGPoint {
        guard let motion else { return .zero }
        let pixels = ActionMotion.offset(for: motion, at: date)
        return CGPoint(x: pixels.x * scale, y: pixels.y * scale)
    }

    @State private var wanderer: SpriteWanderer

    /// Where the sprite is DRAWN, as against where the model says it stands.
    ///
    /// The model's offset is a staircase — one whole `stepDistance` every `MovementModel.step` — and
    /// this is the value that slides between two of its stairs. It is `@State` rather than simply
    /// the model's offset because a tween needs a change to animate, and the animation has to be
    /// attached to that change from OUTSIDE the timeline's own update (see `body`).
    @State private var drawnOffset: CGFloat = 0

    private var side: CGFloat { CGFloat(SpriteSheet.frameSize) * scale }

    /// Whether what is being drawn is an unhatched Digitama, which sits at centre rather than
    /// wherever the walk last left the sprite (US-217).
    ///
    /// Read off `stage` rather than passed in as a second flag: `stage` IS `Stage.rawValue` — the
    /// name of the sprite subfolder the art comes from — so the egg is already named here, and a
    /// separate parameter would be the same fact travelling twice.
    private var isEgg: Bool { stage == Stage.digitama.rawValue }

    /// How far from centre the sprite may walk.
    ///
    /// Taken from the device rather than a `GeometryReader`, because the sprite is drawn with
    /// `.offset` and so has no laid-out width of its own to measure — its frame is one sprite wide
    /// wherever it happens to be standing. `screenBounds` is what actually differs between a 42mm
    /// and a 46mm watch, which is the only thing this needs to be right about.
    private var bound: CGFloat {
        #if canImport(WatchKit)
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        #else
        let screenWidth: CGFloat = 176
        #endif
        // Half the leftover width, less a margin, so the sprite turns a little short of the bezel
        // instead of appearing to walk into it. Floored at zero for the case where the sprite is
        // wider than the screen, where there is simply nowhere to walk.
        return max((screenWidth - side) / 2 - 4, 0)
    }

    init(stage: String,
         name: String,
         animation: SpriteAnimation = .idle,
         scale: CGFloat = 5,
         isMoving: Bool = true,
         motion: ActionMotion? = nil) {
        self.stage = stage
        self.name = name
        self.animation = animation
        self.scale = scale
        self.isMoving = isMoving
        self.motion = motion
        // Seeded at random, so two sessions do not pace identically. Tests seed `MovementModel`
        // directly; there is nothing here to pin.
        _wanderer = State(wrappedValue: SpriteWanderer(bound: 0))
    }

    var body: some View {
        // Ticking at exactly the model's step, so one tick applies one step. A faster schedule
        // would redraw between steps to show the same position, and a slower one would apply
        // several at once and stutter. A motion is the one thing worth the extra redraws: its
        // shortest track is shorter than two walk steps, so at the walk's cadence it would be
        // drawn once or not at all.
        TimelineView(.periodic(from: .now, by: motion == nil ? MovementModel.step : ActionMotion.tick)) { context in
            let position = wanderer.position(at: context.date,
                                             bound: bound,
                                             isMoving: isMoving,
                                             holdsAtCentre: isEgg)
            let nudge = motionOffset(at: context.date)

            DigimonSpriteView(
                stage: stage,
                name: name,
                animation: animation,
                scale: scale,
                // The motion's x is written for the way the art faces, which is LEFT; a mirrored
                // sprite lunges the other way, so the nudge is mirrored with it. Without this a
                // Digimon walking right would lunge over its own shoulder.
                //
                // The WALK is no longer part of this offset — it is the `.offset` below, so that
                // the tween can be scoped to it alone. The motion stays here, where it shares one
                // `.offset` with its own vertical component (see `DigimonSpriteView.verticalOffset`).
                offset: position.flipped ? -nudge.x : nudge.x,
                verticalOffset: nudge.y,
                flipped: position.flipped
            )
            // The step the model has just taken is published to the view OUTSIDE this closure and
            // tweened there. Nothing inside a `TimelineView`'s body can be animated: its updates
            // carry a transaction that disables animation — otherwise every tick of every timeline
            // would animate — and that suppression reaches the whole subtree the closure builds.
            // MEASURED, not assumed: with the `.offset` in here, both `.animation(_:value:)` and a
            // `withAnimation` from this same `onChange` left the sprite on an exact 15px (one-step)
            // grid in every frame of a 30fps screen recording.
            .onChange(of: position.offset, initial: true) { _, target in
                drawnOffset = target
            }
        }
        // The walk, applied to the timeline rather than inside it: this is the tween, and it draws
        // the ground between the model's stairs. The model itself is untouched and still steps.
        //
        // SCOPED TO THE OFFSET by the two-pass split above, and NOT by a `.transaction` clear on
        // the timeline: a `.transaction { $0.animation = nil }` between these two modifiers and the
        // `TimelineView` puts the hop straight back (measured — every frame of a 30fps recording
        // back on the 15px grid), because it suppresses the `.offset` beside it as well as the
        // sprite below it. The split is what makes the scoping structural instead: the mirror and
        // the frame index only ever change on a timeline tick, which is pass one and carries no
        // animation, and `drawnOffset` is the only thing that changes in pass two, which is the
        // pass this animates.
        .offset(x: drawnOffset)
        .animation(walkAnimation, value: drawnOffset)
        // The sprite is drawn with `.offset`, which does not reserve the ground it covers. Claiming
        // the full width here is what stops a Digimon standing at the left bound from being clipped
        // by a parent that sized itself to one sprite.
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WanderingSpriteView(stage: "Child", name: "Agumon")
}
