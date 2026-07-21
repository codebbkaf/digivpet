import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-078 — the power meter: how far a hold charges the meter, and what letting go there is worth.
///
/// Everything here is pure. No view is hosted and nothing waits a charge — a charge is arithmetic on
/// a duration, which is exactly what "the fill rate is injectable" has to buy.
///
/// The shipped bounds are eighths and the shipped rate is a half, so every band edge and every hold
/// duration below is exact in binary. Boundary assertions are ON the number, with no epsilon.

/// The shipped band, used throughout.
private let lower = PowerMeterGame.defaultBandLowerBound
private let upper = PowerMeterGame.defaultBandUpperBound

private func grade(_ fill: CGFloat) -> TrainingResult {
    PowerMeterGame.grade(fill: fill, lowerBound: lower, upperBound: upper)
}

// MARK: - AC1 / AC4: the grade at each floor

final class PowerMeterBandTests: XCTestCase {

    /// The four floors, by value. Asserted here so the boundary tests below are reading a pinned
    /// band rather than agreeing with whatever the code happens to compute.
    func testTheFloorsAreOneEighthTwoEighthsFiveEighthsAndSevenEighths() {
        let edges = PowerMeterGame.bandEdges(lowerBound: lower, upperBound: upper)

        XCTAssertEqual(edges.good, 0.15625)
        XCTAssertEqual(edges.great, 0.3125)
        XCTAssertEqual(edges.lower, 0.625)
        XCTAssertEqual(edges.upper, 0.875)
    }

    /// AC1: releasing inside the target band is the best the game pays — at the bottom edge, in the
    /// middle, and at the very top of it.
    func testReleasingAnywhereInTheBandIsAPerfect() {
        XCTAssertEqual(grade(0.625), .perfect, "the bottom edge is in the band")
        XCTAssertEqual(grade(0.75), .perfect)
        XCTAssertEqual(grade(0.875), .perfect, "the top edge is in the band")
    }

    /// AC4 at every floor, from ONE table: on the number is that grade, and a hair below is the
    /// grade beneath it. `nextDown` is the smallest step that exists at these values, so this is the
    /// boundary itself and not a sample near it.
    func testEachFloorIsInclusiveAndAHairBelowIsTheGradeBeneath() {
        let below: [TrainingResult: (CGFloat, TrainingResult)] = [
            .good: (0.15625, .miss),
            .great: (0.3125, .good),
            .perfect: (0.625, .great)
        ]

        for (expected, (floor, beneath)) in below {
            XCTAssertEqual(grade(floor), expected, "\(floor) should have been \(expected)")
            XCTAssertEqual(grade(floor.nextDown), beneath,
                           "just under \(floor) should have been \(beneath)")
        }
    }

    /// AC2, the whole point of the game: one step past the top of the band and the round pays
    /// NOTHING — not the grade below, not a consolation. Greed costs the round.
    func testOverfillingPastTheBandPaysNothingAtAll() {
        XCTAssertEqual(grade(0.875), .perfect)
        XCTAssertEqual(grade(CGFloat(0.875).nextUp), .miss, "a hair over the top is the overload")
        XCTAssertEqual(grade(0.9), .miss)
        XCTAssertEqual(grade(PowerMeterGame.meterCapacity), .miss, "a burst meter")
        XCTAssertEqual(TrainingResult.miss.strengthGain, 0, "the overload cost nothing")
    }

    /// AC2 stated as the shape of the whole curve: the grade climbs with the charge, then falls off
    /// a cliff. Every step up to the band's top is worth at least as much as the one before it, and
    /// everything above it is worth nothing.
    func testTheGradeClimbsWithTheChargeThenFallsOffACliff() {
        let steps = stride(from: CGFloat(0), through: 1, by: 1.0 / 256).map { ($0, grade($0)) }

        var best = 0
        for (fill, grade) in steps where fill <= 0.875 {
            XCTAssertGreaterThanOrEqual(grade.strengthGain, best, "the grade dipped at \(fill)")
            best = grade.strengthGain
        }
        XCTAssertEqual(best, TrainingResult.perfect.strengthGain, "the band was never reached")

        for (fill, grade) in steps where fill > 0.875 {
            XCTAssertEqual(grade, .miss, "\(fill) is past the band and should pay nothing")
        }
    }

