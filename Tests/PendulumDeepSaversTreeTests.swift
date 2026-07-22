import XCTest
@testable import DigiVPet

/// US-139: the Pendulum Color V2 Deep Savers tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 2:
/// Deep Savers (DS)", line 110. Every test here reads the REAL `evolutions.json`.
///
/// The second Phase E tree with no seed line behind it, and the first with NO absent name: every
/// one of the twenty-seven Digimon the section draws has a playable 48x64 sheet. Four of them are
/// filed under a different romanization from the one the document uses (Pichimon/Pitchmon,
/// Bukamon/Pukamon, Syakomon/Shakomon, Dragomon/Dagomon) and two more have a dexOnly twin under the
/// document's spelling (Octomon/Octmon, MarineDevimon/MarinDevimon) — which is what
/// `testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses` exists to pin.
final class PendulumDeepSaversTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-ds"

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
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("pitchmon", .babyI),
        ("pukamon", .babyII),
        ("gomamon", .child),
        ("ganimon", .child),
        ("shakomon", .child),
        ("jellymon", .child),
        ("ikkakumon", .adult),
        ("rukamon", .adult),
        ("pencds_coelamon", .adult),
        ("gesomon", .adult),
        ("octmon", .adult),
        ("pencds_seadramon", .adult),
        ("teslajellymon", .adult),
        ("zudomon", .perfect),
        ("pencds_whamon", .perfect),
        ("pencds_megaseadramon", .perfect),
        ("marindevimon", .perfect),
        ("dagomon", .perfect),
        ("anomalocarimon", .perfect),
        ("thetismon", .perfect),
        ("vikemon", .ultimate),
        ("plesiomon", .ultimate),
        ("pencds_metalseadramon", .ultimate),
        ("leviamon", .ultimate),
        ("pukumon", .ultimate),
        ("aegisdramon", .ultimate),
        ("amphimon", .ultimate),
    ]

    func testEveryNameInTheSectionIsANodeOnTheCorrectStageInTheDeepSaversLine() throws {
        XCTAssertEqual(Self.sectionMembers.count, 27, "the section draws twenty-seven Digimon")
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Deep Savers tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11 read the way this section forces it to be read: there is no absent name here, but six
    /// of the document's names are not the names the ART is filed under, and four of those would
    /// have looked absent to a `find` on the document's spelling alone.
    ///
    /// Every one was searched for with `find -iname` over the whole pack before the substitute was
    /// accepted. Two shapes:
    ///
    /// - **Nothing at all under the document's spelling** — Pichimon, Bukamon, Syakomon and
    ///   Dragomon. `find -iname '*pichi*'`, `'*buka*'`, `'*syako*'` and `'*drago*'` (less the
    ///   Seadramon family) return NO files, while `Baby I/Pitchmon.png`, `Baby II/Pukamon.png`,
    ///   `Child/Shakomon.png` and `Perfect/Dagomon.png` are real 48x64 sheets of those same
    ///   Digimon under another romanization or dub name.
    /// - **A dexOnly twin under the document's spelling** — Octomon and MarineDevimon. Both names
    ///   ARE in the roster and both are idle-frame-only, so wiring the document's spelling would
    ///   have failed the validator's `edgeToDexOnlyNode`; `Adult/Octmon.png` and
    ///   `Perfect/MarinDevimon.png` are the animated sheets of the same two Digimon.
    ///
    /// This is what makes the tree complete. Taking the document's spellings at face value would
    /// have called four names absent and stranded Pukumon and Leviamon behind two dexOnly
    /// Champions — the Betamon problem of US-138, three times over.
    func testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses() throws {
        // The document's spelling -> the id actually wired.
        let renamed = [("Pichimon", "pitchmon"), ("Bukamon", "pukamon"), ("Syakomon", "shakomon"),
                       ("Dragomon", "dagomon"), ("Octomon", "octmon"),
                       ("MarineDevimon", "marindevimon")]

        for (documentName, wiredId) in renamed {
            let entry = try XCTUnwrap(Roster.bundled.entry(id: wiredId))
            XCTAssertFalse(entry.dexOnly, "\(wiredId) must be playable")
            XCTAssertEqual(try node(wiredId).spriteFile, entry.spriteFile)
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == documentName
                                                        && !$0.dexOnly },
                         "\(documentName) is playable after all and should be wired under its own name")
        }

        // The two twins really are in the roster and really are dexOnly — which is why the
        // document's spelling could not simply be used.
        XCTAssertEqual(Roster.bundled.entry(id: "octomon")?.dexOnly, true)
        XCTAssertEqual(Roster.bundled.entry(id: "marinedevimon")?.dexOnly, true)
        XCTAssertNil(graph.node(id: "octomon"))
        XCTAssertNil(graph.node(id: "marinedevimon"))

        // Everything else in the section is wired under the document's own spelling.
        for name in ["Gomamon", "Ganimon", "Jellymon", "Ikkakumon", "Rukamon", "Coelamon",
                     "Gesomon", "Seadramon", "TeslaJellymon", "Zudomon", "Whamon", "MegaSeadramon",
                     "Anomalocarimon", "Thetismon", "Vikemon", "Plesiomon", "MetalSeadramon",
                     "Leviamon", "Pukumon", "Aegisdramon", "Amphimon"] {
            XCTAssertNotNil(Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly },
                            "\(name) has no playable roster entry, so it cannot be wired")
        }
    }

    /// The document writes the second Rookie "Crabmon (Ganimon)" — it supplies both names itself,
    /// so this one needed no lookup at all.
    func testTheDocumentSuppliesBothOfCrabmonsNames() throws {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Digimon_Color_And_Pendulum_Color_Evolution_Trees", withExtension: "md"))
        let document = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(document.contains("Crabmon (Ganimon)"))
        XCTAssertEqual(try node("ganimon").displayName, "Ganimon")
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        XCTAssertTrue(try targets(of: "goma_digitama").contains("pitchmon"))
        XCTAssertTrue(try targets(of: "pitchmon").contains("pukamon"))
        for rookie in ["gomamon", "ganimon", "shakomon", "jellymon"] {
            XCTAssertTrue(try targets(of: "pukamon").contains(rookie),
                          "Pukamon does not reach \(rookie)")
        }

        // Rookie -> Champion, exactly as the document draws them. No rehoming was needed.
        XCTAssertTrue(try targets(of: "gomamon").isSuperset(of: ["ikkakumon", "rukamon"]))
        XCTAssertTrue(try targets(of: "ganimon").isSuperset(of: ["pencds_coelamon", "gesomon"]))
        XCTAssertTrue(try targets(of: "shakomon").isSuperset(of: ["octmon", "pencds_seadramon"]))
        XCTAssertTrue(try targets(of: "jellymon").contains("teslajellymon"))

        // Champion -> Ultimate -> Mega, every thread the document draws.
        let threads = [("ikkakumon", "zudomon", "vikemon"),
                       ("rukamon", "pencds_whamon", "plesiomon"),
                       ("pencds_coelamon", "pencds_megaseadramon", "pencds_metalseadramon"),
                       ("gesomon", "marindevimon", "leviamon"),
                       ("octmon", "dagomon", "pukumon"),
                       ("pencds_seadramon", "anomalocarimon", "aegisdramon"),
                       ("teslajellymon", "thetismon", "amphimon")]

        XCTAssertEqual(threads.count, 7, "the section draws seven Champion-to-Mega threads")
        for (champion, perfect, mega) in threads {
            XCTAssertTrue(try targets(of: champion).contains(perfect),
                          "\(champion) must reach \(perfect)")
            XCTAssertTrue(try targets(of: perfect).contains(mega), "\(perfect) must reach \(mega)")
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is the top of its thread")
        }
    }

    // MARK: - AC4: reachable from a Digitama, end to end

    /// The egg is a real ROSTER Digitama rather than a line-scoped one, and that is a playability
    /// requirement rather than taste: `maps.json` grants a Digitama by roster id, an alias has no
    /// roster entry, and a line whose egg can never drop is a line no player can start.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("goma_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let slots = MapCatalog.bundled.maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        XCTAssertTrue(slots.contains(egg.id), "no map drops \(egg.id), so the line is unstartable")

        // One egg per line until US-144, which hangs `beta_digitama` and `kame_digitama` off this line rather than opening a
        // one-node line for a species this tree already reaches. The line's OWN egg is still the
        // first of them, and still the one the rest of this file reasons about.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "beta_digitama", "kame_digitama"])
    }

    /// Since US-144 the seed is every Digitama of the line, not just this tree's own: the first
    /// orphan sweep gives a line a second egg where the species it belongs to is already wired
    /// here. What the test still means is unchanged — nothing in the line is stranded above the
    /// eggs — and `testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant` is what pins
    /// which eggs those are.
    ///
    /// US-146 puts ONE node beyond the eggs' reach, and it is listed rather than excused. Puyomon's
    /// own Baby II (Puyoyomon) is not in the sprite pack, and Pukamon is the only Baby II on disk
    /// that evolves into Jellymon the way Puyoyomon does — so Puyomon hangs here. It can never gain
    /// an in-edge whatever line it sits on: US-144 and US-145 spent all 57 Digitama, and
    /// `EggHatcher.hatchTarget` reads `evolutions.first`, so no egg has a second hatch to give.
    /// Pinned as a one-element list, not dropped from the check, so a SECOND stranded node fails.
    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains("goma_digitama"), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 36, "US-152 hung Ebidramon and Gawappamon on this line")
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, ["puyomon"],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The five line-scoped aliases

    /// Five of this tree's thirty-one Digimon already had a node in another line, so five are
    /// line-scoped: the piyo_yuramon pattern. Each is asserted to be the SAME Digimon — same art,
    /// same display name — under a second id, because the failure this guards against is an alias
    /// silently pointing at a different sheet from the Digimon it stands in for.
    ///
    /// Two of them are the first aliases in the file whose plain id belongs to another PENDULUM
    /// tree: US-138 gave MegaSeadramon and MetalSeadramon to Nature Spirits, and Deep Savers draws
    /// the same pair over Coelamon.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencds_coelamon", "coelamon", "dmc-v4"),
            ("pencds_seadramon", "seadramon", "dmc-v1"),
            ("pencds_whamon", "whamon", "dmc-v2"),
            ("pencds_megaseadramon", "megaseadramon", "penc-nsp"),
            ("pencds_metalseadramon", "metalseadramon", "penc-nsp"),
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

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencds_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")
    }

    /// Every one of the five needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencds_") {
            let plain = String(node.id.dropFirst("pencds_".count))
            XCTAssertNotNil(ElementCatalog.bundled.types[node.id], "\(node.id) has no element")

            let mine = try XCTUnwrap(MoveCatalog.bundled.moves[node.id], "\(node.id) has no move")
            let theirs = try XCTUnwrap(MoveCatalog.bundled.moves[plain])
            XCTAssertNotEqual(mine.signatureName, theirs.signatureName,
                              "\(node.id) reuses \(plain)'s signature, which must be unique")
        }
    }

    // MARK: - The junk chain, which this document does not supply

    /// The five Digital Monster Color trees each name their own junk Champion. The Pendulum Color
    /// sections name NONE: they draw only the earned tree. Every Child and Adult in this app
    /// nonetheless needs an `isDefault` edge reachable by doing nothing, so US-139 chose a chain
    /// off sheets that were orphans, the way US-138 did: Diginorimon -> Piranimon -> MetalPiranimon.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("diginorimon").stage, .adult)
        XCTAssertEqual(try node("piranimon").stage, .perfect)
        XCTAssertEqual(try node("metalpiranimon").stage, .ultimate)

        for id in ["diginorimon", "piranimon", "metalpiranimon"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("diginorimon").evolutions.first(where: \.isDefault)?.to, "piranimon")
        XCTAssertEqual(try node("piranimon").evolutions.first(where: \.isDefault)?.to,
                       "metalpiranimon")

        // Every Rookie falls to the same Champion — that is what makes it the tree's junk branch.
        for rookie in ["gomamon", "ganimon", "shakomon", "jellymon"] {
            XCTAssertEqual(try node(rookie).evolutions.first(where: \.isDefault)?.to, "diginorimon")
        }

        // The section really is silent — none of the three is named anywhere in the tree markdown.
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Digimon_Color_And_Pendulum_Color_Evolution_Trees", withExtension: "md"))
        let document = try String(contentsOf: url, encoding: .utf8)
        for name in ["Diginorimon", "Piranimon", "MetalPiranimon"] {
            XCTAssertFalse(document.contains(name), "\(name) IS in the document after all")
        }
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesDiginorimon() throws {
        for rookie in ["gomamon", "ganimon", "shakomon", "jellymon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "diginorimon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The junk Champion keeps one way back UP, so a player who neglected a Rookie and then worked
    /// is not locked out of the tree — the same shape US-138 gave PlatinumScumon.
    func testTheJunkChampionKeepsOneEarnedWayBackIntoTheTree() throws {
        let earned = try node("diginorimon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["zudomon"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the way back must be earned, not free")
        XCTAssertEqual(Set(graph.parents(of: "zudomon").map(\.id)), ["ikkakumon", "diginorimon"])
    }

    // MARK: - The branches are tellable apart, and every one is reachable

    /// The other half of a real choice: a well-raised Digimon reaches each branch its Rookie
    /// offers. Distinct energies prove the branches are TELLABLE apart; this proves the engine
    /// routes to each of them.
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
            ("gomamon", [(.strength, "ikkakumon"), (.vitality, "rukamon")]),
            ("ganimon", [(.stamina, "pencds_coelamon"), (.vitality, "gesomon")]),
            ("shakomon", [(.spirit, "octmon"), (.stamina, "pencds_seadramon")]),
            ("jellymon", [(.spirit, "teslajellymon")]),
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

    /// Each Rookie's earned branches need distinct dominant types, or one of them is unreachable —
    /// `EvolutionEngine` picks on the dominant energy first and two branches sharing one would make
    /// the second dead data.
    func testEveryRookiesEarnedBranchesUseDistinctEnergies() throws {
        for rookie in ["gomamon", "ganimon", "shakomon", "jellymon"] {
            let earned = try node(rookie).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(rookie) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(rookie) offers two branches on the same energy")
        }
    }

    /// The document marks Jellymon "Rookie (Unlockable Slot 6)". That is why its edge out of
    /// Pukamon is the only conditioned In-Training edge in this tree — an In-Training rung is
    /// otherwise gated on dominant energy alone.
    func testTheUnlockableSixthSlotIsTheOnlyEarnedInTrainingEdge() throws {
        let pukamon = try node("pukamon")
        XCTAssertEqual(pukamon.evolutions.count, 4, "one edge per Rookie the section draws")
        for edge in pukamon.evolutions {
            XCTAssertEqual(!edge.conditions.isEmpty, edge.to == "jellymon",
                           "\(edge.to) is conditioned out of step with the unlockable slot")
        }
        XCTAssertFalse(try XCTUnwrap(pukamon.evolutions.first { $0.to == "jellymon" }).isDefault)
    }

    // MARK: - The line stays self-contained

    /// No edge leaves the line and none reaches in. `EvolutionTreeLayout` silently drops a connector
    /// whose target is outside the laid-out set, so either direction would draw an arrow to nothing.
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

        XCTAssertTrue(try comment(on: "goma_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "diginorimon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")
        XCTAssertTrue(try comment(on: "dagomon").contains("Wikimon"),
                      "the Dragomon/Dagomon identification must name the reference it came from")

        // The four renamings, each recorded on the node that carries the substitute spelling.
        XCTAssertTrue(try comment(on: "pitchmon").contains("Pichimon"))
        XCTAssertTrue(try comment(on: "pukamon").contains("Bukamon"))
        XCTAssertTrue(try comment(on: "shakomon").contains("Syakomon"))
        XCTAssertTrue(try comment(on: "octmon").contains("dexOnly"))
        XCTAssertTrue(try comment(on: "marindevimon").contains("dexOnly"))
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg). Stronger than "the
    /// file exists": an idle-only 16x16 sprite fails here rather than shipping as a Digimon that
    /// cannot animate, which is exactly the trap the six respelled names set.
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

    /// TWENTY-SIX, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 739 before, 713 after. Asserted rather than merely noted, because the count is the one claim
    /// in `notes` a later reader cannot re-derive from the diff.
    ///
    /// Twenty-six of the thirty-one new nodes carry a plain roster id and so remove an orphan; the
    /// other five are line-scoped aliases of Digimon that were already wired, and an alias removes
    /// nothing — the roster entry it shares was never orphaned.
    func testTheTwentySixOrphansThisStoryRemovedAreTheNodesWithRosterIds() throws {
        let removed = ["goma_digitama", "pitchmon", "pukamon", "gomamon", "ganimon", "shakomon",
                       "jellymon", "ikkakumon", "rukamon", "gesomon", "octmon", "teslajellymon",
                       "diginorimon", "zudomon", "marindevimon", "dagomon", "anomalocarimon",
                       "thetismon", "piranimon", "vikemon", "plesiomon", "leviamon", "pukumon",
                       "aegisdramon", "amphimon", "metalpiranimon"]
        XCTAssertEqual(removed.count, 26)

        for id in removed {
            let node = try self.node(id)
            XCTAssertEqual(node.line, line)
            XCTAssertNotNil(Roster.bundled.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(node.evolutions.isEmpty && graph.parents(of: id).isEmpty,
                           "\(id) is still an orphan")
        }

        // `beta_digitama` and `kame_digitama` are US-144's and `puyomon` is US-146's, not this
        // story's, so they are excluded rather than counted — the totals here are what this
        // story's notes claimed. `ebidramon` and `gawappamon` are US-152's and excluded the
        // same way: the Adult E-G sweep hung both off this line's own Rookies.
        let sweepEggs: Set<String> = ["beta_digitama", "kame_digitama", "puyomon",
                                      "ebidramon", "gawappamon"]
        let mine = graph.nodes.filter { $0.line == line && !sweepEggs.contains($0.id) }
        XCTAssertEqual(mine.count, 31)
        XCTAssertEqual(mine.filter { Roster.bundled.entry(id: $0.id) == nil }.count,
                       5, "the five aliases, which remove no orphan")
    }

    /// This tree is the first Phase E line whose Baby I and Baby II are their OWN Digimon rather
    /// than a second copy of another tree's — Botamon and Koromon had to be aliased in US-138
    /// because dmc-v1 owned them. Pitchmon and Pukamon belong to nobody, so they are two of the
    /// twenty-six, and they are the first Baby rung Phase E has removed an orphan from at all.
    func testTheBabyRungsAreThisTreesOwnDigimonRatherThanAliases() throws {
        for id in ["pitchmon", "pukamon"] {
            XCTAssertNotNil(Roster.bundled.entry(id: id))
            // Pitchmon had exactly one parent until US-144 gave this line two more eggs. What the
            // claim needs is that every way IN is an egg of this line, not that there is one of them.
            for parent in graph.parents(of: id) {
                XCTAssertEqual(parent.line, line, "\(id) is fed from outside the line")
            }
        }
        XCTAssertTrue(graph.parents(of: "pitchmon").contains { $0.id == "goma_digitama" })
        // US-146 gave Pukamon a second parent: Puyomon, whose own Baby II is not in the sprite
        // pack and whose stand-in had to be the one Baby II that also evolves into Jellymon.
        XCTAssertEqual(graph.parents(of: "pukamon").map(\.id).sorted(), ["pitchmon", "puyomon"])
        XCTAssertEqual(try node("pitchmon").stage, .babyI)
        XCTAssertEqual(try node("pukamon").stage, .babyII)
    }
}
