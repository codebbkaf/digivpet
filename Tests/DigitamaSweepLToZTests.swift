import XCTest

@testable import DigiVPet

/// US-145 — the second of Phase E's 26 orphan sweeps, and the other half of the Digitama: every
/// playable egg whose `displayName` starts L–Z that the eleven device trees and US-144 left behind.
///
/// US-144 set the sweep's rule and this story tightens it, because the arithmetic forced it. There
/// were 23 eggs left and 25 orphaned Baby I, and `EggHatcher.hatchTarget` reads
/// `node.evolutions.first`, so an egg has exactly ONE hatch edge and a Baby I's only possible
/// in-edge is an egg of its own. Between US-144 and US-145 the Digitama run out for good, so every
/// egg spent on an already-reachable Baby I is a Baby I nobody can ever hatch. The rule here is
/// therefore:
///
///  1. An egg hatches into the Baby I that Wikimon puts two rungs below its species, and that Baby
///     I is authored HERE if it is not in the graph yet. Twelve of the twenty-three go this way.
///  2. An egg doubles up on a Baby I that already exists only when it has no choice — when its
///     species is already wired at that rung, or when the species (or its own Baby I) is one of the
///     157 idle-only Digimon and no thread can be built to it at all. Eleven go this way, and each
///     one is a case the sweep could not have done differently, not a preference.
///
/// The ceiling this hits is worth writing down: twelve is the MOST any authoring of these 23 eggs
/// could have opened. Thirteen of the 25 orphaned Baby I sit on a thread that reaches one of these
/// 23 species at all, and two of those thirteen — Leafmon and Pururumon — are reachable only
/// through `worm_digitama`, which can hatch into one of them. So 25 - 12 = 13 Baby I are beyond
/// this phase's reach through Digitama, and US-146 inherits that rather than a shortfall it can
/// author away.
final class DigitamaSweepLToZTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The story's scope, derived rather than listed, for the same reason US-144 derived its own:
    /// a Digitama sprite added to the folder later lands IN scope and fails here.
    private var digitamaInRange: [RosterEntry] {
        roster.entries
            .filter { $0.stage == .digitama && !$0.dexOnly }
            .filter { ("L"..."Z").contains(String($0.displayName.prefix(1))) }
    }

    /// The twelve eggs that open a Baby I, each written as the egg, the Baby I it opens, and the
    /// Baby II Wikimon puts between that Baby I and the egg's species — because the middle rung is
    /// the whole justification for the pairing and US-147 is the story that will author it.
    private let opening: [(egg: String, babyI: String, viaBabyII: String)] = [
        ("lala_digitama", "pipimon", "Tanemon"),
        ("lop_digitama", "relemon", "Moonmon"),
        ("luce_digitama", "tsubumon", "Tokomon"),
        ("ludo_digitama", "cotsucomon", "Kakkinmon"),
        ("monodra_digitama", "ketomon", "Hopmon"),
        ("morpho_digitama", "bubbmon", "Mochimon"),
        ("pulse_digitama", "dokimon", "Bibimon"),
        ("rena_digitama", "tomorimon", "Onibimon"),
        ("sunariza_digitama", "sunamon", "Goromon"),
        ("terrier_digitama", "zerimon", "Gummymon"),
        ("v_digitama", "chicomon", "Chibimon"),
        ("worm_digitama", "leafmon", "Minomon"),
    ]

    /// Why an egg was allowed to double up. Five reasons, and nothing else counts — each one is a
    /// fact about the roster or the graph, checked below, rather than a preference.
    private enum Reason {
        /// The egg's species is already a node, so the rung its thread would open exists.
        case speciesAlreadyWired
        /// The species is one of the 157 idle-only Digimon, so no edge may ever name it.
        case speciesIsIdleOnly
        /// The species has no sheet in `16x16 Digimon Sprites` at all.
        case speciesHasNoSheet
        /// The species is playable and unwired, but its OWN Baby I is idle-only, so the bottom of
        /// that thread cannot be authored however much the allocation would like it to be.
        case ownBabyIIsIdleOnly
        /// The species is playable and unwired, and every Baby I Wikimon puts under it is already
        /// in the graph — so there is no orphan for this egg to open, only one to join.
        case everyCandidateBabyIAlreadyWired
    }

    /// The eleven that double up, each with the reason it had no choice. `species` is the roster id
    /// of the Digimon the egg is named for, or nil when that Digimon has no sheet at all.
    private let doubling: [(egg: String, babyI: String, species: String?, why: Reason)] = [
        ("mush_digitama", "nyokimon", "mushmon", .speciesAlreadyWired),
        ("picodevi_digitama", "mokumon", "picodevimon", .speciesAlreadyWired),
        ("plot_digitama", "yukimibotamon", "plotmon", .speciesAlreadyWired),
        ("swim_digitama", "botamon", "swimmon", .speciesAlreadyWired),
        ("pawnchessblack_digitama", "botamon", "pawnchessmon_black", .speciesIsIdleOnly),
        ("pawnchesswhite_digitama", "botamon", "pawnchessmon_white", .speciesIsIdleOnly),
        ("zuba_digitama", "cotsucomon", "zubamon", .speciesIsIdleOnly),
        ("lioll_digitama", "popomon", nil, .speciesHasNoSheet),
        ("meicoo_digitama", "kuramon", "meicoomon", .ownBabyIIsIdleOnly),
        // Phascomon's only Baby I is Choromon (via Caprimon) and Vorvomon's is Mokumon (via Peti
        // Meramon); both are already this file's, on the very line the species belongs to.
        ("phasco_digitama", "choromon", "phascomon", .everyCandidateBabyIAlreadyWired),
        ("vorvo_digitama", "mokumon", "vorvomon", .everyCandidateBabyIAlreadyWired),
    ]

    private var authoredHatches: [(egg: String, babyI: String)] {
        opening.map { ($0.egg, $0.babyI) } + doubling.map { (egg: $0.egg, babyI: $0.babyI) }
    }

    /// The twelve Baby I this sweep opened, every one of them a leaf until US-147 wires its Baby II.
    private let openedBabyI = ["bubbmon", "chicomon", "cotsucomon", "dokimon", "ketomon", "leafmon",
                               "pipimon", "relemon", "sunamon", "tomorimon", "tsubumon", "zerimon"]

    private let newLines = ["adventure02", "vital"]

    // MARK: - AC: every orphan in range is wired

    /// The story's scope check. Twenty-seven of the roster's fifty-seven Digitama have a display
    /// name in L–Z; four of those (Pal, Pata, Piyo, Tento) were already wired by a device tree, so
    /// twenty-three is what this story authored.
    func testEveryPlayableDigitamaFromLToZIsANodeWithAHatchEdge() {
        XCTAssertEqual(digitamaInRange.count, 27)
        XCTAssertEqual(authoredHatches.count, 23)
        for entry in digitamaInRange {
            guard let node = graph.node(id: entry.id) else {
                XCTFail("\(entry.id) (\(entry.displayName)) is still not in evolutions.json")
                continue
            }
            XCTAssertFalse(node.evolutions.isEmpty, "\(entry.id) has no hatch edge — it cannot hatch")
        }
    }

    /// The Appendix B orphan rule rerun over the two stages this story touches. A Digitama is an
    /// orphan until it is the SOURCE of an edge; a Baby I until it is the TARGET of one. Both are
    /// counted, because the story's whole value is the pair — 23 eggs and 12 Baby I, 35 orphans.
    func testTheSweepRemovedThirtyFiveOrphans() {
        let connected = self.connected()

        let eggs = digitamaInRange.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(eggs, [], "Digitama still orphaned: \(eggs)")

        let babies = openedBabyI.filter { !connected.contains($0) }
        XCTAssertEqual(babies, [], "Baby I still orphaned: \(babies)")

        XCTAssertEqual(authoredHatches.count + openedBabyI.count, 35)
    }

    /// The handover number, asserted rather than left in `notes`: thirteen Baby I are beyond every
    /// Digitama's reach, because every playable Digitama in the file already has its single hatch
    /// edge spent. US-146 took the second of the two options this test offered it — it authored the
    /// thirteen for their OUT-edges and recorded them as unreachable — so they are no longer
    /// ORPHANS by the Appendix B rule, and the claim here narrows to the half that survives: they
    /// have no in-edge, and no egg is left that could give them one.
    ///
    /// `DigitamaSweepBabyITests` names the same thirteen from the other side.
    func testTheBabyIStillOrphanedCannotBeReachedByAnyRemainingEgg() {
        let parentless = roster.entries
            .filter { $0.stage == .babyI && !$0.dexOnly }
            .filter { graph.parents(of: $0.id).isEmpty }
            .map(\.id)
            .sorted()
        XCTAssertEqual(parentless.count, 13, "Baby I with no in-edge: \(parentless)")

        let spareEggs = roster.entries
            .filter { $0.stage == .digitama && !$0.dexOnly }
            .filter { (graph.node(id: $0.id)?.evolutions.count ?? 0) == 0 }
        XCTAssertEqual(spareEggs.map(\.id), [], "an unspent egg exists; it should have opened a Baby I")
    }

    private func connected() -> Set<String> {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        return sources.union(targets)
    }

    // MARK: - AC: the hatches themselves

    /// Every authored hatch, through the real engine rather than by reading the edge back.
    func testEachAuthoredEggHatchesIntoTheBabyIItNames() throws {
        for (eggId, babyId) in authoredHatches {
            let egg = try XCTUnwrap(graph.node(id: eggId), "no node \(eggId)")
            XCTAssertEqual(egg.stage, .digitama)
            XCTAssertEqual(EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 50)),
                           babyId, "\(eggId) hatches into the wrong Digimon")
            XCTAssertEqual(graph.node(id: babyId)?.stage, .babyI, "\(babyId) is not a Baby I")
        }
    }

    /// The Baby I this story opened are exactly the ones no earlier story had, and each has an egg
    /// above it and nothing but eggs above it. The second half matters: a Baby I fed by a Baby I
    /// would be a rung skipped, and the validator's stage check would not see it as one.
    func testEveryBabyIThisSweepOpenedIsNewAndHasOnlyEggsAboveIt() {
        for babyId in openedBabyI {
            let parents = graph.parents(of: babyId)
            XCTAssertFalse(parents.isEmpty, "\(babyId) has no in-edge — it is an orphan again")
            for parent in parents {
                XCTAssertEqual(parent.stage, .digitama, "\(babyId) is fed by a non-Digitama")
            }
        }
        XCTAssertEqual(Set(opening.map(\.babyI)).count, 12,
                       "two eggs opened the same Baby I; one of them wasted an in-edge")
    }

    // MARK: - The whole-file dead-end ledger

    /// The whole-file ledger moved on to `DigitamaSweepBabyITests`, which is the newest sweep and
    /// the one US-147 should edit; what is left here is this story's own half of it, narrowed to
    /// the claim that survives. US-146 wired every one of the twelve Baby I this story opened, so
    /// NONE of them is a dead end any more — and none may quietly become one again.
    func testTheTwelveBabyIThisSweepOpenedAreNoLongerDeadEnds() {
        for babyId in openedBabyI {
            let node = graph.node(id: babyId)
            XCTAssertNotNil(node, "no node \(babyId)")
            XCTAssertFalse(node?.evolutions.isEmpty ?? true,
                           "\(babyId) is a dead end again — US-146 gave it a Baby II")
        }
    }

    /// Two of the twelve are cheaper to close than the other ten, and saying which buys US-147 the
    /// search: their Baby II is ALREADY a node on the same line, so closing the dead end is one
    /// edge and no new node at all.
    func testTwoOfTheOpenedBabyIAlreadyHaveTheirBabyIIOnTheSameLine() throws {
        for (babyI, babyII) in [("pipimon", "tanemon"), ("tsubumon", "tokomon")] {
            let baby = try XCTUnwrap(graph.node(id: babyI))
            let target = try XCTUnwrap(graph.node(id: babyII), "\(babyII) is not in the graph")
            XCTAssertEqual(target.stage, .babyII)
            XCTAssertEqual(baby.line, target.line,
                           "\(babyI) is not on \(babyII)'s line, so US-147 cannot close it with an edge")
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line. It held for all 330 nodes before this story and has to
    /// keep holding: an egg that joins an existing line must join the line of the Baby I it hatches
    /// into, not of its species' eventual home.
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
    /// is two new lines for twelve new threads — the other ten went onto lines that already exist.
    ///
    /// The SIZES of the two lines belong to whichever story last grew them, not to this one:
    /// US-146 put four more nodes on each, so what is pinned here is the thirteen nodes US-145
    /// itself put on them, and that the ten it did not are still on lines it did not open.
    func testTheSweepOpenedTwoLinesAndPutTheRestOntoExistingOnes() {
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(Set(sizes.keys).intersection(newLines).count, newLines.count,
                       "a line this story opened is missing from the graph")

        let mine = Set(["v_digitama", "chicomon", "worm_digitama", "leafmon",
                        "pulse_digitama", "dokimon", "morpho_digitama", "bubbmon",
                        "sunariza_digitama", "sunamon", "ludo_digitama",
                        "zuba_digitama", "cotsucomon"])
        for id in mine {
            XCTAssertTrue(newLines.contains(graph.node(id: id)?.line ?? ""),
                          "\(id) left the line this story opened for it")
        }

        // Every other node this story authored landed on a line that already existed.
        let authored = Set(authoredHatches.map(\.egg) + openedBabyI)
        XCTAssertEqual(authored.subtracting(mine).count, 22)
        for id in authored.subtracting(mine) {
            XCTAssertFalse(newLines.contains(graph.node(id: id)?.line ?? ""),
                           "\(id) is on a line this story opened after all")
        }
    }

    /// The four Tamers partners this sweep added join Guilmon's and Impmon's line rather than
    /// opening four more, which is the single biggest reason the story needed only two new lines.
    /// Asserted through the SPECIES rather than the egg id, so a later story that moves Terriermon
    /// onto its own line has to move the egg too.
    func testTheTamersPartnersLandedOnTheTamersLine() throws {
        for eggId in ["lop_digitama", "monodra_digitama", "rena_digitama", "terrier_digitama"] {
            XCTAssertEqual(graph.node(id: eggId)?.line, "tamers", "\(eggId) left the Tamers line")
        }
        let tamers = graph.nodes.filter { $0.line == "tamers" }
        XCTAssertEqual(tamers.filter { $0.stage == .digitama }.count, 8)
        // Eight Baby I, not the seven this story left: US-146 hung Pafumon here, one of the
        // thirteen Baby I no egg can reach, because Yaamon is the Baby II its stand-in points at.
        XCTAssertEqual(tamers.filter { $0.stage == .babyI }.count, 8)
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
    /// The validator checks the first half; this checks the second, which is the one that bites —
    /// `import_roster.py` reads a Digimon's rung off its sprite FOLDER, so a node authored at the
    /// wrong stage resolves to no art at all.
    func testEveryNodeThisSweepAddedAgreesWithTheRoster() throws {
        for id in authoredHatches.map(\.egg) + openedBabyI {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.stage, entry.stage, "\(id) is authored at the wrong rung")
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the 157 idle-only Digimon")
        }
    }

    /// The sweep had no document to copy, so every thread it opened cites Wikimon in the node's
    /// `comment`, and names the Baby II the pairing rests on. A `comment` that cites nothing is the
    /// shape of an invented evolution, and a citation that skips the middle rung is unfalsifiable.
    func testEveryThreadThisSweepOpenedCitesItsSourceAndItsMiddleRung() throws {
        for (eggId, _, babyII) in opening {
            let comment = try authoredComment(on: eggId)
            XCTAssertTrue(comment.contains("Wikimon"),
                          "\(eggId) opens a thread without naming where the arrow comes from")
            XCTAssertTrue(comment.contains(babyII),
                          "\(eggId)'s comment does not name \(babyII), the rung the pairing rests on")
        }
    }

    /// The eleven that doubled up are the story's weak spot — an egg placed on an existing Baby I
    /// is the one thing a later reader cannot tell from a shortcut — so each states its reason. The
    /// three reasons are the three the sweep allows, and nothing else counts.
    func testEveryDoubledUpEggSaysWhyItHadNoChoice() throws {
        XCTAssertEqual(doubling.count, 11)
        for (eggId, babyI, species, why) in doubling {
            XCTAssertTrue(try authoredComment(on: eggId).contains("Wikimon"),
                          "\(eggId) is placed without a citation")
            // "Doubling up" means the Baby I was not opened FOR this egg: either an earlier story
            // authored it, or one of this sweep's twelve thread-opening eggs claimed it first.
            // `zuba_digitama` is the second case — Zubamon is idle-only and rides Ludomon's
            // Cotsucomon — and it is why this cannot be a flat "the Baby I is not new" check.
            XCTAssertGreaterThan(graph.parents(of: babyI).count, 1,
                                 "\(eggId) has \(babyI) to itself, so it did not double up at all")
            if openedBabyI.contains(babyI) {
                XCTAssertTrue(opening.contains { $0.babyI == babyI },
                              "\(eggId) doubles onto \(babyI), which no thread-opening egg claims")
            }
            switch why {
            case .speciesAlreadyWired:
                XCTAssertNotNil(graph.node(id: try XCTUnwrap(species)),
                                "\(eggId)'s species is NOT wired — it should have opened a thread")
            case .speciesIsIdleOnly:
                XCTAssertEqual(roster.entry(id: try XCTUnwrap(species))?.dexOnly, true,
                               "\(eggId)'s species is playable now — it should open a thread")
            case .speciesHasNoSheet:
                XCTAssertNil(species)
                XCTAssertNil(roster.entry(id: "liollmon"),
                             "Liollmon now has a sheet; lioll_digitama should open a thread")
            case .ownBabyIIsIdleOnly:
                let id = try XCTUnwrap(species)
                XCTAssertNotNil(roster.entry(id: id))
                XCTAssertNil(graph.node(id: id), "\(id) is wired now; revisit \(eggId)")
                XCTAssertEqual(roster.entry(id: "meicoo_baby")?.dexOnly, true,
                               "Meicoo's Baby I is playable now; \(eggId) should open that thread")
            case .everyCandidateBabyIAlreadyWired:
                let id = try XCTUnwrap(species)
                XCTAssertNotNil(roster.entry(id: id))
                XCTAssertNil(graph.node(id: id), "\(id) is wired now; revisit \(eggId)")
                // The Baby I it settled for is one an earlier story authored, which is the whole
                // claim: there was an existing rung to join and no orphan to open.
                XCTAssertNotNil(graph.node(id: babyI))
            }
        }
    }

    /// `comment` is authored in `evolutions.json` and deliberately NOT decoded into
    /// `EvolutionNode`, so the tests that hold the sourcing honest read the raw JSON, the same way
    /// every device-tree story's does.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }

    // MARK: - AC: the validator is clean

    /// AC7, run over the WHOLE file rather than this story's slice — a sweep can only break the
    /// data it touches, but the cheapest place to find out is here.
    func testTheShippedGraphValidatesClean() throws {
        let findings = try EvolutionGraph.load().validate()
        XCTAssertEqual(findings.map(\.description), [])
    }
}
