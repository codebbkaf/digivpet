import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// No health data at all, which is what the Simulator has and what this story is not about: the
/// migration must land the same whether or not the first refresh credits anything.
private final class NoProfileSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class NoProfileSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// US-123: what outlives a Digimon lives on `PlayerProfile`, and an existing save migrates onto it.
///
/// The migration is the risky half, so it is tested against a REAL FILE written by the previous
/// build — `Tests/Fixtures/pre-us123.store`, produced by running the commit before this story and
/// copying the store out of the Simulator. A fixture the new build constructs cannot prove a
/// migration: it would be written through the new model, under the new schema, and every column
/// would already be where this code expects it.
@MainActor
final class PlayerProfileTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("Profile.store") }

    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 900_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayerProfileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - AC1 / AC2: the model, and the schema it has to be in

    /// AC1: everything global, on one record — the lifetime total, where the player is, what they
    /// have walked and finished, and the eggs they have ever owned.
    func testTheProfileHoldsEverythingThatOutlivesADigimon() {
        let profile = PlayerProfile(
            lifetimeEnergy: EnergyTotals(strength: 1, vitality: 2, spirit: 3, stamina: 4),
            selectedMapId: "02_river",
            recorded: ["02_river": 1_222],
            finishedAt: ["01_grassland": t0],
            ownedDigitamaIds: ["agu_digitama", "gabu_digitama"])

        XCTAssertEqual(profile.lifetimeEnergy.total, 10)
        XCTAssertEqual(profile.selectedMapId, "02_river")
        XCTAssertEqual(profile.recorded(forMap: "02_river"), 1_222)
        XCTAssertEqual(profile.finishedAt(forMap: "01_grassland"), t0)
        XCTAssertTrue(profile.isFinished(forMap: "01_grassland"))
        XCTAssertFalse(profile.isFinished(forMap: "02_river"))
        XCTAssertEqual(profile.ownedDigitamaIds, ["agu_digitama", "gabu_digitama"])
    }

    /// AC2 asserted directly on the schema, because the failure it guards against is silent: a
    /// `@Model` missing from `GameStore.schema` still compiles, still holds values in memory for a
    /// whole session, and simply never reaches disk.
    func testTheProfileIsInTheStoresSchema() {
        XCTAssertTrue(GameStore.schema.entities.contains { $0.name == "PlayerProfile" },
                      "a @Model missing from the schema is never saved")
    }

    /// And the same claim the expensive way: written, stack dropped, read off disk through a new
    /// container. Only this can catch a schema that lists the type but a store that cannot hold it.
    func testEveryProfileFieldRoundTripsThroughTheStore() throws {
        do {
            let store = try GameStore(url: storeURL)
            let profile = try store.loadOrCreateProfile()
            profile.lifetimeEnergy = EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88)
            profile.meat = 12
            profile.selectedMapId = "08_jungle"
            profile.record(steps: 4_321, forMap: "08_jungle")
            profile.markFinished("01_grassland", at: t1)
            profile.record(ownedDigitama: "koro_digitama")
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let profile = try reopened.loadOrCreateProfile()
        XCTAssertEqual(profile.lifetimeEnergy,
                       EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88))
        XCTAssertEqual(profile.meat, 12, "the global larder survives to the next launch")
        XCTAssertEqual(profile.selectedMapId, "08_jungle")
        XCTAssertEqual(profile.recorded(forMap: "08_jungle"), 4_321)
        XCTAssertEqual(profile.finishedAt(forMap: "01_grassland"), t1)
        XCTAssertTrue(profile.ownedDigitamaIds.contains("koro_digitama"))
    }

    // MARK: - AC4: one way in

    /// `loadOrCreateProfile` is the only door, so calling it twice must not leave two profiles —
    /// two would each be half the player's history, and which one the app read would be a fetch
    /// order nobody controls.
    func testLoadOrCreateProfileReturnsTheSameRecordEveryTime() throws {
        let store = try GameStore(url: storeURL)
        let first = try store.loadOrCreateProfile()
        first.lifetimeEnergy[.spirit] = 12

        let second = try store.loadOrCreateProfile()
        XCTAssertEqual(second.lifetimeEnergy[.spirit], 12)
        XCTAssertEqual(try store.container.mainContext.fetch(FetchDescriptor<PlayerProfile>()).count, 1)
    }

    // MARK: - AC3: every read of the lifetime total goes through the profile

    /// Crediting energy tops up the Digimon's stage total and the PLAYER's lifetime total, and the
    /// second one is on the profile. The `GameState` cannot answer for it at all any more — there
    /// is no property to read — so this is where the two totals are proved to still both accrue.
    func testCreditingEnergyAccruesTheLifetimeTotalOntoTheProfile() throws {
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        let profile = try store.loadOrCreateProfile()
        let ledger = try store.loadOrCreateLedger(now: t0)

        EnergyCreditor.credit([.strength: .value(1_000)], to: state, profile: profile,
                              ledger: ledger, now: t0)

        XCTAssertEqual(state.stageEnergy.strength, 10)
        XCTAssertEqual(profile.lifetimeEnergy.strength, 10, "the player's total, on the player")
    }

    /// The reason it moved: a death must not cost the player their earnings, and since US-123 that
    /// is true because nothing copies them — the record they live on is not the one being replaced.
    func testTheLifetimeTotalSurvivesARebirthWithoutBeingCopied() throws {
        let store = try GameStore(url: storeURL)
        _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        let profile = try store.loadOrCreateProfile()
        profile.lifetimeEnergy = EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444)
        profile.record(steps: 900, forMap: "01_grassland")
        try store.save()

        let reborn = try store.rebirth(digitamaId: "gabu_digitama", now: t1)

        XCTAssertEqual(reborn.currentDigimonId, "gabu_digitama", "a new Digimon")
        XCTAssertEqual(try store.loadOrCreateProfile().lifetimeEnergy,
                       EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444),
                       "and the same player")
        XCTAssertEqual(try store.loadOrCreateProfile().recorded(forMap: "01_grassland"), 900,
                       "the maps they walked outlive the Digimon that walked them")
    }

    /// The debug reset is still a total wipe of the player, which is what it is for — and the one
    /// place the lifetime total is deliberately destroyed rather than carried.
    func testResettingTheGameWipesTheLifetimeTotalButNotTheMaps() throws {
        let store = try GameStore(url: storeURL)
        _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        let profile = try store.loadOrCreateProfile()
        profile.lifetimeEnergy = EnergyTotals(strength: 500, vitality: 500, spirit: 500, stamina: 500)
        profile.record(steps: 900, forMap: "01_grassland")
        try store.save()

        _ = try store.resetGame(digitamaId: "gabu_digitama", now: t1)

        XCTAssertEqual(try store.loadOrCreateProfile().lifetimeEnergy, .zero)
        XCTAssertEqual(try store.loadOrCreateProfile().recorded(forMap: "01_grassland"), 900,
                       "map progress is not the Digimon's to lose")
    }

    /// The egg the player is handed is an egg the player owns, on both paths that hand one over.
    func testStartingAGameRecordsTheDigitamaAsOwned() throws {
        let store = try GameStore(url: storeURL)
        _ = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        XCTAssertEqual(try store.loadOrCreateProfile().ownedDigitamaIds, ["agu_digitama"])

        _ = try store.rebirth(digitamaId: "gabu_digitama", now: t1)
        XCTAssertEqual(try store.loadOrCreateProfile().ownedDigitamaIds,
                       ["agu_digitama", "gabu_digitama"],
                       "ever owned, so the dead one's egg is still on the list")
    }

    // MARK: - AC5 / AC6: the migration, against a store the PREVIOUS build wrote

    /// AC6, and the reason this file carries a binary fixture: the store opened here was written by
    /// the build at the commit before US-123, with `lifetimeEnergy` on the `GameState` and the map
    /// fields on a `MapProgress` record. Nothing in this test constructs the new shape.
    ///
    /// AC5 in full: the Digimon comes back whole — stage, energy, care mistakes, poop, the battle
    /// record, the light state and the sickness — and its lifetime energy is on a profile that did
    /// not exist when the file was written.
    func testAStoreFromThePreviousBuildOpensWithTheDigimonIntactAndTheEnergyMigrated() throws {
        let url = try copyPreMigrationFixture()

        let store = try GameStore(url: url)
        let state = try XCTUnwrap(store.savedState(), "the saved Digimon survived the migration")

        // Everything the old build wrote about the Digimon, unchanged.
        XCTAssertEqual(state.currentDigimonId, "greymon")
        XCTAssertEqual(state.stage, .adult)
        XCTAssertEqual(state.stageEnergy, EnergyTotals(strength: 11, vitality: 22, spirit: 33, stamina: 44))
        XCTAssertEqual(state.birthDate, Date(timeIntervalSinceReferenceDate: 700_000))
        XCTAssertEqual(state.stageEnteredDate, Date(timeIntervalSinceReferenceDate: 900_000))
        XCTAssertEqual(state.careMistakeCount, 2)
        XCTAssertEqual(state.hunger, 3)
        XCTAssertEqual(state.strengthStat, 17)
        XCTAssertEqual(state.healthStatus, .sick)
        XCTAssertEqual(state.sickSince, Date(timeIntervalSinceReferenceDate: 950_000))
        XCTAssertEqual(state.battleWins, 5)
        XCTAssertEqual(state.battleLosses, 6)
        XCTAssertEqual(state.poopCount, 4)
        XCTAssertEqual(state.lightState, .off)

        // And the one thing that moved.
        let profile = try store.loadOrCreateProfile()
        XCTAssertEqual(profile.lifetimeEnergy,
                       EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88),
                       "the old save's lifetime energy is on the new profile")
        XCTAssertEqual(profile.meat, 0,
                       "US-174: an existing save migrates to an empty larder, not a full one")
    }

    /// The map fields moved too, and the record they came off is deleted — two answers to "where am
    /// I adventuring" is one too many, and the one nothing writes must not be the one that lingers.
    func testThePreviousBuildsMapProgressIsAdoptedAndTheOldRecordRemoved() throws {
        let url = try copyPreMigrationFixture()

        let store = try GameStore(url: url)
        let profile = try store.loadOrCreateProfile()

        XCTAssertEqual(profile.selectedMapId, "02_river")
        XCTAssertEqual(profile.recorded(forMap: "02_river"), 1_234)
        XCTAssertEqual(profile.recorded(forMap: "01_grassland"), 3_000)
        XCTAssertEqual(profile.finishedAt(forMap: "01_grassland"),
                       Date(timeIntervalSinceReferenceDate: 900_000))
        XCTAssertTrue(try store.container.mainContext.fetch(FetchDescriptor<MapProgress>()).isEmpty,
                      "the drained record is gone")
    }

    /// The migration runs ONCE. A second launch must read the profile it wrote rather than build
    /// another one from a `GameState` whose legacy column is now a stale duplicate — which would
    /// silently roll the player's energy back to what it was the day they upgraded.
    func testTheMigrationDoesNotRunASecondTime() throws {
        let url = try copyPreMigrationFixture()

        do {
            let store = try GameStore(url: url)
            let profile = try store.loadOrCreateProfile()
            profile.lifetimeEnergy[.strength] += 1_000
            profile.selectedMapId = "08_jungle"
            try store.save()
        }

        let reopened = try GameStore(url: url)
        let profile = try reopened.loadOrCreateProfile()
        XCTAssertEqual(profile.lifetimeEnergy.strength, 1_055, "played on, not migrated again")
        XCTAssertEqual(profile.selectedMapId, "08_jungle")
        XCTAssertEqual(try reopened.container.mainContext.fetch(FetchDescriptor<PlayerProfile>()).count, 1)
    }

    /// The Dex has recorded every egg the moment it was handed over since US-016, so "ever owned"
    /// is a fact the old save already knows. The fixture's Dex holds the egg it started at and the
    /// Adult it grew into; only the egg is a Digitama, and only the egg comes across.
    func testOwnedDigitamaAreSeededFromTheDexOnMigration() throws {
        let url = try copyPreMigrationFixture()

        let store = try GameStore(url: url)
        let owned = try store.loadOrCreateProfile().ownedDigitamaIds

        XCTAssertEqual(owned, ["agu_digitama"],
                       "the egg it hatched from, and not the Adult it became")
    }

    /// The migration through the APP's own path, which is the one that actually has to work: the
    /// screen opens the store, and what the player sees on the first launch after the upgrade is
    /// their Digimon and their earnings, not a fresh egg.
    ///
    /// The real graph and the real roster, because the fixture's `greymon` is a real node — a stub
    /// graph would prove only that the model tolerates an id it does not know.
    func testTheAppsOwnOpenPathMigratesTheStoreAndShowsTheSameDigimon() async throws {
        let url = try copyPreMigrationFixture()
        let store = try GameStore(url: url)
        let model = MainScreenModel(
            makeStore: { store },
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoProfileSampleFetcher()),
                sleepReader: LastNightSleepReader(fetcher: NoProfileSleepFetcher())),
            now: { Date(timeIntervalSinceReferenceDate: 1_000_000) })

        await model.start()

        XCTAssertEqual(model.phase, .playing, "the store opened rather than failing to migrate")
        XCTAssertEqual(model.state?.currentDigimonId, "greymon", "the same Digimon it was raising")
        XCTAssertEqual(model.lifetimeEnergy,
                       EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88),
                       "and the same earnings, read through the profile")
        XCTAssertEqual(model.selectedMapAsset, "02_river",
                       "still adventuring where it was, off the migrated selection")
    }

    /// AC7: the two ledgers are untouched by all of this — still one record each, still carrying
    /// what the old build banked, because a migration that refunded today's cap would let the day's
    /// steps be earned twice.
    func testTheLedgersAreStillSingleGlobalRecordsAfterTheMigration() throws {
        let url = try copyPreMigrationFixture()

        let store = try GameStore(url: url)
        _ = try store.loadOrCreateProfile()
        _ = try store.loadOrCreateLedger(now: t1)
        _ = try store.loadOrCreateMetricLedger(now: t1)

        let context = store.container.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<EnergyLedger>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MetricLedger>()).count, 1)
    }

    // MARK: -

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
