import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-128 — eggs drop from the selected map when its stated conditions are met.
///
/// A fixed-timezone calendar and hand-written instants, as in the other suites: nothing here waits
/// real time or asks HealthKit anything — the clock is injected and every reading comes from an
/// empty fixture fetcher. The drop generator is seeded, so "one of three" is deterministic.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    /// Mid-morning, well outside the 22:00–07:00 fallback sleep window, so a Digimon can train.
    static let morning = date("2026-07-17 09:00")

    /// A condition met by any context with a training session on the board, and one nothing meets.
    static func trainedAtLeastOnce() -> EvolutionCondition {
        EvolutionCondition(metric: .careTrainingSessions, window: .stage,
                           comparison: .atLeast, value: 1, hint: "Train it once")
    }

    static func metContext() -> ConditionContext {
        ConditionContext(trainingSessionsThisStage: 5)
    }

    static func unmetContext() -> ConditionContext {
        ConditionContext(trainingSessionsThisStage: 0)
    }
}

// MARK: - The drop rule (pure)

final class DigitamaDropEngineTests: XCTestCase {
    private func map(slots: [DigitamaSlot]) -> AdventureMap {
        AdventureMap(id: "grass", displayName: "Grass", assetName: "01_grassland",
                     tier: 1, totalSteps: 3_000, digitamaSlots: slots)
    }

    private func slot(_ id: String, _ conditions: [EvolutionCondition]) -> DigitamaSlot {
        DigitamaSlot(digitamaId: id, conditions: conditions)
    }

    /// THE AC: conditions unmet awards nothing.
    func testConditionsUnmetAwardsNothing() {
        let map = map(slots: [slot("gabu_digitama", [Fixture.trainedAtLeastOnce()])])
        var generator = SeededGenerator(seed: 1)

        let award = DigitamaDropEngine.award(in: map, context: Fixture.unmetContext(),
                                             held: [], using: &generator)

        XCTAssertNil(award)
    }

    /// THE AC: exactly one eligible awards that one.
    func testExactlyOneEligibleAwardsThatOne() {
        let map = map(slots: [
            slot("gabu_digitama", [Fixture.trainedAtLeastOnce()]),
            slot("pal_digitama", [Fixture.trainedAtLeastOnce(),
                                  EvolutionCondition(metric: .careOverfeeds, window: .stage,
                                                     comparison: .atLeast, value: 3,
                                                     hint: "never met here")]),
        ])
        var generator = SeededGenerator(seed: 99)

        // Only the first slot is met — the second waits on an overfeed count the context has at 0.
        let award = DigitamaDropEngine.award(in: map, context: Fixture.metContext(),
                                             held: [], using: &generator)

        XCTAssertEqual(award, "gabu_digitama")
    }

    /// THE AC: three eligible awards one of the three, and is deterministic under a seeded generator.
    func testThreeEligibleAwardsOneOfThemDeterministically() {
        let ids = ["gabu_digitama", "pal_digitama", "pata_digitama"]
        let map = map(slots: ids.map { slot($0, [Fixture.trainedAtLeastOnce()]) })

        var first = SeededGenerator(seed: 7)
        let a = DigitamaDropEngine.award(in: map, context: Fixture.metContext(),
                                         held: [], using: &first)
        var second = SeededGenerator(seed: 7)
        let b = DigitamaDropEngine.award(in: map, context: Fixture.metContext(),
                                         held: [], using: &second)

        XCTAssertNotNil(a)
        XCTAssertEqual(a, b, "the same seed picks the same egg")
        XCTAssertTrue(ids.contains(a!), "and it is one of the three eligible")
    }

    /// THE AC: all eligible eggs already held awards nothing — the rule that stops farming duplicates.
    func testAllHeldAwardsNothing() {
        let ids = ["gabu_digitama", "pal_digitama", "pata_digitama"]
        let map = map(slots: ids.map { slot($0, [Fixture.trainedAtLeastOnce()]) })
        var generator = SeededGenerator(seed: 3)

        let award = DigitamaDropEngine.award(in: map, context: Fixture.metContext(),
                                             held: Set(ids), using: &generator)

        XCTAssertNil(award)
    }

