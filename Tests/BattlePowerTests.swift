import Foundation
import XCTest

@testable import DigiVPet

/// US-030 — battle power.
///
/// `BattlePower` is pure, so every test here is arithmetic on hand-built inputs: no store, no clock,
/// no simulator state. The monotonicity tests are the ones that matter — they hold whatever the
/// weights are tuned to, so re-balancing the formula cannot silently make a bigger Digimon weaker.

private let start = Date(timeIntervalSinceReferenceDate: 700_000)

private func totals(_ each: Int) -> EnergyTotals {
    EnergyTotals(strength: each, vitality: each, spirit: each, stamina: each)
}

final class BattlePowerTests: XCTestCase {

    // MARK: - AC1: a pure function of stage, strengthStat and lifetime energy

    /// Same inputs, same answer — no randomness and no hidden clock, so US-031 can roll its own dice
    /// against a stat that does not move underneath it.
    func testPowerIsDeterministicForTheSameInputs() {
        let first = BattlePower.power(stage: .adult, strengthStat: 7, lifetimeEnergy: totals(30))
        for _ in 0..<10 {
            XCTAssertEqual(
                BattlePower.power(stage: .adult, strengthStat: 7, lifetimeEnergy: totals(30)), first)
        }
    }

    /// Nothing else on the saved game may reach the formula. Two Digimon agreeing on the three
    /// documented terms must have identical power however different they are elsewhere — hunger,
    /// care mistakes, sickness, battles won, the day they hatched.
    func testOnlyStageStrengthAndLifetimeEnergyAffectPower() {
        let plain = GameState(currentDigimonId: "hero", stage: .child, now: start)
        plain.strengthStat = 4
        plain.lifetimeEnergy = totals(20)

        let battered = GameState(currentDigimonId: "hero", stage: .child, now: start)
        battered.strengthStat = 4
        battered.lifetimeEnergy = totals(20)
        // Everything the formula must ignore.
        battered.stageEnergy = totals(500)
        battered.hunger = HungerClock.maximumHunger
        battered.careMistakeCount = 9
        battered.healthStatus = .sick
        battered.battleWins = 12
        battered.battleLosses = 3
        battered.birthDate = start.addingTimeInterval(-90 * 24 * 3600)

        XCTAssertEqual(battered.battlePower, plain.battlePower)
    }

    /// The `GameState` convenience reads the same three fields the free function does.
    func testGameStateBattlePowerMatchesTheFreeFunction() {
        let state = GameState(currentDigimonId: "hero", stage: .perfect, now: start)
        state.strengthStat = 11
        state.lifetimeEnergy = totals(40)

        XCTAssertEqual(
            state.battlePower,
            BattlePower.power(stage: .perfect, strengthStat: 11, lifetimeEnergy: totals(40)))
    }

    // MARK: - AC2 / AC3: the documented weights, and monotonicity in stage and strength

    /// The formula in the doc comment, evaluated by hand. If a weight is retuned this fails, which
    /// is the point: the comment is the specification and must be updated with the constants.
    func testPowerMatchesTheDocumentedFormula() {
        // Adult (rung 4), 6 sessions trained, 260 lifetime energy total.
        let lifetime = EnergyTotals(strength: 100, vitality: 60, spirit: 50, stamina: 50)
        XCTAssertEqual(lifetime.total, 260)

        let expected = 1 + 8 * 4 + 3 * 6 + 260 / 25  // 1 + 32 + 18 + 10 = 61
        XCTAssertEqual(expected, 61)
        XCTAssertEqual(
            BattlePower.power(stage: .adult, strengthStat: 6, lifetimeEnergy: lifetime), 61)
    }

