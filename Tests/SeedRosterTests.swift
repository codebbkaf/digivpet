import Foundation
import XCTest

@testable import DigiVPet

/// Tests the SHIPPED roster data in `Resources/evolutions.json` — not the model that decodes it
/// (`EvolutionGraphTests` owns that, against a fixture). Everything here reads the real file, so
/// a broken seed fails the build rather than the app.
///
/// US-009 owns validating the graph in general (unknown ids, stage skips, missing art, ...).
/// These are the US-008 acceptance criteria specifically: the three lines exist, are complete,
/// are animated, and branch.
final class SeedRosterTests: XCTestCase {
    private var graph: EvolutionGraph!

    /// The seed lines, each as its full Digitama -> Ultimate default path.
    ///
    /// Written out as literals rather than derived from the file: a test that walks whatever the
    /// data says and asserts it matches the data would pass on any roster at all.
    ///
    /// The Patamon line (US-044) is the odd one: its fallback runs through Scumon, the V3 tree's
    /// junk evolution, because Patamon has five Champions and only four energy types to gate them
    /// with. That is the path a neglected Patamon walks, and it still covers all seven rungs.
    private let seedLines: [[String]] = [
        ["agu_digitama", "botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"],
        ["gabu_digitama", "punimon", "tsunomon", "gabumon", "garurumon", "weregarurumon", "metalgarurumon"],
        ["pal_digitama", "yuramon", "tanemon", "palmon", "togemon", "lilimon", "rosemon"],
        ["pata_digitama", "puttimon", "tokomon", "patamon", "scumon", "etemon", "bancholeomon"],
    ]

    /// The seven rungs a complete line must cover, in order.
    private let ladder: [Stage] = [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate]

    override func setUpWithError() throws {
        try super.setUpWithError()
        graph = try EvolutionGraph.load()
    }

    override func tearDown() {
        graph = nil
        super.tearDown()
    }

    /// Follows `isDefault` edges from a node, which is the path US-020 takes when nothing else
    /// qualifies — i.e. the line a player is guaranteed to walk.
    private func defaultPath(from id: String) throws -> [EvolutionNode] {
        var path: [EvolutionNode] = []
        var next: String? = id

        while let current = next {
            // Also catches a cycle: a line longer than the ladder can only be looping.
            guard path.count <= ladder.count else {
                XCTFail("default path from \(id) does not terminate: \(path.map(\.id))")
                return path
            }
            let node = try XCTUnwrap(graph.node(id: current), "no node with id \(current)")
            path.append(node)
            next = node.evolutions.first(where: \.isDefault)?.to
        }
        return path
    }

    // MARK: - AC: 3 complete lines, each Digitama -> Baby I -> Baby II -> Child -> Adult -> Perfect -> Ultimate

    func testEachSeedLineIsCompleteFromDigitamaToUltimate() throws {
        for line in seedLines {
            let path = try defaultPath(from: line[0])

            XCTAssertEqual(path.map(\.id), line, "line from \(line[0]) does not follow its default edges")
            XCTAssertEqual(path.map(\.stage), ladder, "line from \(line[0]) does not cover all 7 stages in order")
        }
    }

    /// The AC names these three lines by their Child-and-up forms; assert them literally.
    func testTheThreeNamedLinesAreTheOnesShipped() throws {
        XCTAssertEqual(try defaultPath(from: "agumon").map(\.displayName),
                       ["Agumon", "Greymon", "MetalGreymon", "WarGreymon"])
        XCTAssertEqual(try defaultPath(from: "gabumon").map(\.displayName),
                       ["Gabumon", "Garurumon", "WereGarurumon", "MetalGarurumon"])
        XCTAssertEqual(try defaultPath(from: "palmon").map(\.displayName),
                       ["Palmon", "Togemon", "Lilimon", "Rosemon"])

        // The AC calls out Palmon's Baby forms by name.
        XCTAssertEqual(graph.node(id: "yuramon")?.stage, .babyI)
        XCTAssertEqual(graph.node(id: "tanemon")?.stage, .babyII)
    }

    // MARK: - AC: every node uses a real 48x64 animated stage sheet, never an "Idle Frame Only" sprite

