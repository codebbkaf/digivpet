import Foundation
import XCTest

@testable import DigiVPet

/// US-203 — each map has a boss that gates the next map.
///
/// The trigger conditions (steps done AND every resident met), the win-unlock, and the 1,000-step
/// loss penalty are all driven against the real `MainScreenModel` over a real store, because every
/// criterion is about what the map's recorded counter and finish stamp say. No test here waits real
/// time: the clock is injected and the "step source" is the map's recorded total, seeded directly, the
/// same way `WildEncounterTests` proves US-201.
///
/// The fixture pits deliberately lopsided pairs so a battle's outcome is certain regardless of the
/// seed — an Ultimate hero against a Baby-I boss is a sure win, a Baby-I hero against an Ultimate boss
/// a sure loss — exactly as `WildEncounterTests` does, which is what lets the win-unlock and the
/// loss-penalty each be asserted for real.
@MainActor
final class BossEncounterTests: XCTestCase {
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

    /// Mid-morning, stated as a wall-clock time so the fallback 22:00–07:00 sleep window cannot swallow
    /// the whole suite — the same care the other battle suites take.
    private static let now: Date = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "2026-07-17 10:00")!
    }()

    private static let winMap = "winmap"
    private static let nextMap = "nextmap"
    private static let lossMap = "lossmap"
    private static let weakling = "weakling"
    private static let midling = "midling"
    private static let titan = "titan"

    /// A hero, an egg for `start()` to name, and residents at three rungs so the boss (highest stage)
    /// is unambiguous and the two extreme fights are certain.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: Self.weakling, displayName: "Weakling", stage: .babyI, spriteFile: "Botamon"),
            EvolutionNode(id: Self.midling, displayName: "Midling", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: Self.titan, displayName: "Titan", stage: .ultimate, spriteFile: "Metalgreymon"),
        ])
    }

    /// One short map whose only resident is the Baby-I (so its boss is a sure loss for a strong hero
    /// and a win for the player), a map gated behind it, and a short map whose only resident is the
    /// Ultimate (a sure win for the boss, a loss for the player).
    private func fixtureCatalog() -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(id: Self.winMap, displayName: "Win", assetName: "01_grassland",
                         tier: 1, totalSteps: 1_000, opponentPool: [Self.weakling]),
            AdventureMap(id: Self.nextMap, displayName: "Next", assetName: "02_river",
                         tier: 2, totalSteps: 1_000, unlockedBy: Self.winMap, opponentPool: [Self.midling]),
            AdventureMap(id: Self.lossMap, displayName: "Loss", assetName: "03_snow",
                         tier: 5, totalSteps: 1_000, opponentPool: [Self.titan]),
        ])
    }

    private func makeModel(stage: Stage = .ultimate,
                           strength: Int = 30,
                           seed: UInt64 = 1) throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("Boss.store")
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.now)
        state.stage = stage
        state.strengthStat = strength
        // US-027: the empty readers would otherwise have the audit charge a mistake for every day
        // since the epoch, sickening the Digimon before a boss could land.
        state.healthDataLastSeen = Self.now
        state.hungerUpdatedAt = Self.now
        state.stageEnteredDate = Self.now
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            maps: fixtureCatalog(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { Self.now },
            chooseStartingDigitama: { $0.first },
            makeBattleGenerator: { SeededGenerator(seed: seed) }
        )
        return model
    }

    /// Selects the map and puts `steps` on its counter, as a day of walking would.
    private func walked(_ steps: Double, into mapId: String, on model: MainScreenModel) {
        model.selectMap(mapId)
        model.profile?.record(steps: steps, forMap: mapId)
    }

    /// Marks every resident of the map met — the state a player reaches by fighting or 500-step
    /// meeting each of them (US-202). Recorded straight so the boss trigger can be exercised without
    /// walking out a chain of wild encounters. The catalog and graph are the same shape the model
    /// holds (all residents are graph nodes, so the roster is never consulted), so `.bundled` is a
    /// safe stand-in for the fallback.
    private func metEveryResident(of mapId: String, on model: MainScreenModel) throws {
        let map = try XCTUnwrap(fixtureCatalog().map(id: mapId))
        let residents = MapOpponentBand.residents(of: map, graph: fixtureGraph(),
                                                  roster: .bundled, excluding: "hero")
        for resident in residents {
            model.profile?.recordMet(resident.id, forMap: mapId)
        }
    }

    // MARK: - AC3: the boss is the highest-stage resident

    func testTheBossIsTheHighestStageResident() {
        let map = AdventureMap(id: "m", displayName: "M", assetName: "01_grassland", tier: 1,
                               totalSteps: 1_000,
                               opponentPool: [Self.weakling, Self.midling, Self.titan])
        let boss = MapOpponentBand.boss(of: map, graph: fixtureGraph(), roster: .bundled,
                                        excluding: "hero")
        XCTAssertEqual(boss?.id, Self.titan, "the Ultimate is the boss, not the Baby-I or the Child")
    }

    // MARK: - AC1: the boss appears only once both conditions hold

    func testStepsShortOfTheTotalRaiseNoBossThenTheTotalTipsIt() async throws {
        let model = try makeModel()
        await model.start()

        walked(999, into: Self.winMap, on: model)
        try metEveryResident(of: Self.winMap, on: model)
        model.checkForBossEncounter()
        XCTAssertNil(model.pendingBossEncounter, "999 of 1,000 is not the whole map, even all-met")

        model.profile?.record(steps: 1, forMap: Self.winMap) // 1,000 now
        model.checkForBossEncounter()
        let boss = try XCTUnwrap(model.pendingBossEncounter,
                                 "the total is reached and every resident met — the boss stands up")
        XCTAssertEqual(boss.opponent.node.id, Self.weakling, "the boss is the map's top resident")
        XCTAssertEqual(boss.mapId, Self.winMap)
        XCTAssertEqual(boss.presentation.displayName, "Weakling")
    }

    /// The steps without the meetings raise nothing: a player who sprinted the whole map but has not
    /// met its residents has no boss yet.
    func testStepsWithoutMeetingEveryResidentRaiseNoBoss() async throws {
        let model = try makeModel()
        await model.start()
        walked(2_000, into: Self.winMap, on: model) // well past the 1,000 total

        model.checkForBossEncounter()

        XCTAssertNil(model.pendingBossEncounter, "the residents are unmet, so the boss does not appear")
    }

    /// The boss fires on refresh — the app coming to the front — so a boss that came due while the app
    /// was closed is waiting the moment it opens.
    func testTheBossFiresOnRefresh() async throws {
        let model = try makeModel()
        await model.start()
        walked(1_500, into: Self.winMap, on: model)
        try metEveryResident(of: Self.winMap, on: model)

        await model.refresh()

        XCTAssertNotNil(model.pendingBossEncounter, "the refresh raised the boss")
    }

    // MARK: - AC4: winning finishes the map and unlocks the next

    func testWinningTheBossFinishesTheMapAndUnlocksTheNext() async throws {
        let model = try makeModel(stage: .ultimate, strength: 30)
        await model.start()
        walked(1_200, into: Self.winMap, on: model)
        try metEveryResident(of: Self.winMap, on: model)
        model.checkForBossEncounter()

        let bout = try XCTUnwrap(model.acceptBossEncounter(), "the boss fight resolves")
        XCTAssertTrue(bout.report.playerWon, "the Ultimate beats the Baby-I boss")

        let profile = try XCTUnwrap(model.profile)
        XCTAssertTrue(profile.isFinished(forMap: Self.winMap), "a boss win finishes the map")
        XCTAssertEqual(profile.finishedAt(forMap: Self.winMap), Self.now, "stamped at the win")
        XCTAssertEqual(profile.recorded(forMap: Self.winMap), 1_200, "a win costs no steps")
        XCTAssertNil(model.pendingBossEncounter, "the dialog is gone")
        XCTAssertEqual(model.pendingBattle, bout, "the fight replays over the same spot")

        // The next map, locked until this boss fell, is now open.
        let catalog = fixtureCatalog()
        let next = try XCTUnwrap(catalog.map(id: Self.nextMap))
        XCTAssertTrue(MapListRow.isUnlocked(next, in: catalog, progress: profile),
                      "beating the boss unlocks the next map")
    }

    // MARK: - AC5: losing knocks 1,000 steps off, and the boss can be re-challenged

    func testLosingTheBossCostsTheMap1000StepsAndDoesNotFinishIt() async throws {
        let model = try makeModel(stage: .babyI, strength: 0)
        await model.start()
        walked(1_200, into: Self.lossMap, on: model)
        try metEveryResident(of: Self.lossMap, on: model)
        model.checkForBossEncounter()

        let bout = try XCTUnwrap(model.acceptBossEncounter())
        XCTAssertFalse(bout.report.playerWon, "the Baby-I loses to the Ultimate boss")
        // The loss replays on `pendingBattle`; dismissing it is what the player does on the result
        // screen, and the boss cannot re-appear over a battle still on screen (its own guard).
        model.finishBattle()

        let profile = try XCTUnwrap(model.profile)
        XCTAssertEqual(profile.recorded(forMap: Self.lossMap), 200, "1,200 minus the 1,000 loss penalty")
        XCTAssertFalse(profile.isFinished(forMap: Self.lossMap), "a loss does not finish the map")

        // Below the total now, so the boss does not stand up again until the map is walked back up.
        model.checkForBossEncounter()
        XCTAssertNil(model.pendingBossEncounter, "200 of 1,000 is short again")

        model.profile?.record(steps: 800, forMap: Self.lossMap) // back to 1,000
        model.checkForBossEncounter()
        XCTAssertNotNil(model.pendingBossEncounter, "re-challengeable once the total holds again")
    }

    // MARK: - AC6: the map is not finished by steps alone

    func testUntilTheBossIsBeatenTheMapIsNotFinished() async throws {
        let model = try makeModel()
        await model.start()
        walked(5_000, into: Self.winMap, on: model) // far past the total
        try metEveryResident(of: Self.winMap, on: model)

        let profile = try XCTUnwrap(model.profile)
        XCTAssertFalse(profile.isFinished(forMap: Self.winMap),
                       "the step total is well past, but the boss is unbeaten")
        let catalog = fixtureCatalog()
        let next = try XCTUnwrap(catalog.map(id: Self.nextMap))
        XCTAssertFalse(MapListRow.isUnlocked(next, in: catalog, progress: profile),
                       "so the next map stays locked")
    }

    // MARK: - Guards

    func testNoBossOnAFinishedMap() async throws {
        let model = try makeModel()
        await model.start()
        walked(1_200, into: Self.winMap, on: model)
        try metEveryResident(of: Self.winMap, on: model)
        model.profile?.markFinished(Self.winMap, at: Self.now) // already beaten

        model.checkForBossEncounter()

        XCTAssertNil(model.pendingBossEncounter, "a finished map raises no boss")
    }

    func testNoBossWithoutAMapSelected() async throws {
        let model = try makeModel()
        await model.start()
        // Steps and meetings recorded against a map, but nothing selected: no place to be gated.
        model.profile?.record(steps: 2_000, forMap: Self.winMap)
        try metEveryResident(of: Self.winMap, on: model)

        model.checkForBossEncounter()

        XCTAssertNil(model.pendingBossEncounter)
    }

    func testNoSecondBossWhileOneIsAlreadyPending() async throws {
        let model = try makeModel()
        await model.start()
        walked(2_000, into: Self.winMap, on: model)
        try metEveryResident(of: Self.winMap, on: model)
        model.checkForBossEncounter()
        let first = try XCTUnwrap(model.pendingBossEncounter)

        model.checkForBossEncounter()

        XCTAssertEqual(model.pendingBossEncounter, first, "a second check does not replace the boss")
    }
}

// MARK: - Fixtures

private final class NoSamples: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class NoSleep: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
