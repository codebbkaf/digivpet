import SwiftUI
import XCTest
@testable import DigiVPet

/// US-038: the circular action row.
///
/// What can be asserted here is the geometry and the wiring; that the four circles actually LOOK
/// like a row is a Simulator screenshot, and is recorded in progress.txt rather than faked here.
final class ActionControlsTests: XCTestCase {
    /// AC: no button larger than 32x32. Asserted against the constant the frame is built from, so a
    /// later "just a bit bigger" edit fails here rather than quietly eating the sprite's screen.
    func testTheButtonsAreNoLargerThanThirtyTwoPoints() {
        XCTAssertLessThanOrEqual(ActionButtonFace.diameter, 32)
    }

    /// Each button invokes the closure it was handed and no other — the row is a fan-out to three
    /// distinct model calls, and crossing two of them would be invisible until a user fed their
    /// Digimon and watched it train.
    func testEachActionInvokesItsOwnClosure() {
        var called: [String] = []
        let controls = ActionControls(battlesLeft: BattleLimits.perDay,
                                      feed: { called.append("feed") },
                                      train: { called.append("train") },
                                      battle: { called.append("battle") }) { EmptyView() }

        controls.feed()
        controls.train()
        controls.battle()

        XCTAssertEqual(called, ["feed", "train", "battle"])
    }
}
