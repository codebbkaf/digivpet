import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-025 / US-177 — training.
///
/// US-177 repriced training: a session no longer spends Strength/Stamina energy, it spends one
/// training charge banked from active calories (`GameState.trainCharges`). These tests pin the new
/// currency — one charge per session, blocked at zero, energy left untouched — while keeping the
/// original pose/haptic/persistence coverage.
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
/// `strength`/`stamina` are seeded so the tests can prove training leaves them ALONE now that the
/// currency is a charge rather than energy.
private func makeState(trainCharges: Int = 0, strength: Int = 0, stamina: Int = 0) -> GameState {
    let state = GameState(currentDigimonId: "hero", stage: .babyI, now: Clock.start)
    state.trainCharges = trainCharges
    state.stageEnergy[.strength] = strength
    state.stageEnergy[.stamina] = stamina
    return state
}

final class TrainActionTests: XCTestCase {

    // MARK: - AC2: raises strengthStat, spends one charge, no energy

    func testTrainingRaisesStrengthStatAndSpendsOneCharge() {
        let state = makeState(trainCharges: 3, strength: 20, stamina: 20)

        let outcome = TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(outcome, .trained(gain: TrainAction.strengthGainPerTraining))
        XCTAssertEqual(state.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(state.trainCharges, 2, "exactly one charge spent")
        XCTAssertEqual(state.stageEnergy[.strength], 20, "no Strength energy spent")
        XCTAssertEqual(state.stageEnergy[.stamina], 20, "no Stamina energy spent")
    }

    /// The energies training used to spend are now spent by nothing at all — Vitality is feeding's,
    /// Spirit is sleep, and the physical pair is left standing for battling. Pins that a session
    /// touches none of the four.
    func testTrainingSpendsNoneOfTheFourEnergies() {
        let state = makeState(trainCharges: 1, strength: 20, stamina: 15)
        state.stageEnergy[.vitality] = 40
        state.stageEnergy[.spirit] = 30

        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.stageEnergy[.strength], 20)
        XCTAssertEqual(state.stageEnergy[.stamina], 15)
        XCTAssertEqual(state.stageEnergy[.vitality], 40)
        XCTAssertEqual(state.stageEnergy[.spirit], 30)
    }

    /// `lifetimeEnergy` is the record of what was ever EARNED, so training must not rewrite it.
    /// Since US-123 the total is on `PlayerProfile`, which `TrainAction` is never handed — so
    /// this pins the API shape as much as the arithmetic.
    func testTrainingDoesNotTakeBackLifetimeEnergy() {
        let state = makeState(trainCharges: 1, strength: 20)
        let profile = PlayerProfile()
        profile.lifetimeEnergy[.strength] = 90

        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(profile.lifetimeEnergy[.strength], 90)
    }

