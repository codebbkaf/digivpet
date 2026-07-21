import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-124: the store may hold several Digimon, of which exactly one is ACTIVE.
///
/// The invariant under test is a property of the whole store rather than of any one record, so
/// every assertion here counts the actives across `allStates()` rather than trusting the flag on
/// the record that was just written. Where it matters the count is taken through a REOPENED store,
/// so what is asserted came off disk and not out of the first context's cache.
@MainActor
final class GameBoxTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("Box.store") }

    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 800_000)
    private let t2 = Date(timeIntervalSinceReferenceDate: 900_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GameBoxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - AC1: the flag, and a store that holds more than one

    /// A brand new Digimon is the one you are raising, so it is born active — which is what keeps
    /// every path that existed before this story (first launch, reset, rebirth) unchanged.
    func testAFreshGameStateIsBornActive() {
        XCTAssertTrue(GameState(currentDigimonId: "agu_digitama", now: t0).isActive)
    }

    /// The box's other Digimon are created frozen, which is the caller US-126 will be.
    func testAGameStateCanBeCreatedFrozen() {
        XCTAssertFalse(GameState(currentDigimonId: "gabu_digitama", isActive: false, now: t0).isActive)
    }

    /// The flag is persisted, not merely held in memory: a frozen Digimon must still be frozen
    /// after a relaunch, or the box would come back with two of them out.
    func testTheActiveFlagRoundTripsThroughDisk() throws {
        do {
            let store = try GameStore(url: storeURL)
            _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
            store.container.mainContext.insert(
                GameState(currentDigimonId: "gabu_digitama", isActive: false, now: t1))
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let box = try reopened.allStates()
        XCTAssertEqual(box.map(\.currentDigimonId), ["agu_digitama", "gabu_digitama"])
        XCTAssertEqual(box.map(\.isActive), [true, false])
    }

    /// AC1: the store may hold many records — the thing `loadOrCreate` fetching `.first` made
    /// impossible to express before this story.
    func testTheStoreHoldsEveryDigimonPutInIt() throws {
        let store = try GameStore(url: storeURL)
        try seedBox(in: store)

        XCTAssertEqual(try store.allStates().count, 3)
    }

    // MARK: - AC2: allStates, activeState, and what savedState now means

    /// `allStates()` is the box, oldest first — a stable order the party list can draw without
    /// reshuffling between launches.
    func testAllStatesReturnsTheWholeBoxOldestFirst() throws {
        let store = try GameStore(url: storeURL)
        try seedBox(in: store)

        XCTAssertEqual(try store.allStates().map(\.currentDigimonId),
                       ["agu_digitama", "gabu_digitama", "piyo_digitama"])
    }

    /// AC2: `activeState()` picks the active record out of a box where it is not the first one.
    /// A test where the active Digimon is also the oldest cannot tell this apart from `.first`.
    func testActiveStateReturnsTheActiveRecordAndNotTheFirstOne() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[2])

        XCTAssertEqual(try store.activeState()?.currentDigimonId, "piyo_digitama")
        XCTAssertEqual(try store.allStates().first?.currentDigimonId, "agu_digitama")
    }

    /// AC2: `savedState()` returns the ACTIVE record. Every caller of it wanted the Digimon on
    /// screen, and that is what it still hands back.
    func testSavedStateReturnsTheActiveRecord() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[1])

        XCTAssertEqual(try store.savedState()?.currentDigimonId, "gabu_digitama")
    }

    /// The empty box is still nil rather than a freshly hatched Digimon: opening a read-only
    /// screen must not be what starts a game.
    func testSavedStateIsNilOnAnEmptyStore() throws {
        XCTAssertNil(try GameStore(url: storeURL).savedState())
        XCTAssertEqual(try GameStore(url: storeURL).allStates().count, 0)
    }

    // MARK: - AC4: activate is one transaction

    func testActivateFreezesThePreviousDigimonAndPutsOutTheNewOne() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)

        try store.activate(box[1])

        XCTAssertEqual(box.map(\.isActive), [false, true, false])
    }

    /// Both flips are on disk together — the store goes straight from "A is out" to "B is out",
    /// with no reopen that can find zero active or two.
    func testActivateIsDurableInOneTransaction() throws {
        do {
            let store = try GameStore(url: storeURL)
            let box = try seedBox(in: store)
            try store.activate(box[2])
        }

        let reopened = try GameStore(url: storeURL)
        XCTAssertEqual(try reopened.activeState()?.currentDigimonId, "piyo_digitama")
        XCTAssertEqual(try reopened.allStates().filter(\.isActive).count, 1)
        // Asserted explicitly rather than left to the count: the one that WAS out is the one that
        // has to have been frozen by the same save.
        XCTAssertEqual(try reopened.allStates().first(where: { $0.currentDigimonId == "agu_digitama" })?.isActive,
                       false)
    }

    /// Activating the Digimon already out is a no-op, so a party screen need not special-case the
    /// row the player is already standing on.
    func testActivatingTheDigimonAlreadyOutChangesNothing() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)

        try store.activate(box[0])

        XCTAssertEqual(box.map(\.isActive), [true, false, false])
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "agu_digitama")
    }

    /// A store that had somehow drifted into two active comes back correct, because `activate`
    /// writes EVERY record rather than only the two it is moving between.
    func testActivateRepairsAStoreThatHadTwoActive() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        box[1].isActive = true
        try store.save()
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 2)

        try store.activate(box[2])

        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "piyo_digitama")
    }

    // MARK: - AC5: at most one active, asserted directly

    func testExactlyOneIsActiveAfterAFreshStart() throws {
        let store = try GameStore(url: storeURL)
        _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)

        try assertExactlyOneActive(in: store)
    }

    func testExactlyOneIsActiveAfterAnActivate() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)

        try store.activate(box[1])

        try assertExactlyOneActive(in: store)
    }

    /// AC5's third case. The failure is a real one and not a contrived throw: a `GameState` from a
    /// DIFFERENT store is a live, inserted record whose id this store simply does not hold, which
    /// is exactly what US-126 would hand in if it ever cached a row across stores.
    func testAFailedActivateLeavesTheBoxExactlyAsItWas() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[1])

        let other = try GameStore(url: directory.appendingPathComponent("Other.store"))
        let stranger = try other.loadOrCreate(digitamaId: "piyo_digitama", now: t0)

        XCTAssertThrowsError(try store.activate(stranger)) { error in
            XCTAssertEqual(error as? GameStoreError, .stateNotInStore)
        }

        try assertExactlyOneActive(in: store)
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(box.map(\.isActive), [false, true, false])
    }

    /// The refusal is decided BEFORE anything is mutated, so it survives a reopen too — a failed
    /// activate that had already flipped a flag in memory would leave the next save to write it.
    func testAFailedActivateWritesNothingToDisk() throws {
        do {
            let store = try GameStore(url: storeURL)
            let box = try seedBox(in: store)
            try store.activate(box[2])

            let other = try GameStore(url: directory.appendingPathComponent("Other.store"))
            let stranger = try other.loadOrCreate(digitamaId: "agu_digitama", now: t0)
            XCTAssertThrowsError(try store.activate(stranger))
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        try assertExactlyOneActive(in: reopened)
        XCTAssertEqual(try reopened.activeState()?.currentDigimonId, "piyo_digitama")
    }

    // MARK: - AC6: reset and rebirth still work, and still on the active record

    /// A total wipe means the whole box: the player asked to start over, not to keep the Digimon
    /// they had put away.
    func testResetGameEmptiesTheBoxAndLeavesOneActiveDigimon() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[1])

        let fresh = try store.resetGame(digitamaId: "koro_digitama", now: t2)

        XCTAssertEqual(try store.allStates().map(\.currentDigimonId), ["koro_digitama"])
        XCTAssertTrue(fresh.isActive)
        try assertExactlyOneActive(in: store)
        XCTAssertEqual(try store.savedState()?.currentDigimonId, "koro_digitama")
    }

    /// Rebirth still carries the lifetime total across, and still ends with exactly one Digimon
    /// out — the behaviour US-029 and US-123 pinned, now on a store that could hold several.
    func testRebirthCarriesLifetimeEnergyAndLeavesOneActiveDigimon() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[2])
        try store.loadOrCreateProfile().lifetimeEnergy =
            EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444)
        try store.save()

        let reborn = try store.rebirth(digitamaId: "koro_digitama", now: t2)

        XCTAssertEqual(reborn.currentDigimonId, "koro_digitama")
        XCTAssertTrue(reborn.isActive)
        try assertExactlyOneActive(in: store)
        XCTAssertEqual(try store.loadOrCreateProfile().lifetimeEnergy,
                       EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444))
    }

    /// `loadOrCreate` returns the ACTIVE Digimon rather than starting a new one, on a box where
    /// the active record is not the first — the case that would have wiped the box if it had
    /// fallen through to `resetGame`.
    func testLoadOrCreateReturnsTheActiveDigimonOutOfABox() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        try store.activate(box[1])

        let loaded = try store.loadOrCreate(digitamaId: "koro_digitama", now: t2)

        XCTAssertEqual(loaded.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(try store.allStates().count, 3)
    }

    /// A box whose records are somehow ALL frozen must not be wiped. Nothing here can produce that
    /// state, which is why the recovery is worth having: the alternative is `resetGame` deleting
    /// Digimon the player still owns.
    func testABoxWithNothingActiveAdoptsTheOldestRatherThanBeingWiped() throws {
        let store = try GameStore(url: storeURL)
        let box = try seedBox(in: store)
        for state in box { state.isActive = false }
        try store.save()

        let loaded = try store.loadOrCreate(digitamaId: "koro_digitama", now: t2)

        XCTAssertEqual(loaded.currentDigimonId, "agu_digitama")
        XCTAssertEqual(try store.allStates().count, 3)
        try assertExactlyOneActive(in: store)
    }

    // MARK: - AC3 / AC7: a store from before the box opens with its Digimon out

    /// AC3, against a REAL pre-box store — `Tests/Fixtures/pre-us123.store`, written by a build
    /// that had no `isActive` column at all. A fixture this build constructs cannot prove this:
    /// its record would be written through the new model with the flag already set.
    func testAPreBoxStoreMigratesWithItsOnlyDigimonActive() throws {
        let url = try copyPreMigrationFixture()
        let store = try GameStore(url: url)

        _ = try store.loadOrCreateProfile()

        let box = try store.allStates()
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box.first?.currentDigimonId, "greymon")
        XCTAssertTrue(try XCTUnwrap(box.first).isActive)
        try assertExactlyOneActive(in: store)
    }

    /// AC7: the migration is a backstop, not the mechanism. A player who ran the US-123 build
    /// already HAS a profile, so `loadOrCreateProfile` returns early and never reaches the stamp —
    /// and their Digimon still has to be the one on screen. It is, because an unwritten flag reads
    /// as active.
    func testAPreBoxStoreShowsItsDigimonEvenWithoutRunningTheMigration() throws {
        let url = try copyPreMigrationFixture()
        let store = try GameStore(url: url)

        let saved = try store.savedState()

        XCTAssertEqual(saved?.currentDigimonId, "greymon")
        XCTAssertEqual(saved?.stage, .adult)
        XCTAssertEqual(try store.loadOrCreate(digitamaId: "agu_digitama", now: t2).currentDigimonId,
                       "greymon")
    }

    /// And the stamp is durable: reopened after the migration, the record is still the one out and
    /// still the only one.
    func testTheMigratedFlagSurvivesAReopen() throws {
        let url = try copyPreMigrationFixture()
        do {
            let store = try GameStore(url: url)
            _ = try store.loadOrCreateProfile()
            try store.save()
        }

        let reopened = try GameStore(url: url)
        XCTAssertEqual(try reopened.activeState()?.currentDigimonId, "greymon")
        try assertExactlyOneActive(in: reopened)
    }

    // MARK: -

    /// Three Digimon, oldest first, with the oldest one out — the shape every box test starts from.
    /// Returned in `allStates()` order, so `box[1]` in a test is the same record the store's own
    /// ordering calls second.
    @discardableResult
    private func seedBox(in store: GameStore) throws -> [GameState] {
        _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        let context = store.container.mainContext
        context.insert(GameState(currentDigimonId: "gabu_digitama", isActive: false, now: t1))
        context.insert(GameState(currentDigimonId: "piyo_digitama", isActive: false, now: t2))
        try store.save()
        return try store.allStates()
    }

    private func assertExactlyOneActive(
        in store: GameStore, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let active = try store.allStates().filter(\.isActive)
        XCTAssertEqual(active.count, 1,
                       "expected exactly one active Digimon, found \(active.map(\.currentDigimonId))",
                       file: file, line: line)
    }

    /// Copies the committed pre-US-123 store into this test's own directory, sidecars and all.
    /// SwiftData opens the file read-write and migrates it in place, so the bundle's copy must
    /// never be the one opened — the second test to run would find it already migrated.
    private func copyPreMigrationFixture() throws -> URL {
        let bundle = Bundle(for: Self.self)
        let store = try XCTUnwrap(bundle.url(forResource: "pre-us123", withExtension: "store"),
                                  "the pre-migration fixture must be bundled with the tests")
        let destination = directory.appendingPathComponent("pre-us123.store")
        try FileManager.default.copyItem(at: store, to: destination)
        for sidecar in ["store-wal", "store-shm"] {
            guard let url = bundle.url(forResource: "pre-us123", withExtension: sidecar) else { continue }
            try FileManager.default.copyItem(
                at: url, to: directory.appendingPathComponent("pre-us123.\(sidecar)"))
        }
        return destination
    }
}
