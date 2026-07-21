import CoreGraphics
import SwiftUI

/// How the adventure map is drawn behind the Digimon (US-115).
///
/// Free-standing constants rather than statics on the view, for the same reason `SpriteScale` and
/// `LightButtonLayout` are: a test should be able to check the numbers without building a view
/// graph to do it.
enum MapBackgroundLayout {
    /// How strongly the map shows through. **The Digimon is the subject and the map is scenery**, so
    /// this is the one number that decides whether a 16x16 sprite is still readable over 822x330 of
    /// painted grass — and the sprite is only 16 pixels wide, with no outline to separate it from
    /// whatever it happens to be standing in front of.
    ///
    /// 0.35 was chosen at the low end of the band on purpose: the brightest assets (`01_grassland`,
    /// `14_farmland`, `16_iceland`) are near-white in their sky band, which is exactly where a
    /// pale-bellied sprite walks.
    static let opacity: Double = 0.35

    /// The band `opacity` is allowed to live in, asserted by `MapBackgroundTests`. Below the floor
    /// the map is not worth drawing; above the ceiling the sprite starts to disappear into it. A
    /// later "let's make the maps pop" edit fails the suite rather than the eye test.
    static let minimumOpacity: Double = 0.30
    static let maximumOpacity: Double = 0.50

    /// Whether a map should be drawn at all, given what is selected. Nil — no map chosen yet, which
    /// is every save until US-119 ships the picker — draws NOTHING, so the screen is byte-for-byte
    /// what US-114 left rather than a black rectangle at 0.35.
    ///
    /// A named function for the same reason `LightLayer.scrimRect` is one: it is the part of the
    /// decision arithmetic can reach.
    static func shouldDraw(assetName: String?) -> Bool {
        guard let assetName else { return false }
        // An empty name is not a map: `Image("")` draws a missing-resource placeholder, which is a
        // worse answer than the nothing a fresh save gets.
        return !assetName.isEmpty
    }
}

/// The selected map, painted behind the Digimon's slot and nowhere else (US-115).
///
/// **This draws the image alone — the caller owns the frame, the clip and the placement.** It is
/// installed as a `backgroundPreferenceValue` off `SpriteSlotBoundsKey` in `ContentView`, sized to
/// the sprite slot that preference reports and clipped to it, which is what keeps the map out from
/// behind the stats strip, the name line, the energy bars and the action row. Nothing here is laid
/// out against those rows, so nothing here can push them around.
///
/// It is painted BELOW the sprite and below the scrim: the map is in the background layer, the
/// Digimon is the content, and `LightLayer` is the overlay. Turning the light down therefore dims
/// the map exactly as much as it dims the Digimon — the room got darker, and the room includes what
/// is on its walls.
///
/// `.scaledToFill()` rather than `.fit`: the assets are ~2.5:1 landscapes and the slot is closer to
/// 2:1, so a fit would letterbox the map with two black bands inside the lit room. Fill overflows
/// instead, and the caller's `.clipped()` cuts the overflow off.
///
/// No `.interpolation(.none)`, and that is deliberate rather than an oversight of the sprite rule:
/// these are 822x330 backgrounds being drawn DOWN into a ~190pt slot, and nearest-neighbour on a
/// downscale of that ratio drops rows and columns unevenly, which shimmers as the sprite walks past.
/// The rule exists to stop 16x16 art being smoothed UP; it does not apply here.
struct MapBackgroundView: View {
    /// The asset catalog name of the selected map — `01_grassland` ... `16_iceland`.
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .opacity(MapBackgroundLayout.opacity)
            // Scenery is not a control. The Feed, Train, Clean and Battle buttons are elsewhere, but
            // the sprite slot is a live area and a full-slot image that ate taps would be a bug
            // waiting for the first thing to become tappable inside the room.
            .allowsHitTesting(false)
            // The map is decoration; the Digimon and its stats are what a VoiceOver user is here for.
            .accessibilityHidden(true)
    }
}
