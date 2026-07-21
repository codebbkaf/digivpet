import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-129 — never stranded: the Agumon failsafe.
///
/// Three layers, the shape the other suites use: `StrandedRuleTests` pins the condition as pure
/// arithmetic over a box, `FailsafeGrantTests` drives a real `GameStore` on disk, and
/// `FailsafeModelTests` runs the two shipped call sites — a launch and the refresh that settles a
/// death — through `MainScreenModel` itself. Every clock is injected; nothing waits real time and
/// nothing asks HealthKit anything.
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

    /// Mid-morning, outside the 22:00–07:00 fallback sleep window.
    static let morning = date("2026-07-20 09:00")
    static let hour: TimeInterval = 60 * 60

    static func dead(_ id: String, stage: Stage = .child, isActive: Bool = true) -> GameState {
        let state = GameState(currentDigimonId: id, stage: stage, isActive: isActive,
                              now: morning)
        state.healthStatus = .dead
        state.diedAt = morning
        return state
    }

    static func alive(_ id: String, stage: Stage = .child, isActive: Bool = true) -> GameState {
        GameState(currentDigimonId: id, stage: stage, isActive: isActive, now: morning)
    }
}

// MARK: - The rule (pure)

final class StrandedRuleTests: XCTestCase {
    /// THE AC, both clauses at once: every owned Digimon dead and no unhatched egg in the box.
    func testABoxWhereEverythingIsDeadIsStranded() {
        XCTAssertTrue(StrandedFailsafe.isStranded(in: [Fixture.dead("greymon")]))
        XCTAssertTrue(StrandedFailsafe.isStranded(in: [Fixture.dead("greymon"),
                                                       Fixture.dead("gabumon", isActive: false)]))
    }

    /// AC1's first clause on its own: one living Digimon anywhere in the box — even frozen, even not
    /// the one that is out — is not a wipeout.
    func testALivingDigimonAnywhereInTheBoxIsNotStranded() {
        XCTAssertFalse(StrandedFailsafe.isStranded(in: [Fixture.alive("greymon")]))
        XCTAssertFalse(StrandedFailsafe.isStranded(in: [Fixture.dead("greymon"),
                                                        Fixture.alive("gabumon", isActive: false)]),
                       "the frozen one is still the player's")
    }

    /// AC1's second clause on its own: an unhatched egg in the box is something to raise, so a player
    /// whose Digimon died with an egg waiting is not stranded and gets no second one.
    func testAnUnhatchedDigitamaInTheBoxIsNotStranded() {
        XCTAssertFalse(StrandedFailsafe.isStranded(in: [
            Fixture.dead("greymon"),
            Fixture.alive("gabu_digitama", stage: .digitama, isActive: false)
        ]))
    }

    /// A DEAD egg is not something to raise. It reads as an unhatched Digitama on stage alone, which
    /// is why the rule asks about life first — a box holding only a corpse and a dead egg is stranded.
    func testADeadDigitamaDoesNotCountAsSomethingToRaise() {
        XCTAssertTrue(StrandedFailsafe.isStranded(in: [
            Fixture.dead("greymon"),
            Fixture.dead("gabu_digitama", stage: .digitama, isActive: false)
        ]))
    }

    /// The vacuous case, stated so it is a decision rather than an accident: an empty box is stranded.
    func testAnEmptyBoxIsStranded() {
        XCTAssertTrue(StrandedFailsafe.isStranded(in: []))
    }

    /// The egg the failsafe hands over is a real, playable Digitama — not an id typed into a
    /// constant. A rename in `roster.json` that missed this constant would strand the player it
    /// exists to rescue, and nothing else would catch it.
    func testTheFailsafeEggIsAPlayableDigitamaInTheShippedData() throws {
        let entry = try XCTUnwrap(Roster.bundled.entry(id: StrandedFailsafe.digitamaId),
                                  "\(StrandedFailsafe.digitamaId) is in the roster")
        XCTAssertEqual(entry.stage, .digitama)
        XCTAssertFalse(entry.dexOnly, "a dexOnly egg has no animated sheet and could never hatch")
        XCTAssertNotNil(EvolutionGraph.bundled.node(id: StrandedFailsafe.digitamaId),
                        "and it is wired into the graph, so the line is playable end to end")
    }
}