    /// Undercharging is a miss too — the round is not free at the bottom either.
    func testBarelyTouchingTheMeterIsAMiss() {
        XCTAssertEqual(grade(0), .miss)
        XCTAssertEqual(grade(0.1), .miss)
    }

    /// AC3: the bounds are what decides all of it. The SAME fill is a perfect, a great and an
    /// overload depending only on where the band was put.
    func testTheSameFillIsWorthDifferentThingsUnderDifferentBounds() {
        XCTAssertEqual(PowerMeterGame.grade(fill: 0.5, lowerBound: 0.25, upperBound: 0.75), .perfect)
        XCTAssertEqual(PowerMeterGame.grade(fill: 0.5, lowerBound: 0.75, upperBound: 0.875), .great)
        XCTAssertEqual(PowerMeterGame.grade(fill: 0.5, lowerBound: 0.25, upperBound: 0.375), .miss)
    }

    /// Absurd injected bounds are sanitised rather than trusted: the band cannot escape the meter and
    /// cannot read backwards. Without this a reversed band would make every release an overload.
    func testAbsurdBoundsAreClampedIntoTheMeter() {
        let escaped = PowerMeterGame.bandEdges(lowerBound: -3, upperBound: 9)
        XCTAssertEqual(escaped.lower, 0)
        XCTAssertEqual(escaped.upper, PowerMeterGame.meterCapacity)

        let backwards = PowerMeterGame.bandEdges(lowerBound: 0.8, upperBound: 0.2)
        XCTAssertEqual(backwards.lower, 0.8)
        XCTAssertEqual(backwards.upper, 0.8, "the top of the band cannot sit below its bottom")
        XCTAssertEqual(PowerMeterGame.grade(fill: 0.8, lowerBound: 0.8, upperBound: 0.2), .perfect)
    }

    /// The charge is tinted by the zone it has reached, so the warning arrives while there is still a
    /// finger down to lift. Three zones, three colours.
    func testTheChargeWarnsInItsOwnColourBeforeItBursts() {
        XCTAssertEqual(PowerMeterGame.chargeTint(fill: 0.3, lowerBound: lower, upperBound: upper),
                       .orange)
        XCTAssertEqual(PowerMeterGame.chargeTint(fill: 0.7, lowerBound: lower, upperBound: upper),
                       .yellow)
        XCTAssertEqual(PowerMeterGame.chargeTint(fill: 0.95, lowerBound: lower, upperBound: upper),
                       .red)
    }
}

// MARK: - AC3: the fill rate is injectable, and it is what a hold is read against

final class PowerMeterFillTests: XCTestCase {

