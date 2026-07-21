import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-127: one of each Digitama, ever — until it dies.
///
/// The rule is "a map cannot drop an egg the player already HOLDS", where held means an unhatched
/// egg in the box or any LIVING Digimon that hatched from one, and it has to survive a Digimon
/// evolving six times. It rests on two facts: every `GameState` remembers the `originDigitamaId` it
/// hatched from and carries it UNCHANGED through evolution, and the held set is derived off that from
/// the LIVING records — so a death releases an id for free.
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
        guard let date = formatter.date(from: iso) else { preconditionFailure("bad fixture date \(iso)") }
        return date
    }

    static let morning = date("2026-07-17 08:00")
    static let born = date("2026-07-10 08:00")
}

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - The origin, and the held set, as arithmetic

/// The pure half: `originDigitamaId` is carried across evolution, the held set is the living records'
/// origins, and the graph can recover an evolved save's egg. No store, no Simulator.
@MainActor
final class HeldDigitamaRuleTests: XCTestCase {
    /// AC4 (records) + the six-evolutions requirement: `advance` moves `currentDigimonId` but never
    /// the origin, so a Digimon six forms deep still names the egg it came from. Simulated here the
    /// way `advance` really works — by reassigning the id — so the rule is asserted at its mechanism.
    func testOriginDigitamaIsCarriedUnchangedThroughEveryEvolution() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Fixture.born)
        XCTAssertEqual(state.originDigitamaId, "agu_digitama", "a fresh egg is its own origin")

        for form in ["botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"] {
            state.currentDigimonId = form
        }

        XCTAssertEqual(state.originDigitamaId, "agu_digitama",
                       "six digivolutions later, still the egg it hatched from")
    }

    /// AC1 + AC5: the held set is exactly the origins of the LIVING records — an unhatched egg (its
    /// own origin), a living evolved Digimon (the egg it carries), and NOT a dead one's.
    func testHeldSetIsTheLivingRecordsOrigins() {
        let egg = GameState(currentDigimonId: "koro_digitama", now: Fixture.born)
        let alive = GameState(currentDigimonId: "greymon", stage: .adult,
                              originDigitamaId: "agu_digitama", now: Fixture.born)
        let dead = GameState(currentDigimonId: "gabumon", stage: .child,
                             originDigitamaId: "gabu_digitama", now: Fixture.born)
        dead.healthStatus = .dead

        XCTAssertEqual(GameStore.heldDigitamaIds(in: [egg, alive, dead]),
                       ["koro_digitama", "agu_digitama"],
                       "the dead Digimon's egg is droppable again")
    }

    /// The backfill's one moving part: an evolved id traces down its line to the Digitama it hatched
    /// from, an egg is its own root, and an id the graph has never heard of has no root to give.
    func testDigitamaRootTracesAnEvolvedFormBackToItsEgg() {
        let graph = EvolutionGraph.bundled
        XCTAssertEqual(graph.digitamaRoot(of: "greymon"), "agu_digitama")
        XCTAssertEqual(graph.digitamaRoot(of: "agu_digitama"), "agu_digitama")
        XCTAssertNil(graph.digitamaRoot(of: "not_a_real_id"))
    }
}

// MARK: - The held set through the store

