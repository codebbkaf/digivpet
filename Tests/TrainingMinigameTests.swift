import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-075 — the shape every training minigame shares, and the graded payout it feeds.
///
/// `TrainingTests.swift` still owns the eligibility rule and the apply layer; this suite owns the
/// three things US-075 adds on top: the grade -> gain table, the split between entering a round and
/// grading it, and the protocol a seventh game would conform to.
///
/// Everything here is pure. No game is played, no view is hosted, and nothing waits.

/// A saved game outside any store, funded enough to train. Copied from `TrainingTests`' fixture for
/// the same reason its own fixtures are copied — that one is `private` to its file.
private func makeState(strength: Int = 20, stamina: Int = 0) -> GameState {
    let state = GameState(currentDigimonId: "hero", stage: .babyI,
                          now: Date(timeIntervalSinceReferenceDate: 600_000))
    state.stageEnergy[.strength] = strength
    state.stageEnergy[.stamina] = stamina
    return state
}

// MARK: - AC1 / AC7: the grade -> gain table

final class TrainingResultTests: XCTestCase {

    /// AC1: the four grades, by name. Pinned as a set so a fifth grade added without a payout, or a
    /// rename, fails here rather than silently changing what a round can earn.
    func testTheGradesAreExactlyMissGoodGreatPerfect() {
        XCTAssertEqual(TrainingResult.allCases, [.miss, .good, .great, .perfect])
        XCTAssertEqual(Set(TrainingResult.allCases.map(\.rawValue)),
                       ["miss", "good", "great", "perfect"])
    }

    /// AC2 at every boundary — the whole table, not a sample of it. There are only four inputs, so
    /// "every boundary" is every case.
    func testEachGradeBuysItsOwnNumberOfPoints() {
        XCTAssertEqual(TrainingResult.miss.strengthGain, 0)
        XCTAssertEqual(TrainingResult.good.strengthGain, 1)
        XCTAssertEqual(TrainingResult.great.strengthGain, 2)
        XCTAssertEqual(TrainingResult.perfect.strengthGain, 3)
    }

    /// A miss must be worth nothing, never a penalty: the round already cost energy, and a negative
    /// gain would make training something a careful player avoids.
    func testAMissIsWorthNothingAndNeverTakesAPointAway() {
        XCTAssertEqual(TrainingResult.miss.strengthGain, 0)
        for grade in TrainingResult.allCases {
            XCTAssertGreaterThanOrEqual(grade.strengthGain, 0, "\(grade) pays a penalty")
        }
    }

    /// Doing better must never pay less — the property the four numbers exist to have.
    func testGainsRiseStrictlyWithTheGrade() {
        let gains = TrainingResult.allCases.map(\.strengthGain)
        XCTAssertEqual(gains, gains.sorted(), "the table is out of order")
        XCTAssertEqual(Set(gains).count, gains.count, "two grades pay the same")
    }

    /// The old ungraded payout is `good`, not a fifth number living beside the table.
    func testTheUngradedSessionPaysExactlyAGood() {
        XCTAssertEqual(TrainAction.strengthGainPerTraining, TrainingResult.good.strengthGain)
        XCTAssertEqual(TrainAction.strengthGainPerTraining, 1)
    }

    /// Every grade has to be showable — the end card names the round.
    func testEveryGradeCanNameItself() {
        XCTAssertEqual(TrainingResult.perfect.displayName, "Perfect")
        for grade in TrainingResult.allCases {
            XCTAssertFalse(grade.displayName.isEmpty)
        }
        XCTAssertEqual(Set(TrainingResult.allCases.map(\.displayName)).count, 4)
    }
}

// MARK: - AC2 / AC3 / AC4: entering a round, then grading it

final class GradedTrainingTests: XCTestCase {

