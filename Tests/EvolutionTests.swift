import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-019 — evolution edge evaluation.
///
/// Two layers: `EvolutionEngineTests` pins the pure branch chooser (which edge, if any, qualifies
/// and wins) against hand-built fixture nodes; `EvolutionApplyTests` drives the real `refresh()`
/// path so the mutation an evolution performs — reset stageEnergy, keep lifetimeEnergy, stamp
/// stageEnteredDate, record the Dex — is exercised end to end and persisted.

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
    static let lastStage = date("2026-07-01 08:00")

    static func edge(
        to: String,
        energy: EnergyType?,
        minEnergy: Int,
        maxCareMistakes: Int = 99,
        minBattleWins: Int? = nil,
        isDefault: Bool = false
    ) -> EvolutionEdge {
        EvolutionEdge(to: to, requiredEnergy: energy, minEnergy: minEnergy,
                      maxCareMistakes: maxCareMistakes, minBattleWins: minBattleWins,
                      isDefault: isDefault)
    }

    /// A Child node with the given outgoing edges — the shape of a branching node the engine picks
    /// among.
    static func hero(_ edges: [EvolutionEdge]) -> EvolutionNode {
        EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon",
                      evolutions: edges)
    }
}

// MARK: - The branch chooser (pure)

final class EvolutionEngineTests: XCTestCase {
    /// A strength edge qualifies only while strength is the dominant type — the same node with a
    /// different dominant produces nothing.
    func testAnEdgeQualifiesOnlyWhenDominantMatchesRequiredEnergy() {
        let node = Fixture.hero([Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40)])

        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 0), "greymon")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(spirit: 50), dominant: .spirit,
            careMistakes: 0, battleWins: 0), "spirit dominant does not take the strength branch")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: .zero, dominant: nil,
            careMistakes: 0, battleWins: 0), "no dominant yet, so nothing qualifies")
    }

    /// AC2: the edge needs `minEnergy` worth of the dominant type — 39 of 40 is not yet enough,
    /// 40 is. The boundary is asserted in both directions so it pins the number, not merely "big".
    func testAnEdgeNeedsMinEnergyInTheDominantType() {
        let node = Fixture.hero([Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40)])

        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 39), dominant: .strength,
            careMistakes: 0, battleWins: 0), "39 is below the threshold")
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 40), dominant: .strength,
            careMistakes: 0, battleWins: 0), "greymon", "40 exactly qualifies")
    }

    /// AC6: an edge is blocked when care mistakes exceed `maxCareMistakes`. At the limit it still
    /// qualifies; one over and it does not.
    func testAnEdgeIsBlockedWhenCareMistakesExceedMaxCareMistakes() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40, maxCareMistakes: 2)
        ])

        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 2, battleWins: 0), "greymon", "at the limit it still qualifies")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 3, battleWins: 0), "one mistake over the limit blocks the edge")
    }

    /// An edge that sets `minBattleWins` is gated on it; below the requirement it is blocked, at it
    /// it qualifies. An edge that sets none ignores battle wins entirely.
    func testAnEdgeWithMinBattleWinsIsBlockedUntilItIsMet() {
        let gated = Fixture.hero([
            Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40, minBattleWins: 3)
        ])
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: gated, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 2), "2 wins is short of the 3 required")
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: gated, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 3), "greymon", "3 wins meets it")

        let ungated = Fixture.hero([Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40)])
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: ungated, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 0), "greymon", "no minBattleWins means wins are irrelevant")
    }

    /// AC3: when several edges qualify, the highest `minEnergy` wins. Two strength edges gate at 40
    /// and 80; with 90 both qualify and the harder one is taken, with 50 only the easy one does.
    func testWhenMultipleEdgesQualifyTheHighestMinEnergyWins() {
        let node = Fixture.hero([
            Fixture.edge(to: "easyform", energy: .strength, minEnergy: 40),
            Fixture.edge(to: "hardform", energy: .strength, minEnergy: 80)
        ])

        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 90), dominant: .strength,
            careMistakes: 0, battleWins: 0), "hardform", "both qualify, the harder-earned branch wins")
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50), dominant: .strength,
            careMistakes: 0, battleWins: 0), "easyform", "only the easy branch qualifies at 50")
    }

    /// AC5, at the level the acceptance criterion names it: a strength-dominant and a spirit-dominant
    /// state, from the SAME node, evolve down different branches.
    func testStrengthAndSpiritDominantFromTheSameNodeProduceDifferentResults() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40),
            Fixture.edge(to: "seadramon", energy: .spirit, minEnergy: 40)
        ])

        let strengthResult = EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 60), dominant: .strength,
            careMistakes: 0, battleWins: 0)
        let spiritResult = EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(spirit: 60), dominant: .spirit,
            careMistakes: 0, battleWins: 0)

        XCTAssertEqual(strengthResult, "greymon")
        XCTAssertEqual(spiritResult, "seadramon")
        XCTAssertNotEqual(strengthResult, spiritResult, "the earned energy shapes the outcome")
    }

    /// The dominant gate is a SEPARATE condition from the per-type threshold: a type that has
    /// cleared its own `minEnergy` is still blocked when it is not the dominant one. Both branches
    /// gate at 40 and both types are above it, so only the DOMINANT type's branch may be taken —
    /// which is what distinguishes "dominant matches requiredEnergy" from "that type reached
    /// minEnergy".
    func testAnEdgeIsBlockedWhenItsTypeIsNotDominantEvenWithEnoughEnergy() {
        let node = Fixture.hero([
            Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40),
            Fixture.edge(to: "seadramon", energy: .spirit, minEnergy: 40)
        ])

        // strength 60, spirit 50: both cleared 40, but strength is dominant, so the strength branch.
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 60, spirit: 50), dominant: .strength,
            careMistakes: 0, battleWins: 0), "greymon")
        // Swap the dominance: strength still holds 50 (>= 40) but spirit now leads, so the spirit
        // branch — the strength edge is blocked despite having the energy for it.
        XCTAssertEqual(EvolutionEngine.evolutionTarget(
            for: node, stageEnergy: EnergyTotals(strength: 50, spirit: 60), dominant: .spirit,
            careMistakes: 0, battleWins: 0), "seadramon")
    }

    /// A Digitama's hatch edge (nil `requiredEnergy`) never qualifies here, whatever the dominant —
    /// hatching is `EggHatcher`'s job, and letting a nil edge match a nil dominant would evolve a
    /// fresh egg the instant it existed.
    func testANilRequiredEnergyEdgeNeverQualifies() {
        let egg = EvolutionNode(
            id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
            evolutions: [EvolutionEdge(to: "botamon", minEnergy: 50, maxCareMistakes: 99)]
        )
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: egg, stageEnergy: EnergyTotals(strength: 999), dominant: .strength,
            careMistakes: 0, battleWins: 0))
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: egg, stageEnergy: .zero, dominant: nil, careMistakes: 0, battleWins: 0))
    }

    /// A terminal node (no outgoing edges) never evolves rather than crashing on an empty list.
    func testATerminalNodeNeverEvolves() {
        let terminal = EvolutionNode(id: "wargreymon", displayName: "WarGreymon",
                                     stage: .ultimate, spriteFile: "WarGreymon")
        XCTAssertNil(EvolutionEngine.evolutionTarget(
            for: terminal, stageEnergy: EnergyTotals(strength: 999), dominant: .strength,
            careMistakes: 0, battleWins: 0))
    }
}

