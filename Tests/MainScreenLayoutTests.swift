import CoreGraphics
import XCTest
@testable import DigiVPet

/// US-039: the main screen fits without scrolling.
///
/// What can be asserted here is the sprite's sizing rule. That the sprite and all four buttons are
/// on screen together at 42mm and 46mm is a Simulator screenshot, recorded in progress.txt.
final class MainScreenLayoutTests: XCTestCase {
    /// Whole scales only. A fractional one resamples 16x16 art onto a grid it does not line up with,
    /// which `.interpolation(.none)` renders as uneven pixel widths rather than hiding as blur.
    func testTheScaleIsAlwaysAWholeNumber() {
        for height in stride(from: 30.0, through: 200.0, by: 0.5) {
            let scale = SpriteScale.fitting(CGFloat(height))
            XCTAssertEqual(scale, scale.rounded(), "height \(height) gave a fractional scale")
        }
    }

    /// The sprite must never be taller than the room it was offered — that is the whole point of
    /// measuring, and an overflow here is what the ScrollView used to hide.
    func testTheSpriteFitsTheHeightItIsOffered() {
        for height in stride(from: SpriteScale.minimum * 16, through: 200.0, by: 1.0) {
            let side = SpriteScale.fitting(CGFloat(height)) * CGFloat(SpriteSheet.frameSize)
            XCTAssertLessThanOrEqual(side, CGFloat(height), "overflowed at height \(height)")
        }
    }

    /// Given room, the sprite is drawn at the size it was before anything competed with it.
    func testAmpleHeightGivesTheFullScale() {
        XCTAssertEqual(SpriteScale.fitting(400), SpriteScale.maximum)
        XCTAssertEqual(SpriteScale.fitting(SpriteScale.maximum * 16), SpriteScale.maximum)
    }

    /// Below the floor the sprite stops shrinking and overflows visibly instead — a smudge that fits
    /// would look fine and be wrong.
    ///
    /// The heights are under `minimum * 16` rather than the old 0 and 20: US-221 drops the floor to 1
    /// and 20pt is now above it, so asserting on 20 would pass while testing nothing.
    func testTheScaleIsFlooredRatherThanShrinkingToNothing() {
        XCTAssertEqual(SpriteScale.fitting(0), SpriteScale.minimum)
        XCTAssertEqual(SpriteScale.fitting(SpriteScale.minimum * 16 - 0.1), SpriteScale.minimum)
        XCTAssertEqual(SpriteScale.fitting(-40), SpriteScale.minimum)
    }

    /// US-099 AC2: the light button costs the screen nothing.
    ///
    /// It was never a row of its own — unlike the sick badge, which takes
    /// `SickBadgeLayout.reservedHeight` out of the height the sprite is sized against — so the slot
    /// `SpriteScale.fitting` is asked about is the same slot it was asked about before the light
    /// existed, and the action row is still the five 30pt circles it was.
    ///
    /// It was an overlay in that slot until US-114 moved it to the toolbar, which is why this still
    /// holds: it cost the slot no height as an overlay, and costs it none from outside.
    ///
    /// The numbers are pinned rather than the layout: what the light MUST NOT do is move the row's
    /// diameter or push the 42mm slot out of the band it was in. That screen was measured drawing
    /// the sprite at 6 screenshot pixels per sprite pixel — scale 3 at @2x — both before and after
    /// this story, on a fresh save, and 78px wide in both (see progress.txt).
    func testTheLightButtonChangesNeitherTheActionRowNorTheSpriteScale() {
        XCTAssertEqual(ActionButtonFace.diameter, 30)

        for slot in stride(from: 3 * 16.0, to: 4 * 16.0, by: 0.5) {
            XCTAssertEqual(SpriteScale.fitting(CGFloat(slot)), 3, "slot \(slot)")
        }

        // The same screen drops a whole step once the action row's battle-allowance caption takes a
        // line out of the slot — measured at scale 2 on a save showing "4 left today". Both bands
        // matter, because which of them the screen is in depends on the save rather than on the
        // layout, and the light must be free in either.
        XCTAssertEqual(SpriteScale.fitting(3 * 16 - 0.1), 2)
    }

