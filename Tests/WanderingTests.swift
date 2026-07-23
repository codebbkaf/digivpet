import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-037 — when the Digimon is allowed to walk about the main screen.
///
/// The walk ITSELF is `MovementTests`' subject; this file is only about `MainScreenModel`'s
/// suspension rule, driven through the real model and the real store so each state is reached the
/// way the app reaches it rather than by setting `animation` by hand.
///
/// The sleeping case is deliberately NOT here: it lives in `SleepStateTests`, where the sleep
/// history that derives the state already exists, so it can be driven from a real night of sleep
/// instead of a flag.
///
/// No test waits real time — the clock is chosen `Date`s and the action hold is milliseconds.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// Empty fetchers, so no health data can move the model behind these tests' backs. Copied rather
/// than shared: the equivalents in the other apply suites are `private` to their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class WanderingTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WanderingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve mid-test and change the pose for
    /// reasons this file is not about. The egg exists only because `start()` resolves a starting
    /// Digitama before it loads.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    /// A started model reading a saved game at "hero", hungry and with Vitality to spend, so it can
    /// be fed without the feed being refused or blocked.
    private func startedModel(named name: String) async throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("\(name).store")
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.hunger = 3
        state.stageEnergy[.vitality] = 20
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
        // Feeding spends meat since US-174; stock the larder so a fed test eats rather than blocks.
        model.profile?.meat = 10
        // Battling spends a charge since US-176; stock it so a battle test fights rather than blocks.
        model.state?.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        return model
    }

    // MARK: - AC: movement runs by default

    /// The control for every test below. Without this, a rule that suspended movement
    /// unconditionally would satisfy all of them.
    func testAHealthyIdleDigimonWanders() async throws {
        let model = try await startedModel(named: "idle")

        XCTAssertEqual(model.animation, .idle)
        XCTAssertTrue(model.isWandering)
    }

    // MARK: - AC: suspended while eating, and resumes after

    func testEatingSuspendsMovementAndFinishingResumesIt() async throws {
        let model = try await startedModel(named: "eating")

        model.feed()
        XCTAssertEqual(model.animation, .eat)
        XCTAssertFalse(model.isWandering, "a Digimon holding still to eat must not slide about")

        // The model's own hold expiring is what puts it back to idle — nothing here resets it.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.animation, .idle)
        XCTAssertTrue(model.isWandering, "and the walk resumes once the meal is over")
    }

    // MARK: - AC: suspended while sick and while dead

    func testASickDigimonDoesNotWander() async throws {
        let model = try await startedModel(named: "sick")

        model.state?.healthStatus = .sick
        await model.refresh()

        // US-068 AC2. The sick pose is a LOOP now rather than a held frame, so this is no longer
        // free — the sprite animates in place, and `isWandering` is what stops it also travelling.
        XCTAssertEqual(model.animation, .sick)
        XCTAssertFalse(model.isWandering)
    }

    func testADeadDigimonDoesNotWander() async throws {
        let model = try await startedModel(named: "dead")

        model.state?.healthStatus = .dead
        await model.refresh()

        XCTAssertEqual(model.animation, .still(.hurt2))
        XCTAssertFalse(model.isWandering, "a dead Digimon must not go for a walk")
    }

    // MARK: - AC: suspended behind an overlay

    /// A battle covers the screen, so the sprite underneath has nothing to walk for. Checked
    /// through the real `battle()` and cleared through the real `finishBattle()`, so this tracks
    /// what the screen actually does rather than a flag set by hand.
    func testABattleOverlaySuspendsMovementUntilItIsFinished() async throws {
        let model = try await startedModel(named: "battle")
        model.state?.stageEnergy[.strength] = 40

        XCTAssertNotNil(model.battle(), "the bout must actually start, or this proves nothing")
        XCTAssertFalse(model.isWandering, "nothing to walk for behind the pre-battle round either")

        model.finishBattleRound(.good)
        XCTAssertNotNil(model.pendingBattle)
        XCTAssertFalse(model.isWandering, "nothing to walk for behind a full-screen battle")

        model.finishBattle()
        XCTAssertNil(model.pendingBattle)
        XCTAssertTrue(model.isWandering, "and the walk resumes when the battle comes down")
    }
}