@MainActor
final class HeldDigitamaStoreTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("Held.store") }
    private var steps: EmptySampleFetcher!
    private var heldStore: GameStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HeldDigitamaTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        steps = EmptySampleFetcher()
    }

    override func tearDownWithError() throws {
        heldStore = nil
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// AC (drop → hatch → evolve twice → still held and blocked): starting a game holds the egg, and
    /// the record it becomes keeps holding it however far it evolves — so a map still cannot drop it.
    func testAnEggStaysHeldAsItsRecordEvolves() throws {
        let store = try GameStore(url: storeURL)
        heldStore = store
        let out = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        XCTAssertEqual(try store.heldDigitamaIds(), ["agu_digitama"], "the egg the player was handed")

        // Hatch, then evolve twice — the same record, `currentDigimonId` moving as `advance` moves it.
        out.currentDigimonId = "botamon"; out.stage = .babyI
        out.currentDigimonId = "koromon"; out.stage = .babyII
        out.currentDigimonId = "agumon"; out.stage = .child
        try store.save()

        XCTAssertEqual(out.originDigitamaId, "agu_digitama")
        XCTAssertTrue(try store.heldDigitamaIds().contains("agu_digitama"),
                      "still held, so a map still cannot drop it")
    }

    /// AC (drop → hatch → death → droppable again) + AC5: a Digimon's death releases its origin, and
    /// it does so for free — the dead record is simply filtered out of the derived set.
    func testDeathReleasesTheOriginDigitama() throws {
        let store = try GameStore(url: storeURL)
        heldStore = store
        let out = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        out.currentDigimonId = "agumon"; out.stage = .child
        try store.save()
        XCTAssertTrue(try store.heldDigitamaIds().contains("agu_digitama"))

        out.healthStatus = .dead
        out.diedAt = Fixture.born
        try store.save()

        XCTAssertFalse(try store.heldDigitamaIds().contains("agu_digitama"),
                       "a dead Digimon no longer holds its egg")
        XCTAssertTrue(try store.heldDigitamaIds().isEmpty)
    }

    /// A box of several Digimon holds every living one's egg at once — the derived set is the union.
    func testHeldIsTheUnionAcrossTheWholeBox() throws {
        let store = try GameStore(url: storeURL)
        heldStore = store
        let out = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        out.currentDigimonId = "greymon"; out.stage = .adult
        let context = store.container.mainContext
        context.insert(GameState(currentDigimonId: "gabu_digitama", isActive: false, now: Fixture.born))
        let gone = GameState(currentDigimonId: "koromon", stage: .babyII, isActive: false,
                             originDigitamaId: "koro_digitama", now: Fixture.born)
        gone.healthStatus = .dead
        context.insert(gone)
        try store.save()

        XCTAssertEqual(try store.heldDigitamaIds(), ["agu_digitama", "gabu_digitama"],
                       "the two living records' eggs, and not the dead one's")
    }

    // MARK: - AC2: the migration backfills an existing save's origin

    /// A save written before origins were tracked — the committed pre-US-123 fixture, whose Digimon
    /// is a `greymon` with no origin column — has its `originDigitamaId` recovered by tracing down
    /// the graph to the egg it hatched from. Nothing here constructs the new shape.
    func testMigrationBackfillsTheOriginFromAnEvolvedSave() throws {
        let url = try copyPreMigrationFixture()
        let store = try GameStore(url: url)
        _ = try store.loadOrCreateProfile()

        let state = try XCTUnwrap(store.savedState())
        XCTAssertEqual(state.currentDigimonId, "greymon", "the same Digimon the old build saved")
        XCTAssertEqual(state.originDigitamaId, "agu_digitama", "traced down greymon's line to the egg")
        XCTAssertTrue(state.hasStoredOrigin, "stamped, not merely read as the current-id fallback")
        XCTAssertEqual(try store.heldDigitamaIds(), ["agu_digitama"],
                       "so the migrated player's egg is held and cannot be dropped on them")
    }

    /// And it is a real WRITE: a store reopened without ever calling the migration again reads the
    /// origin straight off disk, so a later launch does not depend on the backfill running twice.
    func testTheBackfilledOriginIsPersisted() throws {
        let url = try copyPreMigrationFixture()
        do {
            let store = try GameStore(url: url)
            _ = try store.loadOrCreateProfile()
        }

        let reopened = try GameStore(url: url)
        let state = try XCTUnwrap(reopened.savedState())
        XCTAssertTrue(state.hasStoredOrigin, "the origin was written to the file, not inferred on read")
        XCTAssertEqual(state.originDigitamaId, "agu_digitama")
    }

    // MARK: - Through the app's own open path

    /// The real hatch is an `advance`, and this is the proof that the SHIPPED evolution path leaves
    /// the origin standing: the app opens on a fresh `agu_digitama`, 5,000 steps are walked, the
    /// ordinary refresh hatches it — and the record that comes out still names its egg and still
    /// holds it.
    func testTheRealHatchKeepsTheOrigin() async throws {
        let store = try GameStore(url: storeURL)
        heldStore = store
        let model = MainScreenModel(
            makeStore: { store },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(), calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { nodes in nodes.first { $0.id == "agu_digitama" } }
        )
        await model.start()
        XCTAssertEqual(model.state?.currentDigimonId, "agu_digitama")
        XCTAssertEqual(model.state?.originDigitamaId, "agu_digitama")

        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 06:00"),
                         end: Fixture.date("2026-07-17 06:30"), value: 5_000)
        ]
        await model.refresh()

        XCTAssertNotEqual(model.state?.currentDigimonId, "agu_digitama", "it hatched into something")
        XCTAssertEqual(model.state?.originDigitamaId, "agu_digitama", "and the real advance kept the egg")
        XCTAssertEqual(model.heldDigitamaIds, ["agu_digitama"])
    }

    // MARK: -

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
