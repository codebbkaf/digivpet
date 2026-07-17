import XCTest
import Foundation

@testable import DigiVPet

private func edge(
    to: String = "next",
    _ energy: EnergyType?,
    min: Int,
    isDefault: Bool = false
) -> EvolutionEdge {
    EvolutionEdge(to: to, requiredEnergy: energy, minEnergy: min, maxCareMistakes: 3,
                  isDefault: isDefault)
}

private func node(stage: Stage = .child, _ edges: [EvolutionEdge]) -> EvolutionNode {
    EvolutionNode(id: "test", displayName: "Test", stage: stage, spriteFile: "Agumon",
                  evolutions: edges)
}

private func energy(strength: Int = 0, vitality: Int = 0, spirit: Int = 0, stamina: Int = 0)
-> EnergyTotals {
    EnergyTotals(strength: strength, vitality: vitality, spirit: spirit, stamina: stamina)
}

private extension EnergyProgress {
    func goal(_ type: EnergyType) -> EnergyGoal {
        goals.first { $0.type == type }!
    }

    func fraction(_ type: EnergyType) -> Double {
        fraction(of: goal(type))
    }
}

// MARK: - The symbols

final class EnergySymbolTests: XCTestCase {
    /// THE AC, literally: these four glyphs and no others. Asserted as hand-written literals rather
    /// than by round-tripping some mapping through itself.
    func testTheFourSymbolsAreTheOnesTheACNames() {
        XCTAssertEqual(EnergyType.strength.symbol, "力")
        XCTAssertEqual(EnergyType.vitality.symbol, "活")
        XCTAssertEqual(EnergyType.spirit.symbol, "心")
        XCTAssertEqual(EnergyType.stamina.symbol, "耐")
    }

    /// A copy-paste that gave two types one glyph would leave two bars that cannot be told apart —
    /// and every assertion above would still pass if only one of the pair were wrong.
    func testEverySymbolIsDistinct() {
        let symbols = EnergyType.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, EnergyType.allCases.count)
    }

    /// An empty glyph would draw a bar with no label at all rather than failing anywhere.
    func testEveryTypeHasASymbol() {
        for type in EnergyType.allCases {
            XCTAssertFalse(type.symbol.isEmpty, "\(type)")
        }
    }

    /// The symbol is what the bar shows; `displayName` is what VoiceOver reads. Both must exist,
    /// and they are not interchangeable.
    func testTheSymbolIsNotTheDisplayName() {
        for type in EnergyType.allCases {
            XCTAssertNotEqual(type.symbol, type.displayName, "\(type)")
        }
    }
}

// MARK: - What each bar aims at

final class EnergyGoalTests: XCTestCase {
    /// THE AC: a bar's threshold is the `minEnergy` of the edge gated on that type. Agumon's shape:
    /// two branches, on two different types.
    func testEachTypeAimsAtTheThresholdOfTheEdgeGatedOnIt() {
        let progress = node([
            edge(to: "greymon", .strength, min: 60, isDefault: true),
            edge(to: "meramon", .stamina, min: 90)
        ]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goal(.strength).target, 60)
        XCTAssertEqual(progress.goal(.stamina).target, 90)
    }

    /// A type no edge names has NO target, and that is a real answer: nothing out of Agumon is
    /// gated on Vitality. Inventing a threshold would draw a goal the graph does not contain.
    func testATypeNoEdgeNamesHasNoTarget() {
        let progress = node([
            edge(to: "greymon", .strength, min: 60, isDefault: true),
            edge(to: "meramon", .stamina, min: 90)
        ]).energyProgress(for: .zero)

        XCTAssertNil(progress.goal(.vitality).target)
        XCTAssertNil(progress.goal(.spirit).target)
    }

