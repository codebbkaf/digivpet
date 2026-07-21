import Foundation
import XCTest

@testable import DigiVPet

/// US-092 — effective power from the matchup and the training grade.
///
/// `BattleModifiers` is pure, so every test here is arithmetic on hand-built inputs: no store, no
/// clock, no generator. The pinned-outcome tests ("a perfect grade beats one stage up") are the
/// point — they are the balance claims D-4 makes, and re-tuning a multiplier into a state where a
/// good matchup cannot overcome a rung has to fail something.

/// Both axes inert: nothing beats it, it beats nothing. The floor an unauthored Digimon lands on.
private let inert = DigimonType.unauthored

private func type(_ element: DigimonElement, _ attribute: DigimonAttribute = .free) -> DigimonType {
    DigimonType(element: element, attribute: attribute)
}

/// Base power for a Digimon at `stage` that has never trained and never earned energy — so a test's
/// expected numbers move with `BattlePower`'s weights rather than freezing them a second time here.
private func basePower(_ stage: Stage, strengthStat: Int = 0) -> Int {
    BattlePower.power(stage: stage, strengthStat: strengthStat, lifetimeEnergy: .zero)
}

final class BattleModifierTests: XCTestCase {

    // MARK: - AC2: every multiplier is a named constant

    func testMultipliersAreTheDocumentedValues() {
        XCTAssertEqual(BattleModifiers.elementAdvantage, 1.25)
        XCTAssertEqual(BattleModifiers.elementDisadvantage, 0.8)
        XCTAssertEqual(BattleModifiers.attributeAdvantage, 1.1)
        XCTAssertEqual(BattleModifiers.attributeDisadvantage, 0.9)
    }

    /// The element axis is meant to be the headline and the attribute axis the tie-breaker. If a
    /// re-tune ever inverts that, the whole "canon is flavour, elements are rules" story is gone.
    func testTheElementAxisSwingsHarderThanTheAttributeAxis() {
        XCTAssertGreaterThan(BattleModifiers.elementAdvantage, BattleModifiers.attributeAdvantage)
        XCTAssertLessThan(BattleModifiers.elementDisadvantage, BattleModifiers.attributeDisadvantage)
    }

    // MARK: - AC3: TrainingResult.battleMultiplier

    func testTrainingMultipliersAreTheDocumentedValues() {
        XCTAssertEqual(TrainingResult.miss.battleMultiplier, 0.8)
        XCTAssertEqual(TrainingResult.good.battleMultiplier, 1.0)
        XCTAssertEqual(TrainingResult.great.battleMultiplier, 1.15)
        XCTAssertEqual(TrainingResult.perfect.battleMultiplier, 1.3)
    }

    /// A better round is never worth less, whatever the numbers are tuned to.
    func testABetterGradeNeverMultipliesLower() {
        let ascending = TrainingResult.allCases.sorted { $0.strengthGain < $1.strengthGain }
        for (weaker, stronger) in zip(ascending, ascending.dropFirst()) {
            XCTAssertLessThan(weaker.battleMultiplier, stronger.battleMultiplier)
        }
    }

    // MARK: - AC8: a light-vs-dark mutual matchup nets 1.0

    /// Both sides are strong against each other, so both multipliers apply and cancel. This is the
    /// only pairing in the chart where that happens, and it is the reason the factor is computed
    /// from the two directions rather than from a single `Effectiveness`.
    func testLightAgainstDarkNetsNothingForEitherSide() {
        XCTAssertEqual(BattleModifiers.elementFactor(.light, against: .dark), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BattleModifiers.elementFactor(.dark, against: .light), 1.0, accuracy: 0.0001)

        let power = basePower(.adult)
        let result = BattleModifiers.matchup(playerPower: power, playerType: type(.light),
                                             opponentPower: power, opponentType: type(.dark),
                                             training: .good)
        XCTAssertEqual(result.playerPower, power)
        XCTAssertEqual(result.opponentPower, power)
        // And it must READ as even, not as the `.advantage` the vocabulary type reports.
        XCTAssertEqual(DigimonElement.light.effectiveness(against: .dark), .advantage)
        XCTAssertEqual(result.elementEffectiveness, .even)
    }