    /// A held egg is skipped even when its condition is met, and an unheld met one beside it drops.
    func testAHeldEggIsSkippedButAnUnheldOneBesideItDrops() {
        let map = map(slots: [
            slot("gabu_digitama", [Fixture.trainedAtLeastOnce()]),
            slot("pal_digitama", [Fixture.trainedAtLeastOnce()]),
        ])
        var generator = SeededGenerator(seed: 42)

        let award = DigitamaDropEngine.award(in: map, context: Fixture.metContext(),
                                             held: ["gabu_digitama"], using: &generator)

        XCTAssertEqual(award, "pal_digitama", "the only one both met and unheld")
    }

    /// No map selected awards nothing — there is nowhere for an egg to be found.
    func testNoMapAwardsNothing() {
        var generator = SeededGenerator(seed: 1)

        let award = DigitamaDropEngine.award(in: nil, context: Fixture.metContext(),
                                             held: [], using: &generator)

        XCTAssertNil(award)
    }

    /// A map with no slots awards nothing.
    func testAMapWithNoSlotsAwardsNothing() {
        var generator = SeededGenerator(seed: 1)

        let award = DigitamaDropEngine.award(in: map(slots: []), context: Fixture.metContext(),
                                             held: [], using: &generator)

        XCTAssertNil(award)
    }

    /// A slot with no conditions is vacuously met — a free drop when it is not held.
    func testASlotWithNoConditionsIsEligible() {
        let eligible = DigitamaDropEngine.eligibleSlots(
            in: map(slots: [slot("gabu_digitama", [])]),
            context: .unknown, held: [])

        XCTAssertEqual(eligible.map(\.digitamaId), ["gabu_digitama"])
    }
}

// MARK: - The light-off map condition (US-186)

/// US-186 — a map can reveal a dark Digimon only when the light is off.
///
/// The whole feature rides on US-185's `care.lightOff` metric being ordinary condition vocabulary:
/// `DigitamaSlot` reuses `EvolutionCondition`, and `DigitamaDropEngine` reads it through
/// `ConditionReveal.allMet` against a `ConditionContext` — the same context that already carries
/// `lightState`. So there is no new plumbing to test, only that a light-off gate is honoured (off →
/// available, on → withheld) and that the shipped Dungeon authors one that actually resolves.
final class LightOffMapConditionTests: XCTestCase {
    private func lightOff() -> EvolutionCondition {
        EvolutionCondition(metric: .careLightOff, window: .stage,
                           comparison: .atLeast, value: 1,
                           hint: "Seek it in the dark, with the light off")
    }

    private func map(slots: [DigitamaSlot]) -> AdventureMap {
        AdventureMap(id: "dark", displayName: "Dark", assetName: "15_dungeon",
                     tier: 5, totalSteps: 38_000, digitamaSlots: slots)
    }

    /// THE AC (pure engine): the gated slot is eligible with the light OFF and withheld with it ON.
    func testALightOffSlotIsEligibleOnlyWhenTheLightIsOff() {
        let map = map(slots: [DigitamaSlot(digitamaId: "ghost_digitama", conditions: [lightOff()])])

        let offEligible = DigitamaDropEngine.eligibleSlots(
            in: map, context: ConditionContext(lightState: .off), held: [])
        XCTAssertEqual(offEligible.map(\.digitamaId), ["ghost_digitama"],
                       "the dark Digimon shows itself with the light off")

        let onEligible = DigitamaDropEngine.eligibleSlots(
            in: map, context: ConditionContext(lightState: .on), held: [])
        XCTAssertTrue(onEligible.isEmpty, "and stays hidden with the light on")
    }

    /// Dimmed and never-read are both "not off", so the slot stays hidden — the gate is `light == off`,
    /// not `light != on`.
    func testASemiOrUnknownLightWithholdsTheSlot() {
        let map = map(slots: [DigitamaSlot(digitamaId: "ghost_digitama", conditions: [lightOff()])])

        XCTAssertTrue(DigitamaDropEngine.eligibleSlots(
            in: map, context: ConditionContext(lightState: .semi), held: []).isEmpty)
        XCTAssertTrue(DigitamaDropEngine.eligibleSlots(
            in: map, context: .unknown, held: []).isEmpty)
    }

