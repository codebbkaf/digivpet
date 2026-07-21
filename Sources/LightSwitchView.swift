import CoreGraphics
import SwiftUI

/// How the light button is drawn and how fast the room dims (US-099, US-114).
///
/// Free-standing constants rather than statics on the view, for the same reason `SpriteScale` and
/// `SickBadgeLayout` are free-standing: a test should be able to check the arithmetic without
/// building a view graph to do it.
///
/// **Nothing here reserves height, and since US-114 nothing here covers the Digimon either.** The
/// button used to be an overlay in the sprite's slot, hugging its top-leading corner; it is now a
/// toolbar item beside the Dex book, so the room it lights is no longer a room it stands in. The
/// `inset` that placed it in that corner went with it.
enum LightButtonLayout {
    /// The tappable square the symbol is centred in. Smaller than the action row's 30pt because this
    /// is a switch on the wall rather than one of the five things you do to the Digimon.
    ///
    /// An exact size, not a hug: the three symbols have different metrics, and a toolbar button that
    /// resized as the light cycled would shift under the finger that was tapping it.
    static let diameter: CGFloat = 24

    /// The symbol's point size, sized to sit inside `diameter` with air around it.
    static let iconSize: CGFloat = 12

    /// How long the scrim takes to fade in or out. Long enough to read as a light being turned
    /// rather than the screen glitching, short enough not to sit between the tap and the result.
    static let dimDuration: TimeInterval = 0.25
}

/// Where the sprite's slot is on screen — which is exactly how far the scrim reaches (US-112).
///
/// The scrim darkens the Digimon's room and nothing else, so it has to be drawn in a layer that can
/// still be told where that room is after leaving it. This preference carries that rect.
///
/// It used to have a second job: placing the lamp in the room's top-leading corner. US-114 moved the
/// button to the toolbar, so this now says one thing only.
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

/// The scrim that dims the Digimon's room (US-099, narrowed to the room in US-112).
///
/// **It covers the sprite's slot, not the screen.** Turning the light down darkens the room the
/// Digimon is in; the action row, the energy bars, the name line and the toolbar are chrome around
/// that room and stay at full brightness, because a night light is not a reason to lose the buttons.
///
/// Since US-114 this draws the scrim and nothing else. The light button used to be painted here, a
/// layer above the scrim, because a switch you cannot find in the dark is not a switch — the toolbar
/// solves that better, by being somewhere the scrim was never going to reach.
///
/// Applied inside the main screen and nowhere else, which is what keeps the scrim off the battle,
/// training, ceremony and memorial overlays: those are applied to the `NavigationStack` itself, so
/// they are painted after this and cover it. A moment that takes the whole screen is not happening
/// in the room.
struct LightLayer: View {
    let state: LightState
    /// The sprite's slot, from `SpriteSlotBoundsKey`. Nil before the first layout pass, which draws
    /// no scrim at all for that one pass — see `scrimRect`.
    let spriteSlot: Anchor<CGRect>?

    /// How far the scrim reaches, given the sprite slot resolved against the drawing proxy: the
    /// slot itself, and nil for "paint nothing at all" (US-112).
    ///
    /// A named function rather than an expression buried in `body` because it is the one part of
    /// the layering arithmetic can reach — a test can ask what the scrim covers without building a
    /// view graph to ask it. The nil is the load-bearing half: a slot that has not been measured
    /// yet must fall through to nothing, never to the layer's own bounds, or the single pass before
    /// the first layout would black out the whole screen.
    static func scrimRect(spriteSlot: CGRect?) -> CGRect? { spriteSlot }

    var body: some View {
        // The reader is what the anchor is resolved against, so the scrim is placed in the reader's
        // own space rather than in one a full-screen child stretched.
        GeometryReader { proxy in
            if let scrim = Self.scrimRect(spriteSlot: spriteSlot.map { proxy[$0] }) {
                // Never removed, only faded: a scrim that comes and goes as a view cannot animate
                // its own arrival, and at `on` its opacity is zero, which draws nothing. The `if`
                // is not that switch — it is the unmeasured slot, which is one layout pass long and
                // has no rect to draw in yet.
                //
                // `allowsHitTesting(false)` is what keeps AC6 true — Feed, Train, Clean, Battle and
                // the bell are all underneath this, and a scrim that swallowed taps would make
                // turning the light down a way to lock yourself out of the game.
                Color.black
                    .opacity(state.dimOpacity)
                    .frame(width: scrim.width, height: scrim.height)
                    // `.offset` rather than padding: padding is laid out and would push the
                    // reader's content around, while an offset moves the drawing alone.
                    .offset(x: scrim.minX, y: scrim.minY)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: LightButtonLayout.dimDuration), value: state)
    }
}

/// The lamp button: what the light is doing, and the way to change it (US-099, moved in US-114).
///
/// The symbol names the state the light is IN rather than the one a tap would move to — see
/// `LightState.symbolName` — so it reads as an indicator that happens to be tappable.
///
/// It lives in the toolbar's leading slot, opposite the Dex book, and is never dimmed: the scrim
/// covers the sprite's slot alone, and the toolbar is chrome outside that room. That is the whole
/// point of the move — the lamp used to hang in the corner of the room it lit, where the Digimon
/// walked underneath it.
///
/// No disc behind the glyph, unlike the version that sat over the scrim. Nothing dark is painted
/// under it any more, so the disc that kept it legible through 0.85 black is now just a smudge the
/// Dex book does not have.
struct LightButton: View {
    let state: LightState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbolName)
                .font(.system(size: LightButtonLayout.iconSize, weight: .semibold))
                // Yellow while the light is giving any light at all, white once it is out: a lamp
                // glyph still glowing yellow over a darkened room would say the opposite of what
                // the screen is showing.
                .foregroundStyle(state == .off ? Color.white : Color.yellow)
                // An exact frame, like `ActionButtonFace`: the tap target must not change size with
                // the metrics of whichever of the three symbols is up.
                .frame(width: LightButtonLayout.diameter, height: LightButtonLayout.diameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Light")
        .accessibilityValue(state.displayName)
        .accessibilityHint("Cycles the room light")
    }
}
