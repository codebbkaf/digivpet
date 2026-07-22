import XCTest

@testable import DigiVPet

/// US-153 — the tenth of Phase E's orphan sweeps and the third at the Adult rung: the three playable
/// Champions whose display name begins H-L that no device tree and no Child sweep reached.
///
/// **The scope reading is US-151's and US-152's.** The criteria ask for coverage of "every remaining
/// orphan at stage Adult whose displayName starts with H-L", so the seventeen Champions in this range
/// that US-149 and US-150 left as LEAVES are not in scope — they have an in-edge and are therefore
/// not orphans. They stay in `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreTheOnesThe
/// SweepsHaveOpened`, which this story leaves at ninety-nine, and the Perfect sweeps from US-157 on
/// are what pays them off: giving an orphaned Perfect an in-edge is the same edge as giving a
/// leaf Champion its out-edge.
///
/// **Three, not the twenty-five the PRD estimated, and that is the device trees' doing.** The
/// estimate was taken when the Adult rung held 168 orphans; eleven device trees and three Child
/// sweeps later the whole rung holds 22, of which three fall in H-L. The range is derived from the
/// roster here rather than from a list, so the claim is checkable rather than asserted.
///
/// **What it costs one rung up: nothing.** All three land on a line that already has a Perfect, and
/// in all three cases the Perfect is one Wikimon itself names, because the line was chosen by
/// intersecting the orphan's `Evolves From` AND `Evolves To` against the graph — US-152's rule. The
/// most interesting case is Kinkakumon, where the cheap reading and the thematic one disagreed: see
/// `testKinkakumonTookTheCitedLineThatAlreadyHadAPerfectRung`.
final class AdultSweepHToLTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The three orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, perfect: String)] = [
        ("kausgammamon", "gammamon", "pencvb_weregarurumon"),
        ("kinkakumon", "jellymon", "zudomon"),
        ("kougamon", "mushmon", "jyureimon"),
    ]

    /// The junk Perfect each of the three lines already had, and which of the three falls to it.
    /// Nothing here is new: `andiramon_virus` is US-143's, `piranimon` US-139's, `tonosamagekomon`
    /// US-141's.
    private let junkFloors: [(adult: String, junk: String)] = [
        ("kausgammamon", "andiramon_virus"),
        ("kinkakumon", "piranimon"),
        ("kougamon", "tonosamagekomon"),
    ]

    /// The shared "did everything right" context, US-151's and US-152's exactly.
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
    func testEveryPlayableAdultHToLIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 28)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The three this story owns lead somewhere too. The rest are US-149's and US-150's leaves,
        // counted in `ChildSweepAToFTests`' dead-end ledger and wired onward by the Perfect sweeps.
        for (adult, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: adult)).evolutions.isEmpty,
                           "\(adult) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoAdultHToLIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Adults H-L still orphaned: \(orphans)")
    }

    /// The seventeen in range that this story deliberately did NOT wire onward, named rather than
    /// counted. They are leaves, not orphans, and every one of them is on the dead-end ledger; if a
    /// later story wires one, it belongs there and here, not silently in one place.
    func testTheAdultsHToLThisStoryLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        XCTAssertEqual(leaves,
                       // US-157 took THREE off this list by giving each an out-edge: Hakubamon
                       // (Cho-Hakkaimon, which opened `penc-sw`'s Perfect rung), Ice Devimon
                       // (Baalmon) and Lekismon (Crescemon).
                       ["hi-commandramon", "hookmon", "hyougamon",
                        "icemon", "igamon", "jazardmon", "junglemojyamon", "kokeshimon",
                        "kuwagamon_x", "kyubimon", "kyubimon_silver", "lavorvomon",
                        "leomon_x", "lianpumon"].sorted(),
                       "the H-L leaves have moved without the ledger moving with them")

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
            XCTAssertEqual(node.evolutions.count, 2, "\(adult) is not a branch plus a fallback")

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

    /// Nothing new at the Perfect rung, for the second sweep running. US-151 authored four Perfects
    /// for seven Champions; US-152 and US-153 between them authored none for eight, because both
    /// chose the line by intersecting BOTH ends of the Wikimon page against the graph.
    func testTheSweepAuthoredNoNewPerfectAndEveryFallbackIsAnExistingJunkFloor() throws {
        for (adult, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(adult) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(adult)'s line")
            XCTAssertEqual(floor.stage, .perfect)
        }

        // Every node this story added is an Adult, and every Perfect it points at is older than it.
        for (adult, _, perfect) in swept {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).stage, .adult)
            XCTAssertEqual(try XCTUnwrap(graph.node(id: perfect)).stage, .perfect)
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

    /// **This story said Gammamon was FULL. It was one branch short, and US-156 spent the branch.**
    /// `EvolutionEngine` picks on the dominant energy first, so two branches out of one node sharing
    /// an energy would make the second dead data — four energy types is the hard ceiling on earned
    /// branches, and after KausGammamon this node carried only THREE of them: BetelGammamon
    /// (spirit, US-149), GulusGammamon (strength, US-152) and KausGammamon (stamina). Vitality was
    /// free, and the junk edge to Turuiemon sharing spirit with BetelGammamon is what made the count
    /// of DISTINCT energies read as full when the count of EARNED branches did not. The wrong half
    /// of that claim travelled through US-154 and US-155 as advice, and US-156 checked it instead of
    /// inheriting it — WezenGammamon now hangs here on vitality, which is its bolded Wikimon arrow,
    /// rather than on the Gabumon stand-in this story found. NOW the node is full.
    func testEveryChildThisStoryBranchedStillUsesDistinctEnergiesAndGammamonIsFull() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }

        let gammamon = try XCTUnwrap(graph.node(id: "gammamon"))
        XCTAssertEqual(Set(gammamon.evolutions.filter { !$0.isDefault }.map(\.to)),
                       ["betelgammamon", "gulusgammamon", "kausgammamon", "wezengammamon"],
                       "US-156 spent the vitality this story mistook for spent")
        XCTAssertEqual(Set(gammamon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       Set(EnergyType.allCases), "Gammamon has an energy left after all")
        XCTAssertEqual(Set(gammamon.evolutions.compactMap(\.requiredEnergy)).count, 4,
                       "the junk fallback shares an energy with an earned branch, as it should")
        XCTAssertEqual(gammamon.evolutions.count, 5, "five is the ceiling, and it is reached now")

        // Mushmon was at three earned branches when this story ran and US-156's XV-mon Black filled
        // it. Jellymon, the tree's unlockable sixth Rookie, is still at two — said out loud so the
        // next sweep prices a third honestly.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mushmon"))
                           .evolutions.filter { !$0.isDefault }.count, 4)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "jellymon"))
                           .evolutions.filter { !$0.isDefault }.count, 2)
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
    /// merely hard. Restated over this story's six new edges because it is cheap and because the
    /// engine, not the validator, is the only thing that catches it.
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

    /// No new lines for three new nodes, and one node each on three existing ones.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["penc-vb"], 53, "US-153 added KausGammamon, US-154 two more, US-156 two more, US-157 four")
        XCTAssertEqual(sizes["penc-ds"], 39, "US-153 added Kinkakumon, US-154 MoriShellmon, US-157 Anomalocarimon X")
        XCTAssertEqual(sizes["penc-wg"], 37, "US-153 added Kougamon, US-154 RedV-dramon, US-156 two more")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.adult)?.line }).count, 3)
    }

    /// **The placement that had two defensible answers, and why the cheap one won.** Kinkakumon is
    /// an Oni of the Saiyu Warriors set: Wikimon cites Fujamon and Takinmon as parents to *Pendulum
    /// COLOR 6 Saiyu Warriors*, and both are Children on `penc-sw`. That reading was rejected on
    /// PRICE, not on citation — `penc-sw` has no Perfect rung at all, so it would have cost an
    /// earned Perfect plus a junk floor under it, the two-node bill US-151 paid twice. The Vital
    /// Bracelet BE reading cites Jellymon below and Zudomon above, and BOTH were already on
    /// `penc-ds`. Pinned from both sides: the `penc-sw` Children really are still free of it, and
    /// `penc-sw` really does still have no Perfect, so the day someone opens that rung this test
    /// tells them Kinkakumon is a candidate to rehome.
    func testKinkakumonTookTheCitedLineThatAlreadyHadAPerfectRung() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kinkakumon")).line, "penc-ds")

        for id in ["fujamon", "takinmon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.line, "penc-sw")
            XCTAssertFalse(node.evolutions.map(\.to).contains("kinkakumon"),
                           "\(id) reaches Kinkakumon, so the rejected reading was taken after all")
        }

        // US-157 OPENED THAT RUNG, so the "still no Perfect" half of this claim is flipped rather
        // than deleted: `penc-sw` now has Cho-Hakkaimon and the junk floor Pandamon under it, which
        // is exactly the two-node bill this test quoted. Kinkakumon is therefore a live rehome
        // candidate — and it is NOT rehomed here, because a Champion's move drags its whole thread
        // (Jellymon below, Zudomon above) across a line and that is a story of its own.
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .perfect }
                        .map(\.id).sorted(),
                       ["chohakkaimon", "pandamon"],
                       "`penc-sw`'s Perfect rung has moved since US-157 opened it")

        let comment = try authoredComment(on: "kinkakumon")
        XCTAssertTrue(comment.contains("Saiyu Warriors"),
                      "the rejected reading is not written down where the next reader will find it")
        XCTAssertTrue(comment.contains("Vital Bracelet BE"))
    }

    /// The other two placements needed no argument at all: for each, the parent Wikimon bolds and
    /// the Perfect it names were BOTH already on one line before this story touched it. Asserted as
    /// the shape that produces rather than as a comment.
    func testTheOtherTwoPlacementsLandedOnLinesThatAlreadyHeldBothEnds() throws {
        for (adult, parent, perfect) in swept where adult != "kinkakumon" {
            let line = try XCTUnwrap(graph.node(id: adult)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line)
            XCTAssertEqual(try XCTUnwrap(graph.node(id: perfect)).line, line)
        }

        // KausGammamon's whole placement is one device's drawing — Wikimon cites Gammamon below it
        // and WereGarurumon above it to Pendulum COLOR ZERO Virus Busters, and gives its family as
        // Virus Busters outright, which is the line it is on.
        XCTAssertTrue(try authoredComment(on: "kausgammamon").contains("Pendulum COLOR ZERO"))
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Kougamon is the case that makes this worth restating — it has
    /// a sheet in `Adult/` AND a frame in `Idle Frame Only/`, and only the first is playable.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for (id, _, _) in swept {
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
        for (id, _, _) in swept {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }
    }

    /// **The handover this story wrote, now CLOSED — the same fact from the other side.**
    /// KausGammamon's bolded Evolves To is Canoweissmon, which had a full Perfect sheet on disk and
    /// no node; this story took WereGarurumon, the cited alternative that already existed, rather
    /// than spend a Perfect, and left the thread open. US-156 spent it — but on WezenGammamon, not
    /// on KausGammamon, so the arrow this story declined is STILL not drawn and the reason it was
    /// declined still holds. Both halves are pinned: Canoweissmon exists and KausGammamon does not
    /// reach it.
    func testTheGammamonThreadThisStoryLeftOpenWasSpentOnWezenGammamonInstead() throws {
        let canoweissmon = try XCTUnwrap(graph.node(id: "canoweissmon"),
                                         "US-156 wired it; it cannot have gone away")
        XCTAssertEqual(canoweissmon.line, "penc-vb")
        XCTAssertEqual(graph.parents(of: "canoweissmon").map(\.id), ["wezengammamon"],
                       "KausGammamon's declined arrow was drawn after all — say which story did it")
        XCTAssertNotNil(graph.node(id: "wezengammamon"),
                        "WezenGammamon is US-156's U-Z orphan and should be wired")
        XCTAssertTrue(try authoredComment(on: "kausgammamon").contains("Canoweissmon"),
                      "the arrow that was NOT taken is not written down")
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// THREE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 314 before, 311 after; the Adult bucket falls 22 -> 19 and no other bucket moves, because
    /// this story spent no Perfect. Asserted rather than only noted, because the count is the one
    /// claim in `notes` a later reader cannot re-derive from the diff.
    func testTheThreeOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 3)

        for (id, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 672,
                       "615 before this story, 618 after it, 629 after US-154, 635 after US-155, "
                           + "643 after US-156, 672 after US-157")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because one of this story's edges asks for FEW sleep disturbances
    /// and a blanket "did everything right" context is the one thing that cannot take an `atMost`.
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
    /// helper US-144 through US-152 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
