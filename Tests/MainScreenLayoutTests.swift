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

    /// Below the floor the sprite stops being readable as a Digimon, so it stops shrinking and
    /// overflows visibly instead — a smudge that fits would look fine and be wrong.
    func testTheScaleIsFlooredRatherThanShrinkingToNothing() {
        XCTAssertEqual(SpriteScale.fitting(0), SpriteScale.minimum)
        XCTAssertEqual(SpriteScale.fitting(20), SpriteScale.minimum)
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
    /// out of the one flexible row, the slot lost 8pt on each screen. RE-MEASURED on the Simulator
    /// with `-wanderDemo` (progress.txt has the method): 41.5pt on 41mm and 56.0pt on 46mm, which
    /// drop the sprite one deliberate step to scale 2 (41mm) and scale 3 (46mm). Those now sit mid-
    /// band rather than on an edge, so the font ceiling is looser than it was — but it stays pinned
    /// as a conservative guard, and if a later story changes the layout it must re-measure these two.
    ///
    /// This cannot assert the layout — that is a screenshot. What it CAN hold is the two font sizes,
    /// so growing one fails here rather than silently costing the Digimon a scale step.
    func testTheMainScreenFontsStaySmallEnoughToKeepTheSpriteScale() {
        XCTAssertLessThanOrEqual(MainScreenTypography.nameFontSize,
                                 MainScreenTypography.maximumSafeFontSize)
        XCTAssertLessThanOrEqual(MainScreenTypography.statValueFontSize,
                                 MainScreenTypography.maximumSafeFontSize)

        // The measured slots after US-194 shortened the room: scale 2 on 41mm, scale 3 on 46mm. These
        // are evidence, not arithmetic — a later layout change must re-measure and update them.
        XCTAssertEqual(SpriteScale.fitting(41.5), 2, "41mm slot measured after US-194")
        XCTAssertEqual(SpriteScale.fitting(56.0), 3, "46mm slot measured after US-194")

        // Both now sit mid-band with room to spare: 41mm keeps scale 2 down to 32, 46mm keeps 3 to 48.
        XCTAssertEqual(SpriteScale.fitting(48.0), 3)
        XCTAssertEqual(SpriteScale.fitting(47.9), 2)
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
