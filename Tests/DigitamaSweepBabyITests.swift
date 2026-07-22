import XCTest

@testable import DigiVPet

/// US-146 — the third of Phase E's 26 orphan sweeps, and the whole Baby I rung.
///
/// **Which reading of the story's scope this takes, and why.** The PRD's Appendix A lists 38
/// orphaned Baby I, and the acceptance criteria ask for an in-edge AND an out-edge on each. US-144
/// and US-145 gave 25 of the 38 an in-edge from a Digitama, and the other criterion — an out-edge —
/// was left for this story on all of them. So the scope here is the RUNG, not the 13 names still
/// orphaned when the story started: every playable Baby I in the file gets a Baby II above it, and
/// the 13 that were never wired at all are authored too.
///
/// **The half of the criteria that cannot be met, stated up front rather than discovered.** Those
/// 13 Baby I can never have an in-edge. A Baby I's only possible parent is a Digitama;
/// `EggHatcher.hatchTarget` reads `node.evolutions.first`, so an egg carries exactly ONE hatch edge;
/// and US-144 and US-145 between them spent all 57. `DigitamaSweepLToZTests` proved that 12 was the
/// most any authoring of the last 23 eggs could have opened, so this is arithmetic, not an omission
/// — see `testTheThirteenBabyIWithNoParentAreTheOnesTheDigitamaRanOutOn`. They are authored anyway,
/// because a Digimon that evolves into something is a Dex entry with a tree; one that does neither
/// is a dead sprite.
///
/// What the sweep DOES deliver on the whole rung: 45 playable Baby I, 45 with an out-edge, zero
/// orphans left at the stage, and the dead-end ledger moved up one rung to Baby II for US-147.
final class DigitamaSweepBabyITests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The story's scope, derived rather than listed, so a Baby I sprite added to the folder later
    /// lands IN scope and fails here.
    private var babyIInRange: [RosterEntry] {
        roster.entries.filter { $0.stage == .babyI && !$0.dexOnly }
    }

    /// The graph's own Baby I, which is TWO more than the roster's 43: `piyo_yuramon` and
    /// `pencnsp_botamon` are line-scoped aliases of a Digimon that already had a node elsewhere, so
    /// they are nodes without being separate roster entries. Everything asserted about the shape of
    /// the rung is asserted over these, not over the roster, so an alias cannot dodge it.
    private var babyINodes: [EvolutionNode] { graph.nodes(at: .babyI) }

    /// The thirteen Baby I that had no node at all before this story — the ones still orphaned
    /// after US-144 and US-145, and the ones no egg can ever hatch into.
    private let authoredBabyI = ["bombmon", "chibickmon", "curimon", "fufumon", "fukamon",
                                 "pafumon", "paomon", "petitmon", "pupumon", "pururumon",
                                 "pusumon", "puyomon", "pyonmon"]

    /// Every edge this story authored, as (Baby I, Baby II). Thirty-three of them: the twenty Baby
    /// I that US-144 and US-145 left as dead ends, plus the thirteen authored here.
    private let authoredEdges: [(babyI: String, babyII: String)] = [
        ("algomon_babyi", "algomon_babyii"),
        ("bommon", "kyokyomon"),
        ("cocomon", "chocomon"),
        ("dodomon", "wanyamon"),
        ("popomon", "wanyamon"),
        ("jyarimon", "gigimon"),
        ("kiimon", "yaamon"),
        ("kuramon", "tsumemon"),
        ("bubbmon", "mochimon"),
        ("chicomon", "chibimon"),
        ("cotsucomon", "kakkinmon"),
        ("dokimon", "bibimon"),
        ("ketomon", "dorimon"),
        ("leafmon", "minomon"),
        ("pipimon", "tanemon"),
        ("relemon", "moonmon"),
        ("sunamon", "goromon"),
        ("tomorimon", "onibimon"),
        ("tsubumon", "tokomon"),
        ("zerimon", "gummymon"),
        ("bombmon", "monimon"),
        ("chibickmon", "pickmon"),
        ("petitmon", "babydmon"),
        ("fufumon", "kyokyomon"),
        ("pupumon", "puroromon"),
        ("fukamon", "mococomon"),
        ("paomon", "xiaomon"),
        ("pururumon", "poromon"),
        ("curimon", "wanyamon"),
        ("pafumon", "yaamon"),
        ("pyonmon", "mochimon"),
        ("pusumon", "pusurimon"),
        ("puyomon", "pukamon"),
    ]

    /// The twenty-five Baby II this story authored, each a leaf until US-147 wires its Child. Three
    /// of the thirty-three edges above land on a Baby II that already existed (`tanemon`,
    /// `tokomon`, `pukamon`), which is why this is 25 and not 33.
    private let authoredBabyII = ["algomon_babyii", "babydmon", "bibimon", "chibimon", "chocomon",
                                  "dorimon", "gigimon", "goromon", "gummymon", "kakkinmon",
                                  "kyokyomon", "minomon", "mochimon", "mococomon", "monimon",
                                  "moonmon", "onibimon", "pickmon", "poromon", "puroromon",
                                  "pusurimon", "tsumemon", "wanyamon", "xiaomon", "yaamon"]

    private let newLines = ["xros", "penc-sw"]

    // MARK: - AC: every orphan in range is wired

    /// The rung's headline claim, counted off the roster rather than off the list above: every
    /// playable Baby I on disk is a node, and every one of them evolves into something.
    func testEveryPlayableBabyIIsANodeWithAnOutEdge() {
        XCTAssertEqual(babyIInRange.count, 43)
        for entry in babyIInRange {
            XCTAssertNotNil(graph.node(id: entry.id),
                            "\(entry.id) (\(entry.displayName)) is still not in evolutions.json")
        }
        XCTAssertEqual(babyINodes.count, 45)
        for node in babyINodes {
            XCTAssertFalse(node.evolutions.isEmpty,
                           "\(node.id) leads nowhere — it is a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the stage this story owns. A node is an orphan until
    /// it is the source or the target of an edge, so an out-edge is enough — which is what makes
    /// "13 Baby I can never be hatched" and "0 Baby I are orphans" both true at once, and why the
    /// two facts are asserted side by side rather than one being allowed to stand for the other.
    func testTheBabyIRungHasNoOrphansLeft() {
        let connected = self.connected()
        let orphans = babyINodes.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Baby I still orphaned: \(orphans)")
        XCTAssertEqual(authoredEdges.count, 33)
    }

    /// The thirteen with no parent, named and explained. The count is the arithmetic
    /// `DigitamaSweepLToZTests` proved, and this test is the other side of it: not one of these can
    /// be given an in-edge by any later story, because there is no unspent Digitama in the file and
    /// nothing but a Digitama may point at a Baby I.
    func testTheThirteenBabyIWithNoParentAreTheOnesTheDigitamaRanOutOn() {
        let parentless = babyINodes
            .map(\.id)
            .filter { graph.parents(of: $0).isEmpty }
            .sorted()
        XCTAssertEqual(parentless, authoredBabyI.sorted())

        let spareEggs = roster.entries
            .filter { $0.stage == .digitama && !$0.dexOnly }
            .filter { (graph.node(id: $0.id)?.evolutions.count ?? 0) == 0 }
            .map(\.id)
        XCTAssertEqual(spareEggs, [], "an egg is unspent after all — it should adopt one of the 13")
    }

    /// Every other Baby I in the file DOES have a parent, and it is an egg. The second half is what
    /// stops the first from being satisfied by a rung skipped: a Baby I fed by another Baby I would
    /// have a parent, and the validator's stage check would not see it as a mistake either.
    func testEveryOtherBabyIIsFedByADigitamaAndNothingElse() {
        for node in babyINodes where !authoredBabyI.contains(node.id) {
            let parents = graph.parents(of: node.id)
            XCTAssertFalse(parents.isEmpty, "\(node.id) lost its in-edge")
            for parent in parents {
                XCTAssertEqual(parent.stage, .digitama, "\(node.id) is fed by a non-Digitama")
            }
        }
    }

    // MARK: - AC: the edges themselves

    /// Every authored edge is really in the file, at the rungs it claims, and is the node's FIRST
    /// way out — the `isDefault` one.
    ///
    /// **This said "only way out" until US-147, and the change is a real one rather than a
    /// loosening.** US-146 could say it because a Baby I's one edge was the shape the twelve
    /// device-tree Baby I already had. US-147 then had twelve Baby II with no parent and nothing
    /// but a Baby I able to give them one, so nine Baby I gained a SECOND (Puttimon, Kuramon and
    /// Piyo's Yuramon a third). Those branches are conditional and this one is not, which is what
    /// keeps `testEachAuthoredEdgeIsTakenByTheEngineOnItsOwnEnergy` below honest: under
    /// `.unknown` conditions no branch can qualify, so the edge asserted here is still what a
    /// Baby I takes on its own energy.
    func testEachAuthoredEdgeIsTheBabyIsDefaultWayUpOneRung() throws {
        for (babyI, babyII) in authoredEdges {
            let node = try XCTUnwrap(graph.node(id: babyI), "no node \(babyI)")
            XCTAssertEqual(node.stage, .babyI)
            let target = try XCTUnwrap(graph.node(id: babyII), "no node \(babyII)")
            XCTAssertEqual(target.stage, .babyII, "\(babyII) is not a Baby II")
            XCTAssertEqual(node.evolutions.filter(\.isDefault).map(\.to), [babyII],
                           "\(babyI)'s fallback is no longer \(babyII)")
        }
    }

    /// The engine's view of the same thing: a Baby I that earned the edge's energy really evolves,
    /// rather than the edge merely existing. Read through `EvolutionEngine` so a gate authored
    /// wrong — a `requiredEnergy` that no dominant type can match, a `minEnergy` above what the
    /// rung can earn — fails here instead of stranding the player.
    func testEachAuthoredEdgeIsTakenByTheEngineOnItsOwnEnergy() throws {
        for (babyI, babyII) in authoredEdges {
            let node = try XCTUnwrap(graph.node(id: babyI))
            let edge = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            let energy = try XCTUnwrap(edge.requiredEnergy, "\(babyI) has no requiredEnergy")
            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 0),
                babyII,
                "\(babyI) does not evolve into \(babyII) on the energy its own edge asks for")
        }
    }

    /// A Baby I's FALLBACK edge carries no `conditions`, and that is a decision rather than an
    /// omission — the same one US-144 recorded for the hatch edges, for the same reason one rung
    /// up. US-020 takes the `isDefault` edge once the stage's time gate opens and nothing else
    /// qualifies, so a condition on it could never decide anything; it would be a hint describing a
    /// gate that does not gate. The four energy gates still do real work — they are what
    /// `testEachAuthoredEdgeIsTakenByTheEngineOnItsOwnEnergy` reads.
    ///
    /// **US-146 could also say every Baby I had exactly ONE edge; US-147 spent nine of them on a
    /// second.** That half moved to `BabyIISweepTests.testEveryBabyIThatBranchesDoesSoForAnOrphan`,
    /// which names the nine and proves each branch buys a Baby II that had no other possible
    /// parent — so a tenth branch authored for convenience still fails somewhere.
    func testEveryBabyIsFallbackEdgeIsUnconditional() throws {
        for node in babyINodes {
            let defaults = node.evolutions.filter(\.isDefault)
            XCTAssertEqual(defaults.count, 1, "\(node.id) has no single fallback")
            let edge = try XCTUnwrap(defaults.first)
            XCTAssertTrue(edge.conditions.isEmpty, "\(node.id) gates its fallback on a condition")
        }
    }

    // MARK: - The dead-end ledger, moved up one rung

    /// US-146's half of the dead-end ledger, flipped in place now that US-147 has wired it: the
    /// twenty-five Baby II this sweep opened all lead somewhere. The whole-file ledger moved up a
    /// rung with the sweep, to
    /// `BabyIISweepTests.testTheOnlyDeadEndsBelowUltimateAreTheChildrenThisSweepOpened`.
    ///
    /// Wiring one of the twenty-five back into a leaf fails here, which is the direction this copy
    /// still guards.
    func testTheBabyIIThisSweepOpenedAllLeadSomewhereNow() {
        for id in authoredBabyII {
            XCTAssertFalse(graph.node(id: id)?.evolutions.isEmpty ?? true,
                           "\(id) is a dead end again — US-147 gave it a Child")
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line. It held for all 365 nodes before this story and has to
    /// keep holding: a Baby I that could not be put on the line of the Baby II above it has been
    /// paired with the wrong Baby II.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// The criterion is that a sweep must not produce dozens of one-node lines, and the answer here
    /// is TWO new lines for 38 new nodes — 30 of them went onto lines that already exist. Sizes are
    /// asserted as well as membership, since a line of one would satisfy "only two new lines" and
    /// still be the thing the rule forbids.
    /// The sizes moved when US-147 wired the Child rung above these eight (`xros` 6 -> 9,
    /// `penc-sw` 2 -> 5), so the claim is stated as MEMBERSHIP rather than as a count: these eight
    /// of the thirty-eight are the ones that opened a line, and the other thirty went onto lines
    /// that already existed. A ninth US-146 node appearing on a new line still fails it.
    func testTheSweepOpenedTwoLinesAndPutTheRestOntoExistingOnes() {
        let authored = Set(authoredBabyI + authoredBabyII)
        XCTAssertEqual(authored.count, 38)
        let onNewLines = authored.filter { newLines.contains(graph.node(id: $0)?.line ?? "") }
        XCTAssertEqual(onNewLines, ["bombmon", "monimon", "chibickmon", "pickmon",
                                    "petitmon", "babydmon", "fukamon", "mococomon"])
        XCTAssertEqual(authored.subtracting(onNewLines).count, 30)
    }

    /// The eight nodes on the two new lines are grouped on a fact about a DEVICE, not on a vibe —
    /// the same check US-145 used to justify `vital`. Wikimon's Virtual Pets section is
    /// machine-readable, and every Digimon on `xros` appears in the Digimon Xros Loader while every
    /// Digimon on `penc-sw` appears in the Pendulum COLOR 6 Saiyu Warriors. The node comments are
    /// what record it, so this test reads them.
    func testEachNewLineNamesTheDeviceItsMembersShare() throws {
        for id in graph.nodes.filter({ $0.line == "xros" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Xros"),
                          "\(id) is on the Xros Loader line without saying so")
        }
        for id in graph.nodes.filter({ $0.line == "penc-sw" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Saiyu Warriors"),
                          "\(id) is on the Saiyu Warriors line without saying so")
        }
    }

    /// Every new line resolves to a Dex heading and to a training game. Both are keyed on strings
    /// the JSON owns, and a line missing from either degrades silently.
    func testEveryNewLineHasAHeadingAndAGame() {
        for line in newLines {
            let title = DexModel.lineTitles[line]
            XCTAssertNotNil(title, "line \(line) has no Dex heading")
            XCTAssertNotEqual(title, line, "line \(line) heads its section with its own key")
            XCTAssertNotNil(MinigameAssignment.byLine[line], "line \(line) has no training game")
        }
    }

    // MARK: - AC: the data the story rests on

    /// Every node this story added names art that exists, at the stage the ROSTER files it under.
    /// `EvolutionGraphValidator` checks the first half; this checks the second, which is the one
    /// that bites — `import_roster.py` reads a Digimon's rung off its sprite FOLDER, so a node
    /// authored at the wrong stage resolves to no art at all.
    func testEveryNodeThisSweepAddedAgreesWithTheRoster() throws {
        for id in authoredBabyI + authoredBabyII {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.stage, entry.stage, "\(id) is authored at the wrong rung")
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the 157 idle-only Digimon")
        }
    }

    /// The sweep had no document to copy, so every node it added cites Wikimon in its `comment`. A
    /// comment that cites nothing is the shape of an invented evolution.
    func testEveryNodeThisSweepAddedCitesItsSource() throws {
        for id in authoredBabyI + authoredBabyII {
            XCTAssertTrue(try authoredComment(on: id).contains("Wikimon"),
                          "\(id) is authored without naming where the arrow comes from")
        }
    }

    /// The four pairings that are NOT a Wikimon arrow are the story's weak spot — a stand-in is the
    /// one thing a later reader cannot tell from a shortcut — so each states which rung was missing
    /// and which arrow the stand-in was chosen on. Three are rehomes onto a shared next rung; the
    /// fourth, Bombmon, has no arrow at all and says the word FLAVOUR rather than dressing itself
    /// as a citation. Each stated fact is checked against the roster, not merely read.
    func testEveryStandInSaysWhichRungWasMissingAndWhy() throws {
        // (the Baby I, the Baby II that is missing or idle-only, whether it is on disk at all)
        let rehomes: [(babyI: String, missing: String, dexOnlyOnDisk: Bool)] = [
            ("curimon", "Gurimon", false),
            ("pafumon", "Kyaromon", true),
            ("pyonmon", "Bosamon", false),
            ("puyomon", "Puyoyomon", false),
        ]
        for (babyI, missing, dexOnlyOnDisk) in rehomes {
            let comment = try authoredComment(on: babyI)
            XCTAssertTrue(comment.contains("REHOME"), "\(babyI) hides that it is a stand-in")
            XCTAssertTrue(comment.contains(missing),
                          "\(babyI) does not name the Baby II it could not use")
            let entry = roster.entries.first { $0.displayName == missing }
            if dexOnlyOnDisk {
                XCTAssertEqual(entry?.dexOnly, true,
                               "\(missing) is not idle-only, so \(babyI) had a choice")
            } else {
                XCTAssertNil(entry, "\(missing) IS on disk, so \(babyI) had a choice")
            }
        }

        let bombmon = try authoredComment(on: "monimon")
        XCTAssertTrue(bombmon.contains("FLAVOUR"),
                      "monimon reads as a citation; Bombmon has no evolution to cite")
    }

    // MARK: - The whole file still validates

    func testTheGraphValidatesWithNoFindings() {
        let errors = EvolutionGraph.bundled.validate()
        XCTAssertEqual(errors.map(\.description), [])
    }

    // MARK: - Helpers

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 and US-145 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }

    private func connected() -> Set<String> {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        return sources.union(targets)
    }
}
