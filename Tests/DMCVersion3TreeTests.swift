import XCTest
@testable import DigiVPet

/// US-135: the Digital Monster Color Version 3 tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 1, "Version 3
/// (Original Purple)". Every test here reads the REAL `evolutions.json` — a fixture could satisfy
/// all of it while the shipped file still stopped where US-061 left it.
///
/// The seed line US-044 called `patamon` WAS this tree, authored pruned; US-135 renamed it to
/// `dmc-v3` and filled in the rest, exactly as US-133 and US-134 did for Versions 1 and 2.
/// `EvolutionTreeLayout` draws one tree per line and drops any connector leaving it, so a node of
/// the V3 tree in another line would be a Digimon the tree cannot draw an arrow to.
///
/// Unlike Version 1 and Version 2 this section has NO Ultra row at all, so there is no Jogress half
/// to check — the document's last line for Version 3 is Etemon -> Mega: BanchoLeomon.
final class DMCVersion3TreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "dmc-v3"

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
    ///
    /// Poyomon, the document's Fresh, is NOT here: it is idle-only and may not be playable. See
    /// `SeedRosterTests.testTheLineDoesNotUsePoyomon` and the Puttimon substitution US-044 made.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("tokomon", .babyII),
        ("patamon", .child),
        ("kunemon", .child),
        ("unimon", .adult),
        ("centalmon", .adult),
        ("ogremon", .adult),
        ("bakemon", .adult),
        ("shellmon", .adult),
        ("drimogemon", .adult),
        ("scumon", .adult),
        ("andromon", .perfect),
        ("giromon", .perfect),
        ("etemon", .perfect),
        ("hiandromon", .ultimate),
        ("gokumon", .ultimate),
        ("bancholeomon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheVersionThreeLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Version 3 tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's one absent name for this section is Poyomon, and it is absent as ART rather than as a
    /// name: `find -iname 'Poyomon.png'` over the whole asset pack returns exactly one hit,
    /// `16x16 Digimon Sprites/Idle Frame Only/Poyomon.png`, with no 48x64 sheet under `Baby I/`.
    /// Every OTHER name in the section is playable, and that is asserted rather than merely noted so
    /// that losing one of them fails here instead of at launch.
    func testEveryOtherNameInTheSectionIsPlayableInTheRoster() throws {
        let displayNames = ["Tokomon", "Patamon", "Kunemon", "Unimon", "Centalmon", "Ogremon",
                            "Bakemon", "Shellmon", "Drimogemon", "Scumon", "Andromon", "Giromon",
                            "Etemon", "HiAndromon", "Gokumon", "BanchoLeomon"]
        XCTAssertEqual(displayNames.count, Self.sectionMembers.count)

        for name in displayNames {
            let entry = Roster.bundled.entries.first { $0.displayName == name }
            let found = try XCTUnwrap(entry, "\(name) has no roster entry, so it cannot be wired")
            XCTAssertFalse(found.dexOnly, "\(name) is idle-only and may not sit on an edge")
        }

        // The absent one, pinned in both directions: no playable roster entry, and no node.
        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "Poyomon" && !$0.dexOnly },
                     "if a Poyomon sheet ever lands, it replaces Puttimon as this line's Baby I")
        XCTAssertNil(graph.node(id: "poyomon"))
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the two Rookies. Fresh is Puttimon, not the document's Poyomon.
        XCTAssertTrue(try targets(of: "puttimon").contains("tokomon"))
        XCTAssertTrue(try targets(of: "tokomon").contains("patamon"))
        XCTAssertTrue(try targets(of: "tokomon").contains("kunemon"))

        // Rookie -> Champion. All five of Patamon's are drawable and all five hang off Patamon
        // since US-135; Kunemon's five are the document's, sharing three with Patamon.
        XCTAssertEqual(try targets(of: "patamon"),
                       ["unimon", "centalmon", "ogremon", "bakemon", "scumon"])
        XCTAssertEqual(try targets(of: "kunemon"),
                       ["ogremon", "bakemon", "shellmon", "drimogemon", "scumon"])

        // Champion -> Ultimate.
        for parent in ["unimon", "centalmon", "shellmon"] {
            XCTAssertTrue(try targets(of: parent).contains("andromon"),
                          "\(parent) must reach Andromon")
        }
        for parent in ["ogremon", "bakemon", "drimogemon"] {
            XCTAssertTrue(try targets(of: parent).contains("giromon"),
                          "\(parent) must reach Giromon")
        }
        XCTAssertTrue(try targets(of: "scumon").contains("etemon"))

        // Ultimate -> Mega.
        XCTAssertTrue(try targets(of: "andromon").contains("hiandromon"))
        XCTAssertTrue(try targets(of: "giromon").contains("gokumon"))
        XCTAssertTrue(try targets(of: "etemon").contains("bancholeomon"))
    }

    /// The section has no "Ultra (Jogress)" row, unlike Versions 1, 2 and 4. Asserted rather than
    /// assumed: the three Megas here are terminal on purpose, and a later story adding a recipe for
    /// one of them should have to notice this test and say why.
    func testTheSectionHasNoUltraRow() throws {
        for mega in ["hiandromon", "gokumon", "bancholeomon"] {
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is terminal in the V3 tree")
        }
    }

    // MARK: - AC4: the tree is reachable from a Digitama, end to end

    /// Since US-144 a line may have SEVERAL eggs — the first orphan sweep hangs an alternate
    /// Digitama off the line whose species it belongs to, rather than opening a one-node line for
    /// it — so the claim generalises from "reachable from THE egg" to "reachable from one of the
    /// line's eggs". The original egg is still asserted to be among them, because an alternate that
    /// had quietly replaced it would satisfy a bare reachability check.
    func testEveryNodeInTheLineIsReachableFromTheLinesDigitama() throws {
        let egg = try node("pata_digitama")
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

    /// Tsukaimon was US-061's second Child, invented to carry Ogremon and Bakemon when a Child
    /// could hold only two earned branches. The document has no Tsukaimon at all, and US-135 gives
    /// Patamon its five Champions back — but stripping Tsukaimon's branches would leave a shipped
    /// Digimon that evolves into nothing, which is the opposite of what Phase E is for. It keeps
    /// them, standing beside Kunemon as a third Rookie the device never had.
    func testTsukaimonKeptItsBranchesWhenPatamonTookAllFiveChampions() throws {
        let tsukaimon = try node("tsukaimon")
        XCTAssertEqual(tsukaimon.line, line)
        XCTAssertEqual(graph.parents(of: "tsukaimon").map(\.id), ["tokomon"])
        XCTAssertEqual(try targets(of: "tsukaimon"), ["ogremon", "bakemon", "scumon"])
    }

    /// Scumon is the V3 device's junk Champion — the one BOTH Rookies fall to — so it is the
    /// `isDefault` edge on all three Children, and Etemon is the junk Perfect under it. Stated
    /// through the engine rather than by reading the file: a Digimon whose owner did nothing at all
    /// lands on Scumon.
    func testAPatamonOrKunemonThatDidNothingBecomesScumon() throws {
        for rookie in ["patamon", "kunemon", "tsukaimon"] {
            let node = try self.node(rookie)
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: node,
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "scumon", "\(rookie) does not fall to the Ver.3 junk Champion")
        }
    }

    // MARK: - The line stays self-contained

    /// No edge out of the line leaves it, and no edge from elsewhere reaches in. `EvolutionTreeLayout`
    /// silently drops a connector whose target is outside the laid-out set, so either direction
    /// would draw a node with an arrow to nothing.
    ///
    /// Version 3 needs NO line-scoped alias, unlike `dmcv1_shinmonzaemon` and `dmcv2_vademon`: no
    /// other line already owns any of its sixteen names.
    func testNoEdgeCrossesTheLineBoundaryInEitherDirection() throws {
        for node in graph.nodes {
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertEqual(node.line == line, target.line == line,
                               "\(node.id) -> \(edge.to) crosses into or out of '\(line)'")
            }
        }

        let scoped = graph.nodes.filter { $0.line == line && $0.id.hasPrefix("dmcv3_") }
        XCTAssertEqual(scoped, [], "no name in the V3 tree collides with another line's")
    }

    // MARK: - AC5/AC6: divergences are written into the data file, sprites are real

    /// Every divergence from the source tree lives in `evolutions.json` itself, so the next reader
    /// diffing it against the tree markdown finds the reason there rather than in a commit message.
    /// US-044 already wrote the Poyomon one onto `puttimon`
    /// (`SeedRosterTests.testThePoyomonSubstitutionIsRecordedInTheDataFile`); these are US-135's.
    func testTheDivergencesAreRecordedInTheDataFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        XCTAssertTrue(try comment(on: "patamon").contains("Tsukaimon"),
                      "the Rookie that took its five Champions back must say what became of the stand-in")
        XCTAssertTrue(try comment(on: "kunemon").contains("Shellmon"),
                      "the second Rookie must name the Champions that are its alone")
        XCTAssertTrue(try comment(on: "shellmon").contains("Andromon"))
        XCTAssertTrue(try comment(on: "drimogemon").contains("Giromon"))
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

    /// The three roster Digimon that had neither an in-edge nor an out-edge before this story and
    /// have both now. Counted here as well as in `notes` so the claim is checkable at any time.
    /// Version 3 removes far fewer than Versions 1 and 2 because US-044 authored most of the tree
    /// already — only its second Rookie and that Rookie's two exclusive Champions were missing.
    func testTheThreeOrphansThisStoryClaimedAreConnected() throws {
        for id in ["kunemon", "shellmon", "drimogemon"] {
            let node = try self.node(id)
            XCTAssertNotNil(Roster.bundled.entry(id: id),
                            "\(id) must be a roster entry to have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty, "\(id) has no in-edge, so it is still an orphan")
            XCTAssertFalse(node.evolutions.isEmpty, "\(id) leads nowhere")
        }
    }
}