    /// AC3, against the REAL data: the shipped Dungeon's `ghost_digitama` slot carries a light-off
    /// gate, and it is honoured — met (twenty battles fought) it drops with the light off and is held
    /// back with it on.
    func testTheShippedDungeonGhostIsGatedOnTheLightBeingOff() throws {
        let catalog = try MapCatalog.load()
        let dungeon = try XCTUnwrap(catalog.map(id: "15_dungeon"))
        let ghost = try XCTUnwrap(dungeon.digitamaSlots.first { $0.digitamaId == "ghost_digitama" })
        XCTAssertTrue(ghost.conditions.contains { $0.metric == ConditionMetric.careLightOff.rawValue },
                      "at least one authored map uses the light-off condition")

        // Its other gate is twenty lifetime battles; satisfy that and vary only the light.
        func context(light: LightState) -> ConditionContext {
            ConditionContext(battlesLifetime: 20, lightState: light)
        }

        XCTAssertTrue(ConditionReveal.allMet(ghost.conditions, in: context(light: .off)),
                      "twenty battles fought and the light off — the ghost appears")
        XCTAssertFalse(ConditionReveal.allMet(ghost.conditions, in: context(light: .on)),
                       "same battles, light on — it stays hidden")
    }

    /// AC2: the validator accepts the light-off condition — a slot gated on it is a finding of no
    /// kind (a known metric, answerable over `.stage`, and not empty-on-hardware).
    func testTheValidatorAcceptsALightOffSlot() {
        let roster = Roster(entries: [
            RosterEntry(id: "ghost_digitama", displayName: "Ghost Digitama",
                        stage: .digitama, spriteFile: "Ghost_Digitama", dexOnly: false),
        ])
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "dark", displayName: "Dark", assetName: "15_dungeon",
                         tier: 5, totalSteps: 38_000,
                         digitamaSlots: [DigitamaSlot(digitamaId: "ghost_digitama",
                                                      conditions: [lightOff()])]),
        ])

        XCTAssertEqual(catalog.validate(roster: roster, assetExists: { _ in true }), [],
                       "a light-off gate is a clean condition")
    }
}

// MARK: - The validator's empty-on-hardware rule (US-128 AC7)

final class DigitamaDropValidatorTests: XCTestCase {
    /// A tiny sound roster: one egg to name in slots, so the fixture catalog validates on everything
    /// EXCEPT the rule under test.
    private func roster() -> Roster {
        Roster(entries: [
            RosterEntry(id: "gabu_digitama", displayName: "Gabu Digitama",
                        stage: .digitama, spriteFile: "Gabu_Digitama", dexOnly: false),
        ])
    }

    private func catalog(_ conditions: [EvolutionCondition]) -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(id: "grass", displayName: "Grass", assetName: "01_grassland",
                         tier: 1, totalSteps: 3_000,
                         digitamaSlots: [DigitamaSlot(digitamaId: "gabu_digitama",
                                                      conditions: conditions)]),
        ])
    }

    /// THE AC: a slot gated SOLELY on an empty-on-hardware metric is rejected — that egg is
    /// unreachable on a watch-only device.
    func testASoleSparseConditionIsRejected() {
        let errors = catalog([
            EvolutionCondition(metric: .healthHandwashing, window: .day,
                               comparison: .atLeast, value: 3, hint: "Wash your hands"),
        ]).validate(roster: roster(), assetExists: { _ in true })

        XCTAssertEqual(errors, [.soleSparseCondition(map: "grass", digitamaId: "gabu_digitama")])
    }

    /// Two sparse metrics together are still solely sparse — pairing two empty gates does not make
    /// the egg reachable.
    func testTwoSparseConditionsAreStillSole() {
        let errors = catalog([
            EvolutionCondition(metric: .healthHandwashing, window: .day,
                               comparison: .atLeast, value: 3, hint: "Wash your hands"),
            EvolutionCondition(metric: .healthToothbrushing, window: .day,
                               comparison: .atLeast, value: 2, hint: "Brush your teeth"),
        ]).validate(roster: roster(), assetExists: { _ in true })

        XCTAssertEqual(errors, [.soleSparseCondition(map: "grass", digitamaId: "gabu_digitama")])
    }

    /// A sparse metric PAIRED with a real one is fine — the shipped `06_industrial/pulse_digitama`
    /// pattern (steps + handwashing). The empty gate is a bonus, not the only way in.
    func testASparseConditionPairedWithARealOneIsFine() {
        let errors = catalog([
            EvolutionCondition(metric: .healthSteps, window: .day,
                               comparison: .atLeast, value: 4_000, hint: "Walk 4,000 steps"),
            EvolutionCondition(metric: .healthHandwashing, window: .day,
                               comparison: .atLeast, value: 3, hint: "Wash your hands"),
        ]).validate(roster: roster(), assetExists: { _ in true })

        XCTAssertTrue(errors.isEmpty, "a real gate beside the sparse one makes the egg reachable")
    }

    /// The rule does not fire on a slot with no conditions at all — that is a free drop, not an
    /// unreachable one.
    func testAnEmptyConditionSlotIsNotSole() {
        let errors = catalog([]).validate(roster: roster(), assetExists: { _ in true })

        XCTAssertTrue(errors.isEmpty)
    }

    /// AC8, against the REAL data: the shipped catalog has no sole-sparse slot. (The broader
    /// zero-findings sweep lives in `MapCatalogValidatorTests`; this pins the new rule specifically.)
    func testTheShippedCatalogHasNoSoleSparseSlot() throws {
        let sole = try MapCatalog.load().validate().filter {
            if case .soleSparseCondition = $0 { return true }
            return false
        }
        XCTAssertEqual(sole, [], "\(sole)")
    }

    /// `isSparseOnHardware` is exactly the seven the type comment names — pinned so a later edit to
    /// the set is a deliberate one.
    func testTheSparseSetIsTheSevenFeatureSourcedMetrics() {
        let sparse = ConditionMetric.allCases.filter(\.isSparseOnHardware)
        XCTAssertEqual(Set(sparse), [
            .healthHandwashing, .healthToothbrushing, .healthWater, .healthDaylight,
            .healthAudioExposure, .healthLowCardioFitnessEvents, .healthWalkingSteadinessEvents,
        ])
    }
}

