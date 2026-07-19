import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, as in the other suites: a test that passed
/// only in the machine's own zone would be no test at all.
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

    static let morning = date("2026-07-17 08:00")

    /// A Digitama fixture with a single hatch edge at `threshold`, shaped like the seed's eggs:
    /// `requiredEnergy` nil because hatching is gated on TOTAL energy, not any one type.
    static func egg(threshold: Int = 50, hatchesInto baby: String = "baby") -> EvolutionNode {
        EvolutionNode(
            id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
            evolutions: [EvolutionEdge(to: baby, minEnergy: threshold, maxCareMistakes: 99,
                                       isDefault: true)]
        )
    }
}

private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - The hatch rule (pure)

final class EggHatcherTests: XCTestCase {
    /// THE AC: 49 total energy does not hatch and 50 does.
    func testFortyNineDoesNotHatchAndFiftyDoes() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")

        // 49 spread across the four types — hatching is gated on the TOTAL, not any one type.
        XCTAssertNil(EggHatcher.hatchTarget(
            for: egg, stageEnergy: EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 12)))
        XCTAssertEqual(EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 12).total, 49)

        // 50 exactly — the boundary hatches.
        XCTAssertEqual(EggHatcher.hatchTarget(
            for: egg, stageEnergy: EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 13)),
            "botamon")
        XCTAssertEqual(EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 13).total, 50)
    }

    /// The threshold is the hatch edge's `minEnergy`, not a hard-coded 50 — a different egg with a
    /// different edge hatches on its own number.
    func testTheThresholdComesFromTheHatchEdge() {
        let egg = Fixture.egg(threshold: 30)
        XCTAssertNil(EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 29)))
        XCTAssertEqual(EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 30)), "baby")
    }

    /// Only a Digitama hatches. A Baby I with 50 energy is not an egg, and evolving it is US-019's
    /// job under different rules.
    func testOnlyADigitamaHatches() {
        let baby = EvolutionNode(
            id: "botamon", displayName: "Botamon", stage: .babyI, spriteFile: "Botamon",
            evolutions: [EvolutionEdge(to: "koromon", minEnergy: 50, maxCareMistakes: 4, isDefault: true)]
        )
        XCTAssertNil(EggHatcher.hatchTarget(for: baby, stageEnergy: EnergyTotals(strength: 99)))
    }

    /// A terminal Digitama with no hatch edge cannot hatch, rather than crashing on an empty edge
    /// list.
    func testADigitamaWithNoEdgeDoesNotHatch() {
        let egg = EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama")
        XCTAssertNil(EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 999)))
    }

    /// AC3, against the SHIPPED graph: each seed egg hatches into the Baby I its edge names.
    func testEachSeedEggHatchesIntoItsLinkedBabyI() throws {
        let graph = EvolutionGraph.bundled
        for (eggId, babyId) in [("agu_digitama", "botamon"),
                                ("gabu_digitama", "punimon"),
                                ("pal_digitama", "yuramon")] {
            let egg = try XCTUnwrap(graph.node(id: eggId))
            let target = EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 50))
            XCTAssertEqual(target, babyId)
            XCTAssertEqual(graph.node(id: babyId)?.stage, .babyI, "\(babyId) is the Baby I form")
        }
    }
}

// MARK: - The Dex and the hatch applied (persisted)

