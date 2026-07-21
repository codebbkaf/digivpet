import XCTest
import SwiftUI
@testable import DigiVPet

/// US-090: the two combatants stand at opposite ends of the arena, and the projectile's flight is
/// measured off that arena rather than off a literal.
///
/// All of it is arithmetic against a screen width, which is the point: a screenshot can only say
/// where the sprites ended up on the one watch it was taken on, and the story is about BOTH.
final class BattleArenaTests: XCTestCase {

    /// The two widths every assertion below is made on: 41/42mm and 46mm.
    private var supportedWidths: [CGFloat] {
        [BattleArenaLayout.narrowestScreenWidth, BattleArenaLayout.widestScreenWidth]
    }

    // MARK: - AC1/AC3: they stand apart

    /// One sprite is 16pt of art at scale 3. Stated here so the gap arithmetic below is checkable
    /// against the sheet rather than against another constant in the same file.
    func testASpriteIsThreeTimesTheSixteenPointFrame() {
        XCTAssertEqual(BattleArenaLayout.spriteScale, 3)
        XCTAssertEqual(BattleArenaLayout.spriteSide, CGFloat(SpriteSheet.frameSize) * 3)
        XCTAssertEqual(BattleArenaLayout.spriteSide, 48)
    }

    /// AC3: at least 60pt of clear space between the two sprites' inner edges — on the 42mm screen
    /// the criterion names, and on the 46mm one too, where there is only ever more room.
    func testTheGapClearsSixtyPointsOnEverySupportedScreen() {
        for width in supportedWidths {
            XCTAssertGreaterThanOrEqual(BattleArenaLayout.gap(inWidth: width), 60,
                                        "only \(BattleArenaLayout.gap(inWidth: width))pt of gap at \(width)pt")
        }
    }

    /// The gap is exactly what is left once both sprites and both bezel insets are taken out — 72pt
    /// on a 176pt screen. Spelled out, so a change to the inset or the scale has to come past a
    /// number somebody can check by hand.
    func testTheGapIsTheScreenLessBothSpritesAndBothInsets() {
        XCTAssertEqual(BattleArenaLayout.gap(inWidth: 176), 176 - 8 - 96, accuracy: 0.001)
        XCTAssertEqual(BattleArenaLayout.gap(inWidth: 176), 72, accuracy: 0.001)
        XCTAssertEqual(BattleArenaLayout.gap(inWidth: 208), 104, accuracy: 0.001)
    }

    /// This is the story's whole delta: the old centred `HStack(spacing: 8)` left the two sprites 8pt
    /// apart. Asserted as a comparison rather than as prose, so nobody can quietly put it back.
    func testTheGapIsFarWiderThanTheOldEightPointSpacing() {
        for width in supportedWidths {
            XCTAssertGreaterThan(BattleArenaLayout.gap(inWidth: width), 8)
        }
    }

    /// A screen too narrow to hold both sprites has no gap — not a negative one. Never happens on a
    /// real watch; it is here so the arithmetic cannot hand a nonsense number to a layout.
    func testAnImpossiblyNarrowScreenHasNoGapRatherThanANegativeOne() {
        XCTAssertEqual(BattleArenaLayout.gap(inWidth: 40), 0)
        XCTAssertEqual(BattleArenaLayout.projectileSpan(inWidth: 20), 0)
    }

    // MARK: - AC2: they still face each other

    /// Unchanged by this story, and asserted here because pushing the two sprites apart is exactly
    /// the change that would make them face outward without anybody noticing until a screenshot.
    func testThePlayerIsMirroredAndTheOpponentIsNot() {
        XCTAssertTrue(BattleView.faces(.player), "the player turns right, toward the opponent")
        XCTAssertFalse(BattleView.faces(.opponent), "the opponent keeps the art's natural leftward heading")
    }

    // MARK: - AC4: the flight is derived from the arena

    /// The span is centre-to-centre: the gap plus one sprite. That is what makes a shot leave the
    /// attacker and land on the defender rather than stopping short in empty space.
    func testTheSpanIsTheGapPlusOneSprite() {
        for width in supportedWidths {
            XCTAssertEqual(BattleArenaLayout.projectileSpan(inWidth: width),
                           BattleArenaLayout.gap(inWidth: width) + BattleArenaLayout.spriteSide,
                           accuracy: 0.001)
        }
    }

    /// The flight's two ends land on the two sprites' centres, measured from the arena's centre —
    /// which is the claim "starts at the attacker and ends at the defender" written as arithmetic.
    func testTheFlightRunsBetweenTheTwoSpriteCentres() {
        for width in supportedWidths {
            let span = BattleArenaLayout.projectileSpan(inWidth: width)
            // Where each sprite's centre actually sits, worked out from the layout independently:
            // inset, then half a sprite in from its own edge.
            let playerCentre = BattleArenaLayout.bezelInset + BattleArenaLayout.spriteSide / 2
            let opponentCentre = width - BattleArenaLayout.bezelInset - BattleArenaLayout.spriteSide / 2
            let arenaCentre = width / 2

            XCTAssertEqual(BattleView.projectileOffset(rightward: true, progress: 0, span: span),
                           playerCentre - arenaCentre, accuracy: 0.001,
                           "a player shot starts at the player's centre")
            XCTAssertEqual(BattleView.projectileOffset(rightward: true, progress: 1, span: span),
                           opponentCentre - arenaCentre, accuracy: 0.001,
                           "and reaches the opponent's centre")
        }
    }

    /// The old 56pt literal was measured for a centred pair 8pt apart, so on either real screen it
    /// now falls well short of the defender. This is the reason AC4 asks for a derived span.
    func testTheDerivedSpanIsLongerThanTheOldFiftySixPointLiteral() {
        for width in supportedWidths {
            XCTAssertGreaterThan(BattleArenaLayout.projectileSpan(inWidth: width), 56)
        }
    }

    /// A wider watch means a longer flight, not the same flight with more empty screen around it.
    func testAWiderScreenGivesBothAWiderGapAndALongerFlight() {
        let narrow = BattleArenaLayout.narrowestScreenWidth
        let wide = BattleArenaLayout.widestScreenWidth
        XCTAssertGreaterThan(wide, narrow, "the two supported widths are genuinely different")
        XCTAssertEqual(BattleArenaLayout.gap(inWidth: wide) - BattleArenaLayout.gap(inWidth: narrow),
                       wide - narrow, accuracy: 0.001, "every extra point of screen becomes gap")
        XCTAssertGreaterThan(BattleArenaLayout.projectileSpan(inWidth: wide),
                             BattleArenaLayout.projectileSpan(inWidth: narrow))
    }

    // AC5 — that the opponent's name and the HP readout keep their places and are not overlapped —
    // is deliberately NOT asserted here. The sprites move only within their own row of the arena's
    // `VStack`, so no arithmetic in this file can be made to fail by an overlap; claiming otherwise
    // would be a test that passes for the wrong reason. It is checked on the screenshots instead.
}
