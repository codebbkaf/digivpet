import XCTest

@testable import DigiVPet

/// US-158 — the fifteenth of Phase E's orphan sweeps and the second at the Perfect rung: the
/// fifteen playable Perfect whose display name begins D-G that no device tree and no Champion
/// sweep reached.
///
/// **Fifteen orphans, FOURTEEN nodes.** The fifteenth, Ex-Tyranomon, was already drawn on `dmc-v5`
/// under the hyphen-less id `extyranomon` — the roster's `ex-tyranomon` with the hyphen dropped,
/// which `DMCVersion5TreeTests` has recorded as spelling drift since US-137. Appendix B counts the
/// SHEET id, and nothing pointed at it, so it read as an orphan while its art was on screen. The
/// fix is a rename, not a node: it clears the orphan, retires the drift, and takes `extyranomon`
/// off `RosterTests`' alias list, where it never belonged.
///
/// **US-152's intersection closed on seven of the fourteen** — Delumon, Duramon, Entmon, Fantomon,
/// Garudamon X, Gigadramon and Gusokumon each landed between a Champion and an Ultimate that were
/// both already on the chosen line. The other seven cost one Ultimate apiece.
///
/// **The rung it closes: `wanyamon` had Perfects and no Mega, and was the last line in the file
/// that did.** US-157 handed it on by name. Gogmamon and Grappleomon went over its last two leaf
/// Champions, Ancient Volcamon and Dinotigermon over them, and all four `wanyamon` Digitama were
/// promoted to legal starting eggs in one edit. Every line in the file that has a Perfect rung now
/// has an Ultimate rung too.
///
/// **And it moves the dead-end ledger down without adding anything back**, which US-157 could not:
/// seven of the fourteen in-edges came off a leaf Champion, and every one of the seven falls to a
/// junk Perfect that already existed. 97 -> 90.
final class PerfectSweepDToGTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The fourteen orphaned Perfects this story wired, with the Champion that now reaches each and
    /// the Ultimate each now climbs into. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("darkknightmon", "tailmon", "darkknightmon_x"),
        ("darksuperstarmon", "starmon", "titamon"),
        ("delumon", "kiwimon", "griffomon"),
        ("doruguremon", "dorugamon", "dorugoramon"),
        ("duramon", "raptordramon", "pencme_wargreymon"),
        ("entmon", "cockatrimon", "cherubimon_virtue"),
        ("fantomon", "wizarmon", "piemon"),
        ("flaremon", "firamon", "apollomon"),
        ("garudamon_x", "pencwg_birdramon", "hououmon"),
        ("gigadramon", "devidramon", "mugendramon"),
        ("gogmamon", "gaogamon", "ancientvolcamon"),
        ("gokuwmon", "ginkakumon", "seitengokuwmon"),
        ("grappleomon", "gryzmon", "dinotigermon"),
        ("gusokumon", "ebidramon", "plesiomon"),
    ]

    /// The seven Ultimates this story authored, and the line each landed on. All seven are leaves,
    /// as every Ultimate in this file is; none is on the dead-end ledger, which stops below the top
    /// rung.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        ("darkknightmon_x", ["darkknightmon"], "penc-nsp"),
        ("titamon", ["darksuperstarmon"], "tamers"),
        ("dorugoramon", ["doruguremon"], "tamers"),
        ("apollomon", ["flaremon"], "penc-nso"),
        // US-160 hung MachGaogamon under this one — Gaogamon's bolded Perfect, and a cited climb
        // on its page. Named rather than the check being loosened to a superset.
        ("ancientvolcamon", ["gogmamon", "machgaogamon"], "wanyamon"),
        ("dinotigermon", ["grappleomon"], "wanyamon"),
        // US-162 hung Xingtianmon under this one — a cited climb on that page, over the same
        // Ginkakumon Gokuwmon hangs off. Named rather than the check being loosened.
        ("seitengokuwmon", ["gokuwmon", "xingtianmon"], "penc-sw"),
    ]

    /// The seven Champions that were LEAVES before this story, and the junk Perfect each now falls
    /// to. **Every one of the seven floors already existed**, which is what makes this sweep the
    /// first at this rung to move the dead-end ledger down without adding a node back to it:
    /// US-157 had to author Pandamon for `penc-sw` before Hakubamon could branch at all.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("starmon", "catchmamemon"),
        ("dorugamon", "catchmamemon"),
        ("cockatrimon", "andiramon_virus"),
        ("firamon", "darumamon"),
        ("gaogamon", "karakurumon"),
        ("ginkakumon", "pandamon"),
        ("gryzmon", "karakurumon"),
    ]

    /// The shared "did everything right" context, US-151's through US-157's exactly.
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

    // MARK: - AC1/AC2: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so a Perfect sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayablePerfectDToGIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && ("D"..."G").contains(String($0.displayName.prefix(1)).uppercased())
        }
        // Twenty-six, not the twenty-seven Appendix B's script reports: that script reads
        // `roster.generated.json`, which mirrors `evolutions.json` and so carries the line-scoped
        // ALIASES too — `pencwg_gerbemon` is the only one in this band. `Roster.bundled` reads
        // `Resources/roster.json`, which is one entry per SHEET on disk, and that is the right
        // denominator for "every Digimon on disk is obtainable".
        XCTAssertEqual(inRange.count, 26)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The fourteen this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoPerfectDToGIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("D"..."G").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects D-G still orphaned: \(orphans)")
    }

    /// The Perfects in range this story deliberately did NOT wire onward, named rather than counted.
    /// Grademon is the only one and it is US-154's — it has an in-edge, so it was never an orphan,
    /// and it sits on the dead-end ledger in `ChildSweepAToFTests` waiting for an Ultimate sweep.
    func testTheOnePerfectDToGLeftAsALeafIsTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("D"..."G").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        // US-163 IS THAT ULTIMATE SWEEP, and it took the bolded arrow this story left waiting:
        // Grademon climbs to Alphamon, so the D-G band now has no Perfect leaf at all. The list is
        // kept as an empty one rather than deleted, because the other direction still matters — a
        // D-G Perfect left as a leaf by a later story lands here.
        XCTAssertEqual(leaves, [],
                       "the D-G Perfect leaves have moved without the ledger moving with them")
        XCTAssertFalse(graph.parents(of: "grademon").isEmpty,
                       "Grademon is an orphan rather than a leaf, so it WAS in this story's scope")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "grademon")).evolutions.map(\.to), ["alphamon"],
                       "Grademon is a dead end again — then it belongs back on the list above")
    }

    // MARK: - The fifteenth orphan, which cost a rename rather than a node

    /// **EX-TYRANOMON WAS THE FIFTEENTH ORPHAN IN THE BAND AND WAS ALREADY ON SCREEN.** `dmc-v5`
    /// has drawn it since US-137 under `extyranomon`, the roster's id with the hyphen dropped; the
    /// two spellings meant the sheet id had no in-edge and no out-edge of its own, which is exactly
    /// what Appendix B counts. Renaming the node is the whole fix — three in-edges and the node's
    /// own id, plus its `elements.json` and `moves.json` rows — and it costs no new node at all.
    ///
    /// Pinned from both sides, because a rename is the one edit that can silently half-apply.
    func testExTyranomonCostARenameRatherThanANode() throws {
        let node = try XCTUnwrap(graph.node(id: "ex-tyranomon"))
        XCTAssertEqual(node.line, "dmc-v5", "it is still the Gazimon line's Perfect")
        XCTAssertEqual(node.stage, .perfect)
        XCTAssertNil(graph.node(id: "extyranomon"),
                     "the hyphen-less spelling is back — say why, it was retired here")

        let entry = try XCTUnwrap(roster.entry(id: "ex-tyranomon"))
        XCTAssertEqual(node.spriteFile, entry.spriteFile)
        XCTAssertEqual(node.displayName, entry.displayName)

        // The three in-edges the V5 document draws followed the id.
        XCTAssertEqual(Set(graph.parents(of: "ex-tyranomon").map(\.id)),
                       ["devidramon", "tuskmon", "deltamon"])
        XCTAssertEqual(node.evolutions.map(\.to), ["gaioumon"])

        // And nothing anywhere still points at the old spelling.
        for other in graph.nodes {
            XCTAssertFalse(other.evolutions.map(\.to).contains("extyranomon"),
                           "\(other.id) still reaches the retired spelling")
        }
        XCTAssertNotNil(ElementCatalog.bundled.types["ex-tyranomon"],
                        "the elements.json row did not follow the rename")
        XCTAssertNil(ElementCatalog.bundled.types["extyranomon"])
        XCTAssertNotNil(MoveCatalog.bundled.moves["ex-tyranomon"],
                        "the moves.json row did not follow the rename")
        XCTAssertNil(MoveCatalog.bundled.moves["extyranomon"])
    }

    // MARK: - AC2/AC4: the shape of every edge this story authored

    /// Each swept Perfect climbs by exactly one `isDefault` edge, gated on energy and on care but
    /// carrying no criteria — the shape every Perfect in this file has had since US-134, and the
    /// reading of "no edge is unconditional" that every rung below recorded. US-020 takes the
    /// `isDefault` edge exactly when nothing else qualifies, so a condition on one would be data
    /// that lies about how it is taken. What the criterion binds is the EARNED edges, and every
    /// earned edge this story authored is checked below.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        // **US-163 IS THE FIRST STORY TO FORK A PERFECT, AND THESE ARE THE ONES IT FORKED.** The
        // Ultimate sweep's in-edges come from this rung, so a Perfect that already had its climb
        // gained an EARNED branch beside it — a different `requiredEnergy`, two criteria, and the
        // climb untouched and still `isDefault`, which is the whole of what this test checks. Each
        // is NAMED with its new edge count rather than the count being loosened to a `>=`.
        // US-164, the C-D Ultimate sweep, forked three more: doruguremon gained Dynasmon X beside
        // its US-163 branch (2 -> 3), and darkknightmon and entmon each gained their first (1 -> 2).
        // US-165, the E-H sweep, forked four more of this story's Perfects: doruguremon gained
        // Examon X (3 -> 4), and flaremon, garudamon_x and gokuwmon each gained their first (1 -> 2).
        let branchedBySweeps: [String: Int] = ["doruguremon": 4, "darkknightmon": 2, "entmon": 2,
                                               "flaremon": 2, "garudamon_x": 2, "gokuwmon": 2]
        for (perfect, _, ultimate) in swept {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.evolutions.count, branchedBySweeps[perfect] ?? 1,
                           "\(perfect) is not a single climb")

            let climb = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertTrue(climb.isDefault, "\(perfect)'s climb is not its fallback")
            XCTAssertEqual(climb.to, ultimate)
            XCTAssertEqual(climb.conditions, [], "\(perfect)'s fallback carries criteria")
            XCTAssertNotNil(climb.requiredEnergy, "\(perfect) climbs on no energy at all")
            XCTAssertEqual(climb.minEnergy, 150, "the Perfect rung's gate is 150 since US-134")
            XCTAssertEqual(climb.maxCareMistakes, 2)
        }
    }

    /// The in-edges are earned, conditioned and hinted, and none of them displaces the fallback of
    /// the Champion it hangs off — the guard every sweep below this one needed.
    func testEveryNewChampionBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (perfect, parent, _) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == perfect },
                                     "\(parent) does not reach \(perfect)")
            XCTAssertFalse(edge.isDefault, "\(parent) -> \(perfect) took over the junk branch")
            XCTAssertFalse(edge.conditions.isEmpty, "\(parent) -> \(perfect) is gated on nothing")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(parent) -> \(perfect) has an undiscoverable criterion")
            }
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has a single fallback")
            XCTAssertGreaterThan(edge.minEnergy, 0,
                                 "\(parent)'s junk edge would win the branch outright")
        }
    }

    /// **SEVEN Champions came off the dead-end ledger here, and not one of them needed a new junk
    /// node.** A leaf Champion has no fallback because it has no edges at all; the moment it gains
    /// an earned branch, `EvolutionCriteriaTests` requires an `isDefault` edge onto a junk Perfect
    /// of its OWN line. US-157 had to author Pandamon to pay that on `penc-sw`; this story pays it
    /// seven times out of floors that already existed, including Pandamon itself.
    func testTheSevenLeafChampionsGainedTheirLinesExistingJunkFloor() throws {
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            // Two when this story wrote it. Gaogamon is three since US-160 gave it MachGaogamon,
            // its bolded Perfect, so what is pinned is "one fallback and at least one earned
            // branch" plus the exact count for the six nobody has branched again.
            // Gaogamon is three since US-160 gave it MachGaogamon; Firamon and Ginkakumon are
            // three since US-162 gave them SaviorHackmon and Xingtianmon. Named exceptions rather
            // than a loosened `>=`, so a FOURTH branch on any of them still fails here.
            XCTAssertEqual(node.evolutions.count,
                           ["gaogamon", "firamon", "ginkakumon"].contains(parent) ? 3 : 2,
                           "\(parent) is not one earned branch plus a fallback")
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(parent) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(parent)'s line")
            XCTAssertEqual(floor.stage, .perfect)

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.minEnergy, 0, "\(parent)'s junk edge demands energy")
            XCTAssertEqual(fallback.conditions, [], "\(parent)'s junk edge carries criteria")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)

            // The claim that makes this story cheaper than US-157: every floor pre-dated it.
            XCTAssertFalse(swept.map(\.perfect).contains(junk),
                           "\(junk) is one of this story's own nodes, so a floor WAS authored")
        }

        // The other seven hung off a Champion that was ALREADY branching, so none of them needed a
        // floor and none of them touched one.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching.count, 7)
        for parent in alreadyBranching {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3,
                                        "\(parent) was a leaf after all, so it needed a floor")
        }
    }

    /// No Champion offers two earned branches on one energy — `EvolutionEngine` picks on the
    /// dominant energy first, so a second branch sharing an energy would be dead data. Four energy
    /// types is a hard ceiling on earned branches and five edges is `EvolutionCriteriaTests`'.
    func testNoChampionThisStoryBranchedOffersTwoBranchesOnOneEnergy() throws {
        for parent in Set(swept.map(\.parent)) {
            let node = try XCTUnwrap(graph.node(id: parent))
            let earned = node.evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
            XCTAssertLessThanOrEqual(node.evolutions.count, 5,
                                     "five is the ceiling `EvolutionCriteriaTests` sets")
        }

        // Ebidramon is the ONE this story took to within a branch of the ceiling — US-139's
        // Anomalocarimon has vitality, US-157's Anomalocarimon X stamina and Gusokumon the strength
        // that was left, so only spirit remained. Said out loud, as US-157 said it of Revolmon, so
        // that a later sweep prices a branch off this rather than discovering it as a failure.
        // **US-159 SPENT THE LAST ONE**, on the bolded Ebidramon -> Hangyomon arrow, so this node
        // is now FULL at four earned branches plus the junk fall and can never branch again. The
        // claim is flipped rather than deleted, which is what makes it a handover.
        let ebidramon = try XCTUnwrap(graph.node(id: "ebidramon"))
        XCTAssertEqual(Set(ebidramon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       Set(EnergyType.allCases))
        XCTAssertEqual(ebidramon.evolutions.count, 5)
        XCTAssertTrue(ebidramon.evolutions.map(\.to).contains("hangyomon"))
    }

    /// Every edge this story authored is really reachable through the engine, criteria and all —
    /// the check that separates an authored edge from a taken one.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (perfect, parent, ultimate) in swept {
            for (from, to) in [(parent, perfect), (perfect, ultimate)] {
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

    /// And a neglected Champion falls to junk instead. Read through `scheduledEvolutionTarget` with
    /// the gate open and an EMPTY context, which is what "the owner did nothing" actually looks
    /// like — `evolutionTarget` matches on the dominant energy and a neglected Digimon has none.
    func testANeglectedChampionFallsToItsLinesJunkPerfect() throws {
        for (parent, junk) in junkFloors {
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: try XCTUnwrap(graph.node(id: parent)), stageEnergy: EnergyTotals(),
                    dominant: nil, careMistakes: 9, battleWins: 0,
                    stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                junk,
                "a neglected \(parent) does not fall to \(junk)")
        }
    }

    /// The window trap US-150 shipped into a first draft and `ChildSweepMToZTests` pinned over the
    /// whole file: `care.battleCount` and `care.battleWinRatio` are answerable only over `lifetime`
    /// and every other `care.*` counter only over `stage`, so an edge that asks the other way is
    /// UNREACHABLE rather than merely hard. Restated over this story's new edges because it is
    /// cheap and because the engine, not the validator, is the only thing that catches it.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        for id in Set(swept.map(\.perfect) + swept.map(\.parent)) {
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

    // MARK: - AC3: lines are grouped coherently

    /// No edge in the file crosses a line, still — the rule that decides every placement here. A
    /// Perfect that could not be put on the line of the Champion below it has been paired with the
    /// wrong Champion.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// No new lines for twenty-one new nodes — ten existing ones absorbed all of them. A sweep must
    /// not produce dozens of one-node lines, and the way this one satisfies that is by opening none
    /// at all.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 117, "DarkSuperstarmon, DORUguremon and their two Megas, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["wanyamon"], 29, "Gogmamon, Grappleomon and the line's first two Megas, plus US-159's two" + ", plus US-160's one, plus US-161's RizeGreymon and Ravmon")
        XCTAssertEqual(sizes["penc-nso"], 75, "Fantomon, Flaremon and Apollomon, plus US-159's four" + ", plus US-160's five, plus US-161's Orochimon, plus US-163's seven Ultimates")
        XCTAssertEqual(sizes["penc-wg"], 45, "Delumon and Garudamon X, plus US-161's Paildramon")
        XCTAssertEqual(sizes["penc-nsp"], 43, "DarkKnightmon and DarkKnightmon X" + ", plus US-160's one, plus US-161's both Panjyamon, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-sw"], 20, "Gokuwmon and SeitenGokuwmon")
        XCTAssertEqual(sizes["penc-me"], 71, "Duramon, plus US-159's two" + ", plus US-160's one, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas, plus US-163's four Ultimates")
        XCTAssertEqual(sizes["penc-vb"], 60, "Entmon, plus US-161's Regulusmon, plus US-163's two Ultimates")
        XCTAssertEqual(sizes["penc-ds"], 46, "Gusokumon, plus US-159's Hangyomon" + ", plus US-160's two, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["dmc-v5"], 26, "Gigadramon, and Ex-Tyranomon renamed rather than added" + ", plus US-160's two")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 10)
    }

    /// **Every variant in this story landed on a line that already held its family**, which is the
    /// criteria's variant rule. Garudamon X follows the plain Garudamon onto `penc-wg` and is
    /// reached by the same Birdramon; DarkKnightmon X follows the DarkKnightmon this story
    /// authored, which is the rule read from the top rather than the bottom.
    ///
    /// DarkSuperstarmon is the one whose base form has NO node yet, and that is recorded rather
    /// than glossed: Superstarmon is an orphan the S-Z sweep owns, and this story pins where it
    /// goes — over the same Starmon, on `tamers`.
    func testTheVariantsLandedBesideTheirBaseForm() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "garudamon_x")).line,
                       try XCTUnwrap(graph.node(id: "garudamon")).line)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "garudamon")).stage, .perfect)
        XCTAssertEqual(Set(graph.parents(of: "garudamon_x").map(\.id)), ["pencwg_birdramon"])
        XCTAssertTrue(graph.parents(of: "garudamon").map(\.id).contains("pencwg_birdramon"),
                      "the X is not reached by a Champion its base form is reached by")

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "darkknightmon_x")).line,
                       try XCTUnwrap(graph.node(id: "darkknightmon")).line)

        // **US-162 WIRED SUPERSTARMON AND DID NOT PUT IT ON `tamers`**, so this claim flips
        // rather than dies: Starmon, the bolded parent, is a `tamers` Adult and `tamers` holds no
        // cited climb for Superstarmon at all, so it went to Omekamon on `penc-me` with the cited
        // Prince Mamemon above it. DarkSuperstarmon therefore does NOT follow its base form's line,
        // and that is the one place in the file where the pair is split — said here so it is a
        // recorded decision rather than a drift.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "superstarmon")).line, "penc-me")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "darksuperstarmon")).line, "tamers")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "starmon")).line, "tamers")
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "starmon")).evolutions.map(\.to)
            .contains("superstarmon"),
                       "Starmon took Superstarmon after all — then the pair is together again")
    }

    /// **The seven placements that cost nothing, restated as a check on the DATA rather than on the
    /// prose.** For each, the Champion below and the Ultimate above were on the chosen line BEFORE
    /// this story — which is exactly what "US-152's intersection was non-empty" means, and the
    /// property a later reader can re-derive.
    func testTheSevenFreePlacementsPutTheChampionAndTheUltimateOnOneLine() throws {
        let free = swept.filter { !authoredUltimates.map(\.ultimate).contains($0.ultimate) }
        XCTAssertEqual(Set(free.map(\.perfect)),
                       ["delumon", "duramon", "entmon", "fantomon", "garudamon_x", "gigadramon",
                        "gusokumon"])

        for (perfect, parent, ultimate) in free {
            let line = try XCTUnwrap(graph.node(id: perfect)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line,
                           "\(parent) is not on \(perfect)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: ultimate)).line, line,
                           "\(ultimate) is not on \(perfect)'s line")
            XCTAssertGreaterThan(graph.parents(of: ultimate).count, 1,
                                 "\(ultimate) had no parent before this story, so it was not free")
        }
    }

    // MARK: - The rung this story closed

    /// **`wanyamon` WAS THE LAST LINE IN THE FILE WITH PERFECTS AND NO MEGA, AND US-157 HANDED IT
    /// ON BY NAME.** Gryzmon and Gaogamon were its last two leaf Champions, both bolded or cited
    /// parents of a D-G orphan, so the two arrows that clear its dead ends are the same two that
    /// open its top rung. The knock-on is the one worth pinning: `MainScreenModel.startingDigitamaId`
    /// filters on `reachesUltimate`, so ALL FOUR `wanyamon` Digitama went from unraisable to legal
    /// starting eggs in one edit — the whole line at once, which no earlier promotion managed.
    func testOpeningTheWanyamonUltimateRungPromotedEveryEggOnTheLine() throws {
        let ultimates = graph.nodes.filter { $0.line == "wanyamon" && $0.stage == .ultimate }
        // US-159 added Tengumon over Karatenmon, so this is a superset rather than an equality:
        // what this story owns is its two, not the rung's whole census.
        XCTAssertTrue(Set(ultimates.map(\.id)).isSuperset(of: ["ancientvolcamon", "dinotigermon"]),
                      "the `wanyamon` Ultimate rung has moved since US-158 opened it")

        let eggs = graph.nodes.filter { $0.line == "wanyamon" && $0.stage == .digitama }.map(\.id)
        XCTAssertEqual(eggs.sorted(),
                       ["bear_digitama", "gao_digitama", "koe_digitama", "lioll_digitama"])
        for id in eggs {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) no longer reaches an Ultimate — `EggHatchingTests` moves with it")
        }

        // And the file-wide claim that closes: no line has a Perfect rung with nothing over it.
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again")
    }

    /// The fifth egg this story promoted, and the ordinary kind: Monodra Digitama's DORUmon thread
    /// stopped at the leaf DORUgamon until DORUguremon and DORUgoramon went over it. Named because
    /// `PerfectSweepAToCTests` pinned it in the OTHER direction — it listed Monodra among the
    /// `tamers` eggs US-157 could not reach — and a promotion that moves a pinned list should say
    /// which arrow did it.
    func testMonodraDigitamaWasPromotedByTheDORUmonThread() throws {
        XCTAssertTrue(graph.reachesUltimate(from: "monodra_digitama"))
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "monodra_digitama")).line, "tamers")

        // The thread, rung by rung, so a break anywhere in it fails here rather than in the egg list.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "dorumon")).stage, .child)
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "dorumon")).evolutions.map(\.to)
                        .contains("dorugamon"))
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "dorugamon")).evolutions.map(\.to)
                        .contains("doruguremon"))
        // US-163 hung Alphamon: Ouryuken here as an EARNED branch, US-164 hung Dynasmon X beside it
        // and US-165 hung Examon X too — each cites DORUguremon on Wikimon and each has an
        // all-Ultimate bolded `Evolves From` — so the thread now forks three times and DORUguremon
        // spends all four energies. The rung this test is about is the `isDefault` climb, which is
        // still Dorugoramon.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "doruguremon")).evolutions.map(\.to),
                       ["alphamon_ouryuken", "dynasmon_x", "examon_x", "dorugoramon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "doruguremon")).evolutions
                        .first(where: \.isDefault)?.to, "dorugoramon")

        // The `tamers` eggs that were STILL unraisable when this story ran, so the story that
        // promotes one knows it is the one doing it. **US-159 took both `tamers` ones the same
        // middle-of-the-thread way this story took Monodra**: LadyDevimon over the leaf Kyubimon
        // carries Rena, and LadyDevimon X over the junk Numemon X carries Terrier. V Digitama is
        // on `adventure02`, which has no Perfect rung, so it is out of every Perfect sweep's reach.
        for id in ["rena_digitama", "terrier_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) stopped reaching an Ultimate — US-159's LadyDevimon pair carries it")
        }
        // **US-162 took V Digitama**, the last one, by opening `adventure02`'s Perfect rung under
        // Nise Drimogemon — the line's junk Champion, which all three of its Children fall into, so
        // one arrow promoted both eggs of that line at once.
        XCTAssertTrue(graph.reachesUltimate(from: "v_digitama"),
                      "v_digitama stopped reaching an Ultimate — US-162's Vermillimon carries it")
    }

    /// **`penc-sw` GAINED THE FIRST OF THE FOUR PERFECTS US-157 OPENED ITS RUNG FOR.** Gokuwmon is
    /// Son Goku and the Saiyu Warriors line is Journey to the West, so the placement is not in
    /// doubt — but the in-edge is, and the node says so: Wikimon's three cited parents (Hanumon,
    /// Kinkakumon, Turuiemon) are all on other lines, so the arrow rests on Ginkakumon, the twin of
    /// the Kinkakumon that US-153 and US-157 both pinned as this line's rehome candidate. Rehome
    /// Kinkakumon and the arrow becomes a citation; that is still a story of its own.
    func testGokuwmonRestsOnALineArgumentThatARehomeWouldTurnIntoACitation() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gokuwmon")).line, "penc-sw")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "ginkakumon")).line, "penc-sw")

        let comment = try authoredComment(on: "gokuwmon")
        XCTAssertTrue(comment.contains("NO CITATION"),
                      "Gokuwmon's in-edge is dressed as a citation it does not have")
        XCTAssertTrue(comment.contains("LINE argument"))
        XCTAssertTrue(comment.contains("Kinkakumon"), "the rehome that would fix it is not named")

        // Kinkakumon is STILL on `penc-ds`, which is what makes the argument a live one.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kinkakumon")).line, "penc-ds")

        // The three Saiyu Warriors Perfects still owed after this story, all taken by US-162 and
        // all onto this rung. Same claim, other side.
        for id in ["sagomon", "sanzomon", "shawujinmon"] {
            XCTAssertNotNil(roster.entry(id: id), "\(id) is on disk, which is why it was owed")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "penc-sw",
                           "\(id) left the rung US-157 opened for it")
        }

        // And the whole line is STILL stranded, which no story at this rung can fix: `penc-sw` has
        // no Digitama, and US-144/US-145 spent all 57.
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .digitama }, [])
    }

    // MARK: - AC5/AC6: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to all twenty-one new nodes.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
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

    /// AC7: every new node has a line, and a line the file already knew. A blank one would trap
    /// `EvolutionGraph.bundled` at launch through `emptyLine`; a typo'd one would silently make a
    /// nameless Dex group, which is what the count in `testTheSweepOpenedNoNewLines` catches.
    func testEveryNodeThisStoryAddedHasAKnownLine() throws {
        let known = Set(graph.nodes.map(\.line))
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
            let line = try XCTUnwrap(graph.node(id: id)).line
            XCTAssertFalse(line.isEmpty, "\(id) has no line")
            XCTAssertTrue(known.contains(line), "\(id) is on the unknown line \(line)")
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation") || comment.contains("FLAVOUR"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }

        // **The two edges in this story that rest on a LINE argument rather than a citation say so
        // out loud**, which is US-151's Burgamon rule and US-157's Anomalocarimon X one. Gokuwmon's
        // is the in-edge; Entmon's is the CLIMB, which is the first time this sweep series has had
        // to say it of an out-edge — all three of Entmon's cited climbs are undrawable in this pack.
        for id in ["gokuwmon", "entmon"] {
            XCTAssertTrue(try authoredComment(on: id).contains("LINE argument"),
                          "\(id)'s edge is dressed as a citation it does not have")
            XCTAssertTrue(try authoredComment(on: id).contains("NO CITATION"))
        }

        // And the rejected readings are written down too, so the story that revisits one is told
        // which arrow was considered and why it lost, rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "gigadramon").contains("Megadramon"),
                      "Gigadramon's rejected `dmc-v4` reading is not named")
        XCTAssertTrue(try authoredComment(on: "gogmamon").contains("Mirage Gaogamon"),
                      "Gogmamon's undrawable idle-only climb is not named")
        XCTAssertTrue(try authoredComment(on: "grappleomon").contains("Leomon"),
                      "Grappleomon's rejected `dmc-v4` reading is not named")
        XCTAssertTrue(try authoredComment(on: "duramon").contains("Zubaeagermon"),
                      "Duramon's undrawable bolded ends are not named")
        XCTAssertTrue(try authoredComment(on: "darksuperstarmon").contains("Superstarmon"),
                      "the pin that tells the S-Z sweep where Superstarmon goes is missing")
        XCTAssertTrue(try authoredComment(on: "fantomon").contains("Phantomon"),
                      "the Fantomon/Phantomon two-sheets reading is not written down")
    }

    /// **FANTOMON AND PHANTOMON ARE ONE DIGIMON AND THIS PACK SHIPS BOTH SHEETS**, which is US-143's
    /// HolyAngemon/MagnaAngemon case with the opposite answer: there, two names shared ONE sheet and
    /// became one node; here, two sheets exist, the roster is one entry per sheet, and so two nodes
    /// are right. What must NOT happen is one Champion offering the same Digimon twice under two
    /// names, so they hang off different Champions of the same line — and that is the claim.
    func testFantomonAndPhantomonAreTwoSheetsAndNeverShareAParent() throws {
        for id in ["fantomon", "phantomon"] {
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) has no sheet of its own")
            XCTAssertFalse(entry.dexOnly)
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "penc-nso")
        }
        XCTAssertNotEqual(try XCTUnwrap(roster.entry(id: "fantomon")).spriteFile,
                          try XCTUnwrap(roster.entry(id: "phantomon")).spriteFile,
                          "one sheet after all — then this is US-143's case and one node is right")

        let fantomonParents = Set(graph.parents(of: "fantomon").map(\.id))
        let phantomonParents = Set(graph.parents(of: "phantomon").map(\.id))
        XCTAssertEqual(fantomonParents, ["wizarmon"])
        XCTAssertTrue(fantomonParents.isDisjoint(with: phantomonParents),
                      "a Champion reaches the same Digimon twice under two spellings")
    }

    /// **The handover to US-159, in the shape US-151 through US-157 established: a claim, not a
    /// note.** What the H-Z Perfect sweeps inherit is seven brand-new Ultimate leaves, six lines
    /// that still have no Perfect rung, a dead-end ledger seven lower, and — for the first time
    /// since US-134 — no line anywhere with a Perfect rung and nothing above it. The ledger figure
    /// tracks the FILE rather than this story, so US-159's nine cleared leaves moved it again
    /// (90 -> 81); the six lines without a Perfect rung have not moved at all.
    func testWhatThisSweepHandsToTheRestOfThePerfectRung() throws {
        for id in authoredUltimates.map(\.ultimate) {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) leads somewhere, which nothing at the top rung may")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).stage, .ultimate)
        }

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["algomon"],
                       "a line gained or lost its Perfect rung; the remaining sweeps' bill changed — "
                           + "US-160 took `diablomon` off this list by putting the two Meicrackmon "
                           + "over Meicoomon, and gave it Rasielmon and Raguelmon in the same edit")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       59, "the dead-end ledger in `ChildSweepAToFTests` has moved")
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// FOURTEEN Perfects plus SEVEN Ultimates plus one rename, counted with Appendix B of the PRD
    /// over a regenerated `roster.generated.json`: 257 before, 235 after; the Perfect bucket falls
    /// 84 -> 69 and the Ultimate bucket 157 -> 150, because every Ultimate this story opened was an
    /// orphan too and Ex-Tyranomon's rename took a fifteenth Perfect off the list for free.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later reader
    /// cannot re-derive from the diff.
    func testTheTwentyTwoOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 14)
        XCTAssertEqual(authoredUltimates.count, 7)

        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["ex-tyranomon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 851, "672 before this story, 693 after it, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")

        // The buckets, re-derived off the graph rather than trusted from the notes.
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "101 before this story, 115 after it, 126 after US-159, 148 after US-160, 165 after US-161, 189 after US-162")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 172, "81 before this story, 88 after it, 93 after US-159, 98 after US-160, 105 after US-161, 108 after US-162, 138 after US-163")
    }

    /// Every Ultimate this story opened serves exactly one Perfect, so a second parent hung on one
    /// later fails this rather than passing quietly — the `Set(graph.parents(of:))` equality shape
    /// every sweep since US-151 has established.
    func testTheSevenUltimatesThisStoryOpenedEachServeExactlyOneOfItsPerfects() throws {
        for (ultimate, parents, line) in authoredUltimates {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertEqual(node.line, line, "\(ultimate) is not on its Perfect's line")
            XCTAssertEqual(Set(graph.parents(of: ultimate).map(\.id)), parents,
                           "\(ultimate)'s parents changed without this claim changing with them")
        }

        // No two of this story's Perfects share a climb, which US-157 could not say — Cargodramon
        // and Cyberdramon X both landed on Mugendramon there. Each of the seven free placements
        // joins an Ultimate that already had a parent, and each of the seven new ones has exactly
        // one, so the file gains no second-parent ambiguity from this story at all.
        XCTAssertEqual(Set(swept.map(\.ultimate)).count, swept.count)
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
    /// helper US-151 wrote, kept because several of this story's edges ask for FEW overfeeds, FEW
    /// sleep disturbances or LITTLE sleep, and a blanket "did everything right" context is the one
    /// thing that cannot take an `atMost`.
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
    /// helper US-144 through US-157 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
