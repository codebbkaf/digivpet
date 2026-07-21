import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-025 — training.
///
/// Two layers, as in US-024's suite: `TrainActionTests` pins the pure rule against a hand-built
/// `GameState`, and `TrainApplyTests` drives the real `MainScreenModel` and the real store, so the
/// attack pose, the haptic and the save are exercised through the code the screen actually calls.
///
/// No test waits real time: the model's action hold is injected at milliseconds rather than the
/// app's two seconds.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    /// A fixed zone, matching the other apply suites, so nothing here depends on where it runs.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// A saved game outside any store — enough for the pure rule, which only reads and writes fields.
private func makeState(strength: Int = 0, stamina: Int = 0) -> GameState {
    let state = GameState(currentDigimonId: "hero", stage: .babyI, now: Clock.start)
    state.stageEnergy[.strength] = strength
    state.stageEnergy[.stamina] = stamina
    return state
}

final class TrainActionTests: XCTestCase {

    // MARK: - AC1 / AC4: raises strengthStat, deducts the energy

    func testTrainingRaisesStrengthStatAndDeductsStrengthEnergy() {
        let state = makeState(strength: 20)

        let outcome = TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(outcome, .trained(spent: .strength,
                                         cost: TrainAction.energyCostPerTraining,
                                         gain: TrainAction.strengthGainPerTraining))
        XCTAssertEqual(state.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(state.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
    }

    /// The "or Stamina" half of the criterion: a Digimon with no Strength but plenty of exercise
    /// minutes can still train, and pays with what it has.
    func testTrainingSpendsStaminaWhenItIsTheRicherOfTheTwo() {
        let state = makeState(strength: 1, stamina: 30)

        let outcome = TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(outcome, .trained(spent: .stamina,
                                         cost: TrainAction.energyCostPerTraining,
                                         gain: TrainAction.strengthGainPerTraining))
        XCTAssertEqual(state.stageEnergy[.stamina], 30 - TrainAction.energyCostPerTraining)
        XCTAssertEqual(state.stageEnergy[.strength], 1, "the poorer currency was left alone")
    }

    /// A tie goes to Strength, by `payableWith` order. Pinned because "whichever it holds more of"
    /// says nothing about equal holdings, and an unstable answer would make the caption flicker.
    func testATieIsPaidWithStrength() {
        let state = makeState(strength: 20, stamina: 20)

        XCTAssertEqual(TrainAction.train(state, isAsleep: false),
                       .trained(spent: .strength,
                                cost: TrainAction.energyCostPerTraining,
                                gain: TrainAction.strengthGainPerTraining))
    }

    /// Vitality is feeding's currency and Spirit is sleep; training must not quietly drain either,
    /// or feeding and the evolution branch would silently pay for the gym.
    func testTrainingSpendsNeitherVitalityNorSpirit() {
        let state = makeState(strength: 20)
        state.stageEnergy[.vitality] = 40
        state.stageEnergy[.spirit] = 30

        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.stageEnergy[.vitality], 40)
        XCTAssertEqual(state.stageEnergy[.spirit], 30)
    }

    /// `lifetimeEnergy` is the record of what was ever EARNED, so spending must not rewrite it.
    func testTrainingDoesNotTakeBackLifetimeEnergy() {
        let state = makeState(strength: 20)
        state.lifetimeEnergy[.strength] = 90

        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.lifetimeEnergy[.strength], 90)
    }

