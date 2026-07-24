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
    /// The rule with an egg's age and step count spelled out, defaulting to a freshly laid, unwalked
    /// egg — so an assertion that names only the energy is testing the energy path alone.
    ///
    /// `age` and `steps` are what US-222 added; both are handed in, and nothing here reads a real
    /// clock, so five minutes of egg costs a test nothing.
    private func target(_ node: EvolutionNode, energy: EnergyTotals,
                        age: TimeInterval = 0, steps: Double? = nil) -> String? {
        var metrics = MetricTotals.zero
        // Left ABSENT rather than written as 0 by default: the un-credited case is the real one on
        // a fresh save, and the rule has to read it as zero steps through the subscript.
        if let steps { metrics[.healthSteps] = steps }
        return EggHatcher.hatchTarget(for: node, stageEnergy: energy,
                                      stageEnteredAt: Fixture.morning,
                                      stageMetrics: metrics,
                                      now: Fixture.morning.addingTimeInterval(age))
    }

    /// THE AC: 49 total energy does not hatch and 50 does.
    func testFortyNineDoesNotHatchAndFiftyDoes() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")

        // 49 spread across the four types — hatching is gated on the TOTAL, not any one type.
        XCTAssertNil(target(egg, energy: EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 12)))
        XCTAssertEqual(EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 12).total, 49)

        // 50 exactly — the boundary hatches.
        XCTAssertEqual(target(egg, energy: EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 13)),
                       "botamon")
        XCTAssertEqual(EnergyTotals(strength: 13, vitality: 12, spirit: 12, stamina: 13).total, 50)
    }

    /// The threshold is the hatch edge's `minEnergy`, not a hard-coded 50 — a different egg with a
    /// different edge hatches on its own number.
    func testTheThresholdComesFromTheHatchEdge() {
        let egg = Fixture.egg(threshold: 30)
        XCTAssertNil(target(egg, energy: EnergyTotals(strength: 29)))
        XCTAssertEqual(target(egg, energy: EnergyTotals(strength: 30)), "baby")
    }

    /// Only a Digitama hatches. A Baby I with 50 energy is not an egg, and evolving it is US-019's
    /// job under different rules.
    func testOnlyADigitamaHatches() {
        let baby = EvolutionNode(
            id: "botamon", displayName: "Botamon", stage: .babyI, spriteFile: "Botamon",
            evolutions: [EvolutionEdge(to: "koromon", minEnergy: 50, maxCareMistakes: 4, isDefault: true)]
        )
        XCTAssertNil(target(baby, energy: EnergyTotals(strength: 99)))
        // US-222: and not on either of the new paths either. A Baby I sitting a week in its stage
        // with 100,000 steps behind it must NOT take its `isDefault` edge on the clock — that would
        // turn the hatch shortcut into a free evolution for the whole roster.
        XCTAssertNil(target(baby, energy: .zero, age: 7 * 24 * 60 * 60, steps: 100_000))
    }

    /// A terminal Digitama with no hatch edge cannot hatch, rather than crashing on an empty edge
    /// list — on any of the three paths.
    func testADigitamaWithNoEdgeDoesNotHatch() {
        let egg = EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama")
        XCTAssertNil(target(egg, energy: EnergyTotals(strength: 999)))
        XCTAssertNil(target(egg, energy: .zero, age: EggHatcher.maximumEggDuration, steps: 5_000))
    }

    /// AC3, against the SHIPPED graph: each seed egg hatches into the Baby I its edge names.
    func testEachSeedEggHatchesIntoItsLinkedBabyI() throws {
        let graph = EvolutionGraph.bundled
        for (eggId, babyId) in [("agu_digitama", "botamon"),
                                ("gabu_digitama", "punimon"),
                                ("pal_digitama", "yuramon")] {
            let egg = try XCTUnwrap(graph.node(id: eggId))
            XCTAssertEqual(target(egg, energy: EnergyTotals(strength: 50)), babyId)
            XCTAssertEqual(graph.node(id: babyId)?.stage, .babyI, "\(babyId) is the Baby I form")
        }
    }

    // MARK: US-222's two extra paths

    /// THE AC: an egg with no energy and no steps hatches at five minutes on the nose, and does not
    /// one second earlier. The comparison is `>=`, like the energy one.
    func testAnEggHatchesOnTheClockAtFiveMinutesAndNotBefore() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")
        XCTAssertEqual(EggHatcher.maximumEggDuration, 5 * 60, "five minutes")

        XCTAssertNil(target(egg, energy: .zero, age: EggHatcher.maximumEggDuration - 1),
                     "4m59s is still an egg")
        XCTAssertEqual(target(egg, energy: .zero, age: EggHatcher.maximumEggDuration), "botamon",
                       "the boundary hatches")
        // And an app closed on an egg and reopened much later finds it hatched: the rule is
        // wall-clock against `stageEnteredDate`, not a counter that had to be running.
        XCTAssertEqual(target(egg, energy: .zero, age: 6 * 60), "botamon")
    }

    /// THE AC: an egg with no energy hatches on its 500th step at the very instant it was laid —
    /// the step path does not need the clock, and the clock path does not need the steps.
    func testAnEggHatchesOnFiveHundredStepsWithNoTimePassed() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")
        XCTAssertEqual(EggHatcher.stepsToHatch, 500)

        XCTAssertNil(target(egg, energy: .zero, age: 0, steps: 499), "499 steps is still an egg")
        XCTAssertEqual(target(egg, energy: .zero, age: 0, steps: 500), "botamon",
                       "the 500th step hatches it, with now == stageEnteredDate")
    }

    /// A fresh save has never credited a step metric at all, and that absent total must read as 0
    /// rather than trip the gate — the subscript's flattening is exactly what is wanted here, unlike
    /// US-180's `atMost` conditions where unknown must not satisfy.
    func testAnUncreditedStepTotalIsNotAHatch() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")
        XCTAssertEqual(MetricTotals.zero.known(.healthSteps), nil, "nothing was ever credited")
        XCTAssertNil(target(egg, energy: .zero, age: 0, steps: nil))
    }

    /// The three paths are an OR, not an AND: none of them needs either of the others, and an egg
    /// that meets all three still hatches once.
    func testTheThreePathsAreIndependent() {
        let egg = Fixture.egg(threshold: 50, hatchesInto: "botamon")
        XCTAssertEqual(target(egg, energy: EnergyTotals(strength: 50), age: 0, steps: 0), "botamon",
                       "energy alone")
        XCTAssertEqual(target(egg, energy: .zero, age: 5 * 60, steps: 0), "botamon", "time alone")
        XCTAssertEqual(target(egg, energy: .zero, age: 0, steps: 500), "botamon", "steps alone")
        XCTAssertEqual(target(egg, energy: EnergyTotals(strength: 50), age: 5 * 60, steps: 500),
                       "botamon", "all three at once is still one hatch into the same Baby I")
        XCTAssertNil(target(egg, energy: EnergyTotals(strength: 49), age: 5 * 60 - 1, steps: 499),
                     "just short on every path is no hatch at all")
    }

    /// The hatch shortcut must NOT have leaked into the evolution gate: a Digitama still has no
    /// minimum stage duration, so `EvolutionEngine` cannot take the egg's `isDefault` edge on the
    /// clock behind `EggHatcher`'s back. US-222 adds a hatch path, not an evolution one.
    func testTheDigitamaEvolutionGateStillNeverOpens() {
        XCTAssertNil(EvolutionTiming.minimumStageDuration(for: .digitama))
        XCTAssertFalse(EvolutionTiming.hasClearedTimeGate(
            stage: .digitama, enteredAt: Fixture.morning,
            now: Fixture.morning.addingTimeInterval(EggHatcher.maximumEggDuration * 100)))
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
        let graph = EvolutionGraph.bundled
        let candidates = graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && graph.reachesUltimate(from: $0.id) }
        XCTAssertEqual(Set(candidates.map(\.id)),
                       ["agu_digitama", "gabu_digitama", "pal_digitama", "pata_digitama", "piyo_digitama",
                        "gazi_digitama", "tento_digitama", "goma_digitama", "baku_digitama",
                        "flora_digitama", "funbee_digitama", "heriss_digitama",
                        "agu2006_digitama", "gabublack_digitama", "elec_digitama", "kune_digitama",
                        "hyoko_digitama", "angora_digitama", "cand_digitama", "beta_digitama",
                        "kame_digitama", "kuda_digitama", "kuda2006_digitama", "espi_digitama",
                        "mush_digitama", "pawnchessblack_digitama", "pawnchesswhite_digitama",
                        "phasco_digitama", "picodevi_digitama", "plot_digitama", "swim_digitama",
                        "vorvo_digitama", "lala_digitama", "luce_digitama",
                        // US-157's five, and the first promotion since US-146 that came from the
                        // TOP of a thread rather than the middle: opening the `tamers` Ultimate
                        // rung (Beelzebumon, ChaosDukemon, Dianamon, Hexeblaumon) gave that line
                        // its first Mega, so every `tamers` egg whose thread already ran to a
                        // Perfect now runs all the way and is a legal starting egg.
                        "guil_digitama", "blackguil_digitama", "imp_digitama", "lop_digitama",
                        "bluco_digitama",
                        // US-158's five. Four are `wanyamon`'s whole egg list at once — that line
                        // was the LAST with a Perfect rung and no Mega above it, and opening it
                        // over Gogmamon and Grappleomon promoted every egg on the line in one
                        // edit. The fifth is Monodra, whose DORUmon thread reached only as far as
                        // DORUgamon until this story wired DORUguremon and DORUgoramon over it.
                        "gao_digitama", "bear_digitama", "koe_digitama", "lioll_digitama",
                        "monodra_digitama",
                        // US-159's two, and both are middle-of-the-thread promotions on `tamers`:
                        // Rena Digitama runs to Renamon, whose Kyubimon was a leaf until LadyDevimon
                        // and Beelzebumon went over it, and Terrier Digitama runs to Terriermon,
                        // whose only onward edge is the JUNK fall to Numemon X — which US-159 gave
                        // an earned branch to LadyDevimon X and on to BeelStarmon X. So the Terrier
                        // egg reaches a Mega only by being neglected first, which is a strange
                        // thread and a legal one.
                        "rena_digitama", "terrier_digitama",
                        // US-160's two, and they are `diablomon`'s WHOLE egg list — the same shape
                        // US-158's four `wanyamon` eggs had, one rung lower down the bill: that
                        // line had no Perfect rung AND no Ultimate rung at all until the M sweep
                        // put the two Meicrackmon over Meicoomon and Rasielmon and Raguelmon over
                        // them. Kera and Meicoo Digitama both hatch onto Kuramon, so opening the
                        // top of that one thread promoted both at once.
                        "kera_digitama", "meicoo_digitama",
                        // US-161's five, and they are `vital`'s WHOLE egg list — the third time a
                        // Perfect sweep has promoted a line's eggs by opening the rung rather than
                        // by lengthening a thread, after US-158's `wanyamon` four and US-160's
                        // `diablomon` two. Every `vital` Child falls to Kokeshimon, which now
                        // carries Oboromon and Zanbamon, so all five arrive together.
                        "ludo_digitama", "morpho_digitama", "pulse_digitama",
                        "sunariza_digitama", "zuba_digitama",
                        // US-162's three, and they close the Perfect rung with the same move made
                        // twice: `commandramon` and `adventure02` were the last two lines with no
                        // Perfect rung, and the S-Z sweep opened both. Commandra Digitama runs
                        // through Commandramon into Damemon, which now carries SkullBaluchimon and
                        // Chaosdramon X. V and Worm Digitama are the interesting pair — US-161
                        // deliberately left that line closed because XV-mon carries only one of
                        // them, and US-162 branched Nise Drimogemon instead, the JUNK Champion all
                        // three of the line's Children fall into, so both eggs arrived at once.
                        "commandra_digitama", "v_digitama", "worm_digitama"],
                       "every seeded egg is a candidate — US-044's Pata, US-045's Piyo and US-046's Gazi Digitama joined the three US-008 ones, US-138's Tento, US-139's Goma, US-140's Baku, US-141's Flora, US-142's Funbee and US-143's Heriss Digitama root the six Pendulum trees, US-144's sweep added twelve alternate eggs onto lines that already reach an Ultimate, US-145's added eight more, US-146 promoted Lala and Luce Digitama by finishing the two threads they hatch — Pipimon into Tanemon and Tsubumon into Tokomon, both Baby II that already reached an Ultimate — and US-157 promoted five `tamers` eggs by giving that line an Ultimate rung at last")

        // The rest are deliberately NOT candidates: each hatches into a Baby I that is still the
        // top of its thread, and a new game must not start on one. That filter lives in
        // `MainScreenModel.startingDigitamaId` and is the reason `reachesUltimate` exists. Ten are
        // US-144's; the fifteen US-145 added are the twelve eggs that opened a brand-new Baby I,
        // `zuba_digitama` which doubles up on one of them, and `lioll_digitama`/`meicoo_digitama`,
        // whose species has no usable sheet and which therefore hatch onto a leaf US-144 left.
        //
        // US-146 gives every Baby I a Baby II, which moves the top of each of these threads up one
        // rung rather than closing it — the thread still stops below Ultimate, so all but two stay
        // here. The two that left are `lala_digitama` and `luce_digitama`, whose Baby II
        // (`tanemon`, `tokomon`) already existed and already reached an Ultimate.
        let unraisable = graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && !graph.reachesUltimate(from: $0.id) }
            .map(\.id)
            .sorted()
        //
        // US-157 takes FIVE off this list rather than one — Guil, BlackGuil, Imp, Lop and Bluco —
        // and for a different reason than any story before it: not because their thread grew, but
        // because the thread's far END finally exists. `tamers` had five Perfects and no Ultimate
        // at all until this story opened four, so every egg on that line stopped one rung short.
        // Rena, Terrier, Monodra and V Digitama stay, because their own threads still stop below
        // the Perfect rung.
        //
        // US-158 takes FIVE more, and four of them are one line: `wanyamon` was the last line in
        // the file with Perfects and no Mega, so Gao, Bear, Koe and Lioll Digitama all stopped one
        // rung short exactly as the `tamers` eggs had, and Ancient Volcamon and Dinotigermon
        // promoted all four at once. Monodra is the fifth and is the ordinary middle-of-the-thread
        // kind: DORUgamon was a leaf until DORUguremon and DORUgoramon went over it. Rena, Terrier
        // and V Digitama stay — their threads still stop below the Perfect rung.
        //
        // US-159 takes TWO more, Rena and Terrier, and both are `tamers` again: LadyDevimon over
        // the leaf Kyubimon carries the first, and LadyDevimon X over the junk Numemon X carries
        // the second. **AND THAT IS THE LAST ONE ANY PERFECT SWEEP CAN MOVE**: all eleven eggs left
        // here sit on `commandramon`, `algomon`, `diablomon`, `vital` or `adventure02`, and not one
        // of those five lines has a Perfect rung at all — so promoting any of them means opening a
        // whole rung, not adding a node to one.
        //
        // US-160 takes TWO more, Kera and Meicoo, and it is the case US-159 said could only happen
        // by opening a whole rung: `diablomon` had neither a Perfect nor an Ultimate rung, and the
        // M sweep authored both over Meicoomon. Four lines are left here — `commandramon`,
        // `algomon`, `vital` and `adventure02` — and every one still stops at the Champion rung.
        //
        // US-161 takes FIVE more, and they are `vital`'s WHOLE egg list — Ludo, Morpho, Pulse,
        // Sunariza and Zuba. Same shape as US-160's two: the line had neither a Perfect nor an
        // Ultimate rung, and the N-R sweep authored both, twice over (Oboromon and Zanbamon over
        // Kokeshimon, RaijiLudomon and Bryweludramon over Tia Ludomon). Every `vital` Child falls
        // to Kokeshimon when neglected, so ONE of the two threads promotes all five at once and
        // the other is the earned route. Four eggs are left, on three lines: `commandramon`,
        // `algomon` and `adventure02`. The last of those is the interesting one — US-161 could
        // have opened it with Paildramon over XV-mon, and did not, precisely because Worm Digitama
        // descends through Wormmon to Sorcerymon and would have been left unraisable on a line
        // that HAS a Perfect rung. `adventure02` is a whole-line job, not a one-node one.
        // US-162 takes THREE more and leaves exactly ONE, which is where this list stops for
        // good: Commandra by branching Damemon, and V and Worm together by branching Nise
        // Drimogemon rather than XV-mon. **Ghost Digitama cannot be moved by any story at this
        // rung or above**, because `algomon`'s only Perfect-orphan citation is Siesamon and
        // Siesamon descends from Paomon — a Baby I no Digitama can reach, since US-145 spent all
        // fifty-seven. See
        // `PerfectSweepSToZTests.testAlgomonCouldNotBeOpenedBecauseItsEggCannotReachSiesamon`.
        XCTAssertEqual(unraisable, ["ghost_digitama"])

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
    ///
    /// Walked as 499 steps rather than the 4,900 this test used before US-222 — 4,900 steps now
    /// hatches the egg on the STEP path long before it has 49 energy (see
    /// `testTheStepPathHatchesAWalkedEggBeforeItHasFiftyEnergy`), so the only way to hold an egg
    /// short of every path through the real refresh is to walk under 500. The 49-vs-50 energy seam
    /// itself is pinned in `EggHatcherTests`, where the other two paths can be shut individually.
    func testShortOfEveryHatchPathTheEggStaysAnEgg() async throws {
        walk(499) // 4 energy, and 499 steps — one short of US-222's step path
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "agu_digitama", "still an egg")
        XCTAssertEqual(model.state?.stage, .digitama)
        XCTAssertEqual(model.state?.stageMetricTotals[.healthSteps], 499,
                       "the steps were credited to the egg's stage — they just did not reach 500")
    }

    /// US-222's step path through the real refresh: 4,900 steps is only 49 energy, one short of the
    /// hatch threshold this test's ancestor pinned, and the egg hatches anyway because 4,900 steps
    /// is nine times the 500 the step path asks for.
    func testTheStepPathHatchesAWalkedEggBeforeItHasFiftyEnergy() async throws {
        walk(4_900) // 49 energy — NOT enough on the energy path
        let model = makeModel()
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.stage, .babyI, "hatched on steps, not on energy")
        XCTAssertEqual(state.currentDigimonId, "botamon")
        XCTAssertEqual(state.hatchedDate, Fixture.morning, "US-200's age counter is stamped either way")
        XCTAssertEqual(model.lifetimeEnergy.strength, 49, "and it really was one short on energy")
    }

    /// US-222's whole point, through the real refresh: a save with NO health data at all — the
    /// Simulator, a watch worn for the first time — hatches on the clock alone, five minutes after
    /// the egg appeared. The clock is injected, so this test waits for nothing.
    func testAnEggWithNoHealthDataAtAllHatchesAfterFiveMinutes() async throws {
        // No `walk(_:)` at all: zero steps, zero energy, nothing to earn 50 with.
        var currentNow = Fixture.morning
        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { currentNow },
            chooseStartingDigitama: { $0.first }
        )
        await model.start()
        XCTAssertEqual(model.state?.stage, .digitama, "a new game opens on the egg")

        // 4m59s: still an egg.
        currentNow = Fixture.morning.addingTimeInterval(EggHatcher.maximumEggDuration - 1)
        await model.refresh()
        XCTAssertEqual(model.state?.currentDigimonId, "agu_digitama", "not yet")

        // Five minutes: hatched, and stamped with the instant it hatched at rather than the one it
        // was laid at.
        currentNow = Fixture.morning.addingTimeInterval(EggHatcher.maximumEggDuration)
        await model.refresh()
        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.currentDigimonId, "botamon", "hatched on the clock with no health data")
        XCTAssertEqual(state.stage, .babyI)
        XCTAssertEqual(state.hatchedDate, currentNow)
        XCTAssertEqual(state.stageEnteredDate, currentNow, "the Baby I's own stage starts now")
    }

    /// A frozen egg does not age toward the five-minute hatch. `Freeze.shiftTimeline` moves
    /// `stageEnteredDate` forward by exactly the span spent in the box, which US-222 makes
    /// load-bearing in a way it was not before: without it, an egg put away for an hour would hatch
    /// the instant it was taken out.
    func testAFrozenEggDoesNotAgeTowardTheHatch() throws {
        let egg = try XCTUnwrap(EvolutionGraph.bundled.node(id: "agu_digitama"))
        let state = GameState(currentDigimonId: "agu_digitama", now: Fixture.morning)

        // Away for an hour, twelve times the whole egg stage.
        state.freeze(at: Fixture.morning.addingTimeInterval(60))
        let outAgain = Fixture.morning.addingTimeInterval(60 + 60 * 60)
        state.thaw(at: outAgain)

        // One minute of egg was served before the freeze, so four minutes are left — and the
        // hour in the box bought none of them.
        XCTAssertEqual(state.stageEnteredDate, Fixture.morning.addingTimeInterval(60 * 60))
        XCTAssertNil(EggHatcher.hatchTarget(for: egg, stageEnergy: state.stageEnergy,
                                            stageEnteredAt: state.stageEnteredDate,
                                            stageMetrics: state.stageMetricTotals,
                                            now: outAgain),
                     "an hour in the box is not five minutes of egg")

        // Four more minutes of being OUT, and it hatches — the freeze delayed the hatch, it did not
        // cancel it.
        XCTAssertEqual(EggHatcher.hatchTarget(for: egg, stageEnergy: state.stageEnergy,
                                              stageEnteredAt: state.stageEnteredDate,
                                              stageMetrics: state.stageMetricTotals,
                                              now: outAgain.addingTimeInterval(4 * 60)),
                       "botamon")
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
        XCTAssertEqual(model.lifetimeEnergy.strength, 50, "but the life's energy is kept")
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
        walk(499) // under US-222's step path as well as under the energy one
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

    // MARK: Age (US-200)

    /// AC2 + AC3, through the real hatch: hatching stamps `hatchedDate` with the clock's instant, so
    /// a Digimon that hatches at `morning` reads 0Y right then and 1Y after one injected day. The
    /// clock is a mutable reference so the same model can be wound forward without waiting.
    func testHatchingStampsTheHatchDateAndAgeCountsFromIt() async throws {
        walk(5_000) // 50 energy — enough to hatch at the first read
        // A local mutable clock, since `makeModel` pins `now` to a constant.
        var currentNow = Fixture.morning
        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { currentNow },
            chooseStartingDigitama: { $0.first }
        )
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.currentDigimonId, "botamon", "it hatched")
        XCTAssertEqual(state.hatchedDate, Fixture.morning, "the hatch instant was stamped")
        XCTAssertEqual(model.ageYears, 0, "freshly hatched reads 0Y")

        // Wind the clock forward one day — the age the screen reads increments to 1Y.
        currentNow = Fixture.morning.addingTimeInterval(Death.secondsPerDay)
        XCTAssertEqual(model.ageYears, 1, "after one injected day, 1Y")
    }

    /// An egg that has NOT hatched has no age yet: `hatchedDate` stays nil and `ageYears` reads 0,
    /// so the strip never shows an egg a stale year.
    func testAnUnhatchedEggHasNoHatchDateAndReadsZeroYears() async throws {
        walk(499) // under every hatch path — see `testShortOfEveryHatchPathTheEggStaysAnEgg`
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "agu_digitama", "still an egg")
        XCTAssertNil(model.state?.hatchedDate, "an egg has not hatched, so nothing is stamped")
        XCTAssertEqual(model.ageYears, 0)
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
