import CoreGraphics
import SwiftUI

/// Where the light button sits and how big it is (US-099).
///
/// Free-standing constants rather than statics on the view, for the same reason `SpriteScale` and
/// `SickBadgeLayout` are free-standing: a test should be able to check the arithmetic without
/// building a view graph to do it.
///
/// **Nothing here reserves height.** The button is an OVERLAY in the sprite's slot, not a row above
/// it — unlike the sick badge, which takes a band out of the height the sprite is sized against.
/// That is the whole reason the light costs the Digimon nothing on a 42mm screen, where the sprite
/// is already down at scale 2.
enum LightButtonLayout {
    /// The tappable circle. Smaller than the action row's 30pt because this is a switch on the wall
    /// rather than one of the five things you do to the Digimon, and every point of it sits over the
    /// sprite's slot — but not so small that a fingertip misses it.
    static let diameter: CGFloat = 24

    /// The symbol's point size, sized to leave a ring of the circle around it rather than filling it.
    static let iconSize: CGFloat = 12

    /// How far in from the leading edge of the sprite's slot the circle sits. Small: the Digimon
    /// walks the full width (US-037), so there is no inset that keeps them apart, and hugging the
    /// corner is what keeps the button out of the way of the walk for as long as possible.
    static let inset: CGFloat = 2

    /// How long the scrim takes to fade in or out. Long enough to read as a light being turned
    /// rather than the screen glitching, short enough not to sit between the tap and the result.
    static let dimDuration: TimeInterval = 0.25
}

/// Where the sprite's slot is on screen.
///
/// The light button is drawn in a layer ABOVE the scrim, which covers the whole screen — so it
/// cannot simply be an overlay inside the sprite's own row, or the scrim would be painted over it
/// and the user would be locked in the dark with nothing legible to tap. This preference is how the
/// button, drawn in that top layer, still lands in the corner of a row it is no longer inside.
///
/// An `Anchor` rather than a number in a named coordinate space, and that is not a style choice: a
/// layer holding a view that ignores the safe area does not necessarily start where the row it
/// covers starts, so a raw offset lands wherever that layer happens to have been stretched to. An
/// anchor is resolved by the `GeometryProxy` that draws it, in whatever space THAT proxy is in, so
/// the button lands on the slot however the layer around it was laid out. Measured the other way
/// first, and it put the lamp on top of the stats strip.
///
/// Last writer wins, which is exact here: only one view reports it.
struct SpriteSlotBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The room light, drawn over the main screen: the scrim, and the button that changes it (US-099).
///
/// One view for both halves because the ORDER is the feature. The scrim is painted first and the
/// button second, so the button is above it — a light switch you cannot find in the dark is not a
/// light switch. Splitting them would leave that ordering to whoever composed them next.
///
/// Applied inside the main screen and nowhere else, which is what keeps the scrim off the battle,
/// training, ceremony and memorial overlays: those are applied to the `NavigationStack` itself, so
/// they are painted after this and cover it. A moment that takes the whole screen is not happening
/// in the room.
struct LightLayer: View {
    let state: LightState
    /// The sprite's slot, from `SpriteSlotBoundsKey`. Nil before the first layout pass, which draws
    /// the button in the layer's own corner for that one pass rather than not at all.
    let spriteSlot: Anchor<CGRect>?
    let cycle: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Never removed, only faded: a scrim that comes and goes as a view cannot animate its
            // own arrival, and at `on` its opacity is zero, which draws nothing.
            //
            // `allowsHitTesting(false)` is what keeps AC6 true — Feed, Train, Clean, Battle and the
            // bell are all underneath this, and a scrim that swallowed taps would make turning the
            // light down a way to lock yourself out of the game.
            Color.black
                .opacity(state.dimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // The reader is what the anchor is resolved against, so the button is placed in the
            // reader's own space rather than in one the scrim above may have stretched.
            GeometryReader { proxy in
                let slot = spriteSlot.map { proxy[$0] } ?? .zero

                LightButton(state: state, action: cycle)
                    // `.offset` rather than padding: padding is laid out and would push the reader's
                    // content around, while an offset moves the drawing alone.
                    .offset(x: slot.minX + LightButtonLayout.inset, y: slot.minY)
            }
        }
        .animation(.easeInOut(duration: LightButtonLayout.dimDuration), value: state)
    }
}

/// The lamp button: what the light is doing, and the way to change it (US-099).
///
/// The symbol names the state the light is IN rather than the one a tap would move to — see
/// `LightState.symbolName` — so it reads as an indicator that happens to be tappable.
///
/// Drawn at full opacity with a lit glyph on its own dark disc, because this is the one control that
/// has to stay legible through a 0.85 scrim. Nothing about it is dimmed with the room.
struct LightButton: View {
    let state: LightState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbolName)
                .font(.system(size: LightButtonLayout.iconSize, weight: .semibold))
                // Yellow while the light is giving any light at all, white once it is out: a lamp
                // glyph still glowing yellow over a dark screen would say the opposite of what the
                // screen is showing. White rather than grey because grey on an 85% black scrim is
                // exactly the thing AC3 forbids.
                .foregroundStyle(state == .off ? Color.white : Color.yellow)
                // An exact frame, like `ActionButtonFace`: the circle must not change size with the
                // metrics of whichever of the three symbols is up.
                .frame(width: LightButtonLayout.diameter, height: LightButtonLayout.diameter)
                .background(Circle().fill(Color.white.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Light")
        .accessibilityValue(state.displayName)
        .accessibilityHint("Cycles the room light")
    }
}