    /// The meter charges at the rate it is given, and stops at capacity rather than running away.
    func testTheMeterChargesAtTheGivenRateAndStopsAtCapacity() {
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: 0, fillRate: 0.5), 0)
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: 1, fillRate: 0.5), 0.5)
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: 1.25, fillRate: 0.5), 0.625)
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: 2, fillRate: 0.5),
                       PowerMeterGame.meterCapacity)
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: 60, fillRate: 0.5),
                       PowerMeterGame.meterCapacity, "the meter cannot overfill past bursting")
        XCTAssertEqual(PowerMeterGame.fill(afterHolding: -1, fillRate: 0.5), 0)
    }

    /// A meter that cannot fill stays empty rather than dividing by zero, and its fuse is infinite —
    /// which is what the round caps at its idle timeout instead of holding the user forever.
    func testANonPositiveRateLeavesTheMeterEmpty() {
        for rate in [0.0, -2.0] {
            XCTAssertEqual(PowerMeterGame.fill(afterHolding: 5, fillRate: rate), 0, "rate \(rate)")
            XCTAssertEqual(PowerMeterGame.holdDuration(toReach: 1, fillRate: rate), .infinity)
        }
    }

    /// `holdDuration` really is the inverse of `fill`: hold for exactly as long as it says and the
    /// meter is exactly that full. This is what the demo staging and the round's fuse both ride on.
    func testHoldDurationIsTheInverseOfFill() {
        for rate in [0.25, 0.5, 2.0] {
            for target: CGFloat in [0, 0.15625, 0.3125, 0.625, 0.875, 1] {
                let held = PowerMeterGame.holdDuration(toReach: target, fillRate: rate)
                XCTAssertEqual(PowerMeterGame.fill(afterHolding: held, fillRate: rate), target,
                               accuracy: 1e-12, "rate \(rate), target \(target)")
            }
        }
    }

    /// AC3: the same HOLD is worth different things at different rates. This is the whole reason the
    /// meter is a rate over a duration — without it a test driving a round in milliseconds could not
    /// charge the meter at all, and the injectability would have bought nothing.
    func testTheSameHoldIsWorthDifferentThingsAtDifferentRates() {
        func graded(rate: Double) -> TrainingResult {
            PowerMeterGame.grade(releasingAfter: 1.5, fillRate: rate,
                                 lowerBound: lower, upperBound: upper)
        }

        XCTAssertEqual(graded(rate: 0.5), .perfect, "1.5s at a half fills 0.75 — in the band")
        XCTAssertEqual(graded(rate: 0.25), .great, "1.5s at a quarter fills 0.375 — short of it")
        XCTAssertEqual(graded(rate: 0.125), .good, "1.5s at an eighth fills 0.1875 — barely on")
        XCTAssertEqual(graded(rate: 2), .miss, "1.5s at two bursts the meter")
    }

    /// A round driven in milliseconds still grades, at every band — the injectability an automated
    /// test actually needs.
    func testAWholeRoundGradesInMilliseconds() {
        let fast = 1000.0 // the whole meter in a thousandth of a second

        XCTAssertEqual(PowerMeterGame.grade(releasingAfter: 0.0001, fillRate: fast,
                                            lowerBound: lower, upperBound: upper), .miss)
        XCTAssertEqual(PowerMeterGame.grade(releasingAfter: 0.0004, fillRate: fast,
                                            lowerBound: lower, upperBound: upper), .great)
        XCTAssertEqual(PowerMeterGame.grade(releasingAfter: 0.0007, fillRate: fast,
                                            lowerBound: lower, upperBound: upper), .perfect)
        XCTAssertEqual(PowerMeterGame.grade(releasingAfter: 0.001, fillRate: fast,
                                            lowerBound: lower, upperBound: upper), .miss)
    }

    /// Never letting go is the overload, reached by the meter's own fuse: hold past capacity and the
    /// round pays nothing. This is the path `runRound` takes when the user simply does not release.
    func testHoldingForeverBurstsTheMeter() {
        for held: TimeInterval in [2, 5, 60] {
            XCTAssertEqual(PowerMeterGame.grade(releasingAfter: held, fillRate: 0.5,
                                                lowerBound: lower, upperBound: upper),
                           .miss, "held \(held)s")
        }
    }
}

// MARK: - The game as a minigame

@MainActor
final class PowerMeterGameTests: XCTestCase {

    /// It is a `TrainingMinigame` in the way US-075 means: buildable knowing only the protocol.
    func testItConformsThroughTheProtocolAlone() {
        let game = makeGame(PowerMeterGame.self) { _ in }

        XCTAssertEqual(type(of: game).title, "Power Meter")
        XCTAssertGreaterThan(game.fillRate, 0, "a meter that never fills")
    }

