import XCTest

@testable import DigiVPet

/// US-160 — the seventeenth of Phase E's orphan sweeps and the fourth at the Perfect rung: the
/// twenty-one playable Perfect whose display name begins with M that no device tree, Champion sweep
/// or earlier Perfect sweep reached. **The biggest single band the rung has, and the biggest sweep
/// since US-157.**
///
/// **Twenty-one orphans, twenty-seven nodes**: the Perfects, five Ultimates they climb into that had
/// no node, and one junk Perfect floor. Fifteen of the twenty-one landed between a Champion and an
/// Ultimate that were BOTH already on the chosen line — US-152's intersection closing more often
/// than in any earlier sweep, because after three Perfect sweeps most lines now have a Mega rung.
///
/// **`diablomon` got its Perfect AND its Ultimate rung in one edit**, which is the bill US-158 wrote
/// down: a sweep that opens a Perfect rung on one of the six lines with none owes a Mega over it in
/// the same story. Meicoomon is the ONLY parent this pack can draw for either Meicrackmon, so the
/// alternative was leaving both orphaned. It cost a junk floor, and that floor is the first in
/// `EvolutionCriteriaTests.junkIds` that is a line-scoped ALIAS — every unused Perfect sheet left in
/// the pack is a real Digimon rather than a gag one, so there was nothing to spend the way
/// CatchMamemon, Karakurumon and Pandamon were spent.
///
/// **Nine of the twenty-one are variants and eight of the nine sit with their base form.** Two of
/// those eight sit on their base form's own PARENT as well, which is the strongest reading the
/// variant rule has; the ninth, MetalMamemon X, follows a cited parent instead, because `dmc-v2`
/// offers none at all.
///
/// **Five leaf Champions cleared, one node added back**: 81 -> 77 on the dead-end ledger.
final class PerfectSweepMTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The twenty-one orphaned Perfects this story wired, with the Champion that now reaches each
    /// and the Ultimate each now climbs into. Every one is a plain roster id, so every one removes
    /// an orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("machgaogamon", "gaogamon", "ancientvolcamon"),
        ("mamemon_x", "greymon_blue", "banchomamemon"),
        ("mammon_x", "shimaunimon", "pencnso_skullmammon"),
        ("manticoremon", "growmon", "dukemon"),
        ("marinbullmon", "shellmon", "ryugumon"),
        ("marinchimairamon", "octmon", "plesiomon"),
        ("megaseadramon_x", "hyougamon", "metalseadramon"),
        ("megalogrowmon_orange", "growmon_orange", "dukemon"),
        ("megalogrowmon_x", "blackgalgomon", "chaosdukemon"),
        ("meicrackmon", "meicoomon", "rasielmon"),
        ("meicrackmon_vicious", "meicoomon", "raguelmon"),
        ("mephismon", "wizarmon", "piemon"),
        ("mephismon_x", "pencnso_devimon", "dinorexmon"),
        ("mermaimon", "ikkakumon", "vikemon"),
        ("metalgreymon_virus_x", "devimon", "blitzgreymon"),
        ("metalmamemon_x", "thunderballmon", "princemamemon"),
        ("metalphantomon", "bakemon", "gokumon"),
        ("metaltyranomon_v2", "darktyranomon", "mugendramon"),
        ("metaltyranomon_x", "cyclomon", "mugendramon"),
        ("monzaemon_x", "numemon", "dmcv1_shinmonzaemon"),
        ("mummymon", "pencnso_bakemon", "deathmon"),
    ]

    /// The five Ultimates this story authored, and the line each landed on. All five are leaves, as
    /// every Ultimate in this file is; none is on the dead-end ledger, which stops below the top
    /// rung.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        ("dukemon", ["manticoremon", "megalogrowmon_orange"], "tamers"),
        // US-162 hung Sekkamon under this one, over the same Shellmon MarinBullmon hangs off —
        // both ends cited on `dmc-v3`. Named rather than the check being loosened to a superset.
        ("ryugumon", ["marinbullmon", "sekkamon"], "dmc-v3"),
        ("rasielmon", ["meicrackmon"], "diablomon"),
        ("raguelmon", ["meicrackmon_vicious"], "diablomon"),
        ("dinorexmon", ["mephismon_x"], "penc-nso"),
    ]

    /// The five Champions that were LEAVES before this story, and the junk Perfect each now falls
    /// to. Four of the five floors already existed; `diablomon_gerbemon` is this story's own, and
    /// `diablomon` is the first line since `penc-sw` in US-157 to need one.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("greymon_blue", "blackkingnumemon"),
        ("growmon", "catchmamemon"),
        ("blackgalgomon", "catchmamemon"),
        ("hyougamon", "pumpmon"),
        ("meicoomon", "diablomon_gerbemon"),
    ]

    /// The shared "did everything right" context, US-151's through US-159's exactly.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.standHours": 1_000,
                                           "health.flightsClimbed": 5_000,
                                           "health.distanceSwimming": 500_000,
                                           "health.mindfulMinutes": 5_000,
                                           "health.daylight": 5_000,
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
    func testEveryPlayablePerfectMIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && String($0.displayName.prefix(1)).uppercased() == "M"
        }
        // Thirty-four, not the thirty-eight nodes the graph holds in this band: `Roster.bundled`
        // reads `Resources/roster.json`, one entry per SHEET on disk, while the graph also carries
        // the line-scoped ALIASES — `pencds_megaseadramon`, `pencme_metalgreymon`,
        // `pencnsp_metalgreymon` and `pencvb_metalgreymon` in this band. The roster count is the
        // right denominator for "every Digimon on disk is obtainable"; Appendix B's script reads
        // `roster.generated.json` and so counts the aliases too.
        XCTAssertEqual(inRange.count, 34)
        XCTAssertEqual(graph.nodes.filter {
            $0.stage == .perfect && String($0.displayName.prefix(1)).uppercased() == "M"
        }.count, 38)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The twenty-one this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoPerfectMIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && String($0.displayName.prefix(1)).uppercased() == "M" }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects M still orphaned: \(orphans)")
    }

    /// The Perfects in range this story deliberately did NOT wire onward, named rather than counted.
    /// All three have an in-edge already — Mametyramon is US-154's, MegaloGrowmon US-151's and
    /// MetalGreymon X US-155's — so none was ever an orphan, and all three sit on the dead-end
    /// ledger in `ChildSweepAToFTests` waiting for an Ultimate sweep.
    func testThePerfectsMLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && String($0.displayName.prefix(1)).uppercased() == "M" }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        XCTAssertEqual(leaves, ["mametyramon", "megalogrowmon", "metalgreymon_x"],
                       "the M Perfect leaves have moved without the ledger moving with them")
        for id in leaves {
            XCTAssertFalse(graph.parents(of: id).isEmpty,
                           "\(id) is an orphan rather than a leaf, so it WAS in this story's scope")
        }
    }

    // MARK: - AC2/AC4: the shape of every edge this story authored

    /// Each swept Perfect climbs by exactly one `isDefault` edge, gated on energy and on care but
    /// carrying no criteria — the shape every Perfect in this file has had since US-134, and the
    /// reading of "no edge is unconditional" that every rung below recorded. US-020 takes the
    /// `isDefault` edge exactly when nothing else qualifies, so a condition on one would be data
    /// that lies about how it is taken. What the criterion binds is the EARNED edges.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        for (perfect, _, ultimate) in swept {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.evolutions.count, 1, "\(perfect) is not a single climb")

            let climb = try XCTUnwrap(node.evolutions.first)
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
            XCTAssertEqual(edge.conditions.count, 2,
                           "\(parent) -> \(perfect) is not one HealthKit and one care criterion")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(parent) -> \(perfect) has an undiscoverable criterion")
            }
            XCTAssertEqual(edge.conditions.filter { $0.metric.hasPrefix("health.") }.count, 1)
            XCTAssertEqual(edge.conditions.filter { $0.metric.hasPrefix("care.") }.count, 1)
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has a single fallback")
            XCTAssertGreaterThan(edge.minEnergy, 0,
                                 "\(parent)'s junk edge would win the branch outright")
        }
    }

    /// **FIVE Champions came off the dead-end ledger, and ONE of the five needed a junk node that
    /// did not exist.** A leaf Champion has no fallback because it has no edges at all; the moment
    /// it gains an earned branch, `EvolutionCriteriaTests` requires an `isDefault` edge onto a junk
    /// Perfect of its OWN line. `diablomon` had no Perfect rung at all, so this story paid the same
    /// bill US-157 paid for `penc-sw` — see `testTheDiablomonJunkFloorIsAnAliasBecauseNoOrphanIsJunk`
    /// for why the payment is an alias rather than an unused sheet.
    func testTheFiveLeafChampionsGainedTheirLinesJunkFloor() throws {
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            // Two for four of them; Meicoomon is three, because it carries BOTH Meicrackmon.
            XCTAssertEqual(node.evolutions.count, parent == "meicoomon" ? 3 : 2,
                           "\(parent) is not its earned branches plus a fallback")
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

        // Four floors pre-dated this story; exactly one did not.
        let authoredFloors = junkFloors.map(\.junk).filter { graph.node(id: $0)?.line == "diablomon" }
        XCTAssertEqual(Set(authoredFloors), ["diablomon_gerbemon"])

        // The other fifteen Champions were ALREADY branching, so none needed a floor and none
        // touched one.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching.count, 15)
        for parent in alreadyBranching {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3,
                                        "\(parent) was a leaf after all, so it needed a floor")
        }
    }

    /// **THE FIRST JUNK FLOOR IN THE FILE THAT IS A LINE-SCOPED ALIAS, AND THAT IS A CLAIM ABOUT
    /// THE POOL RATHER THAN A SHORTCUT.** CatchMamemon, Karakurumon and Pandamon were each an unused
    /// sheet, so each also removed an orphan; by the time this story ran, not one of the Perfect
    /// sheets still orphaned was junk-flavoured. `diablomon_gerbemon` therefore draws the Gerbemon
    /// art under a scoped id — the `dmcv2_vademon` pattern — and removes no orphan, which is why
    /// `RosterTests`' alias list moves and `EvolutionCriteriaTests.junkIds` gains a scoped name for
    /// the first time.
    func testTheDiablomonJunkFloorIsAnAliasBecauseNoOrphanIsJunk() throws {
        let floor = try XCTUnwrap(graph.node(id: "diablomon_gerbemon"))
        XCTAssertEqual(floor.line, "diablomon")
        XCTAssertEqual(floor.stage, .perfect)
        XCTAssertEqual(floor.spriteFile, "Gerbemon")
        XCTAssertTrue(floor.evolutions.isEmpty, "a junk floor is a leaf until an Ultimate sweep")

        // An ALIAS: no roster entry of its own, and the plain id belongs to another line.
        XCTAssertNil(roster.entry(id: "diablomon_gerbemon"))
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gerbemon")).line, "dmc-v2")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gerbemon")).spriteFile, floor.spriteFile)

        XCTAssertTrue(try authoredComment(on: "diablomon_gerbemon").contains("FLAVOUR"),
                      "a junk floor must admit it is flavour rather than citation")
    }

    /// **`diablomon` GAINED A PERFECT RUNG AND AN ULTIMATE RUNG IN ONE STORY**, which is the bill
    /// US-158 wrote down: opening one without the other re-opens the gap that keeps a line's eggs
    /// unraisable. Five lines are left with no Perfect rung.
    func testDiablomonGainedBothOfItsMissingRungsAtOnce() throws {
        let perfects = graph.nodes.filter { $0.line == "diablomon" && $0.stage == .perfect }
        let ultimates = graph.nodes.filter { $0.line == "diablomon" && $0.stage == .ultimate }

        XCTAssertEqual(Set(perfects.map(\.id)),
                       ["meicrackmon", "meicrackmon_vicious", "diablomon_gerbemon"])
        XCTAssertEqual(Set(ultimates.map(\.id)), ["rasielmon", "raguelmon"])

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertFalse(linesWithAPerfect.subtracting(linesWithAnUltimate).contains("diablomon"))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["algomon"],
                       "US-161 took `vital` and `xros` off this list, for the same bill")
    }

    /// **MEICOOMON IS THE ONLY PARENT THIS PACK CAN DRAW FOR EITHER MEICRACKMON**, which is what
    /// forced `diablomon` open rather than either mode being rehomed. It carries both, on two
    /// energies, which is the distinct-energy rule; and the junk fall still wins for a neglected
    /// Digimon, proved through the engine in both directions rather than reasoned about.
    func testMeicoomonCarriesBothMeicrackmonAndStillFallsToJunkWhenNeglected() throws {
        let meicoomon = try XCTUnwrap(graph.node(id: "meicoomon"))
        XCTAssertEqual(meicoomon.line, "diablomon")

        let earned = meicoomon.evolutions.filter { !$0.isDefault }
        XCTAssertEqual(Set(earned.map(\.to)), ["meicrackmon", "meicrackmon_vicious"])
        XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, 2,
                       "the two modes share an energy, so one of them is dead data")

        for edge in earned {
            var totals = EnergyTotals()
            totals[try XCTUnwrap(edge.requiredEnergy)] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: meicoomon, stageEnergy: totals,
                                                dominant: edge.requiredEnergy, careMistakes: 0,
                                                battleWins: 40, conditions: context(for: edge)),
                edge.to)
        }

        XCTAssertEqual(
            EvolutionEngine.scheduledEvolutionTarget(
                for: meicoomon, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 9,
                battleWins: 0, stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
            "diablomon_gerbemon")
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

        // **WIZARMON IS EFFECTIVELY CLOSED, AND IT IS CLOSED BY ITS JUNK EDGE RATHER THAN BY ITS
        // ENERGIES.** Pumpmon took spirit in US-140, Fantomon stamina in US-158 and Mephismon takes
        // vitality here; the one type left is strength, which is what its fall to Darumamon already
        // asks for. Sharing would be legal — the Scumon arrangement — but a fourth earned branch on
        // this node would have to be argued rather than simply written, so the next `penc-nso`
        // Perfect should expect a different Champion.
        let wizarmon = try XCTUnwrap(graph.node(id: "wizarmon"))
        XCTAssertEqual(
            Set(wizarmon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
            [.spirit, .stamina, .vitality])
        XCTAssertEqual(wizarmon.evolutions.first(where: \.isDefault)?.requiredEnergy, .strength)
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
    /// UNREACHABLE rather than merely hard.
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

    /// No edge in the file crosses a line, still — the rule that decides every placement here.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// No new lines for twenty-seven new nodes — ten existing ones absorbed all of them, which is
    /// the AC's "a sweep must NOT produce dozens of one-node lines" met by opening none at all.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 105, "Manticoremon, both MegaloGrowmon and Dukemon, plus US-161's Rapidmon and SaintGalgomon")
        XCTAssertEqual(sizes["penc-nso"], 62,
                       "Mammon X, both Mephismon, Mummymon and Dinorexmon, plus US-161's Orochimon")
        XCTAssertEqual(sizes["diablomon"], 22,
                       "both Meicrackmon, the Gerbemon floor, Rasielmon and Raguelmon")
        XCTAssertEqual(sizes["dmc-v1"], 36, "Mamemon X, MetalGreymon Virus X and Monzaemon X, plus US-161's NeoDevimon")
        XCTAssertEqual(sizes["dmc-v3"], 52, "MarinBullmon, Ryugumon and MetalPhantomon")
        XCTAssertEqual(sizes["penc-ds"], 44, "MarinChimairamon and Mermaimon")
        XCTAssertEqual(sizes["dmc-v5"], 25, "MetalTyranomon V2 and MetalTyranomon X")
        XCTAssertEqual(sizes["wanyamon"], 29, "MachGaogamon, plus US-161's RizeGreymon and Ravmon")
        XCTAssertEqual(sizes["penc-nsp"], 39, "MegaSeadramon X, plus US-161's both Panjyamon")
        XCTAssertEqual(sizes["penc-me"], 63, "MetalMamemon X, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 10)
    }

    /// **Eight of the nine variants sit on their base form's line, and TWO of those eight sit on
    /// its own PARENT** — the strongest reading the variant rule has, and the one
    /// `AdultSweepEToGTests.testTheOneVariantSitsWithItsBaseForm` established. The ninth,
    /// MetalMamemon X, follows a cited parent instead: `dmc-v2` holds the plain MetalMamemon and a
    /// cited climb, but not one cited PARENT, so honouring the line would have meant inventing an
    /// arrow at both ends. That is the escape hatch
    /// `ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened.
    func testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent() throws {
        for (variant, base) in [("mamemon_x", "mamemon"),
                                ("mammon_x", "mammon"),
                                ("megaseadramon_x", "megaseadramon"),
                                ("megalogrowmon_orange", "megalogrowmon"),
                                ("megalogrowmon_x", "megalogrowmon"),
                                ("metalgreymon_virus_x", "metalgreymon_virus"),
                                ("metaltyranomon_v2", "metaltyranomon"),
                                ("metaltyranomon_x", "metaltyranomon"),
                                ("monzaemon_x", "monzaemon"),
                                ("mephismon_x", "mephismon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }

        // The five that took the base form's OWN Champion, which is what makes them free: no new
        // parent had to be argued at all.
        for (variant, base) in [("mammon_x", "mammon"),
                                ("megalogrowmon_orange", "megalogrowmon"),
                                ("metalgreymon_virus_x", "metalgreymon_virus"),
                                ("metaltyranomon_v2", "metaltyranomon"),
                                ("metaltyranomon_x", "metaltyranomon"),
                                ("monzaemon_x", "monzaemon")] {
            let shared = Set(graph.parents(of: variant).map(\.id))
            XCTAssertFalse(shared.isEmpty)
            XCTAssertTrue(shared.isSubset(of: Set(graph.parents(of: base).map(\.id))),
                          "\(variant) does not share a Champion with \(base)")
        }

        // And the one that could NOT sit with its base form, stated as the reason rather than as an
        // exception: `dmc-v2` has no Champion Wikimon names among MetalMamemon X's parents.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "metalmamemon")).line, "dmc-v2")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "metalmamemon_x")).line, "penc-me")
        XCTAssertEqual(Set(graph.parents(of: "metalmamemon_x").map(\.id)), ["thunderballmon"])
        XCTAssertTrue(try authoredComment(on: "metalmamemon_x").contains("FOLLOWS A CITED PARENT"),
                      "the one variant that left its base form's line does not say so")
    }

    /// **The fifteen placements that cost nothing above, restated as a check on the DATA rather than
    /// on the prose.** For each, the Champion below and the Ultimate above were on the chosen line
    /// BEFORE this story — which is exactly what "the intersection was non-empty" means, and the
    /// property a later reader can re-derive. Fifteen of twenty-one is the best ratio any Perfect
    /// sweep has managed, and the reason is cumulative: three sweeps' worth of Megas are in place.
    func testTheFifteenFreePlacementsPutTheChampionAndTheUltimateOnOneLine() throws {
        let free = swept.filter { !authoredUltimates.map(\.ultimate).contains($0.ultimate) }
        XCTAssertEqual(free.count, 15)

        for (perfect, parent, ultimate) in free {
            let line = try XCTUnwrap(graph.node(id: perfect)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line,
                           "\(parent) is not on \(perfect)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: ultimate)).line, line,
                           "\(ultimate) is not on \(perfect)'s line")
            XCTAssertGreaterThan(graph.parents(of: ultimate).count, 1,
                                 "\(ultimate) had no parent before this story, so it was not free")
        }

        // Two pairs of this story's Perfects share a climb, and in both cases the two are separate
        // NODES rather than two branches off one Champion, so there is no energy for them to
        // collide on: both MetalTyranomon variants take Mugendramon, and Manticoremon and
        // MegaloGrowmon Orange both take the Dukemon this story authored.
        XCTAssertEqual(swept.filter { $0.ultimate == "mugendramon" }.map(\.perfect),
                       ["metaltyranomon_v2", "metaltyranomon_x"])
        XCTAssertEqual(swept.filter { $0.ultimate == "dukemon" }.map(\.perfect),
                       ["manticoremon", "megalogrowmon_orange"])
        XCTAssertNotEqual(graph.parents(of: "metaltyranomon_v2").map(\.id),
                          graph.parents(of: "metaltyranomon_x").map(\.id))
        XCTAssertNotEqual(graph.parents(of: "manticoremon").map(\.id),
                          graph.parents(of: "megalogrowmon_orange").map(\.id))
    }

    /// **`tamers` GOT DUKEMON, which that line has been owed since US-151 opened its Perfect rung.**
    /// Growmon was the bolded parent of MegaloGrowmon Orange and was spent on Manticoremon instead,
    /// for a reason the node comment states: the Orange form has to hang off Growmon (Orange) under
    /// the variant rule, and every other reading of Manticoremon opens a Perfect rung on a line that
    /// has none. So one leaf Champion paid for two nodes.
    func testGrowmonWasSpentOnManticoremonSoThatDukemonCouldBeAuthoredAtAll() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "dukemon")).line, "tamers")
        XCTAssertEqual(Set(graph.parents(of: "growmon").map(\.id)),
                       Set(graph.parents(of: "growmon_orange").map(\.id)),
                       "the two Growmon no longer share a parent set, so US-152's pairing moved")

        // The rejected readings really would each have opened a rung — `algomon` still has none.
        // US-161 opened `vital`'s, over Tia Ludomon among others, so that half of the claim is
        // restated as what it was: at the time this story ran, taking Reppamon or Tia Ludomon
        // meant paying for a Perfect rung, a junk floor and a Mega. Manticoremon has NOT moved.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mimicmon")).line, "algomon")
        XCTAssertEqual(graph.nodes.filter { $0.line == "algomon" && $0.stage == .perfect }, [],
                       "`algomon` has a Perfect rung now, so Manticoremon had a cheaper reading")
        for id in ["reppamon", "tialudomon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "vital")
            XCTAssertFalse(try XCTUnwrap(graph.node(id: id)).evolutions.map(\.to)
                .contains("manticoremon"),
                           "Manticoremon was rehomed onto \(id) — then this story overpaid")
        }
        XCTAssertEqual(graph.parents(of: "manticoremon").map(\.id), ["growmon"])
        XCTAssertTrue(try authoredComment(on: "manticoremon").contains("Mimicmon"),
                      "the rejected `algomon` reading is not named")
    }

    // MARK: - The eggs this story promoted

    /// **`diablomon`'s WHOLE EGG LIST AT ONCE**, which is the shape US-158's four `wanyamon` eggs
    /// had one rung further up the bill: the line had neither a Perfect nor an Ultimate rung, so
    /// every thread on it stopped two short. Kera and Meicoo Digitama both hatch onto Kuramon, so
    /// opening the top of that one thread promoted both. `EggHatchingTests` moves with this.
    func testTheKeraAndMeicooDigitamaWerePromotedByOpeningDiablomon() throws {
        for id in ["kera_digitama", "meicoo_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) no longer reaches an Ultimate — `EggHatchingTests` moves with it")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "diablomon")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).evolutions.map(\.to), ["kuramon"])
        }

        // US-159's claim, restated where it still holds: no egg on a line that HAS a Perfect rung
        // is unraisable. This story did not weaken it — it took a whole line off the other side.
        let unraisableLines = Set(graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && !graph.reachesUltimate(from: $0.id) }
            .map(\.line))
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertTrue(unraisableLines.isDisjoint(with: linesWithAPerfect),
                      "an egg is unraisable on a line that HAS a Perfect rung — a sweep can fix it")
    }

    // MARK: - AC5/AC6: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to all twenty-seven new nodes — the junk floor
    /// separately, because it is an alias and so has no roster entry of its own.
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

        let floor = try XCTUnwrap(graph.node(id: "diablomon_gerbemon"))
        let sheet = try XCTUnwrap(
            SpriteSheetCache.shared.sheet(stage: floor.stage.rawValue, name: floor.spriteFile))
        XCTAssertEqual(sheet.kind, .stage)
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
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["diablomon_gerbemon"] {
            let line = try XCTUnwrap(graph.node(id: id)).line
            XCTAssertFalse(line.isEmpty, "\(id) has no line")
            XCTAssertTrue(known.contains(line), "\(id) is on the unknown line \(line)")
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) + ["diablomon_gerbemon"] {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation") || comment.contains("FLAVOUR"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }

        // The rejected and undrawable readings are written down too, so the story that revisits one
        // is told which arrow was considered and why it lost, rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "machgaogamon").contains("Mirage Gaogamon"),
                      "MachGaogamon's idle-only bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "marinbullmon").contains("Ariemon"),
                      "MarinBullmon's rejected bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "marinchimairamon").contains("Chimairamon"),
                      "the sheet MarinChimairamon is NOT a second copy of is not named")
        XCTAssertTrue(try authoredComment(on: "metalphantomon").contains("Fantomon"),
                      "MetalPhantomon's other bolded parent is not named")
        XCTAssertTrue(try authoredComment(on: "mummymon").contains("VenomVamdemon"),
                      "Mummymon's rejected climb is not named")
        XCTAssertTrue(try authoredComment(on: "raguelmon").contains("Ordinemon"),
                      "the Mega above Raguelmon that this pack cannot draw is not named")
    }

    /// **MEPHISMON X HAS NO DRAWABLE CITED PARENT ANYWHERE, AND THE COMMENT SAYS SO RATHER THAN
    /// IMPLYING ONE.** Wikimon gives it two `Evolves From`: Mephismon itself, a Perfect, and
    /// Velgrmon, which is Armor-Hybrid and off the ladder. That is a harder dead end than
    /// US-159's LadyDevimon X, which at least had Numemon X — so the parent is chosen on the line
    /// and on flavour, and the node admits it.
    func testMephismonXHadNoDrawableCitedParentAndSaysSo() throws {
        // Velgrmon is on disk and off the ladder — Armor-Hybrid has no `ladderIndex`, so the
        // validator's one-rung rule cannot place it — and it is not a node at all, which is what
        // makes it unusable as a parent rather than merely a bad one.
        XCTAssertEqual(try XCTUnwrap(roster.entry(id: "velgrmon")).stage, .armorHybrid)
        XCTAssertNil(graph.node(id: "velgrmon"))
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mephismon")).stage, .perfect)

        let comment = try authoredComment(on: "mephismon_x")
        XCTAssertTrue(comment.contains("NO DRAWABLE CITED PARENT"),
                      "the dead end this node sits in is not admitted")
        XCTAssertTrue(comment.contains("Velgrmon"))
        XCTAssertEqual(Set(graph.parents(of: "mephismon_x").map(\.id)), ["pencnso_devimon"])
    }

    // MARK: - The handover

    /// **The handover to US-161 onward, in the shape US-151 through US-159 established: a claim, not
    /// a note.** What the N-Z Perfect sweeps and the Ultimate ones inherit is five brand-new
    /// Ultimate leaves, FIVE lines with no Perfect rung rather than six, and a dead-end ledger four
    /// lower. `vital` is the biggest of the five and every one of its ten Champions is still a leaf,
    /// which makes it the cheapest rung left to open — LadyDevimon X and Boutmon are already pinned
    /// as its rehome candidates by US-157 and US-159.
    func testWhatThisSweepHandsToTheRestOfThePerfectRung() throws {
        for id in authoredUltimates.map(\.ultimate) {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) leads somewhere, which nothing at the top rung may")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).stage, .ultimate)
        }

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["algomon"],
                       "a line gained or lost its Perfect rung; the remaining sweeps' bill changed")

        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again — US-158 closed the last")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       67, "the dead-end ledger in `ChildSweepAToFTests` has moved")

        // `vital` was all leaves when this story ran, which was the claim behind "cheapest rung
        // left to open" — and US-161 took the advice: it branched Kokeshimon and Tia Ludomon and
        // left the other eight untouched. The claim FLIPS to that rather than dying.
        let vitalAdults = graph.nodes.filter { $0.line == "vital" && $0.stage == .adult }
        XCTAssertEqual(vitalAdults.count, 10)
        XCTAssertEqual(vitalAdults.filter { !$0.evolutions.isEmpty }.map(\.id).sorted(),
                       ["hookmon", "kokeshimon", "reppamon", "tialudomon"],
                       "`vital`'s branching Champions moved without this claim moving with them")
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// TWENTY-ONE Perfects plus FIVE Ultimates plus one junk floor, counted with Appendix B of the
    /// PRD over a regenerated `roster.generated.json`: **219 before, 193 after; the Perfect bucket
    /// falls 58 -> 37 and the Ultimate bucket 145 -> 140**. Twenty-six rather than twenty-seven,
    /// because `diablomon_gerbemon` is an alias and removes no orphan. Asserted rather than only
    /// noted, because the count is the one claim in `notes` a later reader cannot re-derive from
    /// the diff.
    func testTheTwentySixOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 21)
        XCTAssertEqual(authoredUltimates.count, 5)

        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertNil(roster.entry(id: "diablomon_gerbemon"),
                     "the junk floor gained a roster entry, so it removes an orphan after all")

        XCTAssertEqual(graph.nodes.count, 787, "709 before this story")

        // The buckets, re-derived off the graph rather than trusted from the notes.
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "126 before this story")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 108, "93 before this story")
    }

    /// Every Ultimate this story opened serves exactly the Perfects named here, so a parent hung on
    /// one later fails this rather than passing quietly — the `Set(graph.parents(of:))` equality
    /// shape every sweep since US-151 has established. Dukemon is the first in the series authored
    /// with TWO parents on purpose: both are `tamers` Perfects whose Wikimon pages name it.
    func testTheFiveUltimatesThisStoryOpenedServeExactlyTheNamedPerfects() throws {
        for (ultimate, parents, line) in authoredUltimates {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertEqual(node.line, line, "\(ultimate) is not on its Perfect's line")
            XCTAssertEqual(Set(graph.parents(of: ultimate).map(\.id)), parents,
                           "\(ultimate)'s parents changed without this claim changing with them")
        }
        XCTAssertEqual(Set(authoredUltimates.map(\.ultimate)).count, authoredUltimates.count)
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
    /// sleep disturbances, LITTLE sleep or LITTLE daylight, and a blanket "did everything right"
    /// context is the one thing that cannot take an `atMost`.
    ///
    /// Meicrackmon: Vicious Mode is why it also has to handle an `atLeast` on a care counter the
    /// shared context sets to zero: it asks for MANY sleep disturbances, the same shape US-159's
    /// Lucemon Falldown had — the only two edges in the file that reward the neglect every other
    /// edge punishes.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30
        var overfeeds = 0
        var disturbances = 0

        for condition in edge.conditions {
            switch (condition.knownMetric, condition.comparison) {
            case (.careTrainingSessions, .atMost): training = 0
            case (.careOverfeeds, .atMost): overfeeds = 0
            case (.careSleepDisturbances, .atMost): disturbances = 0
            case (.careSleepDisturbances, .atLeast): disturbances = Int(condition.value) + 1
            case (.some(let metric), .atMost) where metric.isHealthMetric:
                values[metric.rawValue] = 0
            default: break
            }
        }

        return ConditionContext(
            stageTotals: MetricTotals(values: values),
            trainingSessionsThisStage: training,
            overfeedsThisStage: overfeeds,
            sleepDisturbancesThisStage: disturbances,
            battlesLifetime: 40,
            battleWinRatioLifetime: 1.0)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-159 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