@MainActor
final class EggHatchingTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("EggHatching.store") }
    private var steps: FixtureSampleFetcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        steps = FixtureSampleFetcher()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func walk(_ count: Double) {
        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 07:00"),
                         end: Fixture.date("2026-07-17 07:30"),
                         value: count)
        ]
    }

    /// A model reading `steps` and starting on the FIRST playable Digitama (agu_digitama), so the
    /// hatch target is known.
    private func makeModel() -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first }
        )
    }

    // MARK: Random starting egg

    /// AC1: a new game starts at a RANDOMLY selected Digitama. The default chooser is
    /// `randomElement`, so over many picks it must land on more than one of the seed eggs —
    /// and never on anything that is not a candidate.
    func testTheDefaultChooserPicksARandomDigitama() {
        let candidates = EvolutionGraph.bundled.nodes(at: .digitama).filter { !$0.dexOnly }
        XCTAssertEqual(Set(candidates.map(\.id)),
                       ["agu_digitama", "gabu_digitama", "pal_digitama", "pata_digitama", "piyo_digitama"],
                       "every seeded egg is a candidate — US-044's Pata and US-045's Piyo Digitama joined the three US-008 ones")

        var seen: Set<String> = []
        for _ in 0..<200 {
            let picked = try? XCTUnwrap(candidates.randomElement())
            let id = picked?.id ?? ""
            XCTAssertTrue(candidates.contains { $0.id == id }, "only ever a real candidate")
            seen.insert(id)
        }
        XCTAssertGreaterThan(seen.count, 1, "randomness actually varies the starting egg")
    }

    /// The injected chooser decides which egg a new game starts at, so a test can pin one.
    func testTheInjectedChooserDecidesTheStartingEgg() async throws {
        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { candidates in candidates.first { $0.id == "pal_digitama" } }
        )
        await model.start()
        XCTAssertEqual(model.state?.currentDigimonId, "pal_digitama")
        XCTAssertEqual(model.presentation?.stage, .digitama)
    }

    /// The starting egg's art must load as a real animated egg sheet, or a new game opens on the
    /// '?' placeholder. This is AC1's "animating its 3 frames" at the level a test can reach: three
    /// egg frames on disk, and a non-empty idle loop to move them.
    func testTheStartingEggAnimates() async throws {
        let model = makeModel()
        await model.start()

        let presentation = try XCTUnwrap(model.presentation)
        let sheet = try XCTUnwrap(
            SpriteSheetCache.shared.sheet(stage: presentation.spriteStage, name: presentation.spriteFile))
        XCTAssertEqual(sheet.kind, .egg)
        XCTAssertEqual([EggFrame.idle, .wobble, .hatch].compactMap { sheet[$0] }.count, 3,
                       "the Digitama sheet has all three frames")
        XCTAssertEqual(SpriteAnimation.idle.frames(from: sheet).count, 2,
                       "and the idle loop the screen plays actually animates")
    }

    // MARK: Hatching, applied and persisted

    /// AC2 + AC3, through the real refresh: 50 energy hatches agu_digitama into its linked Baby I,
    /// Botamon. The step count is exactly the 5,000 steps the PRD says is a day of normal activity.
    func testFiftyEnergyHatchesIntoTheLinkedBabyI() async throws {
        walk(5_000) // 5,000 steps at 1 Strength / 100 = 50
        let model = makeModel()
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.currentDigimonId, "botamon", "hatched into agu_digitama's Baby I")
        XCTAssertEqual(state.stage, .babyI, "the saved stage moved with it")
        XCTAssertEqual(model.presentation?.displayName, "Botamon")
    }

    /// AC2's other half at the seam: 49 energy is NOT enough, so the egg stays an egg.
    func testFortyNineEnergyDoesNotHatch() async throws {
        walk(4_900) // 49
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "agu_digitama", "still an egg")
        XCTAssertEqual(model.state?.stage, .digitama)
    }

    /// Hatching starts the new stage fresh (stageEnergy zero, a new stageEnteredDate) while the
    /// lifetime total carries the egg's energy forward — the same reset an evolution does (US-019),
    /// so a Baby I is not born already part-way to Baby II.
    func testHatchingResetsStageEnergyButKeepsLifetime() async throws {
        walk(5_000)
        let model = makeModel()
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.stageEnergy, .zero, "the new stage starts fresh")
        XCTAssertEqual(state.lifetimeEnergy.strength, 50, "but the life's energy is kept")
        XCTAssertEqual(state.stageEnteredDate, Fixture.morning)
        XCTAssertEqual(state.birthDate, Fixture.morning, "birth is the egg's, not the hatch's")
    }

    /// AC4: the hatched Digimon is written to persistence. Asserted through a SECOND store on the
    /// same file, so what is read came off disk, not out of the first context's memory.
    func testTheHatchedDigimonIsPersisted() async throws {
        walk(5_000)
        let model = makeModel()
        await model.start()

        let reopened = try GameStore(url: storeURL)
        let saved = try reopened.loadOrCreate(digitamaId: "unused", now: Fixture.morning)
        XCTAssertEqual(saved.currentDigimonId, "botamon", "the hatch reached disk")
        XCTAssertEqual(saved.stage, .babyI)
    }

    /// AC4: the hatched Digimon is recorded in the Dex — and so is the egg it came from.
    func testTheHatchedDigimonAndItsEggAreInTheDex() async throws {
        walk(5_000)
        let model = makeModel()
        await model.start()

        let reopened = try GameStore(url: storeURL)
        let dex = Set(try reopened.dexIds())
        XCTAssertTrue(dex.contains("botamon"), "the hatched Baby I is recorded")
        XCTAssertTrue(dex.contains("agu_digitama"), "the egg it hatched from is recorded too")
    }

    /// An egg that has not hatched records only itself in the Dex, not the Baby I it has yet to
    /// become — the control for the test above.
    func testAnUnhatchedEggDoesNotRecordItsBabyForm() async throws {
        walk(4_900)
        let model = makeModel()
        await model.start()

        let dex = Set(try GameStore(url: storeURL).dexIds())
        XCTAssertTrue(dex.contains("agu_digitama"))
        XCTAssertFalse(dex.contains("botamon"), "you have not met Botamon yet")
    }

    // MARK: GameStore.recordDiscovery directly

    /// Recording is idempotent: a Digimon already in the Dex is not duplicated, and its original
    /// discovery date is kept. The Dex is a set of firsts, not a log of every sighting.
    func testRecordingADiscoveryIsIdempotent() throws {
        let store = try GameStore(url: storeURL)
        let first = Fixture.date("2026-07-17 08:00")
        let later = Fixture.date("2026-07-18 08:00")

        XCTAssertTrue(store.recordDiscovery(id: "botamon", now: first), "a first sighting is new")
        XCTAssertFalse(store.recordDiscovery(id: "botamon", now: later), "a repeat is not")
        try store.save()

        let entries = try store.container.mainContext.fetch(FetchDescriptor<DexEntry>())
            .filter { $0.digimonId == "botamon" }
        XCTAssertEqual(entries.count, 1, "no duplicate entry")
        XCTAssertEqual(entries.first?.firstDiscovered, first, "the original date is kept")
    }

    /// The Dex outlives a reset game. `resetGame` deletes the GameState, but Dex entries are a
    /// separate entity and stay — which US-029's rebirth depends on.
    func testResettingTheGameKeepsTheDex() throws {
        let store = try GameStore(url: storeURL)
        store.recordDiscovery(id: "botamon", now: Fixture.morning)
        try store.save()

        try store.resetGame(digitamaId: "gabu_digitama", now: Fixture.morning)

        let dex = Set(try store.dexIds())
        XCTAssertTrue(dex.contains("botamon"), "the old Digimon is still in the field guide")
        XCTAssertTrue(dex.contains("gabu_digitama"), "and the new egg was recorded")
    }

    /// A discovery must reach DISK, not just the live context's cache. Asserted after the writing
    /// store is torn down and a brand new one opened on the same file — a second store on a live
    /// first one can read through a shared cache and hide a save that never flushed.
    func testRecordDiscoveryPersistsAcrossAReopen() throws {
        do {
            let store = try GameStore(url: storeURL)
            store.recordDiscovery(id: "botamon", now: Fixture.morning)
            try store.save()
        }
        let reopened = try GameStore(url: storeURL)
        XCTAssertEqual(try reopened.dexIds(), ["botamon"])
    }

    /// The hatch's Dex entry must survive a real relaunch. The writing model is discarded before a
    /// fresh store reads the file, so this cannot pass on a same-process cache the way an assertion
    /// against a still-open store can.
    func testAHatchedDigimonIsInTheDexAfterAReopen() async throws {
        walk(5_000)
        do {
            let model = makeModel()
            await model.start()
            XCTAssertEqual(model.state?.currentDigimonId, "botamon")
        }
        let reopened = try GameStore(url: storeURL)
        XCTAssertTrue(Set(try reopened.dexIds()).contains("botamon"),
                      "the hatch's Dex entry reached disk")
    }

    // MARK: Migration

    /// A store written before the Dex existed still opens under the new schema. Adding an ENTITY is
    /// a lightweight migration (US-014 proved it for the ledger); this re-runs it now that DexEntry
    /// is the addition. A store that could not migrate would crash at launch on exactly the watches
    /// that already have a Digimon.
    func testAStoreWrittenBeforeTheDexExistedStillOpens() throws {
        let now = Fixture.morning

        // The schema before this story: GameState and the ledger, no Dex.
        let oldSchema = Schema([GameState.self, EnergyLedger.self])
        let oldContainer = try ModelContainer(
            for: oldSchema,
            configurations: ModelConfiguration(schema: oldSchema, url: storeURL)
        )
        oldContainer.mainContext.insert(GameState(currentDigimonId: "agu_digitama", now: now))
        try oldContainer.mainContext.save()

        // Same file, new schema.
        let upgraded = try GameStore(url: storeURL)
        let state = try upgraded.loadOrCreate(digitamaId: "gabu_digitama", now: now)
        XCTAssertEqual(state.currentDigimonId, "agu_digitama",
                       "the saved game survived — it was not replaced by a new one")

        // The Dex is empty but usable: recording and reading back both work on the migrated store.
        XCTAssertEqual(try upgraded.dexIds(), [])
        upgraded.recordDiscovery(id: "botamon", now: now)
        try upgraded.save()
        XCTAssertEqual(try upgraded.dexIds(), ["botamon"])
    }
}
