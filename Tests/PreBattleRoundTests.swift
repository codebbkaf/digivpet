import Foundation
import XCTest

@testable import DigiVPet

/// US-093 — the pre-battle training round.
///
/// Tapping Battle no longer fights anything. It picks the opponent, spends the day's allowance and
/// puts the Digimon's assigned minigame on screen; the grade that round produces is what decides how
/// hard the player hits, through `BattleModifiers`. These run against the real `MainScreenModel` over
/// a real store, because every criterion here is about what is SAVED and when — the round costing
/// nothing, the allowance costing something, and neither depending on how the round goes.
///
/// The fixture is deliberately typed: `agumon` is fire and `tanemon` is plant, so the player carries
/// a real element advantage into the fight. That is what keeps "the report is built from the
/// effective powers" from being provable by an implementation that quietly passed `battlePower`
/// through — a neutral fixture would look identical.
@MainActor
final class PreBattleRoundTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Mid-morning, stated as a wall-clock time for the reason `BattleApplyTests` gives: the fallback
    /// sleep window is 22:00-07:00, and a bare interval could land the whole suite inside it and block
    /// every battle for the wrong reason.
    private static let now: Date = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "2026-07-17 10:00")!
    }()

    /// Three nodes: an egg for `start()` to have a Digitama to choose from, the fire Child fought as,
    /// and the one plant Baby II it can be matched against. One eligible opponent on purpose —
    /// matchmaking must not be the thing that varies between two runs of the same assertion.
    ///
    /// The ids are REAL ones, so `ElementCatalog.bundled` types them: fire beats plant, and neither
    /// vaccine nor free beats the other, which makes the element axis the only one that moves.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "agumon", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "agumon", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "tanemon", displayName: "Tanemon", stage: .babyII, spriteFile: "Tanemon")
        ])
    }

    /// - Parameter strengthEnergy: what a battle is PAID with since US-108. Funded by default,
    ///   because these tests are about the round rather than about affording it.
    private func makeModel(storeName: String = "Round",
                           strength: Int = 8,
                           strengthEnergy: Int = 100,
                           seed: UInt64 = 1) throws -> (MainScreenModel, GameStore, URL) {
        let url = storeDirectory.appendingPathComponent("\(storeName).store")
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "agumon", now: Self.now)
        state.stage = .child
        state.strengthStat = strength
        state.stageEnergy[.strength] = strengthEnergy
        // US-176: a battle now spends a charge walked up from steps, and the empty readers walk none.
        // Stocked past what these tests spend, since what they are about is the round rather than the
        // walking that pays for it.
        state.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        // US-027: the empty readers would otherwise have the audit charge a mistake for every day
        // since the epoch, which would sicken the Digimon before a single battle.
        state.healthDataLastSeen = Self.now
        state.hungerUpdatedAt = Self.now
        state.stageEnteredDate = Self.now
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { Self.now },
            chooseStartingDigitama: { $0.first },
            makeBattleGenerator: { SeededGenerator(seed: seed) }
        )
        return (model, store, url)
    }

    /// The game the fixture's Agumon is assigned, asked the way the model asks.
    private var assignedGame: MinigameKind {
        MinigameAssignment.game(for: "agumon", in: fixtureGraph(), roster: .bundled)
    }

    // MARK: - AC1: the tap opens the round, and nothing is fought until it is graded

    func testTappingBattleOpensTheAssignedMinigameAndFightsNothingYet() async throws {
        let (model, _, _) = try makeModel()
        await model.start()
        XCTAssertNil(model.pendingBattleRound, "nothing before the button is tapped")

        let game = try XCTUnwrap(model.battle(), "the round should have opened")

        XCTAssertEqual(game, assignedGame, "the Digimon's own assigned game, not a fixed one")
        XCTAssertEqual(model.pendingBattleRound?.game, game)
        XCTAssertNil(model.pendingBattle, "the battle does not begin until the round is graded")
        XCTAssertFalse(model.isWandering, "the round covers the screen, so nothing walks under it")

        let bout = try XCTUnwrap(model.finishBattleRound(.good), "grading it is what fights the fight")

        XCTAssertNil(model.pendingBattleRound, "the game comes down with the grade")
        XCTAssertEqual(model.pendingBattle, bout)
        XCTAssertFalse(bout.report.turns.isEmpty, "resolved before a frame of the arena is drawn")
    }

    /// "Exactly as `train()` does": the same assignment, asked through the same lookup, so the two
    /// buttons can never open different games for the same Digimon.
    func testTheRoundIsTheSameGameTrainOpens() async throws {
        let (battler, _, _) = try makeModel(storeName: "SameA")
        await battler.start()
        let (trainer, _, _) = try makeModel(storeName: "SameB")
        await trainer.start()
        trainer.state?.stageEnergy[.strength] = 40

        battler.battle()
        trainer.train()

        XCTAssertEqual(battler.pendingBattleRound?.game, trainer.pendingTraining?.kind)
    }

    // MARK: - AC2: the round is a fight, not a workout

    /// Each of the three costs asserted separately, and against the SAVED state rather than only the
    /// one in memory — a charge that reached disk would be the thing a user actually lost.
    func testThePreBattleRoundCostsNoEnergyNoStatAndNoTrainingSession() async throws {
        let (model, store, url) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.stageEnergy[.strength] = 40
        state.stageEnergy[.stamina] = 30
        state.strengthStat = 8
        state.stageTrainingSessions = 2

        model.battle()
        // Graded `perfect`, which is the most a round can be worth: if any of this were being paid
        // out as training, the best round is where it would show.
        model.finishBattleRound(.perfect)

        // US-108 gave the BATTLE a cost of its own — 5 points from the richer payable energy, taken
        // by the tap. What is asserted here is unchanged: the ROUND adds nothing on top of it.
        XCTAssertEqual(state.stageEnergy[.strength], 40 - BattleCost.energy,
                       "the battle's own cost, and not a point more for the round")
        XCTAssertEqual(state.stageEnergy[.stamina], 30, "and no Stamina — only one energy pays")
        XCTAssertEqual(state.strengthStat, 8, "and buys no strengthStat")
        XCTAssertEqual(state.stageTrainingSessions, 2, "and counts as no training session")

        try store.save()
        // The reopened store is held in a `let`: a `GameStore` that goes out of scope takes its
        // context with it, and the `GameState` it handed back traps the moment it is read.
        let reopened = try GameStore(url: url)
        let saved = try reopened.loadOrCreate(digitamaId: "agumon", now: Self.now)
        XCTAssertEqual(saved.stageEnergy[.strength], 40 - BattleCost.energy)
        XCTAssertEqual(saved.stageEnergy[.stamina], 30)
        XCTAssertEqual(saved.strengthStat, 8)
        XCTAssertEqual(saved.stageTrainingSessions, 2)
    }

    // MARK: - AC3: the allowance is spent when the game opens

    /// Read back off DISK with the round still on screen, which is the whole criterion: a force-quit
    /// mid-round has to have cost the battle. Nothing is saved between `battle()` and this read — the
    /// model's own flush is what has to have happened.
    func testTheCostIsSpentAndSavedWhenTheMinigameOpens() async throws {
        let (model, _, url) = try makeModel()
        await model.start()
        let before = try XCTUnwrap(model.state).stageEnergy[.strength]

        model.battle()

        XCTAssertNotNil(model.pendingBattleRound, "still mid-round")
        XCTAssertNil(model.pendingBattle, "and nothing fought")
        XCTAssertEqual(model.state?.stageEnergy[.strength], before - BattleCost.energy)

        // Held in a `let` for the reason the cost test spells out — a discarded store takes the
        // context of everything it returned with it.
        let reopened = try GameStore(url: url)
        let saved = try reopened.loadOrCreate(digitamaId: "agumon", now: Self.now)
        XCTAssertEqual(saved.stageEnergy[.strength], before - BattleCost.energy,
                       "the charge reached disk when the game appeared, not when the grade did")
        XCTAssertEqual(saved.battlesFought(now: Self.now, calendar: Self.calendar), 1)
    }

    // MARK: - AC4: walking out grades a miss and the fight still happens

    func testBackgroundingMidRoundGradesAMissAndTheBattleGoesAhead() async throws {
        let (model, _, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)

        model.battle()
        // The one call `ContentView` makes when the app leaves the foreground.
        model.abandonBattleRound()

        let bout = try XCTUnwrap(model.pendingBattle, "the fight is not cancelled")
        XCTAssertNil(model.pendingBattleRound)
        XCTAssertEqual(bout.matchup?.player.trainingFactor, TrainingResult.miss.battleMultiplier,
                       "graded a miss, and the miss multiplier is what it fights with")
        XCTAssertEqual(bout.report.playerPower,
                       BattleModifiers.effectivePower(basePower: state.battlePower(lifetimeEnergy: model.lifetimeEnergy),
                                                      elementFactor: BattleModifiers.elementAdvantage,
                                                      attributeFactor: 1.0,
                                                      trainingFactor: TrainingResult.miss.battleMultiplier))
        XCTAssertEqual(state.stageEnergy[.strength], 100 - BattleCost.energy,
                       "and the energy is not handed back for leaving")

        // A second backgrounding, with no round left, must not start a second battle over the first.
        model.abandonBattleRound()
        XCTAssertEqual(model.pendingBattle, bout)
    }

    // MARK: - AC5: the grade reaches the fight through BattleModifiers

    /// Every grade, same seed, same opponent. Three things are pinned at once: the player's effective
    /// power is D-4's arithmetic on the grade, the report is resolved FROM it, and the opponent — who
    /// played no round — is untouched by which grade the player earned.
    func testTheGradeIsCarriedIntoTheEffectivePowersTheReportIsBuiltFrom() async throws {
        var playerPowers: [TrainingResult: Int] = [:]
        var opponentPowers: Set<Int> = []

        for (index, grade) in [TrainingResult.miss, .good, .great, .perfect].enumerated() {
            let (model, _, _) = try makeModel(storeName: "Grade\(index)")
            await model.start()
            let state = try XCTUnwrap(model.state)

            model.battle()
            let bout = try XCTUnwrap(model.finishBattleRound(grade))
            let matchup = try XCTUnwrap(bout.matchup, "the arithmetic rides along on the bout")

            XCTAssertEqual(matchup.player.elementFactor, BattleModifiers.elementAdvantage,
                           "fire against plant")
            XCTAssertEqual(matchup.opponent.elementFactor, BattleModifiers.elementDisadvantage)
            XCTAssertEqual(matchup.elementEffectiveness, .advantage)
            XCTAssertEqual(matchup.player.attributeFactor, 1.0, "vaccine and free settle nothing")
            XCTAssertEqual(matchup.player.trainingFactor, grade.battleMultiplier)
            XCTAssertEqual(matchup.player.basePower, state.battlePower(lifetimeEnergy: model.lifetimeEnergy),
                           "the base is still what BattlePower says")

            XCTAssertEqual(matchup.player.effectivePower,
                           BattleModifiers.effectivePower(basePower: state.battlePower(lifetimeEnergy: model.lifetimeEnergy),
                                                          elementFactor: BattleModifiers.elementAdvantage,
                                                          attributeFactor: 1.0,
                                                          trainingFactor: grade.battleMultiplier))
            XCTAssertEqual(bout.report.playerPower, matchup.player.effectivePower,
                           "the report is fought from the effective power, not the raw one")
            XCTAssertEqual(bout.report.opponentPower, matchup.opponent.effectivePower)

            playerPowers[grade] = bout.report.playerPower
            opponentPowers.insert(bout.report.opponentPower)
        }

        XCTAssertEqual(opponentPowers.count, 1,
                       "the opponent played no round, so no grade of the player's may move it")
        let ordered = [TrainingResult.miss, .good, .great, .perfect].compactMap { playerPowers[$0] }
        XCTAssertEqual(ordered, ordered.sorted(), "a better round is never a weaker fight")
        XCTAssertLessThan(try XCTUnwrap(playerPowers[.miss]), try XCTUnwrap(playerPowers[.perfect]),
                          "and playing well is worth something")
    }

    // MARK: - AC6: a blocked battle opens no minigame

    /// Asleep is deliberately NOT in this list any more: US-110 made a sleeping Digimon one that is
    /// woken and fought with, not one that is refused. The two states left here are the two that
    /// still refuse — see `testASleepingDigimonIsWokenIntoTheRound` for what replaced the third.
    func testABlockedBattleShowsItsReasonAndOpensNoMinigame() async throws {
        // Dead.
        let (dead, _, _) = try makeModel(storeName: "Dead")
        await dead.start()
        dead.state?.healthStatus = .dead
        XCTAssertNil(dead.battle())
        XCTAssertEqual(dead.actionMessage, "It cannot battle.")
        XCTAssertNil(dead.pendingBattleRound)
        XCTAssertNil(dead.pendingBattle)

        // Broke — everything payable spent, which since US-108 is what refuses a battle where the
        // daily cap used to.
        let (spent, _, _) = try makeModel(storeName: "Spent", strengthEnergy: BattleCost.energy)
        await spent.start()
        spent.battle()
        spent.finishBattleRound(.good)
        spent.finishBattle()
        XCTAssertNil(spent.battle())
        XCTAssertEqual(spent.actionMessage, BattleCost.insufficientEnergyReason)
        XCTAssertNil(spent.pendingBattleRound, "the broke tap opens no game to play for nothing")
        XCTAssertNil(spent.pendingBattle)
    }

    /// US-110's half of the case above: the sleeping Digimon opens the round like any other, and the
    /// energy is really spent — a wake that opened a FREE round would be the same bug the other way
    /// round.
    func testASleepingDigimonIsWokenIntoTheRound() async throws {
        let (sleeper, _, _) = try makeModel(storeName: "Asleep")
        await sleeper.start()
        sleeper.isAsleep = true

        XCTAssertEqual(sleeper.battle(), assignedGame)
        XCTAssertFalse(sleeper.isAsleep)
        XCTAssertNotNil(sleeper.pendingBattleRound, "the round opened")
        XCTAssertEqual(sleeper.state?.stageEnergy[.strength], 100 - BattleCost.energy,
                       "and was paid for")
        XCTAssertEqual(sleeper.state?.stageSleepDisturbances, 1)
    }

    // MARK: - AC7: one round at a time

    func testTrainDuringAPendingBattleRoundIsANoOp() async throws {
        let (model, _, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.stageEnergy[.strength] = 40

        model.battle()
        let charged = state.stageEnergy[.strength]
        XCTAssertNil(model.train(), "Train is refused while a battle round is on screen")

        XCTAssertNil(model.pendingTraining, "no second game")
        XCTAssertEqual(state.stageEnergy[.strength], charged,
                       "the battle's charge and no training charge on top of it")
        XCTAssertEqual(state.stageTrainingSessions, 0)
        XCTAssertNotNil(model.pendingBattleRound, "the battle round is left alone")
    }

    func testBattleDuringAPendingTrainingRoundIsANoOp() async throws {
        let (model, _, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.stageEnergy[.strength] = 40

        model.train()
        let charged = state.stageEnergy[.strength]
        XCTAssertNil(model.battle(), "Battle is refused while a training round is on screen")

        XCTAssertNil(model.pendingBattleRound, "no second game")
        XCTAssertNil(model.pendingBattle)
        XCTAssertEqual(state.stageEnergy[.strength], charged,
                       "the training round is left alone and the refused battle charged nothing")
        XCTAssertNotNil(model.pendingTraining)
    }

    /// A second Battle tap during a round of its own is refused too — otherwise the overlay being the
    /// only thing covering the button would make a double tap cost two charges.
    func testASecondBattleTapDuringItsOwnRoundIsANoOp() async throws {
        let (model, _, _) = try makeModel()
        await model.start()

        let game = try XCTUnwrap(model.battle())
        XCTAssertNil(model.battle())

        XCTAssertEqual(model.pendingBattleRound?.game, game)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 100 - BattleCost.energy,
                       "one battle, one charge")
    }
}

// MARK: - Fixtures

private final class NoSamples: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class NoSleep: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
