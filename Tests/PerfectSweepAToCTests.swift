import XCTest

@testable import DigiVPet

/// US-157 — the fourteenth of Phase E's orphan sweeps and the FIRST at the Perfect rung: the
/// nineteen playable Perfect whose display name begins A-C that no device tree and no Champion
/// sweep reached.
///
/// **The scope reading is US-151's through US-156's, one rung up.** The criteria ask for coverage of
/// "every remaining orphan at stage Perfect whose displayName starts with A-C", so the Perfects in
/// range that an earlier story left as LEAVES — Canoweissmon, BlackRapidmon, CatchMamemon and the
/// rest — are not in scope: they have an in-edge and are therefore not orphans. They stay on the
/// dead-end ledger in `ChildSweepAToFTests` and the Ultimate sweeps are what pays them off.
///
/// **What makes this rung different from the six below it, and it is the whole shape of the story:
/// a Perfect sweep pays DOWN as well as up.** A Champion sweep could only ever hang a new Champion
/// off a Rookie that was already branching. A Perfect needs a Champion beneath it, and after six
/// Adult sweeps most Champions are LEAVES — so nine of this story's nineteen in-edges came off the
/// dead-end ledger rather than adding to it, and the ledger falls 105 -> 97 for the first time in
/// Phase E. Each of those nine also had to be given its line's junk floor in the same edit, because
/// `EvolutionCriteriaTests` fails any branching Champion without one.
///
/// **What it costs one rung up: NINE Ultimates, and ten of the nineteen cost nothing at all.**
/// US-152's rule — intersect `Evolves From` against `Evolves To` before choosing a line — closed on
/// ten of them, which is the highest rate of any sweep so far and is not luck: after six Adult
/// sweeps almost every line has a full Perfect rung, so the Ultimates are already there to land on.
/// The nine that had to be opened are the ones whose cited climb had no node anywhere — four of
/// them on `tamers`, which had FIVE Perfects and no Ultimate at all until this story.
///
/// **Two rungs were opened outright.** `tamers` got its first Ultimate rung, which promoted five
/// Digitama to legal starting eggs in `EggHatchingTests`; and `penc-sw` got its first Perfect rung,
/// which US-153 and US-156 both deferred and US-156 handed to the Perfect sweeps by name.
final class PerfectSweepAToCTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The nineteen orphaned Perfects this story wired, with the Champion that now reaches each and
    /// the Ultimate each now climbs into. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("andiramon_data", "turuiemon", "cherubimon_vice"),
        ("angewomon_x", "tailmon_x", "ophanimon_x"),
        ("anomalocarimon_x", "ebidramon", "aegisdramon"),
        ("archnemon", "dokugumon", "piemon"),
        ("astamon", "porcupamon", "pencme_venomvamdemon"),
        ("atlurkabuterimon_red", "pencnsp_kabuterimon", "heraklekabuterimon"),
        ("baalmon", "icedevimon", "beelzebumon"),
        ("blackmegalogrowmon", "blackgrowmon", "chaosdukemon"),
        ("bluemeramon", "pencnso_meramon", "pencnso_boltmon"),
        ("boutmon", "thunderballmon", "kazuchimon"),
        ("cannonbeemon", "waspmon", "tigervespamon"),
        ("cargodramon", "tankmon", "pencme_mugendramon"),
        ("caturamon", "pencvb_leomon", "pencvb_saberleomon"),
        ("cerberumon_x", "raptordramon", "pencme_wargreymon"),
        ("chimairamon", "airdramon", "millenniumon"),
        ("chohakkaimon", "hakubamon", "shakamon"),
        ("crescemon", "lekismon", "dianamon"),
        ("cryspaledramon", "paledramon", "hexeblaumon"),
        ("cyberdramon_x", "revolmon", "pencme_mugendramon"),
    ]

    /// The nine Ultimates this story authored, and the line each landed on. All nine are leaves, as
    /// every Ultimate in the file is; none of them is on the dead-end ledger, which only counts
    /// below the top rung.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        ("ophanimon_x", ["angewomon_x"], "penc-vb"),
        // US-159 hung LadyDevimon under this one — the first of the nine to take a second Perfect,
        // and a cited climb on that page. Named rather than the check being loosened to a superset.
        ("beelzebumon", ["baalmon", "ladydevimon"], "tamers"),
        // US-160 hung MegaloGrowmon X under this one, off the leaf BlackGalgomon — a cited climb
        // on that page, and the black thread beside the one this story drew. Named rather than the
        // check being loosened to a superset, the same way LadyDevimon was named above.
        ("chaosdukemon", ["blackmegalogrowmon", "megalogrowmon_x"], "tamers"),
        // US-162 hung Shootmon under this one — its ONLY cited climb with a node anywhere, so the
        // line was decided by this Mega rather than by a parent. Named rather than loosened.
        ("kazuchimon", ["boutmon", "shootmon"], "penc-me"),
        ("tigervespamon", ["cannonbeemon"], "palmon"),
        ("millenniumon", ["chimairamon"], "dmc-v1"),
        // US-162 hung Sagomon, Sanzomon and Shawujinmon under this one, which is the Journey to
        // the West party fusing exactly as the pages draw it. Named rather than loosened.
        ("shakamon", ["chohakkaimon", "sagomon", "sanzomon", "shawujinmon"], "penc-sw"),
        ("dianamon", ["crescemon"], "tamers"),
        ("hexeblaumon", ["cryspaledramon"], "tamers"),
    ]

    /// The nine Champions that were LEAVES before this story, and the junk Perfect each now falls
    /// to. Eight of the nine floors already existed; Pandamon is this story's own, and `penc-sw`
    /// needed it before Hakubamon could branch at all.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("tailmon_x", "andiramon_virus"),
        ("porcupamon", "locomon"),
        ("icedevimon", "catchmamemon"),
        ("blackgrowmon", "catchmamemon"),
        ("waspmon", "jyagamon"),
        ("raptordramon", "locomon"),
        ("hakubamon", "pandamon"),
        ("lekismon", "catchmamemon"),
        ("paledramon", "catchmamemon"),
    ]

    /// The shared "did everything right" context, US-151's through US-156's exactly.
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
    ///
    /// Both halves of AC2 are asserted for the whole range rather than only for this story's
    /// nineteen: a Perfect is not a terminal Ultimate, so every one of them owes an out-edge too —
    /// which is why the leaves an earlier sweep opened (BlackRapidmon, Canoweissmon, Huankunmon,
    /// Grademon, Mametyramon, MegaloGrowmon, CatchMamemon, BlackMachGaogamon, Karakurumon) are
    /// EXCLUDED here and asserted against the ledger instead. They are leaves, not orphans, and the
    /// Ultimate sweeps own them.
    func testEveryPlayablePerfectAToCIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && ("A"..."C").contains(String($0.displayName.prefix(1)).uppercased())
        }
        // Thirty-four, not the thirty-seven Appendix B's script reports: that script reads
        // `roster.generated.json`, which mirrors `evolutions.json` and so carries the line-scoped
        // ALIASES too (`pencme_andromon`, `pencvb_angewomon`, `pencvb_asuramon` are the three in
        // this range). `Roster.bundled` reads `Resources/roster.json`, which is one entry per
        // SHEET on disk — the right denominator for "every Digimon on disk is obtainable".
        XCTAssertEqual(inRange.count, 34)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The nineteen this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoPerfectAToCIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("A"..."C").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects A-C still orphaned: \(orphans)")
    }

    /// The Perfects in range this story deliberately did NOT wire onward, named rather than counted.
    /// Every one of them is on the dead-end ledger in `ChildSweepAToFTests`; if a later story wires
    /// one it belongs there and here, not silently in one place.
    func testThePerfectsAToCLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("A"..."C").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        // US-163 wired TWO of the four onward, which is what "it belongs there and here" meant:
        // BlackRapidmon now climbs to BlackSaintGalgomon and Canoweissmon to Arcturusmon, both
        // cited on Wikimon and both off the dead-end ledger in the same edit. The other two are
        // junk floors and stay leaves.
        let wiredByUS163 = ["blackrapidmon", "canoweissmon"]
        XCTAssertEqual(leaves, ["blackmachgaogamon", "catchmamemon"],
                       "the A-C Perfect leaves have moved without the ledger moving with them")

        for id in leaves + wiredByUS163 {
            XCTAssertFalse(graph.parents(of: id).isEmpty,
                           "\(id) is an orphan rather than a leaf, so it WAS in this story's scope")
        }
        for id in wiredByUS163 {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                           "\(id) is a leaf again — then it belongs back on the list above")
        }
    }

    // MARK: - AC2/AC4: the shape of every edge this story authored

    /// Each swept Perfect climbs by exactly one `isDefault` edge, gated on energy and on care but
    /// carrying no criteria — the shape every Perfect in this file has had since US-134, and the
    /// reading of "no edge is unconditional" that every rung below recorded. US-020 takes the
    /// `isDefault` edge exactly when nothing else qualifies, so a condition on one would be data
    /// that lies about how it is taken. What the criterion really binds is the EARNED edges, and
    /// every earned edge this story authored is checked below.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        // **US-163 IS THE FIRST STORY TO FORK A PERFECT, AND THESE ARE THE ONES IT FORKED.** The
        // Ultimate sweep's in-edges come from this rung, so a Perfect that already had its climb
        // gained an EARNED branch beside it — a different `requiredEnergy`, two criteria, and the
        // climb untouched and still `isDefault`, which is the whole of what this test checks. Each
        // is NAMED with its new edge count rather than the count being loosened to a `>=`.
        // US-164, the C-D Ultimate sweep, forked two more of them: andiramon_virus (Cherubimon
        // Vice X) and blackmegalogrowmon (ChaosDukemon Core) each gained their first branch
        // (1 -> 2). Chimairamon stayed at its US-163 count because Chaosmon, the Ultimate that
        // would have forked it, is a Jogress result and so was left unwired.
        // US-166, the I-M Ultimate sweep, forked two more: chohakkaimon (Jougamon) and cyberdramon_x
        // (Justimon X), each gaining their first branch (1 -> 2).
        let branchedBySweeps: [String: Int] = ["astamon": 3, "atlurkabuterimon_red": 2, "baalmon": 3,
                                             "cargodramon": 2, "cerberumon_x": 2, "chimairamon": 3,
                                             "andiramon_virus": 2, "blackmegalogrowmon": 2,
                                             "chohakkaimon": 2, "cyberdramon_x": 2,
                                             "angewomon_x": 2]
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

    /// **NINE Champions came off the dead-end ledger here, and each one had to be given a junk
    /// floor in the same edit.** A leaf Champion has no fallback because it has no edges at all; the
    /// moment it gains an earned branch, `EvolutionCriteriaTests` requires an `isDefault` edge onto
    /// a junk Perfect of its OWN line. Eight of the nine floors already existed. Pandamon is the
    /// exception and is this story's own — see `testOpeningPencSwsPerfectRungCostThreeNodes`.
    func testTheNineLeafChampionsGainedTheirLinesJunkFloor() throws {
        // **US-158 hung Duramon on Raptordramon**, so the "exactly two edges" half of this claim
        // no longer holds for it. Relaxed to "exactly one fallback, and this story's branch is
        // still earned" rather than deleted — a second earned branch off a Champion this story
        // opened is exactly what a later sweep is supposed to be able to do; a second FALLBACK
        // never is.
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) is not one earned branch plus a single fallback")
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(parent) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(parent)'s line")
            XCTAssertEqual(floor.stage, .perfect)

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.minEnergy, 0, "\(parent)'s junk edge demands energy")
            XCTAssertEqual(fallback.conditions, [], "\(parent)'s junk edge carries criteria")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)
        }

        // The other ten hung off a Champion that was ALREADY branching, so none of them needed a
        // floor and none of them touched one.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching.count, 10)
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

        // Revolmon is the ONE this story filled: Andromon took vitality, the plain Cyberdramon
        // strength and Cyberdramon X the stamina that was left, so only spirit remains and the node
        // is one branch off the ceiling. Said out loud so a later sweep prices a branch off this
        // rather than discovering it as a failure.
        let revolmon = try XCTUnwrap(graph.node(id: "revolmon"))
        XCTAssertEqual(Set(revolmon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       [.vitality, .strength, .stamina])
        XCTAssertEqual(revolmon.evolutions.count, 4)
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
    /// like — the entry point US-155 established is the right one for a neglect assertion, because
    /// `evolutionTarget` matches on the dominant energy and a neglected Digimon has none.
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
    /// UNREACHABLE rather than merely hard. Restated over this story's thirty-eight new edges
    /// because it is cheap and because the engine, not the validator, is the only thing that catches
    /// it.
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

    /// No new lines for twenty-nine new nodes — nine existing ones absorbed all of them, and the
    /// biggest single share went to `tamers`, which was already the largest line in the file. A
    /// sweep must not produce dozens of one-node lines, and the way this one satisfies that is by
    /// opening none at all.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 123, "four Perfects and four Ultimates, plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["penc-me"], 74, "five Perfects and Kazuchimon, plus US-158's Duramon, plus US-159's two" + ", plus US-160's one, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas, plus US-163's four Ultimates")
        XCTAssertEqual(sizes["penc-vb"], 61, "three Perfects and Ophanimon X, plus US-158's Entmon, plus US-161's Regulusmon, plus US-163's two Ultimates")
        XCTAssertEqual(sizes["penc-nso"], 84, "Archnemon and BlueMeramon, plus US-158's three, plus US-159's four" + ", plus US-160's five, plus US-161's Orochimon, plus US-163's seven Ultimates")
        XCTAssertEqual(sizes["dmc-v1"], 42, "Chimairamon and Millenniumon" + ", plus US-160's three, plus US-161's NeoDevimon, plus US-163's three Ultimates")
        XCTAssertEqual(sizes["palmon"], 32, "Cannonbeemon and TigerVespamon, plus US-159's two, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-sw"], 23, "Cho-Hakkaimon, Pandamon and Shakamon, plus US-158's two")
        XCTAssertEqual(sizes["penc-ds"], 48, "Anomalocarimon X, plus US-158's Gusokumon, plus US-159's Hangyomon" + ", plus US-160's two, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-nsp"], 46, "AtlurKabuterimon Red, plus US-158's two" + ", plus US-160's one, plus US-161's both Panjyamon, plus US-163's one Ultimate")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 9)
    }

    /// **Every variant in this story landed on a line that already held its family**, which is the
    /// criteria's variant rule. Four followed their BASE FORM's line (Angewomon X, Anomalocarimon X,
    /// AtlurKabuterimon Red, Cyberdramon X — every one of those base forms is a Perfect on the line
    /// the variant took), and Cerberumon X is the exception argued in its comment: the plain
    /// Cerberumon has NO sheet in this pack at all, so there was no base form to follow and the
    /// cited Champion chose the line instead.
    func testTheFiveVariantsLandedBesideTheirBaseForm() throws {
        for (variant, base) in [("angewomon_x", "pencvb_angewomon"),
                                ("anomalocarimon_x", "anomalocarimon"),
                                ("atlurkabuterimon_red", "atlurkabuterimon_blue"),
                                ("cyberdramon_x", "cyberdramon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: base)).stage, .perfect)
        }

        XCTAssertNil(graph.node(id: "cerberumon"),
                     "the plain Cerberumon is a node now — then the X follows it, not Raptordramon")
        XCTAssertNil(roster.entry(id: "cerberumon"),
                     "a Cerberumon sheet appeared — Cerberumon X's placement wants re-arguing")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "cerberumon_x")).line, "penc-me")

        XCTAssertEqual(swept.map(\.perfect).filter { $0.hasSuffix("_x") || $0.hasSuffix("_red") }
                        .sorted(),
                       ["angewomon_x", "anomalocarimon_x", "atlurkabuterimon_red", "cerberumon_x",
                        "cyberdramon_x"],
                       "a variant appeared that this claim does not account for")
    }

    /// **The ten placements that cost nothing, restated as a check on the DATA rather than on the
    /// prose.** For each, the Champion below and the Ultimate above were on the chosen line BEFORE
    /// this story — which is exactly what "US-152's intersection was non-empty" means, and the
    /// property a later reader can re-derive.
    func testTheTenFreePlacementsPutTheChampionAndTheUltimateOnOneLine() throws {
        let free = swept.filter { !authoredUltimates.map(\.ultimate).contains($0.ultimate) }
        XCTAssertEqual(free.count, 10)

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

    // MARK: - The two rungs this story opened

    /// **`tamers` HAD FIVE PERFECTS AND NO ULTIMATE AT ALL, AND THAT IS WHY FOUR OF THE NINE NEW
    /// ULTIMATES ARE ON ONE LINE.** It is the largest line in the file and every thread on it
    /// stopped one rung short of the top. The knock-on is the one worth pinning: `EggHatchingTests`
    /// promoted FIVE Digitama from unraisable to legal starting eggs, because
    /// `MainScreenModel.startingDigitamaId` filters on `reachesUltimate` and those five threads
    /// now reach one.
    func testOpeningTheTamersUltimateRungPromotedFiveStartingEggs() throws {
        // US-158 added Titamon and DORUgoramon, so this is a superset rather than an equality:
        // what this story owns is its four, not the rung's whole census.
        let ultimates = graph.nodes.filter { $0.line == "tamers" && $0.stage == .ultimate }
        XCTAssertTrue(Set(ultimates.map(\.id)).isSuperset(
                        of: ["beelzebumon", "chaosdukemon", "dianamon", "hexeblaumon"]),
                      "the `tamers` Ultimate rung has moved since US-157 opened it")

        for id in ["guil_digitama", "blackguil_digitama", "imp_digitama", "lop_digitama",
                   "bluco_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) no longer reaches an Ultimate — `EggHatchingTests` moves with it")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "tamers")
        }

        // And the `tamers` eggs that are STILL unraisable, named so that the story which promotes
        // one knows it is the one doing it. Each stops below the Perfect rung, not below the
        // Ultimate one, so this story could not have reached them. **Monodra left the list in
        // US-158**, which wired DORUguremon and DORUgoramon over the leaf DORUgamon — the
        // middle-of-the-thread kind of promotion, not this story's top-of-the-thread kind.
        // **Rena and Terrier left in US-159** the same middle-of-the-thread way: LadyDevimon over
        // the leaf Kyubimon, and LadyDevimon X over the junk Numemon X that Terriermon falls to.
        // **V Digitama left in US-162**, which is the third kind again: it opened `adventure02`'s
        // Perfect rung under Nise Drimogemon, the line's JUNK Champion, so the promotion came down
        // the neglect thread rather than the earned one. Every `tamers` egg now reaches an
        // Ultimate, so the list this comment used to carry is empty and the claim is the empty set.
        XCTAssertEqual(graph.nodes(at: .digitama)
            .filter { $0.line == "tamers" && !graph.reachesUltimate(from: $0.id) }, [],
                       "a `tamers` egg stopped reaching an Ultimate")
        XCTAssertTrue(graph.reachesUltimate(from: "v_digitama"),
                      "V Digitama stopped reaching an Ultimate — US-162's Vermillimon carries it")
        for id in ["rena_digitama", "terrier_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) stopped reaching an Ultimate — US-159's LadyDevimon pair carries it")
        }
    }

    /// **OPENING `penc-sw`'s PERFECT RUNG COST EXACTLY THE THREE NODES US-153 AND US-156 QUOTED,
    /// AND IT IS PAID HERE RATHER THAN DEFERRED A THIRD TIME.** Cho-Hakkaimon is the earned Perfect,
    /// Shakamon the Ultimate over it, and Pandamon the junk floor every branching Champion of the
    /// line now needs — plus the `EvolutionCriteriaTests.junkIds` entry those two stories also
    /// priced. It is paid because four more Saiyu Warriors Perfects (Sagomon, Sanzomon, Gokuwmon,
    /// Shawujinmon) are orphans waiting on this rung and Kinkakumon and Xiquemon are both waiting to
    /// be rehomed onto it.
    func testOpeningPencSwsPerfectRungCostThreeNodes() throws {
        // US-158 added Gokuwmon and Seiten Gokuwmon over Ginkakumon, so the claim is a superset
        // rather than an equality: what this story owns is the three, not the rung's whole census.
        let added = graph.nodes.filter { $0.line == "penc-sw" && $0.stage != .child
            && $0.stage != .babyI && $0.stage != .babyII && $0.stage != .adult }
        XCTAssertTrue(Set(added.map(\.id))
                        .isSuperset(of: ["chohakkaimon", "pandamon", "shakamon"]))

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "chohakkaimon")).stage, .perfect)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "pandamon")).stage, .perfect)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "shakamon")).stage, .ultimate)
        // Pandamon was this rung's junk floor and a dead end until US-165, the E-H Ultimate sweep,
        // gave it its climb to Erlangmon — so it now leads exactly one place.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "pandamon")).evolutions.map(\.to), ["erlangmon"],
                       "Pandamon's climb changed without this claim changing with it")

        // Hakubamon was the only Champion of the line that branched; US-158 gave Ginkakumon
        // Gokuwmon, so it is two now and the other two are still leaves.
        let branching = graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .adult
            && !$0.evolutions.isEmpty }
        XCTAssertEqual(branching.map(\.id).sorted(),
                       ["ginkakumon", "hakubamon", "lianpumon", "tsuchidarumon"],
                       "US-162 branched the other two — the whole line's Champions now carry a Perfect")

        // The four Saiyu Warriors Perfects this rung was opened FOR, all four now on it. US-158
        // took Gokuwmon — the first of them, and the reason the rung was opened early — and US-162
        // took the other three, plus Xingtianmon with them. Same claim, other side: it fails if one
        // of them is rehomed off `penc-sw` without this test moving with it.
        for id in ["sagomon", "sanzomon", "shawujinmon"] {
            XCTAssertNotNil(roster.entry(id: id), "\(id) is on disk, which is why it was owed")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "penc-sw",
                           "\(id) left the rung this story opened for it")
        }
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gokuwmon")).line, "penc-sw",
                       "US-158 put Gokuwmon on the rung this story opened for it")

        // And the whole line is STILL stranded, which US-148 recorded and no story at this rung can
        // fix: `penc-sw` has no Digitama, and US-144/US-145 spent all 57.
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .digitama }, [])
    }

    // MARK: - AC5/AC6: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to all twenty-nine new nodes.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["pandamon"] {
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
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["pandamon"] {
            let line = try XCTUnwrap(graph.node(id: id)).line
            XCTAssertFalse(line.isEmpty, "\(id) has no line")
            XCTAssertTrue(known.contains(line), "\(id) is on the unknown line \(line)")
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["pandamon"] {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation") || comment.contains("FLAVOUR"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }

        // **The two edges in this story that rest on a LINE argument rather than a citation say so
        // out loud**, which is US-151's Burgamon rule and US-156's V-dramon Black one. Both are
        // X-Antibody Perfects whose only cited parent is their own base form — a Perfect, which can
        // never be an in-edge — so the day someone finds a real citation they know what they are
        // replacing.
        for id in ["anomalocarimon_x", "cyberdramon_x"] {
            XCTAssertTrue(try authoredComment(on: id).contains("LINE argument"),
                          "\(id)'s in-edge is dressed as a citation it does not have")
            XCTAssertTrue(try authoredComment(on: id).contains("NO CITATION"))
        }

        // And the rejected readings are written down too, so the story that revisits one is told
        // which arrow was considered and why it lost, rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "cargodramon").contains("commandramon"),
                      "Cargodramon's rejected D-Brigade reading is not named")
        XCTAssertTrue(try authoredComment(on: "boutmon").contains("vital"),
                      "Boutmon's rejected Vital Bracelet reading is not named")
        XCTAssertTrue(try authoredComment(on: "astamon").contains("Belphemon"),
                      "Astamon's undrawable bolded Ultimates are not named")
        XCTAssertTrue(try authoredComment(on: "caturamon").contains("Baihumon"),
                      "Caturamon's undrawable bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "chimairamon").contains("Mugendramon"),
                      "Chimairamon's rejected Mugendramon reading is not named")
    }

    /// **The rejected readings that a LATER story is expected to act on, pinned from both sides.**
    /// Cargodramon belongs on `commandramon` — Ginryumon and Hi-Commandramon are both cited parents
    /// and both are on it — and lost only on price, exactly as US-153's Kinkakumon and US-156's
    /// Xiquemon did. Boutmon belongs on `vital` for the same shape of reason. Whoever opens either
    /// line's Perfect rung is TOLD here that these two are the rehome candidates on it.
    func testTheTwoRejectedLineReadingsAreStillTheCheaperOnesNotTaken() throws {
        // `commandramon` still has none. `vital` gained one in US-161 — Oboromon and RaijiLudomon,
        // both over its own leaf Champions — so THAT half of the claim flips rather than dies: the
        // rehome candidate this story pinned for `vital` is now a live job for a later sweep, and
        // the check is that Cargodramon and Boutmon did NOT quietly move there with it.
        // US-162 opened `commandramon` too, under Damemon and Ginryumon, so BOTH halves of this
        // claim have now flipped: each line has a Perfect rung and each rehome candidate is a live
        // job for an Ultimate sweep. What is still checked is that neither candidate quietly moved.
        XCTAssertFalse(graph.nodes.filter { $0.line == "commandramon" && $0.stage == .perfect }
            .isEmpty, "`commandramon` lost the Perfect rung US-162 opened")
        XCTAssertFalse(graph.nodes.filter { $0.line == "vital" && $0.stage == .perfect }.isEmpty,
                       "`vital` lost the Perfect rung US-161 opened")

        for id in ["ginryumon", "hi-commandramon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "commandramon",
                           "a cited parent of the rejected Cargodramon reading has moved line")
        }
        XCTAssertEqual(roster.entry(id: "sealsdramon")?.dexOnly, true,
                       "Sealsdramon is animated now — the third D-Brigade parent became usable")
        XCTAssertEqual(roster.entry(id: "bulkmon")?.dexOnly, true,
                       "Bulkmon is animated now — Boutmon's bolded parent became usable")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "pulsemon")).stage, .child,
                       "Pulsemon is a Champion now — Boutmon's warp-evolution arrow is drawable")

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "cargodramon")).line, "penc-me")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "boutmon")).line, "penc-me")
    }

    /// **The handover to US-158, in the shape US-151 through US-156 established: a claim, not a
    /// note.** What the D-Z Perfect sweeps inherit is nine brand-new Ultimate leaves of this story's
    /// own, six lines that STILL have no Perfect rung, and a dead-end ledger that fell for the first
    /// time in Phase E. Pinned so the next sweep is told the shape of its job rather than having to
    /// count it.
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

        // The two lines that still have a Perfect rung and NO Ultimate rung, which is the shape
        // `tamers` had before this story and the next thing a sweep will have to pay for.
        // **US-158 CLOSED IT.** `wanyamon` was the one line left with Perfects and no Mega; the
        // D-G sweep hung Gogmamon and Grappleomon on its last two leaf Champions and Ancient
        // Volcamon and Dinotigermon over them, so every line in the file that has a Perfect rung
        // now has an Ultimate rung too. The claim is flipped rather than deleted: the day a sweep
        // opens a Perfect rung on one of the six lines above without a Mega over it, this fails.
        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again — US-158 closed the last")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       58, "the dead-end ledger in `ChildSweepAToFTests` has moved")
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// NINETEEN Perfects plus NINE Ultimates plus one junk floor, counted with Appendix B of the PRD
    /// over a regenerated `roster.generated.json`: 286 before, 257 after; the Perfect bucket falls
    /// 104 -> 84 and the Ultimate bucket 166 -> 157, because every node this story opened was an
    /// orphan too. Asserted rather than only noted, because the count is the one claim in `notes` a
    /// later reader cannot re-derive from the diff.
    func testTheTwentyNineOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 19)
        XCTAssertEqual(authoredUltimates.count, 9)

        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["pandamon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 898,
                       "643 before this story, 672 after it, 693 after US-158, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")

        // The buckets, re-derived off the graph rather than trusted from the notes.
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189,
                       "81 before this story, 101 after it, 115 after US-158, 126 after US-159, 148 after US-160, 165 after US-161, 189 after US-162")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 219,
                       "72 before this story, 81 after it, 88 after US-158, 93 after US-159, 98 after US-160, 105 after US-161, 108 after US-162, 138 after US-163")
    }

    /// Every Ultimate this story opened served exactly one Perfect when it was written, so a second
    /// parent hung on one later fails this rather than passing quietly — the
    /// `Set(graph.parents(of:))` equality shape US-151, US-152, US-154, US-155 and US-156
    /// established. US-159 hung LadyDevimon under Beelzebumon and NAMED it here, which is what the
    /// shape is for: the claim is the parent SET, not the count.
    func testTheNineUltimatesThisStoryOpenedEachServeExactlyOneOfItsPerfects() throws {
        for (ultimate, parents, line) in authoredUltimates {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertEqual(node.line, line, "\(ultimate) is not on its Perfect's line")
            XCTAssertEqual(Set(graph.parents(of: ultimate).map(\.id)), parents,
                           "\(ultimate)'s parents changed without this claim changing with them")
        }

        // And the one Ultimate that took TWO of this story's Perfects, which is the only place a
        // pair shares a climb: Cargodramon and Cyberdramon X both cite Mugendramon, and `penc-me`
        // already had it. Different energies would be the guard if these were earned branches off
        // one node — they are not, they are two separate Perfects, so what is pinned is that the
        // node they share was there before this story.
        // US-162's Scorpiomon joined them, over the leaf Kuwagamon X — a cited parent with
        // Mugendramon BOLDED on its own page. Named rather than the check being loosened.
        XCTAssertEqual(Set(graph.parents(of: "pencme_mugendramon").map(\.id)),
                       ["pencme_andromon", "cyberdramon", "cargodramon", "cyberdramon_x",
                        "scorpiomon"])
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
            battleWinRatioLifetime: 1.0,
            // Lights-out, so a dark-line edge gated on `care.lightOff` (US-185) is reachable.
            lightState: .off)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-156 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
