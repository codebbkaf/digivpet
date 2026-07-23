import Foundation
import XCTest

@testable import DigiVPet

/// US-201 — a wild battle greets you after 500 more steps.
///
/// The trigger, the flee penalty and the win/loss penalty are all driven against the real
/// `MainScreenModel` over a real store, because every criterion is about what the map's recorded
/// counter says and what is saved. No test here waits real time: the clock is injected and the "step
/// source" is the map's recorded total, seeded directly, exactly as US-201 promises.
///
/// The fixture pits a deliberately lopsided pair so a battle's outcome is certain regardless of the
/// seed — an Ultimate hero against a Baby-I is a sure win, a Baby-I hero against an Ultimate a sure
/// loss — which is what lets the win-branch and loss-branch each be asserted for real.
@MainActor
final class WildEncounterTests: XCTestCase {
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
    /// the whole suite — the same care `PreBattleRoundTests` takes.
    private static let now: Date = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "2026-07-17 10:00")!
    }()

    private static let winMap = "winmap"
    private static let lossMap = "lossmap"
    private static let weakling = "weakling"
    private static let titan = "titan"

    /// A hero, an egg for `start()` to have a Digitama to name, and two opponents at the extremes of
    /// the ladder — one far below the hero, one far above.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: Self.weakling, displayName: "Weakling", stage: .babyI, spriteFile: "Botamon"),
            EvolutionNode(id: Self.titan, displayName: "Titan", stage: .ultimate, spriteFile: "Metalgreymon"),
        ])
    }

    /// One map whose only resident is the Baby-I, one whose only resident is the Ultimate.
    private func fixtureCatalog() -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(id: Self.winMap, displayName: "Win", assetName: "01_grassland",
                         tier: 1, totalSteps: 100_000, opponentPool: [Self.weakling]),
            AdventureMap(id: Self.lossMap, displayName: "Loss", assetName: "02_river",
                         tier: 5, totalSteps: 100_000, opponentPool: [Self.titan]),
        ])
    }

    /// - Parameters:
    ///   - stage: the hero's battle stage — `.ultimate` for the sure-win fixture, `.babyI` for the
    ///     sure-loss one. Set on the state, which is what battle power and HP read.
    private func makeModel(storeName: String = "Wild",
                           stage: Stage = .ultimate,
                           strength: Int = 30,
                           seed: UInt64 = 1) throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("\(storeName).store")
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.now)
        state.stage = stage
        state.strengthStat = strength
        // US-027: the empty readers would otherwise have the audit charge a mistake for every day
        // since the epoch, sickening the Digimon before an encounter could land.
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

    /// Puts `steps` on the selected map's counter, as a day of walking would.
    private func walked(_ steps: Double, into mapId: String, on model: MainScreenModel) {
        model.selectMap(mapId)
        model.profile?.record(steps: steps, forMap: mapId)
    }

    // MARK: - AC1: crossing 500 steps raises an encounter against a map foe

    func testCrossing500StepsRaisesAWildEncounterFromTheMapPool() async throws {
        let model = try makeModel()
        await model.start()

        walked(499, into: Self.winMap, on: model)
        model.checkForWildEncounter()
        XCTAssertNil(model.pendingWildEncounter, "499 of 500 is not across")

        walked(1, into: Self.winMap, on: model)   // 500 now
        model.checkForWildEncounter()

        let encounter = try XCTUnwrap(model.pendingWildEncounter, "500 steps raises the encounter")
        XCTAssertEqual(encounter.opponent.node.id, Self.weakling, "the wild foe is the map's resident")
        XCTAssertEqual(encounter.mapId, Self.winMap)
        XCTAssertEqual(encounter.presentation.displayName, "Weakling")
    }

    /// The foreground hook: a refresh — the app coming to the front — is what fires the check, so an
    /// encounter that came due while the app was closed is waiting the moment it opens.
    func testTheEncounterFiresOnRefresh() async throws {
        let model = try makeModel()
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh()

        XCTAssertNotNil(model.pendingWildEncounter, "the refresh raised the encounter")
    }

    // MARK: - AC3: fleeing costs the map 500 steps and plays the refuse pose

    func testFleeReducesTheMapBy500AndTurnsAway() async throws {
        let model = try makeModel()
        await model.start()
        walked(800, into: Self.winMap, on: model)
        model.checkForWildEncounter()
        XCTAssertNotNil(model.pendingWildEncounter)

        model.fleeWildEncounter()

        let profile = try XCTUnwrap(model.profile)
        XCTAssertEqual(profile.recorded(forMap: Self.winMap), 300, "800 minus the 500 flee penalty")
        XCTAssertNil(model.pendingWildEncounter, "the dialog is gone")
        XCTAssertNil(model.pendingBattle, "and no fight was started")
        XCTAssertEqual(model.animation, .pose(.refuse), "the Digimon turns tail")
        // The marker moved to the new total, so the next encounter is a fresh 500 from here.
        XCTAssertEqual(profile.encounterMarker(forMap: Self.winMap), 300)
    }

    /// The penalty floors at zero rather than going negative — a flee on a barely walked map sends the
    /// player back to the start of it, not into debt.
    func testTheFleePenaltyFloorsAtZero() async throws {
        let model = try makeModel()
        await model.start()
        walked(500, into: Self.winMap, on: model)
        model.checkForWildEncounter()

        model.fleeWildEncounter()

        XCTAssertEqual(try XCTUnwrap(model.profile).recorded(forMap: Self.winMap), 0)
    }

    // MARK: - AC5: winning keeps the steps and marks the foe met

    func testBattleThenWinningKeepsTheStepsAndMarksTheFoeMet() async throws {
        let model = try makeModel(stage: .ultimate, strength: 30)
        await model.start()
        walked(700, into: Self.winMap, on: model)
        model.checkForWildEncounter()

        let bout = try XCTUnwrap(model.acceptWildEncounter(), "the fight is resolved")
        XCTAssertTrue(bout.report.playerWon, "the Ultimate beats the Baby-I")

        let profile = try XCTUnwrap(model.profile)
        XCTAssertEqual(profile.recorded(forMap: Self.winMap), 700, "a win costs no steps")
        XCTAssertTrue(profile.hasMet(Self.weakling, forMap: Self.winMap), "the wild foe counts as met")
        XCTAssertNil(model.pendingWildEncounter, "the dialog is gone")
        XCTAssertEqual(model.pendingBattle, bout, "the fight replays over the same spot")
        // The marker moved to the (unchanged) total, so the next encounter is a fresh 500 from here.
        XCTAssertEqual(profile.encounterMarker(forMap: Self.winMap), 700)
    }

    // MARK: - AC4: losing costs the map 500 steps

    func testBattleThenLosingReducesTheMapBy500() async throws {
        let model = try makeModel(stage: .babyI, strength: 0)
        await model.start()
        walked(700, into: Self.lossMap, on: model)
        model.checkForWildEncounter()

        let bout = try XCTUnwrap(model.acceptWildEncounter())
        XCTAssertFalse(bout.report.playerWon, "the Baby-I loses to the Ultimate")

        let profile = try XCTUnwrap(model.profile)
        XCTAssertEqual(profile.recorded(forMap: Self.lossMap), 200, "700 minus the 500 loss penalty")
        XCTAssertFalse(profile.hasMet(Self.titan, forMap: Self.lossMap), "a loss does not meet the foe")
        XCTAssertEqual(profile.encounterMarker(forMap: Self.lossMap), 200)
    }

    // MARK: - AC2: the marker means the next encounter needs another 500 fresh steps

    func testTheMarkerGatesTheNextEncounterOnAnother500() async throws {
        let model = try makeModel()
        await model.start()
        walked(500, into: Self.winMap, on: model)
        model.checkForWildEncounter()

        // Win it: the total stays 500 and the marker moves to 500.
        model.acceptWildEncounter()
        model.finishBattle()
        XCTAssertNil(model.pendingWildEncounter)

        // Immediately checking again raises nothing — no new steps since the marker.
        model.checkForWildEncounter()
        XCTAssertNil(model.pendingWildEncounter, "the same 500 does not raise a second foe")

        // 499 more is still short; the 500th tips it.
        model.profile?.record(steps: 499, forMap: Self.winMap)
        model.checkForWildEncounter()
        XCTAssertNil(model.pendingWildEncounter, "999 total is only 499 past the marker")

        model.profile?.record(steps: 1, forMap: Self.winMap)
        model.checkForWildEncounter()
        XCTAssertNotNil(model.pendingWildEncounter, "1,000 total is a fresh 500 past the marker")
    }

    // MARK: - Guards

    func testNoEncounterWithoutAMapSelected() async throws {
        let model = try makeModel()
        await model.start()
        // Steps recorded against a map, but nothing selected: no place to be ambushed.
        model.profile?.record(steps: 5_000, forMap: Self.winMap)

        model.checkForWildEncounter()

        XCTAssertNil(model.pendingWildEncounter)
    }

    func testNoEncounterWhileOneIsAlreadyPending() async throws {
        let model = try makeModel()
        await model.start()
        walked(5_000, into: Self.winMap, on: model)
        model.checkForWildEncounter()
        let first = try XCTUnwrap(model.pendingWildEncounter)

        model.checkForWildEncounter()

        XCTAssertEqual(model.pendingWildEncounter, first, "a second check does not replace the foe")
    }
}

// MARK: - Fixtures

private final class NoSamples: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class NoSleep: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
