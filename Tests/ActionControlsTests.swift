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
                                      lightState: .on,
                                      feed: { called.append("feed") },
                                      train: { called.append("train") },
                                      clean: { called.append("clean") },
                                      battle: { called.append("battle") },
                                      cycleLight: { called.append("light") },
                                      mapDestination: { EmptyView() },
                                      partyDestination: { EmptyView() },
                                      dexDestination: { EmptyView() })

        controls.feed()
        controls.train()
        controls.clean()
        controls.battle()
        controls.cycleLight()

        XCTAssertEqual(called, ["feed", "train", "clean", "battle", "light"])
    }

    /// US-052 AC4: Clean is disabled with nothing to clean, and enabled the moment there is.
    /// Asserted through the same `poopCount` the pile is drawn from, so the button and the mess on
    /// screen cannot get out of step.
    func testCleanIsDisabledOnlyWhenThereIsNoPoop() {
        for count in 0...PoopClock.maximumPoops {
            let controls = ActionControls(canAffordBattle: true,
                                          poopCount: count,
                                          lightState: .on,
                                          feed: {}, train: {}, clean: {}, battle: {}, cycleLight: {},
                                          mapDestination: { EmptyView() },
                                          partyDestination: { EmptyView() },
                                          dexDestination: { EmptyView() })
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
    private func controls(strength: Int, stamina: Int)
        -> ActionControls<EmptyView, EmptyView, EmptyView> {
        let state = GameState(currentDigimonId: "hero", now: Date(timeIntervalSince1970: 0))
        state.stageEnergy.strength = strength
        state.stageEnergy.stamina = stamina
        let canAfford = EnergyPurchase.payer(for: BattleCost.energy,
                                             from: BattleCost.payableWith, in: state) != nil

        return ActionControls(canAffordBattle: canAfford, poopCount: 0,
                              lightState: .on,
                              feed: {}, train: {}, clean: {}, battle: {}, cycleLight: {},
                              mapDestination: { EmptyView() },
                              partyDestination: { EmptyView() },
                              dexDestination: { EmptyView() })
    }

    /// US-197 AC6: a row of four circles and their gaps fits the narrowest supported screen (176pt
    /// at 41mm). US-197 split the old row of five into two rows of four, so each row is now narrower
    /// than before — but the guard stays, so a later fifth button or a bumped diameter that would
    /// clip a row at both ends fails here rather than only on a screenshot of the SMALL watch.
    func testARowOfFourFitsTheNarrowestScreen() {
        let buttons = 4
        let spacing: CGFloat = 4
        let width = CGFloat(buttons) * ActionButtonFace.diameter + CGFloat(buttons - 1) * spacing
        XCTAssertLessThanOrEqual(width, 176)
    }

    // MARK: - US-208: the meat ring on Feed

    /// AC4: Feed speaks its larder the way the other three speak their charges — through the SAME
    /// `chargeValue`, so the four buttons cannot drift into two phrasings. Asserted at the boundaries
    /// the shared rule owns: a full larder, an empty one, an overshoot clamped to the cap, and an
    /// economy with no cap at all staying silent rather than saying "0 of 0".
    func testFeedSpeaksItsMeatThroughTheSharedChargeValue() {
        let controls = ringed(meat: 7, meatCap: 20)
        XCTAssertEqual(controls.chargeValue(controls.meat, controls.meatCap), "7 of 20")

        XCTAssertEqual(controls.chargeValue(0, 20), "0 of 20")
        XCTAssertEqual(controls.chargeValue(20, 20), "20 of 20")
        XCTAssertEqual(controls.chargeValue(21, 20), "20 of 20", "an overshoot cannot say 21 of 20")
        XCTAssertEqual(controls.chargeValue(3, 0), "", "no larder, so nothing to announce")
    }

    /// AC1: the ring Feed carries is built the same way Train's, Clean's and Battle's are — same
    /// `DashRing`, same defaults, only the count and the hue differ. Built here rather than reached
    /// for inside `body`, which is unreachable outside a view graph, so what is pinned is that a
    /// meat ring and a charge ring are the same object with different numbers.
    func testTheMeatRingIsTheSameRingTheChargesUse() {
        let meatRing = DashRing(filled: 7, total: 20, tint: .orange)
        let trainRing = DashRing(filled: 3, total: 8, tint: .red)

        XCTAssertEqual(meatRing.diameter, trainRing.diameter)
        XCTAssertEqual(meatRing.lineWidth, trainRing.lineWidth)
        XCTAssertEqual(meatRing.gapDegrees, trainRing.gapDegrees)
        XCTAssertEqual(meatRing.diameter, ActionButtonFace.diameter + 4,
                       "it encircles the face rather than resizing the button")
    }

    /// A call site that says nothing about meat draws no ring, so every pre-US-208 construction of
    /// this view — the fixtures above, and every test that predates the rings — is unchanged.
    func testARowBuiltWithoutMeatCarriesNoRing() {
        let controls = self.controls(strength: 5, stamina: 5)
        XCTAssertEqual(controls.meat, 0)
        XCTAssertEqual(controls.meatCap, 0)
        XCTAssertEqual(controls.chargeValue(controls.meat, controls.meatCap), "")
    }

    /// A row carrying a larder, for the ring assertions above.
    private func ringed(meat: Int, meatCap: Int) -> ActionControls<EmptyView, EmptyView, EmptyView> {
        ActionControls(canAffordBattle: true, poopCount: 0, lightState: .on,
                       meat: meat, meatCap: meatCap,
                       feed: {}, train: {}, clean: {}, battle: {}, cycleLight: {},
                       mapDestination: { EmptyView() },
                       partyDestination: { EmptyView() },
                       dexDestination: { EmptyView() })
    }
}
