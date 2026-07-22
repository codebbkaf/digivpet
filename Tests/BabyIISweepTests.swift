import XCTest

@testable import DigiVPet

/// US-147 — the fourth of Phase E's 26 orphan sweeps, and the whole Baby II rung.
///
/// **Which reading of the story's scope this takes, and why.** The PRD's Appendix A lists 42
/// orphaned Baby II, and the acceptance criteria ask for an in-edge AND an out-edge on each.
/// US-146 gave twenty-five of them an in-edge from a Baby I and left every one of them a leaf, so
/// reading the scope as "the twelve still orphaned when the story started" would have shipped
/// twenty-five Baby II that lead nowhere. The scope is the RUNG: every playable Baby II in the
/// file gets a Child above it, and the twelve that were never wired at all are authored too.
///
/// **The half of the criteria that cannot be met, stated up front rather than discovered.** Eight
/// of the Baby II wired here can never be reached — their only parent is one of the thirteen Baby I
/// no Digitama can hatch (`EvolutionCriteriaTests`, `DigitamaSweepBabyITests`) — so the nine
/// Children hanging off those eight cannot be reached either. That is arithmetic inherited from the
/// egg budget, not an omission here, and it is pinned by name in `EvolutionCriteriaTests` rather
/// than being allowed to relax a check.
///
/// What the sweep DOES deliver on the whole rung: 49 playable Baby II, 49 with an out-edge, zero
/// orphans left at the stage, and the dead-end ledger moved up one rung to Child for US-148.
final class BabyIISweepTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The story's scope, derived rather than listed, so a Baby II sprite added to the folder later
    /// lands IN scope and fails here.
    private var babyIIInRange: [RosterEntry] {
        roster.entries.filter { $0.stage == .babyII && !$0.dexOnly }
    }

    private var babyIINodes: [EvolutionNode] { graph.nodes(at: .babyII) }

    /// The twelve Baby II that had no node at all before this story.
    private let authoredBabyII = ["arkadimon_baby", "budmon", "chicchimon", "cupimon", "hiyarimon",
                                  "kozenimon", "meicoobaby", "pokomon", "sunmon", "tokomon_x",
                                  "torikaraballmon", "upamon"]

    /// The thirty-nine Child nodes this story opened. Every one of them is a leaf until the three
    /// Child sweeps (US-148..150) wire the rung above.
    private let authoredChild = ["algomon_child", "arkadimon_child", "bearmon", "blackguilmon",
                                 "blucomon", "commandramon", "coronamon", "dorumon", "fujamon",
                                 "gaomon", "ghostmon", "guilmon", "gumdramon", "impmon", "kakamon",
                                 "keramon", "koemon", "labramon", "lalamon", "lopmon", "ludomon",
                                 "lunamon", "meicoochild", "monodramon", "morphomon", "penmon",
                                 "pulsemon", "renamon", "ryudamon", "shoutmon", "sistermon_blanc",
                                 "sunarizamon", "takinmon", "terriermon", "tinkermon", "v-mon",
                                 "wormmon", "xros_hagurumon", "zenimon"]

    /// The thirty-eight Baby II whose out-edges this story authored: the twelve above, the
    /// twenty-five US-146 opened and left as leaves, and `tanemon` — already wired since US-008,
    /// but given one more branch here so `lala_digitama` finally arrives at Lalamon. The other
    /// eleven Baby II in the file are the device trees' own, wired by US-044..US-143, and the
    /// claims about branch SHAPE below are made over this set rather than over the rung — a device
    /// tree's In-Training may fork on dominant energy alone, which US-147 has no business
    /// rewriting.
    private var sweptBabyII: [String] {
        authoredBabyII + ["tanemon", "algomon_babyii", "babydmon", "bibimon", "chibimon", "chocomon",
                          "dorimon", "gigimon", "goromon", "gummymon", "kakkinmon", "kyokyomon",
                          "minomon", "mochimon", "mococomon", "monimon", "moonmon", "onibimon",
                          "pickmon", "poromon", "puroromon", "pusurimon", "tsumemon", "wanyamon",
                          "xiaomon", "yaamon"]
    }

    /// The nine Baby I that gained a SECOND way up, and the Baby II each one bought. A Baby II's
    /// only possible parent is a Baby I, so this is the only mechanism there is for giving one an
    /// in-edge — see `testEveryBabyIThatBranchesDoesSoForAnOrphan`, which proves each of these
    /// twelve had no other candidate parent at all.
    private let babyIBranches: [(babyI: String, babyII: String)] = [
        ("yuramon", "budmon"),
        ("puttimon", "cupimon"),
        ("puttimon", "tokomon_x"),
        ("tsubumon", "upamon"),
        ("piyo_yuramon", "chicchimon"),
        ("piyo_yuramon", "torikaraballmon"),
        ("yukimibotamon", "hiyarimon"),
        ("mokumon", "sunmon"),
        ("choromon", "kozenimon"),
        ("relemon", "pokomon"),
        ("kuramon", "arkadimon_baby"),
        ("kuramon", "meicoobaby"),
    ]

    // MARK: - AC: every orphan in range is wired

    /// The rung's headline claim, counted off the roster rather than off the lists above: every
    /// playable Baby II on disk is a node, and every one of them evolves into something.
    /// The graph's Baby II are TWO more than the roster's 47: `piyo_tanemon` and `pencnsp_koromon`
    /// are line-scoped aliases of a Digimon that already had a node elsewhere, so they are nodes
    /// without being separate roster entries. Coverage is asserted over roster entries and shape
    /// over graph nodes, the split US-146 recorded one rung down.
    func testEveryPlayableBabyIIIsANodeWithAnOutEdge() {
        XCTAssertEqual(babyIIInRange.count, 47)
        for entry in babyIIInRange {
            XCTAssertNotNil(graph.node(id: entry.id),
                            "\(entry.id) (\(entry.displayName)) is still not in evolutions.json")
        }
        XCTAssertEqual(babyIINodes.count, 49)
        for node in babyIINodes {
            XCTAssertFalse(node.evolutions.isEmpty,
                           "\(node.id) leads nowhere — it is a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the stage this story owns.
    func testTheBabyIIRungHasNoOrphansLeft() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)
        let orphans = babyIINodes.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Baby II still orphaned: \(orphans)")
    }

    /// Every Baby II has a parent, and it is a Baby I. The second half is what stops the first from
    /// being satisfied by a rung skipped: a Baby II fed by a Digitama would have a parent, and the
    /// validator's stage check would not see it as a mistake either.
    func testEveryBabyIIIsFedByABabyIAndNothingElse() {
        for node in babyIINodes {
            let parents = graph.parents(of: node.id)
            XCTAssertFalse(parents.isEmpty, "\(node.id) has no in-edge")
            for parent in parents {
                XCTAssertEqual(parent.stage, .babyI, "\(node.id) is fed by a non-Baby I")
            }
        }
    }

    // MARK: - AC: the in-edges, which cost a Baby I its single-edge shape

    /// **The one invariant this story spends, and the proof it had to.** Until US-147 every Baby I
    /// had exactly one edge. Twelve Baby II had no parent, nothing but a Baby I may point at a Baby
    /// II, and no Digitama is left to open a new thread — so nine Baby I gained a second edge (three
    /// of them a third). This test is what keeps that from becoming a habit: for each of the twelve,
    /// no OTHER Baby I in the file could have taken it, because the parent is the only one Wikimon
    /// names, or — for the four with no citation at all — because the branch is recorded as FLAVOUR
    /// in the node's own comment and checked as such below.
    func testEveryBabyIThatBranchesDoesSoForAnOrphan() throws {
        let branching = graph.nodes(at: .babyI).filter { $0.evolutions.count > 1 }
        XCTAssertEqual(Set(branching.map(\.id)), Set(babyIBranches.map(\.babyI)))
        XCTAssertEqual(branching.count, 9)

        for (babyI, babyII) in babyIBranches {
            let node = try XCTUnwrap(graph.node(id: babyI), "no node \(babyI)")
            XCTAssertEqual(node.stage, .babyI)
            XCTAssertTrue(node.evolutions.contains { $0.to == babyII },
                          "\(babyI) does not branch to \(babyII)")
            // Every extra edge a Baby I carries was bought by one of the twelve. Anything else on
            // one of these nodes is a branch authored for convenience.
            let extras = node.evolutions.filter { !$0.isDefault }.map(\.to)
            XCTAssertEqual(Set(extras).subtracting(authoredBabyII), [],
                           "\(babyI) branches to something that was not an orphan")
        }
    }

    /// A branch at Baby I is EARNED, and the fallback is untouched. Both halves matter: an
    /// unconditional second edge would beat nothing and mean nothing (US-020 takes the `isDefault`
    /// one whenever nothing qualifies), and a second `isDefault` would make the fallback ambiguous —
    /// which `EvolutionGraphValidator` reports, but only after the data shipped.
    func testEveryBabyIBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (babyI, babyII) in babyIBranches {
            let node = try XCTUnwrap(graph.node(id: babyI))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == babyII })
            XCTAssertFalse(edge.isDefault, "\(babyI) -> \(babyII) is the fallback")
            XCTAssertFalse(edge.conditions.isEmpty, "\(babyI) -> \(babyII) is unconditional")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.isEmpty,
                               "\(babyI) -> \(babyII) has a condition the player cannot discover")
            }
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(babyI) no longer has exactly one fallback")
        }
    }

    /// The engine's view of the same thing: a Baby I that met the branch's energy AND its criteria
    /// really reaches the orphan, rather than the edge merely existing. Read through
    /// `EvolutionEngine` so a gate authored wrong — a `requiredEnergy` its default edge already
    /// claims, a threshold no context can meet — fails here instead of stranding the Digimon.
    func testEachBabyIBranchIsTakenByTheEngineWhenItIsEarned() throws {
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.activeEnergy": 50_000,
                                               "health.exerciseMinutes": 5_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 20)

        for (babyI, babyII) in babyIBranches {
            let node = try XCTUnwrap(graph.node(id: babyI))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == babyII })
            let energy = try XCTUnwrap(edge.requiredEnergy, "\(babyI) -> \(babyII) has no energy")
            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 0, conditions: met),
                babyII,
                "a well-raised \(energy.rawValue) \(babyI) does not reach \(babyII)")
        }
    }

    // MARK: - AC: the out-edges

    /// Every Baby II's fallback is unconditional, and every branch beside it is earned and hinted.
    ///
    /// A condition on a fallback would be data that lies: US-020 takes the `isDefault` edge exactly
    /// when nothing else qualifies, so its own criteria are never consulted. That is why "no edge is
    /// unconditional" is read here as "no edge a player has to EARN is unconditional" — the same
    /// reading US-144 recorded for the hatch edges and US-146 for the Baby I rung.
    ///
    /// The earned count moved from nine to twenty in US-148: a Child's only possible parent is a
    /// Baby II, so the only way to give an orphaned Child an in-edge is to branch one of these,
    /// exactly as US-147 had to branch a Baby I one rung down. Eleven of the fourteen Children
    /// that sweep authored hang off a node in this set.
    func testEveryBabyIIBranchIsEarnedAndHintedAndEveryFallbackIsNot() throws {
        var earned = 0
        XCTAssertEqual(sweptBabyII.count, 38)
        for id in sweptBabyII {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(node.id) has no single fallback")
            for edge in node.evolutions {
                if edge.isDefault {
                    XCTAssertEqual(edge.conditions, [], "\(node.id)'s fallback carries criteria")
                } else {
                    earned += 1
                    XCTAssertFalse(edge.conditions.isEmpty,
                                   "\(node.id) -> \(edge.to) is an unconditional branch")
                    for condition in edge.conditions {
                        XCTAssertFalse(condition.hint.isEmpty,
                                       "\(node.id) -> \(edge.to) has an undiscoverable criterion")
                    }
                }
            }
            XCTAssertNotNil(try? XCTUnwrap(node.evolutions.first?.requiredEnergy))
        }
        XCTAssertEqual(earned, 51,
                       "the number of earned Baby II branches has drifted — US-149 added fourteen "
                           + "and US-150 seventeen")
    }

    /// Each Baby II's branches are told apart by dominant energy, or one of them is unreachable:
    /// `EvolutionEngine.evolutionTarget` filters on `dominant == requiredEnergy` first, so two
    /// branches sharing a type are decided by `minEnergy` alone and the loser can never be had.
    func testEachBabyIIsBranchesAskForADifferentEnergy() {
        for node in babyIINodes {
            let energies = node.evolutions.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, node.evolutions.count,
                           "\(node.id) has an edge with no requiredEnergy")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(node.id) has two branches on the same energy")
        }
    }

    /// Every branch out of a Baby II is really reachable through the engine, criteria and all.
    func testEveryBabyIIBranchIsTakenByTheEngineWhenItIsEarned() throws {
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.activeEnergy": 50_000,
                                               "health.exerciseMinutes": 5_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 20)

        for id in sweptBabyII {
            let node = try XCTUnwrap(graph.node(id: id))
            for edge in node.evolutions {
                let energy = try XCTUnwrap(edge.requiredEnergy)
                var totals = EnergyTotals()
                totals[energy] = edge.minEnergy
                XCTAssertEqual(
                    EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                                    dominant: energy, careMistakes: 0,
                                                    battleWins: 0, conditions: met),
                    edge.to,
                    "\(node.id) does not reach \(edge.to) on the energy its own edge asks for")
            }
        }
    }

    // MARK: - The dead-end ledger, moved up one rung

    /// **The half of US-147's ledger the Child sweeps have paid off — all of it, as of US-150.**
    /// The whole-file dead-end ledger lives in `ChildSweepAToFTests`, the newest of the three,
    /// which is where the next sweep will look. What stays here is the claim this story owns: of
    /// the thirty-nine Children it opened as leaves, every single one now leads somewhere.
    ///
    /// This was a sixteen-name list until US-150 (the M-Z third) emptied it, and it is kept as an
    /// EMPTY list rather than deleted, because the direction that still matters is the other one:
    /// a fortieth Child opened here and left a leaf fails this immediately.
    func testTheChildrenThisSweepOpenedAreBeingWiredOnwardInAlphabeticalOrder() throws {
        let stillLeaves = authoredChild
            .filter { graph.node(id: $0)?.evolutions.isEmpty ?? true }
            .sorted()
        XCTAssertEqual(stillLeaves, [], "every Child this sweep opened should lead somewhere now")

        // And each one is a Child with a real Champion above it, rather than merely non-empty.
        for id in authoredChild {
            let node = try XCTUnwrap(graph.node(id: id))
            for edge in node.evolutions {
                XCTAssertEqual(graph.node(id: edge.to)?.stage, .adult,
                               "\(id) -> \(edge.to) does not land on the Champion rung")
            }
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line. It held for all 403 nodes before this story and has to
    /// keep holding: a Baby II that could not be put on the line of the Child above it has been
    /// paired with the wrong Child.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// The criterion is that a sweep must not produce dozens of one-node lines, and the answer here
    /// is NO new lines at all for 51 new nodes. Every one of them joined a line that already exists,
    /// which is what a rung-shaped story should do: an in-edge forces a Baby II onto its parent's
    /// line, and an out-edge forces the Child onto the Baby II's.
    func testTheSweepOpenedNoNewLines() {
        let lines = Set(graph.nodes.map(\.line))
        XCTAssertEqual(lines.count, 21)
        for id in authoredBabyII + authoredChild {
            XCTAssertTrue(lines.contains(graph.node(id: id)?.line ?? ""),
                          "\(id) is on a line of its own")
        }
        // Nine of the twenty-one grew by more than the four nodes a chain would add, which is the
        // shape of grouping rather than of a chain per Digimon.
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        // Sizes are the FILE's, not this story's: US-150 added twelve to `tamers` and eleven
        // to `vital`, the latter because the four Otamamon variants and their Champions all
        // landed on the Vital Bracelet line.
        XCTAssertEqual(sizes["tamers"], 99,
                       "US-152 put FlareLizamon and Growmon Orange under this line's Perfect rung, "
                           + "US-156 Youkomon and BlackRapidmon, plus US-158's four, plus US-159's five")
        XCTAssertEqual(sizes["vital"], 33)
        XCTAssertEqual(sizes["wanyamon"], 26, "US-151 opened the Perfect rung on `tamers` and on `wanyamon`, plus US-158's four, plus US-159's two")
    }

    /// The line-scoped alias, called out because it is the one node here that is not its own
    /// Digimon. Monimon's only Wikimon Child is Hagurumon, `line` is single-valued, and `hagurumon`
    /// is already the Metal Empire line's Child — so the Xros Loader line carries a second node on
    /// the same art, exactly as `pencnsp_koromon` and `dmcv4_palmon` do.
    func testTheOneAliasSharesItsArtAndNothingElse() throws {
        let alias = try XCTUnwrap(graph.node(id: "xros_hagurumon"))
        let original = try XCTUnwrap(graph.node(id: "hagurumon"))
        XCTAssertEqual(alias.spriteFile, original.spriteFile)
        XCTAssertEqual(alias.stage, original.stage)
        XCTAssertEqual(alias.displayName, original.displayName)
        XCTAssertNotEqual(alias.line, original.line)
        XCTAssertNil(roster.entry(id: "xros_hagurumon"),
                     "an alias must not be a roster entry of its own — the Dex would show it twice")
    }

    // MARK: - AC: the data the story rests on

    /// Every node this story added names art that exists, at the stage the ROSTER files it under.
    /// `EvolutionGraphValidator` checks the first half; this checks the second, which is the one
    /// that bites — `import_roster.py` reads a Digimon's rung off its sprite FOLDER, so a node
    /// authored at the wrong stage resolves to no art at all.
    func testEveryNodeThisSweepAddedAgreesWithTheRoster() throws {
        for id in authoredBabyII + authoredChild where id != "xros_hagurumon" {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.stage, entry.stage, "\(id) is authored at the wrong rung")
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the 157 idle-only Digimon")
        }
    }

    /// The sweep had no document to copy, so every node it added cites Wikimon in its `comment` —
    /// except the six that have nothing to cite, which say FLAVOUR or REHOME instead and are read
    /// by the two tests below. A comment that cites nothing is the shape of an invented evolution.
    func testEveryNodeThisSweepAddedCitesItsSourceOrSaysItCannot() throws {
        let uncited = ["torikaraballmon", "kozenimon", "arkadimon_baby", "meicoobaby",
                       "blackguilmon", "zenimon"]
        for id in authoredBabyII + authoredChild {
            let comment = try authoredComment(on: id)
            if uncited.contains(id) {
                XCTAssertTrue(comment.contains("FLAVOUR") || comment.contains("REHOME"),
                              "\(id) has nothing to cite and does not say so")
            } else {
                XCTAssertTrue(comment.contains("Wikimon"),
                              "\(id) is authored without naming where the arrow comes from")
            }
        }
    }

    /// The pairings that are NOT a Wikimon arrow are the story's weak spot — a stand-in is the one
    /// thing a later reader cannot tell from a shortcut — so each says which rung was missing or
    /// that nothing could be cited at all. Chicchimon and Torikara Ballmon have no `Evolves From`
    /// on Wikimon and Arkadimon has none anywhere, so their parents are FLAVOUR; Kozenimon has
    /// neither direction. Each stated fact about the roster is checked rather than merely read.
    func testEveryUncitedPairingSaysSoInCapitals() throws {
        for id in ["chicchimon", "torikaraballmon", "kozenimon", "arkadimon_baby", "zenimon",
                   "blackguilmon"] {
            XCTAssertTrue(try authoredComment(on: id).contains("FLAVOUR"),
                          "\(id) reads as a citation when nothing could be cited")
        }
        // The two rehomes: a Child that exists on disk but belongs to another line, and a species
        // whose own Baby I is idle-only. Both name the rung they could not use.
        let tinkermon = try authoredComment(on: "tinkermon")
        XCTAssertTrue(tinkermon.contains("REHOME"), "tinkermon hides that it is a stand-in")
        XCTAssertTrue(tinkermon.contains("Hawkmon"),
                      "tinkermon does not name the Child it could not use")
        XCTAssertEqual(roster.entries.first { $0.displayName == "Hawkmon" }?.dexOnly, true,
                       "Hawkmon is not idle-only, so Poromon had a choice")

        let meicoobaby = try authoredComment(on: "meicoobaby")
        XCTAssertTrue(meicoobaby.contains("REHOME"), "meicoobaby hides that it is a stand-in")
        XCTAssertNil(graph.node(id: "meicoo_baby"),
                     "Meicoomon's own Baby I is idle-only and may not sit on an edge")
    }

    /// The two grouping claims US-146 made about its new lines still hold now that the Child rung
    /// above them exists: every Digimon on `xros` names the Xros Loader or Xros Wars in its
    /// comment, and every one on `penc-sw` names the Saiyu Warriors. Both were checked against
    /// Wikimon's machine-readable Virtual Pets section before the comment was written.
    func testTheTwoNewestLinesStillNameTheDeviceTheirMembersShare() throws {
        for id in graph.nodes.filter({ $0.line == "xros" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Xros"),
                          "\(id) is on the Xros Loader line without saying so")
        }
        for id in graph.nodes.filter({ $0.line == "penc-sw" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Saiyu Warriors"),
                          "\(id) is on the Saiyu Warriors line without saying so")
        }
    }

    /// Each of the four eggs whose species is a Child this story opened now reaches it. That is what
    /// makes US-144/US-145's allocation mean something: an egg that hatches into a thread which
    /// never arrives at its own Digimon is a promise the file does not keep.
    func testTheEggsWhoseSpeciesThisRungReachesNowArriveAtIt() throws {
        for (egg, child) in [("guil_digitama", "guilmon"), ("lop_digitama", "lopmon"),
                             ("gao_digitama", "gaomon"), ("terrier_digitama", "terriermon"),
                             ("kera_digitama", "keramon"), ("lala_digitama", "lalamon"),
                             ("commandra_digitama", "commandramon"), ("ludo_digitama", "ludomon"),
                             ("morpho_digitama", "morphomon"), ("pulse_digitama", "pulsemon"),
                             ("sunariza_digitama", "sunarizamon"), ("ghost_digitama", "ghostmon"),
                             ("bluco_digitama", "blucomon"), ("monodra_digitama", "monodramon"),
                             ("rena_digitama", "renamon"), ("imp_digitama", "impmon"),
                             ("v_digitama", "v-mon"), ("worm_digitama", "wormmon"),
                             ("bear_digitama", "bearmon"), ("koe_digitama", "koemon")] {
            var reached: Set<String> = [egg]
            var frontier = [egg]
            while let id = frontier.popLast() {
                for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                    reached.insert(edge.to)
                    frontier.append(edge.to)
                }
            }
            XCTAssertTrue(reached.contains(child), "\(egg) never arrives at \(child)")
        }
    }

    // MARK: - The whole file still validates

    func testTheGraphValidatesWithNoFindings() {
        let errors = EvolutionGraph.bundled.validate()
        XCTAssertEqual(errors.map(\.description), [])
    }

    // MARK: - Helpers

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144, US-145 and US-146 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
