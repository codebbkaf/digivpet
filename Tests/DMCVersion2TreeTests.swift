import XCTest
@testable import DigiVPet

/// US-134: the Digital Monster Color Version 2 tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 1, "Version 2
/// (Original White / Black)". Every test here reads the REAL `evolutions.json` — a fixture could
/// satisfy all of it while the shipped file still stopped where US-061 left it.
///
/// The seed line US-008 called `gabumon` WAS this tree, authored pruned; US-134 renamed it to
/// `dmc-v2` and filled in the rest, exactly as US-133 did for Version 1. `EvolutionTreeLayout`
/// draws one tree per line and drops any connector leaving it, so a node of the V2 tree in another
/// line would be a Digimon the tree cannot draw an arrow to.
final class DMCVersion2TreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "dmc-v2"

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
    /// Whamon is the one entry whose rung is not the document's: see
    /// `testWhamonIsAPerfectBecauseThatIsTheOnlyRungItsArtExistsAt`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("punimon", .babyI),
        ("tsunomon", .babyII),
        ("gabumon", .child),
        ("elecmon", .child),
        ("kabuterimon", .adult),
        ("garurumon", .adult),
        ("angemon", .adult),
        ("yukidarumon", .adult),
        ("vegimon", .adult),
        ("birdramon", .adult),
        ("skullgreymon", .perfect),
        ("metalmamemon", .perfect),
        ("dmcv2_vademon", .perfect),
        ("whamon", .perfect),
        ("skullmammon", .ultimate),
        ("cresgarurumon", .ultimate),
        ("dmcv2_ebemon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheVersionTwoLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Version 2 tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11 has no entry for this section: EVERY name the Version 2 tree lists has a playable
    /// 48x64 sheet, unlike Version 1's Betamon (idle-only) and Tyranomon (no colour art at all).
    /// Asserted rather than merely noted, so that if the roster ever loses one of them this fails
    /// here instead of at launch.
    func testEveryNameInTheSectionIsPlayableInTheRoster() throws {
        let displayNames = ["Punimon", "Tsunomon", "Gabumon", "Elecmon", "Kabuterimon",
                            "Garurumon", "Angemon", "Yukidarumon", "Vegimon", "Birdramon",
                            "Whamon", "SkullGreymon", "MetalMamemon", "Vademon", "SkullMammon",
                            "CresGarurumon", "Ebemon"]
        XCTAssertEqual(displayNames.count, Self.sectionMembers.count)

        for name in displayNames {
            let entry = Roster.bundled.entries.first { $0.displayName == name }
            let found = try XCTUnwrap(entry, "\(name) has no roster entry, so it cannot be wired")
            XCTAssertFalse(found.dexOnly, "\(name) is idle-only and may not sit on an edge")
        }
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the two Rookies.
        XCTAssertTrue(try targets(of: "punimon").contains("tsunomon"))
        XCTAssertTrue(try targets(of: "tsunomon").contains("gabumon"))
        XCTAssertTrue(try targets(of: "tsunomon").contains("elecmon"))

        // Rookie -> Champion. All five of Gabumon's are drawable, which is why this tree needs a
        // five-wide Child where Version 1 needed only four.
        XCTAssertEqual(try targets(of: "gabumon"),
                       ["kabuterimon", "garurumon", "angemon", "yukidarumon", "vegimon"])
        // Elecmon's five, less Whamon, which is a Perfect here — plus Geremon, which is not one of
        // its arrows (see the node's comment in evolutions.json).
        XCTAssertEqual(try targets(of: "elecmon"),
                       ["garurumon", "angemon", "birdramon", "geremon", "vegimon"])

        // Champion -> Ultimate.
        for parent in ["kabuterimon", "angemon", "birdramon"] {
            XCTAssertTrue(try targets(of: parent).contains("skullgreymon"),
                          "\(parent) must reach SkullGreymon")
        }
        for parent in ["garurumon", "yukidarumon"] {
            XCTAssertTrue(try targets(of: parent).contains("metalmamemon"),
                          "\(parent) must reach MetalMamemon")
        }
        XCTAssertTrue(try targets(of: "vegimon").contains("dmcv2_vademon"))

        // Ultimate -> Mega.
        XCTAssertTrue(try targets(of: "skullgreymon").contains("skullmammon"))
        XCTAssertTrue(try targets(of: "metalmamemon").contains("cresgarurumon"))
        XCTAssertTrue(try targets(of: "dmcv2_vademon").contains("dmcv2_ebemon"))
    }

    /// The section's last row is a Jogress, not an evolution: "CresGarurumon -> Ultra: Omegamon
    /// Alter-S (Jogress with BlitzGreymon)" — the other half of the row US-133 met from the V1
    /// side. US-130/US-131 own it, so CresGarurumon is terminal here and the pair has to be a
    /// recipe instead, otherwise the row is simply missing.
    func testTheUltraRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertTrue(try node("cresgarurumon").evolutions.isEmpty,
                      "a Jogress is not an evolution edge")

        let recipe = try XCTUnwrap(
            JogressCatalog.bundled.recipe(for: "cresgarurumon", and: "blitzgreymon"),
            "the V2 tree's Ultra row has no recipe in jogress.json")
        XCTAssertEqual(recipe.result, "omegamon_alter-s")
    }

    // MARK: - AC4: the tree is reachable from a Digitama, end to end

    /// Since US-144 a line may have SEVERAL eggs — the first orphan sweep hangs an alternate
    /// Digitama off the line whose species it belongs to, rather than opening a one-node line for
    /// it — so the claim generalises from "reachable from THE egg" to "reachable from one of the
    /// line's eggs". The original egg is still asserted to be among them, because an alternate that
    /// had quietly replaced it would satisfy a bare reachability check.
    func testEveryNodeInTheLineIsReachableFromTheLinesDigitama() throws {
        let egg = try node("gabu_digitama")
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

    /// Geremon was Gabumon's junk fallback until this story, and the V2 tree has no room for it:
    /// Gabumon's five arrows are spoken for and end in Vegimon. Dropping it would have left a
    /// shipped Digimon with no parent at all — reachable from nothing, so no longer obtainable —
    /// which is the opposite of what Phase E is for. It hangs off Elecmon instead.
    func testGeremonKeptAParentWhenVegimonTookItsFallback() throws {
        XCTAssertEqual(graph.parents(of: "geremon").map(\.id), ["elecmon"])

        let edge = try XCTUnwrap(node("elecmon").evolutions.first { $0.to == "geremon" })
        XCTAssertFalse(edge.isDefault, "Vegimon is the tree's fallback; Geremon is now earned")
        XCTAssertFalse(edge.conditions.isEmpty, "an earned edge without a criterion is a fallback")

        // And its own subtree still hangs together underneath it.
        XCTAssertEqual(try targets(of: "geremon"), ["weregarurumon", "gerbemon"])
    }

    // MARK: - The line stays self-contained

    /// No edge out of the line leaves it, and no edge from elsewhere reaches in. `EvolutionTreeLayout`
    /// silently drops a connector whose target is outside the laid-out set, so either direction
    /// would draw a node with an arrow to nothing — the reason US-045 gave the Piyomon line its
    /// own scoped ids and the reason `dmcv2_vademon` exists.
    func testNoEdgeCrossesTheLineBoundaryInEitherDirection() throws {
        let ids = Set(graph.nodes.filter { $0.line == line }.map(\.id))

        for node in graph.nodes {
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertEqual(node.line == line, target.line == line,
                               "\(node.id) -> \(edge.to) crosses into or out of '\(line)'")
            }
        }
        XCTAssertTrue(ids.contains("dmcv2_vademon"))
        XCTAssertTrue(ids.contains("dmcv2_ebemon"))
    }

    /// The scoped Vademon and Ebemon are the same Digimon on the same art as the dmc-v5 line's,
    /// not copies of the sprite and not invented Digimon — the dmcv1_shinmonzaemon pattern exactly.
    func testTheScopedVademonAndEbemonShareTheArtOfTheOnesInTheGazimonLine() throws {
        for (scopedId, sharedId) in [("dmcv2_vademon", "vademon"), ("dmcv2_ebemon", "ebemon")] {
            let shared = try node(sharedId)
            let scoped = try node(scopedId)

            XCTAssertEqual(scoped.displayName, shared.displayName)
            XCTAssertEqual(scoped.spriteFile, shared.spriteFile)
            XCTAssertEqual(scoped.stage, shared.stage)
            XCTAssertEqual(shared.line, "dmc-v5")
            XCTAssertEqual(scoped.line, line)
        }
    }

    // MARK: - AC5/AC6: divergences are written into the data file, sprites are real

    /// THE ONE STAGE DIVERGENCE. The document makes Whamon a Champion feeding MetalMamemon, but
    /// this asset pack files its only animated sheet under `Perfect/`, so the roster has it at
    /// Perfect and a node claiming Adult would resolve to no art at all — `missingSprite`, caught
    /// by the validator. It stands beside MetalMamemon instead of beneath it.
    func testWhamonIsAPerfectBecauseThatIsTheOnlyRungItsArtExistsAt() throws {
        let whamon = try node("whamon")
        XCTAssertEqual(whamon.stage, .perfect)
        XCTAssertEqual(Roster.bundled.entry(id: "whamon")?.stage, .perfect,
                       "the roster's rung is what the art folder says; the node must agree")
        XCTAssertNil(SpriteLoader.url(stage: Stage.adult.rawValue, name: "Whamon"),
                     "if an Adult Whamon sheet ever appears, move it back to the document's rung")

        // It keeps the two Champions the document puts on its row, and shares MetalMamemon's Mega.
        XCTAssertEqual(Set(graph.parents(of: "whamon").map(\.id)), ["garurumon", "yukidarumon"])
        XCTAssertEqual(try targets(of: "whamon"), ["cresgarurumon"])
    }

    /// Every divergence from the source tree lives in `evolutions.json` itself, so the next reader
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

        XCTAssertTrue(try comment(on: "whamon").contains("Perfect"),
                      "the relocated Digimon must say which rung its art forced it onto")
        XCTAssertTrue(try comment(on: "dmcv2_vademon").contains("dmc-v5"),
                      "a scoped id must say which line already took the plain one")
        XCTAssertTrue(try comment(on: "dmcv2_ebemon").contains("dmc-v5"))
        XCTAssertTrue(try comment(on: "elecmon").contains("Geremon"),
                      "the Rookie that adopted Geremon must say so")
        XCTAssertTrue(try comment(on: "vegimon").contains("SkullGreymon"),
                      "the one invented Champion arrow must be called out where it is authored")
        XCTAssertTrue(try comment(on: "cresgarurumon").contains("jogress.json"),
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

    /// The eleven roster Digimon that had neither an in-edge nor an out-edge before this story and
    /// have one now. Counted here as well as in `notes` so the claim is checkable at any time:
    /// `dmcv2_vademon` and `dmcv2_ebemon` are deliberately NOT among them — they are not roster
    /// ids, so they never counted as orphans and wiring them removes nothing.
    func testTheElevenOrphansThisStoryClaimedAreConnected() throws {
        let claimed = ["elecmon", "kabuterimon", "angemon", "yukidarumon", "vegimon", "birdramon",
                       "skullgreymon", "metalmamemon", "whamon", "skullmammon", "cresgarurumon"]

        for id in claimed {
            let node = try self.node(id)
            XCTAssertNotNil(Roster.bundled.entry(id: id), "\(id) must be a roster entry to have been an orphan")
            let hasIn = !graph.parents(of: id).isEmpty
            let hasOut = !node.evolutions.isEmpty
            XCTAssertTrue(hasIn, "\(id) has no in-edge, so it is still an orphan")
            XCTAssertTrue(hasIn || hasOut, "\(id) is connected in neither direction")
        }

        for alias in ["dmcv2_vademon", "dmcv2_ebemon"] {
            XCTAssertNil(Roster.bundled.entry(id: alias),
                         "a line-scoped id is not a roster entry and must not be counted as an orphan removed")
        }
    }
}
