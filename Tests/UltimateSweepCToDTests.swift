import XCTest

@testable import DigiVPet

/// US-164 — the twenty-first of Phase E's orphan sweeps and **the second at the TOP rung**: the
/// twenty playable Ultimate whose display name begins C-D that no device tree and no earlier sweep
/// reached, and that a Jogress recipe does not already reach. The Ultimate bucket 100 -> 80.
///
/// **AN ULTIMATE SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE**, exactly as US-163 recorded: the rung
/// is terminal, so there is no rung above to open, no junk floor to invent
/// (`EvolutionCriteriaTests.branchingNodes` filters to Child and Adult), and no new line. Twenty
/// orphans cost exactly twenty nodes.
///
/// **TWO C-D ULTIMATES ARE NOT ORPHANS AND ARE LEFT ALONE: Chaosdramon and Chaosmon.** Both are
/// Jogress results — the DMC Ver.5 / Ver.4 documents draw them as the Jogress Ultra row and
/// `jogress.json` spends them — so they are obtainable, and `DMCVersion5TreeTests`,
/// `DMCVersion4TreeTests` and `PendulumMetalEmpireTreeTests` each pin them to NO evolution node.
/// Cernumon is a Jogress result too, but no device tree reserves it (as `aegisdramon` and
/// `millenniumon` are both Jogress results and wired nodes), so it IS wired here.
///
/// Two shapes of in-edge, and the parent decides which:
///
///  * TWO leaf Perfects gain their single `isDefault` climb — MetalGreymon X -> Chaosdramon V2 and
///    Huankunmon -> Dijiangmon. Both were parked for this rung IN AS MANY WORDS: US-160 and US-159
///    each ended those nodes with "A leaf until the Ultimate sweeps", and each is a CITED parent of
///    the Digimon it now carries. Two entries off `ChildSweepAToFTests`' dead-end ledger, 62 -> 60.
///  * The other eighteen hang an EARNED branch beside the climb their Perfect already has, with two
///    criteria and a `requiredEnergy` distinct from every other edge on that node.
///
/// **THIS STORY'S ONE FIRST: HolyAngemon becomes the FIRST PERFECT IN THE FILE WITH FOUR EDGES**,
/// and in doing so spends its last free energy on Dominimon — the node is CLOSED.
final class UltimateSweepCToDTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// Chaosdramon and Chaosmon: C-D Ultimates that are Jogress results, so obtainable and left
    /// unwired. Named here because the coverage and bucket claims below have to know them.
    private let jogressReachable = ["chaosdramon", "chaosmon"]

    /// The twenty orphaned Ultimates this story wired, with the Perfect that now reaches each and
    /// the `requiredEnergy` of the new edge. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(ultimate: String, parent: String, energy: EnergyType)] = [
        ("callismon", "soloogarmon", .vitality),
        ("cernumon", "jyureimon", .spirit),
        ("chaosdukemon_core", "blackmegalogrowmon", .vitality),
        ("chaosdramon_v2", "metalgreymon_x", .strength),
        ("cherubimon_vice_x", "andiramon_virus", .vitality),
        ("cherubimon_virtue_x", "entmon", .spirit),
        ("craniummon_x", "pencme_andromon", .stamina),
        ("cthyllamon", "dagomon", .vitality),
        ("darknessbagramon", "darkknightmon", .strength),
        ("deathmon_black", "darumamon", .vitality),
        ("demon", "deathmeramon", .spirit),
        ("demon_x", "deathmeramon", .vitality),
        ("diablomon", "meicrackmon", .strength),
        ("diablomon_x", "meicrackmon", .spirit),
        ("dijiangmon", "huankunmon", .spirit),
        ("dominimon", "holyangemon", .stamina),
        ("duftmon", "knightmon", .spirit),
        ("duftmon_x", "knightmon", .vitality),
        ("dukemon_x", "megalogrowmon_orange", .spirit),
        ("dynasmon_x", "doruguremon", .vitality),
    ]

    /// The two Perfects that were LEAVES before this story and now carry their one `isDefault`
    /// climb — Huankunmon -> Dijiangmon and MetalGreymon X -> Chaosdramon V2. Each is an entry off
    /// `ChildSweepAToFTests`' ledger.
    private let leafParents = ["huankunmon", "metalgreymon_x"]

    /// The shared "did everything right" context, US-151's through US-163's exactly.
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
    func testEveryPlayableUltimateCToDIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .ultimate && !$0.dexOnly
                && ("C"..."D").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 37, "the C-D Ultimate range changed size")

        // Every one is OBTAINABLE — by an evolution in-edge, or (for the two Jogress results) by a
        // recipe. Chaosdramon and Chaosmon have no node and must not: the device trees reserve
        // them, so this test reads "obtainable", not "has an evolution parent".
        for entry in inRange {
            let byJogress = JogressCatalog.bundled.recipes.contains { $0.result == entry.id }
            if byJogress && graph.node(id: entry.id) == nil {
                continue  // reserved as a Jogress result, and correctly not an evolution node
            }
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertTrue(!graph.parents(of: entry.id).isEmpty || byJogress,
                          "\(entry.id) is neither evolved into nor a Jogress")
        }
        for id in jogressReachable {
            XCTAssertTrue(graph.parents(of: id).isEmpty,
                          "\(id) gained an evolution parent, but the device trees reserve it")
            XCTAssertTrue(JogressCatalog.bundled.recipes.contains { $0.result == id },
                          "\(id) is not a Jogress result, so leaving it unwired stranded it")
        }

        // Fifteen of the thirty-seven were already wired before this story — device-tree Megas and
        // the Megas the Perfect sweeps opened under them (Chaosdramon X US-151's, Dukemon US-160's,
        // Craniummon US-142's, Cherubimon Vice/Virtue US-143's, and so on).
        let alreadyWired = ["chaosdramon_x", "chaosdukemon", "cherubimon_vice", "cherubimon_virtue",
                            "craniummon", "cresgarurumon", "darkdramon", "darkknightmon_x",
                            "deathmon", "dianamon", "diarbbitmon", "dinorexmon", "dinotigermon",
                            "dorugoramon", "dukemon"]
        XCTAssertEqual(Set(inRange.map(\.id)),
                       Set(swept.map(\.ultimate)).union(alreadyWired).union(jogressReachable),
                       "the range no longer partitions into this story's twenty, the fifteen before, and the two Jogress")
    }

    /// The whole-file form, so an Ultimate outside C-D that a later sweep is meant to take shows up
    /// as a falling number rather than as nothing at all. The evolution-edge count is 80 — the two
    /// Jogress results are obtainable but carry no edge, so 78 is the true remainder E-Z is owed.
    func testTheUltimateBucketFellByExactlyThisStorysTwenty() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .ultimate && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)

        XCTAssertEqual(orphans.count, 19,
                       "100 before this story, 80 after; US-165 then took the E-H band down to 66")
        XCTAssertEqual(orphans.filter { !jogressReachable.contains($0) }.count, 17,
                       "the true remainder once the Jogress results are set aside, after US-167")
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

    /// No new lines for twenty-two new nodes, and the count is the file's rather than this story's.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 123)
        XCTAssertEqual(sizes["penc-nso"], 84)
        XCTAssertEqual(sizes["penc-me"], 74)
        XCTAssertEqual(sizes["penc-vb"], 61)
        XCTAssertEqual(sizes["dmc-v3"], 56)
        XCTAssertEqual(sizes["penc-ds"], 48)
        XCTAssertEqual(sizes["penc-wg"], 50)
        XCTAssertEqual(sizes["penc-nsp"], 46)
        XCTAssertEqual(sizes["dmc-v1"], 42)
        XCTAssertEqual(sizes["dmc-v4"], 35)
        XCTAssertEqual(sizes["diablomon"], 24)
    }

    // MARK: - AC4: the shape of every edge this story authored

    /// The AC's "no edge is unconditional" binds the EARNED edges. The twenty branches each carry
    /// two criteria with a non-empty hint; the two leaf climbs do NOT, and must not — the reading
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

        // **HolyAngemon is the first Perfect in the file to carry four edges**, and it now spends
        // every one of the four energies — the node is closed to any later sweep.
        let holyangemon = try XCTUnwrap(graph.node(id: "holyangemon"))
        XCTAssertEqual(holyangemon.evolutions.count, 4)
        XCTAssertEqual(Set(holyangemon.evolutions.compactMap(\.requiredEnergy)), Set(EnergyType.allCases))

        // The Perfects that carry three edges after this story. (Chimairamon was NOT forked here —
        // Chaosmon, which would have, is a Jogress result left unwired — so it stays at the two
        // edges US-163 gave it.) US-165 later took doruguremon and pencme_andromon to FOUR edges
        // (Examon X and Hi-Andromon), so they are checked at four rather than three.
        for parent in ["deathmeramon", "meicrackmon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3, parent)
        }
        // Knightmon carried three here (Duftmon, Duftmon X, Craniummon) but US-166 took it to four
        // with LordKnightmon X, so it joins the four-edge Perfects.
        for parent in ["doruguremon", "pencme_andromon", "knightmon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 4, parent)
        }
    }

    /// Proven through the ENGINE rather than argued: a Digimon that earned the branch takes it, and
    /// a Digimon that did not falls to the Perfect's own climb instead. Both directions.
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

    /// The two leaf climbs are the only way on from their Perfect, so the engine has to take them
    /// for a Digimon that did nothing in particular. MetalGreymon X's fallback is Chaosdramon, its
    /// `isDefault` edge, even though it now also offers Chaosdramon V2.
    func testTheTwoClearedLeavesClimbForADigimonThatEarnedNothing() throws {
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

    /// The window trap US-150 shipped into a first draft: `care.battleCount` and
    /// `care.battleWinRatio` are answerable only over `lifetime` and every other `care.*` counter
    /// only over `stage`, so an edge that asks the other way is UNREACHABLE rather than merely hard.
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
    /// `ConditionMetric.isSparseOnHardware` states. Two of these edges reach for daylight, each
    /// paired with a care counter.
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

    /// **THE STRONG FORM OF THE VARIANT RULE — SAME PARENT, NOT MERELY SAME LINE — HOLDS FOR THE
    /// THREE X-ANTIBODY MEGAS WHOSE BASE FORM IS A SINGLE-PARENT NODE.** Demon X, Diablomon X and
    /// Duftmon X each have an `Evolves From` made ENTIRELY of Ultimates or undrawable forms, so each
    /// hangs off the very Perfect its base form hangs off. The Cherubimon pair sit on a cited parent
    /// of their two-parent base form; Craniummon X and Dynasmon X on a cited parent elsewhere on the
    /// line; and Chaosdramon V2 on a cited parent because its base form is a Jogress result, not a
    /// node at all.
    func testTheVariantsSitWithTheirBaseFormOrFollowACitedParent() throws {
        // Same PARENT as the base form: the X and its base share their one Perfect exactly.
        for (variant, base) in [("demon_x", "demon"), ("diablomon_x", "diablomon"),
                                ("duftmon_x", "duftmon")] {
            XCTAssertEqual(graph.parents(of: variant).map(\.id), graph.parents(of: base).map(\.id),
                           "\(variant) no longer hangs off \(base)'s own Perfect")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line)
        }

        // Same LINE, a parent that is drawable: the Cherubimon pair each take one of their
        // two-parent base form's Perfects, and Craniummon X a cited parent. Each parent is either
        // the base form's own or on the base form's line.
        for (variant, base, parent) in [("cherubimon_vice_x", "cherubimon_vice", "andiramon_virus"),
                                        ("cherubimon_virtue_x", "cherubimon_virtue", "entmon"),
                                        ("craniummon_x", "craniummon", "pencme_andromon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line, variant)
            XCTAssertEqual(graph.parents(of: variant).map(\.id), [parent], variant)
            let parentLine = try XCTUnwrap(graph.node(id: parent)).line
            let onBaseFormsLine = graph.parents(of: base).map(\.id).contains(parent)
                || parentLine == graph.node(id: base)?.line
            XCTAssertTrue(onBaseFormsLine, variant)
        }

        // Dynasmon X: base form Dynasmon is idle-only (not a node), so the variant follows a cited
        // parent. Chaosdramon V2: base form Chaosdramon is a Jogress result (not a node), so it
        // follows MetalGreymon X, a cited parent of Chaosdramon on its own `dmc-v3` line.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "dynasmon_x")).line, "tamers")
        XCTAssertEqual(graph.parents(of: "dynasmon_x").map(\.id), ["doruguremon"])
        XCTAssertEqual(roster.entry(id: "dynasmon")?.dexOnly, true)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "chaosdramon_v2")).line, "dmc-v3")
        XCTAssertEqual(graph.parents(of: "chaosdramon_v2").map(\.id), ["metalgreymon_x"])
        XCTAssertNil(graph.node(id: "chaosdramon"), "Chaosdramon is a Jogress result, not a node")

        // DarknessBagramon is the rare case whose bolded parent (DarkKnightmon) is a drawable
        // Perfect in this pack, so the page's own arrow is drawn exactly as drawn.
        XCTAssertEqual(graph.parents(of: "darknessbagramon").map(\.id), ["darkknightmon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "darkknightmon")).stage, .perfect)
        XCTAssertTrue(try authoredComment(on: "darknessbagramon").contains("DarkKnightmon"))
    }

    /// This story authored no one-node line and no line at all: every new node joined a line that
    /// already had at least a Champion rung on it.
    func testEveryLineThisStoryTouchedAlreadyHadAPerfectRung() throws {
        for (ultimate, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: ultimate)).line
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            XCTAssertGreaterThan(perfects.count, 0,
                                 "\(line) has no Perfect rung to speak of, so \(ultimate) opened one")
        }
    }

    // MARK: - The two leaves this story cleared

    /// The dead-end ledger's other direction: each of the two really does lead somewhere now, and
    /// each was a LEAF rather than an orphan — it had an in-edge all along.
    func testTheTwoLeafPerfectsThisStoryClearedNowClimb() throws {
        for parent in leafParents {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertFalse(node.evolutions.isEmpty, "\(parent) is a dead end again")
            XCTAssertFalse(graph.parents(of: parent).isEmpty,
                           "\(parent) was an orphan, not a leaf, so this claim is the wrong shape")
        }

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       58, "the dead-end ledger in `ChildSweepAToFTests` has moved")
    }

    // MARK: - The nodes on shut-out lines, and the eponym's near-miss

    /// **THE `diablomon` LINE IS NAMED FOR A DIGIMON EVERY CITED ROUTE ONTO IT SHUTS OUT — AND THIS
    /// STORY GOT IT HOME ANYWAY.** All four bolded parents on Wikimon are on this line and none is
    /// drawable: Chrysalimon and Infermon are idle-only (`edgeToDexOnlyNode`), Keramon is a Child
    /// and Kuramon a Baby I (`invalidStageTransition`). US-163 hit the same wall with Armagemon and
    /// had to leave the line; Meicrackmon, a drawable Perfect on the line that already climbs, is
    /// what let the eponym stay.
    func testTheEponymDiablomonLandedOnItsOwnLineDespiteEveryCitedRouteBeingShut() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "diablomon")).line, "diablomon")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "diablomon_x")).line, "diablomon")

        for id in ["chrysalimon", "infermon"] {
            XCTAssertEqual(try XCTUnwrap(roster.entry(id: id)).dexOnly, true)
            XCTAssertNil(graph.node(id: id))
        }
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "keramon")).stage, .child)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kuramon")).stage, .babyI)
        XCTAssertTrue(try authoredComment(on: "diablomon").contains("edgeToDexOnlyNode"))
        XCTAssertTrue(try authoredComment(on: "diablomon").contains("invalidStageTransition"))
    }

    /// **TWO NODES HAD A BOLDED PARENT THAT WAS A PLAIN THING, NOT A DIGIMON**, the Code Key trap
    /// US-163 recorded for Barbamon: ChaosDukemon Core's Chrono Core is an item, and Dijiangmon's
    /// bolded parent is literally "Digitama". Each says so in its comment.
    func testTheNodesWhoseBoldedParentIsNotADigimonSayItInAsManyWords() throws {
        XCTAssertTrue(try authoredComment(on: "chaosdukemon_core").contains("ITEM"))
        XCTAssertTrue(try authoredComment(on: "dijiangmon").contains("NOT A DIGIMON"))
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for (ultimate, _, _) in swept {
            let comment = try authoredComment(on: ultimate)
            XCTAssertTrue(comment.contains("Wikimon"),
                          "\(ultimate)'s comment neither cites a source nor says it has none")
            XCTAssertGreaterThan(comment.count, 200, "\(ultimate)'s comment is a stub")
        }

        // The undrawable and rejected readings are written down too.
        XCTAssertTrue(try authoredComment(on: "callismon").contains("invalidStageTransition"),
                      "that Callismon's bolded parent is at the wrong rung is not recorded")
        XCTAssertTrue(try authoredComment(on: "cernumon").contains("EVERY"),
                      "that all of Cernumon's parents are Ultimates is not recorded")
        XCTAssertTrue(try authoredComment(on: "chaosdramon_v2").contains("NO PAGE"),
                      "that Chaosdramon V2 has no Wikimon page is not recorded")
        XCTAssertTrue(try authoredComment(on: "dominimon").contains("FOUR EDGES"),
                      "that Dominimon makes HolyAngemon the first four-edge Perfect is not recorded")
        XCTAssertTrue(try authoredComment(on: "dynasmon_x").contains("IDLE-ONLY"),
                      "that Dynasmon X's base form is idle-only is not recorded")
    }

    /// **ONE EDGE IN THIS STORY IS EARNED BY LOSING**, the Lucemon Falldown arrangement: a core is
    /// what is left when a knight burns out. Proven through the engine in both directions.
    func testTheFallenMegaIsEarnedByLosingRatherThanByWinning() throws {
        let node = try XCTUnwrap(graph.node(id: "blackmegalogrowmon"))
        let edge = try XCTUnwrap(node.evolutions.first { $0.to == "chaosdukemon_core" })
        let ratio = try XCTUnwrap(edge.conditions.first { $0.metric == "care.battleWinRatio" })
        XCTAssertEqual(ratio.comparison, .atMost, "ChaosDukemon Core's losing gate became a winning one")

        var totals = EnergyTotals()
        totals[try XCTUnwrap(edge.requiredEnergy)] = edge.minEnergy
        XCTAssertNotEqual(
            EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                            dominant: edge.requiredEnergy, careMistakes: 0,
                                            battleWins: 60, conditions: met),
            "chaosdukemon_core",
            "a BlackMegaloGrowmon that won everything still becomes ChaosDukemon Core")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                            dominant: edge.requiredEnergy, careMistakes: 0,
                                            battleWins: 60, conditions: context(for: edge)),
            "chaosdukemon_core",
            "a BlackMegaloGrowmon that lost does not become ChaosDukemon Core")
    }

    // MARK: - AC8: the orphan count, and what this sweep hands on

    /// The count that goes into `notes`, asserted rather than merely written down.
    func testTheTwentyOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 20)
        for (ultimate, _, _) in swept {
            XCTAssertNotNil(roster.entry(id: ultimate),
                            "\(ultimate) is an alias, so it removed no orphan")
        }

        XCTAssertEqual(graph.nodes.count, 898, "817 before this story, 837 after it")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "the Perfect rung must not have moved")
    }

    /// **The handover to US-165 onward, in the shape US-151 through US-163 established: a claim, not
    /// a note.** What the remaining Ultimate sweeps inherit is a rung two-fifths done, sixty Perfect
    /// leaves still owed a climb, and the sixteen Armor-Hybrid US-169 owns.
    func testWhatThisSweepHandsToTheRestOfTheUltimateRung() throws {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let stillOrphaned = roster.entries.filter { !$0.dexOnly && !connected.contains($0.id) }

        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate }.count, 19,
                       "the Ultimate edge-orphan bucket moved without this claim moving with it")
        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate && !jogressReachable.contains($0.id) }.count,
                       17, "Ultimate truly owed once the Jogress results are set aside, after US-167")
        XCTAssertEqual(stillOrphaned.filter { $0.stage == .armorHybrid }.count, 16,
                       "the Armor-Hybrid bucket is US-169's and must not have moved")
        XCTAssertEqual(stillOrphaned.filter { $0.stage != .ultimate && $0.stage != .armorHybrid },
                       [], "a rung below Ultimate is orphaned again")

        // Ogudomon is still US-159's pin; its display name begins O, so it belongs to US-167.
        XCTAssertNotNil(roster.entry(id: "ogudomon"))
        // US-167 wired Ogudomon from Mephismon, a Nightmare Soldiers Demon Lord.
        XCTAssertEqual(graph.parents(of: "ogudomon").map(\.id), ["mephismon"])
    }

    // MARK: - Helpers

    /// A context derived from the EDGE's own conditions rather than the shared "did everything
    /// right" one, because that fixture cannot satisfy an `atMost` criterion — US-151's rule.
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
    /// helper US-144 through US-163 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