    // MARK: - AC8: an even matchup with a good grade is raw BattlePower

    func testAnEvenMatchupWithAGoodGradeLeavesPowerUntouched() {
        let playerBase = basePower(.child, strengthStat: 5)
        let opponentBase = basePower(.child, strengthStat: 2)
        let result = BattleModifiers.matchup(playerPower: playerBase, playerType: inert,
                                             opponentPower: opponentBase, opponentType: inert,
                                             training: .good)

        XCTAssertEqual(result.playerPower, playerBase)
        XCTAssertEqual(result.opponentPower, opponentBase)
        XCTAssertEqual(result.player.totalFactor, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.elementEffectiveness, .even)
        XCTAssertEqual(result.attributeEffectiveness, .even)
    }

    // MARK: - AC8: a perfect grade with element advantage beats one stage up

    /// The upset D-4 promises: 1.3 x 1.25 is worth more than the 8 points a rung is worth, so the
    /// work the player did in the moment can overcome one evolution's head start.
    func testAPerfectGradeWithElementAdvantageBeatsAnOpponentOneStageHigher() {
        let player = basePower(.child)
        let opponent = basePower(.adult)
        XCTAssertLessThan(player, opponent, "the underdog must really be behind on raw power")

        let result = BattleModifiers.matchup(playerPower: player, playerType: type(.fire),
                                             opponentPower: opponent, opponentType: type(.plant),
                                             training: .perfect)

        XCTAssertEqual(result.elementEffectiveness, .advantage)
        XCTAssertGreaterThan(result.playerPower, result.opponentPower)
        // And it must show up where it counts — in what the engine actually rolls.
        XCTAssertGreaterThan(
            BattleEngine.maximumDamage(attacker: result.playerPower, defender: result.opponentPower),
            BattleEngine.maximumDamage(attacker: result.opponentPower, defender: result.playerPower))
    }

    /// ...but it is still a thumb on the scale, not the scale. Even every modifier in the game at
    /// once cannot DOUBLE a Digimon, so `BattlePower`'s stage term — 8 points a rung, 48 across the
    /// ladder — stays what a battle is mostly decided by.
    func testTheBestPossibleBoostStillDoesNotDoubleADigimon() {
        let best = BattleModifiers.elementAdvantage
            * BattleModifiers.attributeAdvantage
            * TrainingResult.perfect.battleMultiplier
        XCTAssertLessThan(best, 2.0)

        let power = basePower(.adult)
        let result = BattleModifiers.matchup(playerPower: power, playerType: type(.fire, .vaccine),
                                             opponentPower: power, opponentType: type(.plant, .virus),
                                             training: .perfect)
        XCTAssertEqual(result.player.totalFactor, best, accuracy: 0.0001)
        XCTAssertLessThan(result.playerPower, 2 * power)
    }

    // MARK: - AC8: a miss with element disadvantage loses to an equal stage

    func testAMissWithElementDisadvantageLosesToAnEqualStageOpponent() {
        let power = basePower(.child)
        let result = BattleModifiers.matchup(playerPower: power, playerType: type(.plant),
                                             opponentPower: power, opponentType: type(.fire),
                                             training: .miss)

        XCTAssertEqual(result.elementEffectiveness, .disadvantage)
        XCTAssertLessThan(result.playerPower, power, "the grade and the matchup both cut")
        XCTAssertGreaterThan(result.opponentPower, power, "and the opponent gains what it is owed")
        XCTAssertLessThan(result.playerPower, result.opponentPower)
    }

    // MARK: - AC8: the training multiplier never reaches the opponent

