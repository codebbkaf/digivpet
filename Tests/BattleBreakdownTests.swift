import Foundation
import XCTest

@testable import DigiVPet

/// US-094 — the matchup caption and the result screen's breakdown.
///
/// `BattleBreakdown` is pure and takes a whole `BattleMatchup`, so every test here builds one
/// through `BattleModifiers.matchup` rather than by hand: what is being asserted is that the text
/// and the arithmetic the fight used agree, and a hand-built matchup could be given factors no
/// matchup can actually produce.
private func type(_ element: DigimonElement, _ attribute: DigimonAttribute = .free) -> DigimonType {
    DigimonType(element: element, attribute: attribute)
}

/// The AC's worked example: a Fire Vaccine on 41 power against a Plant Virus, after a perfect round.
private func workedExample(training: TrainingResult = .perfect) -> BattleMatchup {
    BattleModifiers.matchup(playerPower: 41,
                            playerType: type(.fire, .vaccine),
                            opponentPower: 41,
                            opponentType: type(.plant, .virus),
                            training: training)
}

final class BattleBreakdownTests: XCTestCase {

    // MARK: - Percentages

    func testAFactorReadsAsASignedWholePercentage() {
        XCTAssertEqual(BattleBreakdown.percent(of: BattleModifiers.elementAdvantage), 25)
        XCTAssertEqual(BattleBreakdown.percent(of: BattleModifiers.elementDisadvantage), -20)
        XCTAssertEqual(BattleBreakdown.percent(of: BattleModifiers.attributeAdvantage), 10)
        XCTAssertEqual(BattleBreakdown.percent(of: BattleModifiers.attributeDisadvantage), -10)
        XCTAssertEqual(BattleBreakdown.percent(of: 1.0), 0)
    }

    /// 1.15 is not representable in binary, and truncating it would print a `great` round as +14%.
    func testEveryGradeReadsAsTheMultiplierItIs() {
        XCTAssertEqual(BattleBreakdown.percent(of: TrainingResult.miss.battleMultiplier), -20)
        XCTAssertEqual(BattleBreakdown.percent(of: TrainingResult.good.battleMultiplier), 0)
        XCTAssertEqual(BattleBreakdown.percent(of: TrainingResult.great.battleMultiplier), 15)
        XCTAssertEqual(BattleBreakdown.percent(of: TrainingResult.perfect.battleMultiplier), 30)
    }

    // MARK: - AC2: the three contributions, then the power

    func testTheBreakdownIsTheACsWorkedExample() {
        let matchup = workedExample()

        XCTAssertEqual(BattleBreakdown.contributions(for: matchup), [
            BattleBreakdown.Contribution(label: "Perfect", percent: 30),
            BattleBreakdown.Contribution(label: "Fire vs Plant", percent: 25),
            BattleBreakdown.Contribution(label: "Vaccine vs Virus", percent: 10)
        ])
        XCTAssertEqual(BattleBreakdown.text(for: matchup),
                       "Perfect +30% · Fire vs Plant +25% · Vaccine vs Virus +10%")
        XCTAssertEqual(BattleBreakdown.powerText(for: matchup), "PWR 41 → 73")
    }

    /// The grade comes first because it is applied to a power the user has just earned; the axes
    /// follow in the order `BattleModifiers` multiplies them.
    func testTheGradeIsListedBeforeTheTypings() {
        let labels = BattleBreakdown.contributions(for: workedExample()).map(\.label)
        XCTAssertEqual(labels.first, "Perfect")
    }

    func testADisadvantageReadsAsANegativePercentage() {
        let matchup = BattleModifiers.matchup(playerPower: 40,
                                              playerType: type(.plant, .data),
                                              opponentPower: 40,
                                              opponentType: type(.fire, .virus),
                                              training: .miss)

        XCTAssertEqual(BattleBreakdown.text(for: matchup),
                       "Miss -20% · Plant vs Fire -20% · Data vs Virus -10%")
        XCTAssertEqual(BattleBreakdown.powerText(for: matchup), "PWR 40 → 23")
    }

    /// The result screen shows the power the ENGINE was handed, so the two can never disagree about
    /// how hard the player hit.
    func testThePowerShownIsThePowerTheBattleWasFoughtWith() {
        let matchup = workedExample()
        var generator = SeededGenerator(seed: 7)
        let report = BattleEngine.resolve(playerPower: matchup.playerPower,
                                          opponentPower: matchup.opponentPower,
                                          using: &generator)

        XCTAssertTrue(BattleBreakdown.powerText(for: matchup).hasSuffix("\(report.playerPower)"))
    }