// MARK: - Through the store

@MainActor
final class FailsafeGrantTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FailsafeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// Seeds a store whose only Digimon has died, hatched from `origin`.
    @discardableResult
    private func seedWipeout(_ store: GameStore, origin: String = "gabu_digitama",
                             id: String = "gabumon") throws -> GameState {
        let state = try store.loadOrCreate(digitamaId: origin, now: Fixture.morning)
        state.currentDigimonId = id
        state.stage = .child
        state.healthStatus = .dead
        state.diedAt = Fixture.morning
        try store.save()
        return state
    }

    /// AC1: every owned Digimon dead and no egg in the box means `agu_digitama`, immediately — with
    /// no map selected, no condition met and nothing else asked of the player.
    func testAWipeoutIsHandedTheAgumonEgg() throws {
        let store = try GameStore(url: storeURL("Wipeout"))
        try seedWipeout(store)

        let egg = try XCTUnwrap(store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))

        XCTAssertEqual(egg.currentDigimonId, "agu_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(try store.allStates().count, 2, "it joined the box beside the corpse")
        XCTAssertTrue(try store.heldDigitamaIds().contains("agu_digitama"), "and is held at once")
        XCTAssertTrue(try store.dexIds().contains("agu_digitama"), "recorded like any egg handed over")
        XCTAssertTrue(try store.loadOrCreateProfile().ownedDigitamaIds.contains("agu_digitama"))
    }

    /// The egg lands the way a dropped one does — frozen and inactive — so US-124's one-active
    /// invariant holds and US-125 leaves its timeline alone until the player takes it out. The dead
    /// Digimon is still the active record, so the memorial the player is looking at does not vanish.
    func testTheFailsafeEggIsFrozenAndInactiveAndTheDeadDigimonStaysOut() throws {
        let store = try GameStore(url: storeURL("Frozen"))
        let corpse = try seedWipeout(store)

        let egg = try XCTUnwrap(store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))

        XCTAssertFalse(egg.isActive)
        XCTAssertEqual(egg.frozenSince, Fixture.morning)
        XCTAssertTrue(corpse.isActive, "the dead Digimon is still the one out")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1, "exactly one active")
    }

    /// AC2: the egg is handed over even though the dead Digimon hatched from that very egg. "Held"
    /// is about the living box, and a life already spent must not lock the player out of the next.
    func testTheEggIsGrantedEvenWhenTheDeadDigimonHatchedFromIt() throws {
        let store = try GameStore(url: storeURL("Repeat"))
        let corpse = try seedWipeout(store, origin: "agu_digitama", id: "greymon")
        XCTAssertEqual(corpse.originDigitamaId, "agu_digitama", "precondition: it was this egg")
        XCTAssertTrue(try store.loadOrCreateProfile().ownedDigitamaIds.contains("agu_digitama"),
                      "precondition: already ever-owned")

        let egg = try XCTUnwrap(store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))
        XCTAssertEqual(egg.currentDigimonId, "agu_digitama")
    }

    /// AC3: once per wipeout. The grant itself ends the wipeout, so a second call — and a third —
    /// hands over nothing, and the box still holds one egg.
    func testTheGrantIsIdempotentWithinOneWipeout() throws {
        let store = try GameStore(url: storeURL("Idempotent"))
        try seedWipeout(store)

        XCTAssertNotNil(try store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))
        XCTAssertNil(try store.grantFailsafeDigitamaIfStranded(now: Fixture.morning),
                     "the box is no longer stranded, so nothing more is owed")
        XCTAssertNil(try store.grantFailsafeDigitamaIfStranded(
            now: Fixture.morning.addingTimeInterval(30 * 24 * Fixture.hour)))
        XCTAssertEqual(try store.allStates().count, 2)
    }

    /// AC7, read off DISK on a second launch rather than off the objects still in memory: a player
    /// who quits while still holding the unhatched failsafe egg is not handed another on open.
    func testASecondLaunchWhileStillWipedOutGrantsNothing() throws {
        let url = storeURL("Relaunch")
        do {
            let store = try GameStore(url: url)
            try seedWipeout(store)
            XCTAssertNotNil(try store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))
        }

        let reopened = try GameStore(url: url)
        XCTAssertEqual(try reopened.allStates().count, 2, "precondition: the egg came back off disk")
        XCTAssertNil(try reopened.grantFailsafeDigitamaIfStranded(
            now: Fixture.morning.addingTimeInterval(Fixture.hour)))
        XCTAssertEqual(try reopened.allStates().count, 2, "still one corpse and one egg")
    }

    /// AC3's other half, and what "once per wipeout" is for: losing the failsafe egg too is a NEW
    /// wipeout, and the floor holds again.
    func testASecondWipeoutIsHandedAnotherEgg() throws {
        let store = try GameStore(url: storeURL("Twice"))
        try seedWipeout(store)
        let first = try XCTUnwrap(store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))

        // The failsafe egg is hatched, raised and lost as well.
        first.currentDigimonId = "agumon"
        first.stage = .child
        first.healthStatus = .dead
        try store.save()

        let second = try XCTUnwrap(store.grantFailsafeDigitamaIfStranded(
            now: Fixture.morning.addingTimeInterval(24 * Fixture.hour)))
        XCTAssertEqual(second.currentDigimonId, "agu_digitama")
        XCTAssertEqual(try store.allStates().count, 3)
    }

    /// A player who still has something alive is handed nothing — the failsafe is a floor, not a
    /// supply of free eggs.
    func testNothingIsGrantedWhileAnythingLives() throws {
        let store = try GameStore(url: storeURL("Alive"))
        try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)

        XCTAssertNil(try store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))
        XCTAssertEqual(try store.allStates().count, 1)
    }

    /// AC5 and AC6: what outlives a Digimon outlives the failsafe too. Nothing here goes near
    /// `resetGame`, so the lifetime total, the map selection and every step banked on a map are
    /// exactly what they were — asserted after a reopen, off disk.
    func testLifetimeEnergyAndMapProgressSurviveTheFailsafe() throws {
        let url = storeURL("Survives")
        do {
            let store = try GameStore(url: url)
            try seedWipeout(store)
            let profile = try store.loadOrCreateProfile()
            profile.lifetimeEnergy = EnergyTotals(strength: 111, vitality: 222,
                                                  spirit: 333, stamina: 444)
            profile.selectedMapId = "02_river"
            profile.record(steps: 900, forMap: "01_grassland")
            profile.markFinished("01_grassland", at: Fixture.morning)
            try store.save()

            XCTAssertNotNil(try store.grantFailsafeDigitamaIfStranded(now: Fixture.morning))
        }

        // The store is held in a local rather than chained (`GameStore(url:).loadOrCreateProfile()`):
        // ARC releases a temporary store the moment the call returns, and a released store's context
        // is reset, which DESTROYS the profile the assertions below are about — a fatal error, not a
        // failed assertion.
        let reopened = try GameStore(url: url)
        let profile = try reopened.loadOrCreateProfile()
        XCTAssertEqual(profile.lifetimeEnergy,
                       EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444),
                       "AC5: the player's whole earnings are untouched")
        XCTAssertEqual(profile.selectedMapId, "02_river", "AC6: still adventuring where they were")
        XCTAssertEqual(profile.recorded(forMap: "01_grassland"), 900)
        XCTAssertEqual(profile.finishedAt(forMap: "01_grassland"), Fixture.morning)
    }
}

