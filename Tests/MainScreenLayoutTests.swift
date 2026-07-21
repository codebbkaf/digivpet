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
