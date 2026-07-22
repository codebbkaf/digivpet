import XCTest

@testable import DigiVPet

/// US-144 — the first of Phase E's 26 orphan sweeps: every playable Digitama whose `displayName`
/// starts A–K, over what the eleven device trees left behind.
///
/// The sweeps differ from the device-tree stories in kind. A tree story copies a document; a sweep
/// has no document, so what stands in for one is a rule, applied the same way every time:
///
///  1. An egg whose species is ALREADY a node hangs off that species' line and hatches onto that
///     line's Baby I. Twelve of the twenty-two go this way, and they add no rung at all.
///  2. An egg whose species is NOT in the graph opens a thread: it hatches into that species' own
///     Baby I, taken from Wikimon's Evolves From/Evolves To lists two rungs down, and that Baby I
///     is authored here as a LEAF for US-146/US-147 to carry on from.
///
/// A Digitama is the one stage where "every Digimon in the range gets an in-edge" cannot be met:
/// nothing evolves INTO an egg, and the ladder starts here. What the sweep can do, and what the
/// orphan count in Appendix B actually measures, is give every one of them an out-edge.
final class DigitamaSweepTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The story's scope, derived rather than listed: every playable Digitama the roster holds
    /// whose display name starts A–K. Derived so that a Digitama sprite added to the folder later
    /// lands IN scope and fails here, rather than being quietly out of it.
    private var digitamaInRange: [RosterEntry] {
        roster.entries
            .filter { $0.stage == .digitama && !$0.dexOnly }
            .filter { ("A"..."K").contains(String($0.displayName.prefix(1))) }
    }

    /// Every egg this sweep authored, and the Baby I it hatches into. Written out rather than read
    /// off the file, so a repointed edge has to be a deliberate edit here too.
    private let authoredHatches: [(egg: String, babyI: String)] = [
        // Eggs that join a device line their species already belongs to.
        ("agu2006_digitama", "botamon"),
        ("gabublack_digitama", "punimon"),
        ("elec_digitama", "punimon"),
        ("kune_digitama", "puttimon"),
        ("hyoko_digitama", "piyo_yuramon"),
        ("angora_digitama", "pencnsp_botamon"),
        ("cand_digitama", "mokumon"),
        ("beta_digitama", "pitchmon"),
        ("kame_digitama", "pitchmon"),
        ("kuda_digitama", "yukimibotamon"),
        ("kuda2006_digitama", "yukimibotamon"),
        ("espi_digitama", "choromon"),
        // Eggs that open a thread, with the Baby I authored beside them.
        ("guil_digitama", "jyarimon"),
        ("blackguil_digitama", "jyarimon"),
        ("imp_digitama", "kiimon"),
        ("bluco_digitama", "cocomon"),
        ("gao_digitama", "dodomon"),
        ("bear_digitama", "popomon"),
        ("koe_digitama", "popomon"),
        ("kera_digitama", "kuramon"),
        ("commandra_digitama", "bommon"),
        ("ghost_digitama", "algomon_babyi"),
    ]

    /// The Baby I this sweep opened, every one of them a LEAF until US-146/US-147 wire their Baby
    /// II. See `testTheOnlyDeadEndsBelowUltimateAreTheOnesThisSweepOpened` for why the list is
    /// pinned rather than merely written down.
    private let openedBabyI = ["algomon_babyi", "bommon", "cocomon", "dodomon", "jyarimon",
                               "kiimon", "kuramon", "popomon"]

    private let newLines = ["algomon", "commandramon", "diablomon", "tamers", "wanyamon"]

    // MARK: - AC: every orphan in range is wired

    /// The story's own scope check. Thirty of the roster's fifty-seven Digitama have a display
    /// name in A–K, and eight of those were already wired by a device tree — so twenty-two is what
    /// this story authored and thirty is what has to hold afterwards. Asserting the count as well
    /// as the membership is what catches a Digitama sprite being added without being wired.
    func testEveryPlayableDigitamaFromAToKIsANodeWithAHatchEdge() {
        XCTAssertEqual(digitamaInRange.count, 30)
        XCTAssertEqual(authoredHatches.count, 22)
        for entry in digitamaInRange {
            guard let node = graph.node(id: entry.id) else {
                XCTFail("\(entry.id) (\(entry.displayName)) is still not in evolutions.json")
                continue
            }
            XCTAssertFalse(node.evolutions.isEmpty, "\(entry.id) has no hatch edge — it cannot hatch")
        }
    }

    /// The Appendix B orphan rule, rerun over the stage this story owns: an orphan is a playable
    /// Digimon that is neither the source nor the target of any edge. Every Digitama A–K must now
    /// be a source. Counted rather than spot-checked, because a sweep that leaves one behind is
    /// exactly the failure this story exists to prevent.
    func testNoPlayableDigitamaFromAToKIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = digitamaInRange.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "still orphaned: \(orphans)")
    }

    /// This began as US-144's marker for the half it did not do: 23 Digitama were left over, all of
    /// them L–Z, and the test said so in order to fail the day US-145 landed. US-145 has landed, so
    /// the marker is rewritten into the claim it was guarding — there is now no orphaned Digitama
    /// at all, and "45 before US-144, 23 between the two sweeps, 0 after" is auditable from the
    /// suite rather than only from a script.
    func testNoPlayableDigitamaIsOrphanedAnyMore() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let stillOrphaned = roster.entries
            .filter { $0.stage == .digitama && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.displayName)
        XCTAssertEqual(stillOrphaned, [], "still orphaned: \(stillOrphaned)")
        XCTAssertEqual(roster.entries.filter { $0.stage == .digitama && !$0.dexOnly }.count, 57,
                       "all 57 playable Digitama are wired; a 58th sprite would land here")
    }

    // MARK: - AC: the hatches themselves

    /// Every authored hatch, through the real engine rather than by reading the edge back.
    /// `EggHatcher` is what the main screen calls, so this is the assertion that the egg a map
    /// grants can actually become something.
    func testEachAuthoredEggHatchesIntoTheBabyIItNames() throws {
        for (eggId, babyId) in authoredHatches {
            let egg = try XCTUnwrap(graph.node(id: eggId), "no node \(eggId)")
            XCTAssertEqual(egg.stage, .digitama)
            XCTAssertEqual(EggHatcher.hatchTarget(for: egg, stageEnergy: EnergyTotals(strength: 50)),
                           babyId, "\(eggId) hatches into the wrong Digimon")
            XCTAssertEqual(graph.node(id: babyId)?.stage, .babyI, "\(babyId) is not a Baby I")
        }
    }

    /// `EggHatcher.hatchTarget` reads `node.evolutions.first` and nothing else, so a SECOND hatch
    /// edge on an egg would be authored data the engine silently ignores. Pinned across every
    /// Digitama in the file, not only this story's, because the trap is for whoever wires the
    /// remaining Baby I and needs an in-edge from somewhere.
    func testNoDigitamaHasMoreThanOneHatchEdge() {
        for node in graph.nodes where node.stage == .digitama {
            XCTAssertEqual(node.evolutions.count, 1,
                           "\(node.id) has \(node.evolutions.count) hatch edges; EggHatcher reads only the first")
        }
    }

    /// A hatch edge carries no `conditions`, and that is a decision rather than an omission — the
    /// sweep's generic "no edge is unconditional" criterion cannot be met at this stage without
    /// breaking the game. `EggHatcher` ignores `conditions` entirely, so authoring one would be
    /// data that lies; and since every egg has exactly one way out (above), a condition that an
    /// engine DID honour could leave a player's only egg unable to hatch at all. The gate that
    /// exists is `minEnergy`, and US-018 hatches on total energy, which is why `requiredEnergy` is
    /// nil here too.
    func testHatchEdgesAreUnconditionalAndUngatedByType() {
        for node in graph.nodes where node.stage == .digitama {
            for edge in node.evolutions {
                XCTAssertTrue(edge.conditions.isEmpty, "\(node.id) gates its hatch on a condition")
                XCTAssertNil(edge.requiredEnergy, "\(node.id) type-gates its hatch")
                XCTAssertEqual(edge.minEnergy, 50)
                XCTAssertTrue(edge.isDefault)
            }
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line, which is what makes a `line` a readable Dex tree rather
    /// than a tag. It held for all 300 nodes before this story and has to keep holding: an egg that
    /// joins a device line must join the line of the Baby I it hatches into, not of its species'
    /// eventual home.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// The sweep opened five lines, not twenty-two: the criterion is that a sweep must not produce
    /// dozens of one-node lines. Asserting the SIZES is what makes that meaningful — a line of one
    /// would satisfy "there are only five new lines" and still be the thing the rule forbids.
    func testTheSweepOpenedFiveLinesAndNoneOfThemIsASingleNode() {
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(newLines.compactMap { sizes[$0] }.count, newLines.count,
                       "a line this story opened is missing from the graph")
        for line in newLines {
            XCTAssertGreaterThan(sizes[line] ?? 0, 1, "line \(line) is a single node")
        }
        // Both grew in US-145 — `tamers` took four more Tamers partners with a Baby I apiece and
        // `wanyamon` took Liollmon's egg — again in US-146, which put a Baby II above every Baby I
        // on both, again in US-147, which put a Child above every Baby II, and again in US-148,
    // which put a Champion above every Child whose name begins A-F. The numbers are the
        // file's, not this story's, and are pinned here rather than in the newer sweep because
        // this is where the lines were opened.
        // US-149 put a Champion above every Child G-L and US-150 above every Child M-Z, which
        // is where the last twelve `tamers` nodes came from.
        // US-151 opened the Perfect rung on both, three nodes each: the Champion it swept, the
        // Perfect above it and the junk floor under that.
        XCTAssertEqual(sizes["tamers"], 117, "plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["wanyamon"], 29, "plus US-159's two" + ", plus US-160's one, plus US-161's RizeGreymon and Ravmon")
    }

    /// Twelve of the twenty-two eggs added no rung at all, because their species is already wired.
    /// Spot-checked on the four where the claim is strongest — the species is literally a Child of
    /// the line the egg now roots — since those are the ones a later story might "tidy" into a line
    /// of their own and lose the point.
    func testAnEggWhoseSpeciesIsAlreadyWiredJoinsThatSpeciesLine() throws {
        for (eggId, childId) in [("elec_digitama", "elecmon"), ("kune_digitama", "kunemon"),
                                 ("hyoko_digitama", "hyokomon"), ("angora_digitama", "angoramon"),
                                 ("cand_digitama", "candmon")] {
            let egg = try XCTUnwrap(graph.node(id: eggId))
            let child = try XCTUnwrap(graph.node(id: childId))
            XCTAssertEqual(egg.line, child.line,
                           "\(eggId) does not root the line that reaches \(childId)")
        }
    }

    /// Every new line resolves to a Dex heading and to a training game. Both are keyed on strings
    /// the JSON owns, and a line missing from either degrades silently — the Dex heads the section
    /// with the raw slug, and the game falls through to the stage floor, which would change a
    /// Digimon's minigame as it evolved.
    func testEveryNewLineHasAHeadingAndAGame() {
        for line in newLines {
            let title = DexModel.lineTitles[line]
            XCTAssertNotNil(title, "line \(line) has no Dex heading")
            XCTAssertNotEqual(title, line, "line \(line) heads its section with its own key")
            XCTAssertNotNil(MinigameAssignment.byLine[line], "line \(line) has no training game")
        }
    }

    // MARK: - The dead-end ledger

    /// **The handover to US-146/US-147.** Before this story the file had ZERO nodes below Ultimate
    /// with no way onward; a sweep that authors a rung at a time cannot keep that, because the Baby
    /// I an egg hatches into has to exist before the Baby II above it does.
    ///
    /// So the invariant becomes a ledger instead of a zero, and the WHOLE-FILE ledger lives in
    /// whichever sweep last changed it — now `DigitamaSweepBabyITests`, since US-146 emptied the
    /// Baby I rung of dead ends and refilled it at Baby II. What is left here is this story's own
    /// half of it, flipped: all eight of US-144's Baby I now lead somewhere, and none may quietly
    /// become a leaf again.
    func testTheBabyIThisSweepOpenedAreNoLongerDeadEnds() {
        for id in openedBabyI {
            XCTAssertEqual(graph.node(id: id)?.evolutions.isEmpty, false,
                           "\(id) leads nowhere — US-146 gave every Baby I a Baby II")
        }
    }

    /// Each opened Baby I is really reachable — it is not enough that it exists, something has to
    /// hatch into it, or the story has swapped one orphan for another.
    func testEveryBabyIThisSweepOpenedHasAnEggAboveIt() {
        for babyId in openedBabyI {
            let parents = graph.parents(of: babyId)
            XCTAssertFalse(parents.isEmpty, "\(babyId) has no in-edge — it is an orphan again")
            for parent in parents {
                XCTAssertEqual(parent.stage, .digitama, "\(babyId) is fed by a non-Digitama")
            }
        }
    }

    // MARK: - The data the story rests on

    /// Every node this story added names art that exists, at the stage the ROSTER files it under.
    /// The validator checks the first half; this checks the second, which is the one that bites —
    /// `import_roster.py` reads a Digimon's rung off its sprite FOLDER, so a node authored at the
    /// wrong stage resolves to no art at all.
    func testEveryNodeThisSweepAddedAgreesWithTheRoster() throws {
        let added = authoredHatches.map(\.egg) + openedBabyI
        for id in added {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.stage, entry.stage, "\(id) is authored at the wrong rung")
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the 157 idle-only Digimon")
        }
    }

    /// The sweep had no document to copy, so every thread it opened cites Wikimon in the node's
    /// `comment` — and a `comment` that cites nothing is the shape of an invented evolution. Only
    /// the thread-opening eggs are checked: the twelve that join an existing line rest on that
    /// line's own sourcing, not on a new claim.
    func testEveryThreadThisSweepOpenedCitesItsSource() throws {
        for eggId in ["guil_digitama", "imp_digitama", "bluco_digitama", "gao_digitama",
                      "bear_digitama", "koe_digitama", "kera_digitama", "commandra_digitama",
                      "ghost_digitama"] {
            XCTAssertTrue(try authoredComment(on: eggId).contains("Wikimon"),
                          "\(eggId) opens a thread without naming where the arrow comes from")
        }
    }

    /// `comment` is authored in `evolutions.json` and deliberately NOT decoded into
    /// `EvolutionNode` — it is documentation for whoever reads the file, and a property nothing
    /// renders would invite someone to render it. So the tests that hold the sourcing honest read
    /// the raw JSON, the same way every device-tree story's does.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }

    /// `blackguil_digitama` is the exception the test above must not swallow: Wikimon records no
    /// Evolves From for BlackGuilmon at all, so its placement is the sweep's variant rule and the
    /// comment says so instead of citing a page that does not support it.
    func testTheVariantEggSaysItIsPlacedByRuleRatherThanByCitation() throws {
        XCTAssertTrue(try authoredComment(on: "blackguil_digitama").contains("variant rule"))
        XCTAssertEqual(graph.node(id: "blackguil_digitama")?.line,
                       graph.node(id: "guil_digitama")?.line,
                       "the variant does not hang off its base form's line")
    }
}