// MARK: - Through the model, at the two shipped call sites

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class FailsafeModelTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FailsafeModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// The real ids, so the model's roster lookups are the shipped ones — the failsafe names a
    /// shipped id and a fixture graph of made-up eggs could not answer for it.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "agu_digitama", displayName: "Agu Digitama", stage: .digitama,
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "koromon", minEnergy: 5,
                                                     maxCareMistakes: 99)]),
            EvolutionNode(id: "koromon", displayName: "Koromon", stage: .babyII,
                          spriteFile: "Koromon")
        ])
    }

    private func makeModel(store: GameStore, now: Date) -> MainScreenModel {
        MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            roster: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// AC4, the launch check: a store that was left with nothing alive in it — the app killed after
    /// the last Digimon died — hands the player an egg as the screen opens.
    func testALaunchOnAWipedOutStoreGrantsTheEgg() async throws {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("Launch.store"))
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        state.currentDigimonId = "koromon"
        state.stage = .babyII
        state.healthStatus = .dead
        state.diedAt = Fixture.morning
        try store.save()

        let model = makeModel(store: store, now: Fixture.morning)
        await model.start()

        XCTAssertEqual(try store.allStates().count, 2, "the egg was waiting before the first draw")
        XCTAssertTrue(try store.heldDigitamaIds().contains("agu_digitama"))
        XCTAssertTrue(model.discoveredDigimonIds.contains("agu_digitama"),
                      "and the Dex set the screens read is in step")
        XCTAssertNotNil(model.memorial, "the memorial is still up — the egg is taken out from the box")
        XCTAssertNil(model.pendingDigitamaDrop, "a floor is not announced as a reward")
    }

    /// AC4, the death check, through the REAL rule rather than a hand-set flag: a Digimon 72 hours
    /// sick is found dead by `refresh()`, and the same refresh leaves the egg in the box.
    func testTheRefreshThatFindsTheDigimonDeadGrantsTheEgg() async throws {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("Death.store"))
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        state.currentDigimonId = "koromon"
        state.stage = .babyII
        state.healthStatus = .sick
        state.sickSince = Fixture.morning.addingTimeInterval(-80 * Fixture.hour)
        state.healthDataLastSeen = Fixture.morning
        state.hungerUpdatedAt = Fixture.morning
        try store.save()

        let model = makeModel(store: store, now: Fixture.morning)
        await model.start()

        XCTAssertEqual(model.state?.healthStatus, .dead, "precondition: the refresh killed it")
        XCTAssertEqual(try store.allStates().count, 2)
        XCTAssertEqual(try store.allStates().first { $0.stage == .digitama }?.currentDigimonId,
                       "agu_digitama")
    }

    /// AC7 through the model: a second launch while the failsafe egg is still sitting unhatched in
    /// the box does not hand over another. The box, not a stored flag, is what remembers.
    func testASecondLaunchDoesNotGrantASecondEgg() async throws {
        let url = storeDirectory.appendingPathComponent("Twice.store")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
            state.currentDigimonId = "koromon"
            state.stage = .babyII
            state.healthStatus = .dead
            state.diedAt = Fixture.morning
            try store.save()
            await makeModel(store: store, now: Fixture.morning).start()
            XCTAssertEqual(try store.allStates().count, 2, "precondition: the first launch granted")
        }

        let reopened = try GameStore(url: url)
        let later = Fixture.morning.addingTimeInterval(2 * Fixture.hour)
        await makeModel(store: reopened, now: later).start()

        XCTAssertEqual(try reopened.allStates().count, 2, "AC7: one egg, not two")
        XCTAssertEqual(try reopened.allStates().filter { $0.currentDigimonId == "agu_digitama" }.count,
                       1)
    }

    /// A living Digimon is left entirely alone: the ordinary launch grants nothing and the box still
    /// holds exactly the one record it did.
    func testAnOrdinaryLaunchGrantsNothing() async throws {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("Ordinary.store"))
        let model = makeModel(store: store, now: Fixture.morning)
        await model.start()

        XCTAssertEqual(try store.allStates().count, 1)
        XCTAssertNil(model.memorial)
    }
}
