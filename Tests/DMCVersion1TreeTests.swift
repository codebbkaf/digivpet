import XCTest
@testable import DigiVPet

/// US-133: the Digital Monster Color Version 1 tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 1, "Version 1
/// (Original Brown / Gray)". Every test here reads the REAL `evolutions.json` — a fixture could
/// satisfy all of it while the shipped file still stopped where US-043 left it.
///
/// The seed line US-043 called `agumon` WAS this tree, authored pruned; US-133 renamed it to
/// `dmc-v1` and filled in the rest rather than adding a second, near-identical tree beside it.
/// `EvolutionTreeLayout` draws one tree per line and drops any connector leaving it, so a node of
/// the V1 tree in another line would be a Digimon the tree cannot draw an arrow to.
final class DMCVersion1TreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "dmc-v1"

    private func node(_ id: String) throws -> EvolutionNode {
        try XCTUnwrap(graph.node(id: id), "\(id) is not a node in evolutions.json")
    }

    private func targets(of id: String) throws -> Set<String> {
        Set(try node(id).evolutions.map(\.to))
    }

    // MARK: - AC1/AC2: every playable name in the section is a node, on the right stage, in the line

    /// The tree as the document writes it, stage by stage. `Fresh` is Baby I, `In-Training` is
    /// Baby II, `Rookie` is Child, `Champion` is Adult, the document's `Ultimate` is Perfect and
    /// its `Mega` is this app's `Ultimate-Super Ultimate`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("botamon", .babyI),
        ("koromon", .babyII),
        ("agumon", .child),
        ("greymon", .adult),
        ("devimon", .adult),
        ("meramon", .adult),
        ("numemon", .adult),
        ("airdramon", .adult),
        ("seadramon", .adult),
        ("metalgreymon_virus", .perfect),
        ("mamemon", .perfect),
        ("monzaemon", .perfect),
        ("blitzgreymon", .ultimate),
        ("banchomamemon", .ultimate),
        ("dmcv1_shinmonzaemon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheVersionOneLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Version 1 tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's other half, as a test rather than only as a note: the two names the section carries
    /// that this asset pack cannot draw must appear NOWHERE — not as nodes, not as edge targets.
    ///
    ///  - Betamon: `Idle Frame Only/Betamon.png` only, so it is `dexOnly` in the roster.
    ///  - Tyranomon: no colour sheet at all. The only file matching the name is
    ///    `Black and White Sprites/Adult/Tyranomon.png`, a monochrome folder the roster does not
    ///    index, so there is no roster entry to point at either.
    func testTheTwoUndrawableNamesAppearNowhere() {
        for missing in ["betamon", "tyranomon"] {
            XCTAssertNil(graph.node(id: missing), "\(missing) cannot be drawn and may not be a node")
            for node in graph.nodes {
                for edge in node.evolutions {
                    XCTAssertNotEqual(edge.to, missing, "\(node.id) points at undrawable \(missing)")
                }
            }
        }
        XCTAssertEqual(Roster.bundled.entry(id: "betamon")?.dexOnly, true,
                       "the reason Betamon is out is that it is dexOnly; if that changed, wire it")
        XCTAssertNil(Roster.bundled.entry(id: "tyranomon"),
                     "the reason Tyranomon is out is that it has no colour sheet at all")
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the Rookies.
        XCTAssertTrue(try targets(of: "botamon").contains("koromon"))
        XCTAssertTrue(try targets(of: "koromon").contains("agumon"))
        // Betamon's slot under Koromon, carried by its substitute.
        XCTAssertTrue(try targets(of: "koromon").contains("swimmon"))

        // Rookie -> Champion. Agumon's four of the five the document lists; Tyranomon is undrawable.
        XCTAssertEqual(try targets(of: "agumon"), ["greymon", "devimon", "meramon", "numemon"])
        // Betamon's five, less the three Agumon already reaches, on the substitute.
        XCTAssertEqual(try targets(of: "swimmon"), ["airdramon", "seadramon", "numemon"])

        // Champion -> Ultimate.
        for parent in ["greymon", "devimon", "airdramon"] {
            XCTAssertTrue(try targets(of: parent).contains("metalgreymon_virus"),
                          "\(parent) must reach MetalGreymon (Virus)")
        }
        for parent in ["meramon", "seadramon"] {
            XCTAssertTrue(try targets(of: parent).contains("mamemon"), "\(parent) must reach Mamemon")
        }
        XCTAssertTrue(try targets(of: "numemon").contains("monzaemon"))

        // Ultimate -> Mega.
        XCTAssertTrue(try targets(of: "metalgreymon_virus").contains("blitzgreymon"))
        XCTAssertTrue(try targets(of: "mamemon").contains("banchomamemon"))
        XCTAssertTrue(try targets(of: "monzaemon").contains("dmcv1_shinmonzaemon"))
    }

    /// The section's last row is a Jogress, not an evolution: "BlitzGreymon -> Ultra: Omegamon
    /// Alter-S (Jogress with CresGarurumon)". US-130/US-131 own that, so BlitzGreymon is terminal
    /// here and the pair has to be a recipe instead — otherwise the row is simply missing.
    func testTheUltraRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertTrue(try node("blitzgreymon").evolutions.isEmpty,
                      "a Jogress is not an evolution edge")

        let recipe = try XCTUnwrap(
            JogressCatalog.bundled.recipe(for: "blitzgreymon", and: "cresgarurumon"),
            "the V1 tree's Ultra row has no recipe in jogress.json")
        XCTAssertEqual(recipe.result, "omegamon_alter-s")
    }

    // MARK: - AC4: the tree is reachable from a Digitama, end to end

    /// Since US-144 a line may have SEVERAL eggs — the first orphan sweep hangs an alternate
    /// Digitama off the line whose species it belongs to, rather than opening a one-node line for
    /// it — so the claim generalises from "reachable from THE egg" to "reachable from one of the
    /// line's eggs". The original egg is still asserted to be among them, because an alternate that
    /// had quietly replaced it would satisfy a bare reachability check.
    func testEveryNodeInTheLineIsReachableFromTheLinesDigitama() throws {
        let egg = try node("agu_digitama")
        XCTAssertEqual(egg.line, line)

        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains(egg.id), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertFalse(inLine.isEmpty)
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    /// Every stage from Digitama to Ultimate is occupied, which is what "end to end" means beyond
    /// mere reachability: no rung is skipped on the way up.
    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The line stays self-contained

    /// No edge out of the line leaves it, and no edge from elsewhere reaches in. `EvolutionTreeLayout`
    /// silently drops a connector whose target is outside the laid-out set, so either direction
    /// would draw a node with an arrow to nothing — the reason US-045 gave the Piyomon line its
    /// own scoped ids and the reason `dmcv1_shinmonzaemon` exists.
    func testNoEdgeCrossesTheLineBoundaryInEitherDirection() throws {
        let ids = Set(graph.nodes.filter { $0.line == line }.map(\.id))

        for node in graph.nodes {
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertEqual(node.line == line, target.line == line,
                               "\(node.id) -> \(edge.to) crosses into or out of '\(line)'")
            }
        }
        XCTAssertTrue(ids.contains("dmcv1_shinmonzaemon"))
    }

    /// The scoped ShinMonzaemon is the same Digimon on the same art as the palmon line's, not a
    /// copy of the sprite and not an invented Digimon — the piyo_yuramon pattern exactly.
    func testTheScopedShinMonzaemonSharesTheArtOfTheOneInThePalmonLine() throws {
        let shared = try node("shinmonzaemon")
        let scoped = try node("dmcv1_shinmonzaemon")

        XCTAssertEqual(scoped.displayName, shared.displayName)
        XCTAssertEqual(scoped.spriteFile, shared.spriteFile)
        XCTAssertEqual(scoped.stage, shared.stage)
        XCTAssertEqual(shared.line, "palmon")
        XCTAssertEqual(scoped.line, line)
    }

    // MARK: - AC5/AC6: divergences are written into the data file, sprites are real

    /// Both divergences from the source tree live in `evolutions.json` itself, so the next reader
    /// diffing it against the tree markdown finds the reason there rather than in a commit message.
    func testTheDivergencesAreRecordedInTheDataFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        XCTAssertTrue(try comment(on: "swimmon").contains("Betamon"),
                      "the substitute Rookie must name the Digimon it stands in for")
        XCTAssertTrue(try comment(on: "dmcv1_shinmonzaemon").contains("palmon"),
                      "the scoped id must say which line already took the plain one")
        XCTAssertTrue(try comment(on: "blitzgreymon").contains("jogress.json"),
                      "a terminal Mega must say where its Ultra row went")
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg). Stronger than "the
    /// file exists": an idle-only 16x16 sprite fails here rather than shipping as a Digimon that
    /// cannot animate.
    func testEveryNodeInTheLineHasAnAnimatedSheet() throws {
        for node in graph.nodes where node.line == line {
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(node.id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, node.stage == .digitama ? .egg : .stage, node.id)
        }
    }

    // MARK: - AC10: the validator is clean over the WHOLE file

    func testTheWholeGraphStillPassesTheValidator() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [],
                       errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC12: the orphans this story removed

    /// The nine roster Digimon that had neither an in-edge nor an out-edge before this story and
    /// have one now. Counted here as well as in `notes` so the claim is checkable at any time:
    /// `dmcv1_shinmonzaemon` is deliberately NOT among them — it is not a roster id, so it never
    /// counted as an orphan and wiring it removes nothing.
    func testTheNineOrphansThisStoryClaimedAreConnected() throws {
        let claimed = ["swimmon", "devimon", "airdramon", "seadramon", "metalgreymon_virus",
                       "mamemon", "monzaemon", "blitzgreymon", "banchomamemon"]

        for id in claimed {
            let node = try self.node(id)
            XCTAssertNotNil(Roster.bundled.entry(id: id), "\(id) must be a roster entry to have been an orphan")
            let hasIn = !graph.parents(of: id).isEmpty
            let hasOut = !node.evolutions.isEmpty
            XCTAssertTrue(hasIn, "\(id) has no in-edge, so it is still an orphan")
            XCTAssertTrue(hasIn || hasOut, "\(id) is connected in neither direction")
        }

        XCTAssertNil(Roster.bundled.entry(id: "dmcv1_shinmonzaemon"),
                     "a line-scoped id is not a roster entry and must not be counted as an orphan removed")
    }
}