    /// Several edges may name one type at different thresholds. The bar is working toward whichever
    /// unlocks FIRST — the furthest one is not what it is about to reach.
    func testTheNearestThresholdWinsWhenSeveralEdgesShareAType() {
        let progress = node([
            edge(to: "far", .strength, min: 200),
            edge(to: "near", .strength, min: 40, isDefault: true),
            edge(to: "middle", .strength, min: 90)
        ]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goal(.strength).target, 40)
    }

    /// A terminal node has nowhere to go, so no bar has anything to fill toward. The energy still
    /// accrues, so the amounts are still shown.
    func testATerminalNodeHasNoTargetsAtAll() {
        let progress = node(stage: .ultimate, []).energyProgress(for: energy(strength: 40))

        XCTAssertNil(progress.totalGate)
        for goal in progress.goals {
            XCTAssertNil(goal.target, "\(goal.type)")
        }
        XCTAssertEqual(progress.goal(.strength).earned, 40, "the amount is still real")
    }

    /// An egg's hatch edge leaves `requiredEnergy` nil because US-018 hatches on the TOTAL, so no
    /// single type gates it. The gate belongs to the total row, and no bar may claim it as its own.
    func testAnEggAimsAtItsHatchTotalRatherThanAtAnyOneType() {
        let progress = node(stage: .digitama, [edge(to: "botamon", nil, min: 50, isDefault: true)])
            .energyProgress(for: energy(strength: 20, spirit: 5))

        XCTAssertEqual(progress.totalGate, 50)
        XCTAssertEqual(progress.totalEarned, 25)
        for goal in progress.goals {
            XCTAssertNil(goal.target, "no ONE type hatches an egg: \(goal.type)")
        }
    }

    /// One goal per type, in a fixed order, so the four rows never reshuffle between redraws.
    func testThereIsExactlyOneGoalPerTypeInAllCasesOrder() {
        let progress = node([edge(.strength, min: 60, isDefault: true)]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goals.map(\.type), EnergyType.allCases)
    }

    /// Each bar shows its OWN type's energy. A crossed subscript would still produce four plausible
    /// bars, so every type is given a distinct amount — no two can agree by coincidence.
    func testEachGoalCarriesItsOwnTypesEnergy() {
        let progress = node([edge(.strength, min: 60, isDefault: true)])
            .energyProgress(for: energy(strength: 1, vitality: 2, spirit: 3, stamina: 4))

        XCTAssertEqual(progress.goal(.strength).earned, 1)
        XCTAssertEqual(progress.goal(.vitality).earned, 2)
        XCTAssertEqual(progress.goal(.spirit).earned, 3)
        XCTAssertEqual(progress.goal(.stamina).earned, 4)
    }
}

// MARK: - How full a bar is

final class EnergyFractionTests: XCTestCase {
    func testABarFillsInProportionToItsTarget() {
        let progress = node([edge(.strength, min: 60, isDefault: true)])
            .energyProgress(for: energy(strength: 30))

        XCTAssertEqual(progress.fraction(.strength), 0.5, accuracy: 0.001)
    }

    /// Energy keeps accruing past a threshold while US-020's time gate holds the evolution back, so
    /// "past the target" is an ordinary state — not an overfull bar drawn outside its track.
    func testABarPastItsTargetIsFullAndNoFuller() {
        let progress = node([edge(.strength, min: 60, isDefault: true)])
            .energyProgress(for: energy(strength: 500))

        XCTAssertEqual(progress.fraction(.strength), 1)
    }

    /// An egg's bars fill toward their SHARE of the hatch total, which is what makes them add up:
    /// 25 + 25 is a ready egg, and two half-full bars is what that honestly looks like.
    func testAnEggsBarsFillTowardTheirShareOfTheHatchTotal() {
        let progress = node(stage: .digitama, [edge(to: "botamon", nil, min: 50, isDefault: true)])
            .energyProgress(for: energy(strength: 25, spirit: 25))

        XCTAssertEqual(progress.fraction(.strength), 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.fraction(.spirit), 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.fraction(.vitality), 0, "earned nothing, contributed nothing")
        XCTAssertEqual(progress.totalEarned, progress.totalGate,
                       "and the total row is what says the egg is actually there")
    }

