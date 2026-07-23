import XCTest

@testable import DigiVPet

/// US-167 — the twenty-fifth of Phase E's orphan sweeps and **the fifth at the TOP rung**: the
/// twenty playable Ultimate whose display name begins N-R that no device tree and no earlier sweep
/// reached. The Ultimate edge-orphan bucket 39 -> 19; what remains is the S-Z band (US-168) and the
/// sixteen Armor-Hybrid US-169 owns.
///
/// **AN ULTIMATE SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE**, exactly as US-163/US-164/US-165/US-166
/// recorded: the rung is terminal, so there is no rung above to open, no junk floor to invent, and no
/// new line. Twenty orphans cost exactly twenty nodes, each hung as an EARNED branch beside the climb
/// its Perfect already has, with two criteria and a `requiredEnergy` distinct from every other edge on
/// that node. No leaf parents this story: all twenty Perfects already led somewhere.
///
/// Omegamon, Omegamon X/Zwart/Alter-S, Ogudomon and Ordinemon are Jogress results whose parents sit at
/// the Ultimate rung, off the one-rung ladder; each still takes a Perfect in-edge here, exactly as
/// Mastemon and Millenniumon did before them.
final class UltimateSweepNToRTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The twenty orphaned Ultimates this story wired, with the Perfect that now reaches each and the
    /// `requiredEnergy` of the new edge. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(ultimate: String, parent: String, energy: EnergyType)] = [
        ("omegamon", "chimairamon", .vitality),
        ("omegamon_x", "metalgreymon_x", .vitality),
        ("omegamon_zwart", "weregarurumon_black", .spirit),
        ("omegamon_alter-s", "metalgreymon_virus", .strength),
        ("ogudomon", "mephismon", .stamina),
        ("ogudomon_x", "mephismon_x", .stamina),
        ("ophanimon_core", "angewomon", .stamina),
        ("ophanimon_falldown_x", "angewomon_x", .vitality),
        ("rosemon_burst", "lilamon", .stamina),
        ("rosemon_x", "lilimon_x", .stamina),
        ("rapidmon_x", "rapidmon", .stamina),
        ("ragnalordmon", "grademon", .spirit),
        ("ragnamon", "nanomon", .strength),
        ("quantumon", "andromon", .strength),
        ("plesiomon_x", "megaseadramon_x", .vitality),
        ("princemamemon_x", "mamemon_x", .stamina),
        ("rusttyrannomon", "metaltyranomon", .stamina),
        ("rasenmon_fury", "hisyaryumon", .stamina),
        ("ordinemon", "lucemon_falldown", .vitality),
        ("nezhamon", "sanzomon", .spirit),
    ]

    // MARK: - AC1/AC2: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so an Ultimate sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableUltimateNToRIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .ultimate && !$0.dexOnly
                && ("N"..."R").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 39, "the N-R Ultimate range changed size")

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertFalse(graph.parents(of: entry.id).isEmpty, "\(entry.id) is evolved into by nothing")
        }

        // Nineteen of the thirty-nine were already wired before this story.
        let alreadyWired = ["noblepumpmon", "ophanimon", "ophanimon_x", "ouryumon", "piemon",
                            "pinochimon", "platinumnumemon", "plesiomon", "princemamemon", "pukumon",
                            "rafflesimon", "raguelmon", "raidenmon", "rasenmon", "rasielmon", "ravmon",
                            "regalecusmon", "rosemon", "ryugumon"]
        XCTAssertEqual(Set(inRange.map(\.id)),
                       Set(swept.map(\.ultimate)).union(alreadyWired),
                       "the range no longer partitions into this story's twenty and the nineteen before")
    }

    /// The whole-file form, so an Ultimate outside N-R that a later sweep is meant to take shows up as
    /// a falling number rather than as nothing at all.
    func testTheUltimateBucketFellByExactlyThisStorys20() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .ultimate && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)

        XCTAssertEqual(orphans.count, 19, "39 Ultimate were edge-orphaned before this story and 19 after")
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

    /// No new lines for twenty new nodes: every one joined a line that already had a Perfect rung.
    func testTheSweepOpenedNoNewLines() throws {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)
        for (ultimate, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: ultimate)).line
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            XCTAssertGreaterThan(perfects.count, 0,
                                 "\(line) has no Perfect rung, so \(ultimate) opened a line")
        }
    }

    // MARK: - AC4: the shape of every edge this story authored

    /// Every branch carries two criteria — one health metric and one care counter — each with a
    /// non-empty hint that states no number, and rises at the rung's 150 gate with two care mistakes
    /// allowed.
    func testEveryEarnedBranchCarriesOneHealthAndOneCareCriterion() throws {
        for (ultimate, parent, energy) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate },
                                     "\(parent) does not reach \(ultimate)")
            XCTAssertEqual(edge.requiredEnergy, energy)
            XCTAssertEqual(edge.minEnergy, 150, "\(ultimate)'s in-edge is not at the rung's gate")
            XCTAssertEqual(edge.maxCareMistakes, 2)
            XCTAssertFalse(edge.isDefault, "\(ultimate)'s branch displaced its Perfect's fallback")

            XCTAssertEqual(edge.conditions.count, 2,
                           "\(ultimate) is not gated on one health metric and one care counter")
            XCTAssertEqual(edge.conditions.filter { $0.knownMetric?.isHealthMetric == true }.count, 1,
                           "\(ultimate) is earned by walking alone or by playing alone")
            for condition in edge.conditions {
                XCTAssertNotNil(condition.knownMetric, "\(ultimate) names an unknown metric")
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(ultimate) has a criterion with no hint")
                XCTAssertFalse(condition.hint.contains(where: \.isNumber),
                               "\(ultimate)'s hint states a number that will go stale")
            }
        }
    }

    /// Every Perfect this story forked keeps the climb it had, still `isDefault` and still last.
    func testEveryForkedPerfectKeepsItsOwnClimbAsItsFallback() throws {
        for parent in Set(swept.map(\.parent)) {
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
    }

    /// The window trap: `care.battleCount` and `care.battleWinRatio` are answerable only over
    /// `lifetime` and every other `care.*` counter only over `stage`.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        for (_, parent, _) in swept {
            for edge in try XCTUnwrap(graph.node(id: parent)).evolutions {
                for condition in edge.conditions {
                    guard let metric = condition.knownMetric, !metric.isHealthMetric else { continue }
                    XCTAssertTrue(metric.canBeAnswered(over: condition.window),
                                  "\(parent) -> \(edge.to): \(metric.rawValue) over \(condition.window)")
                }
            }
        }
    }

    /// No branch is gated SOLELY on a metric that is typically empty on real hardware.
    func testNoBranchIsGatedSolelyOnAMetricThatIsEmptyOnRealHardware() throws {
        for (ultimate, parent, _) in swept {
            let edge = try XCTUnwrap(
                try XCTUnwrap(graph.node(id: parent)).evolutions.first { $0.to == ultimate })
            let known = edge.conditions.compactMap(\.knownMetric)
            XCTAssertFalse(known.allSatisfy(\.isSparseOnHardware),
                           "\(ultimate) is gated only on metrics a real watch rarely records")
        }
    }

    /// Proven through the ENGINE: a Digimon that earned the branch takes it, and one that did not falls
    /// to the Perfect's own climb instead.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarnedAndNotOtherwise() throws {
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.activeEnergy": 50_000,
                                               "health.exerciseMinutes": 5_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 50,
            battlesLifetime: 60,
            battleWinRatioLifetime: 1.0)

        for (ultimate, parent, energy) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == ultimate })
            let climb = try XCTUnwrap(node.evolutions.first(where: \.isDefault))

            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 60, conditions: met),
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

    /// The X-Antibody variants each hang off their base form's line or rise from the X form of the
    /// Perfect their base form uses — never across a line boundary.
    func testTheVariantsHangWithTheirLineage() throws {
        // Variant and base share ONE line (both are nodes this story added, on the same Perfect line).
        for (variant, base) in [("ogudomon_x", "ogudomon"), ("rosemon_x", "rosemon_burst")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) no longer shares \(base)'s line")
        }
        // Every X node this story added is an X-Antibody form on its parent's line.
        for variant in ["omegamon_x", "ogudomon_x", "ophanimon_falldown_x", "rosemon_x", "rapidmon_x",
                        "plesiomon_x", "princemamemon_x"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).variant, "X", variant)
        }
    }

    // MARK: - every choice is recorded in the data file

    func testEveryNodeThisStoryAddedCitesItsSource() throws {
        for (ultimate, _, _) in swept {
            let comment = try authoredComment(on: ultimate)
            XCTAssertTrue(comment.contains("Wikimon"),
                          "\(ultimate)'s comment neither cites a source nor says it has none")
            XCTAssertGreaterThan(comment.count, 200, "\(ultimate)'s comment is a stub")
        }
    }

    // MARK: - AC8: the orphan count, and what this sweep hands on

    func testThe20OrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 20)
        for (ultimate, _, _) in swept {
            XCTAssertNotNil(roster.entry(id: ultimate),
                            "\(ultimate) is an alias, so it removed no orphan")
        }

        XCTAssertEqual(graph.nodes.count, 898, "878 before this story, 898 after it")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "the Perfect rung must not have moved")
    }

    /// **The handover to US-168 and US-169: a claim, not a note.** What the last sweeps inherit is the
    /// S-Z Ultimate band and the sixteen Armor-Hybrid.
    func testWhatThisSweepHandsToTheRestOfTheUltimateRung() throws {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let stillOrphaned = roster.entries.filter { !$0.dexOnly && !connected.contains($0.id) }

        XCTAssertEqual(stillOrphaned.filter { $0.stage == .ultimate }.count, 19,
                       "the Ultimate edge-orphan bucket moved without this claim moving with it")
        XCTAssertEqual(stillOrphaned.filter { $0.stage == .armorHybrid }.count, 16,
                       "the Armor-Hybrid bucket is US-169's and must not have moved")
        XCTAssertEqual(stillOrphaned.filter { $0.stage != .ultimate && $0.stage != .armorHybrid },
                       [], "a rung below Ultimate is orphaned again")
    }

    // MARK: - Helpers

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