// MARK: - The three drop checks, through the model

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class DigitamaDropModelTests: XCTestCase {
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

    /// The graph the player is raised on — `agu_digitama` hatches to `hero`, so the starting egg is
    /// pinned and known, and `foe` gives the battle an opponent. The drop eggs (`gabu_digitama`,
    /// `pal_digitama`) are roster ids, resolved for the announcement off the bundled roster.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "agu_digitama", displayName: "Agu Digitama", stage: .digitama,
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "foe", displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
        ])
    }

    /// A one-map catalog whose only slot drops `digitama` when `conditions` are met. `01_grassland`
    /// is a real asset; the pool is one real graph opponent so `battle()` has someone to fight.
    private func catalog(slotId digitama: String, _ conditions: [EvolutionCondition]) -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(id: "grass", displayName: "Grass", assetName: "01_grassland",
                         tier: 3, totalSteps: 100_000, opponentPool: ["foe"],
                         digitamaSlots: [DigitamaSlot(digitamaId: digitama, conditions: conditions)]),
        ])
    }

    /// The store and a model over it, seeded at a `hero` child fit to act — awake, fed, and with its
    /// health clocks stamped now so the empty readers do not sicken it before the test acts. Its
    /// origin egg is `agu_digitama`, so `gabu_digitama`/`pal_digitama` are unheld and can drop. The
    /// same store instance is returned so the box can be read back without opening a second one.
    private func makeModel(maps: MapCatalog, dropSeed: UInt64 = 1) throws -> (MainScreenModel, GameStore) {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("Drop.store"))
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        state.stage = .child
        state.currentDigimonId = "hero"
        state.stageEnergy[.strength] = 100
        // US-176: a battle also spends a charge walked up from steps; the empty readers walk none.
        state.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        // US-177: a training round spends a charge burned from active calories; stock it likewise.
        state.trainCharges = ConsumptionConfig.bundled.maxTrainCharges
        state.healthDataLastSeen = Fixture.morning
        state.hungerUpdatedAt = Fixture.morning
        state.stageEnteredDate = Fixture.morning
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            roster: .bundled,
            maps: maps,
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
            makeDropGenerator: { SeededGenerator(seed: dropSeed) }
        )
        return (model, store)
    }

    // MARK: after a step accrual tick

    /// THE AC (step path): a refresh whose conditions are unmet drops nothing; once they are met, one
    /// refresh drops the egg, records it in the Dex and announces it — and it becomes held.
    func testAStepRefreshDropsTheEggOnceItsConditionIsMet() async throws {
        let (model, store) = try makeModel(
            maps: catalog(slotId: "gabu_digitama", [Fixture.trainedAtLeastOnce()]))
        await model.start()
        model.selectMap("grass")

        // Condition unmet (no training sessions yet): a refresh drops nothing.
        await model.refresh()
        XCTAssertEqual(try store.allStates().count, 1, "no egg while the condition is unmet")
        XCTAssertNil(model.pendingDigitamaDrop)

        // Meet the condition and refresh again: the egg drops.
        model.state?.stageTrainingSessions = 1
        await model.refresh()

        XCTAssertEqual(try store.allStates().count, 2, "the found egg joined the box")
        XCTAssertEqual(model.pendingDigitamaDrop?.id, "gabu_digitama", "and the player is told")
        XCTAssertEqual(model.pendingDigitamaDrop?.displayName, "Gabu Digitama")
        XCTAssertTrue(try store.dexIds().contains("gabu_digitama"), "recorded like any discovery")
        XCTAssertTrue(try store.heldDigitamaIds().contains("gabu_digitama"), "and now held")
        XCTAssertTrue(model.discoveredDigimonIds.contains("gabu_digitama"))
    }

    /// AC5: at most one drop per check, and a held egg is never dropped twice. A second met refresh
    /// after the drop adds nothing.
    func testASecondRefreshDoesNotDropTheHeldEggAgain() async throws {
        let (model, store) = try makeModel(
            maps: catalog(slotId: "gabu_digitama", [Fixture.trainedAtLeastOnce()]))
        await model.start()
        model.selectMap("grass")
        model.state?.stageTrainingSessions = 1

        await model.refresh()
        model.acknowledgeDigitamaDrop()
        await model.refresh()

        XCTAssertEqual(try store.allStates().count, 2, "the egg is held, so it does not drop again")
        XCTAssertNil(model.pendingDigitamaDrop, "and nothing new is announced")
    }

    /// AC: the dropped egg joins the box FROZEN and inactive, so US-124's one-active invariant holds
    /// and US-125 leaves it untouched until it is taken out.
    func testTheDroppedEggIsFrozenAndInactive() async throws {
        let (model, store) = try makeModel(
            maps: catalog(slotId: "gabu_digitama", [Fixture.trainedAtLeastOnce()]))
        await model.start()
        model.selectMap("grass")
        model.state?.stageTrainingSessions = 1
        await model.refresh()

        let egg = try XCTUnwrap(try store.allStates().first { $0.currentDigimonId == "gabu_digitama" })
        XCTAssertFalse(egg.isActive, "the running Digimon is still the one out")
        XCTAssertNotNil(egg.frozenSince, "and the egg is frozen in the box")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1, "exactly one active")
    }

    // MARK: after a train

    /// THE AC (train path): finishing a training session — which counts a session — runs a drop check,
    /// so a slot gated on `care.trainingSessions` drops the egg the moment the round is graded.
    func testFinishingATrainDropsAConditionThatTheTrainMet() async throws {
        let (model, store) = try makeModel(
            maps: catalog(slotId: "gabu_digitama", [Fixture.trainedAtLeastOnce()]))
        await model.start()
        model.selectMap("grass")

        // No session yet, so start's refresh dropped nothing.
        XCTAssertEqual(try store.allStates().count, 1)

        // One round: begin() counts the session, finish() runs the drop check.
        XCTAssertNotNil(model.train(), "the training round opened")
        model.finishTraining(.good)

        XCTAssertEqual(try store.allStates().count, 2, "the train earned the egg")
        XCTAssertEqual(model.pendingDigitamaDrop?.id, "gabu_digitama")
    }

    // MARK: after a battle

    /// THE AC (battle path): filing a battle result runs a drop check, so a slot gated on
    /// `care.battleCount` drops once the fight is recorded.
    func testFinishingABattleDropsAConditionThatTheBattleMet() async throws {
        let condition = EvolutionCondition(metric: .careBattleCount, window: .lifetime,
                                           comparison: .atLeast, value: 1, hint: "Fight a battle")
        let (model, store) = try makeModel(maps: catalog(slotId: "gabu_digitama", [condition]))
        await model.start()
        model.selectMap("grass")

        XCTAssertEqual(try store.allStates().count, 1, "no battle fought yet")

        model.battle()
        _ = try XCTUnwrap(model.finishBattleRound(.good), "grading fights the fight")
        model.finishBattle()

        XCTAssertEqual(try store.allStates().count, 2, "the battle earned the egg")
        XCTAssertEqual(model.pendingDigitamaDrop?.id, "gabu_digitama")
        XCTAssertTrue(try store.heldDigitamaIds().contains("gabu_digitama"))
    }
}