    /// The opponent is an AI with no minigame to have played. Its effective power must be identical
    /// whatever the player scored — otherwise a perfect round would hand the other side a perfect
    /// round too, and playing well would buy nothing.
    func testTheTrainingMultiplierIsNeverAppliedToTheOpponent() {
        let player = basePower(.adult, strengthStat: 4)
        let opponent = basePower(.adult, strengthStat: 4)

        var opponentPowers: Set<Int> = []
        for grade in TrainingResult.allCases {
            let result = BattleModifiers.matchup(playerPower: player, playerType: type(.water, .vaccine),
                                                 opponentPower: opponent,
                                                 opponentType: type(.fire, .virus),
                                                 training: grade)
            XCTAssertEqual(result.opponent.trainingFactor, 1.0)
            opponentPowers.insert(result.opponentPower)
        }
        XCTAssertEqual(opponentPowers.count, 1, "the opponent must not move when the grade does")
    }

    /// The player's side, conversely, must move with the grade and with nothing else.
    func testThePlayersEffectivePowerRisesWithTheGrade() {
        let power = basePower(.adult)
        let ordered = TrainingResult.allCases.sorted { $0.battleMultiplier < $1.battleMultiplier }
        let powers = ordered.map { grade in
            BattleModifiers.matchup(playerPower: power, playerType: inert,
                                    opponentPower: power, opponentType: inert,
                                    training: grade).playerPower
        }
        XCTAssertEqual(powers, powers.sorted())
        XCTAssertLessThan(powers.first!, powers.last!)
    }

    // MARK: - AC4: the breakdown is carried, not recomputed

    func testTheResultCarriesEveryFactorThatProducedIt() {
        let player = basePower(.adult, strengthStat: 3)
        let opponent = basePower(.child, strengthStat: 1)
        let result = BattleModifiers.matchup(playerPower: player, playerType: type(.fire, .vaccine),
                                             opponentPower: opponent,
                                             opponentType: type(.plant, .virus),
                                             training: .great)

        XCTAssertEqual(result.player.basePower, player)
        XCTAssertEqual(result.opponent.basePower, opponent)
        XCTAssertEqual(result.player.elementFactor, BattleModifiers.elementAdvantage)
        XCTAssertEqual(result.player.attributeFactor, BattleModifiers.attributeAdvantage)
        XCTAssertEqual(result.player.trainingFactor, TrainingResult.great.battleMultiplier)
        XCTAssertEqual(result.opponent.elementFactor, BattleModifiers.elementDisadvantage)
        XCTAssertEqual(result.opponent.attributeFactor, BattleModifiers.attributeDisadvantage)

        // US-094 can show the breakdown without recomputing: the factors it was handed reproduce
        // the very number the battle is fought with.
        for side in [result.player, result.opponent] {
            XCTAssertEqual(
                side.effectivePower,
                BattleModifiers.effectivePower(basePower: side.basePower,
                                               elementFactor: side.elementFactor,
                                               attributeFactor: side.attributeFactor,
                                               trainingFactor: side.trainingFactor))
            XCTAssertEqual(side.totalFactor,
                           side.elementFactor * side.attributeFactor * side.trainingFactor,
                           accuracy: 0.0001)
        }
    }

    // MARK: - AC5: pure

    func testTheSameInputsAlwaysGiveTheSameResult() {
        let first = BattleModifiers.matchup(playerPower: 37, playerType: type(.ice, .data),
                                            opponentPower: 41, opponentType: type(.steel, .vaccine),
                                            training: .perfect)
        for _ in 0..<10 {
            XCTAssertEqual(
                BattleModifiers.matchup(playerPower: 37, playerType: type(.ice, .data),
                                        opponentPower: 41, opponentType: type(.steel, .vaccine),
                                        training: .perfect),
                first)
        }
    }

    // MARK: - AC6: effective power is floored at 1

