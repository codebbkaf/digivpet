import XCTest

@testable import DigiVPet

/// US-165 — the twenty-second of Phase E's orphan sweeps and **the third at the TOP rung**: the
/// fourteen playable Ultimate whose display name begins E-H that no device tree and no earlier sweep
/// reached, and that no Jogress recipe already reaches. The Ultimate bucket 80 -> 66.
///
/// **AN ULTIMATE SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE**, exactly as US-163/US-164 recorded:
/// the rung is terminal, so there is no rung above to open, no junk floor to invent
/// (`EvolutionCriteriaTests.branchingNodes` filters to Child and Adult), and no new line. Fourteen
/// orphans cost exactly fourteen nodes.
///
/// Thirteen hang an EARNED branch beside the climb their Perfect already has, with two criteria and a
/// `requiredEnergy` distinct from every other edge on that node; ONE — Erlangmon — is the single
/// `isDefault` climb of a LEAF, Pandamon, a bolded Saiyu-Warriors parent that had been a Perfect dead
/// end. One entry off `ChildSweepAToFTests`' ledger, 60 -> 59.
///
/// **TWO PERFECTS REACH FOUR EDGES**: DORUguremon (Examon X) and pencme_andromon (Hi-Andromon) join
/// HolyAngemon (US-164) as the file's four-edge, all-energies-spent Perfects.
final class UltimateSweepEToHTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The fourteen orphaned Ultimates this story wired, with the Perfect that now reaches each and
    /// the `requiredEnergy` of the new edge. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(ultimate: String, parent: String, energy: EnergyType)] = [
        ("ebemon_x", "vademon", .vitality),
        ("enmamon", "gokuwmon", .vitality),
        ("erlangmon", "pandamon", .spirit),
        ("examon_x", "doruguremon", .stamina),
        ("gankoomon_x", "digitamamon", .vitality),
        ("gigaseadramon", "megaseadramon", .strength),
        ("goddramon_x", "megadramon", .vitality),
        ("gracenovamon", "flaremon", .strength),
        ("granddracumon", "vamdemon", .strength),
        ("hi-andromon", "pencme_andromon", .spirit),
        ("holydigitamamon", "digitamamon", .spirit),
        ("holydramon_x", "angewomon", .spirit),
        ("hououmon_x", "garudamon_x", .vitality),
        ("hydramon", "blossomon", .vitality),
    ]

    /// The one Perfect that was a LEAF before this story and now carries its one `isDefault` climb —
    /// Pandamon -> Erlangmon. An entry off `ChildSweepAToFTests`' dead-end ledger.
    private let leafParents = ["pandamon"]

    /// The shared "did everything right" context, US-151's through US-164's exactly.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.standHours": 1_000,
                                           "health.flightsClimbed": 5_000,
                                           "health.distanceSwimming": 500_000,
                                           "health.mindfulMinutes": 5_000,
                                           "health.daylight": 5_000,
                                           "health.water": 500_000,
                                           "health.distanceWalkingRunning": 500_000,
                                           "health.sleep": 100_000]),
        trainingSessionsThisStage: 50,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 60,
        battleWinRatioLifetime: 1.0)

    // MARK: - AC1/AC2: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so an Ultimate sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableUltimateEToHIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .ultimate && !$0.dexOnly
                && ("E"..."H").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 30, "the E-H Ultimate range changed size")

        // No E-H Ultimate is a Jogress result reserved as a non-node, so every one is obtainable by
        // an evolution in-edge.
        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertFalse(graph.parents(of: entry.id).isEmpty, "\(entry.id) is evolved into by nothing")
        }

        // Sixteen of the thirty were already wired before this story — device-tree Megas and the Megas
        // the Perfect sweeps opened under them (including the first Hi-Andromon design `hiandromon`
        // and Griffomon US-158's). The alias nodes `dmcv2_ebemon` and `pencme_hiandromon` are not
        // roster entries, so they are outside this playable range.
        let alreadyWired = ["ebemon", "eldoradimon", "fenriloogamon", "gaioumon", "gankoomon",
                            "gokumon", "grandiskuwagamon", "grandlocomon", "grankuwagamon", "griffomon",
                            "gundramon", "heraklekabuterimon", "hexeblaumon", "hiandromon", "holydramon",
                            "hououmon"]
        XCTAssertEqual(Set(inRange.map(\.id)),
                       Set(swept.map(\.ultimate)).union(alreadyWired),
                       "the range no longer partitions into this story's fourteen and the sixteen before")
    }

    /// The whole-file form, so an Ultimate outside E-H that a later sweep is meant to take shows up as
    /// a falling number rather than as nothing at all.
    func testTheUltimateBucketFellByExactlyThisStorysFourteen() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .ultimate && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)

        XCTAssertEqual(orphans.count, 2,
                       "80 Ultimate were edge-orphaned before this story and 66 after")
        for (ultimate, _, _) in swept {
            XCTAssertFalse(orphans.contains(ultimate), "\(ultimate) is still an orphan")
        }
    }

    // MARK: - AC2: an in-edge, and no out-edge, because the rung is terminal

    func testEveryUltimateThisStoryAddedIsTerminal() throws {
        for (ultimate, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertTrue(node.evolutions.isEmpty,
                          "\(ultimate) leads somewhere, which nothing at the top rung may")
        }
    }

    func testEveryUltimateSitsOnItsParentsLine() throws {
        for (ultimate, parent, _) in swept {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: ultimate)).line,
                           try XCTUnwrap(graph.node(id: parent)).line,
                           "\(ultimate) is not on \(parent)'s line")
            XCTAssertEqual(graph.parents(of: ultimate).map(\.id), [parent],
                           "\(ultimate)'s parents changed without this claim changing with them")
        }
    }

    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertEqual(graph.node(id: edge.to)?.line, node.line,
                               "\(node.id) -> \(edge.to) crosses a line boundary")
            }
        }
    }

    /// No new lines for fourteen new nodes, and the count is the file's rather than this story's.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 123)
        XCTAssertEqual(sizes["penc-nso"], 86)
        XCTAssertEqual(sizes["penc-me"], 75)
        XCTAssertEqual(sizes["penc-wg"], 53)
        XCTAssertEqual(sizes["penc-nsp"], 47)
        XCTAssertEqual(sizes["dmc-v4"], 36)
        XCTAssertEqual(sizes["dmc-v5"], 28)
        XCTAssertEqual(sizes["penc-sw"], 26)
    }

    // MARK: - AC4: the shape of every edge this story authored

    /// The AC's "no edge is unconditional" binds the EARNED edges. The thirteen branches each carry
    /// two criteria with a non-empty hint; the one leaf climb does NOT, and must not — the reading
    /// every rung below this one recorded, US-020 taking an `isDefault` edge whatever its gates say.
    func testEveryEarnedBranchCarriesCriteriaAndEveryLeafClimbDoesNot() throws {
        for (ultimate, parent, energy) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate },
                                     "\(parent) does not reach \(ultimate)")
            XCTAssertEqual(edge.requiredEnergy, energy)
            XCTAssertEqual(edge.minEnergy, 150, "\(ultimate)'s in-edge is not at the rung's gate")
            XCTAssertEqual(edge.maxCareMistakes, 2)

            if edge.isDefault {
                XCTAssertTrue(leafParents.contains(parent),
                              "\(parent)'s fallback is this story's edge but it was not a leaf")
                XCTAssertEqual(edge.conditions, [], "\(parent)'s fallback carries criteria")
            } else {
                XCTAssertEqual(edge.conditions.count, 2,
                               "\(ultimate) is not gated on one health metric and one care counter")
                XCTAssertEqual(edge.conditions.filter { $0.knownMetric?.isHealthMetric == true }.count,
                               1, "\(ultimate) is earned by walking alone or by playing alone")
                for condition in edge.conditions {
                    XCTAssertFalse(
                        condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(ultimate) has a criterion with no hint")
                    XCTAssertFalse(condition.hint.contains(where: \.isNumber),
                                   "\(ultimate)'s hint states a number that will go stale")
                }
            }
        }
    }

    /// Every Perfect this story forked keeps the climb it had, still marked `isDefault` and still
    /// last. A branch that displaced one would be a silent retune of the whole rung.
    func testEveryForkedPerfectKeepsItsOwnClimbAsItsFallback() throws {
        for parent in Set(swept.map(\.parent)).subtracting(leafParents) {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has exactly one fallback")
            XCTAssertTrue(try XCTUnwrap(node.evolutions.last).isDefault,
                          "\(parent)'s fallback is no longer last, which every other node's is")
            XCTAssertFalse(swept.map(\.ultimate)
                            .contains(try XCTUnwrap(node.evolutions.first(where: \.isDefault)).to),
                           "\(parent)'s fallback is one of this story's own nodes")
        }
    }

    /// **DISTINCT ENERGIES ARE WHAT MAKE A FORK REAL AT THIS RUNG.** `EvolutionEngine.qualifies`
    /// requires `dominant == requiredEnergy`, so two edges off one Perfect sharing an energy would
    /// leave the lower-`minEnergy` one unreachable for good.
    func testNoPerfectThisStoryForkedOffersTwoEdgesOnOneEnergy() throws {
        for parent in Set(swept.map(\.parent)) {
            let energies = try XCTUnwrap(graph.node(id: parent)).evolutions.compactMap(\.requiredEnergy)
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two edges on the same energy")
        }

        // **DORUguremon and pencme_andromon each reach four edges**, spending every energy — the
        // second and third four-edge Perfects in the file after HolyAngemon (US-164).
        for parent in ["doruguremon", "pencme_andromon"] {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.count, 4, parent)
            XCTAssertEqual(Set(node.evolutions.compactMap(\.requiredEnergy)), Set(EnergyType.allCases), parent)
        }

        // Vamdemon carried three after this story with GrandDracumon; US-168 took it to four with
        // VoltoBautamon (a Jogress of Vamdemon and Piemon, hung off the Perfect parent). (Digitamamon
        // carried three here — Gankoomon, Gankoomon X and HolyDigitamamon — but US-166 took it to
        // four with Minervamon X.)
        for parent in ["vamdemon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 4, parent)
        }
    }

    /// Proven through the ENGINE rather than argued: a Digimon that earned the branch takes it, and a
    /// Digimon that did not falls to the Perfect's own climb instead. Both directions.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarnedAndNotOtherwise() throws {
        for (ultimate, parent, energy) in swept where !leafParents.contains(parent) {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate })
            let climb = try XCTUnwrap(node.evolutions.first(where: \.isDefault))

            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 60,
                                                conditions: context(for: edge)),
                ultimate,
                "a \(parent) that earned \(ultimate) does not reach it")

            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: node, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 0,
                    battleWins: 0, stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                climb.to,
                "a \(parent) that earned nothing does not climb to \(climb.to)")
        }
    }

    /// The one leaf climb is the only way on from Pandamon, so the engine has to take it for a
    /// Digimon that did nothing in particular.
    func testTheClearedLeafClimbsForADigimonThatEarnedNothing() throws {
        for parent in leafParents {
            let node = try XCTUnwrap(graph.node(id: parent))
            let target = try XCTUnwrap(node.evolutions.first(where: \.isDefault)).to
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: node, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 9,
                    battleWins: 0, stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                target,
                "\(parent) still leads nowhere for a Digimon that earned nothing")
        }
    }

    /// The window trap US-150 shipped into a first draft: `care.battleCount` and `care.battleWinRatio`
    /// are answerable only over `lifetime` and every other `care.*` counter only over `stage`, so an
    /// edge that asks the other way is UNREACHABLE rather than merely hard.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        for parent in Set(swept.map(\.parent)) {
            for edge in try XCTUnwrap(graph.node(id: parent)).evolutions {
                for condition in edge.conditions {
                    guard let metric = condition.knownMetric, !metric.isHealthMetric else { continue }
                    XCTAssertEqual(condition.window == .lifetime, metric == .careBattleCount
                                       || metric == .careBattleWinRatio,
                                   "\(parent) -> \(edge.to): \(metric.rawValue) over \(condition.window)")
                }
            }
        }
    }

    /// No branch is gated SOLELY on a metric that is typically empty on real hardware — the rule
    /// `ConditionMetric.isSparseOnHardware` states. GrandDracumon reaches for daylight, paired with a
    /// care counter.
    func testNoBranchIsGatedSolelyOnAMetricThatIsEmptyOnRealHardware() throws {
        for (ultimate, parent, _) in swept where !leafParents.contains(parent) {
            let edge = try XCTUnwrap(
                try XCTUnwrap(graph.node(id: parent)).evolutions.first { $0.to == ultimate })
            let known = edge.conditions.compactMap(\.knownMetric)
            XCTAssertFalse(known.isEmpty && !edge.conditions.isEmpty,
                           "\(ultimate) is gated on a metric the app does not know")
            XCTAssertFalse(known.allSatisfy(\.isSparseOnHardware),
                           "\(ultimate) is gated only on metrics a real watch rarely records")
        }
    }

    // MARK: - AC5: the sprites are real, and nothing on an edge is dexOnly

    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for (ultimate, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            let entry = try XCTUnwrap(roster.entry(id: ultimate), "\(ultimate) has no roster entry")
            XCTAssertFalse(entry.dexOnly, "\(ultimate) is idle-only and must not be on an edge")
            XCTAssertEqual(node.spriteFile, entry.spriteFile)
            XCTAssertEqual(node.stage, entry.stage)

            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(ultimate): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, .stage, ultimate)
        }
    }

    func testNoEdgeInTheFileTouchesADexOnlyDigimon() {
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(roster.entry(id: edge.to)?.dexOnly, true,
                                  "\(node.id) -> \(edge.to) reaches an idle-only Digimon")
            }
        }
    }

    // MARK: - AC6: every new node has a line, an element and a move

    func testEveryNodeThisStoryAddedHasAKnownLineAnElementAndAMove() throws {
        let known = Set(graph.nodes.map(\.line))
        for (ultimate, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: ultimate)).line
            XCTAssertFalse(line.isEmpty, "\(ultimate) has no line")
            XCTAssertTrue(known.contains(line), "\(ultimate) is on the unknown line \(line)")
            XCTAssertNotNil(ElementCatalog.bundled.types[ultimate], "\(ultimate) has no element row")
            XCTAssertNotNil(MoveCatalog.bundled.moves[ultimate], "\(ultimate) has no move row")
        }
    }

    // MARK: - AC7: the validator

    func testTheGraphValidatesWithNoFindings() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [], errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC3: the lines are coherent, and the variants sit with their base forms

    /// The variant rule in its four shapes. Ebemon X and Gankoomon X share their base form's single
    /// Perfect exactly; Holydramon X and Hououmon X take one of their multi-parent base form's
    /// Perfects; Examon X and Goddramon X follow a cited parent because their base form is idle-only;
    /// Hi-Andromon follows a cited parent because it is the pack's SECOND design of a node that
    /// already exists under a different sprite.
    func testTheVariantsSitWithTheirBaseFormOrFollowACitedParent() throws {
        // Same PARENT as the base form, exactly.
        for (variant, base) in [("ebemon_x", "ebemon"), ("gankoomon_x", "gankoomon")] {
            XCTAssertEqual(graph.parents(of: variant).map(\.id), graph.parents(of: base).map(\.id),
                           "\(variant) no longer hangs off \(base)'s own Perfect")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line)
        }

        // One of a multi-parent base form's Perfects, on the base form's line.
        for (variant, base, parent) in [("holydramon_x", "holydramon", "angewomon"),
                                        ("hououmon_x", "hououmon", "garudamon_x")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line, variant)
            XCTAssertEqual(graph.parents(of: variant).map(\.id), [parent], variant)
            XCTAssertTrue(graph.parents(of: base).map(\.id).contains(parent),
                          "\(parent) is not one of \(base)'s parents")
        }

        // Idle-only base form -> a cited parent (the Dynasmon X shape).
        for variant in ["examon_x", "goddramon_x"] {
            let base = variant.replacingOccurrences(of: "_x", with: "")
            XCTAssertEqual(roster.entry(id: base)?.dexOnly, true, "\(base) should be idle-only")
            XCTAssertNil(graph.node(id: base), "\(base) is idle-only and must not be a node")
        }
        XCTAssertEqual(graph.parents(of: "examon_x").map(\.id), ["doruguremon"])
        XCTAssertEqual(graph.parents(of: "goddramon_x").map(\.id), ["megadramon"])

        // Hi-Andromon: the pack's second design, so it follows a cited parent (the OTHER Andromon on
        // `penc-me`) while the first design `hiandromon` keeps its `dmc-v3` home — the Chaosdramon V2
        // shape, US-164.
        XCTAssertEqual(graph.parents(of: "hi-andromon").map(\.id), ["pencme_andromon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "hi-andromon")).line, "penc-me")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "hiandromon")).line, "dmc-v3")
        XCTAssertTrue(try authoredComment(on: "hi-andromon").contains("SECOND"))

        // DarknessBagramon's opposite: DarkKnightmon aside, this story's demon lord GrandDracumon has
        // NO drawable bolded parent (Dracumon is a Child, Matadormon has no sheet), so it takes cited
        // Vamdemon on the Nightmare Soldiers line.
        XCTAssertEqual(graph.parents(of: "granddracumon").map(\.id), ["vamdemon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "vamdemon")).stage, .perfect)
        XCTAssertEqual(try XCTUnwrap(roster.entry(id: "dracumon")).stage, .child)
    }

    /// This story authored no one-node line and no line at all: every new node joined a line that
    /// already had at least a Perfect rung on it.
    func testEveryLineThisStoryTouchedAlreadyHadAPerfectRung() throws {
        for (ultimate, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: ultimate)).line
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            XCTAssertGreaterThan(perfects.count, 0,
                                 "\(line) has no Perfect rung to speak of, so \(ultimate) opened one")
        }
    }

    // MARK: - The leaf this story cleared

    /// The dead-end ledger's other direction: Pandamon really does lead somewhere now, and it was a
    /// LEAF rather than an orphan — it had an in-edge all along.
    func testTheLeafPerfectThisStoryClearedNowClimbs() throws {
        for parent in leafParents {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertFalse(node.evolutions.isEmpty, "\(parent) is a dead end again")
            XCTAssertFalse(graph.parents(of: parent).isEmpty,
                           "\(parent) was an orphan, not a leaf, so this claim is the wrong shape")
        }

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       74, "the dead-end ledger in `ChildSweepAToFTests` has moved")
    }

    // MARK: - The nodes on shut-out lines, and the eponym rescues

    /// **ENMAMON AND GRACENOVAMON HAVE AN `Evolves From` MADE ENTIRELY OF ULTIMATES**, the Cernumon
    /// shape: each is drawn one rung below on the Perfect that climbs into a cited Ultimate.
    func testTheNodesWhoseEveryParentIsAnUltimateAreDrawnOneRungBelow() throws {
        // Enmamon's Seiten Gokuwmon and GraceNovamon's Apollomon are the cited Ultimates whose
        // Perfect parents (Gokuwmon, Flaremon) actually carry these nodes.
        XCTAssertTrue(graph.node(id: "gokuwmon")?.evolutions.contains { $0.to == "seitengokuwmon" } ?? false,
                      "Gokuwmon no longer climbs to Enmamon's cited Ultimate")
        XCTAssertTrue(graph.node(id: "flaremon")?.evolutions.contains { $0.to == "apollomon" } ?? false,
                      "Flaremon no longer climbs to GraceNovamon's cited Ultimate")
        XCTAssertTrue(try authoredComment(on: "enmamon").contains("EVERY"))
        XCTAssertTrue(try authoredComment(on: "gracenovamon").contains("BOTH BOLDED PARENTS ARE ULTIMATES"))
    }

    /// **HOLYDIGITAMAMON HAS AN EMPTY `Evolves From` ON WIKIMON**, so it lands on its eponym
    /// Digitamamon — recorded in as many words.
    func testTheNodeWithNoCitedParentSaysSoAndUsesItsEponym() throws {
        XCTAssertEqual(graph.parents(of: "holydigitamamon").map(\.id), ["digitamamon"])
        XCTAssertTrue(try authoredComment(on: "holydigitamamon").contains("EMPTY"))
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in as
    /// many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for (ultimate, _, _) in swept {
            let comment = try authoredComment(on: ultimate)
            XCTAssertTrue(comment.contains("Wikimon"),
                          "\(ultimate)'s comment neither cites a source nor says it has none")
            XCTAssertGreaterThan(comment.count, 200, "\(ultimate)'s comment is a stub")
        }

        // The idle-only bases and the four-edge results are written down too.
        XCTAssertTrue(try authoredComment(on: "examon_x").contains("IDLE-ONLY"),
                      "that Examon X's base form is idle-only is not recorded")
        XCTAssertTrue(try authoredComment(on: "examon_x").contains("FOUR-EDGE"),
                      "that Examon X makes DORUguremon a four-edge Perfect is not recorded")
        XCTAssertTrue(try authoredComment(on: "goddramon_x").contains("IDLE-ONLY"),
                      "that Goddramon X's base form is idle-only is not recorded")
        XCTAssertTrue(try authoredComment(on: "hi-andromon").contains("FOUR-EDGE"),
                      "that Hi-Andromon makes pencme_andromon a four-edge Perfect is not recorded")
    }

    // MARK: - AC8: the orphan count, and what this sweep hands on

    /// The count that goes into `notes`, asserted rather than merely written down.
    func testTheFourteenOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 14)
        for (ultimate, _, _) in swept {
            XCTAssertNotNil(roster.entry(id: ultimate),
                            "\(ultimate) is an alias, so it removed no orphan")
        }

        XCTAssertEqual(graph.nodes.count, 931, "837 before this story, 851 after it")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "the Perfect rung must not have moved")
    }

    /// **The handover to US-166 onward, in the shape US-151 through US-164 established: a claim, not a
    /// note.** What the remaining Ultimate sweeps inherit is a rung past halfway done and the sixteen
    /// Armor-Hybrid US-169 owns.
    func testWhatThisSweepHandsToTheRestOfTheUltimateRung() throws {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let stillOrphaned = roster.entries.filter { !$0.dexOnly && !connected.contains($0.id) }

        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate }.count, 2,
                       "the Ultimate edge-orphan bucket moved without this claim moving with it")
        XCTAssertEqual(stillOrphaned.filter { $0.stage == .armorHybrid }.count, 0,
                       "US-169 cleared the Armor-Hybrid bucket, the last of the sweeps")
        XCTAssertEqual(stillOrphaned.filter { $0.stage != .ultimate && $0.stage != .armorHybrid },
                       [], "a rung below Ultimate is orphaned again")

        // Ogudomon is still US-159's pin; its display name begins O, so it belongs to US-167.
        XCTAssertNotNil(roster.entry(id: "ogudomon"))
        // US-167 wired Ogudomon from Mephismon, a Nightmare Soldiers Demon Lord.
        XCTAssertEqual(graph.parents(of: "ogudomon").map(\.id), ["mephismon"])
    }

    // MARK: - Helpers

    /// A context derived from the EDGE's own conditions rather than the shared "did everything right"
    /// one, because that fixture cannot satisfy an `atMost` criterion — US-151's rule.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 50
        var overfeeds = 0
        var disturbances = 0
        var winRatio = 1.0

        for condition in edge.conditions {
            switch (condition.knownMetric, condition.comparison) {
            case (.careTrainingSessions, .atMost): training = 0
            case (.careOverfeeds, .atMost): overfeeds = 0
            case (.careOverfeeds, .atLeast): overfeeds = Int(condition.value) + 1
            case (.careSleepDisturbances, .atMost): disturbances = 0
            case (.careSleepDisturbances, .atLeast): disturbances = Int(condition.value) + 1
            case (.careBattleWinRatio, .atMost): winRatio = 0
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
            battlesLifetime: 60,
            battleWinRatioLifetime: winRatio)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-164 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