    /// AC3: the knobs are settable at the call site, so a round can be driven in milliseconds without
    /// a second initialiser.
    func testTheRateAndBandAreInjectable() {
        var game = makeGame(PowerMeterGame.self) { _ in }
        XCTAssertEqual(game.fillRate, 0.5)
        XCTAssertEqual(game.bandLowerBound, 0.625)
        XCTAssertEqual(game.bandUpperBound, 0.875)
        XCTAssertEqual(game.resultDuration, 1.0)
        XCTAssertEqual(game.idleTimeout, 12)

        game.fillRate = 50
        game.bandLowerBound = 0.5
        game.bandUpperBound = 0.55
        game.resultDuration = 0.01
        game.idleTimeout = 0.02

        XCTAssertEqual(game.fillRate, 50)
        XCTAssertEqual(game.bandLowerBound, 0.5)
        XCTAssertEqual(game.bandUpperBound, 0.55)
        XCTAssertEqual(game.resultDuration, 0.01)
        XCTAssertEqual(game.idleTimeout, 0.02)
    }

    /// The shipped defaults are the ones the pure tests above pin, so those tests are describing the
    /// game that actually ships rather than a band of their own.
    func testTheShippedDefaultsAreTheOnesTheRuleIsTestedAgainst() {
        let game = makeGame(PowerMeterGame.self) { _ in }

        XCTAssertEqual(game.bandLowerBound, PowerMeterGame.defaultBandLowerBound)
        XCTAssertEqual(game.bandUpperBound, PowerMeterGame.defaultBandUpperBound)
        XCTAssertEqual(game.fillRate, PowerMeterGame.defaultFillRate)
    }

    /// The shipped round is neither impossible nor automatic: the band is open for half a second,
    /// which is aimable but not driftable, and the meter bursts a second later. Guards against a
    /// later tweak quietly making the meter free or unhittable.
    func testTheShippedRoundIsNeitherImpossibleNorAutomatic() {
        let game = makeGame(PowerMeterGame.self) { _ in }
        let edges = PowerMeterGame.bandEdges(lowerBound: game.bandLowerBound,
                                             upperBound: game.bandUpperBound)

        let open = PowerMeterGame.holdDuration(toReach: edges.upper, fillRate: game.fillRate)
            - PowerMeterGame.holdDuration(toReach: edges.lower, fillRate: game.fillRate)
        XCTAssertEqual(open, 0.5, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(open, 0.25, "a band no finger could let go inside")

        let fuse = PowerMeterGame.holdDuration(toReach: PowerMeterGame.meterCapacity,
                                               fillRate: game.fillRate)
        XCTAssertLessThanOrEqual(fuse, game.idleTimeout,
                                 "a played round outlasts the wait for an unplayed one")
        XCTAssertGreaterThan(fuse, open, "there is no cost to simply holding on")
    }

    /// The grade the meter produces is a value `TrainAction` already knows how to pay out — the game
    /// itself knows nothing about energy or stats. Both endings: the band, and the overload.
    func testAGradeOffTheMeterIsWhatTheActionPaysOut() {
        let charged = makeState()
        TrainAction.begin(charged, isAsleep: false)
        TrainAction.finish(charged, result: PowerMeterGame.grade(releasingAfter: 1.5, fillRate: 0.5,
                                                                 lowerBound: lower, upperBound: upper))
        XCTAssertEqual(charged.strengthStat, TrainingResult.perfect.strengthGain)
        XCTAssertEqual(charged.stageTrainingSessions, 1)

        let burst = makeState()
        TrainAction.begin(burst, isAsleep: false)
        TrainAction.finish(burst, result: PowerMeterGame.grade(releasingAfter: 4, fillRate: 0.5,
                                                               lowerBound: lower, upperBound: upper))
        XCTAssertEqual(burst.strengthStat, 0, "the overload paid out")
        XCTAssertEqual(burst.stageTrainingSessions, 1, "the burst round still happened")
        XCTAssertEqual(burst.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                       "and was still charged for")
    }

    private func makeState() -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: Date(timeIntervalSinceReferenceDate: 600_000))
        state.stageEnergy[.strength] = 20
        return state
    }

    private func makeGame<Game: TrainingMinigame>(
        _ type: Game.Type, onFinish: @escaping (TrainingResult) -> Void
    ) -> Game {
        Game(onFinish: onFinish)
    }
}