    // MARK: - AC4: an even matchup says nothing rather than +0%

    func testAnEvenMatchupAfterAGoodRoundHasNoPercentageRow() {
        let matchup = BattleModifiers.matchup(playerPower: 41,
                                              playerType: .unauthored,
                                              opponentPower: 41,
                                              opponentType: .unauthored,
                                              training: .good)

        XCTAssertEqual(BattleBreakdown.contributions(for: matchup), [])
        XCTAssertNil(BattleBreakdown.text(for: matchup))
        XCTAssertEqual(BattleBreakdown.powerText(for: matchup), "PWR 41")
    }

    /// One neutral axis is dropped on its own — a `great` round against an evenly-attributed
    /// opponent lists the grade and the element, and no "+0%" between them.
    func testANeutralAxisIsDroppedRatherThanShownAtZero() {
        let matchup = BattleModifiers.matchup(playerPower: 40,
                                              playerType: type(.water, .vaccine),
                                              opponentPower: 40,
                                              opponentType: type(.fire, .free),
                                              training: .great)

        XCTAssertEqual(BattleBreakdown.contributions(for: matchup).map(\.label),
                       ["Great", "Water vs Fire"])
    }

    // MARK: - AC3: nothing is recomputed

    /// The one case a second derivation would get wrong. `DigimonElement.effectiveness(against:)`
    /// calls light vs dark an ADVANTAGE on both sides, while the arithmetic the fight used nets
    /// exactly 1.0 — so the caption must be nothing at all, and the row must not exist.
    func testAMutualRivalryIsShownAsTheWashItIs() {
        let matchup = BattleModifiers.matchup(playerPower: 41,
                                              playerType: type(.light),
                                              opponentPower: 41,
                                              opponentType: type(.dark),
                                              training: .good)

        XCTAssertEqual(DigimonElement.light.effectiveness(against: .dark), .advantage,
                       "the vocabulary still says both sides are strong")
        XCTAssertNil(BattleBreakdown.effectivenessCaption(matchup.elementEffectiveness))
        XCTAssertNil(BattleBreakdown.text(for: matchup))
        XCTAssertEqual(BattleBreakdown.powerText(for: matchup), "PWR 41")
    }

    /// Every percentage on screen is its factor, for every pairing the chart can produce — the
    /// breakdown is a reading of the matchup and never a second opinion about it.
    func testEveryContributionIsItsOwnFactor() {
        for element in DigimonElement.allCases {
            for attribute in DigimonAttribute.allCases {
                let matchup = BattleModifiers.matchup(playerPower: 40,
                                                      playerType: type(.fire, .vaccine),
                                                      opponentPower: 40,
                                                      opponentType: type(element, attribute),
                                                      training: .great)
                let percents = BattleBreakdown.contributions(for: matchup).map(\.percent)
                let expected = [matchup.player.trainingFactor,
                                matchup.player.elementFactor,
                                matchup.player.attributeFactor]
                    .map(BattleBreakdown.percent(of:))
                    .filter { $0 != 0 }

                XCTAssertEqual(percents, expected, "fire vaccine vs \(element) \(attribute)")
            }
        }
    }

    // MARK: - AC1: the stare-down's caption

    func testTheCaptionNamesTheEffectivenessOrSaysNothing() {
        XCTAssertEqual(BattleBreakdown.effectivenessCaption(.advantage), "Super effective")
        XCTAssertEqual(BattleBreakdown.effectivenessCaption(.disadvantage), "Not very effective")
        XCTAssertNil(BattleBreakdown.effectivenessCaption(.even))
    }

    /// The badges the stare-down draws come off the matchup, so they name the Digimon the fight was
    /// actually resolved between.
    func testTheMatchupCarriesBothTypingsForTheBadges() {
        let matchup = workedExample()
        XCTAssertEqual(matchup.playerType, type(.fire, .vaccine))
        XCTAssertEqual(matchup.opponentType, type(.plant, .virus))
        XCTAssertEqual(matchup.training, .perfect)
    }

    // MARK: - AC5: the room it may take

    func testTheLayoutIsTheACsBudget() {
        XCTAssertEqual(BattleBreakdownLayout.textSize, 9)
        XCTAssertEqual(BattleBreakdownLayout.minimumScale, 0.7)
        XCTAssertGreaterThan(BattleBreakdownLayout.lineLimit, 1,
                             "the widest breakdown needs a second line rather than truncating")
    }
}
