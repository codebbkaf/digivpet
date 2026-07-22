import XCTest

@testable import DigiVPet

/// US-163 — the twentieth of Phase E's orphan sweeps and **the first at the TOP rung**: the thirty
/// playable Ultimate whose display name begins A-B that no device tree and no earlier sweep
/// reached. 146 orphans -> 116, the Ultimate bucket 130 -> 100.
///
/// **AN ULTIMATE SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE, AND THAT MAKES IT A DIFFERENT SHAPE OF
/// STORY FROM EVERY ONE BEFORE IT.** The AC asks for an out-edge only "unless it is a terminal
/// Ultimate", and every Ultimate in this file is terminal — so there is no rung above to open, no
/// junk floor to invent (`EvolutionCriteriaTests.branchingNodes` filters to Child and Adult, so the
/// Perfect rung owes none), and no new line. Thirty orphans cost exactly thirty nodes, which no
/// earlier sweep in this phase managed.
///
/// Two shapes of in-edge, and the parent decides which:
///
///  * FIVE leaf Perfects gain their single `isDefault` climb — Grademon -> Alphamon, Mametyramon ->
///    Bagramon, Canoweissmon -> Arcturusmon, BlackRapidmon -> BlackSaintGalgomon and MegaloGrowmon
///    -> Breakdramon. That is the shape every other Perfect in the file has carried since US-134,
///    and it takes five entries off `ChildSweepAToFTests`' dead-end ledger, 67 -> 62.
///  * The other twenty-five Perfects already HAVE that climb, so this story is **the first to fork
///    a Perfect**: an EARNED branch beside the climb, with two criteria and a `requiredEnergy` that
///    differs from the climb's. `EvolutionEngine.qualifies` matches on the DOMINANT type, so
///    distinct energies are what make the fork reachable in both directions rather than decorative.
///
/// **`algomon` IS STILL THE ONE LINE WITHOUT A PERFECT AND SO WITHOUT A MEGA, AND IT ALWAYS WILL
/// BE.** US-162 proved its Perfect rung can never open and then closed the rung; Algomon (Ultimate)
/// therefore lands on `penc-nso` under Mummymon, which is the only drawable parent Wikimon gives it
/// anywhere. Armamon is the story's one stranded node, and it is inherited rather than chosen: its
/// only cited Perfect parent is OmegaShoutmon, on the egg-less `xros` line.
final class UltimateSweepAToBTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The thirty orphaned Ultimates this story wired, with the Perfect that now reaches each and
    /// the `requiredEnergy` of the new edge. Every one is a plain roster id, so every one removes
    /// an orphan.
    private let swept: [(ultimate: String, parent: String, energy: EnergyType)] = [
        ("agumon_ynk", "metalgreymon_virus", .vitality),
        ("algomon_ultimate", "mummymon", .vitality),
        ("alphamon", "grademon", .strength),
        ("alphamon_ouryuken", "doruguremon", .spirit),
        ("amaterasumon", "shishimamon", .spirit),
        ("ancientbeatmon", "atlurkabuterimon_red", .stamina),
        ("ancientmegatheriumon", "mammon", .vitality),
        ("ancientmermaimon", "mermaimon", .vitality),
        ("ancientsphinxmon", "mummymon", .spirit),
        ("anubimon", "cerberumon_x", .spirit),
        ("apocalymon", "ladydevimon", .vitality),
        ("arcturusmon", "canoweissmon", .vitality),
        ("ariemon", "marinbullmon", .strength),
        ("armagemon", "chimairamon", .stamina),
        ("armamon", "omegashoutmon", .vitality),
        ("bagramon", "mametyramon", .strength),
        ("bancholilimon", "lilamon", .spirit),
        ("barbamon", "mephismon", .spirit),
        ("barbamon_x", "mephismon", .strength),
        ("beelzebumon_blast", "baalmon", .strength),
        ("beelzebumon_x", "baalmon", .vitality),
        ("belialvamdemon", "vamdemon", .vitality),
        ("belphemon_rage", "astamon", .stamina),
        ("belphemon_x", "astamon", .vitality),
        ("blacksaintgalgomon", "blackrapidmon", .strength),
        ("blackseraphimon", "holyangemon", .strength),
        ("blackwargreymon_x", "metalgreymon_virus_x", .stamina),
        ("blastmon", "insekimon", .strength),
        ("breakdramon", "megalogrowmon", .strength),
        ("brigadramon", "cargodramon", .strength),
    ]

    /// The five Perfects that were LEAVES before this story and now carry their one `isDefault`
    /// climb. Each is also an entry off the dead-end ledger in `ChildSweepAToFTests`.
    private let leafParents = ["blackrapidmon", "canoweissmon", "grademon", "mametyramon",
                               "megalogrowmon"]

    /// The shared "did everything right" context, US-151's through US-162's exactly.
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
        trainingSessionsThisStage: 30,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 40,
        battleWinRatioLifetime: 1.0)

    // MARK: - AC1/AC2: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so an Ultimate sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableUltimateAToBIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .ultimate && !$0.dexOnly
                && ("A"..."B").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 43, "the A-B Ultimate range changed size")

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertFalse(graph.parents(of: entry.id).isEmpty, "\(entry.id) has no in-edge")
        }

        // Thirteen of the forty-three were already wired before this story, which is why it
        // authored thirty and not forty-three: some are device-tree Megas and the rest are the
        // Megas the Perfect sweeps had to open under them — Apollomon is US-158's, BeelStarmon X
        // US-159's, Bryweludramon US-161's and BlackWarGreymon US-162's over Vermillimon.
        let alreadyWired = ["aegisdramon", "amphimon", "ancientvolcamon", "apollomon",
                            "bancholeomon", "banchomamemon", "beelstarmon_x", "beelzebumon",
                            "blackwargreymon", "blitzgreymon", "bloomlordmon", "boltmon",
                            "bryweludramon"]
        XCTAssertEqual(Set(inRange.map(\.id)),
                       Set(swept.map(\.ultimate)).union(alreadyWired),
                       "the range no longer partitions into this story's thirty and the thirteen before")
    }

    /// The whole-file form, so an Ultimate outside A-B that a later sweep is meant to take shows up
    /// as a falling number rather than as nothing at all.
    func testTheUltimateBucketFellByExactlyThisStorysThirty() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .ultimate && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)

        // 100 after this story; US-164 then took the C-D band down to 80 (two of the band,
        // Chaosdramon and Chaosmon, are Jogress results it left unwired, so 80 is the
        // evolution-edge count and 78 the true owed remainder).
        XCTAssertEqual(orphans.count, 39,
                       "130 before US-163, 100 after; US-164 reached 80, US-165 reached 66")
        for (ultimate, _, _) in swept {
            XCTAssertFalse(orphans.contains(ultimate), "\(ultimate) is still an orphan")
        }
    }

    // MARK: - AC2: an in-edge, and no out-edge, because the rung is terminal

    /// Every node this story added is a leaf, which at this rung is the whole of the AC's second
    /// half: "unless it is a terminal Ultimate". A node here with an out-edge would have to point
    /// off the ladder entirely.
    func testEveryUltimateThisStoryAddedIsTerminal() throws {
        for (ultimate, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertTrue(node.evolutions.isEmpty,
                          "\(ultimate) leads somewhere, which nothing at the top rung may")
        }
    }

    /// Each new node sits on its parent's line, which is not a choice: `testNoEdgeCrossesALine`
    /// below makes any other placement a broken file.
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

    /// No new lines for thirty new nodes, and the count is the file's rather than this story's.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 121)
        XCTAssertEqual(sizes["penc-nso"], 81)
        XCTAssertEqual(sizes["penc-me"], 73)
        XCTAssertEqual(sizes["dmc-v1"], 39)
        XCTAssertEqual(sizes["penc-vb"], 60)
        XCTAssertEqual(sizes["penc-ds"], 48)
        XCTAssertEqual(sizes["penc-nsp"], 44)
        XCTAssertEqual(sizes["dmc-v3"], 54)
        XCTAssertEqual(sizes["vital"], 42)
        XCTAssertEqual(sizes["palmon"], 30)
        XCTAssertEqual(sizes["xros"], 22)
    }

    // MARK: - AC4: the shape of every edge this story authored

    /// **The AC's "no edge is unconditional" binds the EARNED edges, and this is where it is
    /// checked.** The twenty-five branches beside an existing climb each carry two criteria with a
    /// non-empty hint. The five leaf climbs do NOT, and must not: `SeedRosterTests` requires a node
    /// with edges to have exactly one `isDefault` fallback, US-020 takes that fallback whatever the
    /// gates say, and so a condition on one would be data that lies about how it is taken — the
    /// reading every rung below this one recorded.
    func testEveryEarnedBranchCarriesCriteriaAndEveryLeafClimbDoesNot() throws {
        for (ultimate, parent, energy) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate },
                                     "\(parent) does not reach \(ultimate)")
            XCTAssertEqual(edge.requiredEnergy, energy)
            XCTAssertEqual(edge.minEnergy, 150, "\(ultimate)'s in-edge is not at the rung's gate")
            XCTAssertEqual(edge.maxCareMistakes, 2)

            if leafParents.contains(parent) {
                XCTAssertTrue(edge.isDefault, "\(parent)'s only edge is not its fallback")
                // US-166 forked Megalo Growmon (Megidramon and Megidramon X) beside the isDefault
                // climb to Breakdramon this story gave it, so it is no longer a single edge.
                XCTAssertEqual(node.evolutions.count, parent == "megalogrowmon" ? 3 : 1,
                               "\(parent) is not a single climb")
                XCTAssertEqual(edge.conditions, [], "\(parent)'s fallback carries criteria")
            } else {
                XCTAssertFalse(edge.isDefault, "\(ultimate)'s in-edge is a fallback, not earned")
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

    /// Every Perfect this story forked keeps the climb it had, still marked `isDefault`. Fifteen
    /// earlier tests describe those climbs; a branch that displaced one would be a silent retune of
    /// the whole rung.
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
    /// leave the lower-`minEnergy` one unreachable for good — and three of these Perfects now carry
    /// three edges apiece.
    func testNoPerfectThisStoryForkedOffersTwoEdgesOnOneEnergy() throws {
        for parent in Set(swept.map(\.parent)) {
            let energies = try XCTUnwrap(graph.node(id: parent)).evolutions.compactMap(\.requiredEnergy)
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two edges on the same energy")
        }

        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mummymon")).evolutions.count, 3)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "mephismon")).evolutions.count, 3)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "astamon")).evolutions.count, 3)
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "baalmon")).evolutions.count, 3)
    }

    /// Proven through the ENGINE rather than argued: a Digimon that earned the branch takes it, and
    /// a Digimon that did not falls to the Perfect's own climb instead. Both directions, because
    /// only the pair rules out an edge that is either unreachable or unavoidable.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarnedAndNotOtherwise() throws {
        for (ultimate, parent, energy) in swept where !leafParents.contains(parent) {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate })
            let climb = try XCTUnwrap(node.evolutions.first(where: \.isDefault))

            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 40,
                                                conditions: context(for: edge)),
                ultimate,
                "a \(parent) that earned \(ultimate) does not reach it")

            // Nothing earned at all: the time gate opens and US-020's fallback takes the climb.
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: node, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 0,
                    battleWins: 0, stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                climb.to,
                "a \(parent) that earned nothing does not climb to \(climb.to)")
        }
    }

    /// The five leaf climbs are the only way on from their Perfect, so the engine has to take them
    /// for a Digimon that did nothing in particular — which is the point of an `isDefault` edge.
    func testTheFiveClearedLeavesClimbForADigimonThatEarnedNothing() throws {
        for parent in leafParents {
            let node = try XCTUnwrap(graph.node(id: parent))
            // The isDefault climb, not `.first` — US-166 forked Megalo Growmon, so its earned
            // branches now sort ahead of the Breakdramon climb a neglected Digimon still takes.
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
    /// `ConditionMetric.isSparseOnHardware` states and US-128's validator enforces for map drops.
    /// Three of these edges reach for daylight, which is in that family; each is paired with a care
    /// counter, so none of them is a gate no watch can open.
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

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate.
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

    /// Nothing on either end of a new edge is a Dex-only Digimon — the whole-file form, since the
    /// validator's `edgeToDexOnlyNode` finding is what would fire.
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

    /// **THE STRONG FORM OF THE VARIANT RULE — SAME PARENT, NOT MERELY SAME LINE — HOLDS FOR THREE
    /// OF THE FOUR X-ANTIBODY MEGAS, AND IT HAD TO.** Barbamon X, Beelzebumon X and Belphemon X
    /// each have an `Evolves From` on Wikimon made ENTIRELY of Ultimates (their own base form is
    /// the bolded one), so no citation of their own could ever be drawn at this rung; each hangs
    /// off the Perfect its base form hangs off. BlackWarGreymon X is the exception and follows a
    /// cited parent instead — the escape hatch `ChildSweepMToZTests` opened.
    func testTheVariantsSitWithTheirBaseFormOrFollowACitedParent() throws {
        for (variant, base) in [("barbamon_x", "barbamon"), ("beelzebumon_x", "beelzebumon_blast"),
                                ("belphemon_x", "belphemon_rage")] {
            XCTAssertEqual(graph.parents(of: variant).map(\.id), graph.parents(of: base).map(\.id),
                           "\(variant) no longer hangs off \(base)'s own Perfect")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line)
        }

        // Beelzebumon Blast Mode is itself hung beside the plain Beelzebumon this file already had,
        // on the Perfect that carries it, so all three sit on one node.
        XCTAssertEqual(Set(graph.parents(of: "beelzebumon").map(\.id)), ["baalmon", "ladydevimon"])
        XCTAssertTrue(graph.parents(of: "beelzebumon").map(\.id).contains("baalmon"))

        // And the one that does not, with the reason pinned at both ends: its base form is on
        // `adventure02`, where US-162 could open only one Champion, and Vermillimon does not cite
        // this variant — while the whole X-Antibody Greymon thread on `dmc-v1` does.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "blackwargreymon")).line, "adventure02")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "blackwargreymon_x")).line, "dmc-v1")
        XCTAssertEqual(graph.parents(of: "blackwargreymon_x").map(\.id), ["metalgreymon_virus_x"])
        XCTAssertTrue(try authoredComment(on: "blackwargreymon_x").contains("Metal Greymon (Virus)"))
    }

    /// Alphamon and Alphamon: Ouryuken are one Digimon and its own fusion form, so they land on one
    /// line — `tamers`, where the whole DORUmon thread lives — even though they take different
    /// Perfects. Both arrows are cited.
    func testTheTwoAlphamonLandOnTheDORUmonLine() throws {
        for id in ["alphamon", "alphamon_ouryuken"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "tamers")
        }
        XCTAssertEqual(graph.parents(of: "alphamon").map(\.id), ["grademon"])
        XCTAssertEqual(graph.parents(of: "alphamon_ouryuken").map(\.id), ["doruguremon"])
        XCTAssertTrue(try authoredComment(on: "alphamon").contains("BOLDED"))
    }

    /// This story authored no one-node line and no line at all, which is the second half of AC3:
    /// every new node joined a line that already had at least a Champion rung on it.
    func testEveryLineThisStoryTouchedAlreadyHadAPerfectRung() throws {
        for (ultimate, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: ultimate)).line
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            XCTAssertGreaterThan(perfects.count, 1,
                                 "\(line) has no Perfect rung to speak of, so \(ultimate) opened one")
        }
    }

    // MARK: - The five leaves this story cleared

    /// The dead-end ledger's other direction, asserted from this side too: each of the five really
    /// does lead somewhere now, and each was a LEAF rather than an orphan — it had an in-edge all
    /// along, which is why it was never in an earlier sweep's scope.
    func testTheFiveLeafPerfectsThisStoryClearedNowClimb() throws {
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

    // MARK: - The nodes with no drawable citation, and the one stranded node

    /// **A CLAIM THIS SWEEP HAS TO MAKE OUT LOUD.** Four of the thirty could not follow a bolded
    /// parent and the reason is written into the node rather than left to be re-derived: Agumon
    /// -Yuki no Kizuna- and Armagemon because their bolded parent is at the wrong RUNG, Anubimon
    /// and Algomon because theirs has no sheet in this pack at all.
    func testTheNodesWithNoDrawableBoldedParentSayItInAsManyWords() throws {
        // A Child or a Baby I cannot be an in-edge at this rung —
        // `GraphValidationError.invalidStageTransition`, the Lucemon Falldown shape US-159 recorded.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "agumon")).stage, .child)
        XCTAssertTrue(try authoredComment(on: "agumon_ynk").contains("invalidStageTransition"))
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kuramon")).stage, .babyI)
        XCTAssertTrue(try authoredComment(on: "armagemon").contains("invalidStageTransition"))

        // And the two whose bolded parent simply is not drawn. Both say NO SHEET.
        XCTAssertNil(roster.entries.first { $0.displayName == "Cerberumon" })
        XCTAssertTrue(try authoredComment(on: "anubimon").contains("NO SHEET"))
        XCTAssertNil(roster.entries.first { $0.stage == .perfect && $0.displayName == "Algomon" })
        XCTAssertTrue(try authoredComment(on: "algomon_ultimate").contains("no sheet"))

        // The `diablomon` line really cannot take Armagemon: both of the Perfect rungs the Kuramon
        // swarm climbs through are idle-only, which `edgeToDexOnlyNode` forbids, so the line has no
        // Perfect that could ever carry the arrow.
        for id in ["chrysalimon", "infermon"] {
            XCTAssertEqual(try XCTUnwrap(roster.entry(id: id)).dexOnly, true)
            XCTAssertNil(graph.node(id: id))
        }
    }

    /// **BANCHOLILIMON'S BOLDED PARENT WAS REFUSED BY A TEST RATHER THAN BY THE DATA**, which is
    /// the one placement in this story a later reader is most likely to question. Lilimon is on
    /// `palmon` and free; hanging an earned branch on it would have redirected US-002's first named
    /// line, because `SeedRosterTests.testTheThreeNamedLinesAreTheOnesShipped` walks that line by
    /// preferring the earned edge at every rung. Lilamon is Lilimon's own sister form, cited on the
    /// same page, on the same line.
    func testBanchoLilimonTookLilamonSoTheNamedPalmonLineStillEndsAtRosemon() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lilimon")).evolutions.map(\.to), ["rosemon"],
                       "Lilimon gained a branch, and US-002's named line no longer ends at Rosemon")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "lilamon")).line,
                       try XCTUnwrap(graph.node(id: "lilimon")).line)
        XCTAssertEqual(graph.parents(of: "bancholilimon").map(\.id), ["lilamon"])
        XCTAssertTrue(try authoredComment(on: "bancholilimon").contains("SeedRosterTests"))
    }

    /// Armamon is the story's only stranded node, and it is inherited: `xros` has no Digitama —
    /// US-144 and US-145 spent all fifty-seven — so everything above Shoutmon King has always been
    /// unreachable from an egg. Pinned here as well as in `EvolutionCriteriaTests` because this is
    /// where a reader looks for what this story left behind.
    func testArmamonIsTheOnlyNodeThisStoryStrandedAndItInheritedIt() throws {
        var reached = Set(graph.nodes(at: .digitama).map(\.id))
        var frontier = Array(reached)
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        XCTAssertEqual(swept.map(\.ultimate).filter { !reached.contains($0) }, ["armamon"])
        XCTAssertFalse(reached.contains("omegashoutmon"), "Armamon's only parent became reachable")
        XCTAssertTrue(graph.nodes.filter { $0.line == "xros" && $0.stage == .digitama }.isEmpty,
                      "`xros` gained a Digitama, so Armamon is no longer stranded by inheritance")
    }

    /// `algomon` is the one line with no Perfect and so no Mega, and US-162 proved it can never
    /// gain one. Algomon (Ultimate) is therefore on `penc-nso`, which is the whole reason this
    /// story could wire it at all.
    func testAlgomonStillHasNoPerfectRungAndItsMegaLandedElsewhere() {
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect), ["algomon"])

        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAnUltimate), ["algomon"])
        XCTAssertEqual(graph.node(id: "algomon_ultimate")?.line, "penc-nso")
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

        // The rejected and undrawable readings are written down too, so the story that revisits one
        // is told which arrow was considered and why it lost rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "agumon_ynk").contains("SeedRosterTests"),
                      "the reason MetalGreymon could not carry Agumon YnK is not named")
        XCTAssertTrue(try authoredComment(on: "apocalymon").contains("INVERTED"),
                      "Apocalymon's inverted care gate is not explained")
        XCTAssertTrue(try authoredComment(on: "blackseraphimon").contains("INVERTED"),
                      "BlackSeraphimon's inverted care gate is not explained")
        XCTAssertTrue(try authoredComment(on: "belphemon_rage").contains("CRITERIA ARE THE DIGIMON"),
                      "Belphemon's sleep-then-wake criteria are not explained")
        XCTAssertTrue(try authoredComment(on: "barbamon").contains("ITEM"),
                      "that Barbamon's bolded parent is an item and not a Digimon is not recorded")
    }

    /// **TWO EDGES IN THIS STORY ARE EARNED BY LOSING**, which the Lucemon Falldown and
    /// WereGarurumon Black arrangement established: Apocalymon is what despair makes and
    /// BlackSeraphimon is a fallen angel, so each asks for a losing record rather than a winning
    /// one. Proven through the engine in both directions rather than argued.
    func testTheTwoFallenMegasAreEarnedByLosingRatherThanByWinning() throws {
        for (ultimate, parent) in [("apocalymon", "ladydevimon"), ("blackseraphimon", "holyangemon")] {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate })
            let ratio = try XCTUnwrap(edge.conditions.first { $0.metric == "care.battleWinRatio" })
            XCTAssertEqual(ratio.comparison, .atMost, "\(ultimate)'s losing gate became a winning one")

            var totals = EnergyTotals()
            totals[try XCTUnwrap(edge.requiredEnergy)] = edge.minEnergy
            XCTAssertNotEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                                dominant: edge.requiredEnergy, careMistakes: 0,
                                                battleWins: 40, conditions: met),
                ultimate,
                "a \(parent) that won everything still becomes \(ultimate)")
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                                dominant: edge.requiredEnergy, careMistakes: 0,
                                                battleWins: 40, conditions: context(for: edge)),
                ultimate,
                "a \(parent) that lost does not become \(ultimate)")
        }
    }

    // MARK: - AC8: the orphan count, and what this sweep hands on

    /// The count that goes into `notes`, asserted rather than merely written down.
    func testTheThirtyOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 30)
        for (ultimate, _, _) in swept {
            XCTAssertNotNil(roster.entry(id: ultimate),
                            "\(ultimate) is an alias, so it removed no orphan")
        }

        XCTAssertEqual(graph.nodes.count, 878, "787 before this story, 817 after it")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 199, "108 before this story, 172 after US-165")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "the Perfect rung must not have moved")
    }

    /// **The handover to US-164 onward, in the shape US-151 through US-162 established: a claim,
    /// not a note.** What the remaining Ultimate sweeps inherit is a rung that is one-fifth done,
    /// sixty-two Perfect leaves still owed a climb, and the sixteen Armor-Hybrid US-169 owns.
    func testWhatThisSweepHandsToTheRestOfTheUltimateRung() throws {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let stillOrphaned = roster.entries.filter { !$0.dexOnly && !connected.contains($0.id) }

        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate }.count, 39,
                       "the Ultimate bucket moved without this claim moving with it")
        XCTAssertEqual(stillOrphaned.filter { $0.stage == .armorHybrid }.count, 16,
                       "the Armor-Hybrid bucket is US-169's and must not have moved")
        XCTAssertEqual(stillOrphaned.filter { $0.stage != .ultimate && $0.stage != .armorHybrid },
                       [], "a rung below Ultimate is orphaned again")

        // Ogudomon is still the one US-159 pinned in Lucemon Falldown's comment; its display name
        // begins O, so it belongs to US-167 rather than to this story.
        XCTAssertNotNil(roster.entry(id: "ogudomon"))
        XCTAssertNil(graph.node(id: "ogudomon"))
    }

    // MARK: - Helpers

    /// A context derived from the EDGE's own conditions rather than the shared "did everything
    /// right" one, because that fixture cannot satisfy an `atMost` criterion — US-151's rule.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30
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
            battlesLifetime: 40,
            battleWinRatioLifetime: winRatio)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-162 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