// MARK: - Evolution applied through the model (persisted)

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class EvolutionApplyTests: XCTestCase {
    private var storeDirectory: URL!
    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

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

    /// A graph with a starting egg (so a new game can begin), a branching Child "hero", and its two
    /// Adult branches. The engine is driven by the injected `dominant`/`stageEnergy` on the saved
    /// game, so the branch targets' own edges are irrelevant here.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon",
                          evolutions: [
                              Fixture.edge(to: "greymon", energy: .strength, minEnergy: 40,
                                           maxCareMistakes: 3),
                              Fixture.edge(to: "seadramon", energy: .spirit, minEnergy: 40,
                                           maxCareMistakes: 3)
                          ]),
            EvolutionNode(id: "greymon", displayName: "Greymon", stage: .adult, spriteFile: "Greymon"),
            EvolutionNode(id: "seadramon", displayName: "Seadramon", stage: .adult,
                          spriteFile: "Garurumon")
        ])
    }

    /// Seeds a saved game already at "hero" with the given dominant energy and care history, then
    /// builds a model over the same store so `refresh()` sees exactly that state. Returns the store
    /// and the model; the store is shared with the model, so assertions on it see the applied change.
    private func makeModelAtHero(
        storeName: String = "Evolution",
        dominant: EnergyType,
        stageAmount: Int = 60,
        careMistakes: Int = 0
    ) throws -> (store: GameStore, model: MainScreenModel) {
        let url = storeURL(storeName)
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: Fixture.lastStage)
        // The saved stage is a duplicate of the graph node's stage (US-006); seed it in step with
        // hero's Child stage so a blocked evolution can be asserted to have left it untouched.
        state.stage = .child
        var totals = EnergyTotals()
        totals[dominant] = stageAmount
        state.stageEnergy = totals
        // A distinct lifetime total so "lifetimeEnergy is preserved" cannot pass by coincidence.
        state.lifetimeEnergy = EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444)
        state.careMistakeCount = careMistakes
        // US-027: the audit now charges a mistake per whole day that went by with no health data,
        // and this fixture's readers are empty ones. Without this the days between `lastStage` and
        // `morning` would each be charged, and a `careMistakes: 0` premise would not survive to the
        // moment the edge is evaluated — these tests would be measuring the care gate rather than
        // the branch they are about. Stamped at the refresh instant: health data was seen just now,
        // and the Digimon was fed just now, so neither the silent-day nor the starvation rule has
        // anything to charge for the fortnight this fixture spans.
        state.healthDataLastSeen = Fixture.morning
        state.hungerUpdatedAt = Fixture.morning
        state.stageEnteredDate = Fixture.lastStage
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first }
        )
        return (store, model)
    }

    /// AC1 + AC5, through the real refresh: strength-dominant hero evolves to the strength branch,
    /// spirit-dominant hero to the spirit branch — the same node, different outcomes from the energy
    /// earned. Refresh is the "energy update" the engine evaluates on.
    func testDominantEnergyDecidesTheBranchThroughRefresh() async throws {
        let strength = try makeModelAtHero(storeName: "Strength", dominant: .strength)
        await strength.model.start()
        XCTAssertEqual(strength.model.state?.currentDigimonId, "greymon")
        XCTAssertEqual(strength.model.state?.stage, .adult)

        // An independent store file for the spirit run — same node, different earned energy.
        let spirit = try makeModelAtHero(storeName: "Spirit", dominant: .spirit)
        await spirit.model.start()
        XCTAssertEqual(spirit.model.state?.currentDigimonId, "seadramon")

        XCTAssertNotEqual(strength.model.state?.currentDigimonId,
                          spirit.model.state?.currentDigimonId,
                          "the dominant energy really steered the branch")
    }

    /// AC4: evolution resets stageEnergy to zero, preserves lifetimeEnergy, stamps a new
    /// stageEnteredDate, and records the new form in the Dex.
    func testEvolvingResetsStageEnergyKeepsLifetimeStampsDateAndRecordsTheDex() async throws {
        let (store, model) = try makeModelAtHero(dominant: .strength)
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.currentDigimonId, "greymon")
        XCTAssertEqual(state.stageEnergy, .zero, "the new stage starts fresh")
        XCTAssertEqual(state.lifetimeEnergy,
                       EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444),
                       "the whole life's energy is carried forward untouched")
        XCTAssertEqual(state.stageEnteredDate, Fixture.morning,
                       "the stage clock is restarted for the time gate US-020 will read")
        XCTAssertGreaterThan(Fixture.morning, Fixture.lastStage, "and it genuinely moved forward")

        let dex = Set(try store.dexIds())
        XCTAssertTrue(dex.contains("greymon"), "the new form is in the Dex")
        XCTAssertTrue(dex.contains("hero"), "the form it evolved from is still there")
    }

    /// AC4, persisted: the evolution reaches disk. Asserted through a SECOND store on the same file
    /// so what is read came off disk, not out of the writing context's memory.
    func testTheEvolutionIsPersisted() async throws {
        let (_, model) = try makeModelAtHero(dominant: .strength)
        await model.start()

        let reopened = try GameStore(url: storeURL("Evolution"))
        let saved = try reopened.loadOrCreate(digitamaId: "unused", now: Fixture.morning)
        XCTAssertEqual(saved.currentDigimonId, "greymon", "the evolution reached disk")
        XCTAssertEqual(saved.stage, .adult)
        XCTAssertTrue(Set(try reopened.dexIds()).contains("greymon"), "and so did the Dex entry")
    }

    /// AC6, through the model: too many care mistakes block the qualifying branch, so the Digimon
    /// stays where it is even though its energy would otherwise be enough. The control for the
    /// evolution tests above — without it they could pass on an engine that always evolves.
    func testCareMistakesBlockEvolutionThroughRefresh() async throws {
        let (store, model) = try makeModelAtHero(dominant: .strength, careMistakes: 4)
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "hero", "neglect held the evolution back")
        XCTAssertEqual(model.state?.stage, .child)
        XCTAssertFalse(Set(try store.dexIds()).contains("greymon"), "so Greymon was never met")
    }

    /// A node whose energy has not reached any edge's threshold does not evolve on refresh — the
    /// engine really is a no-op until something qualifies.
    func testAnUnqualifiedNodeStaysPutThroughRefresh() async throws {
        let (_, model) = try makeModelAtHero(dominant: .strength, stageAmount: 39)
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "hero", "39 < 40 minEnergy, so no evolution")
    }
}