    /// A type with no gate of its own and no shared one has nothing to be a fraction OF. An empty
    /// track, rather than a bar filled against an imagined threshold.
    func testATypeWithNoGateAtAllShowsNoFill() {
        let progress = node([edge(.strength, min: 60, isDefault: true)])
            .energyProgress(for: energy(strength: 30, vitality: 999))

        XCTAssertEqual(progress.fraction(.vitality), 0)
    }

    /// A threshold of zero is legal data meaning "no energy needed", and dividing by it is not.
    /// It is already met, so the bar is full.
    func testAThresholdOfZeroIsAlreadyMetRatherThanDividedBy() {
        let progress = node([edge(.strength, min: 0, isDefault: true)])
            .energyProgress(for: .zero)

        let fraction = progress.fraction(.strength)
        XCTAssertEqual(fraction, 1)
        XCTAssertTrue(fraction.isFinite, "not a NaN drawn as a zero-width bar")
    }

    /// Nothing earned is an empty bar, not a full one — the boundary the test above sits next to.
    func testAnUntouchedTypeWithARealTargetIsEmpty() {
        let progress = node([edge(.strength, min: 60, isDefault: true)])
            .energyProgress(for: .zero)

        XCTAssertEqual(progress.fraction(.strength), 0)
    }
}

// MARK: - Against the shipped roster

final class SeedEnergyBarsTests: XCTestCase {
    /// The bars against the REAL graph, not a fixture: the seed's one branching node aims two bars
    /// at two different types, and leaves the other two with nothing to reach for.
    func testTheShippedAgumonAimsItsBarsAtItsTwoRealBranches() throws {
        let agumon = try XCTUnwrap(EvolutionGraph.bundled.node(id: "agumon"))
        let progress = agumon.energyProgress(for: energy(strength: 30))

        XCTAssertEqual(progress.goal(.strength).target, 60, "-> Greymon")
        XCTAssertEqual(progress.goal(.stamina).target, 60, "-> Meramon")
        XCTAssertNil(progress.goal(.vitality).target)
        XCTAssertNil(progress.goal(.spirit).target)
        XCTAssertNil(progress.totalGate, "a Child hatches from nothing")
        XCTAssertEqual(progress.fraction(.strength), 0.5, accuracy: 0.001)
    }

    /// The screen a first launch actually opens on.
    func testTheShippedStartingEggShowsItsHatchTotal() throws {
        let egg = try XCTUnwrap(EvolutionGraph.bundled.node(id: "agu_digitama"))
        let progress = egg.energyProgress(for: .zero)

        XCTAssertEqual(progress.totalGate, 50)
        XCTAssertEqual(progress.totalEarned, 0)
    }

    /// Every playable node must give the bars something coherent to draw. A node with neither a
    /// per-type target nor a total gate is legal only if it is genuinely terminal — anywhere else
    /// it means four dead bars on a live screen.
    func testEverySeedNodeEitherIsTerminalOrGivesTheBarsAGate() {
        for node in EvolutionGraph.bundled.nodes where !node.dexOnly {
            let progress = node.energyProgress(for: .zero)
            let hasGate = progress.totalGate != nil || progress.goals.contains { $0.target != nil }
            XCTAssertEqual(hasGate, !node.evolutions.isEmpty,
                           "\(node.id) has \(node.evolutions.count) edges but hasGate=\(hasGate)")
        }
    }
}

// MARK: - The bars on the main screen

