import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-218 — Feed, Train and Battle are refused while the Digimon is still an egg.
///
/// Driven through the real model and the real store, like `WanderingTests`: the egg is reached by
/// `loadOrCreate`ing the Digitama and leaving it alone, which is how the app reaches it.
///
/// The subject of every test here is what a blocked action DOES NOT do. An egg guard that merely
/// showed the message while the charge was still spent would pass a "returns blocked" assertion on
/// its own, so each case asserts the whole ledger — meat, charges, energy and the care-mistake
/// counter — is exactly where it was.
///
/// No test waits real time: the clock is a chosen `Date` and the action hold is milliseconds.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// Empty fetchers, so no health data can move the model behind these tests' backs. Copied rather
/// than shared, as in every other apply suite: the equivalents there are `private` to their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// Everything a blocked action must leave alone, read off the model in one go so a test can compare
/// two readings rather than list six assertions per call.
private struct Ledger: Equatable {
    var meat: Int
    var trainCharges: Int
    var battleCharges: Int
    var energy: [EnergyType: Int]
    var careMistakes: Int
    var overfeeds: Int
    var trainingSessions: Int
    var sleepDisturbances: Int

    @MainActor
    init(_ model: MainScreenModel) {
        let state = model.state
        meat = model.profile?.meat ?? -1
        trainCharges = state?.trainCharges ?? -1
        battleCharges = state?.battleCharges ?? -1
        energy = EnergyType.allCases.reduce(into: [:]) { $0[$1] = state?.stageEnergy[$1] ?? -1 }
        careMistakes = state?.careMistakeCount ?? -1
        overfeeds = state?.stageOverfeeds ?? -1
        trainingSessions = state?.stageTrainingSessions ?? -1
        sleepDisturbances = state?.stageSleepDisturbances ?? -1
    }
}

@MainActor
final class EggActionsTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EggActionsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// An egg and a Baby I with nothing to evolve into, so no hatch or evolution can change the
    /// stage mid-test and decide a case for reasons this file is not about.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 999, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    /// A started model on a fresh save, stocked so that NOTHING but the stage can block an action:
    /// hungry, with meat in the larder, both charges full and energy to spend. That is the point —
    /// when the egg case blocks, the only possible reason is the egg.
    private func startedModel(named name: String, hatched: Bool) async throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("\(name).store")
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "egg", now: Clock.start)
        if hatched {
            state.currentDigimonId = "hero"
            state.stage = .babyI
        }
        state.hunger = 3
        try seeding.save()

        let model = MainScreenModel(
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
            // Milliseconds, so the revert to idle is observable without waiting out the app's 2s.
            actionDuration: 0.05
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        model.profile?.meat = 10
        model.state?.trainCharges = ConsumptionConfig.bundled.maxTrainCharges
        model.state?.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        model.state?.stageEnergy[.vitality] = 40
        model.state?.stageEnergy[.strength] = 40
        model.state?.stageEnergy[.stamina] = 40
        XCTAssertEqual(model.state?.stage, hatched ? .babyI : .digitama)
        return model
    }

    // MARK: - AC: the model refuses all three at .digitama

    func testFeedingAnEggIsBlockedAndSpendsNothing() async throws {
        let model = try await startedModel(named: "feed-egg", hatched: false)
        let before = Ledger(model)

        let outcome = model.feed()

        XCTAssertEqual(outcome, .blocked(reason: MainScreenModel.eggActionReason))
        XCTAssertEqual(model.actionMessage, MainScreenModel.eggActionReason)
        XCTAssertEqual(Ledger(model), before, "a blocked feed spends no meat and counts no overfeed")
        XCTAssertEqual(model.state?.hunger, 3, "and does not feed it either")
    }

    func testTrainingAnEggIsBlockedAndOpensNoMinigame() async throws {
        let model = try await startedModel(named: "train-egg", hatched: false)
        let before = Ledger(model)

        let start = model.train()

        XCTAssertEqual(start, .blocked(reason: MainScreenModel.eggActionReason))
        XCTAssertEqual(model.actionMessage, MainScreenModel.eggActionReason)
        XCTAssertNil(model.pendingTraining, "a round that was never paid for must not open")
        XCTAssertEqual(Ledger(model), before, "a blocked training spends no charge and counts no session")
    }

    func testBattlingAsAnEggIsBlockedAndOpensNoRound() async throws {
        let model = try await startedModel(named: "battle-egg", hatched: false)
        let before = Ledger(model)

        let game = model.battle()

        XCTAssertNil(game)
        XCTAssertEqual(model.actionMessage, MainScreenModel.eggActionReason)
        XCTAssertNil(model.pendingBattleRound, "no opponent was picked, so no round may be on screen")
        XCTAssertNil(model.pendingBattle)
        XCTAssertEqual(Ledger(model), before, "a blocked battle spends no charge and no energy")
    }

    /// The guard runs before the pose and the motion as well as before the ledger: a blocked action
    /// is a message and nothing else, exactly as every other `.blocked` outcome is drawn.
    func testABlockedEggActionPlaysNoPoseAndNoMotion() async throws {
        let model = try await startedModel(named: "egg-still", hatched: false)

        for act in [{ _ = model.feed() }, { _ = model.train() }, { _ = model.battle() }] {
            act()
            XCTAssertEqual(model.animation, .idle, "the egg keeps its own resting loop")
            XCTAssertNil(model.actionMotion, "and does not lurch about while being refused")
        }
    }

    // MARK: - AC: the same three calls at .babyI are untouched

    func testFeedingAHatchedDigimonStillFeedsIt() async throws {
        let model = try await startedModel(named: "feed-baby", hatched: true)

        XCTAssertEqual(model.feed(), .fed)
        XCTAssertEqual(model.animation, .eat)
        XCTAssertEqual(model.state?.hunger, 2)
        XCTAssertEqual(model.profile?.meat, 9, "one meat, as before")
    }

    func testTrainingAHatchedDigimonStillOpensItsRound() async throws {
        let model = try await startedModel(named: "train-baby", hatched: true)
        let charges = model.state?.trainCharges ?? 0

        XCTAssertEqual(model.train(), .started)
        XCTAssertNotNil(model.pendingTraining, "the minigame still opens past the egg stage")
        XCTAssertEqual(model.state?.trainCharges, charges - 1)
        XCTAssertEqual(model.state?.stageTrainingSessions, 1)
    }

    func testBattlingAsAHatchedDigimonStillStartsTheRound() async throws {
        let model = try await startedModel(named: "battle-baby", hatched: true)
        let charges = model.state?.battleCharges ?? 0

        XCTAssertNotNil(model.battle(), "the bout must actually start, or this proves nothing")
        XCTAssertNotNil(model.pendingBattleRound)
        XCTAssertEqual(model.state?.battleCharges, charges - 1)
    }

    // MARK: - AC: one fact, three readers

    /// `isEgg` is what the buttons are greyed from and what the three guards ask, so it is worth
    /// pinning that it tracks the stage rather than anything else — hatching turns all three back on
    /// at once.
    func testIsEggTracksTheStageAndHatchingClearsIt() async throws {
        let model = try await startedModel(named: "is-egg", hatched: false)
        XCTAssertTrue(model.isEgg)

        model.state?.currentDigimonId = "hero"
        model.state?.stage = .babyI

        XCTAssertFalse(model.isEgg)
        XCTAssertEqual(model.feed(), .fed, "and the actions come back with the stage")
    }
}
