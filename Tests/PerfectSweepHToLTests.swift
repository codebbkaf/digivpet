import XCTest

@testable import DigiVPet

/// US-159 — the sixteenth of Phase E's orphan sweeps and the third at the Perfect rung: the eleven
/// playable Perfect whose display name begins H-L that no device tree, Champion sweep or earlier
/// Perfect sweep reached.
///
/// **Eleven orphans, eleven nodes, and NINE of them hang off a leaf Champion** — the largest single
/// fall the dead-end ledger has taken. That is not luck: after seven Adult sweeps most Champions
/// ARE leaves, so the cheapest in-edge is nearly always one that also clears a debt. Every junk
/// floor those nine needed already existed (Locomon, Darumamon twice, CatchMamemon three times,
/// Karakurumon, Jyagamon twice), so `EvolutionCriteriaTests.junkIds` did not move for the second
/// story running. 90 -> 81.
///
/// **US-152's intersection closed on six of the eleven** — Hangyomon, Insekimon, LadyDevimon,
/// Lilamon, Lilimon X and Lucemon Falldown each landed between a Champion and an Ultimate that were
/// both already on the chosen line, and Lilamon cost nothing at either end. The other five bought
/// one Ultimate apiece.
///
/// **Two junk Champions gained an earned branch**, which is the Scumon arrangement US-133 recorded
/// and is what makes this sweep's egg promotion odd: Terrier Digitama reaches a Mega only by
/// falling to Numemon X first, because LadyDevimon X hangs off that fall.
///
/// **The rehome pins it leaves**: Hisyaryumon for `commandramon` and LadyDevimon X for `vital`.
/// Both took a second-choice line because their bolded or cited parent sits on a line with no
/// Perfect rung at all, and both say so in their own node comment.
final class PerfectSweepHToLTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The eleven orphaned Perfects this story wired, with the Champion that now reaches each and
    /// the Ultimate each now climbs into. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("hangyomon", "ebidramon", "vikemon"),
        ("hisyaryumon", "omekamon", "ouryumon"),
        ("insekimon", "icemon", "pencnso_boltmon"),
        ("jazarichmon", "jazardmon", "metallicdramon"),
        ("karatenmon", "igamon", "tengumon"),
        ("ladydevimon", "kyubimon", "beelzebumon"),
        ("ladydevimon_x", "numemon_x", "beelstarmon_x"),
        ("lavogaritamon", "lavorvomon", "volcanicdramon"),
        ("lilamon", "sunflowmon", "rosemon"),
        ("lilimon_x", "togemon_x", "rosemon"),
        ("lucemon_falldown", "pencnso_devimon", "venomvamdemon"),
    ]

    /// The five Ultimates this story authored, and the line each landed on. All five are leaves, as
    /// every Ultimate in this file is; none is on the dead-end ledger, which stops below the top
    /// rung.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        // US-161 hung RizeGreymon X under this one, off the Omekamon that also carries
        // Hisyaryumon — a cited climb on that page, and the escape hatch the variant rule opens
        // when the base form's line holds neither end. Named rather than the check being loosened
        // to a superset, the shape US-159 and US-160 established.
        ("ouryumon", ["hisyaryumon", "rizegreymon_x"], "penc-me"),
        ("metallicdramon", ["jazarichmon"], "tamers"),
        ("tengumon", ["karatenmon"], "wanyamon"),
        ("beelstarmon_x", ["ladydevimon_x"], "tamers"),
        ("volcanicdramon", ["lavogaritamon"], "penc-nso"),
    ]

    /// The nine Champions that were LEAVES before this story, and the junk Perfect each now falls
    /// to. **Every one of the nine floors already existed**, as in US-158 and unlike US-157, which
    /// had to author Pandamon for `penc-sw` before Hakubamon could branch at all.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("omekamon", "locomon"),
        ("icemon", "darumamon"),
        ("jazardmon", "catchmamemon"),
        ("igamon", "karakurumon"),
        ("kyubimon", "catchmamemon"),
        ("numemon_x", "catchmamemon"),
        ("lavorvomon", "darumamon"),
        ("sunflowmon", "jyagamon"),
        ("togemon_x", "jyagamon"),
    ]

    /// The shared "did everything right" context, US-151's through US-158's exactly.
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
    func testEveryPlayablePerfectHToLIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased())
        }
        // Twenty, not the twenty-one nodes the graph holds in this band: `Roster.bundled` reads
        // `Resources/roster.json`, one entry per SHEET on disk, while the graph also carries the
        // line-scoped ALIASES — `pencwg_lilimon` is the only one in this band. The roster count is
        // the right denominator for "every Digimon on disk is obtainable"; Appendix B's script
        // reads `roster.generated.json` and so counts the alias too.
        XCTAssertEqual(inRange.count, 20)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The eleven this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoPerfectHToLIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects H-L still orphaned: \(orphans)")
    }

    /// The Perfects in range this story deliberately did NOT wire onward, named rather than counted.
    /// Both are JUNK Perfects rather than orphans — Karakurumon is `wanyamon`'s floor and Huankunmon
    /// US-156's — so both have an in-edge and both sit on the dead-end ledger in
    /// `ChildSweepAToFTests` waiting for an Ultimate sweep.
    func testThePerfectsHToLLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("H"..."L").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        // US-164 wired Huankunmon and US-166 gave Karakurumon its climb to Kaguyamon, so there is no
        // H-L Perfect leaf left at all.
        XCTAssertEqual(leaves, [],
                       "the H-L Perfect leaves have moved without the ledger moving with them")
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
    /// that lies about how it is taken. What the criterion binds is the EARNED edges, and every
    /// earned edge this story authored is checked below.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        // **US-163 IS THE FIRST STORY TO FORK A PERFECT, AND THESE ARE THE ONES IT FORKED.** The
        // Ultimate sweep's in-edges come from this rung, so a Perfect that already had its climb
        // gained an EARNED branch beside it — a different `requiredEnergy`, two criteria, and the
        // climb untouched and still `isDefault`, which is the whole of what this test checks. Each
        // is NAMED with its new edge count rather than the count being loosened to a `>=`.
        // US-166, the I-M Ultimate sweep, took LadyDevimon to four (Lilithmon and Lilithmon X) and
        // Lucemon: Falldown Mode to three (Lucemon Satan and Lucemon X), forked Lilamon a second time
        // (Lotusmon, 2 -> 3), and gave Karatenmon its first branch (Kuzuhamon, 1 -> 2).
        let branchedByUS163: [String: Int] = ["insekimon": 2, "ladydevimon": 4, "lilamon": 4,
                                              "lucemon_falldown": 4, "karatenmon": 2,
                                              "hisyaryumon": 2, "lilimon_x": 2]
        for (perfect, _, ultimate) in swept {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.evolutions.count, branchedByUS163[perfect] ?? 1,
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

    /// **NINE Champions came off the dead-end ledger here — more than any story before it — and not
    /// one of them needed a new junk node.** A leaf Champion has no fallback because it has no edges
    /// at all; the moment it gains an earned branch, `EvolutionCriteriaTests` requires an
    /// `isDefault` edge onto a junk Perfect of its OWN line. Every one of the nine floors already
    /// existed, so `junkIds` did not move.
    func testTheNineLeafChampionsGainedTheirLinesExistingJunkFloor() throws {
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            // Omekamon carries THREE since US-161, which hung RizeGreymon X on it beside the
            // Hisyaryumon this story gave it — both cited on `penc-me`, both climbing Ouryumon.
            // Named rather than the claim being loosened to `>=`, the shape US-160 established.
            // US-162 hung Superstarmon on Omekamon as well, so it carries FOUR. Named exception
            // rather than a loosened `>=`, the shape US-160 established — and Omekamon is now full
            // in the sense that matters: three earned branches on three distinct energies.
            XCTAssertEqual(node.evolutions.count, parent == "omekamon" ? 4 : 2,
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

            // The claim that keeps this story as cheap as US-158: every floor pre-dated it.
            XCTAssertFalse(swept.map(\.perfect).contains(junk),
                           "\(junk) is one of this story's own nodes, so a floor WAS authored")
        }

        // The other two hung off a Champion that was ALREADY branching, so neither needed a floor
        // and neither touched one.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching, ["ebidramon", "pencnso_devimon"])
        for parent in alreadyBranching {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3,
                                        "\(parent) was a leaf after all, so it needed a floor")
        }
    }

    /// **TWO OF THE NINE LEAVES ARE JUNK CHAMPIONS, AND THAT IS DELIBERATE.** Numemon X is `tamers`'
    /// junk Champion (US-148) and is the ONLY parent this graph can offer LadyDevimon X — Wikimon's
    /// bolded one is LadyDevimon itself, a Perfect, and Velgrmon is Armor-Hybrid. A junk node with
    /// an earned branch is the Scumon arrangement US-133 recorded; what must hold is that the junk
    /// FALL still wins for a neglected Digimon and the earned branch still wins for a raised one,
    /// which is proved through the engine in both directions rather than reasoned about.
    func testNumemonXIsAJunkChampionThatStillFallsCorrectlyWhileOfferingLadyDevimonX() throws {
        let numemonX = try XCTUnwrap(graph.node(id: "numemon_x"))
        XCTAssertEqual(numemonX.line, "tamers")

        // Raised: the earned branch wins.
        let earned = try XCTUnwrap(numemonX.evolutions.first { $0.to == "ladydevimon_x" })
        var totals = EnergyTotals()
        totals[try XCTUnwrap(earned.requiredEnergy)] = earned.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: numemonX, stageEnergy: totals,
                                            dominant: earned.requiredEnergy, careMistakes: 0,
                                            battleWins: 40, conditions: context(for: earned)),
            "ladydevimon_x")

        // Neglected: it falls onward to CatchMamemon exactly as it did before this story.
        XCTAssertEqual(
            EvolutionEngine.scheduledEvolutionTarget(
                for: numemonX, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 9,
                battleWins: 0, stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
            "catchmamemon")
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

        // **EBIDRAMON IS FULL**, and this story is the one that filled it: US-139's Anomalocarimon
        // took vitality, US-157's Anomalocarimon X stamina, US-158's Gusokumon strength, and the
        // bolded Hangyomon arrow takes the spirit that was left. Four earned branches is the hard
        // ceiling — there are only four energy types — so this Champion can never branch again, and
        // a later sweep that wants a Deep Savers Perfect needs a different parent, not a fifth edge.
        let ebidramon = try XCTUnwrap(graph.node(id: "ebidramon"))
        XCTAssertEqual(
            Set(ebidramon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
            Set(EnergyType.allCases),
            "Ebidramon has an energy free again — then US-158's handover was wrong")
        XCTAssertEqual(ebidramon.evolutions.count, 5)

        // The two `palmon` flowers deliberately came off DIFFERENT Champions on different energies,
        // so no one node offers Lilamon and Lilimon X as a pair the engine cannot tell apart.
        XCTAssertNotEqual(graph.parents(of: "lilamon").map(\.id),
                          graph.parents(of: "lilimon_x").map(\.id))
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

    /// No new lines for sixteen new nodes — six existing ones absorbed all of them. A sweep must not
    /// produce dozens of one-node lines, and the way this one satisfies that is by opening none at
    /// all.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 123,
                       "Jazarichmon, LadyDevimon, LadyDevimon X and their two Megas" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["penc-nso"], 86,
                       "Insekimon, Lavogaritamon, Volcanicdramon and Lucemon Falldown" + ", plus US-160's five, plus US-161's Orochimon, plus US-163's seven Ultimates")
        XCTAssertEqual(sizes["penc-me"], 75, "Hisyaryumon and Ouryumon" + ", plus US-160's one, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas, plus US-163's four Ultimates")
        XCTAssertEqual(sizes["wanyamon"], 33, "Karatenmon and Tengumon" + ", plus US-160's one, plus US-161's RizeGreymon and Ravmon")
        XCTAssertEqual(sizes["palmon"], 32, "Lilamon and Lilimon X, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-ds"], 48, "Hangyomon" + ", plus US-160's two, plus US-163's one Ultimate")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 6)
    }

    /// **Every variant in this story landed on a line that already held its family**, which is the
    /// criteria's variant rule, and one of the two decided where its BASE FORM went rather than the
    /// other way round: Numemon X is the only cited parent for LadyDevimon X anywhere in this graph,
    /// so LadyDevimon had to go to `tamers` — not to the `penc-nso` its own Piemon citation would
    /// have suggested — for the pair to sit on one line. Lilimon X is the ordinary shape: it follows
    /// the plain Lilimon onto `palmon` and comes off Togemon X, which is the X-to-X pairing the page
    /// draws.
    func testTheVariantsLandedBesideTheirBaseForm() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "ladydevimon_x")).line,
                       try XCTUnwrap(graph.node(id: "ladydevimon")).line)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "ladydevimon")).line, "tamers")
        XCTAssertEqual(Set(graph.parents(of: "ladydevimon_x").map(\.id)), ["numemon_x"])

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lilimon_x")).line,
                       try XCTUnwrap(graph.node(id: "lilimon")).line)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lilimon")).line, "palmon")
        XCTAssertEqual(Set(graph.parents(of: "lilimon_x").map(\.id)), ["togemon_x"])
        XCTAssertTrue(graph.parents(of: "lilimon").map(\.id).contains("togemon"),
                      "the X is not reached by the X of a Champion its base form is reached by")
    }

    /// **The six placements that cost nothing above, restated as a check on the DATA rather than on
    /// the prose.** For each, the Champion below and the Ultimate above were on the chosen line
    /// BEFORE this story — which is exactly what "the intersection was non-empty" means, and the
    /// property a later reader can re-derive.
    func testTheSixFreePlacementsPutTheChampionAndTheUltimateOnOneLine() throws {
        let free = swept.filter { !authoredUltimates.map(\.ultimate).contains($0.ultimate) }
        XCTAssertEqual(free.count, 6)

        for (perfect, parent, ultimate) in free {
            let line = try XCTUnwrap(graph.node(id: perfect)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line,
                           "\(parent) is not on \(perfect)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: ultimate)).line, line,
                           "\(ultimate) is not on \(perfect)'s line")
            XCTAssertGreaterThan(graph.parents(of: ultimate).count, 1,
                                 "\(ultimate) had no parent before this story, so it was not free")
        }

        // Lilamon is the ONE that cost nothing at either end — both its arrows are bolded and both
        // Sunflowmon and Rosemon were already on `palmon`. It is also the only place two of this
        // story's Perfects share a climb, and they are two separate nodes rather than two branches
        // off one, so there is no energy for them to collide on.
        XCTAssertEqual(swept.filter { $0.ultimate == "rosemon" }.map(\.perfect),
                       ["lilamon", "lilimon_x"])
        XCTAssertEqual(Set(graph.parents(of: "rosemon").map(\.id)),
                       ["lilimon", "lilamon", "lilimon_x"])
    }

    // MARK: - The two rehome pins this story leaves

    /// **HISYARYUMON'S BOLDED PARENT IS ON A LINE WITH NO PERFECT RUNG, SO IT TOOK THE CITED ONE
    /// INSTEAD — AND SAYS SO.** Wikimon bolds Ginryumon and Ryudamon, both `commandramon`; taking
    /// that reading would have cost a junk Perfect floor and a `junkIds` entry on top of this node,
    /// and left all three stranded, because Ryudamon and Ginryumon are already on
    /// `EvolutionCriteriaTests`' stranded list. The arrow rests on Omekamon, which the same Wikimon
    /// clause names, and Hisyaryumon is pinned as `commandramon`'s rehome candidate — the shape
    /// US-153 and US-157 used for Kinkakumon on `penc-sw`.
    func testHisyaryumonIsPinnedAsCommandramonsRehomeCandidate() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "hisyaryumon")).line, "penc-me")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "ginryumon")).line, "commandramon")

        let comment = try authoredComment(on: "hisyaryumon")
        XCTAssertTrue(comment.contains("NOT THE BOLDED PARENT"),
                      "the bolded arrow this node did not take is not admitted")
        XCTAssertTrue(comment.contains("REHOME CANDIDATE"), "the rehome pin is missing")
        XCTAssertTrue(comment.contains("Ginryumon"))

        // **US-162 OPENED `commandramon`'s PERFECT RUNG**, over the very Ginryumon this pin names
        // — Triceramon X, with SkullBaluchimon beside it over Damemon — so the pin is now a live
        // job for an Ultimate sweep rather than a waiting one. Same claim, other side: what is
        // checked is that Hisyaryumon did NOT quietly move there with it.
        XCTAssertFalse(graph.nodes.filter { $0.line == "commandramon" && $0.stage == .perfect }
            .isEmpty, "`commandramon` lost the Perfect rung US-162 opened")
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "ginryumon")).evolutions.map(\.to)
            .contains("hisyaryumon"), "Hisyaryumon was rehomed — then this whole pin wants rewriting")
    }

    /// **LADYDEVIMON X IS THE SAME SHAPE ONE LINE OVER.** Mantaraymon X is the page's other drawable
    /// parent and is on `vital`, which has no Perfect rung either, so the arrow rests on the
    /// Numemon X that `tamers` already had. Boutmon has been `vital`'s pinned rehome candidate since
    /// US-157; LadyDevimon X joins it.
    func testLadyDevimonXIsPinnedAsVitalsRehomeCandidate() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mantaraymon_x")).line, "vital")

        let comment = try authoredComment(on: "ladydevimon_x")
        XCTAssertTrue(comment.contains("Mantaraymon"), "the rejected `vital` reading is not named")
        XCTAssertTrue(comment.contains("rehome"), "the rehome pin is missing")

        // US-161 opened `vital`'s Perfect rung — Oboromon over Kokeshimon and RaijiLudomon over
        // Tia Ludomon, with Zanbamon and Bryweludramon above them — so the pin is LIVE rather than
        // waiting: LadyDevimon X can be rehomed onto Mantaraymon X the day a sweep wants it. What
        // the check pins now is that it has NOT been moved silently, and that Boutmon has not gone
        // with it either.
        XCTAssertFalse(graph.nodes.filter { $0.line == "vital" && $0.stage == .perfect }.isEmpty,
                       "`vital` lost the Perfect rung US-161 opened")
        XCTAssertEqual(graph.parents(of: "ladydevimon_x").map(\.id), ["numemon_x"],
                       "LadyDevimon X was rehomed — say which Champion has it now")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "boutmon")).line, "penc-me")
    }

    /// **LUCEMON FALLDOWN'S CANONICAL ARROW IS FORBIDDEN BY THE LADDER, NOT BY THE PACK.** Wikimon's
    /// sole bolded `Evolves From` is Lucemon, which is a CHILD — a Child cannot reach a Perfect in
    /// one rung, and `GraphValidationError.invalidStageTransition` refuses the edge. So this is the
    /// first node in the series whose bolded parent is undrawable for a REASON OF SHAPE rather than
    /// of art, and the comment says so rather than quietly picking a Champion.
    func testLucemonFalldownCouldNotTakeTheLucemonArrowBecauseLucemonIsAChild() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lucemon")).stage, .child)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lucemon")).line, "dmc-v3")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lucemon_falldown")).line, "penc-nso")
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "lucemon")).evolutions.map(\.to)
            .contains("lucemon_falldown"),
                       "a Child reaches a Perfect — the validator should have refused this")

        let comment = try authoredComment(on: "lucemon_falldown")
        XCTAssertTrue(comment.contains("CHILD"), "the reason the bolded arrow is undrawable is not said")
        XCTAssertTrue(comment.contains("Ogudomon"), "the bolded climb left for a later sweep is not named")

        // US-167, the N-R Ultimate sweep, paid that debt: Ogudomon is wired now, hung on Mephismon
        // — a Demon Lord of the Nightmare Soldiers line, not off Lucemon Falldown Mode itself.
        XCTAssertNotNil(roster.entry(id: "ogudomon"))
        XCTAssertEqual(graph.parents(of: "ogudomon").map(\.id), ["mephismon"],
                       "Ogudomon's Demon Lord parent changed without this claim moving with it")
    }

    // MARK: - The eggs this story promoted

    /// **BOTH PROMOTIONS ARE `tamers` AND BOTH ARE MIDDLE-OF-THE-THREAD**, which is the only kind
    /// left: `MainScreenModel.startingDigitamaId` filters on `reachesUltimate`, and every line that
    /// has a Perfect rung already has an Ultimate rung over it since US-158. Terrier's is the odd
    /// one — Terriermon's ONLY onward edge is the junk fall to Numemon X, so that egg reaches a Mega
    /// only by being neglected first. Pinned because `EggHatchingTests` moves with it.
    func testTheRenaAndTerrierDigitamaWerePromotedByTheLadyDevimonPair() throws {
        for id in ["rena_digitama", "terrier_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) no longer reaches an Ultimate — `EggHatchingTests` moves with it")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "tamers")
        }

        // The threads, rung by rung, so a break anywhere fails here rather than in the egg list.
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "renamon")).evolutions.map(\.to)
            .contains("kyubimon"))
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kyubimon")).evolutions.map(\.to),
                       ["ladydevimon", "catchmamemon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "terriermon")).evolutions.map(\.to).last,
                       "numemon_x",
                       "Terriermon's junk fall is the whole of its route to a Mega")

        // V Digitama is the only egg left on a line WITH an Ultimate rung that still cannot reach
        // one... except it is not: `adventure02` has no Perfect rung at all, and neither has any
        // other line still carrying an unraisable egg. So this is the LAST promotion a Perfect
        // sweep can make, and the claim is stated as that rather than as a list.
        let unraisableLines = Set(graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && !graph.reachesUltimate(from: $0.id) }
            .map(\.line))
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertTrue(unraisableLines.isDisjoint(with: linesWithAPerfect),
                      "an egg is unraisable on a line that HAS a Perfect rung — a sweep can fix it")
    }

    // MARK: - AC5/AC6: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to all sixteen new nodes.
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

        // The rejected readings are written down too, so the story that revisits one is told which
        // arrow was considered and why it lost, rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "hangyomon").contains("Neptunemon"),
                      "Hangyomon's undrawable bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "insekimon").contains("Gottsumon"),
                      "Insekimon's undrawable bolded parent is not named")
        XCTAssertTrue(try authoredComment(on: "jazarichmon").contains("Hououmon"),
                      "Jazarichmon's rejected `penc-wg` reading is not named")
        XCTAssertTrue(try authoredComment(on: "karatenmon").contains("Peckmon"),
                      "Karatenmon's rejected `tamers` reading is not named")
        XCTAssertTrue(try authoredComment(on: "ladydevimon").contains("Piemon"),
                      "LadyDevimon's rejected `penc-nso` reading is not named")
        XCTAssertTrue(try authoredComment(on: "lavogaritamon").contains("Ancient Volcamon"),
                      "Lavogaritamon's rejected `wanyamon` climb is not named")
        XCTAssertTrue(try authoredComment(on: "lilimon_x").contains("Rosemon (X-Antibody)"),
                      "Lilimon X's undrawable bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "beelstarmon_x").contains("US-158"),
                      "the reason this sheet waited a story is not written down")
    }

    // MARK: - The handover

    /// **The handover to US-160 onward, in the shape US-151 through US-158 established: a claim, not
    /// a note.** What the M-Z Perfect sweeps and the Ultimate ones inherit is five brand-new
    /// Ultimate leaves, the SAME six lines with no Perfect rung, a dead-end ledger nine lower, and a
    /// file in which no egg on a line with a Perfect rung is unraisable any more.
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

        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again — US-158 closed the last")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       74, "the dead-end ledger in `ChildSweepAToFTests` has moved")
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// ELEVEN Perfects plus FIVE Ultimates, counted with Appendix B of the PRD over a regenerated
    /// `roster.generated.json`: **235 before, 219 after; the Perfect bucket falls 69 -> 58 and the
    /// Ultimate bucket 150 -> 145**, because every Ultimate this story opened was an orphan too.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later reader
    /// cannot re-derive from the diff.
    func testTheSixteenOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 11)
        XCTAssertEqual(authoredUltimates.count, 5)

        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 931, "693 before this story")

        // The buckets, re-derived off the graph rather than trusted from the notes.
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "115 before this story")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 236, "88 before this story, 138 after US-163")
    }

    /// Every Ultimate this story opened serves exactly one Perfect, so a second parent hung on one
    /// later fails this rather than passing quietly — the `Set(graph.parents(of:))` equality shape
    /// every sweep since US-151 has established.
    func testTheFiveUltimatesThisStoryOpenedEachServeExactlyOneOfItsPerfects() throws {
        for (ultimate, parents, line) in authoredUltimates {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertEqual(node.line, line, "\(ultimate) is not on its Perfect's line")
            XCTAssertEqual(Set(graph.parents(of: ultimate).map(\.id)), parents,
                           "\(ultimate)'s parents changed without this claim changing with them")
        }

        // The ONE climb two of this story's Perfects share is Rosemon, which this story did not
        // author — so none of the five above is ambiguous, and the shared one is checked in
        // `testTheSixFreePlacementsPutTheChampionAndTheUltimateOnOneLine` instead.
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
    /// sleep disturbances or LITTLE sleep, and a blanket "did everything right" context is the one
    /// thing that cannot take an `atMost`.
    ///
    /// Lucemon Falldown is why it also has to handle an `atLeast` on a care counter that the shared
    /// context sets to zero: its second criterion asks for MANY sleep disturbances, which is the
    /// only edge in the file that rewards the neglect every other edge punishes.
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
    /// helper US-144 through US-158 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
