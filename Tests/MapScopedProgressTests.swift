import Foundation
import XCTest

@testable import DigiVPet

/// US-206 — a map's Digitama conditions measure progress ON THAT MAP, not globally.
///
/// Three layers, and they are separate on purpose: the counters themselves (`PlayerProfile`), the
/// reading of them (`ConditionContext.mapScoped`), and the whole game wired end to end
/// (`MainScreenModel`) — where the regression the story is named for lives. The clock is injected
/// throughout and nothing here waits on real time.
private enum Fixture {
    static let morning = Date(timeIntervalSince1970: 1_770_000_000)

    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Train once. The condition BOTH maps below are gated on, so "met here, not met there" is a
    /// statement about the map and never about which criterion was chosen.
    static let trainedOnce = EvolutionCondition(
        metric: .careTrainingSessions, window: .stage, comparison: .atLeast, value: 1,
        hint: "Train it once")

    /// Walk 2,000 steps. `.day`, which map-scoping answers off the map's running total — see
    /// `ConditionContext.mapScoped`.
    static let walked = EvolutionCondition(
        metric: .healthSteps, window: .day, comparison: .atLeast, value: 2_000,
        hint: "Walk 2,000 steps")

    /// Two unlocked maps holding the SAME condition over two different eggs. Neither is
    /// `unlockedBy` the other, so both have a reachable detail from the first launch — the story is
    /// about arriving somewhere new, not about opening it.
    static let catalog = MapCatalog(maps: [
        AdventureMap(id: "alpha", displayName: "Alpha", assetName: "01_grassland",
                     tier: 1, totalSteps: 100_000, opponentPool: ["foe"],
                     digitamaSlots: [DigitamaSlot(digitamaId: "gabu_digitama",
                                                  conditions: [trainedOnce])]),
        AdventureMap(id: "beta", displayName: "Beta", assetName: "02_river",
                     tier: 1, totalSteps: 100_000, opponentPool: ["foe"],
                     digitamaSlots: [DigitamaSlot(digitamaId: "pal_digitama",
                                                  conditions: [trainedOnce])]),
    ])
}

// MARK: - AC1: the counters themselves

final class MapScopedCounterTests: XCTestCase {
    /// AC1/AC3: every counter is filed under a map id, and one map's progress is invisible from
    /// another. This is the leak the whole story is about, asserted at the storage.
    func testCountersAreKeptPerMapAndDoNotLeak() {
        let profile = PlayerProfile()

        profile.credit(MetricTotals(values: [ConditionMetric.healthSteps.rawValue: 2_500]),
                       forMap: "alpha")
        profile.credit(.careTrainingSessions, forMap: "alpha")
        profile.recordBattle(won: true, forMap: "alpha")

        XCTAssertEqual(profile.stepsWalked(forMap: "alpha"), 2_500)
        XCTAssertEqual(profile.battlesWon(forMap: "alpha"), 1)
        XCTAssertEqual(profile.battlesFought(forMap: "alpha"), 1)

        XCTAssertEqual(profile.stepsWalked(forMap: "beta"), 0, "beta was never walked in")
        XCTAssertEqual(profile.battlesWon(forMap: "beta"), 0)
        XCTAssertEqual(profile.mapMetrics(forMap: "beta").known(.careTrainingSessions), nil,
                       "and nothing was trained there")
    }

    /// Credits ACCUMULATE rather than replace, so a second read adds to the first — the same
    /// arithmetic `record(steps:forMap:)` has always done for the progress counter.
    func testCreditsAccumulate() {
        let profile = PlayerProfile()

        profile.credit(.healthSteps, amount: 1_000, forMap: "alpha")
        profile.credit(.healthSteps, amount: 400, forMap: "alpha")

        XCTAssertEqual(profile.stepsWalked(forMap: "alpha"), 1_400)
    }

    /// Nothing writes a zero, which is what keeps "absent means never credited" true — see
    /// `mapMetricStorage`, and `MetricTotals.known(_:)` for why an absence must not read as a zero.
    func testANonPositiveCreditWritesNothing() {
        let profile = PlayerProfile()

        profile.credit(.healthSteps, amount: 0, forMap: "alpha")
        profile.credit(.healthSteps, amount: -5, forMap: "alpha")

        XCTAssertNil(profile.mapMetrics(forMap: "alpha").known(.healthSteps))
    }

