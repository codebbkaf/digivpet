import XCTest

@testable import DigiVPet

/// US-166 — the twenty-third of Phase E's orphan sweeps and **the fourth at the TOP rung**: the
/// twenty-seven playable Ultimate whose display name begins I-M that no device tree and no earlier
/// sweep reached. Mastemon and Mitamamon are Jogress results, but a Jogress result still takes an
/// evolution in-edge here, exactly as Cernumon, Aegisdramon and Millenniumon did. The Ultimate
/// bucket 66 -> 39.
///
/// **AN ULTIMATE SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE**, exactly as US-163/US-164/US-165
/// recorded: the rung is terminal, so there is no rung above to open, no junk floor to invent
/// (`EvolutionCriteriaTests.branchingNodes` filters to Child and Adult), and no new line. Twenty-seven
/// orphans cost exactly twenty-seven nodes.
///
/// Twenty-six hang an EARNED branch beside the climb their Perfect already has, with two criteria and
/// a `requiredEnergy` distinct from every other edge on that node; ONE — Kaguyamon — is the single
/// `isDefault` climb of a LEAF, Karakurumon, a bolded parent that had been a Perfect dead end on
/// `wanyamon`. One entry off `ChildSweepAToFTests`' ledger, 59 -> 58.
///
/// **FIVE PERFECTS REACH FOUR EDGES** (all energies spent): Paildramon (the three Imperialdramon
/// Modes), SaviorHackmon (the three Jesmon), LadyDevimon (Lilithmon + Lilithmon X), Knightmon
/// (LordKnightmon X) and Digitamamon (Minervamon X) — joining HolyAngemon, DORUguremon and
/// pencme_andromon.
final class UltimateSweepIToMTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The twenty-seven orphaned Ultimates this story wired, with the Perfect that now reaches each and
    /// the `requiredEnergy` of the new edge. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(ultimate: String, parent: String, energy: EnergyType)] = [
        ("imperialdramon_fighter", "paildramon", .stamina),
        ("imperialdramon_fighter_black", "paildramon", .spirit),
        ("imperialdramon_paladin", "paildramon", .vitality),
        ("jesmon", "saviorhackmon", .strength),
        ("jesmon_x", "saviorhackmon", .stamina),
        ("jesmon_gx", "saviorhackmon", .vitality),
        ("jougamon", "chohakkaimon", .strength),
        ("jumbogamemon", "shawujinmon", .stamina),
        ("justimon_x", "cyberdramon_x", .strength),
        ("kaguyamon", "karakurumon", .strength),
        ("kuzuhamon", "karatenmon", .strength),
        ("leviamon_x", "marindevimon", .strength),
        ("lilithmon", "ladydevimon", .strength),
        ("lilithmon_x", "ladydevimon", .stamina),
        ("lordknightmon_x", "knightmon", .stamina),
        ("lotusmon", "lilamon", .strength),
        ("lucemon_satan", "lucemon_falldown", .strength),
        ("lucemon_x", "lucemon_falldown", .spirit),
        ("magnamon_x", "aerov-dramon", .stamina),
        ("marinangemon", "pencds_whamon", .strength),
        ("mastemon", "angewomon", .strength),
        ("megidramon", "megalogrowmon", .stamina),
        ("megidramon_x", "megalogrowmon", .spirit),
        ("metalgarurumon_black", "weregarurumon_black", .stamina),
        ("metalgarurumon_x", "weregarurumon_x", .strength),
        ("minervamon_x", "digitamamon", .stamina),
        ("mitamamon", "garudamon", .strength),
    ]

    /// The one Perfect that was a LEAF before this story and now carries its one `isDefault` climb —
    /// Karakurumon -> Kaguyamon. An entry off `ChildSweepAToFTests`' dead-end ledger.
    private let leafParents = ["karakurumon"]

    /// The shared "did everything right" context, US-151's through US-165's exactly.
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
    func testEveryPlayableUltimateIToMIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .ultimate && !$0.dexOnly
                && ("I"..."M").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 37, "the I-M Ultimate range changed size")

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertFalse(graph.parents(of: entry.id).isEmpty, "\(entry.id) is evolved into by nothing")
        }

        // Ten of the thirty-seven were already wired before this story — device-tree Megas and the
        // Megas the Perfect sweeps opened under them.
        let alreadyWired = ["kazuchimon", "kingetemon", "leviamon", "metaletemon", "metalgarurumon",
                            "metallicdramon", "metalpiranimon", "metalseadramon", "millenniumon",
                            "mugendramon"]
        XCTAssertEqual(Set(inRange.map(\.id)),
                       Set(swept.map(\.ultimate)).union(alreadyWired),
                       "the range no longer partitions into this story's twenty-seven and the ten before")
    }

    /// The whole-file form, so an Ultimate outside I-M that a later sweep is meant to take shows up as
    /// a falling number rather than as nothing at all.
    func testTheUltimateBucketFellByExactlyThisStorys27() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .ultimate && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)

        XCTAssertEqual(orphans.count, 2,
                       "66 Ultimate were edge-orphaned before this story and 39 after")
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

    /// No new lines for twenty-seven new nodes, and the count is the file's rather than this story's.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 123)
        XCTAssertEqual(sizes["penc-nso"], 86)
        XCTAssertEqual(sizes["penc-me"], 75)
        XCTAssertEqual(sizes["penc-wg"], 53)
        XCTAssertEqual(sizes["penc-ds"], 48)
        XCTAssertEqual(sizes["penc-nsp"], 47)
        XCTAssertEqual(sizes["dmc-v4"], 36)
        XCTAssertEqual(sizes["wanyamon"], 33)
        XCTAssertEqual(sizes["dmc-v2"], 32)
        XCTAssertEqual(sizes["palmon"], 32)
        XCTAssertEqual(sizes["penc-sw"], 26)
    }

    // MARK: - AC4: the shape of every edge this story authored

    /// The AC's "no edge is unconditional" binds the EARNED edges. The twenty-six branches each carry
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

        // **FIVE PERFECTS REACH FOUR EDGES**, spending every energy — Paildramon, SaviorHackmon,
        // LadyDevimon, Knightmon and Digitamamon join HolyAngemon, DORUguremon and pencme_andromon.
        for parent in ["paildramon", "saviorhackmon", "ladydevimon", "knightmon", "digitamamon"] {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.count, 4, parent)
            XCTAssertEqual(Set(node.evolutions.compactMap(\.requiredEnergy)), Set(EnergyType.allCases), parent)
        }

        // Lucemon: Falldown Mode carried three after this story — Venom Vamdemon, Lucemon Satan and
        // Lucemon X — until US-167 hung Ordinemon on it for a fourth; Megalo Growmon keeps three
        // with Megidramon and Megidramon X.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lucemon_falldown")).evolutions.count, 4)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "megalogrowmon")).evolutions.count, 3)
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

    /// The one leaf climb is the only way on from Karakurumon, so the engine has to take it for a
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
    /// `ConditionMetric.isSparseOnHardware` states. Lilithmon and Lucemon X reach for daylight, each
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

    /// The variant rule in its shapes. Lilithmon X, Megidramon X and Jesmon X share their base form's
    /// single Perfect exactly; Justimon X, LordKnightmon X, Magnamon X and Minervamon X follow a cited
    /// parent because their base form is idle-only; Leviamon X takes one of its multi-parent base
    /// form's Perfects; MetalGarurumon X rises from the X form of its base form's Champion.
    func testTheVariantsSitWithTheirBaseFormOrFollowACitedParent() throws {
        // Same PARENT as the base form, exactly (both are nodes this story added).
        for (variant, base) in [("lilithmon_x", "lilithmon"), ("megidramon_x", "megidramon"),
                                ("jesmon_x", "jesmon"), ("imperialdramon_fighter_black", "imperialdramon_fighter")] {
            XCTAssertEqual(graph.parents(of: variant).map(\.id), graph.parents(of: base).map(\.id),
                           "\(variant) no longer hangs off \(base)'s own Perfect")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line)
        }

        // Idle-only base form -> a cited parent (the Dynasmon X shape).
        for (variant, base, parent) in [("justimon_x", "justimon", "cyberdramon_x"),
                                        ("lordknightmon_x", "lordknightmon", "knightmon"),
                                        ("magnamon_x", "magnamon", "aerov-dramon"),
                                        ("minervamon_x", "minervamon", "digitamamon")] {
            XCTAssertEqual(roster.entry(id: base)?.dexOnly, true, "\(base) should be idle-only")
            XCTAssertNil(graph.node(id: base), "\(base) is idle-only and must not be a node")
            XCTAssertEqual(graph.parents(of: variant).map(\.id), [parent], variant)
        }

        // Leviamon X takes one of its base form's Perfects; the base form IS a node here.
        XCTAssertEqual(graph.parents(of: "leviamon_x").map(\.id), ["marindevimon"])
        XCTAssertTrue(graph.parents(of: "leviamon").map(\.id).contains("marindevimon"),
                      "marindevimon is not one of Leviamon's parents")

        // MetalGarurumon X rises from WereGarurumon (X-Antibody), an antibody from an antibody.
        XCTAssertEqual(graph.parents(of: "metalgarurumon_x").map(\.id), ["weregarurumon_x"])
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

    /// Karakurumon really does lead somewhere now, and it was a LEAF rather than an orphan — it had an
    /// in-edge all along.
    func testTheLeafPerfectThisStoryClearedNowClimbs() throws {
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

    // MARK: - The Cernumon shape and the Jogress results

    /// **MITAMAMON'S `Evolves From` IS A JOGRESS OF TWO ULTIMATES**, the Cernumon shape: it is drawn
    /// one rung below on Garudamon, the Perfect that climbs into its cited Ultimate Hououmon.
    func testTheCernumonShapeNodeIsDrawnOneRungBelow() throws {
        XCTAssertEqual(graph.parents(of: "mitamamon").map(\.id), ["garudamon"])
        XCTAssertTrue(graph.node(id: "garudamon")?.evolutions.contains { $0.to == "hououmon" } ?? false,
                      "Garudamon no longer climbs to Mitamamon's cited Ultimate Hououmon")
        XCTAssertTrue(try authoredComment(on: "mitamamon").contains("JOGRESS"))
    }

    /// Mastemon and Mitamamon are Jogress results, and both take an evolution in-edge all the same —
    /// each parent Angewomon/Garudamon is a Perfect, and both parents of the Mastemon recipe are
    /// Perfects, so it hangs directly off one rather than one rung below.
    func testTheJogressResultsAreWiredAllTheSame() throws {
        XCTAssertEqual(graph.parents(of: "mastemon").map(\.id), ["angewomon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "angewomon")).stage, .perfect)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "ladydevimon")).stage, .perfect)
        XCTAssertTrue(try authoredComment(on: "mastemon").contains("Jogress"))
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
        for variant in ["justimon_x", "lordknightmon_x", "magnamon_x", "minervamon_x"] {
            XCTAssertTrue(try authoredComment(on: variant).contains("IDLE-ONLY"),
                          "that \(variant)'s base form is idle-only is not recorded")
        }
        XCTAssertTrue(try authoredComment(on: "imperialdramon_fighter").contains("FOUR-EDGE"),
                      "that the Imperialdramon Modes make Paildramon a four-edge Perfect is not recorded")
        XCTAssertTrue(try authoredComment(on: "jesmon").contains("FOUR-EDGE"),
                      "that the Jesmon make SaviorHackmon a four-edge Perfect is not recorded")
    }

    // MARK: - AC8: the orphan count, and what this sweep hands on

    /// The count that goes into `notes`, asserted rather than merely written down.
    func testThe27OrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 27)
        for (ultimate, _, _) in swept {
            XCTAssertNotNil(roster.entry(id: ultimate),
                            "\(ultimate) is an alias, so it removed no orphan")
        }

        XCTAssertEqual(graph.nodes.count, 915, "851 before this story, 878 after it")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "the Perfect rung must not have moved")
    }

    /// **The handover to US-167 onward: a claim, not a note.** What the remaining Ultimate sweeps
    /// inherit is the N-Z band and the sixteen Armor-Hybrid US-169 owns.
    func testWhatThisSweepHandsToTheRestOfTheUltimateRung() throws {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let stillOrphaned = roster.entries.filter { !$0.dexOnly && !connected.contains($0.id) }

        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate }.count, 2,
                       "the Ultimate edge-orphan bucket moved without this claim moving with it")
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
    /// helper US-144 through US-165 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
