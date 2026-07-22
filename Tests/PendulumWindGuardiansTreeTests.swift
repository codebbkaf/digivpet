import XCTest
@testable import DigiVPet

/// US-141: the Pendulum Color V4 Wind Guardians tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 4:
/// Wind Guardians (WG)", line 138. Every test here reads the REAL `evolutions.json`.
///
/// The fourth Phase E tree with no seed line behind it, and the first whose Rookie rung is drawn
/// WHOLE — all four of the section's Rookies have animated sheets, including the unlockable
/// seventh slot, which is what brings back the conditioned In-Training edge US-140 had to drop.
///
/// Its two gaps are in the middle and at the top of threads rather than at the bottom. **Deramon**
/// (the Perfect over Kiwimon) and **Crossmon / Eaglemon** (the Mega over Garbagemon) have no art
/// anywhere in the pack, so Wikimon supplied a stand-in on the same thread in each case —
/// Blossomon and Rafflesimon. See `testTheThreeAbsentNamesAreAbsentFromTheWholeSpritePack`.
final class PendulumWindGuardiansTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-wg"

    private func node(_ id: String) throws -> EvolutionNode {
        try XCTUnwrap(graph.node(id: id), "\(id) is not a node in evolutions.json")
    }

    private func targets(of id: String) throws -> Set<String> {
        Set(try node(id).evolutions.map(\.to))
    }

    private func document() throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Digimon_Color_And_Pendulum_Color_Evolution_Trees", withExtension: "md"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - AC1/AC2: every playable name in the section is a node, on the right rung, in the line

    /// The tree as the document writes it, less the three names with no sheet. `Fresh` is Baby I,
    /// `In-Training` is Baby II, `Rookie` is Child, `Champion` is Adult, the document's `Ultimate`
    /// is Perfect and its `Mega` is this app's `Ultimate-Super Ultimate`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("nyokimon", .babyI),
        ("pyocomon", .babyII),
        ("pencwg_piyomon", .child),
        ("floramon", .child),
        ("mushmon", .child),
        ("pteromon", .child),
        ("pencwg_birdramon", .adult),
        ("v-dramon", .adult),
        ("pencwg_togemon", .adult),
        ("kiwimon", .adult),
        ("woodmon", .adult),
        ("redvegimon", .adult),
        ("galemon", .adult),
        ("garudamon", .perfect),
        ("aerov-dramon", .perfect),
        ("pencwg_lilimon", .perfect),
        ("jyureimon", .perfect),
        ("pencwg_gerbemon", .perfect),
        ("grandgalemon", .perfect),
        ("hououmon", .ultimate),
        ("ulforcev-dramon", .ultimate),
        ("pencwg_rosemon", .ultimate),
        ("griffomon", .ultimate),
        ("pinochimon", .ultimate),
        ("zephagamon", .ultimate),
    ]

    func testEveryNameInTheSectionIsANodeOnTheCorrectStageInTheWindGuardiansLine() throws {
        XCTAssertEqual(Self.sectionMembers.count, 25,
                       "the section draws twenty-eight Digimon, three of which have no sheet")
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Wind Guardians tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's other half. Eleven of the section's names are not the names the ART is filed under.
    /// The document disambiguates five of them itself, in brackets — Yokomon (Pyocomon), Biyomon
    /// (Piyomon), Cherrymon (Jureimon), Puppetmon (Pinocchimon) — and even those brackets are not
    /// always the spelling on disk: `Jureimon` is `Jyureimon` and `Pinocchimon` is `Pinochimon`.
    /// The other six it does not disambiguate at all, and every one of them returns NOTHING to a
    /// `find -iname` on the document's spelling: Mushroomon/Mushmon, Veedramon/V-dramon,
    /// AeroVeedramon/AeroV-dramon, UlforceVeedramon/UlforceV-dramon, Lillymon/Lilimon,
    /// Gryphonmon/Griffomon — plus RedVegiemon/RedVegimon and Garbagemon/Gerbemon.
    ///
    /// The asserted direction matters: it is not "this id exists" but "the document's spelling has
    /// no PLAYABLE roster entry of its own", which is the thing that would make the substitution
    /// wrong.
    func testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses() throws {
        // The document's spelling -> the id actually wired.
        let renamed = [("Yokomon", "pyocomon"), ("Biyomon", "pencwg_piyomon"),
                       ("Mushroomon", "mushmon"), ("Veedramon", "v-dramon"),
                       ("AeroVeedramon", "aerov-dramon"),
                       ("UlforceVeedramon", "ulforcev-dramon"),
                       ("Lillymon", "pencwg_lilimon"), ("Gryphonmon", "griffomon"),
                       ("RedVegiemon", "redvegimon"), ("Garbagemon", "pencwg_gerbemon"),
                       ("Cherrymon", "jyureimon"), ("Jureimon", "jyureimon"),
                       ("Puppetmon", "pinochimon"), ("Pinocchimon", "pinochimon")]

        for (documentName, wiredId) in renamed {
            let wired = try node(wiredId)
            XCTAssertFalse(wired.dexOnly, "\(wiredId) must be playable")
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == documentName
                                                        && !$0.dexOnly },
                         "\(documentName) is playable after all and should be wired under its own name")
            // Every one of them appears in the section under the name the wiring rejected.
            XCTAssertTrue(try document().contains(documentName),
                          "\(documentName) is not the document's spelling after all")
        }

        // Everything else in the section is wired under the document's own spelling.
        for name in ["Nyokimon", "Floramon", "Pteromon", "Birdramon", "Togemon", "Kiwimon",
                     "Woodmon", "Galemon", "Garudamon", "GrandGalemon", "Hououmon", "Rosemon",
                     "Zephagamon"] {
            XCTAssertNotNil(Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly },
                            "\(name) has no playable roster entry, so it cannot be wired")
        }
    }

    /// `Garbagemon` is the nastiest of the eleven, and the reason the check above asks about
    /// PLAYABILITY rather than existence: searching the roster by substring DOES find something —
    /// `garbamon` — and it is a different Digimon and idle-only. US-139 recorded this exact shape
    /// with Octomon/Octmon; taking the hit at face value would have wired a Digimon that cannot
    /// animate, and taking its absence at face value would have dropped the thread.
    func testTheGarbamonNearMissIsNotGarbagemon() throws {
        let garbamon = try XCTUnwrap(Roster.bundled.entry(id: "garbamon"))
        XCTAssertTrue(garbamon.dexOnly, "garbamon has a sheet after all")
        XCTAssertNil(graph.node(id: "garbamon"), "an idle-only Digimon may not be a node")

        let wired = try node("pencwg_gerbemon")
        XCTAssertEqual(wired.spriteFile, "Gerbemon")
        XCTAssertNotEqual(wired.displayName, garbamon.displayName)
    }

    /// AC11 proper. Three of the section's twenty-eight names have NO sheet anywhere in the pack:
    ///
    /// - **Deramon**, the Perfect over Kiwimon. `find -iname '*dera*'` over the whole pack returns
    ///   only Thunderballmon, and the roster holds no Deramon under any spelling.
    /// - **Crossmon** and **Eaglemon**, the two names the document gives the Mega over Garbagemon.
    ///   `find -iname '*cross*'` and `'*eagl*'` return nothing at all.
    ///
    /// Both threads survive because Wikimon named a stand-in that sits on the SAME thread — see
    /// `blossomon` and `rafflesimon`. That is US-140's Loogarmon move applied to a missing MIDDLE
    /// rung and a missing TOP rung rather than a missing bottom one.
    func testTheThreeAbsentNamesAreAbsentFromTheWholeSpritePack() throws {
        for absent in ["Deramon", "Crossmon", "Eaglemon"] {
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == absent },
                         "\(absent) IS in the roster after all and should be wired")
            XCTAssertNil(graph.node(id: absent.lowercased()))
        }

        // The document really does name all three, so this records a gap rather than inventing one.
        let text = try document()
        XCTAssertTrue(text.contains("Champion: Kiwimon -> Ultimate: Deramon -> Mega: Gryphonmon"))
        XCTAssertTrue(text.contains("Mega: Crossmon / Eaglemon"))

        // The rungs of those two threads that DO have sheets are all wired.
        for id in ["kiwimon", "griffomon", "redvegimon", "pencwg_gerbemon"] {
            XCTAssertEqual(try node(id).line, line)
        }
    }

    /// The two stand-ins, stated as the substitutions they are. Each is asserted to sit BETWEEN the
    /// two document rungs it joins, so a later reader can see at a glance that the thread the
    /// document draws is still the thread that is wired.
    func testTheTwoWikimonStandInsSitOnTheThreadsTheyStandInFor() throws {
        // Deramon's slot: Kiwimon -> Blossomon -> Griffomon.
        XCTAssertEqual(try node("blossomon").stage, .perfect)
        XCTAssertTrue(try targets(of: "kiwimon").contains("blossomon"))
        XCTAssertTrue(try targets(of: "blossomon").contains("griffomon"))

        // Crossmon's slot: RedVegimon -> Gerbemon -> Rafflesimon.
        XCTAssertEqual(try node("rafflesimon").stage, .ultimate)
        XCTAssertTrue(try targets(of: "pencwg_gerbemon").contains("rafflesimon"))
        XCTAssertTrue(try node("rafflesimon").evolutions.isEmpty)

        // Neither is a name the document uses anywhere, in this section or a later one.
        let text = try document()
        for name in ["Blossomon", "Rafflesimon"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the document after all")
        }
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        XCTAssertTrue(try targets(of: "flora_digitama").contains("nyokimon"))
        XCTAssertTrue(try targets(of: "nyokimon").contains("pyocomon"))
        for rookie in ["pencwg_piyomon", "floramon", "mushmon", "pteromon"] {
            XCTAssertTrue(try targets(of: "pyocomon").contains(rookie),
                          "Pyocomon does not reach \(rookie)")
        }

        // Rookie -> Champion, exactly as the document draws them.
        XCTAssertTrue(try targets(of: "pencwg_piyomon")
            .isSuperset(of: ["pencwg_birdramon", "v-dramon"]))
        XCTAssertTrue(try targets(of: "floramon").isSuperset(of: ["pencwg_togemon", "kiwimon"]))
        XCTAssertTrue(try targets(of: "mushmon").isSuperset(of: ["woodmon", "redvegimon"]))
        XCTAssertTrue(try targets(of: "pteromon").contains("galemon"))

        // Champion -> Ultimate -> Mega, every thread the document draws. Two of the eight carry a
        // Wikimon stand-in for a rung with no art (see the test above); the arrows are the
        // document's either way.
        let threads = [("pencwg_birdramon", "garudamon", "hououmon"),
                       ("v-dramon", "aerov-dramon", "ulforcev-dramon"),
                       ("pencwg_togemon", "pencwg_lilimon", "pencwg_rosemon"),
                       ("kiwimon", "blossomon", "griffomon"),
                       ("woodmon", "jyureimon", "pinochimon"),
                       ("redvegimon", "pencwg_gerbemon", "rafflesimon"),
                       ("galemon", "grandgalemon", "zephagamon")]

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
    ///
    /// It is also the first Pendulum egg that is NOT the default Rookie's own. Pyocomon falls to
    /// Piyomon, but `piyo_digitama` went to `dmc-v4` in US-136 — the Digital Monster Ver.4 tree is
    /// Piyomon's too — and one egg cannot root two lines.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("flora_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let slots = MapCatalog.bundled.maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        XCTAssertTrue(slots.contains(egg.id), "no map drops \(egg.id), so the line is unstartable")

        // One egg per line until US-145, which hangs `mush_digitama` off this line rather than
        // opening a one-node line: Mushmon is already a Child here and Wikimon draws it from
        // Nyokimon, this line's Baby I. The line's OWN egg is still the first of them.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "mush_digitama"])

        // The egg this line could NOT have: it belongs to the other Piyomon tree.
        XCTAssertEqual(try node("piyo_digitama").line, "dmc-v4")
    }

    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        // Seeded from EVERY egg of the line rather than from Flora's alone: since US-144 a line may
        // carry several, and US-145's `mush_digitama` is a second root of this one.
        var reached = Set(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id))
        var frontier = Array(reached)
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 45,
                       "US-151 hung Akatorimon on Floramon, US-153 Kougamon on Mushmon, "
                           + "US-154 RedV-dramon on Piyomon, US-156 V-dramon Black on Piyomon "
                           + "and XV-mon Black on Mushmon, US-158 Delumon on Kiwimon and "
                           + "Garudamon X on Birdramon")
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The six line-scoped aliases

    /// Six of this tree's thirty-one Digimon already had a node in another line, so six are
    /// line-scoped: the piyo_yuramon pattern. Each is asserted to be the SAME Digimon — same art,
    /// same display name, same rung — under a second id, because the failure this guards against is
    /// an alias silently pointing at a different sheet from the Digimon it stands in for.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencwg_piyomon", "piyomon", "dmc-v4"),
            ("pencwg_birdramon", "birdramon", "dmc-v2"),
            ("pencwg_togemon", "togemon", "palmon"),
            ("pencwg_lilimon", "lilimon", "palmon"),
            ("pencwg_rosemon", "rosemon", "palmon"),
            ("pencwg_gerbemon", "gerbemon", "dmc-v2"),
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

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencwg_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")
    }

    /// Three of the six are the first whole THREE-RUNG THREAD to be scoped: the V4 Pendulum draws
    /// Togemon -> Lillymon -> Rosemon over Floramon, and all three have belonged to the `palmon`
    /// line since US-008. Stated as a count so a third copy of any of them cannot slip in unnoticed.
    func testThePalmonThreadIsScopedAllThreeRungsDeep() throws {
        for plain in ["togemon", "lilimon", "rosemon"] {
            let name = try node(plain).displayName
            let copies = graph.nodes.filter { $0.displayName == name }
            XCTAssertEqual(Set(copies.map(\.line)), ["palmon", line],
                           "\(plain) is drawn by exactly two trees")
            XCTAssertEqual(copies.count, 2, "\(plain) has a third copy")
        }
    }

    /// Every one of the six needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencwg_") {
            let plain = String(node.id.dropFirst("pencwg_".count))
            XCTAssertNotNil(ElementCatalog.bundled.types[node.id], "\(node.id) has no element")

            let mine = try XCTUnwrap(MoveCatalog.bundled.moves[node.id], "\(node.id) has no move")
            let theirs = try XCTUnwrap(MoveCatalog.bundled.moves[plain])
            XCTAssertNotEqual(mine.signatureName, theirs.signatureName,
                              "\(node.id) reuses \(plain)'s signature, which must be unique")
        }
    }

    /// `pencwg_gerbemon` is this tree's Pumpmon case, the second in the file: the SAME Digimon is
    /// the Digital Monster Ver.2 tree's junk Perfect and this tree's earned branch above
    /// RedVegimon. One node could not be both, because `EvolutionCriteriaTests` requires `gerbemon`
    /// to be a junk target and this story requires it to be gated behind two conditions.
    func testGerbemonIsJunkInVersionTwoAndEarnedHere() throws {
        XCTAssertEqual(try node("gerbemon").line, "dmc-v2")
        let junkEdges = graph.nodes.filter { $0.line == "dmc-v2" && $0.stage == .adult }
            .compactMap { node in node.evolutions.first { $0.to == "gerbemon" && $0.isDefault } }
        XCTAssertFalse(junkEdges.isEmpty, "Version 2 reaches Gerbemon by neglect")

        let earnedEdge = try XCTUnwrap(
            try node("redvegimon").evolutions.first { $0.to == "pencwg_gerbemon" })
        XCTAssertFalse(earnedEdge.isDefault, "Wind Guardians must EARN its Garbagemon")
        XCTAssertFalse(earnedEdge.conditions.isEmpty)
    }

    // MARK: - The junk chain, which this document does not supply

    /// The five Digital Monster Color trees each name their own junk Champion. The Pendulum Color
    /// sections name NONE: they draw only the earned tree. Every Child and Adult in this app
    /// nonetheless needs an `isDefault` edge reachable by doing nothing, so US-141 chose a chain off
    /// sheets that were orphans, the way US-138, US-139 and US-140 did:
    /// Zassoumon -> TonosamaGekomon -> ElDoradimon.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("zassoumon").stage, .adult)
        XCTAssertEqual(try node("tonosamagekomon").stage, .perfect)
        XCTAssertEqual(try node("eldoradimon").stage, .ultimate)

        for id in ["zassoumon", "tonosamagekomon", "eldoradimon"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("zassoumon").evolutions.first(where: \.isDefault)?.to,
                       "tonosamagekomon")
        XCTAssertEqual(try node("tonosamagekomon").evolutions.first(where: \.isDefault)?.to,
                       "eldoradimon")

        // Every Rookie falls to the same Champion — that is what makes it the tree's junk branch.
        for rookie in ["pencwg_piyomon", "floramon", "mushmon", "pteromon"] {
            XCTAssertEqual(try node(rookie).evolutions.first(where: \.isDefault)?.to, "zassoumon")
        }
        // And every Champion falls to the same Perfect.
        for champion in graph.nodes.filter({ $0.line == line && $0.stage == .adult }) {
            XCTAssertEqual(champion.evolutions.first(where: \.isDefault)?.to, "tonosamagekomon",
                           "\(champion.id) does not fall to this tree's junk Perfect")
        }

        // The section really is silent — none of the three is named anywhere in the tree markdown,
        // which is the grep US-140's notes insist on writing BEFORE authoring rather than after.
        let text = try document()
        for name in ["Zassoumon", "TonosamaGekomon", "Tonosama", "ElDoradimon"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the document after all")
        }
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesZassoumon() throws {
        for rookie in ["pencwg_piyomon", "floramon", "mushmon", "pteromon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "zassoumon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The junk Champion keeps one way back UP, so a player who neglected a Rookie and then worked
    /// is not locked out of the tree — the same shape US-138 gave PlatinumScumon, US-139 gave
    /// Diginorimon and US-140 gave Gokimon. Here it is canon as well as convenient: Wikimon lists
    /// Blossomon as something Zassoumon really evolves into.
    func testTheJunkChampionKeepsOneEarnedWayBackIntoTheTree() throws {
        let earned = try node("zassoumon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["blossomon"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the way back must be earned, not free")

        // And that leaves Blossomon with two parents, the earned one and the way back.
        XCTAssertEqual(Set(graph.parents(of: "blossomon").map(\.id)), ["kiwimon", "zassoumon"])
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
                                               "health.flightsClimbed": 5_000,
                                               "health.distanceWalkingRunning": 500_000,
                                               "health.sleep": 100_000]),
            trainingSessionsThisStage: 30,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 30)

        let rows: [(String, [(EnergyType, String)])] = [
            ("pencwg_piyomon", [(.vitality, "pencwg_birdramon"), (.strength, "v-dramon")]),
            ("floramon", [(.spirit, "pencwg_togemon"), (.stamina, "kiwimon")]),
            ("mushmon", [(.vitality, "woodmon"), (.strength, "redvegimon")]),
            ("pteromon", [(.stamina, "galemon")]),
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

        // The In-Training rung forks four ways, which is the widest fork in the file.
        for (energy, expected) in [(EnergyType.vitality, "pencwg_piyomon"),
                                   (.spirit, "floramon"),
                                   (.strength, "mushmon"),
                                   (.stamina, "pteromon")] {
            var totals = EnergyTotals.zero
            totals[energy] = 150
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: try node("pyocomon"), stageEnergy: totals,
                                                dominant: energy, careMistakes: 0, battleWins: 0,
                                                conditions: met),
                expected, "a well-raised \(energy.rawValue) Pyocomon does not reach \(expected)")
        }
    }

    /// Each Rookie's earned branches need distinct dominant types, or one of them is unreachable —
    /// `EvolutionEngine` picks on the dominant energy first and two branches sharing one would make
    /// the second dead data. The same is true of the In-Training rung, which forks four ways here.
    func testEveryBranchingNodeInTheLineUsesDistinctEnergies() throws {
        for id in ["pyocomon", "pencwg_piyomon", "floramon", "mushmon", "pteromon"] {
            let earned = try node(id).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(id) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(id) offers two branches on the same energy")
        }
    }

    /// US-138's Angoramon and US-139's Jellymon were the document's "Rookie (Unlockable Slot 6)",
    /// and each got the tree's one conditioned In-Training edge. US-140's slot-6 Rookie had no
    /// sheet, so that shape lapsed for a story. It is back here: Pteromon IS drawn, so the
    /// `pyocomon -> pteromon` edge is the only one out of the In-Training rung that is gated on
    /// anything more than dominant energy.
    func testTheUnlockableSeventhSlotIsTheOnlyConditionedInTrainingEdge() throws {
        let pyocomon = try node("pyocomon")
        XCTAssertEqual(pyocomon.evolutions.count, 4, "one edge per Rookie the section draws")

        for edge in pyocomon.evolutions {
            XCTAssertNotNil(edge.requiredEnergy)
            if edge.to == "pteromon" {
                XCTAssertFalse(edge.conditions.isEmpty, "the unlockable slot must be unlocked")
                XCTAssertFalse(edge.isDefault)
            } else {
                XCTAssertTrue(edge.conditions.isEmpty,
                              "\(edge.to) is conditioned, but only slot 7 is unlockable")
            }
        }

        XCTAssertTrue(try document().contains("Rookie (Unlockable Slot 7): Pteromon"))
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

        XCTAssertTrue(try comment(on: "flora_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "flora_digitama").contains("US-136"),
                      "the egg must say which story spent the obvious choice")
        XCTAssertTrue(try comment(on: "zassoumon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")

        // The two stand-ins, each naming the reference it came from and the name it replaces.
        for (id, absent) in [("blossomon", "Deramon"), ("rafflesimon", "Crossmon")] {
            XCTAssertTrue(try comment(on: id).contains("Wikimon"),
                          "\(id) must name the reference it came from")
            XCTAssertTrue(try comment(on: id).contains(absent),
                          "\(id) must name the absent Digimon it stands in for")
        }

        // The renamings, each recorded on the node that carries the substitute spelling.
        XCTAssertTrue(try comment(on: "mushmon").contains("Mushroomon"))
        XCTAssertTrue(try comment(on: "v-dramon").contains("Veedramon"))
        XCTAssertTrue(try comment(on: "pencwg_lilimon").contains("Lillymon"))
        XCTAssertTrue(try comment(on: "griffomon").contains("Gryphonmon"))
        XCTAssertTrue(try comment(on: "jyureimon").contains("Cherrymon"))
        XCTAssertTrue(try comment(on: "pinochimon").contains("Pinocchimon"))
        XCTAssertTrue(try comment(on: "redvegimon").contains("RedVegiemon"))
        XCTAssertTrue(try comment(on: "pencwg_gerbemon").contains("garbamon"))
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg). Stronger than "the
    /// file exists": an idle-only 16x16 sprite fails here rather than shipping as a Digimon that
    /// cannot animate, which is exactly the trap Garbagemon/garbamon set.
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

    /// TWENTY-FIVE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 692 before, 667 after. Asserted rather than merely noted, because the count is the one claim
    /// in `notes` a later reader cannot re-derive from the diff.
    ///
    /// Twenty-five of the thirty-one new nodes carry a plain roster id and so remove an orphan; the
    /// other six are line-scoped aliases of Digimon that were already wired, and an alias removes
    /// nothing — the roster entry it shares was never orphaned. That is the best ratio of any
    /// Pendulum tree so far, and it is what the V4 section is: a tree that overlaps the Digital
    /// Monster ones in one thread and the `palmon` line in one more, and is otherwise its own.
    func testTheTwentyFiveOrphansThisStoryRemovedAreTheNodesWithRosterIds() throws {
        let removed = ["flora_digitama", "nyokimon", "pyocomon", "floramon", "mushmon", "pteromon",
                       "v-dramon", "kiwimon", "woodmon", "redvegimon", "galemon", "zassoumon",
                       "garudamon", "aerov-dramon", "blossomon", "jyureimon", "grandgalemon",
                       "tonosamagekomon", "hououmon", "ulforcev-dramon", "griffomon", "pinochimon",
                       "rafflesimon", "zephagamon", "eldoradimon"]
        XCTAssertEqual(removed.count, 25)

        for id in removed {
            let node = try self.node(id)
            XCTAssertEqual(node.line, line)
            XCTAssertNotNil(Roster.bundled.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(node.evolutions.isEmpty && graph.parents(of: id).isEmpty,
                           "\(id) is still an orphan")
        }

        // Excluded by NAME rather than by bumping the total, the way every other tree file does it:
        // `mush_digitama` is US-144's, `akatorimon` US-151's and `kougamon` US-153's, so the count
        // below stays the claim THIS story's notes made about its own nodes.
        let sweepEggs: Set<String> = ["mush_digitama", "akatorimon", "kougamon", "redv-dramon",
                                      "v-dramon_black", "xv-mon_black",
                                      // US-158's two, both on Perfects this tree already reached.
                                      "delumon", "garudamon_x",
                                      // US-161's one: Paildramon over this line's own XV-mon
                                      // Black, climbing the UlforceV-dramon it already carried.
                                      "paildramon",
                                      // US-162's two: both Yatagaramon, over this line's own
                                      // XV-mon Black and Birdramon, climbing the Hououmon and
                                      // Griffomon it already carried.
                                      "yatagaramon", "yatagaramon_2006",
                                      // US-164's one: Cernumon over this line's own Jyureimon,
                                      // one rung below the Pinochimon its page cites.
                                      "cernumon",
                                      // US-165's two: Hououmon X over this line's own Garudamon X
                                      // and Hydramon over its Blossomon.
                                      "hououmon_x", "hydramon"]
        XCTAssertEqual(graph.nodes.filter { $0.line == line && !sweepEggs.contains($0.id) }.count, 31,
                       "the thirty-one nodes this story authored")
        XCTAssertEqual(graph.nodes.filter { $0.line == line && Roster.bundled.entry(id: $0.id) == nil }.count,
                       6, "the six aliases, which remove no orphan")
    }
}