    /// The map's steps are NOT the map's progress: a lost fight sends the player back down the map
    /// (US-201/US-203) but does not un-walk the steps an egg's condition was earned with.
    func testAProgressPenaltyDoesNotTakeBackTheStepsWalked() {
        let profile = PlayerProfile()
        profile.selectedMapId = "alpha"
        profile.record(steps: 900, forMap: "alpha")
        profile.credit(.healthSteps, amount: 900, forMap: "alpha")

        profile.reduceRecorded(steps: 500, forMap: "alpha")

        XCTAssertEqual(profile.recorded(forMap: "alpha"), 400, "the boss is further away again")
        XCTAssertEqual(profile.stepsWalked(forMap: "alpha"), 900, "but the walking still happened")
    }

    /// Wins and fights move together off one call, so the ratio between them can never exceed 1.
    func testTheWinRatioIsTheMapsOwn() {
        let profile = PlayerProfile()
        profile.recordBattle(won: true, forMap: "alpha")
        profile.recordBattle(won: false, forMap: "alpha")
        profile.recordBattle(won: true, forMap: "alpha")
        profile.recordBattle(won: false, forMap: "beta")

        let alpha = ConditionContext.mapScoped("alpha", profile: profile)
        let beta = ConditionContext.mapScoped("beta", profile: profile)

        XCTAssertEqual(alpha.battleWinRatioLifetime, 2.0 / 3.0)
        XCTAssertEqual(beta.battleWinRatioLifetime, 0, "one fight, none won")
        XCTAssertEqual(ConditionContext.mapScoped("gamma", profile: profile).battleWinRatioLifetime, 0,
                       "and a map never fought in is 0.0, not a divide by zero")
    }
}

// MARK: - AC4: the reading of them

final class MapScopedContextTests: XCTestCase {
    /// AC2/AC4: a fresh map answers its conditions NOT MET, whatever the player has done elsewhere.
    /// The context is built from the map's counters alone, so there is no global history in it to
    /// read from.
    func testAFreshMapMeetsNothing() {
        let profile = PlayerProfile()
        profile.credit(MetricTotals(values: [ConditionMetric.healthSteps.rawValue: 30_000]),
                       forMap: "alpha")
        profile.credit(.careTrainingSessions, amount: 50, forMap: "alpha")

        let beta = ConditionContext.mapScoped("beta", profile: profile)

        XCTAssertFalse(ConditionReveal.allMet([Fixture.walked], in: beta))
        XCTAssertFalse(ConditionReveal.allMet([Fixture.trainedOnce], in: beta))
    }

    /// AC4: all three windows are answered off the map's running total. A map is a place, not a span
    /// of the player's life, so `day` / `stage` / `lifetime` mean the same thing here.
    func testEveryWindowReadsTheMapsTotal() {
        let profile = PlayerProfile()
        profile.credit(.healthSteps, amount: 2_100, forMap: "alpha")
        let context = ConditionContext.mapScoped("alpha", profile: profile)

        for window in ConditionWindow.allCases {
            XCTAssertEqual(context.value(for: .healthSteps, window: window), .known(2_100),
                           "\(window) should read the map's own steps")
        }
    }

    /// An un-credited health metric is `.unknown` and fails its condition whichever way the
    /// comparison points, so a fresh map cannot satisfy an `atMost` gate for free (US-180's rule,
    /// kept). The `care.*` counters are flattened to a real 0 instead, because the game keeps them
    /// itself and "nothing has happened here yet" is a fact rather than an absence.
    func testAnUncreditedHealthMetricIsUnknownWhileCareCountersReadZero() {
        let context = ConditionContext.mapScoped("beta", profile: PlayerProfile())

        XCTAssertEqual(context.value(for: .healthSteps, window: .day), .unknown)
        XCTAssertEqual(context.value(for: .careTrainingSessions, window: .stage), .known(0))
        XCTAssertEqual(context.value(for: .careOverfeeds, window: .stage), .known(0))
        XCTAssertEqual(context.value(for: .careSleepDisturbances, window: .stage), .known(0))
        XCTAssertEqual(context.value(for: .careBattleCount, window: .lifetime), .known(0))
    }

    /// The light is a NOW reading with no per-map version, so it is passed through — `15_dungeon`'s
    /// ghost slot is gated on it and must still be answerable.
    func testTheLightIsPassedThroughUnscoped() {
        let profile = PlayerProfile()
        let off = ConditionContext.mapScoped("alpha", profile: profile, lightState: .off)
        let on = ConditionContext.mapScoped("alpha", profile: profile, lightState: .on)

        XCTAssertEqual(off.value(for: .careLightOff, window: .stage), .known(1))
        XCTAssertEqual(on.value(for: .careLightOff, window: .stage), .known(0))
    }