    /// Sessions accumulate — the stat is a running total, not a flag.
    func testRepeatedTrainingAccumulates() {
        let state = makeState(strength: 20)

        TrainAction.train(state, isAsleep: false)
        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.strengthStat, 2 * TrainAction.strengthGainPerTraining)
        XCTAssertEqual(state.stageEnergy[.strength], 20 - 2 * TrainAction.energyCostPerTraining)
    }

    // MARK: - AC3: blocked while asleep or sick

    func testTrainingIsBlockedWhileAsleep() {
        let state = makeState(strength: 20)

        let outcome = TrainAction.train(state, isAsleep: true)

        guard case .blocked(let reason) = outcome else {
            return XCTFail("expected a block, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "the block has to be able to explain itself on screen")
        XCTAssertEqual(state.strengthStat, 0, "nothing was gained")
        XCTAssertEqual(state.stageEnergy[.strength], 20, "and nothing was spent")
    }

    func testTrainingIsBlockedWhileSick() {
        let state = makeState(strength: 20)
        state.healthStatus = .sick

        let outcome = TrainAction.train(state, isAsleep: false)

        guard case .blocked(let reason) = outcome else {
            return XCTFail("expected a block, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(state.strengthStat, 0)
        XCTAssertEqual(state.stageEnergy[.strength], 20)
    }

    /// A dead Digimon cannot train either. US-029 owns death, but the rule already has to hold or
    /// a corpse would keep getting stronger between now and then.
    func testTrainingIsBlockedWhileDead() {
        let state = makeState(strength: 20)
        state.healthStatus = .dead

        guard case .blocked = TrainAction.train(state, isAsleep: false) else {
            return XCTFail("expected a block")
        }
        XCTAssertEqual(state.strengthStat, 0)
    }

    /// Asleep is checked before sickness, so a Digimon that is both is reported as asleep — the
    /// state that resolves itself by morning.
    func testAsleepAndSickIsReportedAsAsleep() {
        let state = makeState(strength: 20)
        state.healthStatus = .sick

        let sleeping = TrainAction.train(state, isAsleep: true)
        state.healthStatus = .healthy
        let awake = TrainAction.train(state, isAsleep: true)

        XCTAssertEqual(sleeping, awake, "the sleep reason wins either way")
    }

    // MARK: - Not enough energy

    /// Training is a purchase, so it can fail for want of funds — and that has to say so rather
    /// than silently doing nothing or driving an energy total negative.
    func testTrainingIsBlockedWithoutEnoughOfEitherEnergy() {
        let cost = TrainAction.energyCostPerTraining
        let state = makeState(strength: cost - 1, stamina: cost - 1)

        guard case .blocked = TrainAction.train(state, isAsleep: false) else {
            return XCTFail("expected a block")
        }
        XCTAssertEqual(state.stageEnergy[.strength], cost - 1)
        XCTAssertEqual(state.stageEnergy[.stamina], cost - 1)
        XCTAssertEqual(state.strengthStat, 0)
    }

    /// Exactly the cost is enough — the guard is `>=`, not `>`.
    func testExactlyTheCostIsEnoughToTrain() {
        let state = makeState(strength: TrainAction.energyCostPerTraining)

        XCTAssertEqual(TrainAction.train(state, isAsleep: false),
                       .trained(spent: .strength,
                                cost: TrainAction.energyCostPerTraining,
                                gain: TrainAction.strengthGainPerTraining))
        XCTAssertEqual(state.stageEnergy[.strength], 0)
    }
}

/// Fixtures for the apply layer. These fetchers exist because `HealthEnergySource` needs them and
/// the Simulator has no health data; every one hands back nothing, so no energy is ever credited
/// behind these tests' backs. Copied rather than shared — the ones in the other apply suites are
/// `private` to their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class TrainApplyTests: XCTestCase {
    private var storeDirectory: URL!
    private var trainHaptics = 0
    private var feedHaptics = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TrainingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        trainHaptics = 0
        feedHaptics = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve and every change to the saved
    /// game is training's doing alone. The egg exists only because `start()` resolves a starting
    /// Digitama before it loads and throws `.noDigitama` without one — even when a saved game exists.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    private func makeModel(url: URL) -> MainScreenModel {
        MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            calendar: Clock.calendar,
            now: { Clock.start },
            chooseStartingDigitama: { $0.first },
            playFeedHaptic: { [weak self] in self?.feedHaptics += 1 },
            playTrainHaptic: { [weak self] in self?.trainHaptics += 1 },
            // Milliseconds, so the revert to idle is observable without waiting out the app's 2s.
            actionDuration: 0.05
        )
    }

    /// Seeds a saved game at "hero" with the given Strength, then hands back a started model
    /// reading it off disk.
    private func startedModel(named name: String, strength: Int,
                              healthStatus: HealthStatus = .healthy) async throws -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.stageEnergy[.strength] = strength
        state.healthStatus = healthStatus
        try seeding.save()

        let model = makeModel(url: url)
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }

    // MARK: - AC2: the attack frame and the haptic

    /// Frame index 11 by name AND by number, because the number is what the sheet layout pins down —
    /// `.attack` naming a different index would draw the wrong art and still read fine here.
    ///
    /// Since US-083 the pose belongs to the round LANDING rather than to the button, so this plays a
    /// whole round: `train()` enters it and `finishTraining` grades it, which is exactly the pair the
    /// screen makes around the minigame.
    func testTrainingHoldsTheAttackFrameWithAHapticAndThenReturnsToIdle() async throws {
        let model = try await startedModel(named: "attack", strength: 20)

        XCTAssertEqual(model.train(), .started(spent: .strength,
                                               cost: TrainAction.energyCostPerTraining))
        model.finishTraining(.good)

        XCTAssertEqual(model.state?.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(model.animation, .still(.attack))
        XCTAssertEqual(model.animation.stageFrames, [.attack])
        XCTAssertEqual(SpriteFrame.attack.rawValue, 11)
        XCTAssertEqual(trainHaptics, 1)
        XCTAssertEqual(feedHaptics, 0, "training taps differently from feeding")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle, "the pose is held, not stuck")
    }

    // MARK: - AC1 / AC4 persistence

    func testATrainedStatAndItsCostArePersisted() async throws {
        let model = try await startedModel(named: "persist", strength: 20)
        model.train()
        model.finishTraining(.good)

        let reopened = try GameStore(url: storeURL("persist"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(saved.stageEnergy[.strength], 20 - TrainAction.energyCostPerTraining)
    }

    // MARK: - AC3: blocked with a visible reason

    func testTrainingWhileAsleepShowsAReasonAndDoesNotAnimate() async throws {
        let model = try await startedModel(named: "asleep", strength: 20)
        model.isAsleep = true

        guard case .blocked = model.train() else { return XCTFail("expected a block") }
        XCTAssertNotNil(model.actionMessage, "the reason is what the screen shows")
        // US-026 made the resting pose depend on the sleep window: nothing happened to it, so it
        // keeps RESTING, and a sleeping Digimon rests in the sleep loop rather than the walk loop.
        XCTAssertEqual(model.animation, .sleep)
        XCTAssertEqual(trainHaptics, 0)
        XCTAssertEqual(model.state?.strengthStat, 0)
    }

    func testTrainingWhileSickShowsAReasonAndDoesNotPlayTheAttackPose() async throws {
        let model = try await startedModel(named: "sick", strength: 20, healthStatus: .sick)

        guard case .blocked = model.train() else { return XCTFail("expected a block") }
        XCTAssertNotNil(model.actionMessage)
        // US-028 made the resting pose depend on health too, the same way US-026 made it depend on
        // the sleep window above: nothing happened to it, so it keeps RESTING, and since US-068 a
        // sick Digimon rests on the slow hurt loop. The point is that the ATTACK pose never
        // appears — showing it would read as the blocked training having half-worked.
        XCTAssertEqual(model.animation, .sick)
        XCTAssertEqual(trainHaptics, 0)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 20)
    }
}
