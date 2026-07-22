import XCTest

@testable import DigiVPet

/// US-156 — the thirteenth of Phase E's orphan sweeps and the sixth and LAST at the Adult rung: the
/// five playable Champions whose display name begins U-Z that no device tree and no earlier sweep
/// reached. With these five the whole Adult bucket of the Appendix B count is EMPTY — the first rung
/// above Child to be finished, and the claim `testTheAdultRungHoldsNoOrphanAtAll` makes.
///
/// **The scope reading is US-151's through US-155's.** The criteria ask for coverage of "every
/// remaining orphan at stage Adult whose displayName starts with U-Z", so the five Champions in this
/// range that US-149 and US-150 left as LEAVES are not in scope — they have an in-edge and are
/// therefore not orphans. They stay in `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreThe
/// OnesTheSweepsHaveOpened`, and the Perfect sweeps from US-157 on are what pays them off.
///
/// **What it costs one rung up: THREE Perfects, and two Champions that cost nothing at all.** Both
/// Black V-dramon landed on AeroV-dramon, which `penc-wg` has carried since US-141, so the US-152
/// rule of intersecting `Evolves From` AND `Evolves To` paid off twice. The other three could not:
/// WezenGammamon's, Xiquemon's and Youkomon's cited Perfects are, every one of them, either a sheet
/// with no node or — for Youkomon, twice over — one of the 157 idle-only Digimon an edge may not
/// touch at all. Each new Perfect cost ONE node rather than two, because every line involved already
/// had a junk floor.
final class AdultSweepUToZTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The five orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, perfect: String)] = [
        ("v-dramon_black", "pencwg_piyomon", "aerov-dramon"),
        ("xv-mon_black", "mushmon", "aerov-dramon"),
        ("wezengammamon", "gammamon", "canoweissmon"),
        ("xiquemon", "piyomon", "huankunmon"),
        ("youkomon", "renamon", "blackrapidmon"),
    ]

    /// The three Perfects this story authored, and the one Champion each was authored for. All three
    /// are leaves until the Ultimate sweeps, and all three are on the ledger in `ChildSweepAToFTests`.
    private let authoredPerfects: [(perfect: String, parents: Set<String>, line: String)] = [
        ("canoweissmon", ["wezengammamon"], "penc-vb"),
        ("huankunmon", ["xiquemon"], "dmc-v4"),
        ("blackrapidmon", ["youkomon"], "tamers"),
    ]

    /// The junk Perfect each of the four lines already had, and which Champion falls to it. Nothing
    /// here is new: `tonosamagekomon` is US-141's, `andiramon_virus` US-143's, `greatkingscumon`
    /// US-142's and `catchmamemon` US-151's.
    private let junkFloors: [(adult: String, junk: String)] = [
        ("v-dramon_black", "tonosamagekomon"),
        ("xv-mon_black", "tonosamagekomon"),
        ("wezengammamon", "andiramon_virus"),
        ("xiquemon", "greatkingscumon"),
        ("youkomon", "catchmamemon"),
    ]

    /// The shared "did everything right" context, US-151's through US-155's exactly.
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
    func testEveryPlayableAdultUToZIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("U"..."Z").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 17)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The five this story owns lead somewhere too. The rest are US-149's and US-150's leaves.
        for (adult, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: adult)).evolutions.isEmpty,
                           "\(adult) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoAdultUToZIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("U"..."Z").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Adults U-Z still orphaned: \(orphans)")
    }

    /// **The claim the six Adult sweeps have been building to since US-151, and the reason this
    /// story is the last of them.** Not "every Champion U-Z", which the test above already says, but
    /// every Champion in the FILE and every playable Champion in the ROSTER — the two counts differ,
    /// and both have to be zero. US-151 through US-155 cleared A-T; this one clears the tail and
    /// takes the Adult bucket of the Appendix B count from five to nothing.
    func testTheAdultRungHoldsNoOrphanAtAll() {
        let orphaned = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
            .sorted()
        XCTAssertEqual(orphaned, [], "the Adult rung is not finished after all: \(orphaned)")

        // And over the graph, which sees the line-scoped aliases the roster loop cannot.
        XCTAssertEqual(graph.nodes(at: .adult).count, 213)
        for node in graph.nodes(at: .adult) {
            XCTAssertFalse(graph.parents(of: node.id).isEmpty,
                           "\(node.id) has no in-edge, and every Champion should by now")
        }
    }

    /// The five in range that this story deliberately did NOT wire onward, named rather than
    /// counted. They are leaves, not orphans, and every one of them is on the dead-end ledger; if a
    /// later story wires one, it belongs there and here, not silently in one place.
    func testTheAdultsUToZThisStoryLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("U"..."Z").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        // Waspmon left this list in US-157, which gave it Cannonbeemon.
        XCTAssertEqual(leaves, ["witchmon", "wizarmon_x", "xv-mon", "yanmamon"],
                       "the U-Z leaves have moved without the ledger moving with them")

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

    /// Every fallback is a junk Perfect that already existed on the Champion's own line — the three
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
                           "\(junk) is this story's own Perfect, so it is not an old floor")
        }
    }

    /// **The three Perfects this story opened, and the two occasions it did not have to.** Each was
    /// authored for exactly one Champion, so a second parent hung on one later fails this rather
    /// than passing quietly — the `Set(graph.parents(of:))` equality shape US-151, US-152, US-154
    /// and US-155 established. The obvious second parent of each is deliberately NOT drawn and is
    /// named in the node's comment: Gammamon for Canoweissmon (it is full and could not carry it in
    /// any case), Galgomon for BlackRapidmon, and for Huankunmon the whole `penc-sw` reading.
    func testTheThreePerfectsThisStoryOpenedEachServeExactlyOneOfItsChampions() throws {
        for (perfect, parents, line) in authoredPerfects {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertEqual(node.line, line, "\(perfect) is not on its Champion's line")
            XCTAssertTrue(node.evolutions.isEmpty,
                          "\(perfect) leads somewhere, so the dead-end ledger has to move too")
            XCTAssertEqual(Set(graph.parents(of: perfect).map(\.id)), parents,
                           "\(perfect)'s parents changed without this claim changing with them")
        }

        XCTAssertTrue(try XCTUnwrap(graph.node(id: "galgomon")).evolutions.isEmpty,
                      "Galgomon was wired onward — say which arrow, and move the ledger")

        // And the two that cost nothing: both landed on AeroV-dramon, which had two parents before
        // this story and now has four.
        XCTAssertEqual(Set(graph.parents(of: "aerov-dramon").map(\.id)),
                       ["v-dramon", "redv-dramon", "v-dramon_black", "xv-mon_black"],
                       "AeroV-dramon's parents moved without this claim moving with them")
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

    /// **FOUR more Rookies are now FULL, and this is where that is written down.**
    /// `EvolutionEngine` picks on the dominant energy first, so two branches out of one node sharing
    /// an energy would make the second dead data — four energy types is a hard ceiling on earned
    /// branches. `pencwg_piyomon`, Mushmon, the `dmc-v4` Piyomon and Gammamon each spent their last
    /// energy here, one more than US-155's three, and every Rookie this story used except Renamon is
    /// now closed for good. No later sweep can hang a fifth branch on any of the four: it must find
    /// another parent.
    func testTheThreeRookiesThisStoryFilledHaveAnEnergyForEveryEarnedBranch() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }

        for id in ["pencwg_piyomon", "mushmon", "piyomon", "gammamon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(Set(node.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                           Set(EnergyType.allCases), "\(id) has an energy left after all")
            XCTAssertEqual(node.evolutions.count, 5,
                           "five is the ceiling `EvolutionCriteriaTests` sets")
        }

        // Renamon is the one this story left room on, said out loud so the Perfect sweeps price a
        // branch off this list rather than discovering the ceiling as a failure. So is Gabumon,
        // which this story was told to spend and did not have to.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "renamon"))
                        .evolutions.filter { !$0.isDefault }.count, 2)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "pencvb_gabumon"))
                        .evolutions.filter { !$0.isDefault }.count, 2)
    }

    /// **The handover this story was given three times over WAS WRONG, and this is the correction.**
    /// US-153 recorded that Gammamon was full and that WezenGammamon would have to take a Gabumon
    /// stand-in on the same line; US-154 and US-155 both passed that on as advice. It was one branch
    /// short. Gammamon carried BetelGammamon on spirit, GulusGammamon on strength and KausGammamon
    /// on stamina, and its junk edge to Turuiemon shares spirit with the first — so the count of
    /// DISTINCT energies on the node read as four while the count of EARNED branches was three, and
    /// VITALITY was free the whole time. So the bolded Wikimon arrow is drawn after all, and
    /// Gabumon keeps the energy it was going to spend. Both halves are pinned: Gammamon is full NOW
    /// and it is this edge that filled it, and Gabumon is untouched.
    func testWezenGammamonTookItsBoldedParentBecauseGammamonHadVitalityFree() throws {
        let gammamon = try XCTUnwrap(graph.node(id: "gammamon"))
        let edge = try XCTUnwrap(gammamon.evolutions.first { $0.to == "wezengammamon" },
                                 "the bolded arrow is not drawn")
        XCTAssertEqual(edge.requiredEnergy, .vitality, "vitality is the energy that was free")
        XCTAssertEqual(Set(gammamon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       Set(EnergyType.allCases), "Gammamon is not full even now")
        XCTAssertEqual(gammamon.evolutions.filter { !$0.isDefault }.count, 4,
                       "an earned branch went missing, so the correction no longer holds")

        // Gabumon, the stand-in this story was told to use, still has BOTH the energies it had.
        let gabumon = try XCTUnwrap(graph.node(id: "pencvb_gabumon"))
        XCTAssertFalse(gabumon.evolutions.map(\.to).contains("wezengammamon"),
                       "the stand-in was drawn as well as the bolded arrow — draw one or the other")
        XCTAssertEqual(Set(gabumon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       [.strength, .spirit], "Gabumon spent an energy it was left")

        // And the branches Gammamon already had are untouched by the new one.
        let gulus = try XCTUnwrap(gammamon.evolutions.first { $0.to == "gulusgammamon" })
        var strength = EnergyTotals()
        strength[.strength] = gulus.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: gammamon, stageEnergy: strength, dominant: .strength,
                                            careMistakes: 0, battleWins: 40,
                                            conditions: context(for: gulus)),
            "gulusgammamon", "the new branch displaced one Gammamon already had")
    }

    /// **Both Black V-dramon reach the same Perfect, on different energies, and that is the point.**
    /// Bo-1113 draws AeroV-dramon out of V-dramon (Black) with or without XV-mon (Black), so one
    /// card names both arrows; they are the only pair in six Adult sweeps to share a target this
    /// way. Different energies is what keeps them from being the same branch twice: the black
    /// V-dramon takes Piyomon's last spirit, the black XV-mon takes Mushmon's last stamina.
    func testBothBlackVDramonReachAeroVDramonOnDifferentEnergies() throws {
        let energies = try ["v-dramon_black", "xv-mon_black"].map { id -> EnergyType in
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.line, "penc-wg", "\(id) is not on the base V-dramon's line")
            return try XCTUnwrap(
                XCTUnwrap(node.evolutions.first { $0.to == "aerov-dramon" }).requiredEnergy)
        }
        XCTAssertEqual(Set(energies).count, 2, "the two Black V-dramon share an energy")
        XCTAssertEqual(energies, [.spirit, .stamina])

        // The base V-dramon is on this line and is why the variant is: the criteria's own rule that
        // a variant hangs off its base form's line. The base XV-mon is NOT, which is the exception
        // and is argued in the node comment — `adventure02` has no Perfect rung at all.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "v-dramon")).line, "penc-wg")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "xv-mon")).line, "adventure02")
        XCTAssertEqual(graph.nodes.filter { $0.line == "adventure02" && $0.stage == .perfect }, [],
                       "`adventure02` has a Perfect rung now, so XV-mon Black wants re-arguing")
    }

    /// **Youkomon's canonical thread cannot be drawn, and the check is that it still cannot.** Doumon
    /// and Taomon are both bolded in its Wikimon `Evolves To` and both are idle-only in this pack, so
    /// `edgeToDexOnlyNode` forbids either edge; BlackRapidmon is the cited alternative that could be
    /// drawn. The day one of the two gains an animated sheet this test says so, and Youkomon's
    /// out-edge is worth revisiting.
    func testYoukomonsTwoBoldedPerfectsAreStillIdleOnly() throws {
        for id in ["doumon", "taomon"] {
            XCTAssertEqual(roster.entry(id: id)?.dexOnly, true,
                           "\(id) is animated now — Youkomon's canonical arrow is drawable")
            XCTAssertNil(graph.node(id: id), "\(id) is a node, which an idle-only Digimon may not be")
        }

        // And the two cited Perfects that DO have nodes are on lines no cited parent reaches, which
        // is what made a new node necessary rather than merely convenient.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "atlurkabuterimon_blue")).line, "penc-nsp")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "deathmeramon")).line, "penc-nso")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "renamon")).line, "tamers")
    }

    /// **Xiquemon's rejected reading, pinned in both halves so the story that opens `penc-sw`'s
    /// Perfect rung is TOLD rather than having to notice.** Fujamon and Kamemon are cited to
    /// *Pendulum COLOR 6 Saiyu Warriors*, which is the line `penc-sw` — the better theme by far,
    /// since Huankunmon is that same device's Perfect. It lost on cost, exactly as US-153's
    /// Kinkakumon did: `penc-sw` has no Perfect rung at all, so that reading is three nodes and a
    /// new `junkIds` entry against this one's two.
    ///
    /// **US-157 OPENED THAT RUNG**, so the half of this claim that said it was still shut is
    /// flipped rather than deleted: Cho-Hakkaimon and the junk floor Pandamon are on `penc-sw` now,
    /// which is two of the three nodes this test priced. Xiquemon and Huankunmon are STILL on
    /// `dmc-v4` and are still the first rehome candidates; moving them was deliberately left out of
    /// US-157's scope, because a rehome drags a Champion, its Perfect, its Rookie's energy budget
    /// and four device-tree tests with it.
    func testThePencSwReadingOfXiquemonIsStillTheCheaperOneNotTaken() throws {
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .perfect }
                        .map(\.id).sorted(),
                       ["chohakkaimon", "gokuwmon", "pandamon"],
                       "`penc-sw`'s Perfect rung has moved since US-158 added Gokuwmon to it")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "fujamon")).line, "penc-sw",
                       "the cited Rookie of the rejected reading has moved line")
        XCTAssertEqual(roster.entry(id: "kamemon")?.dexOnly, true,
                       "Kamemon is animated now — the second `penc-sw` parent became usable")
        XCTAssertEqual(roster.entry(id: "falcomon_2006")?.dexOnly, true)

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "xiquemon")).line, "dmc-v4")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "huankunmon")).line, "dmc-v4")
        XCTAssertTrue(try authoredComment(on: "xiquemon").contains("penc-sw"),
                      "the rejected reading is not written into the data file")
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
    /// gate open and an EMPTY context, which is what "the owner did nothing" actually looks like —
    /// the entry point US-155 established is the right one for a neglect assertion, because
    /// `evolutionTarget` matches on the dominant energy and a neglected Digimon has none.
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
    /// merely hard. Restated over this story's ten new edges because it is cheap and because the
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

    /// No new lines for eight new nodes: two onto `penc-wg`, two onto `penc-vb`, two onto `dmc-v4`
    /// and two onto `tamers`. A sweep must not produce dozens of one-node lines, and the way this
    /// one satisfies that is by opening none at all — four lines, four threads, every node hung
    /// between two that were already there or directly above one that was.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["penc-wg"], 39, "V-dramon Black and XV-mon Black, plus US-158's two")
        XCTAssertEqual(sizes["penc-vb"], 54, "WezenGammamon and Canoweissmon, plus US-157's four, plus US-158's Entmon")
        XCTAssertEqual(sizes["dmc-v4"], 29, "Xiquemon and Huankunmon")
        XCTAssertEqual(sizes["tamers"], 99, "Youkomon and BlackRapidmon, plus US-157's eight, plus US-158's four, plus US-159's five")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.adult)?.line }).count, 4)
    }

    /// **Both variants in this story landed on a line that already held the family, not on a line of
    /// their own — which is the criteria's variant rule, and it was reached two different ways.**
    /// V-dramon Black followed its BASE FORM: no source draws Piyomon into it, and the line argument
    /// is said as a line argument in its comment rather than dressed as a citation. XV-mon Black
    /// followed its CITED ROOKIE instead — Mushmon, St-768 — and away from the base XV-mon, which is
    /// US-155's Tyranomon X reading a second time. Both endings are the same line, for once.
    func testTheTwoVariantsLandedOnPencWgByTwoDifferentArguments() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "v-dramon_black")).line,
                       try XCTUnwrap(graph.node(id: "v-dramon")).line,
                       "the Black V-dramon is not on its base form's line")
        XCTAssertEqual(graph.parents(of: "v-dramon_black").map(\.id), ["pencwg_piyomon"])
        XCTAssertEqual(Set(graph.parents(of: "v-dramon").map(\.id)), ["pencwg_piyomon"],
                       "the base form moved parent, so the variant's placement wants re-arguing")

        XCTAssertEqual(graph.parents(of: "xv-mon_black").map(\.id), ["mushmon"])
        XCTAssertNotEqual(try XCTUnwrap(graph.node(id: "xv-mon_black")).line,
                          try XCTUnwrap(graph.node(id: "xv-mon")).line,
                          "the two XV-mon are on one line now — then say so in the comment")

        XCTAssertEqual(swept.map(\.adult).filter { $0.hasSuffix("_black") }.sorted(),
                       ["v-dramon_black", "xv-mon_black"],
                       "a variant appeared that this claim does not account for")
    }

    /// **The pairing that made two of the five free, restated as a check on the DATA rather than on
    /// the prose.** For both, the Rookie below and the Perfect above were on the chosen line BEFORE
    /// this story — which is exactly what "the intersection was non-empty" means, and the property a
    /// later reader can re-derive.
    func testTheTwoFreePlacementsPutTheRookieAndThePerfectOnOneLine() throws {
        for (adult, parent, perfect) in swept
        where !authoredPerfects.map(\.perfect).contains(perfect) {
            let line = try XCTUnwrap(graph.node(id: adult)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line,
                           "\(parent) is not on \(adult)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: perfect)).line, line,
                           "\(perfect) is not on \(adult)'s line")
            XCTAssertGreaterThan(graph.parents(of: perfect).count, 2,
                                 "\(perfect) had no parent before this story, so it was not free")
        }

        // And the three where the intersection really was empty: every Perfect those pages name is
        // on a line the Champion's cited Rookie cannot reach, has no sheet, or is idle-only. Spot
        // checked on the cheapest-looking alternative for each, so the day one becomes usable the
        // story is told to revisit rather than left to rot.
        XCTAssertNil(graph.node(id: "regulusmon"), "WezenGammamon had a cheaper arrow after all")
        XCTAssertNil(graph.node(id: "sagomon"), "Xiquemon had a cheaper arrow after all")

        // LadyDevimon is the one of the three that a later story DID author, and the claim flips
        // rather than dies: US-159 wired it on this same `tamers` line — but off Kyubimon, which
        // was a LEAF, not off the Youkomon this story had to hand BlackRapidmon. So Youkomon's
        // arrow really was the expensive one, and the cheap one was a rung down all along.
        XCTAssertEqual(graph.parents(of: "ladydevimon").map(\.id), ["kyubimon"],
                       "LadyDevimon moved — say which Champion has it now")
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "youkomon")).evolutions.map(\.to)
            .contains("ladydevimon"),
                       "Youkomon took LadyDevimon after all — then this claim wants rewriting")
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to the three new Perfects as well as the five
    /// Champions.
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

        // The rejected readings are written down too, so the story that revisits one is told which
        // arrow was considered and why it lost, rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "v-dramon_black").contains("Guilmon"),
                      "V-dramon Black's rejected `tamers` reading is not named")
        XCTAssertTrue(try authoredComment(on: "wezengammamon").contains("Metal Greymon"),
                      "WezenGammamon's rejected Metal Greymon arrow is not named")
        XCTAssertTrue(try authoredComment(on: "youkomon").contains("Doumon"),
                      "Youkomon's undrawable canonical Perfects are not named")

        // And the one in-edge in this story that rests on a LINE argument rather than a citation
        // says so out loud, which is the US-151 Burgamon rule.
        XCTAssertTrue(try authoredComment(on: "v-dramon_black").contains("LINE argument"),
                      "V-dramon Black's in-edge is dressed as a citation it does not have")
    }

    /// **The handover to US-157, in the shape US-151 through US-155 established: a claim, not a
    /// note.** The Adult rung is finished, so what the Perfect sweeps inherit is the rung above:
    /// three brand-new leaves of this story's own, seven lines that STILL have no Perfect rung, and
    /// the dead-end ledger at 105. Pinned so that the first Perfect sweep is told the shape of its
    /// job rather than having to count it.
    func testWhatTheAdultRungHandsToThePerfectSweeps() throws {
        for id in authoredPerfects.map(\.perfect) {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) leads somewhere — then US-157 onward should say so here")
        }

        // US-157 took `penc-sw` off this list — Cho-Hakkaimon opened it — so six lines are left
        // for the sweeps after it, and Cargodramon's node comment nominates `commandramon` as the
        // next one worth opening.
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["xros", "vital", "adventure02", "algomon", "commandramon", "diablomon"],
                       "a line gained or lost its Perfect rung; the sweeps' bill has changed")
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// FIVE Champions plus THREE Perfects, counted with Appendix B of the PRD over a regenerated
    /// `roster.generated.json`: 294 before, 286 after; the Adult bucket falls 5 -> 0 and the Perfect
    /// bucket 107 -> 104, because all three Perfects this story opened were orphans too. Asserted
    /// rather than only noted, because the count is the one claim in `notes` a later reader cannot
    /// re-derive from the diff.
    func testTheEightOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 5)
        XCTAssertEqual(authoredPerfects.count, 3)

        for id in swept.map(\.adult) + authoredPerfects.map(\.perfect) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 709, "635 before this story, 643 after it, 693 after US-158, 709 after US-159")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// Appendix B's "connected" set: everything with an out-edge, plus everything anybody points at.
    private var connectedIds: Set<String> {
        Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
            .union(graph.nodes.flatMap { $0.evolutions.map(\.to) })
    }

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because two of this story's edges ask for FEW sleep disturbances or
    /// FEW overfeeds and a blanket "did everything right" context is the one thing that cannot take
    /// an `atMost`.
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
    /// helper US-144 through US-155 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