    /// AC2 end to end: a whole round at each grade buys exactly that grade's points, and always for
    /// the same price.
    func testAWholeRoundPaysTheGradeAndAlwaysCostsTheSame() {
        for grade in TrainingResult.allCases {
            let state = makeState(strength: 20)

            let outcome = TrainAction.train(state, isAsleep: false, result: grade)

            XCTAssertEqual(outcome, .trained(spent: .strength,
                                             cost: TrainAction.energyCostPerTraining,
                                             gain: grade.strengthGain),
                           "\(grade) reported the wrong payout")
            XCTAssertEqual(state.strengthStat, grade.strengthGain, "\(grade) paid the wrong gain")
            XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                           "\(grade) was not charged the standard price")
        }
    }

    /// AC3: the charge lands when the round is ENTERED, before any grade exists.
    func testEnteringChargesTheEnergyBeforeAnythingIsPlayed() {
        let state = makeState(strength: 20)

        XCTAssertEqual(TrainAction.begin(state, isAsleep: false),
                       .started(spent: .strength, cost: TrainAction.energyCostPerTraining))
        XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
        XCTAssertEqual(state.strengthStat, 0, "nothing is earned until the round is graded")
    }

    /// AC3, the half that matters: a lost round is still a paid round. If the miss refunded, walking
    /// out of a round going badly would be free.
    func testAMissIsNotRefunded() {
        let state = makeState(strength: 20)

        TrainAction.begin(state, isAsleep: false)
        TrainAction.finish(state, result: .miss)

        XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                       "the miss was refunded")
        XCTAssertEqual(state.strengthStat, 0, "a miss buys nothing")
    }

    /// AC3: the charge is taken ONCE. Grading does not bill a second time, however good the round.
    func testGradingDoesNotChargeASecondTime() {
        let state = makeState(strength: 20)

        TrainAction.begin(state, isAsleep: false)
        let afterEntering = state.stageEnergy[.strength]
        TrainAction.finish(state, result: .perfect)

        XCTAssertEqual(state.stageEnergy[.strength], afterEntering)
        XCTAssertEqual(state.strengthStat, 3)
    }

    /// A round that is entered and never graded — dismissed, backgrounded — has still been paid for
    /// and has still happened. US-083 grades that case as a miss; this pins that even doing NOTHING
    /// leaves the charge and the count standing.
    func testAnAbandonedRoundStaysChargedAndStaysCounted() {
        let state = makeState(strength: 20)

        TrainAction.begin(state, isAsleep: false)

        XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
        XCTAssertEqual(state.stageTrainingSessions, 1)
        XCTAssertEqual(state.strengthStat, 0)
    }

    /// AC4: the session count is about how OFTEN, never how well — evolution reads it, and the
    /// bands US-061 authored only mean what they say if a miss counts as much as a perfect.
    func testEveryGradeIncrementsTheSessionCountExactlyOnce() {
        for grade in TrainingResult.allCases {
            let state = makeState(strength: 20)

            TrainAction.train(state, isAsleep: false, result: grade)

            XCTAssertEqual(state.stageTrainingSessions, 1, "\(grade) counted wrong")
        }
    }

    /// The miss case of AC4 spelled out on its own, because it is the one a "reward the player"
    /// instinct would get wrong.
    func testAMissStillCountsAsASessionTrained() {
        let state = makeState(strength: 20)

        TrainAction.train(state, isAsleep: false, result: .miss)

        XCTAssertEqual(state.stageTrainingSessions, 1)
        XCTAssertEqual(state.strengthStat, 0, "and still bought nothing")
    }

    /// Four rounds of mixed quality: four sessions, and the stat is the sum of the grades.
    func testSessionsAndPointsAccumulateIndependently() {
        let state = makeState(strength: 40)

        for grade in TrainingResult.allCases {
            TrainAction.train(state, isAsleep: false, result: grade)
        }

        XCTAssertEqual(state.stageTrainingSessions, 4)
        XCTAssertEqual(state.strengthStat, 0 + 1 + 2 + 3)
        XCTAssertEqual(state.stageEnergy[.strength], 40 - 4 * TrainAction.energyCostPerTraining)
    }

    // MARK: - AC5: eligibility is untouched, messages included

    /// The three block reasons, verbatim. AC5 says "with their current messages", so this asserts
    /// the strings rather than merely that something non-empty came back.
    func testTheBlockReasonsAreUnchangedWordForWord() {
        let asleep = makeState(strength: 20)
        XCTAssertEqual(TrainAction.begin(asleep, isAsleep: true),
                       .blocked(reason: "Asleep — let it rest."))

        let sick = makeState(strength: 20)
        sick.healthStatus = .sick
        XCTAssertEqual(TrainAction.begin(sick, isAsleep: false),
                       .blocked(reason: "Too sick to train."))

        let dead = makeState(strength: 20)
        dead.healthStatus = .dead
        XCTAssertEqual(TrainAction.begin(dead, isAsleep: false),
                       .blocked(reason: "It cannot train."))

        let broke = makeState(strength: TrainAction.energyCostPerTraining - 1,
                              stamina: TrainAction.energyCostPerTraining - 1)
        XCTAssertEqual(TrainAction.begin(broke, isAsleep: false),
                       .blocked(reason: "Not enough Strength or Stamina. Move to earn more."))
    }

    /// A blocked round is not a round: nothing charged, and nothing counted. The count matters most
    /// — a blocked tap that still counted would let a sleeping Digimon evolve on taps alone.
    func testABlockedRoundChargesNothingAndCountsNothing() {
        for (label, state, asleep) in blockedFixtures() {
            let before = state.stageEnergy[.strength]

            guard case .blocked = TrainAction.begin(state, isAsleep: asleep) else {
                return XCTFail("\(label) was not blocked")
            }
            XCTAssertEqual(state.stageEnergy[.strength], before, "\(label) was charged")
            XCTAssertEqual(state.stageTrainingSessions, 0, "\(label) counted as a session")
            XCTAssertEqual(state.strengthStat, 0, "\(label) paid out")
        }
    }

    /// The same four blocks through the one-shot call, so the graded path cannot have opened a way
    /// past a rule the two-phase path still enforces.
    func testTheOneShotCallBlocksForTheSameFourReasons() {
        for (label, state, asleep) in blockedFixtures() {
            guard case .blocked = TrainAction.train(state, isAsleep: asleep, result: .perfect) else {
                return XCTFail("\(label) trained anyway")
            }
            XCTAssertEqual(state.strengthStat, 0, "\(label) paid out")
            XCTAssertEqual(state.stageTrainingSessions, 0, "\(label) counted as a session")
        }
    }

    private func blockedFixtures() -> [(String, GameState, Bool)] {
        let sick = makeState(strength: 20)
        sick.healthStatus = .sick
        let dead = makeState(strength: 20)
        dead.healthStatus = .dead
        return [
            ("asleep", makeState(strength: 20), true),
            ("sick", sick, false),
            ("dead", dead, false),
            ("broke", makeState(strength: TrainAction.energyCostPerTraining - 1,
                                stamina: TrainAction.energyCostPerTraining - 1), false)
        ]
    }

    /// Grading is the only thing `finish` does — it must not touch the purse, the count, or the
    /// lifetime record, because `begin` already settled all three.
    func testGradingTouchesTheStatAndNothingElse() {
        let state = makeState(strength: 20, stamina: 7)
        // On the profile since US-123; `finish` is handed the state alone.
        let profile = PlayerProfile()
        profile.lifetimeEnergy[.strength] = 90
        state.stageEnergy[.vitality] = 40
        state.stageEnergy[.spirit] = 30

        TrainAction.finish(state, result: .great)

        XCTAssertEqual(state.strengthStat, 2)
        XCTAssertEqual(state.stageEnergy[.strength], 20)
        XCTAssertEqual(state.stageEnergy[.stamina], 7)
        XCTAssertEqual(state.stageEnergy[.vitality], 40)
        XCTAssertEqual(state.stageEnergy[.spirit], 30)
        XCTAssertEqual(profile.lifetimeEnergy[.strength], 90)
        XCTAssertEqual(state.stageTrainingSessions, 0, "grading is not a session")
    }
}

