import XCTest
@testable import DigiVPet

/// US-138: the Pendulum Color V1 Nature Spirits tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 1:
/// Nature Spirits (NSp)", line 96. Every test here reads the REAL `evolutions.json`.
///
/// This is the first Phase E tree with NO seed line behind it. US-133…US-137 each renamed a line
/// US-008/US-044/US-045/US-046 had already authored and filled in what the document drew; there was
/// nothing here at all, so the story authored thirty nodes — more than any earlier Phase E story
/// added, and twelve of them line-scoped aliases, because this tree shares twelve Digimon with the
/// Digital Monster Color trees and `line` is single-valued.
final class PendulumNatureSpiritsTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-nsp"

    private func node(_ id: String) throws -> EvolutionNode {
        try XCTUnwrap(graph.node(id: id), "\(id) is not a node in evolutions.json")
    }

    private func targets(of id: String) throws -> Set<String> {
        Set(try node(id).evolutions.map(\.to))
    }

    // MARK: - AC1/AC2: every playable name in the section is a node, on the right rung, in the line

    /// The tree as the document writes it. `Fresh` is Baby I, `In-Training` is Baby II, `Rookie` is
    /// Child, `Champion` is Adult, the document's `Ultimate` is Perfect and its `Mega` is this
    /// app's `Ultimate-Super Ultimate`.
    ///
    /// Betamon is the one Rookie missing and it is missing on purpose — see
    /// `testTheOneAbsentNameIsBetamonAndItsChampionsWereRehomed`. Omegamon is the Jogress half of
    /// the WarGreymon row and is a recipe rather than an edge.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("pencnsp_botamon", .babyI),
        ("pencnsp_koromon", .babyII),
        ("pencnsp_agumon", .child),
        ("tentomon", .child),
        ("angoramon", .child),
        ("pencnsp_greymon", .adult),
        ("pencnsp_leomon", .adult),
        ("pencnsp_seadramon", .adult),
        ("tailmon", .adult),
        ("pencnsp_kabuterimon", .adult),
        ("pencnsp_garurumon", .adult),
        ("symbareangoramon", .adult),
        ("pencnsp_metalgreymon", .perfect),
        ("asuramon", .perfect),
        ("megaseadramon", .perfect),
        ("angewomon", .perfect),
        ("atlurkabuterimon_blue", .perfect),
        ("pencnsp_weregarurumon", .perfect),
        ("lamortmon", .perfect),
        ("pencnsp_wargreymon", .ultimate),
        ("saberleomon", .ultimate),
        ("metalseadramon", .ultimate),
        ("holydramon", .ultimate),
        ("heraklekabuterimon", .ultimate),
        ("pencnsp_metalgarurumon", .ultimate),
        ("diarbbitmon", .ultimate),
    ]

    func testEveryPlayableNameInTheSectionIsANodeOnTheCorrectStageInTheNatureSpiritsLine() throws {
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Nature Spirits tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// Every name in the section, looked up in the ROSTER by display name — which is the check that
    /// would catch a node authored on art that exists under a different spelling.
    func testEveryNameInTheSectionResolvesToAPlayableRosterEntry() throws {
        let displayNames = ["Botamon", "Koromon", "Agumon", "Tentomon", "Angoramon", "Greymon",
                            "Leomon", "Seadramon", "Tailmon", "Kabuterimon", "Garurumon",
                            "SymbareAngoramon", "MetalGreymon", "Asuramon", "MegaSeadramon",
                            "Angewomon", "WereGarurumon", "Lamortmon", "WarGreymon", "SaberLeomon",
                            "MetalSeadramon", "Holydramon", "HerakleKabuterimon", "MetalGarurumon",
                            "Diarbbitmon"]

        for name in displayNames {
            let entry = Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly }
            XCTAssertNotNil(entry, "\(name) has no playable roster entry, so it cannot be wired")
        }

        // AtlurKabuterimon is the one whose roster entry carries the variant in its display name.
        let atlur = try XCTUnwrap(Roster.bundled.entry(id: "atlurkabuterimon_blue"))
        XCTAssertEqual(atlur.displayName, "AtlurKabuterimon Blue")
        XCTAssertEqual(atlur.variant, "Blue")
        XCTAssertEqual(try node("atlurkabuterimon_blue").displayName, "AtlurKabuterimon",
                       "a variant keeps the base display name — the metalgreymon_virus pattern")
    }

    /// AC11: the section's absent names, each searched for with `find -iname` over the whole asset
    /// pack before it was called absent.
    ///
    /// - **Betamon** — `16x16 Digimon Sprites/Idle Frame Only/Betamon.png` and nothing else (the
    ///   only other hit is the unrelated `ModokiBetamon.png`). There is no 48x64 sheet under
    ///   `Child/`, so Betamon is one of the 157 `dexOnly` Digimon and may never sit on an edge. It
    ///   is the document's SECOND Rookie, so this is the costliest absence Phase E has hit: its two
    ///   Champions had to be rehomed rather than merely dropped, or Seadramon, Tailmon and the four
    ///   Digimon above them would have been unreachable.
    ///
    /// That is the section's only absent name. Every other one is playable, and the two names that
    /// LOOK absent are not: "Crabmon (Ganimon)" belongs to the Version 2 section, and Omegamon is
    /// a Jogress result rather than a missing sheet.
    func testTheOneAbsentNameIsBetamonAndItsChampionsWereRehomed() throws {
        let betamon = try XCTUnwrap(Roster.bundled.entry(id: "betamon"))
        XCTAssertTrue(betamon.dexOnly, "Betamon became playable — its Champions can go home")
        XCTAssertNil(graph.node(id: "betamon"), "a dexOnly Digimon may not be a node")
        XCTAssertNil(graph.nodes.first { $0.spriteFile == "Betamon" })

        // Its two Champions live on, under the Rookies that took them in.
        XCTAssertTrue(try targets(of: "pencnsp_agumon").contains("pencnsp_seadramon"))
        XCTAssertTrue(try targets(of: "angoramon").contains("tailmon"))
        XCTAssertEqual(graph.parents(of: "pencnsp_seadramon").map(\.id), ["pencnsp_agumon"])
        XCTAssertEqual(graph.parents(of: "tailmon").map(\.id), ["angoramon"])
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        // Fresh -> In-Training -> the Rookies.
        XCTAssertTrue(try targets(of: "tento_digitama").contains("pencnsp_botamon"))
        XCTAssertTrue(try targets(of: "pencnsp_botamon").contains("pencnsp_koromon"))
        for rookie in ["pencnsp_agumon", "tentomon", "angoramon"] {
            XCTAssertTrue(try targets(of: "pencnsp_koromon").contains(rookie),
                          "Koromon does not reach \(rookie)")
        }

        // Rookie -> Champion, as the document draws them (Seadramon and Tailmon rehomed).
        XCTAssertTrue(try targets(of: "pencnsp_agumon").isSuperset(of: ["pencnsp_greymon",
                                                                       "pencnsp_leomon"]))
        XCTAssertTrue(try targets(of: "tentomon").isSuperset(of: ["pencnsp_kabuterimon",
                                                                  "pencnsp_garurumon"]))
        XCTAssertTrue(try targets(of: "angoramon").contains("symbareangoramon"))

        // Champion -> Ultimate -> Mega, every thread the document draws.
        let threads = [("pencnsp_greymon", "pencnsp_metalgreymon", "pencnsp_wargreymon"),
                       ("pencnsp_leomon", "asuramon", "saberleomon"),
                       ("pencnsp_seadramon", "megaseadramon", "metalseadramon"),
                       ("tailmon", "angewomon", "holydramon"),
                       ("pencnsp_kabuterimon", "atlurkabuterimon_blue", "heraklekabuterimon"),
                       ("pencnsp_garurumon", "pencnsp_weregarurumon", "pencnsp_metalgarurumon"),
                       ("symbareangoramon", "lamortmon", "diarbbitmon")]

        for (champion, perfect, mega) in threads {
            XCTAssertTrue(try targets(of: champion).contains(perfect),
                          "\(champion) must reach \(perfect)")
            XCTAssertTrue(try targets(of: perfect).contains(mega), "\(perfect) must reach \(mega)")
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is the top of its thread")
        }
    }

    /// The document's WarGreymon row reads "Mega: WarGreymon / Omegamon (Jogress)". Omegamon is a
    /// recipe, not an edge — the treatment every other tree's Jogress row got — and this was the
    /// first tree to hold BOTH of that recipe's parents, so the row is satisfiable inside one line.
    /// US-143's Virus Busters / ZERO is the second and the recipe's real home: the V0 document
    /// draws "Ultra: Omegamon (Jogress)" on its Agumon thread AND on its Gabumon one.
    func testTheOmegamonHalfOfTheRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertNil(graph.node(id: "omegamon"), "Omegamon is a Jogress result, not a node here")
        XCTAssertTrue(try node("pencnsp_wargreymon").evolutions.isEmpty)

        XCTAssertNotNil(JogressCatalog.bundled.recipe(for: "wargreymon", and: "metalgarurumon"),
                        "the Nature Spirits Mega row has no recipe in jogress.json")
        // The recipe is authored against the ROSTER ids, which is why the line-scoped copies here
        // do not need one of their own.
        XCTAssertNotNil(Roster.bundled.entry(id: "omegamon"))
        XCTAssertEqual(try node("pencnsp_wargreymon").spriteFile,
                       Roster.bundled.entry(id: "wargreymon")?.spriteFile)
    }

    // MARK: - AC4: reachable from a Digitama, end to end

    /// The egg is a real ROSTER Digitama rather than a line-scoped one, and that is a playability
    /// requirement rather than taste: `maps.json` grants a Digitama by roster id, an alias has no
    /// roster entry, and a line whose egg can never drop is a line no player can start.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("tento_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let slots = MapCatalog.bundled.maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        XCTAssertTrue(slots.contains(egg.id), "no map drops \(egg.id), so the line is unstartable")

        // One egg per line until US-144, which hangs `angora_digitama` off this line rather than opening a
        // one-node line for a species this tree already reaches. The line's OWN egg is still the
        // first of them, and still the one the rest of this file reasons about.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "angora_digitama"])
    }

    /// Since US-144 the seed is every Digitama of the line, not just this tree's own: the first
    /// orphan sweep gives a line a second egg where the species it belongs to is already wired
    /// here. What the test still means is unchanged — nothing in the line is stranded above the
    /// eggs — and `testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant` is what pins
    /// which eggs those are.
    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains("tento_digitama"), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        // US-150 hung YukiAgumon and its Champion Hyougamon on this line's Koromon, which is why
        // the line is two larger than the tree the document draws.
        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 41,
                       "US-157 hung AtlurKabuterimon Red on this line, US-158 DarkKnightmon over "
                           + "Tailmon and DarkKnightmon X over that, US-160 MegaSeadramon X over "
                           + "the leaf Hyougamon")
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The twelve line-scoped aliases

    /// Twelve of this tree's thirty Digimon already had a node in another line, so twelve are
    /// line-scoped: the piyo_yuramon pattern at four times the previous largest scale (US-134's
    /// two). Each is asserted to be the SAME Digimon — same art, same display name — under a
    /// second id, because the failure this guards against is an alias silently pointing at a
    /// different sheet from the Digimon it stands in for.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencnsp_botamon", "botamon", "dmc-v1"),
            ("pencnsp_koromon", "koromon", "dmc-v1"),
            ("pencnsp_agumon", "agumon", "dmc-v1"),
            ("pencnsp_greymon", "greymon", "dmc-v1"),
            ("pencnsp_metalgreymon", "metalgreymon", "dmc-v1"),
            ("pencnsp_wargreymon", "wargreymon", "dmc-v1"),
            ("pencnsp_seadramon", "seadramon", "dmc-v1"),
            ("pencnsp_leomon", "leomon", "dmc-v4"),
            ("pencnsp_kabuterimon", "kabuterimon", "dmc-v2"),
            ("pencnsp_garurumon", "garurumon", "dmc-v2"),
            ("pencnsp_weregarurumon", "weregarurumon", "dmc-v2"),
            ("pencnsp_metalgarurumon", "metalgarurumon", "dmc-v2"),
        ]

        for (scoped, plain, owner) in aliases {
            let a = try node(scoped)
            let b = try node(plain)
            XCTAssertEqual(a.line, line, "\(scoped) belongs to this tree")
            XCTAssertEqual(b.line, owner, "\(plain) belongs to \(owner)")
            XCTAssertEqual(a.displayName, b.displayName, "\(scoped) is a different Digimon")
            XCTAssertEqual(a.spriteFile, b.spriteFile, "\(scoped) draws different art")
            XCTAssertEqual(a.stage, b.stage, "\(scoped) sits on a different rung")
            XCTAssertNil(Roster.bundled.entry(id: scoped), "an alias has no roster entry of its own")
        }

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencnsp_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")
    }

    /// Every one of the twelve needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases. Pinned because "the node exists" is the half a reader checks and
    /// the other two are the half that fails the suite.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencnsp_") {
            let plain = String(node.id.dropFirst("pencnsp_".count))
            XCTAssertNotNil(ElementCatalog.bundled.types[node.id], "\(node.id) has no element")

            let mine = try XCTUnwrap(MoveCatalog.bundled.moves[node.id], "\(node.id) has no move")
            let theirs = try XCTUnwrap(MoveCatalog.bundled.moves[plain])
            XCTAssertNotEqual(mine.signatureName, theirs.signatureName,
                              "\(node.id) reuses \(plain)'s signature, which must be unique")
        }
    }

    // MARK: - The junk chain, which this document does not supply

    /// The five Digital Monster Color trees each name their own junk Champion — Numemon, Vegimon,
    /// Scumon, Nanimon, Raremon. The Pendulum Color V1 section names NONE: it draws only the earned
    /// tree. Every Child and Adult in this app nonetheless needs an `isDefault` edge reachable by
    /// doing nothing, so US-138 chose a chain rather than borrowing one, and chose it off sheets
    /// that were orphans: PlatinumScumon -> Pumpmon -> NoblePumpmon.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("platinumscumon").stage, .adult)
        XCTAssertEqual(try node("pumpmon").stage, .perfect)
        XCTAssertEqual(try node("noblepumpmon").stage, .ultimate)

        for id in ["platinumscumon", "pumpmon", "noblepumpmon"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("platinumscumon").evolutions.first(where: \.isDefault)?.to, "pumpmon")
        XCTAssertEqual(try node("pumpmon").evolutions.first(where: \.isDefault)?.to, "noblepumpmon")

        // The section really is silent — none of the three is named anywhere in the tree markdown.
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Digimon_Color_And_Pendulum_Color_Evolution_Trees", withExtension: "md"))
        let document = try String(contentsOf: url, encoding: .utf8)
        for name in ["PlatinumScumon", "Pumpmon", "NoblePumpmon"] {
            XCTAssertFalse(document.contains(name), "\(name) IS in the document after all")
        }
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesPlatinumScumon() throws {
        for rookie in ["pencnsp_agumon", "tentomon", "angoramon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "platinumscumon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The other half: a well-raised Digimon reaches each branch its Rookie offers. Distinct
    /// energies prove the branches are TELLABLE apart; this proves the engine routes to each.
    func testEachRookiesEarnedBranchesAreAllReachable() throws {
        let met = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                               "health.standHours": 1_000,
                                               "health.exerciseMinutes": 5_000,
                                               "health.activeEnergy": 50_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 30)

        let rows: [(String, [(EnergyType, String)])] = [
            ("pencnsp_agumon", [(.strength, "pencnsp_greymon"), (.stamina, "pencnsp_leomon"),
                                (.vitality, "pencnsp_seadramon")]),
            ("tentomon", [(.stamina, "pencnsp_kabuterimon"), (.strength, "pencnsp_garurumon")]),
            ("angoramon", [(.spirit, "symbareangoramon"), (.vitality, "tailmon")]),
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

    /// The document marks Angoramon "Rookie (Unlockable Slot 6)". That is why its edge out of
    /// Koromon is the only conditioned In-Training edge in this tree — an In-Training rung is
    /// otherwise gated on dominant energy alone.
    ///
    /// SCOPED TO THE EDGES THE TREE DRAWS, and it had to be: US-150 hung YukiAgumon off this same
    /// Koromon, and a sweep's earned branch is conditioned by its own acceptance criteria. Scoping
    /// keeps the claim the document actually makes — of the three Rookies THIS SECTION draws, only
    /// the unlockable one is earned — rather than relaxing it into "some edge is unconditioned".
    func testTheUnlockableSixthSlotIsTheOnlyEarnedInTrainingEdge() throws {
        let koromon = try node("pencnsp_koromon")
        let drawnBySection: Set<String> = ["pencnsp_agumon", "tentomon", "angoramon"]
        for edge in koromon.evolutions where drawnBySection.contains(edge.to) {
            XCTAssertEqual(!edge.conditions.isEmpty, edge.to == "angoramon",
                           "\(edge.to) is conditioned out of step with the unlockable slot")
        }
        XCTAssertEqual(Set(koromon.evolutions.map(\.to)).subtracting(drawnBySection),
                       ["yukiagumon"], "a fourth Rookie was hung here without saying so")
        XCTAssertFalse(try XCTUnwrap(koromon.evolutions.first { $0.to == "angoramon" }).isDefault)
    }

    // MARK: - The line stays self-contained

    /// No edge leaves the line and none reaches in. `EvolutionTreeLayout` silently drops a connector
    /// whose target is outside the laid-out set, so either direction would draw an arrow to nothing —
    /// and with twelve shared Digimon this is the tree where getting it wrong is easiest.
    func testNoEdgeCrossesTheLineBoundaryInEitherDirection() throws {
        for node in graph.nodes {
            for edge in node.evolutions {
                let target = try XCTUnwrap(graph.node(id: edge.to))
                XCTAssertEqual(node.line == line, target.line == line,
                               "\(node.id) -> \(edge.to) crosses into or out of '\(line)'")
            }
        }
    }

    // MARK: - AC5/AC6: the choices are recorded in the data file, the sprites are real

    func testEveryDivergenceIsRecordedInTheDataFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        XCTAssertTrue(try comment(on: "tento_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "pencnsp_agumon").contains("Betamon"),
                      "the rehomed Seadramon must name the Rookie it came from")
        XCTAssertTrue(try comment(on: "angoramon").contains("Betamon"),
                      "the rehomed Tailmon must name the Rookie it came from")
        XCTAssertTrue(try comment(on: "platinumscumon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")
        XCTAssertTrue(try comment(on: "atlurkabuterimon_blue").contains("Wikimon"),
                      "the Blue/Red choice must name the reference it was sourced from")
        XCTAssertTrue(try comment(on: "pencnsp_wargreymon").contains("jogress.json"),
                      "the Jogress half of the Mega row must say where it went")
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg).
    func testEveryNodeInTheLineHasAnAnimatedSheet() throws {
        for node in graph.nodes where node.line == line {
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(node.id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, node.stage == .digitama ? .egg : .stage, node.id)
        }
    }

    // MARK: - AC7/AC8/AC9/AC10

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

    func testEveryNodeInTheFileCarriesALine() {
        for node in graph.nodes {
            XCTAssertFalse(node.line.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(node.id) has no line")
        }
    }

    /// AC9, read the only way it can be true of this file — the reading every Phase E story has
    /// taken. The literal "every edge carries a condition" is contradicted by a rule that predates
    /// this story, `EvolutionCriteriaTests.testEveryJunkFallbackIsReachableByInaction`, which
    /// requires the `isDefault` edge to carry NO criteria: US-020's fallback ignores an edge's
    /// gates, so a gated junk edge would be data that lies about how it is taken.
    ///
    /// The three claims that ARE true: every earned edge at Child and Adult is conditioned, every
    /// condition in the whole file has a hint with visible text, and every junk edge is
    /// unconditioned.
    func testEveryEarnedBranchIsConditionedAndNoHintInTheFileIsBlank() throws {
        for node in graph.nodes where node.line == line && (node.stage == .child || node.stage == .adult) {
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
                if edge.isDefault && (node.stage == .child || node.stage == .adult) {
                    XCTAssertEqual(edge.conditions, [],
                                   "\(node.id) -> \(edge.to): a junk fallback may not be gated")
                }
            }
        }
    }

    func testTheWholeGraphStillPassesTheValidator() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [],
                       errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC12: the orphans this story removed

    /// EIGHTEEN, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 757 before, 739 after. Asserted rather than merely noted, because the count is the one claim
    /// in `notes` a later reader cannot re-derive from the diff.
    ///
    /// Eighteen of the thirty new nodes carry a plain roster id and so remove an orphan; the other
    /// twelve are line-scoped aliases of Digimon that were already wired, and an alias removes
    /// nothing — the roster entry it shares was never orphaned.
    func testTheEighteenOrphansThisStoryRemovedAreTheEighteenNodesWithRosterIds() throws {
        let removed = ["tento_digitama", "tentomon", "angoramon", "tailmon", "symbareangoramon",
                       "platinumscumon", "asuramon", "megaseadramon", "angewomon",
                       "atlurkabuterimon_blue", "lamortmon", "pumpmon", "saberleomon",
                       "metalseadramon", "holydramon", "heraklekabuterimon", "diarbbitmon",
                       "noblepumpmon"]
        XCTAssertEqual(removed.count, 18)

        for id in removed {
            let node = try self.node(id)
            XCTAssertEqual(node.line, line)
            XCTAssertNotNil(Roster.bundled.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(node.evolutions.isEmpty && graph.parents(of: id).isEmpty,
                           "\(id) is still an orphan")
        }

        // Counted over THIS LINE, never over the file: the global total was 145 when US-138 landed
        // and US-139 moved it to 176 without touching a node here. A whole-file count cannot say
        // anything about what one story did once another tree lands beside it.
        // `angora_digitama` is US-144's, not this story's, so it is excluded rather than counted.
        // `yukiagumon` and `hyougamon` are US-150's, excluded the same way.
        // `atlurkabuterimon_red` is US-157's, excluded the same way, and `darkknightmon` /
        // `darkknightmon_x` are US-158's.
        // US-161's two Panjyamon are excluded the same way — both hung off this line's own Leomon,
        // one climbing the Holydramon this tree already carried and one the SaberLeomon.
        let notThisStorys: Set<String> = ["angora_digitama", "yukiagumon", "hyougamon",
                                          "atlurkabuterimon_red", "darkknightmon",
                                          "darkknightmon_x", "megaseadramon_x",
                                          "panjyamon", "panjyamon_x",
                                          // US-163's one: AncientBeatmon over the AtlurKabuterimon
                                          // (Red) US-157 hung beside this tree's own beetle.
                                          "ancientbeatmon",
                                          // US-164's one: DarknessBagramon over the DarkKnightmon
                                          // US-158 hung on Tailmon.
                                          "darknessbagramon"]
        XCTAssertEqual(graph.nodes.filter { $0.line == line && !notThisStorys.contains($0.id) }.count,
                       30)
        XCTAssertEqual(graph.nodes.filter { $0.line == line && Roster.bundled.entry(id: $0.id) == nil }.count,
                       12, "the twelve aliases, which remove no orphan")
    }
}