    /// AC4 at `DigitamaDropEngine`: the drop rule reads the map-scoped context, so a slot is eligible
    /// on the map it was earned on and on no other.
    func testEligibleSlotsFollowTheMapTheProgressWasEarnedOn() {
        let profile = PlayerProfile()
        profile.credit(.careTrainingSessions, forMap: "alpha")
        let alpha = Fixture.catalog.map(id: "alpha")!
        let beta = Fixture.catalog.map(id: "beta")!

        XCTAssertEqual(
            DigitamaDropEngine.eligibleSlots(
                in: alpha, context: .mapScoped("alpha", profile: profile), held: []
            ).map(\.digitamaId),
            ["gabu_digitama"])
        XCTAssertTrue(
            DigitamaDropEngine.eligibleSlots(
                in: beta, context: .mapScoped("beta", profile: profile), held: []
            ).isEmpty,
            "the same condition, unearned in beta")
    }
}

// MARK: - the whole game

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class MapScopedProgressModelTests: XCTestCase {
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

    private var storeURL: URL { storeDirectory.appendingPathComponent("Scoped.store") }

    /// `agu_digitama` hatches to `hero`, so the starting egg is pinned; `foe` gives a battle someone
    /// to fight. Copied from `DigitamaDropTests` — the same shape, because this is the same wiring.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "agu_digitama", displayName: "Agu Digitama", stage: .digitama,
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "foe", displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
        ])
    }

    /// A model over a store seeded at a `hero` child fit to act, with charges stocked so training
    /// and battling are affordable. The clock is `Fixture.morning` throughout — injected, so nothing
    /// here waits.
    private func makeModel(store: GameStore) throws -> MainScreenModel {
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        state.stage = .child
        state.currentDigimonId = "hero"
        state.stageEnergy[.strength] = 100
        state.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        state.trainCharges = ConsumptionConfig.bundled.maxTrainCharges
        state.healthDataLastSeen = Fixture.morning
        state.hungerUpdatedAt = Fixture.morning
        state.stageEnteredDate = Fixture.morning
        try store.save()

        return MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            roster: .bundled,
            maps: Fixture.catalog,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { nodes in nodes.first { $0.id == "agu_digitama" } },
            makeBattleGenerator: { SeededGenerator(seed: 1) },
            makeDropGenerator: { SeededGenerator(seed: 1) }
        )
    }

    /// Whether `map`'s only slot reads as earned on the detail screen the list would push.
    private func slotIsMet(_ mapId: String, in model: MainScreenModel) -> Bool {
        let row = model.mapRows.first { $0.id == mapId }!
        let detail = model.mapDetail(for: row)!
        return ConditionReveal.allMet(Fixture.catalog.map(id: mapId)!.digitamaSlots[0].conditions,
                                      in: detail.context)
    }

    /// Whether `map`'s only slot wears the "Ready to find" mark on that detail screen.
    private func slotIsReady(_ mapId: String, in model: MainScreenModel) -> Bool {
        let row = model.mapRows.first { $0.id == mapId }!
        return model.mapDetail(for: row)!.digitama[0].isReady
    }

    /// **AC2 as the screen states it**: the "Ready to find" mark follows the MAP's counters. Seeded
    /// on the profile rather than played out, so no drop check runs and the slot is still unrevealed
    /// — a revealed slot is never "ready", so this is the only way to see the mark itself.
    func testTheReadyMarkFollowsTheMapsOwnCounters() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()
        let profile = try XCTUnwrap(model.profile)

        XCTAssertFalse(slotIsReady("alpha", in: model), "nothing earned anywhere yet")

        profile.credit(.careTrainingSessions, forMap: "alpha")

        XCTAssertTrue(slotIsReady("alpha", in: model), "alpha's egg is ready to find")
        XCTAssertFalse(slotIsReady("beta", in: model), "and beta's, on the same condition, is not")
    }

    /// **THE REGRESSION (AC6).** Enter alpha and meet its condition; enter beta, whose slot carries
    /// the very same condition, and it is NOT met; return to alpha and it still is.
    func testProgressIsEarnedPerMapAndSurvivesSwitchingAway() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        model.selectMap("alpha")
        XCTAssertFalse(slotIsMet("alpha", in: model), "nothing has been done here yet")

        XCTAssertNotNil(model.train(), "the round opened")
        model.finishTraining(.good)
        XCTAssertTrue(slotIsMet("alpha", in: model), "alpha was trained in")

        model.selectMap("beta")
        XCTAssertFalse(slotIsMet("beta", in: model),
                       "the same condition, and beta has never been trained in")

        model.selectMap("alpha")
        XCTAssertTrue(slotIsMet("alpha", in: model), "and alpha's own progress is still there")
    }

    /// AC2: a player with a long global history arriving somewhere new finds it LOCKED. The
    /// counters below are the ones the pre-US-206 context was built from, set high enough to satisfy
    /// every slot in the catalog — and none of them reaches a map.
    func testGlobalHistoryNeverUnlocksAFreshMap() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        let state = try XCTUnwrap(model.state)
        state.stageTrainingSessions = 500
        state.battleWins = 400
        state.stageMetricTotals[.healthSteps] = 1_000_000
        state.lifetimeMetricTotals[.healthSteps] = 1_000_000
        state.stageBestDayMetrics[.healthSteps] = 40_000

        model.selectMap("alpha")

        XCTAssertFalse(slotIsMet("alpha", in: model), "a lifetime elsewhere earns nothing here")
        XCTAssertFalse(slotIsReady("alpha", in: model), "so no 'Ready to find' mark is drawn")
        await model.refresh()
        XCTAssertNil(model.pendingDigitamaDrop, "so no egg drops out of history either")
        XCTAssertEqual(try store.allStates().count, 1)
    }

    /// AC4 at the drop: the egg is awarded on the map whose conditions were met, and the identical
    /// slot on the other map is not — one train, one egg.
    func testOnlyTheMapTheWorkWasDoneOnDropsItsEgg() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        model.selectMap("alpha")
        XCTAssertNotNil(model.train())
        model.finishTraining(.good)

        XCTAssertEqual(model.pendingDigitamaDrop?.id, "gabu_digitama", "alpha's egg")
        model.acknowledgeDigitamaDrop()

        // Beta's slot carries the same condition and its egg must stay put: a refresh there, with
        // the training already banked on alpha, awards nothing.
        model.selectMap("beta")
        await model.refresh()

        XCTAssertNil(model.pendingDigitamaDrop, "beta has not been trained in")
        XCTAssertFalse(try store.heldDigitamaIds().contains("pal_digitama"))
    }

    /// AC1: the counters survive the app being closed and reopened — the same call the app makes on
    /// launch reads them back.
    func testTheMapsCountersSurviveAReopen() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        model.selectMap("alpha")
        XCTAssertNotNil(model.train())
        model.finishTraining(.good)
        model.battle()
        model.finishBattleRound(.good)
        model.finishBattle()
        let wins = try XCTUnwrap(model.profile).battlesWon(forMap: "alpha")
        try store.save()

        let reopened = try GameStore(url: storeURL)
        let saved = try reopened.loadOrCreateProfile()

        XCTAssertEqual(saved.mapMetrics(forMap: "alpha")[.careTrainingSessions], 1)
        XCTAssertEqual(saved.battlesFought(forMap: "alpha"), 1)
        XCTAssertEqual(saved.battlesWon(forMap: "alpha"), wins)
        XCTAssertEqual(saved.battlesFought(forMap: "beta"), 0, "and beta is untouched")
    }

    /// A battle is filed against the map it was fought in, both halves of the ratio together.
    func testABattleIsFiledAgainstTheMapItWasFoughtIn() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        model.selectMap("beta")
        model.battle()
        model.finishBattleRound(.good)
        model.finishBattle()

        let profile = try XCTUnwrap(model.profile)
        XCTAssertEqual(profile.battlesFought(forMap: "beta"), 1)
        XCTAssertEqual(profile.battlesFought(forMap: "alpha"), 0)
        XCTAssertLessThanOrEqual(profile.battlesWon(forMap: "beta"),
                                 profile.battlesFought(forMap: "beta"),
                                 "the ratio can never exceed 1")
    }

    /// With nowhere selected there is nowhere for a tick to land, and it is dropped rather than
    /// parked somewhere it could later be mistaken for real progress — `MapStepCreditor`'s rule.
    func testWithNoMapSelectedNothingIsCredited() async throws {
        let store = try GameStore(url: storeURL)
        let model = try makeModel(store: store)
        await model.start()

        XCTAssertNil(model.profile?.selectedMapId, "a fresh save has chosen nowhere")
        XCTAssertNotNil(model.train())
        model.finishTraining(.good)

        let profile = try XCTUnwrap(model.profile)
        XCTAssertNil(profile.mapMetrics(forMap: "alpha").known(.careTrainingSessions))
        XCTAssertNil(profile.mapMetrics(forMap: "beta").known(.careTrainingSessions))
    }
}