    /// AC3, stage half: EVERY step up the ladder raises power, with strength and energy held equal.
    /// Asserted across the whole ladder rather than at one pair, so no rung can be missed.
    func testAHigherStageAlwaysProducesHigherPower() {
        let ladder: [Stage] = [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate]

        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            let weak = BattlePower.power(stage: lower, strengthStat: 5, lifetimeEnergy: totals(25))
            let strong = BattlePower.power(stage: higher, strengthStat: 5, lifetimeEnergy: totals(25))
            XCTAssertGreaterThan(
                strong, weak, "\(higher.displayName) must outpower \(lower.displayName)")
        }
    }

    /// AC3, strength half: one more training session is always more power, at every stage.
    func testAHigherStrengthStatAlwaysProducesHigherPower() {
        for stage in Stage.allCases {
            for strength in 0..<10 {
                let weak = BattlePower.power(
                    stage: stage, strengthStat: strength, lifetimeEnergy: totals(25))
                let strong = BattlePower.power(
                    stage: stage, strengthStat: strength + 1, lifetimeEnergy: totals(25))
                XCTAssertGreaterThan(strong, weak, "\(stage.displayName) at \(strength) strength")
            }
        }
    }

    /// AC3 stated as one comparison: a bigger, better-trained Digimon beats a smaller untrained one
    /// even when the small one has hoarded more lifetime energy. Stage and training must dominate,
    /// or the slow floor would let an idle Digitama out-fight an Adult.
    func testAHigherStageAndStrengthBeatsAHoarderOfLifetimeEnergy() {
        let trained = BattlePower.power(stage: .adult, strengthStat: 10, lifetimeEnergy: totals(0))
        let hoarder = BattlePower.power(stage: .babyI, strengthStat: 0, lifetimeEnergy: totals(100))

        XCTAssertGreaterThan(trained, hoarder)
    }

    // MARK: - Lifetime energy and Armor-Hybrid

    /// Lifetime energy raises power too, just slowly: 25 points of it buys exactly one.
    func testLifetimeEnergyRaisesPowerAtTheDocumentedRate() {
        let none = BattlePower.power(stage: .child, strengthStat: 0, lifetimeEnergy: .zero)
        let some = BattlePower.power(
            stage: .child, strengthStat: 0, lifetimeEnergy: EnergyTotals(strength: 25))
        let more = BattlePower.power(
            stage: .child, strengthStat: 0, lifetimeEnergy: EnergyTotals(strength: 100))

        XCTAssertEqual(some, none + 1)
        XCTAssertEqual(more, none + 4)
    }

    /// It is the TOTAL across the four types that counts, not any one of them — a sleeper and a
    /// walker who earned the same amount fight equally hard.
    func testLifetimeEnergyCountsTheTotalNotOneType() {
        let walker = BattlePower.power(
            stage: .child, strengthStat: 0, lifetimeEnergy: EnergyTotals(strength: 100))
        let sleeper = BattlePower.power(
            stage: .child, strengthStat: 0, lifetimeEnergy: EnergyTotals(spirit: 100))
        let mixed = BattlePower.power(
            stage: .child, strengthStat: 0, lifetimeEnergy: totals(25))

        XCTAssertEqual(walker, sleeper)
        XCTAssertEqual(walker, mixed)
    }

    /// Armor-Hybrid has no `ladderIndex`, so it needs its own answer. It fights as an Adult — not as
    /// an egg, which is what a `?? 0` fallback would have made it.
    func testArmorHybridFightsAsAnAdult() {
        XCTAssertNil(Stage.armorHybrid.ladderIndex)
        XCTAssertEqual(BattlePower.battleRung(.armorHybrid), BattlePower.battleRung(.adult))
        XCTAssertEqual(
            BattlePower.power(stage: .armorHybrid, strengthStat: 3, lifetimeEnergy: totals(10)),
            BattlePower.power(stage: .adult, strengthStat: 3, lifetimeEnergy: totals(10)))
    }

    /// Power is never zero, so US-031 may divide by it. A fresh egg is the weakest thing in the game.
    func testAFreshDigitamaHasTheLowestPowerAndItIsPositive() {
        let egg = GameState(currentDigimonId: "hero", stage: .digitama, now: start)

        XCTAssertEqual(egg.battlePower, BattlePower.base)
        XCTAssertGreaterThan(egg.battlePower, 0)
    }
}
