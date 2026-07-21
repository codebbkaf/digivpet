import XCTest
import Foundation
import UIKit

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

// MARK: - The short names

final class EnergyShortNameTests: XCTestCase {
    /// THE AC, literally: the SOURCE of the energy in short English, these four and no others.
    /// Asserted as hand-written literals rather than by round-tripping some mapping through itself.
    func testTheFourShortNamesAreTheOnesTheACNames() {
        XCTAssertEqual(EnergyType.strength.shortName, "STEP")
        XCTAssertEqual(EnergyType.vitality.shortName, "KCAL")
        XCTAssertEqual(EnergyType.spirit.shortName, "SLEEP")
        XCTAssertEqual(EnergyType.stamina.shortName, "EXER")
    }

    /// A copy-paste that gave two types one name would leave two bars that cannot be told apart —
    /// and every assertion above would still pass if only one of the pair were wrong.
    func testEveryShortNameIsDistinct() {
        let names = EnergyType.allCases.map(\.shortName)
        XCTAssertEqual(Set(names).count, EnergyType.allCases.count)
    }

    /// An empty name would draw a bar with no label at all rather than failing anywhere.
    func testEveryTypeHasAShortName() {
        for type in EnergyType.allCases {
            XCTAssertFalse(type.shortName.isEmpty, "\(type)")
        }
    }

    /// The short name is what the bar shows; `displayName` is what VoiceOver reads. Both must
    /// exist, and they are not interchangeable — VoiceOver must not say "STEP".
    func testTheShortNameIsNotTheDisplayName() {
        for type in EnergyType.allCases {
            XCTAssertNotEqual(type.shortName, type.displayName, "\(type)")
        }
    }

    /// The names are display-only, like `displayName`. `rawValue` is the persisted spelling and
    /// changing the label must not have touched it — a saved game decodes by raw value.
    func testTheShortNameIsNotThePersistedSpelling() {
        XCTAssertEqual(EnergyType.strength.rawValue, "strength")
        XCTAssertEqual(EnergyType.vitality.rawValue, "vitality")
        XCTAssertEqual(EnergyType.spirit.rawValue, "spirit")
        XCTAssertEqual(EnergyType.stamina.rawValue, "stamina")
    }

    /// The old glyphs are gone from the shipping code, not merely unused by it — a leftover mapping
    /// somewhere else would put one back on screen.
    func testNoShortNameIsAGlyph() {
        for type in EnergyType.allCases {
            XCTAssertTrue(type.shortName.allSatisfy { $0.isASCII }, "\(type): \(type.shortName)")
        }
    }
}

// MARK: - The row fits

final class EnergyBarLayoutTests: XCTestCase {
    /// THE AC: the name column fits "SLEEP" at the size it is drawn, so the longest of the four
    /// labels does not truncate. Measured against the real watchOS system font rather than a
    /// guess at how wide five capitals are.
    func testTheNameColumnFitsTheLongestShortName() {
        let font = UIFont.systemFont(ofSize: EnergyBarLayout.nameFontSize)
        for type in EnergyType.allCases {
            let width = (type.shortName as NSString)
                .size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, EnergyBarLayout.nameWidth,
                                     "\(type.shortName) needs \(width)pt")
        }
    }

    /// Two bars share a row, so the widths have to clear the narrowest screen with the bars still
    /// at their floor. Fail this and a 41mm screen either truncates a value or draws a hairline.
    func testTwoBarsFitTheNarrowestScreen() {
        XCTAssertLessThanOrEqual(EnergyBarLayout.rowWidth,
                                 EnergyBarLayout.narrowestScreenWidth)
    }

    /// The bar is the point of the row. The floor is what stops a wider name column from being
    /// paid for out of it.
    func testTheBarHasAFloorAndTheValueColumnIsUnchanged() {
        XCTAssertGreaterThanOrEqual(EnergyBarLayout.barMinWidth, 18)
        XCTAssertEqual(EnergyBarLayout.valueWidth, 28)
        XCTAssertEqual(EnergyBarLayout.barHeight, 4)
    }
}

// MARK: - What each bar aims at

final class EnergyGoalTests: XCTestCase {
    /// THE AC: a bar's threshold is the `minEnergy` of the edge gated on that type. Agumon's shape:
    /// two branches, on two different types.
    func testEachTypeAimsAtTheThresholdOfTheEdgeGatedOnIt() {
        let progress = node([
            edge(to: "greymon", .strength, min: 60),
            edge(to: "meramon", .stamina, min: 90),
            edge(to: "numemon", .strength, min: 0, isDefault: true)
        ]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goal(.strength).target, 60)
        XCTAssertEqual(progress.goal(.stamina).target, 90)
    }

    /// The junk fallback US-061 hung off every branching Child and Adult is not a goal. It sits at
    /// `minEnergy: 0` on a type an earned branch already claims, so counting it would win the
    /// lowest-wins rule below and draw a bar that is full the moment the Digimon exists.
    func testAJunkFallbackIsNotSomethingABarAimsAt() {
        let progress = node([
            edge(to: "greymon", .strength, min: 60),
            edge(to: "numemon", .strength, min: 0, isDefault: true)
        ]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goal(.strength).target, 60, "the bar aims past the fallback")
        XCTAssertEqual(progress.fraction(.strength), 0, "a fresh Digimon's bar is empty, not full")
    }

    /// But where the fallback is the ONLY way forward — a Digitama's hatch, or the single edge out
    /// of most Baby and Perfect nodes — it IS what the bars are working toward. Dropping it there
    /// would leave a non-terminal Digimon with four dead bars.
    func testTheFallbackIsAimedAtWhenItIsTheOnlyWayForward() {
        let progress = node([
            edge(to: "koromon", .strength, min: 20, isDefault: true)
        ]).energyProgress(for: .zero)

        XCTAssertEqual(progress.goal(.strength).target, 20)
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
            edge(to: "near", .strength, min: 40),
            edge(to: "middle", .strength, min: 90),
            edge(to: "junk", .stamina, min: 0, isDefault: true)
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