// MARK: - AC1: the protocol a seventh game would conform to

/// What US-076 through US-081 each become: a view with a name that ends by reporting one grade.
/// Its timing knob is a stored property with a default, set at the call site in the manner of
/// `BattleView.turnDuration`, which is how a real game stays testable without waiting.
private struct StubMinigame: TrainingMinigame {
    static let title = "Stub"

    /// The default is what the app plays at; a test overrides it to milliseconds.
    var roundDuration: TimeInterval = 3

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// Stands in for whatever ends a real round — a tap, a timeout, a last remembered step.
    func report(_ result: TrainingResult) { onFinish(result) }

    var body: some View { Text(Self.title) }
}

@MainActor
final class TrainingMinigameProtocolTests: XCTestCase {

    /// The shape, exercised GENERICALLY: anything conforming can be built knowing only the
    /// protocol, which is what "adding a seventh is adding a file" has to mean.
    func testAnyConformingGameCanBeBuiltAndGradedThroughTheProtocolAlone() {
        var reported: [TrainingResult] = []
        let game = makeGame(StubMinigame.self) { reported.append($0) }

        XCTAssertEqual(type(of: game).title, "Stub")
        XCTAssertFalse(type(of: game).title.isEmpty, "a game the overlay cannot name")

        game.report(.great)

        XCTAssertEqual(reported, [.great], "the round reported exactly one grade")
    }

    /// The knob survives being set from outside, so US-076's "injectable so tests never wait real
    /// time" has somewhere to live without a second initialiser.
    func testATimingKnobCanBeOverriddenAtTheCallSite() {
        var game = makeGame(StubMinigame.self) { _ in }
        XCTAssertEqual(game.roundDuration, 3)

        game.roundDuration = 0.01

        XCTAssertEqual(game.roundDuration, 0.01)
    }

    /// The loop closes: a grade off a game is the same value `TrainAction` pays out. Nothing here
    /// knows which game it was.
    func testAGradeFromAGameIsWhatTheActionPaysOut() {
        let state = makeState(strength: 20)
        TrainAction.begin(state, isAsleep: false)

        let game = makeGame(StubMinigame.self) { TrainAction.finish(state, result: $0) }
        game.report(.perfect)

        XCTAssertEqual(state.strengthStat, 3)
        XCTAssertEqual(state.stageTrainingSessions, 1)
        XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
    }

    /// Builds a game knowing nothing but the protocol — the compiler check that is the real point
    /// of this suite. It would not compile against a game that needed its own initialiser.
    private func makeGame<Game: TrainingMinigame>(
        _ type: Game.Type, onFinish: @escaping (TrainingResult) -> Void
    ) -> Game {
        Game(onFinish: onFinish)
    }
}
