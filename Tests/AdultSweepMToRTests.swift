import XCTest

@testable import DigiVPet

/// US-154 — the eleventh of Phase E's orphan sweeps and the fourth at the Adult rung: the nine
/// playable Champions whose display name begins M-R that no device tree and no Child sweep reached.
///
/// **The scope reading is US-151's through US-153's.** The criteria ask for coverage of "every
/// remaining orphan at stage Adult whose displayName starts with M-R", so the seventeen Champions in
/// this range that US-149 and US-150 left as LEAVES are not in scope — they have an in-edge and are
/// therefore not orphans. They stay in `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreThe
/// OnesTheSweepsHaveOpened`, and the Perfect sweeps from US-157 on are what pays them off.
///
/// **Nine, not the thirty-three the PRD estimated.** The estimate was taken when the Adult rung held
/// 168 orphans; eleven device trees and three Child sweeps later the whole rung holds 19, of which
/// nine fall in M-R. The range is derived from the roster here rather than from a list, so the claim
/// is checkable rather than asserted.
///
/// **What it costs one rung up: two Perfects, and that number is the story.** Five of the nine
/// landed on a line that already had the Perfect Wikimon names for them — the US-152 rule of
/// intersecting `Evolves From` AND `Evolves To` before choosing a line. The other four are
/// X-Antibody Champions of the `tamers` X thread, and EVERY Perfect any of them cites is a sheet on
/// disk with no node, so the rung above had to be opened. It was opened twice rather than four
/// times because the citations pair up: Grademon is in the Evolves To of both Meramon X and
/// Pegasmon X off *Digital Monster X Ver.3*, and Mametyramon is the two sides of Bx-43, which
/// fuses Monochromon X and Pteranomon X. Neither needed a junk floor under it — US-151 put
/// CatchMamemon under `tamers` already.
final class AdultSweepMToRTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The nine orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, perfect: String)] = [
        ("meramon_x", "blucomon", "grademon"),
        ("mikemon", "plotmon", "pencvb_angewomon"),
        ("monochromon_x", "guilmon_x", "mametyramon"),
        ("morishellmon", "ganimon", "anomalocarimon"),
        ("musyamon", "picodevimon", "vamdemon"),
        ("nefertimon_x", "plotmon_x", "pencvb_angewomon"),
        ("pegasmon_x", "lopmon_x", "grademon"),
        ("pteranomon_x", "monodramon", "mametyramon"),
        ("redv-dramon", "pencwg_piyomon", "aerov-dramon"),
    ]

    /// The two Perfects this story authored, and the two Champions each was authored for. Both are
    /// leaves until the Ultimate sweeps, and both are on the ledger in `ChildSweepAToFTests`.
    /// US-155 gave Grademon a THIRD parent, Siesamon X, and the claim is widened by NAMING it
    /// rather than by loosening the equality: Wikimon draws Siesamon (X-Antibody) into Grademon off
    /// the same *Digital Monster X Ver.3* the other two arrows come from, so it is the same
    /// drawing, one card wider.
    private let authoredPerfects: [(perfect: String, parents: Set<String>)] = [
        ("grademon", ["meramon_x", "pegasmon_x", "siesamon_x"]),
        ("mametyramon", ["monochromon_x", "pteranomon_x"]),
    ]

    /// The junk Perfect each of the five lines already had, and which Champion falls to it. Nothing
    /// here is new: `catchmamemon` is US-151's, `andiramon_virus` US-143's, `piranimon` US-139's,
    /// `darumamon` US-140's, `tonosamagekomon` US-141's.
    private let junkFloors: [(adult: String, junk: String)] = [
        ("meramon_x", "catchmamemon"),
        ("mikemon", "andiramon_virus"),
        ("monochromon_x", "catchmamemon"),
        ("morishellmon", "piranimon"),
        ("musyamon", "darumamon"),
        ("nefertimon_x", "andiramon_virus"),
        ("pegasmon_x", "catchmamemon"),
        ("pteranomon_x", "catchmamemon"),
        ("redv-dramon", "tonosamagekomon"),
    ]

    /// The shared "did everything right" context, US-151's through US-153's exactly.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.standHours": 1_000,
                                           "health.flightsClimbed": 5_000,
                                           "health.distanceWalkingRunning": 500_000,
                                           "health.sleep": 100_000]),
        trainingSessionsThisStage: 30,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 40,
        battleWinRatioLifetime: 1.0)

    // MARK: - AC1: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so an Adult sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableAdultMToRIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("M"..."R").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 39)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The nine this story owns lead somewhere too. The rest are US-149's and US-150's leaves.
        for (adult, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: adult)).evolutions.isEmpty,
                           "\(adult) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoAdultMToRIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("M"..."R").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Adults M-R still orphaned: \(orphans)")
    }

    /// The seventeen in range that this story deliberately did NOT wire onward, named rather than
    /// counted. They are leaves, not orphans, and every one of them is on the dead-end ledger; if a
    /// later story wires one, it belongs there and here, not silently in one place.
    func testTheAdultsMToRThisStoryLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("M"..."R").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        XCTAssertEqual(leaves,
                       // US-157 took THREE off this list by giving each an out-edge: Paledramon
                       // (Crys Paledramon), Porcupamon (Astamon) and Raptordramon (Cerberumon X).
                       // US-159 took TWO more: Numemon X (LadyDevimon X, which is the only cited
                       // parent for that variant anywhere in this graph) and Omekamon
                       // (Hisyaryumon). Numemon X is `tamers`' JUNK Champion, so it is the third
                       // junk node in the file with an earned branch, after Raremon and Scumon.
                       // US-160 took ONE more, Meicoomon (both Meicrackmon) — the arrow that
                       // opened `diablomon`'s Perfect rung, and the only parent this pack can
                       // draw for either of them.
                       // US-162 took TWO more, and both are the shape this file keeps recording:
                       // Nise Drimogemon (Vermillimon) is `adventure02`'s JUNK Champion — the
                       // fourth junk node in the file with an earned branch — and branching it
                       // opened that line's Perfect rung AND promoted both its eggs at once, which
                       // is what US-161 could not do through XV-mon. Reppamon (Shishimamon) is the
                       // ordinary kind.
                       ["madleomon", "manekimon", "mantaraymon_x", "mimicmon",
                        "ogremon_x",
                        "parasaurmon", "peckmon", "pidmon",
                        "rhinomon_x"].sorted(),
                       "the M-R leaves have moved without the ledger moving with them")

        for id in leaves {
            XCTAssertFalse(graph.parents(of: id).isEmpty,
                           "\(id) is an orphan rather than a leaf, so it WAS in this story's scope")
        }
    }

    // MARK: - AC2/AC3: the shape of every edge this story authored

    /// Each swept Champion is one earned branch plus one unconditioned fallback, and the fallback is
    /// its own line's junk Perfect. A condition on a fallback would be data that lies — US-020 takes
    /// the `isDefault` edge exactly when nothing else qualifies — which is the reading of "no edge
    /// is unconditional" every rung below recorded.
    func testEverySweptChampionIsOneEarnedBranchAndOneUnconditionedFallback() throws {
        for (adult, _, perfect) in swept {
            let node = try XCTUnwrap(graph.node(id: adult))
            // Musyamon is THREE since US-162 hung Vamdemon X on it beside the Vamdemon this
            // story gave it — the variant on the very Champion its base form has. A named
            // exception rather than a loosened `>=`, the shape US-160 established.
            XCTAssertEqual(node.evolutions.count, adult == "musyamon" ? 3 : 2,
                           "\(adult) is not a branch plus a fallback")

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.conditions, [], "\(adult)'s fallback carries criteria")
            XCTAssertEqual(fallback.minEnergy, 0, "\(adult)'s fallback demands energy")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)

            let earned = try XCTUnwrap(node.evolutions.first { !$0.isDefault })
            XCTAssertEqual(earned.to, perfect)
            XCTAssertFalse(earned.conditions.isEmpty,
                           "\(adult) -> \(perfect) is gated on energy alone")
            for condition in earned.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(adult) -> \(perfect) has an undiscoverable criterion")
            }
            XCTAssertGreaterThan(earned.minEnergy, fallback.minEnergy,
                                 "\(adult)'s junk edge would win the branch outright")
        }
    }

    /// Every fallback is a junk Perfect that already existed on the Champion's own line — the two
    /// Perfects this story DID author are earned branches, not floors.
    func testEveryFallbackIsAnExistingJunkFloorOnTheChampionsOwnLine() throws {
        for (adult, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(adult) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(adult)'s line")
            XCTAssertEqual(floor.stage, .perfect)
            XCTAssertFalse(authoredPerfects.map(\.perfect).contains(junk),
                           "\(junk) is one of this story's own Perfects, so it is not an old floor")
        }
    }

    /// **The two Perfects this story opened, and the pairing that made them two instead of four.**
    /// Each was authored for exactly the two Champions Wikimon cites into it, so a third parent
    /// hung here later fails this rather than passing quietly — the `Set(graph.parents(of:))`
    /// equality shape US-151 and US-152 established.
    func testTheTwoPerfectsThisStoryOpenedEachServeExactlyTwoOfItsChampions() throws {
        for (perfect, parents) in authoredPerfects {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertEqual(node.line, "tamers", "\(perfect) is not on the X-Antibody line")
            // US-163 gave BOTH of them their Ultimate and moved the ledger with them, which is
            // exactly what this message asked for: Grademon climbs to Alphamon — its bolded
            // `Evolves From` on that page — and Mametyramon to Bagramon.
            let wiredByUS163 = ["grademon": "alphamon", "mametyramon": "bagramon"]
            XCTAssertEqual(node.evolutions.map(\.to), [wiredByUS163[perfect]].compactMap { $0 },
                           "\(perfect)'s single climb is not the one US-163 gave it")
            XCTAssertEqual(Set(graph.parents(of: perfect).map(\.id)), parents,
                           "\(perfect)'s parents changed without this claim changing with them")
        }

        // And the five that cost nothing: each landed on a Perfect that had a parent before this
        // story, which is what "authored no new Perfect" means for them.
        for (adult, _, perfect) in swept
        where !authoredPerfects.map(\.perfect).contains(perfect) {
            XCTAssertGreaterThan(graph.parents(of: perfect).count, 1,
                                 "\(perfect) was reached only by \(adult), so it is new after all")
        }
    }

    /// The in-edges are earned too, and none of them displaces the fallback of the Child it hangs
    /// off — the guard every sweep below this one needed.
    func testEveryNewChildBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (adult, parent, _) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == adult },
                                     "\(parent) does not reach \(adult)")
            XCTAssertFalse(edge.isDefault, "\(parent) -> \(adult) took over the junk branch")
            XCTAssertFalse(edge.conditions.isEmpty, "\(parent) -> \(adult) is gated on nothing")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(parent) -> \(adult) has an undiscoverable criterion")
            }
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has a single fallback")
        }
    }

    /// **Plotmon is now FULL, and this is where that is written down.** `EvolutionEngine` picks on
    /// the dominant energy first, so two branches out of one node sharing an energy would make the
    /// second dead data — four energy types is a hard ceiling on earned branches. Plotmon carries
    /// Tailmon (vitality, US-143), Wizarmon (spirit, US-143), BlackTailmon (strength, US-151) and
    /// now Mikemon (stamina). No later sweep can hang a fifth here: it must find another parent.
    func testEveryChildThisStoryBranchedStillUsesDistinctEnergiesAndPlotmonIsFull() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }

        let plotmon = try XCTUnwrap(graph.node(id: "plotmon"))
        XCTAssertEqual(Set(plotmon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       Set(EnergyType.allCases), "Plotmon has an energy left after all")
        XCTAssertEqual(plotmon.evolutions.count, 5, "five is the ceiling `EvolutionCriteriaTests` sets")

        // Pico Devimon is full too, on the same arithmetic. Monodramon, Ganimon and Piyomon are one
        // branch short of it and the four remaining Rookies are two — said out loud so the next
        // sweep prices a branch off this list rather than by discovering the ceiling as a failure.
        let earnedCounts = Dictionary(uniqueKeysWithValues: Set(swept.map(\.parent)).map {
            ($0, (graph.node(id: $0)?.evolutions.filter { !$0.isDefault }.count) ?? 0)
        })
        XCTAssertEqual(earnedCounts["plotmon"], 4)
        XCTAssertEqual(earnedCounts["monodramon"], 3)
        XCTAssertEqual(earnedCounts["picodevimon"], 4)
        XCTAssertEqual(earnedCounts["ganimon"], 3)
        XCTAssertEqual(earnedCounts["pencwg_piyomon"], 4, "US-156 filled it with V-dramon Black")
        for id in ["blucomon", "guilmon_x", "lopmon_x", "plotmon_x"] {
            XCTAssertEqual(earnedCounts[id], 2, "\(id) is not the two branches this story left it")
        }
    }

    /// **Musyamon shares its energy with its own Child's junk fallback, on purpose.** Pico Devimon
    /// had exactly one energy left — Devimon took spirit, Bakemon vitality, Dokugumon stamina — and
    /// its junk edge to Gokimon is gated on strength too. That is the Scumon arrangement US-133
    /// recorded rather than a collision: the junk edge asks for 0 energy, the earned one for 60, so
    /// the earned branch wins whenever it is earned and the junk one whenever it is not.
    func testMusyamonSharesStrengthWithPicoDevimonsJunkEdgeAndStillWins() throws {
        let picodevimon = try XCTUnwrap(graph.node(id: "picodevimon"))
        let junk = try XCTUnwrap(picodevimon.evolutions.first(where: \.isDefault))
        let earned = try XCTUnwrap(picodevimon.evolutions.first { $0.to == "musyamon" })
        XCTAssertEqual(junk.requiredEnergy, earned.requiredEnergy)
        XCTAssertGreaterThan(earned.minEnergy, junk.minEnergy)

        var totals = EnergyTotals()
        totals[.strength] = earned.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: picodevimon, stageEnergy: totals,
                                            dominant: .strength, careMistakes: 0, battleWins: 40,
                                            conditions: context(for: earned)),
            "musyamon", "a well-raised strength Pico Devimon does not reach Musyamon")

        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: picodevimon, stageEnergy: EnergyTotals(),
                                            dominant: .strength, careMistakes: 0, battleWins: 0,
                                            conditions: .unknown),
            junk.to, "a neglected strength Pico Devimon does not fall to \(junk.to)")
    }

    /// Every edge this story authored is really reachable through the engine, criteria and all —
    /// the check that separates an authored edge from a taken one. Both directions: the Child's new
    /// branch, and the Champion's own.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (adult, parent, perfect) in swept {
            for (from, to) in [(parent, adult), (adult, perfect)] {
                let node = try XCTUnwrap(graph.node(id: from))
                let edge = try XCTUnwrap(node.evolutions.first { $0.to == to })
                let energy = try XCTUnwrap(edge.requiredEnergy)
                var totals = EnergyTotals()
                totals[energy] = edge.minEnergy

                XCTAssertEqual(
                    EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                                    dominant: energy, careMistakes: 0,
                                                    battleWins: 40, conditions: context(for: edge)),
                    to,
                    "\(from) does not reach \(to) on the energy its own edge asks for")
            }
        }
    }

    /// And a neglected one falls to junk instead. Read through `scheduledEvolutionTarget` with the
    /// gate open and an EMPTY context, which is what "the owner did nothing" actually looks like.
    func testANeglectedSweptChampionFallsToItsLinesJunkPerfect() throws {
        for (adult, junk) in junkFloors {
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: try XCTUnwrap(graph.node(id: adult)), stageEnergy: EnergyTotals(),
                    dominant: nil, careMistakes: 9, battleWins: 0,
                    stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                junk,
                "a neglected \(adult) does not fall to \(junk)")
        }
    }

    /// The window trap US-150 shipped into a first draft and `ChildSweepMToZTests` pinned over the
    /// whole file: `care.battleCount` is answerable only over `lifetime` and every other `care.*`
    /// counter only over `stage`, so an edge that asks the other way is UNREACHABLE rather than
    /// merely hard. Restated over this story's eighteen new edges because it is cheap and because
    /// the engine, not the validator, is the only thing that catches it.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        let touched = swept.map(\.adult) + swept.map(\.parent)
        for id in Set(touched) {
            for edge in try XCTUnwrap(graph.node(id: id)).evolutions {
                for condition in edge.conditions {
                    guard let metric = condition.knownMetric, !metric.isHealthMetric else { continue }
                    XCTAssertEqual(condition.window == .lifetime, metric == .careBattleCount
                                       || metric == .careBattleWinRatio,
                                   "\(id) -> \(edge.to): \(metric.rawValue) over \(condition.window)")
                }
            }
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line, still — the rule that decides every placement here. An
    /// Adult that could not be put on the line of the Child below it has been paired with the
    /// wrong Child.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// No new lines for eleven new nodes: six onto `tamers`, two onto `penc-vb`, one each onto
    /// `penc-ds`, `penc-nso` and `penc-wg`. A sweep must not produce dozens of one-node lines, and
    /// the way this one satisfies that is by opening none at all.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 116, "four Champions and both new Perfects, plus US-156's two and US-157's eight, plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["penc-vb"], 60, "Mikemon and Nefertimon X, plus US-156's two and US-157's four, plus US-158's Entmon, plus US-161's Regulusmon, plus US-163's two Ultimates")
        XCTAssertEqual(sizes["penc-ds"], 46, "MoriShellmon, plus US-157's Anomalocarimon X, plus US-158's Gusokumon, plus US-159's Hangyomon" + ", plus US-160's two, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-nso"], 73, "Musyamon, plus US-157's Archnemon and BlueMeramon, plus US-158's three, plus US-159's four" + ", plus US-160's five, plus US-161's Orochimon, plus US-163's seven Ultimates")
        XCTAssertEqual(sizes["penc-wg"], 43, "RedV-dramon, plus US-156's two Black V-dramon, plus US-158's two, plus US-161's Paildramon")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.adult)?.line }).count, 5)
    }

    /// **The four X-Antibody Champions all went to `tamers`, and the variants sit with their base
    /// form's LINE rather than beside their base form.** Meramon, Monochromon and Pteranomon's base
    /// nodes are on other lines entirely; what carries the four is the X-Antibody Rookie each hangs
    /// off, which is where every X variant in this file lives. Stated as the shape rather than as a
    /// comment: each of the four hangs off a Child whose own id ends in `_x`, or off Monodramon and
    /// Blucomon, the two `tamers` Rookies the X device draws into them.
    func testTheFourXAntibodyChampionsFollowedTheXThreadRatherThanTheirBaseForms() throws {
        let onTheXThread = ["meramon_x", "monochromon_x", "pegasmon_x", "pteranomon_x"]
        for (adult, parent, _) in swept where onTheXThread.contains(adult) {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).line, "tamers")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, "tamers")
        }
        XCTAssertEqual(swept.map(\.adult).filter { $0.hasSuffix("_x") }.sorted(),
                       (onTheXThread + ["nefertimon_x"]).sorted(),
                       "an X-Antibody Champion appeared that this claim does not account for")

        // The base forms really are elsewhere, which is what makes this a line rule and not a
        // coincidence. Pegasmon and Nefertimon have no base node at all — only the X sheets exist.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "meramon")).line, "dmc-v1")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "monochromon")).line, "dmc-v4")
        XCTAssertNil(graph.node(id: "pteranomon"))
        for id in ["pegasmon", "nefertimon"] {
            XCTAssertNil(roster.entry(id: id), "\(id) has a sheet now, so its X form has a base")
        }

        // Nefertimon X is the exception that proves the rule and the reason it is not on `tamers`:
        // its cited Rookie is Plotmon X, which US-150 put on `penc-vb` because `penc-ds` had no
        // room — so the variant followed the citation onto the holy line, not the X line.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "nefertimon_x")).line, "penc-vb")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "plotmon_x")).line, "penc-vb")
    }

    /// **The one Champion whose out-edge could not be a named citation, and the class citation that
    /// carries it instead.** Every Digimon Wikimon names in Mikemon's `Evolves To` is unusable in
    /// this pack — Bastemon and Betsumon have no sheet, Majiramon is idle-only and
    /// `edgeToDexOnlyNode` forbids the edge, Zudomon is on a line no cited parent of Mikemon
    /// reaches. What is left is the same page's CLASS clause, "Any Yellow Lv.5 Digimon from the
    /// Digimon Card Game", which US-151 established is a real citation when it wired Deckerdramon.
    /// Pinned in all four directions so that the day a Bastemon sheet appears this test says so.
    func testMikemonsOutEdgeRestsOnTheClassCitationBecauseEveryNamedOneIsUnusable() throws {
        for id in ["bastemon", "betsumon"] {
            XCTAssertNil(roster.entry(id: id),
                         "\(id) is on disk now — Mikemon has a named Perfect after all")
        }
        XCTAssertEqual(roster.entry(id: "majiramon")?.dexOnly, true,
                       "Majiramon animates now, so Mikemon's bolded arrow is drawable")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "zudomon")).line, "penc-ds")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mikemon")).line, "penc-vb")

        let comment = try authoredComment(on: "mikemon")
        XCTAssertTrue(comment.contains("Digimon Card Game"),
                      "the class citation Mikemon's out-edge rests on is not written down")
        XCTAssertTrue(comment.contains("Bastemon"), "the arrow that was NOT taken is not named")
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to the two new Perfects as well as the nine Champions,
    /// since this is the first Adult sweep since US-151 to author a node above its own rung.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for id in swept.map(\.adult) + authoredPerfects.map(\.perfect) {
            let node = try XCTUnwrap(graph.node(id: id))
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) has no roster entry")
            XCTAssertFalse(entry.dexOnly, "\(id) is idle-only and must not be on an edge")
            XCTAssertEqual(node.spriteFile, entry.spriteFile)
            XCTAssertEqual(node.stage, entry.stage)

            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, .stage, id)
        }
    }

    /// Nothing on either end of a new edge is a Dex-only Digimon — the whole-file form of the check,
    /// since the validator's `edgeToDexOnlyNode` finding is what would fire.
    func testNoEdgeInTheFileTouchesADexOnlyDigimon() {
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(roster.entry(id: edge.to)?.dexOnly, true,
                                  "\(node.id) -> \(edge.to) reaches an idle-only Digimon")
            }
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.adult) + authoredPerfects.map(\.perfect) {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }
    }

    /// **The handover to US-155 and US-156, in the shape US-151 through US-153 established: a
    /// claim, not a note.** Two of this story's Champions cite Perfects that are sheets on disk with
    /// no node — Meramon X names Cyberdramon X, Mamemon X and OmegaShoutmon X, Pegasmon X names
    /// Angewomon X, Hisyaryumon and Monzaemon X — and all six were left to the Perfect sweeps
    /// rather than spent here. When one is wired this test fails, and whoever wires it has to say
    /// which arrow they drew.
    ///
    /// WezenGammamon was the other half: US-153 expected it in THIS story's range, but its display
    /// name starts with W, so it went to US-156 — which wired it, and found that the advice attached
    /// to it was wrong. Gammamon was NOT full; vitality was free, so the bolded arrow was drawn and
    /// the Gabumon stand-in was not needed. The claim here is now the corrected one.
    ///
    /// **US-157 wired TWO of the six, and neither is the arrow this story left.** Cyberdramon X and
    /// Angewomon X are Perfects whose display names begin A-C, so the first Perfect sweep owned
    /// them — but it hung Cyberdramon X off Revolmon on `penc-me` and Angewomon X off Tailmon X on
    /// `penc-vb`, NOT off Meramon X or Pegasmon X, both of which are `tamers` and both of which are
    /// still full up. So the four still owed are the four below, and the two that left are pinned
    /// with the parent they actually took.
    ///
    /// **US-159 wired a THIRD, and it is the same answer again.** Hisyaryumon is a Perfect whose
    /// display name begins H-L, so the third Perfect sweep owned it — and it hung it off Omekamon
    /// on `penc-me`, NOT off the Pegasmon X that named it here, because Pegasmon X is still full.
    /// Ginryumon, the page's bolded parent, is on `commandramon`, which still has no Perfect rung
    /// at all; Hisyaryumon's own node comment pins it as that line's rehome candidate.
    func testThePerfectSheetsLeftForTheLaterSweepsAreStillUnwired() throws {
        // **US-161 WIRED THE LAST OF THEM, AND IT DID NOT TAKE THE ARROW THIS STORY LEFT EITHER.**
        // OmegaShoutmon X has no cited parent and no cited climb on ANY one line, so the variant
        // rule decided it outright: it hangs off Shoutmon King on `xros` beside the plain
        // OmegaShoutmon, not off the Meramon X this story nominated. The pin is FLIPPED rather
        // than deleted, so the claim about this story's own Champions still bites.
        XCTAssertNotNil(roster.entry(id: "omegashoutmon_x"),
                        "omegashoutmon_x is on disk, which is why it was owed")
        XCTAssertEqual(graph.parents(of: "omegashoutmon_x").map(\.id), ["shoutmon_king"],
                       "omegashoutmon_x moved — say which Champion has it now")

        // **US-160 WIRED THE OTHER TWO, AND NEITHER TOOK THE ARROW THIS STORY LEFT.** Mamemon X
        // and Monzaemon X are Perfects whose display names begin with M, so the M sweep owned
        // them — and it put both on `dmc-v1` by the variant rule, beside the plain Mamemon and the
        // plain Monzaemon, rather than on the `tamers` Meramon X / Pegasmon X this story nominated.
        // Both of those Champions are still full, which is the same answer US-157 and US-159 gave.
        for (perfect, parent) in [("cyberdramon_x", "revolmon"), ("angewomon_x", "tailmon_x"),
                                  ("hisyaryumon", "omekamon"),
                                  ("mamemon_x", "greymon_blue"), ("monzaemon_x", "numemon")] {
            XCTAssertEqual(graph.parents(of: perfect).map(\.id), [parent],
                           "\(perfect) was wired off a different Champion than the sweep recorded")
        }
        for champion in ["meramon_x", "pegasmon_x"] {
            XCTAssertFalse(
                try XCTUnwrap(graph.node(id: champion)).evolutions.map(\.to)
                    .contains(where: ["cyberdramon_x", "angewomon_x", "hisyaryumon",
                                      "omegashoutmon_x"].contains),
                "\(champion) took one of the four after all — then this claim wants rewriting")
        }
        XCTAssertTrue(try authoredComment(on: "meramon_x").contains("Cyberdramon"),
                      "the arrows that were NOT taken are not written down")
        XCTAssertTrue(try authoredComment(on: "pegasmon_x").contains("Hisyaryumon"))

        XCTAssertNotNil(graph.node(id: "wezengammamon"),
                        "WezenGammamon is a W, so US-156 owns it and should have wired it")
        XCTAssertEqual(graph.parents(of: "wezengammamon").map(\.id), ["gammamon"],
                       "US-156 found Gammamon had vitality free; if that changed, say which story")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gammamon")).evolutions.count, 5,
                       "Gammamon is at the ceiling now — four earned branches plus the fallback")
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// NINE Champions plus TWO Perfects, counted with Appendix B of the PRD over a regenerated
    /// `roster.generated.json`: 311 before, 300 after; the Adult bucket falls 19 -> 10 and the
    /// Perfect bucket 110 -> 108, because the two Perfects this story opened were orphans too.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later
    /// reader cannot re-derive from the diff.
    func testTheElevenOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 9)
        XCTAssertEqual(authoredPerfects.count, 2)

        for id in swept.map(\.adult) + authoredPerfects.map(\.perfect) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 837, "618 before this story, 635 after US-155, 643 after US-156, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because one of this story's edges asks for FEW overfeeds and a
    /// blanket "did everything right" context is the one thing that cannot take an `atMost`.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30

        for condition in edge.conditions where condition.comparison == .atMost {
            switch condition.knownMetric {
            case .careTrainingSessions: training = 0
            case .some(let metric) where metric.isHealthMetric: values[metric.rawValue] = 0
            default: break
            }
        }

        return ConditionContext(
            stageTotals: MetricTotals(values: values),
            trainingSessionsThisStage: training,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 40,
            battleWinRatioLifetime: 1.0)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-153 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
