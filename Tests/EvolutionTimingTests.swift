import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// US-020 — evolution time gating and default fallback.
///
/// Two layers, like US-019's suite: `EvolutionTimingTests` pins the pure decision
/// (`scheduledEvolutionTarget` and the `EvolutionTiming` thresholds) against hand-built nodes with
/// a mock clock, and `EvolutionTimingApplyTests` drives the real `refresh()` path so the gate is
/// exercised through the model that actually reads `GameState.stageEnteredDate`.

private enum Clock {
    /// A fixed reference instant; every test measures its gate offsets from here, so no test waits
    /// real time — the "clock" is just `enteredAt` and `now` chosen this many seconds apart.
    static let entered = Date(timeIntervalSinceReferenceDate: 800_000)
    static let hour: TimeInterval = 60 * 60

    static func after(_ hours: Double) -> Date { entered.addingTimeInterval(hours * hour) }

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

    static func node(_ stage: Stage, _ edges: [EvolutionEdge]) -> EvolutionNode {
        EvolutionNode(id: "hero", displayName: "Hero", stage: stage, spriteFile: "Agumon",
                      evolutions: edges)
    }
}

// MARK: - The time-gated decision (pure)

final class EvolutionTimingTests: XCTestCase {
    /// AC6, at the level the acceptance criterion names it: a Baby I with the energy to evolve does
    /// NOT at 23h and DOES at 25h. Same node, same energy — only the clock moves.
    func testABabyIDoesNotEvolveAt23hAndDoesAt25h() {
        let babyI = Clock.node(.babyI, [Clock.edge(to: "koromon", energy: .strength, minEnergy: 20)])
        let energy = EnergyTotals(strength: 30) // well past the 20 threshold

        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: babyI, stageEnergy: energy, dominant: .strength, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(23)),
            "23h is inside the 24h Baby I gate — no evolution yet, even with the energy")

        XCTAssertEqual(EvolutionEngine.scheduledEvolutionTarget(
            for: babyI, stageEnergy: energy, dominant: .strength, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(25)), "koromon",
            "25h is past the gate, so the qualifying edge is taken")
    }

    /// The gate opens exactly on the threshold: at 24h on the nose a Baby I evolves. Pins `>=`, not
    /// a strictly-greater comparison that would hold it one tick longer.
    func testTheBabyGateOpensExactlyAt24h() {
        let babyI = Clock.node(.babyI, [Clock.edge(to: "koromon", energy: .strength, minEnergy: 20)])
        let energy = EnergyTotals(strength: 30)

        XCTAssertEqual(EvolutionEngine.scheduledEvolutionTarget(
            for: babyI, stageEnergy: energy, dominant: .strength, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(24)), "koromon",
            "24h exactly clears the gate")
    }

    /// AC1: Child and above wait 72h, not 24h. A Child holding the energy is still gated at 25h
    /// (which would already have freed a Baby I) and only evolves once 72h have passed.
    func testAChildWaits72hNot24h() {
        let child = Clock.node(.child, [Clock.edge(to: "greymon", energy: .strength, minEnergy: 60)])
        let energy = EnergyTotals(strength: 80)

        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: energy, dominant: .strength, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(25)),
            "25h clears a Baby I but not a Child")
        XCTAssertEqual(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: energy, dominant: .strength, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(72)), "greymon",
            "72h clears the Child gate")
    }

    /// AC2, isolated: no evolution before the gate even when the energy threshold is met. With the
    /// gate closed the answer is nil no matter how much energy is banked.
    func testNoEvolutionBeforeTheGateEvenWithEnoughEnergy() {
        let child = Clock.node(.child, [Clock.edge(to: "greymon", energy: .strength, minEnergy: 60)])
        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: EnergyTotals(strength: 9_999), dominant: .strength,
            careMistakes: 0, battleWins: 0, stageEnteredAt: Clock.entered, now: Clock.after(71)),
            "one hour short of the 72h gate, unlimited energy still does not evolve")
    }

    /// AC3: once the gate is open and nothing qualifies, the `isDefault` edge is taken. Here the
    /// energy is far below the threshold, so no edge qualifies — but past the gate the Digimon must
    /// still not be stuck, so it takes the fallback.
    func testTheDefaultEdgeFiresWhenNothingQualifiesAfterTheGate() {
        let child = Clock.node(.child, [
            Clock.edge(to: "greymon", energy: .strength, minEnergy: 60, isDefault: true),
            Clock.edge(to: "meramon", energy: .stamina, minEnergy: 60)
        ])

        XCTAssertEqual(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: EnergyTotals(strength: 5), dominant: .strength,
            careMistakes: 0, battleWins: 0, stageEnteredAt: Clock.entered, now: Clock.after(72)),
            "greymon", "nothing qualifies, so the default edge fires past the gate")
    }

    /// The default fallback does NOT jump the gate: before the time gate the Digimon stays put even
    /// though its default edge would fire the moment the gate opens.
    func testTheDefaultEdgeDoesNotFireBeforeTheGate() {
        let child = Clock.node(.child, [
            Clock.edge(to: "greymon", energy: .strength, minEnergy: 60, isDefault: true)
        ])
        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: .zero, dominant: nil, careMistakes: 0, battleWins: 0,
            stageEnteredAt: Clock.entered, now: Clock.after(71)),
            "the fallback waits for the gate like everything else")
    }

    /// A qualifying non-default branch beats the default: past the gate with the stamina energy for
    /// the Meramon branch, the Digimon takes Meramon, not the default Greymon.
    func testAQualifyingBranchBeatsTheDefaultAfterTheGate() {
        let child = Clock.node(.child, [
            Clock.edge(to: "greymon", energy: .strength, minEnergy: 60, isDefault: true),
            Clock.edge(to: "meramon", energy: .stamina, minEnergy: 60)
        ])
        XCTAssertEqual(EvolutionEngine.scheduledEvolutionTarget(
            for: child, stageEnergy: EnergyTotals(stamina: 80), dominant: .stamina,
            careMistakes: 0, battleWins: 0, stageEnteredAt: Clock.entered, now: Clock.after(72)),
            "meramon", "the earned branch wins over the fallback")
    }

    /// A terminal node with no edges never evolves even long past any gate, and does not crash on
    /// the empty `isDefault` lookup.
    func testATerminalNodeNeverEvolvesEvenLongAfterTheGate() {
        let terminal = EvolutionNode(id: "wargreymon", displayName: "WarGreymon",
                                     stage: .ultimate, spriteFile: "WarGreymon")
        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: terminal, stageEnergy: EnergyTotals(strength: 9_999), dominant: .strength,
            careMistakes: 0, battleWins: 0, stageEnteredAt: Clock.entered, now: Clock.after(1_000)))
    }

    /// A Digitama is never evolved by this path however long it sits: it hatches through
    /// `EggHatcher` instead, and firing the evolution gate on it would take the egg's `isDefault`
    /// hatch edge on the clock, hatching a starved egg. `minimumStageDuration` is nil for it.
    func testADigitamaNeverEvolvesOnTheClock() {
        let egg = EvolutionNode(
            id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
            evolutions: [Clock.edge(to: "botamon", energy: nil, minEnergy: 50, isDefault: true)]
        )
        XCTAssertNil(EvolutionEngine.scheduledEvolutionTarget(
            for: egg, stageEnergy: EnergyTotals(strength: 999), dominant: .strength,
            careMistakes: 0, battleWins: 0, stageEnteredAt: Clock.entered, now: Clock.after(1_000)),
            "an egg past any amount of time still does not evolve — it hatches")
        XCTAssertNil(EvolutionTiming.minimumStageDuration(for: .digitama),
                     "the Digitama stage has no evolution gate at all")
    }

    /// AC4/AC1: the thresholds are the ones the story names, and they live in one place. Reading
    /// them here pins the constants file rather than re-deriving 24h/72h in the tests above.
    func testTheGateThresholdsAreTheOnesTheStoryNames() {
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .babyI), 24 * 60 * 60)
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .babyII), 24 * 60 * 60)
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .child), 72 * 60 * 60)
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .adult), 72 * 60 * 60)
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .perfect), 72 * 60 * 60)
        XCTAssertEqual(EvolutionTiming.minimumStageDuration(for: .ultimate), 72 * 60 * 60)
    }
}

