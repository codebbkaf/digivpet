import XCTest
@testable import DigiVPet

/// US-136: the Digital Monster Color Version 4 tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 1, "Version 4
/// (Original Clear Red)". Every test here reads the REAL `evolutions.json` — a fixture could
/// satisfy all of it while the shipped file still stopped where US-045 and US-061 left it.
///
/// The seed line US-045 called `piyomon` WAS this tree, authored pruned; US-136 renamed it to
/// `dmc-v4` and filled in the rest, exactly as US-133/134/135 did for Versions 1, 2 and 3.
/// `EvolutionTreeLayout` draws one tree per line and drops any connector leaving it, so a node of
/// the V4 tree in another line would be a Digimon the tree cannot draw an arrow to.
final class DMCVersion4TreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "dmc-v4"

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
    /// Yuramon, Tanemon and Palmon carry line-scoped ids because the `palmon` line owns the plain
    /// ones; see `testTheThreeSharedNamesUseLineScopedIds`. Kokatorimon and Nanimon are the two
    /// names with no animated sheet and are absent on purpose — see
    /// `SeedRosterTests.testTheLineOmitsKokatorimonAndNanimon`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("piyo_yuramon", .babyI),
        ("piyo_tanemon", .babyII),
        ("piyomon", .child),
        ("dmcv4_palmon", .child),
        ("monochromon", .adult),
        ("leomon", .adult),
        ("kuwagamon", .adult),
        ("coelamon", .adult),
        ("mojyamon", .adult),
        ("megadramon", .perfect),
        ("piccolomon", .perfect),
        ("digitamamon", .perfect),
        ("darkdramon", .ultimate),
        ("bloomlordmon", .ultimate),
        ("gankoomon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheVersionFourLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Version 4 tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's absent names for this section, searched with `find -iname` over the whole asset pack:
    ///
    /// - **Kokatorimon** — `find "16x16 Digimon Sprites" -iname '*okatorimon*'` returns NOTHING.
    ///   It is not in the pack at all, animated or idle, so it has no roster entry either.
    /// - **Nanimon** — exactly one hit, `16x16 Digimon Sprites/Idle Frame Only/Nanimon.png`, with
    ///   no 48x64 sheet under `Adult/`. It is one of the 157 `dexOnly` Digimon.
    ///
    /// Both were already found and recorded by US-045; this story re-checked them rather than
    /// trusting the note, and both are still absent. Every OTHER name in the section is playable,
    /// asserted here so that losing one fails in the suite instead of at launch.
    func testEveryOtherNameInTheSectionIsPlayableInTheRoster() throws {
        let displayNames = ["Yuramon", "Tanemon", "Piyomon", "Palmon", "Monochromon", "Leomon",
                            "Kuwagamon", "Coelamon", "Mojyamon", "Megadramon", "Piccolomon",
                            "Digitamamon", "Darkdramon", "BloomLordmon", "Gankoomon"]
        XCTAssertEqual(displayNames.count, Self.sectionMembers.count)

        for name in displayNames {
            let entry = Roster.bundled.entries.first { $0.displayName == name }
            let found = try XCTUnwrap(entry, "\(name) has no roster entry, so it cannot be wired")
            XCTAssertFalse(found.dexOnly, "\(name) is idle-only and may not sit on an edge")
        }

        // The two absent ones, pinned in both directions.
        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "Kokatorimon" },
                     "if a Kokatorimon sheet ever lands, both Rookies gain a sixth Champion")
        let nanimon = try XCTUnwrap(Roster.bundled.entry(id: "nanimon"))
        XCTAssertTrue(nanimon.dexOnly, "Nanimon is idle-only, which is why it is not the junk Champion")
        XCTAssertNil(graph.node(id: "kokatorimon"))
        XCTAssertNil(graph.node(id: "nanimon"))
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the two Rookies.
        XCTAssertTrue(try targets(of: "piyo_digitama").contains("piyo_yuramon"))
        XCTAssertTrue(try targets(of: "piyo_yuramon").contains("piyo_tanemon"))
        XCTAssertTrue(try targets(of: "piyo_tanemon").contains("piyomon"))
        XCTAssertTrue(try targets(of: "piyo_tanemon").contains("dmcv4_palmon"))

        // Rookie -> Champion, minus the two names with no sheet. Piyomon's row is
        // Monochromon / Kokatorimon / Leomon / Kuwagamon / Nanimon; Palmon's adds Coelamon and
        // Mojyamon. GoldNumemon is US-061's junk fallback and is in no source tree.
        XCTAssertEqual(try targets(of: "piyomon"),
                       ["monochromon", "leomon", "kuwagamon", "goldnumemon"])
        XCTAssertEqual(try targets(of: "dmcv4_palmon"),
                       ["leomon", "kuwagamon", "coelamon", "mojyamon", "goldnumemon"])

        // Champion -> Ultimate.
        for parent in ["monochromon", "leomon", "coelamon"] {
            XCTAssertTrue(try targets(of: parent).contains("megadramon"),
                          "\(parent) must reach Megadramon")
        }
        for parent in ["kuwagamon", "mojyamon"] {
            XCTAssertTrue(try targets(of: parent).contains("piccolomon"),
                          "\(parent) must reach Piccolomon")
        }
        // Digitamamon's document parent is Nanimon, which cannot be seeded; US-061 rehomed it onto
        // Kuwagamon as an overfeeding branch, and the `kuwagamon` node's comment says so.
        XCTAssertTrue(try targets(of: "kuwagamon").contains("digitamamon"))

        // Ultimate -> Mega.
        XCTAssertTrue(try targets(of: "megadramon").contains("darkdramon"))
        XCTAssertTrue(try targets(of: "piccolomon").contains("bloomlordmon"))
        XCTAssertTrue(try targets(of: "digitamamon").contains("gankoomon"))
    }

    /// The section's last row is a Jogress, not an evolution: "Darkdramon -> Ultra: Chaosmon
    /// (Jogress with BanchoLeomon)". US-130/US-131 own that, so Darkdramon is terminal here and the
    /// row is met by a recipe — the same shape as the V1 and V2 trees' Ultra rows.
    ///
    /// BanchoLeomon is the Version 3 tree's Mega, so this recipe reaches across two device trees,
    /// which is exactly what the party (US-124) and Jogress (US-132) make possible.
    func testTheUltraRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertTrue(try node("darkdramon").evolutions.isEmpty, "a Jogress is not an evolution edge")
        XCTAssertNil(graph.node(id: "chaosmon"), "Chaosmon is a Jogress result, not a node in this tree")
        XCTAssertNotNil(
            JogressCatalog.bundled.recipe(for: "darkdramon", and: "bancholeomon"),
            "the V4 tree's Ultra row has no recipe in jogress.json")
    }

    // MARK: - AC4: the tree is reachable from a Digitama, end to end

    func testEveryNodeInTheLineIsReachableFromTheLinesDigitama() throws {
        let egg = try node("piyo_digitama")
        XCTAssertEqual(egg.line, line)

        var reached: Set<String> = [egg.id]
        var frontier = [egg.id]
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertFalse(inLine.isEmpty)
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from Piyo Digitama, so not playable end to end")
    }

    /// Every stage from Digitama to Ultimate is occupied, which is what "end to end" means beyond
    /// mere reachability: no rung is skipped on the way up.
    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    /// The document's second Rookie is SIX Champions wide — Kokatorimon / Leomon / Kuwagamon /
    /// Coelamon / Mojyamon / Nanimon — which US-134 and US-135 both flagged as the raise US-136
    /// would have to make to the 2...5 out-degree ceiling and the five-candidate Dex ceiling.
    ///
    /// It did not, and this test is why: two of the six have no animated sheet, so the drawable row
    /// is four. Four earned branches plus the junk fallback is exactly five edges, which is the
    /// widest a Child can be under `SeedRosterTests`' distinct-energy rule anyway — there are only
    /// four energy types. Pinned so that a Kokatorimon sheet landing later fails HERE, where the
    /// reason is written down, rather than in the ceiling test where it reads as an arbitrary limit.
    func testTheSixWideRookieNeededNoCeilingRaiseBecauseTwoOfItsSixHaveNoSheet() throws {
        let palmon = try node("dmcv4_palmon")
        XCTAssertEqual(palmon.evolutions.count, 5, "four earned Champions plus the junk fallback")

        let earned = palmon.evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.count, 4)
        XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, 4,
                       "one branch per energy type — there is no room for a fifth")

        for absent in ["Kokatorimon", "Nanimon"] {
            let playable = Roster.bundled.entries.first { $0.displayName == absent && !$0.dexOnly }
            XCTAssertNil(playable, "\(absent) became playable — this Rookie's row is six wide again")
        }
    }

    /// Hyokomon and Muchomon are in NO source tree: US-045 invented them to carry the Champions the
    /// document draws out of Palmon, back when the plain `palmon` id belonged to another line.
    /// US-136 gave those Champions to `dmcv4_palmon` where the document puts them, but the two
    /// invented Children KEEP their branches — emptying one would leave a shipped Child that
    /// evolves into nothing, a new orphan made by the story whose job is to remove them. Exactly
    /// the call US-135 made for Tsukaimon.
    func testTheInventedChildrenKeptTheirBranches() throws {
        XCTAssertEqual(try targets(of: "hyokomon"), ["mojyamon", "coelamon", "goldnumemon"])
        XCTAssertEqual(try targets(of: "muchomon"), ["kuwagamon", "goldnumemon"])

        for id in ["hyokomon", "muchomon"] {
            XCTAssertEqual(try node(id).line, line)
            XCTAssertEqual(graph.parents(of: id).map(\.id), ["piyo_tanemon"])
        }
    }

    /// GoldNumemon is the V4 line's junk Champion — the one every Rookie falls to — so it is the
    /// `isDefault` edge on all four Children. Stated through the engine rather than by reading the
    /// file: a Digimon whose owner did nothing at all lands on GoldNumemon.
    func testARookieThatDidNothingBecomesGoldNumemon() throws {
        for rookie in ["piyomon", "dmcv4_palmon", "hyokomon", "muchomon"] {
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

            XCTAssertEqual(target, "goldnumemon", "\(rookie) does not fall to the Ver.4 junk Champion")
        }
    }

    /// A well-raised Palmon reaches each of its four Champions, one per energy type. The distinct
    /// energies above prove the branches are TELLABLE apart; this proves the engine actually
    /// routes to each of them, which is the half a data-only check cannot see.
    func testEachOfPalmonsFourBranchesIsReachable() throws {
        let palmon = try node("dmcv4_palmon")
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.standHours": 1_000,
                                               "health.activeEnergy": 50_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 20)

        for (energy, expected) in [(EnergyType.strength, "leomon"), (.stamina, "kuwagamon"),
                                   (.vitality, "coelamon"), (.spirit, "mojyamon")] {
            var totals = EnergyTotals.zero
            totals[energy] = 150

            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: palmon, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 0, conditions: met),
                expected,
                "a well-raised \(energy.rawValue) Palmon does not reach \(expected)")
        }
    }

    // MARK: - The line stays self-contained

    /// No edge out of the line leaves it, and no edge from elsewhere reaches in. `EvolutionTreeLayout`
    /// silently drops a connector whose target is outside the laid-out set, so either direction
    /// would draw a node with an arrow to nothing.
    func testNoEdgeCrossesTheLineBoundaryInEitherDirection() throws {
        for node in graph.nodes {
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertEqual(node.line == line, target.line == line,
                               "\(node.id) -> \(edge.to) crosses into or out of '\(line)'")
            }
        }
    }

    /// Three names in this section are already owned by the `palmon` line, so this tree carries
    /// them under scoped ids: same Digimon, same art, second node. US-045 did Yuramon and Tanemon;
    /// US-136 did Palmon, the document's second Rookie, whose plain id is the classic
    /// Palmon -> Togemon -> Lilimon line's Child.
    func testTheThreeSharedNamesUseLineScopedIds() throws {
        for (shared, scoped) in [("yuramon", "piyo_yuramon"), ("tanemon", "piyo_tanemon"),
                                 ("palmon", "dmcv4_palmon")] {
            let owner = try node(shared)
            let alias = try node(scoped)

            XCTAssertEqual(owner.line, "palmon")
            XCTAssertEqual(alias.line, line)
            XCTAssertEqual(alias.displayName, owner.displayName, "same Digimon in two trees")
            XCTAssertEqual(alias.spriteFile, owner.spriteFile, "and the same art, not a copy")
            XCTAssertEqual(alias.stage, owner.stage)
            XCTAssertNil(Roster.bundled.entry(id: scoped),
                         "\(scoped) is an alias, so it must not take a Dex tile of its own")
        }
    }

    // MARK: - AC5/AC6: divergences are written into the data file, sprites are real

    /// Every divergence from the source tree lives in `evolutions.json` itself, so the next reader
    /// diffing it against the tree markdown finds the reason there rather than in a commit message.
    /// US-045 already wrote the Kokatorimon/Nanimon and Digitamamon ones
    /// (`SeedRosterTests.testThePiyomonDivergencesAreRecordedInTheDataFile`); these are US-136's.
    func testTheDivergencesAreRecordedInTheDataFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        let palmon = try comment(on: "dmcv4_palmon")
        XCTAssertTrue(palmon.contains("palmon line"), "the scoped id must say which line it collides with")
        XCTAssertTrue(palmon.contains("Kokatorimon"), "the two undrawable Champions must be named")
        XCTAssertTrue(palmon.contains("Nanimon"), "the two undrawable Champions must be named")

        XCTAssertTrue(try comment(on: "hyokomon").contains("dmcv4_palmon"),
                      "the invented Child must say what became of the Champions it was built for")
        XCTAssertTrue(try comment(on: "darkdramon").contains("jogress.json"),
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

    /// Palmon is the one roster Digimon this story connected, and it was never an orphan by id: the
    /// `palmon` line has held it since US-008. What US-136 removed is ZERO orphans — the whole
    /// Version 4 section was already wired apart from its second Rookie, and that Rookie is a
    /// second node on an already-connected Digimon.
    ///
    /// Asserted rather than merely noted, because "this story removed no orphans" is the kind of
    /// claim a later reader would assume was a slip.
    func testTheStoryAddedNoNewlyConnectedRosterDigimon() throws {
        XCTAssertNil(Roster.bundled.entry(id: "dmcv4_palmon"))

        let plain = try node("palmon")
        XCTAssertFalse(graph.parents(of: plain.id).isEmpty, "Palmon already had an in-edge")
        XCTAssertFalse(plain.evolutions.isEmpty, "Palmon already had out-edges")
    }
}