@MainActor
final class MainScreenEnergyBarsTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("Bars.store") }
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

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

    /// No health fetchers: this suite is about what the bars aim at, and energy is written into the
    /// saved game directly so a test never depends on a reading.
    private func makeModel() -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptyFetcher()),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher())
            ),
            now: { [now] in now }
        )
    }

    private func save(id: String, stage: Stage = .digitama, energy: EnergyTotals = .zero,
                      lifetime: EnergyTotals = .zero) throws {
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: now)
        state.currentDigimonId = id
        state.stage = stage
        state.stageEnergy = energy
        state.lifetimeEnergy = lifetime
        try store.save()
    }

    /// The bars are aimed by the CURRENT NODE's edges. The saved stage is left stale at `.digitama`
    /// on purpose — the same shape US-016 pinned for the sprite: a model reading the saved copy
    /// would show this Adult the egg's 50-point hatch row instead of Greymon's 100.
    func testTheBarsComeFromTheCurrentNodeAndNotTheSavedStage() async throws {
        try save(id: "greymon", stage: .digitama, energy: energy(strength: 25))
        let model = makeModel()
        await model.start()

        let progress = try XCTUnwrap(model.energyProgress)
        XCTAssertEqual(progress.goal(.strength).target, 100, "Greymon -> MetalGreymon")
        XCTAssertNil(progress.totalGate, "an Adult has no hatch row, whatever the save says")
        XCTAssertEqual(progress.fraction(.strength), 0.25, accuracy: 0.001)
    }

    /// The control for the test above: a DIFFERENT Digimon re-aims the bars. Without this, the
    /// thresholds asserted there could be coming from anywhere.
    func testTheBarsReAimThemselvesAtWhicheverDigimonIsBeingRaised() async throws {
        try save(id: "agumon", stage: .child, energy: energy(strength: 25))
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.energyProgress?.goal(.strength).target, 60, "Agumon -> Greymon")
    }

    /// A first launch opens on the egg, and its bars show the hatch it is working toward.
    func testAFreshGameShowsTheEggsHatchTotalAndHighlightsNothing() async throws {
        let model = makeModel()
        await model.start()

        let progress = try XCTUnwrap(model.energyProgress)
        XCTAssertEqual(progress.totalGate, 50)
        XCTAssertEqual(progress.totalEarned, 0)
        XCTAssertNil(model.state?.dominantEnergyType,
                     "an egg that has done nothing has no leaning, so no bar is crowned")
    }

    /// THE AC's dominant bar: it is the one the screen highlights, and it comes from stageEnergy.
    func testTheHighlightedBarIsTheDominantType() async throws {
        try save(id: "agumon", stage: .child, energy: energy(strength: 10, stamina: 40))
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.state?.dominantEnergyType, .stamina)
    }

    /// The bars are about THIS stage. A childhood of walking must not aim adulthood's bars, so a
    /// model reading `lifetimeEnergy` would draw a Digimon further along than it is.
    func testTheBarsShowStageEnergyRatherThanLifetimeEnergy() async throws {
        try save(id: "agumon", stage: .child,
                 energy: energy(strength: 12),
                 lifetime: energy(strength: 900))
        let model = makeModel()
        await model.start()

        let progress = try XCTUnwrap(model.energyProgress)
        XCTAssertEqual(progress.goal(.strength).earned, 12)
        XCTAssertEqual(progress.fraction(.strength), 0.2, accuracy: 0.001)
    }

    /// A saved id the graph does not know draws no bars, rather than four empty ones under a
    /// missing Digimon.
    func testADigimonTheGraphDoesNotKnowHasNoBars() async throws {
        try save(id: "nosuchmon")
        let model = makeModel()
        await model.start()

        XCTAssertNil(model.energyProgress)
    }

    /// Before the store opens there is no game, so there is nothing to draw and nothing to crash on.
    func testThereAreNoBarsBeforeTheGameIsLoaded() {
        XCTAssertNil(makeModel().energyProgress)
    }
}

private struct EmptyFetcher: HealthSampleFetching {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private struct EmptySleepFetcher: SleepSampleFetching {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