// MARK: - The gate applied through the model

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class EvolutionTimingApplyTests: XCTestCase {
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

    /// A graph with a starting egg, a Baby I "hero" holding a single qualifying strength edge, and
    /// the node it evolves into. The engine is driven by the saved game's energy/clock, so the
    /// target's own edges are irrelevant here.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon",
                          evolutions: [
                              Clock.edge(to: "koromon", energy: .strength, minEnergy: 20,
                                         isDefault: true)
                          ]),
            EvolutionNode(id: "koromon", displayName: "Koromon", stage: .babyII, spriteFile: "Koromon")
        ])
    }

    /// Builds a model over a saved game at Baby I "hero" that entered its stage `hoursInStage`
    /// before `now`, with strength energy already past the edge's threshold. Whether it evolves is
    /// then entirely the clock's doing.
    private func makeModel(storeName: String, hoursInStage: Double)
        throws -> (store: GameStore, model: MainScreenModel)
    {
        let now = Clock.after(1_000) // any fixed "current" instant
        let entered = now.addingTimeInterval(-hoursInStage * Clock.hour)

        let store = try GameStore(url: storeURL(storeName))
        let state = try store.loadOrCreate(digitamaId: "hero", now: entered)
        state.stage = .babyI
        state.stageEnergy = EnergyTotals(strength: 30) // past hero's 20 threshold
        state.stageEnteredDate = entered
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(), calendar: .current),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(), calendar: .current)
            ),
            calendar: .current,
            now: { now },
            chooseStartingDigitama: { $0.first }
        )
        return (store, model)
    }

    /// AC2 through the real refresh: a Baby I only 23h into its stage does not evolve, even though
    /// its energy qualifies — the model reads `stageEnteredDate` and the gate holds it.
    func testABabyIStaysPutBeforeTheGateThroughRefresh() async throws {
        let (_, model) = try makeModel(storeName: "Before", hoursInStage: 23)
        await model.start()
        XCTAssertEqual(model.state?.currentDigimonId, "hero", "23h < 24h gate, so no evolution")
        XCTAssertEqual(model.state?.stage, .babyI)
    }

    /// AC6 through the real refresh: the same Baby I 25h in evolves. The change from the test above
    /// is only the elapsed time, which is what proves the gate — not the energy — decided it.
    func testABabyIEvolvesAfterTheGateThroughRefresh() async throws {
        let (store, model) = try makeModel(storeName: "After", hoursInStage: 25)
        await model.start()
        XCTAssertEqual(model.state?.currentDigimonId, "koromon", "25h > 24h gate, so it evolves")
        XCTAssertEqual(model.state?.stage, .babyII)
        XCTAssertTrue(Set(try store.dexIds()).contains("koromon"), "and the new form is in the Dex")
    }
}
