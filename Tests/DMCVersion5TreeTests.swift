import XCTest
@testable import DigiVPet

/// US-137: the Digital Monster Color Version 5 tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 1, "Version 5
/// (Original Clear Green)", line 75. Every test here reads the REAL `evolutions.json` — a fixture
/// could satisfy all of it while the shipped file still stopped where US-046 and US-061 left it.
///
/// The seed line US-046 called `gazimon` WAS this tree, authored pruned; US-137 renamed it to
/// `dmc-v5` and finished it, exactly as US-133/134/135/136 did for Versions 1 to 4.
/// `EvolutionTreeLayout` draws one tree per line and drops any connector leaving it, so a node of
/// the V5 tree in another line would be a Digimon the tree cannot draw an arrow to.
final class DMCVersion5TreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "dmc-v5"

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
    /// Flymon is the one name with no animated sheet and is absent on purpose — see
    /// `SeedRosterTests.testTheLineOmitsFlymon`. Chaosdramon is the Ultra row and is a Jogress
    /// result rather than a node here.
    ///
    /// This line needs NO line-scoped alias: `testTheLineNeedsNoLineScopedAlias` pins that.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("zurumon", .babyI),
        ("pagumon", .babyII),
        ("gazimon", .child),
        ("gizamon", .child),
        ("darktyranomon", .adult),
        ("cyclomon", .adult),
        ("devidramon", .adult),
        ("tuskmon", .adult),
        ("deltamon", .adult),
        ("raremon", .adult),
        ("metaltyranomon", .perfect),
        ("ex-tyranomon", .perfect),
        ("nanomon", .perfect),
        ("mugendramon", .ultimate),
        ("gaioumon", .ultimate),
        ("raidenmon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheVersionFiveLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Version 5 tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's absent names for this section, searched with `find -iname` over the whole asset pack:
    ///
    /// - **Flymon** — two hits, `16x16 Digimon Sprites/Idle Frame Only/Flymon.png` and an unrelated
    ///   `Butterflymon.png`. There is no 48x64 sheet under `Adult/`, so Flymon is one of the 157
    ///   `dexOnly` Digimon and may never sit on an edge.
    ///
    /// That is the section's ONLY absent name — re-checked here rather than trusted from US-046's
    /// note, which is what US-136 found was worth doing. Every other name in the section is
    /// playable, asserted so that losing one fails in the suite instead of at launch.
    ///
    /// "Mugendramon (Machinedramon)" is one Digimon under two dub names; the pack and the roster
    /// hold only `Mugendramon`, and `Machinedramon` matches nothing at all.
    func testEveryOtherNameInTheSectionIsPlayableInTheRoster() throws {
        let displayNames = ["Zurumon", "Pagumon", "Gazimon", "Gizamon", "DarkTyranomon", "Cyclomon",
                            "Devidramon", "Tuskmon", "Deltamon", "Raremon", "MetalTyranomon",
                            "Ex-Tyranomon", "Nanomon", "Mugendramon", "Gaioumon", "Raidenmon"]
        XCTAssertEqual(displayNames.count, Self.sectionMembers.count)

        for name in displayNames {
            let entry = Roster.bundled.entries.first { $0.displayName == name }
            let found = try XCTUnwrap(entry, "\(name) has no roster entry, so it cannot be wired")
            XCTAssertFalse(found.dexOnly, "\(name) is idle-only and may not sit on an edge")
        }

        // The one absent name, pinned in both directions.
        let flymon = try XCTUnwrap(Roster.bundled.entry(id: "flymon"))
        XCTAssertTrue(flymon.dexOnly, "Flymon is idle-only, which is why Gizamon's row is five wide")
        XCTAssertNil(graph.node(id: "flymon"))
        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "Machinedramon" },
                     "Machinedramon is Mugendramon's dub name, not a second Digimon")
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the two Rookies.
        XCTAssertTrue(try targets(of: "gazi_digitama").contains("zurumon"))
        XCTAssertTrue(try targets(of: "zurumon").contains("pagumon"))
        XCTAssertTrue(try targets(of: "pagumon").contains("gazimon"))
        XCTAssertTrue(try targets(of: "pagumon").contains("gizamon"))

        // Rookie -> Champion. Gazimon's document row is DarkTyranomon / Cyclomon / Devidramon /
        // Tuskmon / Raremon; Gizamon's is Cyclomon / Devidramon / Tuskmon / Flymon / Deltamon /
        // Raremon, minus the undrawable Flymon.
        XCTAssertEqual(try targets(of: "gazimon"),
                       ["darktyranomon", "cyclomon", "devidramon", "tuskmon", "raremon"])
        XCTAssertEqual(try targets(of: "gizamon"),
                       ["cyclomon", "devidramon", "tuskmon", "deltamon", "raremon"])

        // Champion -> Ultimate. Flymon is the third parent of MetalTyranomon in the document.
        for parent in ["darktyranomon", "cyclomon"] {
            XCTAssertTrue(try targets(of: parent).contains("metaltyranomon"),
                          "\(parent) must reach MetalTyranomon")
        }
        for parent in ["devidramon", "tuskmon", "deltamon"] {
            XCTAssertTrue(try targets(of: parent).contains("ex-tyranomon"),
                          "\(parent) must reach Ex-Tyranomon")
        }
        XCTAssertTrue(try targets(of: "raremon").contains("nanomon"))

        // Ultimate -> Mega.
        XCTAssertTrue(try targets(of: "metaltyranomon").contains("mugendramon"))
        XCTAssertTrue(try targets(of: "ex-tyranomon").contains("gaioumon"))
        XCTAssertTrue(try targets(of: "nanomon").contains("raidenmon"))
    }

    /// The four edges this story added, named one by one. `testEveryArrowInTheSectionIsAnEdge`
    /// asserts the finished rows; this asserts what was MISSING before US-137, so a later edit that
    /// quietly drops one of them reads as this story being undone rather than as a tuning change.
    func testTheFourEdgesThisStoryAddedAreTheOnesTheDocumentAlreadyDrew() throws {
        for (rookie, champion, energy) in [("gazimon", "devidramon", EnergyType.spirit),
                                           ("gazimon", "tuskmon", .stamina),
                                           ("gizamon", "cyclomon", .vitality),
                                           ("gizamon", "devidramon", .spirit)] {
            let edge = try XCTUnwrap(try node(rookie).evolutions.first { $0.to == champion },
                                     "\(rookie) -> \(champion) is missing")
            XCTAssertEqual(edge.requiredEnergy, energy)
            XCTAssertFalse(edge.isDefault, "an earned branch, not the junk fallback")
            XCTAssertFalse(edge.conditions.isEmpty, "AC9: every edge carries a condition")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(rookie) -> \(champion) carries a blank hint")
            }
        }
    }

    /// The section's last row is a Jogress, not an evolution: "Mugendramon -> Ultra: Chaosdramon
    /// (Jogress with Darkdramon)". US-130/US-131 own that, so Mugendramon is terminal here and the
    /// row is met by a recipe — the same shape as the V1, V2 and V4 trees' Ultra rows.
    ///
    /// Darkdramon is the Version 4 tree's Mega, so this recipe reaches across two device trees,
    /// which is exactly what the party (US-124) and Jogress (US-132) make possible.
    func testTheUltraRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertTrue(try node("mugendramon").evolutions.isEmpty, "a Jogress is not an evolution edge")
        XCTAssertNil(graph.node(id: "chaosdramon"), "Chaosdramon is a Jogress result, not a node in this tree")
        XCTAssertNotNil(
            JogressCatalog.bundled.recipe(for: "mugendramon", and: "darkdramon"),
            "the V5 tree's Ultra row has no recipe in jogress.json")
        XCTAssertEqual(graph.node(id: "darkdramon")?.line, "dmc-v4",
                       "the recipe's other parent is the Version 4 tree's Mega")
    }

    // MARK: - AC4: the tree is reachable from a Digitama, end to end

    func testEveryNodeInTheLineIsReachableFromTheLinesDigitama() throws {
        let egg = try node("gazi_digitama")
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
                       "unreachable from Gazi Digitama, so not playable end to end")
    }

    /// Every stage from Digitama to Ultimate is occupied, which is what "end to end" means beyond
    /// mere reachability: no rung is skipped on the way up.
    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The six-wide Rookie, which is what this story was expected to be about

    /// Gizamon is the second Rookie in Phase E the document draws SIX Champions wide — Cyclomon /
    /// Devidramon / Tuskmon / Flymon / Deltamon / Raremon — and US-134, US-135 and US-136 all
    /// predicted US-137 would have to raise the 2...5 out-degree ceiling and the five-candidate Dex
    /// ceiling for it. US-136 went further and said this one "probably WILL need the raise",
    /// because US-046's note gives Flymon as the section's only omission.
    ///
    /// It did not, and this test is why: that one omission is enough. Six minus Flymon is five,
    /// which is four earned branches plus the junk fallback — and four earned branches is the hard
    /// ceiling anyway, because `SeedRosterTests` requires distinct dominant energies and there are
    /// only four energy types.
    ///
    /// Pinned so that a Flymon sheet landing later fails HERE, where the reason is written down,
    /// rather than in the ceiling test where it reads as an arbitrary limit. If that happens the
    /// row genuinely cannot be authored as it stands and one of the six has to move to another
    /// Child, the way US-045 moved Palmon's onto Hyokomon and Muchomon.
    func testTheSixWideRookieNeededNoCeilingRaiseBecauseOneOfItsSixHasNoSheet() throws {
        let gizamon = try node("gizamon")
        XCTAssertEqual(gizamon.evolutions.count, 5, "four earned Champions plus the junk fallback")

        let earned = gizamon.evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.count, 4)
        XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, 4,
                       "one branch per energy type — there is no room for a fifth")

        let playableFlymon = Roster.bundled.entries.first { $0.displayName == "Flymon" && !$0.dexOnly }
        XCTAssertNil(playableFlymon, "Flymon became playable — this Rookie's row is six wide again")
    }

    /// The two document Rookies now carry the same five Champions apiece, four of them shared. The
    /// sharing is the tree's own shape, not a shortcut: `requiredEnergy` is a property of the EDGE,
    /// so one Champion costs each Rookie whichever of its four slots is still free (US-135's
    /// finding). Here the two rows happen to agree on every shared energy, and the only difference
    /// is DarkTyranomon vs Deltamon on strength.
    func testBothRookiesCarryFiveChampionsFourOfThemShared() throws {
        let gazimon = try targets(of: "gazimon")
        let gizamon = try targets(of: "gizamon")

        XCTAssertEqual(gazimon.count, 5)
        XCTAssertEqual(gizamon.count, 5)
        XCTAssertEqual(gazimon.intersection(gizamon).sorted(),
                       ["cyclomon", "devidramon", "raremon", "tuskmon"])
        XCTAssertEqual(gazimon.subtracting(gizamon), ["darktyranomon"])
        XCTAssertEqual(gizamon.subtracting(gazimon), ["deltamon"])

        for champion in ["cyclomon", "devidramon", "tuskmon"] {
            let a = try XCTUnwrap(try node("gazimon").evolutions.first { $0.to == champion })
            let b = try XCTUnwrap(try node("gizamon").evolutions.first { $0.to == champion })
            XCTAssertEqual(a.requiredEnergy, b.requiredEnergy,
                           "\(champion) is the same branch from both Rookies")
        }
    }

    /// Psychemon is in NO source tree: US-061 invented it as a third Rookie while a Child could
    /// carry only two earned branches. US-137 gave Gazimon and Gizamon the rows the document draws,
    /// which makes Psychemon's Devidramon redundant — but it KEEPS its branches, because emptying
    /// it would leave a shipped Child that evolves into nothing, a new orphan made by the story
    /// whose job is to remove them. The call US-134 made for Geremon, US-135 for Tsukaimon and
    /// US-136 for Hyokomon and Muchomon, made a fourth time.
    func testTheInventedThirdRookieKeptItsBranches() throws {
        XCTAssertEqual(try targets(of: "psychemon"), ["devidramon", "raremon"])
        XCTAssertEqual(try node("psychemon").line, line)
        XCTAssertEqual(graph.parents(of: "psychemon").map(\.id), ["pagumon"])
    }

    /// Raremon is the V5 line's junk Champion — the one every Rookie falls to — so it is the
    /// `isDefault` edge on all three Children. Stated through the engine rather than by reading the
    /// file: a Digimon whose owner did nothing at all lands on Raremon.
    func testARookieThatDidNothingBecomesRaremon() throws {
        for rookie in ["gazimon", "gizamon", "psychemon"] {
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

            XCTAssertEqual(target, "raremon", "\(rookie) does not fall to the Ver.5 junk Champion")
        }
    }

    /// Each Rookie reaches each of its four Champions, one per energy type. The distinct energies
    /// above prove the branches are TELLABLE apart; this proves the engine actually routes to each
    /// of them, which is the half a data-only check cannot see.
    func testEachOfBothRookiesFourBranchesIsReachable() throws {
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.standHours": 1_000,
                                               "health.exerciseMinutes": 5_000,
                                               "health.activeEnergy": 50_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 20)

        let rows: [(String, [(EnergyType, String)])] = [
            ("gazimon", [(.strength, "darktyranomon"), (.vitality, "cyclomon"),
                         (.spirit, "devidramon"), (.stamina, "tuskmon")]),
            ("gizamon", [(.strength, "deltamon"), (.vitality, "cyclomon"),
                         (.spirit, "devidramon"), (.stamina, "tuskmon")]),
        ]

        for (rookie, branches) in rows {
            let node = try self.node(rookie)
            for (energy, expected) in branches {
                var totals = EnergyTotals.zero
                totals[energy] = 150

                XCTAssertEqual(
                    EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                    careMistakes: 0, battleWins: 0, conditions: met),
                    expected,
                    "a well-raised \(energy.rawValue) \(rookie) does not reach \(expected)")
            }
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

    /// This tree needs no line-scoped alias — the second of Phase E's five to need none, after
    /// Version 3. It is the line that OWNS the plain `vademon` and `ebemon` ids that US-134 had to
    /// scope for the Version 2 tree, so the collision runs the other way here.
    ///
    /// `extyranomon` WAS listed beside the four real ones and was never an alias at all — it was
    /// the roster's `ex-tyranomon` with the hyphen dropped, one Digimon under two spellings of one
    /// id. **US-158 RETIRED THE DRIFT**: the Perfect D-G sweep found `ex-tyranomon` counted as an
    /// orphan by Appendix B, because the sheet id had nothing pointing at it while the graph's
    /// hyphen-less id carried all three in-edges, and renaming the node cleared the orphan without
    /// adding one. So the claim is now the stronger one — the graph and the roster spell it the
    /// same way, and the old spelling is nowhere.
    func testTheLineNeedsNoLineScopedAlias() throws {
        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("dmcv5_") }.map(\.id), [],
                       "the day a dmcv5_ alias is needed, write the reason down here")

        for id in ["vademon", "ebemon"] {
            XCTAssertEqual(try node(id).line, line, "\(id)'s plain id belongs to this line")
            XCTAssertEqual(try node("dmcv2_\(id)").line, "dmc-v2", "and US-134 scoped the V2 copy")
        }

        XCTAssertNil(graph.node(id: "extyranomon"),
                     "the hyphen-less spelling is back — US-158 retired it, say why it returned")
        XCTAssertNil(Roster.bundled.entry(id: "extyranomon"))
        let hyphenated = try XCTUnwrap(Roster.bundled.entry(id: "ex-tyranomon"))
        XCTAssertEqual(hyphenated.displayName, try node("ex-tyranomon").displayName)
        XCTAssertEqual(hyphenated.spriteFile, try node("ex-tyranomon").spriteFile)
    }

    // MARK: - AC5/AC6: divergences are written into the data file, sprites are real

    /// Every divergence from the source tree lives in `evolutions.json` itself, so the next reader
    /// diffing it against the tree markdown finds the reason there rather than in a commit message.
    /// US-046 already wrote the Flymon and Pagumon-branches ones
    /// (`SeedRosterTests.testTheGazimonDivergencesAreRecordedInTheDataFile`); these are US-137's.
    func testTheDivergencesAreRecordedInTheDataFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        let gizamon = try comment(on: "gizamon")
        XCTAssertTrue(gizamon.contains("Flymon"), "the undrawable Champion must be named")
        XCTAssertTrue(gizamon.contains("ceiling"),
                      "the six-wide row must say why no ceiling had to move")

        XCTAssertTrue(try comment(on: "psychemon").contains("US-061"),
                      "the invented Child must say where it came from and why it keeps its branches")
        XCTAssertTrue(try comment(on: "mugendramon").contains("jogress.json"),
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

    /// AC7: no `dexOnly` Digimon on any edge, over the WHOLE file rather than this line — the
    /// validator says the same thing, but this states the criterion the story was written against.
    func testNoDexOnlyDigimonAppearsOnAnyEdge() throws {
        for node in graph.nodes {
            XCTAssertFalse(node.dexOnly, "\(node.id) is a dexOnly node")
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertFalse(target.dexOnly, "\(node.id) -> \(edge.to) points at a dexOnly Digimon")
                XCTAssertFalse(Roster.bundled.entry(id: edge.to)?.dexOnly ?? false,
                               "\(edge.to) is dexOnly in the roster")
            }
        }
    }

    /// AC8: every node in the file carries a `line`. `EvolutionGraph.bundled` traps at launch on an
    /// undecodable file, so this is the test that would have caught it before the app did.
    func testEveryNodeInTheFileCarriesALine() {
        for node in graph.nodes {
            XCTAssertFalse(node.line.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(node.id) has no line")
        }
    }

    /// AC9, read the only way it can be true of this file: every CONDITION carries a non-empty
    /// hint. The literal reading — every EDGE carries a condition — is contradicted by a rule that
    /// predates this story, `EvolutionCriteriaTests.testEveryJunkFallbackIsReachableByInaction`,
    /// which requires the `isDefault` edge to carry NO criteria at all: a gated junk edge would be
    /// data that lies about how it is taken, since US-020's fallback ignores an edge's gates.
    /// The stage-gated Digitama and Baby edges are unconditioned for the same reason.
    ///
    /// So: every EARNED edge in this line carries at least one condition, and every condition in
    /// the whole file carries a hint with visible text in it.
    func testEveryEarnedEdgeIsConditionedAndNoHintInTheFileIsBlank() throws {
        let child = try XCTUnwrap(Stage.child.ladderIndex)
        for node in graph.nodes where node.line == line && (node.stage.ladderIndex ?? -1) >= child {
            for edge in node.evolutions where !edge.isDefault {
                XCTAssertFalse(edge.conditions.isEmpty,
                               "\(node.id) -> \(edge.to) is earned but gated on energy alone")
            }
        }

        for node in graph.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    XCTAssertFalse(
                        condition.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(node.id) -> \(edge.to): a condition carries a blank hint")
                }
                if edge.isDefault {
                    XCTAssertEqual(edge.conditions, [],
                                   "\(node.id) -> \(edge.to): a junk fallback may not be gated")
                }
            }
        }
    }

    // MARK: - AC10: the validator is clean over the WHOLE file

    func testTheWholeGraphStillPassesTheValidator() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [],
                       errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC12: the orphans this story removed

    /// ZERO, and asserted rather than merely noted, because "this story removed no orphans" is the
    /// kind of claim a later reader would assume was a slip. US-046 seeded every playable name in
    /// the Version 5 section as a node, and US-061 gave the line its junk branches, so the whole
    /// section was already connected before US-137 — what was missing was four ARROWS the document
    /// draws, not any Digimon. The count stands at 757, the same figure US-136 left.
    ///
    /// This story added no node at all, which is a first for Phase E: US-133 added 10, US-134 13,
    /// US-135 3 and US-136 1.
    ///
    /// The claim is about THIS LINE, so it is stated as this line's node count. It was written as
    /// the whole file's count (115) until US-138 added a thirty-node tree of its own — a global
    /// total cannot say anything about what one story did once another story lands beside it.
    ///
    /// US-149 is the first story to add to this line since, and it is excluded by NAME rather than
    /// counted: Gazimon X hangs off Pagumon, its base form's own In-Training, and Leomon X is its
    /// Champion. Bumping the total to 22 would have quietly turned "US-137 added nothing" into
    /// "US-137 added nothing that US-149 did not", which is a different claim.
    func testTheStoryAddedNoNodesAndSoRemovedNoOrphans() throws {
        let laterSweeps: Set<String> = ["gazimon_x", "leomon_x", "gigadramon"]
        XCTAssertEqual(graph.nodes.filter { $0.line == line && !laterSweeps.contains($0.id) }.count,
                       20, "US-137 adds no node to the Version 5 line")

        // Every Champion this story wired was already connected in both directions beforehand.
        for id in ["devidramon", "tuskmon", "cyclomon"] {
            let champion = try node(id)
            XCTAssertFalse(champion.evolutions.isEmpty, "\(id) already had out-edges")
            XCTAssertGreaterThan(graph.parents(of: id).count, 1,
                                 "\(id) gained a parent it did not need to be reachable")
        }
    }
}
