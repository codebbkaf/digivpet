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

    /// US-209 AC1/AC2: Clean and Battle wear their pre-US-197 glyphs again. Asserted against the
    /// constants the two `ActionButtonFace`s are built from — the body itself is unreachable from a
    /// test — so re-adopting the coil or the fighter fails here rather than only in a screenshot.
    func testCleanAndBattleWearTheirPreUS197Glyphs() {
        XCTAssertEqual(ActionSymbol.clean, "sparkles")
        XCTAssertEqual(ActionSymbol.battle, "bolt.fill")
        XCTAssertNotEqual(ActionSymbol.battle, "figure.martial.arts")
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

    /// US-197 AC6, restated for US-211's AC6: a FULL row of circles and their gaps fits the narrowest
    /// supported screen (176pt at 41mm; the 42mm is 187pt and the 46mm wider still). US-197 split the
    /// old row of five into two rows of four; US-211 puts five back on row 1, so this is the guard
    /// that a bumped diameter or a sixth column clips the row at both ends fails here rather than
    /// only on a screenshot of the SMALL watch.
    func testAFullRowFitsTheNarrowestScreen() {
        XCTAssertLessThanOrEqual(ActionGridLayout.width, 176)
        XCTAssertEqual(ActionGridLayout.width, 166, "5 * 30 + 4 * 4")
    }

    /// US-211 AC6, the other half: the staggered row is offset INTO the full row's width rather than
    /// past it, so nothing hangs off the right edge. Checked at the row-2 count US-213 leaves behind
    /// (four buttons) as well as today's three.
    func testTheStaggeredRowStaysInsideAFullRowsWidth() {
        for buttons in 1...ActionGridLayout.columns - 1 {
            let width = CGFloat(buttons) * ActionButtonFace.diameter
                + CGFloat(buttons - 1) * ActionGridLayout.spacing
            let right = ActionGridLayout.staggerOffset(forRow: 1) + width
            XCTAssertLessThanOrEqual(right, ActionGridLayout.width, "row of \(buttons)")
        }
    }

    // MARK: - US-211: the staggered, scrollable, list-style grid

    /// AC1 and AC4: the buttons chunk five to a row, in the order they are declared. Eight buttons
    /// today put Feed, Train, Clean, Battle, Map on row 1 and Party, Light, Dex on row 2; the nine
    /// US-213 leaves — the same eight with Sleep appended — are the 5-and-4 the story describes, and
    /// AC3's future third row of five needs nothing but more buttons.
    func testTheButtonsChunkFiveToARow() {
        XCTAssertEqual(ActionGridLayout.columns, 5)
        XCTAssertEqual(ActionGridLayout.rowCounts(forButtons: ActionControls<EmptyView, EmptyView,
                                                                             EmptyView>.buttonCount),
                       [5, 3], "Feed Train Clean Battle Map / Party Light Dex")
        XCTAssertEqual(ActionGridLayout.rowCounts(forButtons: 9), [5, 4], "with US-213's Sleep")
        XCTAssertEqual(ActionGridLayout.rowCounts(forButtons: 14), [5, 5, 4], "and a third row")
        XCTAssertEqual(ActionGridLayout.rowCounts(forButtons: 0), [])
    }

    /// AC1: row 2 is staggered — each of its circles sits exactly midway between two of row 1's,
    /// rather than under one of them. Asserted on CENTRES, which is what "sits between" means on
    /// screen; a stagger of a whole cell (or of none) fails here.
    func testTheSecondRowsCirclesSitBetweenTheFirstRows() {
        XCTAssertEqual(ActionGridLayout.staggerOffset(forRow: 0), 0, "row 1 is flush")
        XCTAssertEqual(ActionGridLayout.staggerOffset(forRow: 1), ActionGridLayout.cellPitch / 2)
        XCTAssertEqual(ActionGridLayout.staggerOffset(forRow: 2), 0, "a third row is flush again")

        func centre(row: Int, column: Int) -> CGFloat {
            ActionGridLayout.staggerOffset(forRow: row)
                + CGFloat(column) * ActionGridLayout.cellPitch + ActionButtonFace.diameter / 2
        }

        for column in 0..<ActionGridLayout.columns - 1 {
            XCTAssertEqual(centre(row: 1, column: column),
                           (centre(row: 0, column: column) + centre(row: 0, column: column + 1)) / 2,
                           accuracy: 0.001, "column \(column)")
        }
    }

    /// AC3: the scroll view is capped at the grid's own natural height, so with room to spare it
    /// takes exactly what the two flush rows took before US-211 — the sprite above loses nothing —
    /// and a third row simply asks for more rather than changing the layout.
    func testTheGridsHeightIsItsRowsAndNothingMore() {
        XCTAssertEqual(ActionGridLayout.height(forRows: 0), 0)
        XCTAssertEqual(ActionGridLayout.height(forRows: 1), 30)
        XCTAssertEqual(ActionGridLayout.height(forRows: 2), 64, "30 + 4 + 30, the pre-US-211 height")
        XCTAssertEqual(ActionGridLayout.height(forRows: 3), 98)
    }

    /// AC2: the diameter is the largest the grid can carry, and the reason is the RING rather than
    /// the face — `DashRing` is 4pt wider, so a row's gap must be at least 4pt for two neighbouring
    /// rings to meet instead of overlap, and 5 * 32 + 4 * 4 already exceeds the 176pt screen.
    func testTheGapIsWideEnoughForTwoNeighbouringRingsToMeet() {
        let overhang = DashRing(filled: 0, total: 10).diameter - ActionButtonFace.diameter
        XCTAssertEqual(ActionGridLayout.spacing, overhang,
                       "two rings meet exactly at the row's gap")

        // 32 is US-038's cap and the next size up. It comes to exactly 176pt across — the whole of
        // the narrowest screen, with no margin for the safe area a watch inset leaves — so 30 is the
        // largest diameter this grid can actually carry.
        let oneSizeUp = CGFloat(ActionGridLayout.columns) * (ActionButtonFace.diameter + 2)
            + CGFloat(ActionGridLayout.columns - 1) * ActionGridLayout.spacing
        XCTAssertGreaterThanOrEqual(oneSizeUp, 176, "a 32pt face leaves five columns no margin")
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
        XCTAssertEqual(meatRing.diameter, ActionButtonFace.diameter + 4,
                       "it encircles the face rather than resizing the button")
    }

    // MARK: - US-212: the map ring, and one segment count for all five

    /// AC1: the Map button carries the strip's two step counts as a ring, built exactly like the four
    /// beside it — same `DashRing`, same defaults, only the numbers and the hue differ. The ring is
    /// reached through the view's OWN properties, so a call site that stopped passing the steps would
    /// fail here rather than only in a screenshot.
    func testTheMapRingIsDrivenByTheStripsSteps() {
        let controls = walking(recorded: 12_500, total: 25_000)
        let mapRing = DashRing(filled: controls.mapRecorded, total: controls.mapTotal, tint: .green)

        XCTAssertEqual(controls.mapRecorded, 12_500)
        XCTAssertEqual(controls.mapTotal, 25_000)
        XCTAssertEqual(mapRing.solid, DashRingLayout.segments / 2, "a half-walked map, half a ring")
        XCTAssertEqual(mapRing.diameter, DashRing(filled: 3, total: 10, tint: .red).diameter)
    }

    /// A save with no map selected hands 0 of 0 — `ContentView`'s nil case — which draws no ring and
    /// says nothing, the same silence an absent charge economy gets.
    func testNoMapSelectedDrawsNoRingAndSaysNothing() {
        let controls = walking(recorded: 0, total: 0)

        XCTAssertEqual(DashRing(filled: controls.mapRecorded, total: controls.mapTotal).solid, 0)
        XCTAssertEqual(controls.mapValue, "")
    }

    /// AC5: Map announces its step progress, with the unit spoken — "1500 of 25000" alone would not
    /// say what was being counted — and clamped, because a finished map is not capped at its finish
    /// line and must not read as more steps than the map is long.
    func testMapAnnouncesItsStepProgress() {
        XCTAssertEqual(walking(recorded: 1_500, total: 25_000).mapValue, "1500 of 25000 steps")
        XCTAssertEqual(walking(recorded: 0, total: 25_000).mapValue, "0 of 25000 steps")
        XCTAssertEqual(walking(recorded: 30_000, total: 25_000).mapValue, "25000 of 25000 steps",
                       "a map walked past its end cannot say 30000 of 25000")
    }

    /// AC3, end to end through the numbers the five buttons are actually handed: meat 20, train 10,
    /// battle 10, clean 8 and a 25000-step map all draw the SAME ten segments, so the row reads as one
    /// control repeated. Before US-212 those caps gave three different tick densities side by side.
    func testAllFiveRingsInTheRowShareTheirSegments() {
        let config = ConsumptionConfig.bundled
        let controls = ActionControls(canAffordBattle: true, poopCount: 1, lightState: .on,
                                      trainCharges: 5, trainChargeCap: config.maxTrainCharges,
                                      battleCharges: 5, battleChargeCap: config.maxBattleCharges,
                                      cleanCharges: 4, cleanChargeCap: config.maxCleanCharges,
                                      meat: 10, meatCap: config.meatCap,
                                      mapRecorded: 12_500, mapTotal: 25_000,
                                      feed: {}, train: {}, clean: {}, battle: {}, cycleLight: {},
                                      mapDestination: { EmptyView() },
                                      partyDestination: { EmptyView() },
                                      dexDestination: { EmptyView() })

        let rings = [
            DashRing(filled: controls.meat, total: controls.meatCap, tint: .orange),
            DashRing(filled: controls.trainCharges, total: controls.trainChargeCap, tint: .red),
            DashRing(filled: controls.cleanCharges, total: controls.cleanChargeCap, tint: .blue),
            DashRing(filled: controls.battleCharges, total: controls.battleChargeCap, tint: .purple),
            DashRing(filled: controls.mapRecorded, total: controls.mapTotal, tint: .green),
        ]

        for ring in rings {
            // Each is handed a value at half its own cap, so the same five segments light on all
            // five — which is only possible because the segment count no longer follows the cap.
            XCTAssertEqual(ring.solid, DashRingLayout.segments / 2)
        }
    }

    /// A row carrying a map, for the ring and announcement assertions above.
    private func walking(recorded: Int, total: Int) -> ActionControls<EmptyView, EmptyView, EmptyView> {
        ActionControls(canAffordBattle: true, poopCount: 0, lightState: .on,
                       mapRecorded: recorded, mapTotal: total,
                       feed: {}, train: {}, clean: {}, battle: {}, cycleLight: {},
                       mapDestination: { EmptyView() },
                       partyDestination: { EmptyView() },
                       dexDestination: { EmptyView() })
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
