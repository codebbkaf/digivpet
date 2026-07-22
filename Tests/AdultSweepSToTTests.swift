import XCTest

@testable import DigiVPet

/// US-155 — the twelfth of Phase E's orphan sweeps and the fifth at the Adult rung: the five
/// playable Champions whose display name begins S-T that no device tree and no Child sweep reached.
///
/// **The scope reading is US-151's through US-154's.** The criteria ask for coverage of "every
/// remaining orphan at stage Adult whose displayName starts with S-T", so the twenty Champions in
/// this range that US-149 and US-150 left as LEAVES are not in scope — they have an in-edge and are
/// therefore not orphans. They stay in `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreThe
/// OnesTheSweepsHaveOpened`, and the Perfect sweeps from US-157 on are what pays them off.
///
/// **Five, not the thirty the PRD estimated.** The estimate was taken when the Adult rung held 168
/// orphans; eleven device trees, three Child sweeps and four Adult sweeps later the whole rung holds
/// 10, of which five fall in S-T. The range is derived from the roster here rather than from a list,
/// so the claim is checkable rather than asserted.
///
/// **What it costs one rung up: ONE Perfect, and every other arrow was already on the file.** Four
/// of the five landed on a line that already held both the Rookie below and the Perfect above —
/// the US-152 rule of intersecting `Evolves From` AND `Evolves To` before choosing a line, which
/// here paid off four times out of five because the pairs are unusually tidy: Muchomon and
/// Megadramon are both `dmc-v4`, Bakumon and Mammon are both `penc-nso` and both cited to *Digimon
/// World 2*, DORUmon and Grademon are both `tamers` off *Digital Monster X Ver.3*, and Agumon and
/// Mamemon are both `dmc-v1` off *Digital Monster Ver. 1*. Only Tyranomon X had no such pair, and
/// Metal Greymon X cost one node rather than two because `dmc-v3` has had Etemon as its junk floor
/// since US-133.
final class AdultSweepSToTTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The five orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, perfect: String)] = [
        ("saberdramon", "muchomon", "megadramon"),
        ("shimaunimon", "bakumon", "mammon"),
        ("siesamon_x", "dorumon", "grademon"),
        ("tyrannomon", "agumon", "mamemon"),
        ("tyrannomon_x", "agumon_x", "metalgreymon_x"),
    ]

    /// The one Perfect this story authored, and the one Champion it was authored for. It is a leaf
    /// until the Ultimate sweeps, and it is on the ledger in `ChildSweepAToFTests`.
    private let authoredPerfects: [(perfect: String, parents: Set<String>)] = [
        ("metalgreymon_x", ["tyrannomon_x"]),
    ]

    /// The junk Perfect each of the five lines already had, and which Champion falls to it. Nothing
    /// here is new: `greatkingscumon` is US-142's, `darumamon` US-140's, `catchmamemon` US-151's,
    /// `blackkingnumemon` and `etemon` are US-133's.
    private let junkFloors: [(adult: String, junk: String)] = [
        ("saberdramon", "greatkingscumon"),
        ("shimaunimon", "darumamon"),
        ("siesamon_x", "catchmamemon"),
        ("tyrannomon", "blackkingnumemon"),
        ("tyrannomon_x", "etemon"),
    ]

    /// The shared "did everything right" context, US-151's through US-154's exactly.
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
    func testEveryPlayableAdultSToTIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("S"..."T").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 36)

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
    func testNoAdultSToTIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("S"..."T").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Adults S-T still orphaned: \(orphans)")
    }

    /// The twenty in range that this story deliberately did NOT wire onward, named rather than
    /// counted. They are leaves, not orphans, and every one of them is on the dead-end ledger; if a
    /// later story wires one, it belongs there and here, not silently in one place.
    func testTheAdultsSToTThisStoryLeftAsLeavesAreTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("S"..."T").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        XCTAssertEqual(leaves,
                       ["sandyanmamon", "sangloupmon", "seadramon_x", "siesamon",
                        // Tailmon X left this list in US-157, which gave it Angewomon X.
                        // Starmon left in US-158 (DarkSuperstarmon), and Sunflowmon and Togemon X
                        // in US-159 — the first for Lilamon, the second for Lilimon X, which are
                        // the two `palmon` flowers that sweep put on one line and two energies.
                        // US-161 took TWO more, and both opened a line's Perfect rung: Shoutmon
                        // King carries both OmegaShoutmon on `xros`, and Tia Ludomon carries
                        // RaijiLudomon on `vital` — its bolded parent, and the only line either
                        // of that Digimon's drawable parents sits on.
                        "sorcerymon", "soulmon", "targetmon",
                        "tenkomon", "tobiumon", "tobucatmon", "tortamon",
                        "troopmon", "tsuchidarumon", "tylomon_x"].sorted(),
                       "the S-T leaves have moved without the ledger moving with them")

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
            // Two when this story wrote it. ShimaUnimon is three since US-160 hung Mammon X
            // beside the Mammon it already carried — the variant rule, which puts an X form on
            // its base form's own parent — so it is named rather than the count being loosened.
            XCTAssertEqual(node.evolutions.count, adult == "shimaunimon" ? 3 : 2,
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

    /// Every fallback is a junk Perfect that already existed on the Champion's own line — the one
    /// Perfect this story DID author is an earned branch, not a floor.
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

    /// **The one Perfect this story opened, and the four occasions it did not have to.** Metal
    /// Greymon X was authored for exactly one Champion, so a second parent hung here later fails
    /// this rather than passing quietly — the `Set(graph.parents(of:))` equality shape US-151,
    /// US-152 and US-154 established. Greymon X is the obvious second parent and is deliberately
    /// NOT drawn: it is a dead end on the ledger, and the Perfect sweeps own it.
    func testTheOnePerfectThisStoryOpenedServesExactlyOneOfItsChampions() throws {
        for (perfect, parents) in authoredPerfects {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertEqual(node.line, "dmc-v3", "\(perfect) is not on Agumon X's line")
            XCTAssertTrue(node.evolutions.isEmpty,
                          "\(perfect) leads somewhere, so the dead-end ledger has to move too")
            XCTAssertEqual(Set(graph.parents(of: perfect).map(\.id)), parents,
                           "\(perfect)'s parents changed without this claim changing with them")
        }

        XCTAssertTrue(try XCTUnwrap(graph.node(id: "greymon_x")).evolutions.isEmpty,
                      "Greymon X was wired onward — say which arrow, and move the ledger")

        // And the four that cost nothing: each landed on a Perfect that had a parent before this
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

    /// **Three Rookies are now FULL, and this is where that is written down.** `EvolutionEngine`
    /// picks on the dominant energy first, so two branches out of one node sharing an energy would
    /// make the second dead data — four energy types is a hard ceiling on earned branches. Agumon,
    /// Bakumon and Muchomon each spent their last energy here, which is more Rookies closed in one
    /// story than any sweep before it. No later sweep can hang a fifth branch on any of the three:
    /// it must find another parent.
    func testTheThreeRookiesThisStoryFilledHaveAnEnergyForEveryEarnedBranch() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }

        for id in ["agumon", "bakumon", "muchomon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(Set(node.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                           Set(EnergyType.allCases), "\(id) has an energy left after all")
            XCTAssertEqual(node.evolutions.count, 5,
                           "five is the ceiling `EvolutionCriteriaTests` sets")
        }

        // DORUmon and Agumon X are two branches short of the ceiling, said out loud so the next
        // sweep prices a branch off this list rather than discovering the ceiling as a failure.
        for id in ["dorumon", "agumon_x"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).evolutions.filter { !$0.isDefault }.count,
                           2, "\(id) is not the two branches this story left it")
        }
    }

    /// **Agumon X's new branch takes the energy nothing else on the node uses, and the branch it
    /// already had is untouched.** Vitality was free — Greymon X has strength, and so does the junk
    /// Scumon edge, which is the Scumon arrangement US-133 recorded. Proved through the engine on
    /// all three paths rather than reasoned about, because `evolutionTarget` matches on the
    /// DOMINANT energy: a vitality Agumon X that earned nothing matches no edge at all, and it is
    /// `scheduledEvolutionTarget` — the path the app actually takes — that falls it to junk.
    func testAgumonXReachesTyrannomonXOnVitalityWithoutDisturbingGreymonX() throws {
        let agumonX = try XCTUnwrap(graph.node(id: "agumon_x"))
        let earned = try XCTUnwrap(agumonX.evolutions.first { $0.to == "tyrannomon_x" })
        XCTAssertEqual(earned.requiredEnergy, .vitality)

        var vitality = EnergyTotals()
        vitality[.vitality] = earned.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: agumonX, stageEnergy: vitality, dominant: .vitality,
                                            careMistakes: 0, battleWins: 40,
                                            conditions: context(for: earned)),
            "tyrannomon_x", "a well-raised vitality Agumon X does not reach Tyrannomon X")

        // The branch that was already there still wins on its own energy.
        let greymonX = try XCTUnwrap(agumonX.evolutions.first { $0.to == "greymon_x" })
        var strength = EnergyTotals()
        strength[.strength] = greymonX.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: agumonX, stageEnergy: strength, dominant: .strength,
                                            careMistakes: 0, battleWins: 40,
                                            conditions: context(for: greymonX)),
            "greymon_x", "the new branch displaced the one Agumon X already had")

        // And a neglected one still falls to Scumon, whatever it was leaning towards.
        let junk = try XCTUnwrap(agumonX.evolutions.first(where: \.isDefault))
        XCTAssertEqual(junk.to, "scumon")
        for dominant in [EnergyType.vitality, .strength] {
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: agumonX, stageEnergy: EnergyTotals(), dominant: dominant,
                    careMistakes: 9, battleWins: 0,
                    stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                "scumon", "a neglected \(dominant) Agumon X does not fall to Scumon")
        }
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

    /// No new lines for six new nodes: two onto `dmc-v3`, one each onto `dmc-v1`, `dmc-v4`,
    /// `penc-nso` and `tamers`. A sweep must not produce dozens of one-node lines, and the way this
    /// one satisfies that is by opening none at all — five lines, five different threads, and every
    /// node hung between two that were already there.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["dmc-v1"], 36, "Tyrannomon, plus US-157's Chimairamon and Millenniumon" + ", plus US-160's three, plus US-161's NeoDevimon")
        XCTAssertEqual(sizes["dmc-v3"], 51, "Tyrannomon X and MetalGreymon X" + ", plus US-160's three")
        XCTAssertEqual(sizes["dmc-v4"], 29, "Saberdramon, plus US-156's Xiquemon and Huankunmon")
        XCTAssertEqual(sizes["penc-nso"], 59, "ShimaUnimon, plus US-157's Archnemon and BlueMeramon, plus US-158's three, plus US-159's four" + ", plus US-160's five, plus US-161's Orochimon")
        XCTAssertEqual(sizes["tamers"], 105, "Siesamon X, plus US-156's two and US-157's eight, plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.adult)?.line }).count, 5)
    }

    /// **The two X-Antibody Champions did NOT both go to `tamers`, and the reason is the citation
    /// rather than the suffix.** US-154's rule was that an X variant follows the X thread; what
    /// actually decides is which Rookie Wikimon draws it from. Siesamon X comes from DORUmon on
    /// `tamers`, so it lands there beside every other X Digimon and away from the base Siesamon on
    /// `algomon`. Tyranomon X comes from Agumon (X-Antibody), which US-148 put on `dmc-v3`, so it
    /// lands one line over from the base Tyranomon this same story put on `dmc-v1` — the two
    /// Agumon, the two Tyranomon, on the two lines their own devices drew.
    func testTheTwoXAntibodyChampionsFollowedTheirCitedRookieRatherThanTheirBaseForm() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "siesamon_x")).line, "tamers")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "dorumon")).line, "tamers")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "siesamon")).line, "algomon",
                       "the base Siesamon moved, so the variant's placement wants re-arguing")

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "tyrannomon_x")).line, "dmc-v3")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "agumon_x")).line, "dmc-v3")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "tyrannomon")).line, "dmc-v1")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "agumon")).line, "dmc-v1")

        XCTAssertEqual(swept.map(\.adult).filter { $0.hasSuffix("_x") }.sorted(),
                       ["siesamon_x", "tyrannomon_x"],
                       "an X-Antibody Champion appeared that this claim does not account for")
    }

    /// **The pairing that made four of the five free, restated as a check on the DATA rather than
    /// on the prose.** For each of the four, the Rookie below and the Perfect above were both on
    /// the chosen line BEFORE this story — which is exactly what "the intersection was non-empty"
    /// means, and the property a later reader can re-derive.
    func testTheFourFreePlacementsPutTheRookieAndThePerfectOnOneLine() throws {
        for (adult, parent, perfect) in swept where perfect != "metalgreymon_x" {
            let line = try XCTUnwrap(graph.node(id: adult)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line,
                           "\(parent) is not on \(adult)'s line")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: perfect)).line, line,
                           "\(perfect) is not on \(adult)'s line")
            XCTAssertGreaterThan(graph.parents(of: perfect).count, 1,
                                 "\(perfect) had no parent before this story, so it was not free")
        }

        // Tyranomon X is the fifth, and the one where the intersection really was empty: every
        // other Perfect its page names is on a line Agumon X cannot reach, or has no sheet.
        for id in ["mametyramon", "metaltyranomon", "ex-tyranomon"] {
            XCTAssertNotEqual(try XCTUnwrap(graph.node(id: id)).line, "dmc-v3",
                              "\(id) is on Tyrannomon X's line now, so the new Perfect was avoidable")
        }
        for id in ["yatagaramon_2006"] {
            XCTAssertNil(graph.node(id: id),
                         "\(id) is wired now — Tyrannomon X had a cheaper arrow after all")
        }
        // MetalTyranomon X was the other half of that claim and US-160 wired it — but NOT on
        // `dmc-v3`, so the intersection this story reported really was empty. The M sweep put it
        // on `dmc-v5` under Cyclomon, the plain MetalTyranomon's own second parent, which is the
        // variant rule rather than a cheaper arrow Tyrannomon X could have taken.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "metaltyranomon_x")).line, "dmc-v5")
        XCTAssertEqual(graph.parents(of: "metaltyranomon_x").map(\.id), ["cyclomon"])
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to the new Perfect as well as the five Champions.
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
        XCTAssertTrue(try authoredComment(on: "saberdramon").contains("Vamdemon"),
                      "Saberdramon's rejected `penc-nso` reading is not named")
        XCTAssertTrue(try authoredComment(on: "shimaunimon").contains("Asuramon"),
                      "ShimaUnimon's rejected `penc-nsp` reading is not named")
        XCTAssertTrue(try authoredComment(on: "tyrannomon_x").contains("Herissmon"),
                      "Tyrannomon X's rejected `penc-vb` reading is not named")
    }

    /// **The handover to US-156, FLIPPED now that US-156 has honoured it** — the shape US-152
    /// established when it wired US-151's FlareLizamon: the same fact, from the other side, still
    /// failing if anybody moves it. The five Champions this story handed on are all wired, and the
    /// piece of advice that came with them was taken as given: Gammamon was full, so WezenGammamon
    /// hangs off `pencvb_gabumon`, the second parent US-153 found on the same line.
    func testTheFiveChampionsHandedToUS156AreWiredOnTheAdviceThisStoryGave() throws {
        for id in ["v-dramon_black", "wezengammamon", "xv-mon_black", "xiquemon", "youkomon"] {
            XCTAssertNotNil(roster.entry(id: id), "\(id) is on disk, which is why it was owed")
            let node = try XCTUnwrap(graph.node(id: id), "\(id) is US-156's and is still unwired")
            XCTAssertFalse(graph.parents(of: id).isEmpty, "\(id) has no in-edge")
            XCTAssertFalse(node.evolutions.isEmpty, "\(id) leads nowhere")
        }
        // The advice was that Gammamon was full and Gabumon had to carry WezenGammamon. US-156
        // checked it rather than inheriting it: Gammamon had vitality free all along, so the
        // bolded arrow was drawn and Gabumon kept its energy. Both halves are pinned.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gammamon")).evolutions.count, 5,
                       "Gammamon is at the ceiling since US-156 spent its vitality")
        XCTAssertEqual(graph.parents(of: "wezengammamon").map(\.id), ["gammamon"],
                       "WezenGammamon moved off the bolded parent US-156 found free")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "pencvb_gabumon"))
                        .evolutions.filter { !$0.isDefault }.count, 2,
                       "Gabumon spent an energy after all — it was left free on purpose")
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// FIVE Champions plus ONE Perfect, counted with Appendix B of the PRD over a regenerated
    /// `roster.generated.json`: 300 before, 294 after; the Adult bucket falls 10 -> 5 and the
    /// Perfect bucket 108 -> 107, because the Perfect this story opened was an orphan too.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later
    /// reader cannot re-derive from the diff.
    func testTheSixOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 5)
        XCTAssertEqual(authoredPerfects.count, 1)

        for id in swept.map(\.adult) + authoredPerfects.map(\.perfect) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 760,
                       "629 before this story, 635 after it, 672 after US-157, 693 after US-158, 709 after US-159, 736 after US-160, 760 after US-161")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because two of this story's edges ask for FEW overfeeds or FEW
    /// sleep disturbances and a blanket "did everything right" context is the one thing that cannot
    /// take an `atMost`.
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
    /// helper US-144 through US-154 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