    /// The two main-screen font sizes stay small enough not to shrink the sprite.
    ///
    /// Until US-194 the slot sat right on a scale boundary — 49.5pt on 41mm, 64.0pt on 46mm, 0.5pt
    /// and 0.0pt of slack — so growing either font by a point silently cost the Digimon a scale step.
    /// US-194 grows the action row's bottom inset from 4 to 12, and because that inset comes straight
    /// out of the one flexible row, the slot lost 8pt on each screen. Six stories then DELETED rows
    /// (the currency row, the map strip, both reading bars) and handed all of it back, so by US-219
    /// the rows were 63.5 / 66.5 / 76.0pt on 41 / 42 / 46mm — half again what was pinned here.
    /// US-219 trims the play area to 80% of the row and the bands were RE-MEASURED directly off the
    /// map (see below); they sit mid-band rather than on an edge, so the font ceiling is looser than
    /// it was, but it stays pinned as a conservative guard.
    ///
    /// This cannot assert the layout — that is a screenshot. What it CAN hold is the two font sizes,
    /// so growing one fails here rather than silently costing the Digimon a scale step.
    func testTheMainScreenFontsStaySmallEnoughToKeepTheSpriteScale() {
        XCTAssertLessThanOrEqual(MainScreenTypography.nameFontSize,
                                 MainScreenTypography.maximumSafeFontSize)
        XCTAssertLessThanOrEqual(MainScreenTypography.statValueFontSize,
                                 MainScreenTypography.maximumSafeFontSize)

        // RE-MEASURED on the Simulator for US-219, by diffing a `-mapDemo=01_grassland` screenshot
        // against a `-mapDemo=none` one: the map is painted off `SpriteSlotBoundsKey`, so the band
        // that changes IS the play area, measured directly rather than inferred from a sprite.
        //
        // **The old 41.5 / 56.0 pinned here were stale, and by a lot.** They were US-194 arithmetic
        // (49.5 - 8, 64.0 - 8), and US-196, US-199, US-208, US-210, US-211 and US-213 have since
        // deleted the currency row, the map strip and both reading bars — every point of which went
        // straight back to the one flexible row without anyone re-measuring. The real FLEXIBLE ROWS
        // before this story were 63.5pt (41mm), 66.5pt (42mm) and 76.0pt (46mm).
        //
        // The bands this story draws inside them, floor(row * 0.8), measured to the point:
        //   41mm  63.5 -> 50.0   42mm  66.5 -> 53.0   46mm  76.0 -> 60.0
        //
        // These are the scale the BAND alone allows. Since US-221 the call site hands `fitting` only
        // `SpriteScale.sizeFraction` of that band, so what is actually drawn is one step smaller on
        // all three — see `testTheSpriteIsDrawnAtAFractionOfTheBandItStandsIn`. Kept as the band's
        // own capacity, because that is what a font point eats into.
        XCTAssertEqual(SpriteScale.fitting(50.0), 3, "41mm band measured for US-219")
        XCTAssertEqual(SpriteScale.fitting(53.0), 3, "42mm band measured for US-219")
        XCTAssertEqual(SpriteScale.fitting(60.0), 3, "46mm band measured for US-219")

        // What the trim cost, confirmed by the sprite's ink width in the same screenshots (13 sprite
        // pixels of Agumon, so 78px at @2x is scale 3 and 104px is scale 4): 42mm and 46mm drop one
        // step from 4 to 3, and 41mm keeps the 3 it already had. The floor never binds — the smallest
        // band is 50pt against a 48pt sprite — so `SpriteScale.minimum` is untouched.
        XCTAssertEqual(SpriteScale.fitting(63.5), 3, "41mm row, for comparison")
        XCTAssertEqual(SpriteScale.fitting(66.5), 4, "42mm row, for comparison")
        XCTAssertEqual(SpriteScale.fitting(76.0), 4, "46mm row, for comparison")

        // None of the three bands is on a scale edge: scale 3 holds from 48 up to just under 64.
        XCTAssertEqual(SpriteScale.fitting(48.0), 3)
        XCTAssertEqual(SpriteScale.fitting(47.9), 2)
        XCTAssertEqual(SpriteScale.fitting(64.0), 4)
    }