    /// Slices every seed node's art the way the app does. This is stronger than "the file exists":
    /// `SpriteSheet` rejects anything that is not 48x64 (or 48x16 for an egg), so an idle-only
    /// 16x16 sprite — or a Digimon with no animated sheet at all — fails here rather than shipping
    /// as a Digimon that cannot animate.
    func testEverySeedNodeHasAnAnimatedSheetWithTheRightFrameCount() throws {
        for node in graph.nodes {
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(node.id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")

            if node.stage == .digitama {
                XCTAssertEqual(sheet.kind, .egg, "\(node.id) is a Digitama but its sheet is not 48x16")
                XCTAssertEqual(sheet.frames.count, 3, "\(node.id) should have idle, wobble, hatch")
            } else {
                XCTAssertEqual(sheet.kind, .stage, "\(node.id) is not backed by a 48x64 animated sheet")
                XCTAssertEqual(sheet.frames.count, 12, "\(node.id) should have all 12 frames")
                // The idle loop is what the main screen drives; prove it resolves.
                XCTAssertNotNil(sheet[SpriteFrame.walk1], "\(node.id) cannot animate its idle loop")
            }
        }
    }

    /// The 157 idle-only Digimon (Poyomon, Ankylomon, ...) have no animated sheet, so they must
    /// never be playable. No seed node may be one.
    func testNoSeedNodeIsDexOnly() {
        for node in graph.nodes {
            XCTAssertFalse(node.dexOnly, "\(node.id) is dexOnly and must not appear in an evolution line")
        }
    }

    // MARK: - AC: at least one node has 2+ outgoing edges with different requiredEnergy

    func testAtLeastOneNodeBranchesOnDominantEnergy() {
        let branching = graph.nodes.filter { node in
            Set(node.evolutions.compactMap(\.requiredEnergy)).count >= 2
        }
        XCTAssertFalse(branching.isEmpty, "no node branches on dominant energy — nothing exercises US-019")
    }

    /// The branch above, pinned: Agumon is where dominant energy first changes the outcome.
    func testAgumonBranchesOnStrengthOrStamina() throws {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        XCTAssertEqual(agumon.evolutions.count, 2)

        // Deliberately NOT Dictionary(uniqueKeysWithValues:) keyed on requiredEnergy: two edges
        // sharing an energy would TRAP there, killing the test host so the rest of the suite
        // never reports (see EvolutionGraph.bundled). Collapsed branches must fail, not crash.
        XCTAssertEqual(Set(agumon.evolutions.compactMap(\.requiredEnergy)).count, 2,
                       "Agumon's two edges must require DIFFERENT energies or the branch is fake")

        let toGreymon = agumon.evolutions.first { $0.requiredEnergy == .strength }
        let toMeramon = agumon.evolutions.first { $0.requiredEnergy == .stamina }
        XCTAssertEqual(toGreymon?.to, "greymon")
        XCTAssertEqual(toMeramon?.to, "meramon")

        // Only one of the two may be the fallback, and it is the line the AC names.
        XCTAssertEqual(toGreymon?.isDefault, true)
        XCTAssertEqual(toMeramon?.isDefault, false)

        // Meramon converges back into line 1, so the branch is a detour, not a dead end.
        XCTAssertEqual(graph.parents(of: "metalgreymon").map(\.id).sorted(), ["greymon", "meramon"])
    }

    // MARK: - AC: every non-terminal node has exactly one isDefault edge

    func testEveryNonTerminalNodeHasExactlyOneDefaultEdge() {
        for node in graph.nodes where !node.evolutions.isEmpty {
            XCTAssertEqual(
                node.evolutions.filter(\.isDefault).count, 1,
                "\(node.id) must have exactly one isDefault edge or US-020 has no fallback")
        }
    }

    /// A Digitama hatches on TOTAL energy (US-018), so no single type may gate its edge, and its
    /// maxCareMistakes must not be able to block hatching. Every other edge names its energy.
    func testOnlyDigitamaEdgesOmitRequiredEnergy() {
        for node in graph.nodes {
            for edge in node.evolutions {
                if node.stage == .digitama {
                    XCTAssertNil(edge.requiredEnergy, "\(node.id) is an egg; its hatch must not be type-gated")
                    XCTAssertEqual(edge.minEnergy, 50, "\(node.id) must hatch at the US-018 threshold")
                    XCTAssertGreaterThan(edge.maxCareMistakes, 3, "\(node.id) hatch must not be blocked by neglect")
                } else {
                    XCTAssertNotNil(edge.requiredEnergy, "\(node.id) -> \(edge.to) has no requiredEnergy")
                }
            }
        }
    }

    // MARK: - US-044: the V3 Patamon line

    /// Every node the line may reach, checked against the set US-043 verified has animated art.
    /// A node from outside it is either a Digimon with no sheet or one invented out of thin air.
    private let patamonLineVerifiedSet: Set<String> = [
        "Unimon", "Centalmon", "Ogremon", "Bakemon", "Shellmon", "Drimogemon", "Scumon",
        "Andromon", "Giromon", "Etemon", "HiAndromon", "Gokumon", "BanchoLeomon",
    ]

    func testThePatamonLineDrawsItsAdultsAndUpFromTheVerifiedSet() {
        let adult = Stage.adult.ladderIndex!
        let above = graph.nodes.filter { $0.line == "patamon" && ($0.stage.ladderIndex ?? -1) >= adult }

        XCTAssertFalse(above.isEmpty, "the Patamon line has no Adult-or-later nodes at all")
        for node in above {
            XCTAssertTrue(patamonLineVerifiedSet.contains(node.displayName),
                          "\(node.displayName) is not in the US-043 verified-available set")
        }
    }

    /// Poyomon, the V3 tree's Fresh stage, is one of the 157 idle-only Digimon. The line must not
    /// name it anywhere — not as a node, and not as an edge target.
    func testTheLineDoesNotUsePoyomon() {
        XCTAssertNil(graph.node(id: "poyomon"), "Poyomon is dexOnly and may not be a node")
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(edge.to, "poyomon", "\(node.id) points at dexOnly Poyomon")
            }
        }
    }

    /// The substitute Baby I is real, animated, and its divergence from the source tree is written
    /// down in the data file itself — the next reader will diff `evolutions.json` against the tree
    /// markdown and needs to find the reason there, not in a commit message.
    func testThePoyomonSubstitutionIsRecordedInTheDataFile() throws {
        let substitute = try XCTUnwrap(graph.node(id: "puttimon"))
        XCTAssertEqual(substitute.stage, .babyI)
        XCTAssertFalse(substitute.dexOnly)
        XCTAssertEqual(substitute.evolutions.first(where: \.isDefault)?.to, "tokomon")

        // The raw file, not the decoded graph: `comment` is not a schema field, so the decoder
        // drops it and only re-reading the JSON can prove it is actually written down.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == "puttimon" })
        let comment = try XCTUnwrap(authored["comment"] as? String,
                                    "the Baby I substitute carries no comment explaining the divergence")
        XCTAssertTrue(comment.contains("Poyomon"), "the comment must name what it diverges from")
    }

    /// Patamon's five Champions are the V3 tree's five, and every one of them leads to an Ultimate
    /// rather than dead-ending partway up the ladder.
    func testPatamonBranchesFiveWaysAndEveryBranchReachesUltimate() throws {
        let patamon = try XCTUnwrap(graph.node(id: "patamon"))

        XCTAssertEqual(patamon.evolutions.map(\.to).sorted(),
                       ["bakemon", "centalmon", "ogremon", "scumon", "unimon"])

        for edge in patamon.evolutions {
            let path = try defaultPath(from: edge.to)
            XCTAssertEqual(path.map(\.stage), [.adult, .perfect, .ultimate],
                           "the branch through \(edge.to) does not reach Ultimate: \(path.map(\.id))")
        }
    }

    /// The four earned branches each need a distinct dominant type, or two of them are unreachable.
    /// Scumon is deliberately excluded: it shares Bakemon's vitality gate and wins only when
    /// Bakemon's higher `minEnergy` or stricter `maxCareMistakes` shuts Bakemon out.
    func testPatamonsEarnedBranchesUseFourDistinctEnergies() throws {
        let patamon = try XCTUnwrap(graph.node(id: "patamon"))
        let earned = patamon.evolutions.filter { !$0.isDefault }

        XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, 4,
                       "two earned branches share a dominant type, so one can never be chosen")

        let scumon = try XCTUnwrap(patamon.evolutions.first { $0.isDefault })
        let bakemon = try XCTUnwrap(patamon.evolutions.first { $0.to == "bakemon" })
        XCTAssertEqual(scumon.to, "scumon")
        XCTAssertEqual(scumon.requiredEnergy, bakemon.requiredEnergy)
        XCTAssertLessThan(scumon.minEnergy, bakemon.minEnergy,
                          "Scumon must sit below Bakemon or it would win the vitality branch outright")
    }

    /// The junk branch is not just declared — prove the engine actually routes to it, and that a
    /// well-raised vitality Patamon still gets Bakemon instead.
    func testANeglectedVitalityPatamonGetsScumonAndAWellRaisedOneGetsBakemon() throws {
        let patamon = try XCTUnwrap(graph.node(id: "patamon"))
        let plenty = EnergyTotals(strength: 0, vitality: 90, spirit: 0, stamina: 0)

        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: patamon, stageEnergy: plenty, dominant: .vitality,
                                            careMistakes: 0, battleWins: 0),
            "bakemon")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: patamon, stageEnergy: plenty, dominant: .vitality,
                                            careMistakes: 9, battleWins: 0),
            "scumon", "past Bakemon's care-mistake limit, only the junk branch is left")
    }
}
