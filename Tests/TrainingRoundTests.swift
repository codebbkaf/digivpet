import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-083 — the Train button opens the assigned minigame instead of silently paying a point.
///
/// Everything here drives the real `MainScreenModel` and the real store, because the whole story is
/// about the SEAM between the two halves of a training: `train()` charges and opens a round,
/// `finishTraining(_:)` pays the grade the round produced. The games themselves are already tested
/// (US-076..US-081) and the assignment is already tested (US-082); what is untested until now is that
/// the charge happens once, at the front, and that no ending gives it back.
///
/// No test waits real time — the model's action hold is injected at milliseconds, and no minigame is
/// hosted at all: a grade is handed to `finishTraining` exactly as a game's `onFinish` hands it.

private enum Clock {
    /// Mid-afternoon in the zone below, which matters: nothing here forces the Digimon awake, and the
    /// fallback sleep window (22:00-07:00) would block every training in this file from a night-time
    /// instant. The same value the US-025 apply suite uses, for the same reason.
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    /// A fixed zone, matching the other apply suites, so nothing here depends on where it runs.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// Fixtures for the apply layer: every fetcher hands back nothing, so no energy is credited behind
/// these tests' backs. Copied rather than shared — the ones in the other apply suites are `private`
/// to their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class TrainingRoundTests: XCTestCase {
    private var storeDirectory: URL!
    private var trainHaptics = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TrainingRoundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        trainHaptics = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Child in the SHIPPED `agumon` line, so the game that opens is the one US-082's table names
    /// rather than a stage fallback — that is the tier this story has to prove reaches the screen.
    /// It has no outgoing edges, so nothing here can evolve and every change to the saved game is
    /// training's doing alone. The egg exists only because `start()` resolves a starting Digitama
    /// before it loads, and throws `.noDigitama` without one.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, line: "agumon",
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, line: "agumon",
                          spriteFile: "Agumon")
        ])
    }

    /// Deliberately EMPTY. Every id these tests train is in the fixture graph, which carries both the
    /// line and the stage, so a roster consulted at all would be a bug — see `MainScreenModel.roster`.
    private let fixtureRoster = Roster(entries: [])

    private func makeModel(url: URL) -> MainScreenModel {
        MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            roster: fixtureRoster,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            calendar: Clock.calendar,
            now: { Clock.start },
            chooseStartingDigitama: { $0.first },
            playTrainHaptic: { [weak self] in self?.trainHaptics += 1 },
            // Milliseconds, so the revert to idle is observable without waiting out the app's 2s.
            actionDuration: 0.05
        )
    }

    /// Seeds a saved game at "hero" with the given Strength, then hands back a started model reading
    /// it off disk.
    private func startedModel(named name: String, strength: Int,
                              healthStatus: HealthStatus = .healthy) async throws -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .child
        state.stageEnergy[.strength] = strength
        state.healthStatus = healthStatus
        try seeding.save()

        let model = makeModel(url: url)
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }

    // MARK: - AC1: Train presents the assigned game

    /// The game that opens is the one the ASSIGNMENT names, asked for the same way the model asks —
    /// so reshuffling US-082's table moves this test with it instead of breaking it. The second
    /// assertion is the one that would catch a lookup wired to the stage floor by mistake: "hero" is a
    /// Child, whose fallback is Power Meter, and its line's game is not that.
    func testTrainingOpensTheGameTheDigimonIsAssigned() async throws {
        let model = try await startedModel(named: "opens", strength: 20)

        XCTAssertNil(model.pendingTraining, "no round before the button")
        model.train()

        let expected = MinigameAssignment.game(line: "agumon", stage: .child)
        XCTAssertEqual(model.pendingTraining?.kind, expected)
        XCTAssertNotEqual(expected, MinigameAssignment.fallback(for: .child),
                          "the LINE decided this, not the stage floor")
    }

    /// The overlay covers the Digimon, so it stops pacing about underneath it — the same rule a
    /// battle, a ceremony and a memorial already follow.
    ///
    /// This is as close as a unit test gets to AC1's "the buttons underneath are not tappable through
    /// it": hit testing needs a hosted view. What IS assertable is the invariant that matters — the
    /// round cannot be entered twice, so even a tap that got through would not charge again. See
    /// `testASecondTrainTapDuringARoundChangesNothing`.
    func testAGameOnScreenSuspendsTheWalk() async throws {
        let model = try await startedModel(named: "wander", strength: 20)
        XCTAssertTrue(model.isWandering)

        model.train()
        XCTAssertFalse(model.isWandering, "the game has the screen")

        model.finishTraining(.good)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.isWandering, "and gives it back")
    }

    func testASecondTrainTapDuringARoundChangesNothing() async throws {
        let model = try await startedModel(named: "double", strength: 20)
        model.train()
        let opened = model.pendingTraining

        XCTAssertNil(model.train(), "a round is already in play")
        XCTAssertEqual(model.pendingTraining, opened, "the same round, not a fresh one")
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                       "charged once")
        XCTAssertEqual(model.state?.stageTrainingSessions, 1, "counted once")
    }

    // MARK: - AC2: the result applies the graded gain and shows what was earned

    /// Every grade, through the pair the screen makes: entered by `train()`, paid by
    /// `finishTraining`. The gain is read off `TrainingResult` rather than restated, so this asserts
    /// that the GRADE THE GAME REPORTED is what was paid — not that 3 happens to equal 3.
    func testEachGradePaysItsOwnGain() async throws {
        for (index, result) in TrainingResult.allCases.enumerated() {
            let model = try await startedModel(named: "grade\(index)", strength: 20)
            model.train()
            model.finishTraining(result)

            XCTAssertEqual(model.state?.strengthStat, result.strengthGain, "\(result)")
            XCTAssertNil(model.pendingTraining, "the game comes down when it is paid")
        }
    }

    /// What the user reads afterwards: the grade by name, the stat it bought, and the energy the round
    /// cost. The cost is in the caption because the bar dropped when the game OPENED, several seconds
    /// before this line appears, and would otherwise be unexplained.
    func testTheCaptionNamesTheGradeTheGainAndWhatItCost() async throws {
        let model = try await startedModel(named: "caption", strength: 20)
        model.train()
        model.finishTraining(.great)

        let message = try XCTUnwrap(model.actionMessage)
        XCTAssertTrue(message.contains(TrainingResult.great.displayName), message)
        XCTAssertTrue(message.contains("+\(TrainingResult.great.strengthGain) STR"), message)
        XCTAssertTrue(message.contains("-\(TrainAction.energyCostPerTraining)"), message)
        XCTAssertTrue(message.contains(EnergyType.strength.displayName), message)
    }

    /// A miss is announced too, and does not wear the attack pose: the round happened and bought
    /// nothing, which is a different thing to show than a landed blow.
    func testAMissIsShownAsOneRatherThanAsALandedBlow() async throws {
        let model = try await startedModel(named: "missPose", strength: 20)
        model.train()
        model.finishTraining(.miss)

        XCTAssertEqual(model.animation, .pose(.angry))
        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertTrue(try XCTUnwrap(model.actionMessage).contains("+0 STR"))
    }

    /// A game that called back twice would otherwise be paid twice. `TrainingMinigame` promises one
    /// call; this is what makes the promise unnecessary.
    func testARoundIsPaidOnceEvenIfTheGameReportsTwice() async throws {
        let model = try await startedModel(named: "twice", strength: 20)
        model.train()
        model.finishTraining(.perfect)
        model.finishTraining(.perfect)

        XCTAssertEqual(model.state?.strengthStat, TrainingResult.perfect.strengthGain)
    }

    /// The count evolution reads is taken when the round OPENS, never when it is graded — see
    /// `GameState.stageTrainingSessions`. A missed round is still a session trained.
    func testTheSessionIsCountedOnceWhenTheRoundOpens() async throws {
        let model = try await startedModel(named: "sessions", strength: 20)

        model.train()
        XCTAssertEqual(model.state?.stageTrainingSessions, 1, "counted on entry")
        model.finishTraining(.miss)
        XCTAssertEqual(model.state?.stageTrainingSessions, 1, "and not again on the grade")
    }

    // MARK: - AC3: blocked cases show their message and never open a game

    /// US-083's asleep case, reversed by US-110: a sleeping Digimon is WOKEN and the game opens, so
    /// what this pins now is that the woken round is a whole real round — charged, counted and on
    /// screen — rather than a half-started one.
    func testTrainingWhileAsleepWakesTheDigimonAndOpensTheGame() async throws {
        let model = try await startedModel(named: "asleep", strength: 20)
        model.isAsleep = true

        guard case .started = try XCTUnwrap(model.train()) else {
            return XCTFail("expected the round to open")
        }
        XCTAssertFalse(model.isAsleep)
        XCTAssertNotNil(model.pendingTraining)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
        XCTAssertEqual(model.state?.stageTrainingSessions, 1, "and the session is counted")
        XCTAssertEqual(model.state?.stageSleepDisturbances, 1, "the disturbance is charged too")
    }

    func testTrainingWhileSickIsBlockedAndOpensNoGame() async throws {
        let model = try await startedModel(named: "sick", strength: 20, healthStatus: .sick)

        guard case .blocked(let reason) = try XCTUnwrap(model.train()) else {
            return XCTFail("expected a block")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertNil(model.pendingTraining)
        XCTAssertEqual(model.actionMessage, reason)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20)
        XCTAssertEqual(model.state?.stageTrainingSessions, 0)
    }

    /// The third block, and the one a free game would be most tempting for: a player with no energy
    /// left could otherwise mash Train for a stat all evening.
    func testTrainingWithoutEnoughEnergyIsBlockedAndOpensNoGame() async throws {
        let model = try await startedModel(named: "broke",
                                           strength: TrainAction.energyCostPerTraining - 1)

        guard case .blocked(let reason) = try XCTUnwrap(model.train()) else {
            return XCTFail("expected a block")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertNil(model.pendingTraining)
        XCTAssertEqual(model.actionMessage, reason)
        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertEqual(model.state?.stageTrainingSessions, 0)
    }

    /// Nothing to pay out when no round was ever entered, however `finishTraining` is reached.
    func testGradingWithNoRoundInPlayPaysNothing() async throws {
        let model = try await startedModel(named: "nothing", strength: 20)

        model.finishTraining(.perfect)

        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20)
        XCTAssertEqual(trainHaptics, 0)
        XCTAssertNil(model.actionMessage)
    }

    // MARK: - AC4: walking out mid-round grades a miss and refunds nothing

    func testAbandoningARoundGradesItAMissAndRefundsNothing() async throws {
        let model = try await startedModel(named: "abandon", strength: 20)
        model.train()

        model.abandonTraining()

        XCTAssertNil(model.pendingTraining, "the game comes down with the user")
        XCTAssertEqual(model.state?.strengthStat, 0, "a miss buys nothing")
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                       "and nothing is handed back")
        XCTAssertEqual(model.state?.stageTrainingSessions, 1, "the session still happened")
    }

    /// Every ordinary backgrounding, which is most of them. Abandoning must not manufacture a miss
    /// out of a training that was never started.
    func testAbandoningWithNoRoundInPlayDoesNothing() async throws {
        let model = try await startedModel(named: "idleAbandon", strength: 20)

        model.abandonTraining()

        XCTAssertEqual(model.state?.stageEnergy[.strength], 20)
        XCTAssertEqual(model.state?.stageTrainingSessions, 0)
        XCTAssertEqual(trainHaptics, 0)
        XCTAssertNil(model.actionMessage)
    }

    /// The force-quit case, and the reason the charge is taken and SAVED at the front: a round killed
    /// before it could be graded has already reached disk poorer. Reopening the store is exactly what
    /// the next launch does, so this is that launch.
    func testTheChargeIsOnDiskBeforeTheRoundIsGraded() async throws {
        let model = try await startedModel(named: "forceQuit", strength: 20)
        model.train()
        XCTAssertNotNil(model.pendingTraining, "the round is still open — nothing has graded it")

        let reopened = try GameStore(url: storeURL("forceQuit"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining,
                       "the energy went when the game opened")
        XCTAssertEqual(saved.stageTrainingSessions, 1)
        XCTAssertEqual(saved.strengthStat, 0, "and bought nothing, because nothing was played")
    }

    /// The whole round, persisted: what a relaunch after a training finds.
    func testAGradedRoundIsPersisted() async throws {
        let model = try await startedModel(named: "persistGrade", strength: 20)
        model.train()
        model.finishTraining(.perfect)

        let reopened = try GameStore(url: storeURL("persistGrade"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.strengthStat, TrainingResult.perfect.strengthGain)
        XCTAssertEqual(saved.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
    }
}