    /// US-219: the play area is 80% of the flexible row, and the missing fifth is left empty.
    ///
    /// The fraction is pinned rather than the layout — that the band is visibly shorter with clear
    /// margin above and below is a Simulator screenshot, recorded in progress.txt. What this holds is
    /// that the number itself cannot drift back without failing here.
    func testThePlayAreaTakesEightyPercentOfTheFlexibleRow() {
        XCTAssertEqual(MainScreenLayout.playAreaHeightFraction, 0.8)

        // The three measured rows through the shipped arithmetic, each matching the band that was
        // then measured on the Simulator to the point (progress.txt has the diff).
        XCTAssertEqual(MainScreenLayout.playAreaHeight(in: 63.5), 50.0, "41mm")
        XCTAssertEqual(MainScreenLayout.playAreaHeight(in: 66.5), 53.0, "42mm")
        XCTAssertEqual(MainScreenLayout.playAreaHeight(in: 76.0), 60.0, "46mm")
    }

    /// Floored, never rounded: the band is a whole number of points, so the sprite is never sized
    /// against a fractional slot and the band can never be a hair TALLER than its share of the row.
    func testTheBandIsFlooredToAWholeNumberOfPointsAndNeverExceedsItsShare() {
        for row in stride(from: 0.0, through: 300.0, by: 0.5) {
            let band = MainScreenLayout.playAreaHeight(in: CGFloat(row))
            XCTAssertEqual(band, band.rounded(), "row \(row) gave a fractional band")
            XCTAssertLessThanOrEqual(band,
                                     CGFloat(row) * MainScreenLayout.playAreaHeightFraction,
                                     "row \(row) gave a band over its share")
            XCTAssertGreaterThanOrEqual(band, 0, "row \(row) gave a negative band")
        }
    }

    /// The reclaimed fifth is real: every row leaves strictly more empty than it did, and the empty
    /// space is the row less the band — which is what the centring frame splits above and below.
    func testTheRemainingFifthIsLeftEmpty() {
        for row in stride(from: 20.0, through: 300.0, by: 1.0) {
            let empty = CGFloat(row) - MainScreenLayout.playAreaHeight(in: CGFloat(row))
            XCTAssertGreaterThanOrEqual(empty,
                                        CGFloat(row) * (1 - MainScreenLayout.playAreaHeightFraction),
                                        "row \(row) left too little empty")
        }
    }

    /// The sprite still fits the BAND it is drawn in, sick or healthy — the band is what
    /// `SpriteScale.fitting` is now asked about, and an overflow does not clip, it lands on the rows
    /// above and below.
    ///
    /// The arithmetic here is the shipped call site verbatim, `sizeFraction` included (US-221), so
    /// this holds against what is drawn rather than against what would be drawn without the fraction.
    func testTheSpriteFitsTheShortenedBandAtBothMeasuredRows() {
        for row in [63.5, 66.5, 76.0] as [CGFloat] {
            let band = MainScreenLayout.playAreaHeight(in: row)
            for isSick in [false, true] {
                let offered = SickBadgeLayout.spriteHeight(in: band, isSick: isSick)
                    * SpriteScale.sizeFraction
                let side = SpriteScale.fitting(offered) * CGFloat(SpriteSheet.frameSize)
                XCTAssertLessThanOrEqual(side, band, "row \(row), sick \(isSick) overflowed the band")
            }
        }
    }