    /// The worst case the game can produce — a Digitama that missed its round into a double
    /// disadvantage — still has a power a ratio may be taken of.
    func testEffectivePowerIsNeverBelowOne() {
        let result = BattleModifiers.matchup(playerPower: basePower(.digitama),
                                             playerType: type(.plant, .data),
                                             opponentPower: basePower(.ultimate),
                                             opponentType: type(.fire, .virus),
                                             training: .miss)
        XCTAssertEqual(result.playerPower, 1)
        XCTAssertGreaterThanOrEqual(result.opponentPower, 1)

        // Even hand-built nonsense a caller might pass in.
        XCTAssertEqual(BattleModifiers.effectivePower(basePower: 0, elementFactor: 1,
                                                      attributeFactor: 1, trainingFactor: 1), 1)
        XCTAssertEqual(BattleModifiers.effectivePower(basePower: -50, elementFactor: 1,
                                                      attributeFactor: 1, trainingFactor: 1), 1)
    }

    // MARK: - AC7: BattleEngine.resolve just takes the two numbers

    /// The engine is unchanged: it is handed effective powers exactly where it was handed raw ones,
    /// and it reports back the powers it fought with.
    func testTheEngineFightsWithTheEffectivePowers() {
        let result = BattleModifiers.matchup(playerPower: basePower(.child), playerType: type(.fire),
                                             opponentPower: basePower(.adult),
                                             opponentType: type(.plant),
                                             training: .perfect)
        var generator = SeededGenerator(seed: 42)
        let report = BattleEngine.resolve(playerPower: result.playerPower,
                                          opponentPower: result.opponentPower,
                                          using: &generator)

        XCTAssertEqual(report.playerPower, result.playerPower)
        XCTAssertEqual(report.opponentPower, result.opponentPower)
        XCTAssertFalse(report.turns.isEmpty)
    }

    // MARK: - Factor helpers on their own

    func testAOneSidedElementPairingCutsOneWayAndBoostsTheOther() {
        XCTAssertEqual(BattleModifiers.elementFactor(.fire, against: .plant),
                       BattleModifiers.elementAdvantage)
        XCTAssertEqual(BattleModifiers.elementFactor(.plant, against: .fire),
                       BattleModifiers.elementDisadvantage)
    }

    /// `neutral` and `free` are the unauthored floor. Neither may hand out or suffer anything, or
    /// "we forgot to type this one" becomes a strategy.
    func testTheInertTypesNeverMoveAnyMultiplier() {
        for element in DigimonElement.allCases {
            XCTAssertEqual(BattleModifiers.elementFactor(.neutral, against: element), 1.0)
            XCTAssertEqual(BattleModifiers.elementFactor(element, against: .neutral), 1.0)
        }
        for attribute in DigimonAttribute.allCases {
            XCTAssertEqual(BattleModifiers.attributeFactor(.free, against: attribute), 1.0)
            XCTAssertEqual(BattleModifiers.attributeFactor(attribute, against: .free), 1.0)
        }
    }

    func testEffectivenessReadsOffTheFactor() {
        XCTAssertEqual(BattleModifiers.effectiveness(of: 1.25), .advantage)
        XCTAssertEqual(BattleModifiers.effectiveness(of: 0.8), .disadvantage)
        XCTAssertEqual(BattleModifiers.effectiveness(of: 1.0), .even)
    }

    /// The attribute triangle resolves on the same rule as the element chart, so a caller reading a
    /// matchup uses one idiom for both axes.
    func testTheAttributeTriangleResolvesLikeTheElementChart() {
        let result = BattleModifiers.matchup(playerPower: 20, playerType: type(.neutral, .vaccine),
                                             opponentPower: 20, opponentType: type(.neutral, .virus),
                                             training: .good)
        XCTAssertEqual(result.attributeEffectiveness, .advantage)
        XCTAssertEqual(result.elementEffectiveness, .even)
        XCTAssertEqual(result.playerPower, 22)   // round(20 x 1.1)
        XCTAssertEqual(result.opponentPower, 18) // round(20 x 0.9)
    }
}
