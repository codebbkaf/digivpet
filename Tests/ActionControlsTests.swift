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

    /// US-109 AC7: the Battle button's rule IS the energy rule, not a copy of it. Four points in
    /// both payable energies cannot buy a five-point battle; five in either can.
    ///
    /// Driven through `EnergyPurchase` over a real `GameState` rather than a hand-written `true`,
    /// because the bug this guards against is the view and `MainScreenModel.battle()` drifting
    /// apart — a button that looks tappable and then refuses.
    func testBattleIsDisabledWithFourPointsInBothEnergiesAndEnabledWithFive() {
        XCTAssertEqual(BattleCost.energy, 5, "the four-and-five cases below assume a 5-point battle")

        XCTAssertTrue(controls(strength: 4, stamina: 4).isBattleDisabled, "4 and 4 cannot pay 5")
        XCTAssertFalse(controls(strength: 5, stamina: 4).isBattleDisabled, "Strength can pay")
        XCTAssertFalse(controls(strength: 4, stamina: 5).isBattleDisabled, "Stamina can pay")
    }

    /// US-109 AC3, AC4 and AC8: the caption names ENERGY when the Digimon is broke and is absent
    /// entirely when it is not.
    ///
    /// The unaffordable string is the model's OWN refusal, so what a user reads under the row cannot
    /// disagree with what `battle()` enforces; and it says nothing about a daily allowance, because
    /// US-108 deleted the allowance. Nothing is shown while a battle is affordable — a permanent
    /// cost label on one of five buttons would be noise on a 41mm screen.
    func testTheCaptionNamesEnergyOnlyWhileABattleIsUnaffordable() {
        XCTAssertNil(controls(strength: 5, stamina: 5).limitCaption)
        XCTAssertNil(controls(strength: 99, stamina: 0).limitCaption)

        XCTAssertEqual(controls(strength: 4, stamina: 4).limitCaption,
                       BattleCost.insufficientEnergyReason)
        XCTAssertEqual(controls(strength: 0, stamina: 0).limitCaption,
                       BattleCost.insufficientEnergyReason)
    }

    /// A row whose Battle button reads the affordability of the energies it is given, asked the same
    /// way `MainScreenModel.canAffordBattle` asks it.
    private func controls(strength: Int, stamina: Int) -> ActionControls<EmptyView> {
        let state = GameState(currentDigimonId: "hero", now: Date(timeIntervalSince1970: 0))
        state.stageEnergy.strength = strength
        state.stageEnergy.stamina = stamina
        let canAfford = EnergyPurchase.payer(for: BattleCost.energy,
                                             from: BattleCost.payableWith, in: state) != nil

        return ActionControls(canAffordBattle: canAfford, poopCount: 0,
                              feed: {}, train: {}, clean: {}, battle: {}) { EmptyView() }
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