    /// US-221: the Digimon itself is drawn at a fraction of the band it stands in.
    ///
    /// The fraction is pinned, and so is the ladder it lands on at each measured screen — a smaller
    /// Digimon is a screenshot (progress.txt), but the arithmetic that decides the size is not, and
    /// this is where it stops drifting.
    func testTheSpriteIsDrawnAtAFractionOfTheBandItStandsIn() {
        XCTAssertEqual(SpriteScale.sizeFraction, 0.75)

        // Two fractions, not one, because they answer different complaints: US-219's shortens the
        // BAND (the map and the poop pile shrink with it), this one only shrinks the Digimon. They
        // are deliberately NOT equal, and neither is derived from the other.
        XCTAssertNotEqual(SpriteScale.sizeFraction, MainScreenLayout.playAreaHeightFraction)

        // The floor comes down with it (US-221). It does not bind at any measured band — every
        // screen lands on 2 — so this is headroom for a band that gets shorter later, not a number
        // anything on screen depends on today.
        XCTAssertEqual(SpriteScale.minimum, 1)

        // The bands measured for US-219 (progress.txt) through the shipped call site. Every screen
        // drew scale 3 before this story; RE-MEASURED on the Simulator for US-221 by the sprite's
        // pixel quantisation (screenshot px per sprite px at @2x = 2 x scale) — see progress.txt.
        //   41mm  band 50 -> 37.50 -> 2      42mm  band 53 -> 39.75 -> 2      46mm  band 60 -> 45.0 -> 2
        for band in [50.0, 53.0, 60.0] as [CGFloat] {
            XCTAssertEqual(SpriteScale.fitting(band * SpriteScale.sizeFraction), 2, "band \(band)")
            // Stated as a step rather than as a number, so a future band change shows up here as
            // "the Digimon stopped shrinking" rather than as an opaque constant that moved.
            XCTAssertEqual(SpriteScale.fitting(band)
                               - SpriteScale.fitting(band * SpriteScale.sizeFraction),
                           1, "band \(band) did not step down")
        }

        // **Why not the 0.8 US-221 proposed.** It was predicted against slot numbers that were stale
        // by half; against the real 60pt band at 46mm, 0.8 is exactly 48.0 — exactly the bottom of
        // scale 3 — so that screen alone would have kept its old size. Measured, not deduced: a 0.8
        // build drew 46mm at 6 screenshot px per sprite px (scale 3, unchanged) while 42mm went to 4.
        XCTAssertEqual(SpriteScale.fitting(60.0 * 0.8), 3, "the knife-edge 0.8 sits on")

        // The whole window that steps all three down together, so the next person to tune this can
        // see how much room there is either side rather than guessing.
        for fraction in stride(from: 0.64, to: 0.80, by: 0.01) {
            for band in [50.0, 53.0, 60.0] as [CGFloat] {
                XCTAssertEqual(SpriteScale.fitting(band * CGFloat(fraction)), 2,
                               "fraction \(fraction), band \(band)")
            }
        }
        XCTAssertEqual(SpriteScale.fitting(50.0 * 0.63), 1, "just under the window, 41mm undershoots")
    }

    /// The fraction can only ever shrink the Digimon, never grow it, at any height at all.
    func testTheSizeFractionNeverDrawsALargerSprite() {
        for band in stride(from: 0.0, through: 300.0, by: 0.5) {
            let plain = SpriteScale.fitting(CGFloat(band))
            let scaled = SpriteScale.fitting(CGFloat(band) * SpriteScale.sizeFraction)
            XCTAssertLessThanOrEqual(scaled, plain, "band \(band) drew larger with the fraction")
        }
    }

    /// US-172 pinned the action row 4pt off the bottom; US-194 moves it to 12.
    ///
    /// The play area growing to fill the reclaimed bottom safe-area band is a Simulator screenshot,
    /// recorded in progress.txt — this cannot assert the safe-area reclaim, only the margin the row
    /// keeps below itself. Pinned at 12 so an edit that changes it fails here: because the inset is
    /// padded inside `.ignoresSafeArea(.bottom)` and the sprite is the one flexible row, this number
    /// is also exactly how much shorter US-194 made the room versus US-172 (12 - 4 = 8pt).
    func testTheActionRowKeepsExactlyTwelvePointsBelowIt() {
        XCTAssertEqual(MainScreenLayout.actionRowBottomInset, 12)
    }

    /// More room never draws a smaller Digimon.
    func testTheScaleNeverDecreasesAsHeightGrows() {
        var previous = SpriteScale.fitting(0)
        for height in stride(from: 0.0, through: 200.0, by: 1.0) {
            let scale = SpriteScale.fitting(CGFloat(height))
            XCTAssertGreaterThanOrEqual(scale, previous, "shrank at height \(height)")
            previous = scale
        }
    }
}