    /// Sessions accumulate — the stat is a running total, not a flag — and each spends a charge.
    func testRepeatedTrainingAccumulatesAndSpendsACharge() {
        let state = makeState(trainCharges: 3)

        TrainAction.train(state, isAsleep: false)
        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.strengthStat, 2 * TrainAction.strengthGainPerTraining)
        XCTAssertEqual(state.trainCharges, 1, "two sessions, two charges")
    }

    // MARK: - AC3: blocked while asleep or sick

    func testTrainingIsBlockedWhileAsleep() {
        let state = makeState(trainCharges: 3)

        let outcome = TrainAction.train(state, isAsleep: true)

        guard case .blocked(let reason) = outcome else {
            return XCTFail("expected a block, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "the block has to be able to explain itself on screen")
        XCTAssertEqual(state.strengthStat, 0, "nothing was gained")
        XCTAssertEqual(state.trainCharges, 3, "and no charge was spent")
    }

    func testTrainingIsBlockedWhileSick() {
        let state = makeState(trainCharges: 3)
        state.healthStatus = .sick

        let outcome = TrainAction.train(state, isAsleep: false)

        guard case .blocked(let reason) = outcome else {
            return XCTFail("expected a block, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(state.strengthStat, 0)
        XCTAssertEqual(state.trainCharges, 3)
    }

    /// A dead Digimon cannot train either. US-029 owns death, but the rule already has to hold or
    /// a corpse would keep getting stronger between now and then.
    func testTrainingIsBlockedWhileDead() {
        let state = makeState(trainCharges: 3)
        state.healthStatus = .dead

        guard case .blocked = TrainAction.train(state, isAsleep: false) else {
            return XCTFail("expected a block")
        }
        XCTAssertEqual(state.strengthStat, 0)
        XCTAssertEqual(state.trainCharges, 3)
    }

    /// Asleep is checked before sickness, so a Digimon that is both is reported as asleep — the
    /// state that resolves itself by morning.
    func testAsleepAndSickIsReportedAsAsleep() {
        let state = makeState(trainCharges: 3)
        state.healthStatus = .sick

        let sleeping = TrainAction.train(state, isAsleep: true)
        state.healthStatus = .healthy
        let awake = TrainAction.train(state, isAsleep: true)

        XCTAssertEqual(sleeping, awake, "the sleep reason wins either way")
    }

    // MARK: - AC2: no charge

    /// Training is a purchase, so it can fail for want of a charge — and that has to say so rather
    /// than silently doing nothing. The sleep and sickness checks run first, so a healthy waking
    /// Digimon at zero charges is the one that reaches this arm.
    func testTrainingIsBlockedWithoutACharge() {
        let state = makeState(trainCharges: 0, strength: 100, stamina: 100)

        guard case .blocked(let reason) = TrainAction.train(state, isAsleep: false) else {
            return XCTFail("expected a block")
        }
        XCTAssertEqual(reason, TrainAction.noChargeReason,
                       "the run-out says how to earn more, however much energy is on hand")
        XCTAssertEqual(state.strengthStat, 0)
        XCTAssertEqual(state.trainCharges, 0, "cannot go negative")
    }

    /// Exactly one charge is enough — the guard is `> 0`.
    func testExactlyOneChargeIsEnoughToTrain() {
        let state = makeState(trainCharges: 1)

        XCTAssertEqual(TrainAction.train(state, isAsleep: false),
                       .trained(gain: TrainAction.strengthGainPerTraining))
        XCTAssertEqual(state.trainCharges, 0)
    }

    /// The session is counted only when the round actually starts — a zero-charge tap must not tick
    /// `stageTrainingSessions`, which an evolution branch reads.
    func testABlockedSessionIsNotCounted() {
        let state = makeState(trainCharges: 0)
        TrainAction.train(state, isAsleep: false)
        XCTAssertEqual(state.stageTrainingSessions, 0)

        state.trainCharges = 1
        TrainAction.train(state, isAsleep: false)
        XCTAssertEqual(state.stageTrainingSessions, 1, "a paid round is counted")
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

    /// Seeds a saved game at "hero" with the given training charges, then hands back a started model
    /// reading it off disk.
    private func startedModel(named name: String, trainCharges: Int,
                              healthStatus: HealthStatus = .healthy) async throws -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.trainCharges = trainCharges
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
        let model = try await startedModel(named: "attack", trainCharges: 3)

        XCTAssertEqual(model.train(), .started)
        model.finishTraining(.good)

        XCTAssertEqual(model.state?.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(model.animation, .pose(.attack))
        XCTAssertEqual(model.animation.stageFrames, [.attack, .walk1])
        XCTAssertEqual(SpriteFrame.attack.rawValue, 11)
        XCTAssertEqual(trainHaptics, 1)
        XCTAssertEqual(feedHaptics, 0, "training taps differently from feeding")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle, "the pose is held, not stuck")
    }

    // MARK: - AC1 / AC2 persistence

    func testATrainedStatAndItsSpentChargeArePersisted() async throws {
        let model = try await startedModel(named: "persist", trainCharges: 3)
        model.train()
        model.finishTraining(.good)

        let reopened = try GameStore(url: storeURL("persist"))
        let saved = try reopened.loadOrCreate(digitamaId: "hero", now: Clock.start)
        XCTAssertEqual(saved.strengthStat, TrainAction.strengthGainPerTraining)
        XCTAssertEqual(saved.trainCharges, 2, "the spent charge reached disk")
    }

    // MARK: - AC3: blocked with a visible reason

    /// US-025 AC3 used to read "blocked while asleep". US-110 reversed it for the same reason it
    /// reversed the feed: the mistake was being charged for an action that never happened. The round
    /// now OPENS, the charge is spent, and the disturbance is charged too.
    func testTrainingWhileAsleepWakesTheDigimonAndOpensTheRound() async throws {
        let model = try await startedModel(named: "asleep", trainCharges: 3)
        model.isAsleep = true
        let mistakesBefore = try XCTUnwrap(model.state?.careMistakeCount)

        guard case .started = try XCTUnwrap(model.train()) else {
            return XCTFail("expected the round to open")
        }
        XCTAssertFalse(model.isAsleep, "prodding it woke it")
        XCTAssertNotNil(model.pendingTraining, "and the minigame is on screen")
        XCTAssertEqual(model.state?.trainCharges, 2, "the round was paid for")
        XCTAssertEqual(model.state?.careMistakeCount, mistakesBefore + 1)
        XCTAssertEqual(model.state?.stageSleepDisturbances, 1)
    }

    func testTrainingWhileSickShowsAReasonAndDoesNotPlayTheAttackPose() async throws {
        let model = try await startedModel(named: "sick", trainCharges: 3, healthStatus: .sick)

        guard case .blocked = model.train() else { return XCTFail("expected a block") }
        XCTAssertNotNil(model.actionMessage)
        // US-028 made the resting pose depend on health too, the same way US-026 made it depend on
        // the sleep window above: nothing happened to it, so it keeps RESTING, and since US-068 a
        // sick Digimon rests on the slow hurt loop. The point is that the ATTACK pose never
        // appears — showing it would read as the blocked training having half-worked.
        XCTAssertEqual(model.animation, .sick)
        XCTAssertEqual(trainHaptics, 0)
        XCTAssertEqual(model.state?.trainCharges, 3, "nothing spent")
    }

    /// AC2: at zero charges the Train button is unavailable and says so — the round never opens and
    /// nothing is spent.
    func testTrainingAtZeroChargesIsBlockedAndSaysSo() async throws {
        let model = try await startedModel(named: "broke", trainCharges: 0)

        guard case .blocked(let reason) = try XCTUnwrap(model.train()) else {
            return XCTFail("expected a block")
        }
        XCTAssertEqual(reason, TrainAction.noChargeReason)
        XCTAssertNil(model.pendingTraining, "no round opened")
        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertEqual(trainHaptics, 0)
    }
}

/// US-177 — active calories into training charges, tested pure so the conversion, cap and
/// remainder-carry rules hold without a screen. 50 kcal buys one charge, up to a ceiling of 10.
final class TrainChargeCreditTests: XCTestCase {
    private func freshState() -> GameState {
        GameState(currentDigimonId: "hero", now: Date(timeIntervalSince1970: 0))
    }

    /// THE AC headline: 150 injected kcal is three charges.
    func test150KcalYieldsThreeCharges() {
        let state = freshState()
        state.creditTrainCharges(kcal: 150, kcalPerCharge: 50, maxCharges: 10)
        XCTAssertEqual(state.trainCharges, 3)
        XCTAssertEqual(state.trainChargeKcal, 0, "a hundred and fifty is a clean three, no remainder")
    }

    /// The ceiling: 550 kcal would be eleven charges, so it caps at ten and drops the overflow rather
    /// than banking a remainder toward an uncollectable eleventh.
    func test550KcalCapsAtTen() {
        let state = freshState()
        state.creditTrainCharges(kcal: 550, kcalPerCharge: 50, maxCharges: 10)
        XCTAssertEqual(state.trainCharges, 10, "capped, not eleven")
        XCTAssertEqual(state.trainChargeKcal, 0, "no remainder is hoarded at the cap")
    }

    /// Sub-threshold efforts are not thrown away between reads: 30 kcal now and 30 later is not yet a
    /// charge but is banked toward one — a health reading arrives as many small deltas.
    func testSubThresholdEffortsAccumulateAcrossReads() {
        let state = freshState()
        state.creditTrainCharges(kcal: 30, kcalPerCharge: 50, maxCharges: 10)
        XCTAssertEqual(state.trainCharges, 0, "thirty kcal is not yet a charge")
        XCTAssertEqual(state.trainChargeKcal, 30, "but it is banked toward the next one")

        state.creditTrainCharges(kcal: 30, kcalPerCharge: 50, maxCharges: 10)
        XCTAssertEqual(state.trainCharges, 1, "and the two reads together cross the threshold")
        XCTAssertEqual(state.trainChargeKcal, 10, "with the change carried on")
    }

    /// AC: a second Digimon's charges are independent — the store lives on each `GameState`, so one
    /// is never spending the other's.
    func testTwoDigimonChargesAreIndependent() {
        let mover = freshState()
        let idler = freshState()
        mover.creditTrainCharges(kcal: 150, kcalPerCharge: 50, maxCharges: 10)
        idler.creditTrainCharges(kcal: 20, kcalPerCharge: 50, maxCharges: 10)

        XCTAssertEqual(mover.trainCharges, 3)
        XCTAssertEqual(idler.trainCharges, 0, "the one that sat still earned nothing")
        // And spending from one leaves the other alone.
        TrainAction.train(mover, isAsleep: false)
        XCTAssertEqual(mover.trainCharges, 2, "training decremented by one")
        XCTAssertEqual(idler.trainCharges, 0)
    }
}
