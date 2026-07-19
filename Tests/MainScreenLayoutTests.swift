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
