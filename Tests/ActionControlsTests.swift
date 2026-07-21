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
        let controls = ActionControls(canAffordBattle: true,
                                      poopCount: 1,
                                      feed: { called.append("feed") },
                                      train: { called.append("train") },
                                      clean: { called.append("clean") },
                                      battle: { called.append("battle") }) { EmptyView() }

        controls.feed()
        controls.train()
        controls.clean()
        controls.battle()

        XCTAssertEqual(called, ["feed", "train", "clean", "battle"])
    }

    /// US-052 AC4: Clean is disabled with nothing to clean, and enabled the moment there is.
    /// Asserted through the same `poopCount` the pile is drawn from, so the button and the mess on
    /// screen cannot get out of step.
    func testCleanIsDisabledOnlyWhenThereIsNoPoop() {
        for count in 0...PoopClock.maximumPoops {
            let controls = ActionControls(canAffordBattle: true,
                                          poopCount: count,
                                          feed: {}, train: {}, clean: {}, battle: {}) { EmptyView() }
            XCTAssertEqual(controls.isCleanDisabled, count == 0, "wrong at \(count) poops")
        }
    }

    /// US-052 AC2: five circles and their gaps still fit the narrowest supported screen (176pt at
    /// 41mm). This is the arithmetic that forced the diameter down from 32 — without it, a later
    /// sixth button or a bumped diameter would silently clip the row at both ends, which no unit
    /// test would otherwise catch and only a screenshot on the SMALL watch would show.
    func testTheRowOfFiveFitsTheNarrowestScreen() {
        let buttons = 5
        let spacing: CGFloat = 4
        let width = CGFloat(buttons) * ActionButtonFace.diameter + CGFloat(buttons - 1) * spacing
        XCTAssertLessThanOrEqual(width, 176)
    }
}
