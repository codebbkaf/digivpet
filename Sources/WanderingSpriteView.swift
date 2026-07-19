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

    init(bound: CGFloat, seed: UInt64 = .random(in: .min ... .max), start: Date = .now) {
        self.model = MovementModel(bound: bound, seed: seed, start: start)
    }

    /// Where to draw the sprite at `date`, walking it there first unless movement is suspended.
    ///
    /// `bound` is re-applied on every call because it comes from the screen, and the screen is only
    /// known once the view has been laid out — the first call can genuinely carry a different bound
    /// from the one this was constructed with.
    func position(at date: Date, bound: CGFloat, isMoving: Bool) -> (offset: CGFloat, flipped: Bool) {
        model.bound = bound
        if isMoving {
            model.advance(to: date)
        } else {
            // Not simply skipping the advance: see `MovementModel.hold(at:)`. A skipped advance
            // leaves the clock behind, and the walk would then be caught up in one jump the moment
            // the Digimon woke, finished eating, or the battle came down.
            model.hold(at: date)
        }
        // The pack's art faces left, so a rightward heading is the one that needs mirroring.
        return (model.offset, model.facing == .right)
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
    /// False while the Digimon is asleep, eating, sick, dead, or behind an overlay. The sprite
    /// stays exactly where it stood and resumes from there — see `MainScreenModel.isWandering`.
    var isMoving: Bool = true

    @State private var wanderer: SpriteWanderer

    private var side: CGFloat { CGFloat(SpriteSheet.frameSize) * scale }

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
         isMoving: Bool = true) {
        self.stage = stage
        self.name = name
        self.animation = animation
        self.scale = scale
        self.isMoving = isMoving
        // Seeded at random, so two sessions do not pace identically. Tests seed `MovementModel`
        // directly; there is nothing here to pin.
        _wanderer = State(wrappedValue: SpriteWanderer(bound: 0))
    }

    var body: some View {
        // Ticking at exactly the model's step, so one tick applies one step. A faster schedule
        // would redraw between steps to show the same position, and a slower one would apply
        // several at once and stutter.
        TimelineView(.periodic(from: .now, by: MovementModel.step)) { context in
            let position = wanderer.position(at: context.date, bound: bound, isMoving: isMoving)

            DigimonSpriteView(
                stage: stage,
                name: name,
                animation: animation,
                scale: scale,
                offset: position.offset,
                flipped: position.flipped
            )
        }
        // The sprite is drawn with `.offset`, which does not reserve the ground it covers. Claiming
        // the full width here is what stops a Digimon standing at the left bound from being clipped
        // by a parent that sized itself to one sprite.
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WanderingSpriteView(stage: "Child", name: "Agumon")
}
