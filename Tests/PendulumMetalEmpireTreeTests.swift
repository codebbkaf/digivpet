import XCTest
@testable import DigiVPet

/// US-142: the Pendulum Color V5 Metal Empire tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 5:
/// Metal Empire (ME)", line 152. Every test here reads the REAL `evolutions.json`.
///
/// The fifth Phase E tree with no seed line behind it, and the widest line in the file at 32 nodes.
/// Its one broken thread is the unlockable slot's, and it is broken at BOTH ends: **Machmon** has
/// no animated sheet (the roster holds it, `dexOnly`, so it can be in the Dex but never on an edge)
/// and **HeavyMetaldramon** does not exist in the pack at all. Wikimon supplied a stand-in on the
/// same thread for each — Minotaurmon below Rebellimon and Gundramon above it — so the arrows the
/// document draws survive. See `testTheTwoUndrawableNamesAreRecordedRatherThanSilentlySkipped`.
final class PendulumMetalEmpireTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-me"

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

    /// Just this device's section. Raremon is drawn by the Ver.5 Digital Monster tree three lines
    /// further up the same file, so "is this name in the document" is the wrong question to ask of
    /// a junk pick here — "is it in THIS section" is the one that matters.
    private func metalEmpireSection() throws -> String {
        let text = try document()
        let start = try XCTUnwrap(text.range(of: "### Version 5: Metal Empire (ME)"))
        let end = try XCTUnwrap(text.range(of: "### Version 0: Virus Busters"))
        return String(text[start.lowerBound..<end.lowerBound])
    }

    // MARK: - AC1/AC2: every playable name in the section is a node, on the right rung, in the line

    /// The tree as the document writes it, less the two names it cannot draw. `Fresh` is Baby I,
    /// `In-Training` is Baby II, `Rookie` is Child, `Champion` is Adult, the document's `Ultimate`
    /// is Perfect and its `Mega` is this app's `Ultimate-Super Ultimate`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("choromon", .babyI),
        ("caprimon", .babyII),
        ("toyagumon", .child),
        ("kokuwamon", .child),
        ("hagurumon", .child),
        ("junkmon", .child),
        ("pencme_greymon", .adult),
        ("revolmon", .adult),
        ("tankmon", .adult),
        ("thunderballmon", .adult),
        ("clockmon", .adult),
        ("guardromon", .adult),
        ("mechanorimon", .adult),
        ("pencme_metalgreymon", .perfect),
        ("pencme_andromon", .perfect),
        ("cyberdramon", .perfect),
        ("knightmon", .perfect),
        ("bigmamemon", .perfect),
        ("warumonzaemon", .perfect),
        ("rebellimon", .perfect),
        ("pencme_wargreymon", .ultimate),
        ("pencme_mugendramon", .ultimate),
        ("craniummon", .ultimate),
        ("princemamemon", .ultimate),
        ("pencme_hiandromon", .ultimate),
        ("pencme_venomvamdemon", .ultimate),
    ]

    func testEveryNameInTheSectionIsANodeOnTheCorrectStageInTheMetalEmpireLine() throws {
        XCTAssertEqual(Self.sectionMembers.count, 26,
                       "the section draws twenty-eight distinct Digimon, two of which cannot be drawn")
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Metal Empire tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's other half. Five of the section's names are not the names the ART is filed under.
    /// The document disambiguates three of them itself, in brackets — Revolmon (Deputymon),
    /// Machinedramon (Mugendramon) — and for the other two it gives only the dub name, which
    /// returns NOTHING to a `find -iname`: Kapurimon/Caprimon, Mekanorimon/Mechanorimon and
    /// VenomMyotismon/VenomVamdemon.
    ///
    /// The asserted direction matters: it is not "this id exists" but "the document's spelling has
    /// no PLAYABLE roster entry of its own", which is the thing that would make the substitution
    /// wrong.
    func testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses() throws {
        // The document's spelling -> the id actually wired.
        let renamed = [("Kapurimon", "caprimon"), ("Deputymon", "revolmon"),
                       ("Machinedramon", "pencme_mugendramon"),
                       ("Mekanorimon", "mechanorimon"),
                       ("VenomMyotismon", "pencme_venomvamdemon")]

        for (documentName, wiredId) in renamed {
            let wired = try node(wiredId)
            XCTAssertFalse(wired.dexOnly, "\(wiredId) must be playable")
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == documentName
                                                        && !$0.dexOnly },
                         "\(documentName) is playable after all and should be wired under its own name")
            XCTAssertTrue(try metalEmpireSection().contains(documentName),
                          "\(documentName) is not the document's spelling after all")
        }

        // Everything else in the section is wired under the document's own spelling.
        for name in ["Choromon", "ToyAgumon", "Greymon", "MetalGreymon", "WarGreymon", "Andromon",
                     "Cyberdramon", "Kokuwamon", "Tankmon", "Thunderballmon", "Knightmon",
                     "Craniummon", "Clockmon", "BigMamemon", "PrinceMamemon", "Hagurumon",
                     "Guardromon", "HiAndromon", "WaruMonzaemon", "Junkmon", "Rebellimon"] {
            XCTAssertNotNil(Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly },
                            "\(name) has no playable roster entry, so it cannot be wired")
        }
    }

    /// AC11 proper. Two of the section's twenty-eight names cannot be drawn, and they fail in the
    /// two DIFFERENT ways Phase E has met so far:
    ///
    /// - **Machmon** is the US-139 twin case. `Machmon` IS in the roster and `Machmon.png` IS on
    ///   disk — but only under `Idle Frame Only/`, so the entry is `dexOnly` and may never sit on
    ///   an edge. A `find` alone would have said it was present.
    /// - **HeavyMetaldramon** is simply absent. `find -iname '*heavymetal*'`, `'*metaldramon*'` and
    ///   `'*heavy*'` over the whole pack return only HeavyLeomon, and the roster holds nothing of
    ///   that name under any spelling.
    ///
    /// Both sit on the unlockable slot's thread, one below Rebellimon and one above it, which is
    /// why that thread needed two stand-ins rather than one.
    func testTheTwoUndrawableNamesAreRecordedRatherThanSilentlySkipped() throws {
        let machmon = try XCTUnwrap(Roster.bundled.entry(id: "machmon"),
                                    "Machmon is not in the roster at all")
        XCTAssertTrue(machmon.dexOnly, "Machmon has an animated sheet after all and should be wired")
        XCTAssertNil(graph.node(id: "machmon"), "an idle-only Digimon may not be a node")

        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "HeavyMetaldramon" },
                     "HeavyMetaldramon IS in the roster after all and should be wired")
        XCTAssertNil(graph.node(id: "heavymetaldramon"))

        // The document really does name both, so this records a gap rather than inventing one.
        XCTAssertTrue(try metalEmpireSection().contains(
            "Champion: Machmon -> Ultimate: Rebellimon -> Mega: HeavyMetaldramon"))

        // The rung of that thread that CAN be drawn is wired, between the two stand-ins.
        XCTAssertEqual(try node("rebellimon").line, line)
    }

    /// The two stand-ins, stated as the substitutions they are. Each is asserted to sit where the
    /// name it replaces sat, so a later reader can see at a glance that the thread the document
    /// draws is still the thread that is wired.
    func testTheTwoWikimonStandInsSitOnTheThreadTheyStandInFor() throws {
        // Machmon's slot: Junkmon -> Minotaurmon -> Rebellimon. Wikimon lists Minotaurmon in
        // Junkmon's Evolves To AND in Rebellimon's Evolves From, which is the intersection US-141
        // recorded as the way to price a rehome.
        XCTAssertEqual(try node("minotaurmon").stage, .adult)
        XCTAssertTrue(try targets(of: "junkmon").contains("minotaurmon"))
        XCTAssertTrue(try targets(of: "minotaurmon").contains("rebellimon"))

        // HeavyMetaldramon's slot: Rebellimon -> Gundramon, the top of the thread.
        XCTAssertEqual(try node("gundramon").stage, .ultimate)
        XCTAssertTrue(try targets(of: "rebellimon").contains("gundramon"))
        XCTAssertTrue(try node("gundramon").evolutions.isEmpty)

        // Neither is a name the document uses anywhere, in this section or any other.
        let text = try document()
        for name in ["Minotaurmon", "Gundramon"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the document after all")
        }
    }

    /// Chaosdramon was the other candidate on Rebellimon's Wikimon list and was deliberately NOT
    /// taken: the tree document draws it as the Digital Monster Ver.5 Jogress Ultra, and
    /// `jogress.json` already spends it twice. This is the grep US-140's notes insist on running
    /// BEFORE authoring, written down as an assertion rather than as a comment.
    func testChaosdramonWasLeftAloneBecauseTheDocumentAndJogressBothSpendIt() throws {
        XCTAssertTrue(try document().contains("Chaosdramon"), "the document does draw Chaosdramon")
        XCTAssertTrue(JogressCatalog.bundled.recipes.contains { $0.result == "chaosdramon" },
                      "jogress.json no longer makes Chaosdramon, so this reasoning is stale")
        XCTAssertNil(graph.node(id: "chaosdramon"), "this story must not have spent Chaosdramon")
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        XCTAssertTrue(try targets(of: "funbee_digitama").contains("choromon"))
        XCTAssertTrue(try targets(of: "choromon").contains("caprimon"))
        for rookie in ["toyagumon", "kokuwamon", "hagurumon", "junkmon"] {
            XCTAssertTrue(try targets(of: "caprimon").contains(rookie),
                          "Caprimon does not reach \(rookie)")
        }

        // Rookie -> Champion, exactly as the document draws them.
        XCTAssertTrue(try targets(of: "toyagumon").isSuperset(of: ["pencme_greymon", "revolmon"]))
        XCTAssertTrue(try targets(of: "kokuwamon")
            .isSuperset(of: ["tankmon", "thunderballmon", "clockmon"]))
        XCTAssertTrue(try targets(of: "hagurumon").isSuperset(of: ["guardromon", "mechanorimon"]))
        XCTAssertTrue(try targets(of: "junkmon").contains("minotaurmon"))

        // Champion -> Ultimate -> Mega, every thread the document draws. Three of them share a rung
        // with another thread, which is the shape that makes this section different from every
        // earlier one: Tankmon and Thunderballmon both reach Knightmon, and Andromon is reached
        // from Revolmon AND Guardromon and goes on to both Machinedramon and HiAndromon.
        let threads = [("pencme_greymon", "pencme_metalgreymon", "pencme_wargreymon"),
                       ("revolmon", "pencme_andromon", "pencme_mugendramon"),
                       ("revolmon", "cyberdramon", "pencme_mugendramon"),
                       ("tankmon", "knightmon", "craniummon"),
                       ("thunderballmon", "knightmon", "craniummon"),
                       ("clockmon", "bigmamemon", "princemamemon"),
                       ("guardromon", "pencme_andromon", "pencme_hiandromon"),
                       ("mechanorimon", "warumonzaemon", "pencme_venomvamdemon"),
                       ("minotaurmon", "rebellimon", "gundramon")]

        XCTAssertEqual(threads.count, 9, "the section draws nine Champion-to-Mega threads")
        for (champion, perfect, mega) in threads {
            XCTAssertTrue(try targets(of: champion).contains(perfect),
                          "\(champion) must reach \(perfect)")
            XCTAssertTrue(try targets(of: perfect).contains(mega), "\(perfect) must reach \(mega)")
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is the top of its thread")
        }
    }

    /// The document draws Andromon twice, and one node carries both drawings — so it is the only
    /// Perfect in the whole file with two parents AND two children, and the only one whose second
    /// outgoing edge had to be earned rather than the usual single `isDefault` climb.
    func testAndromonIsTheOneNodeThatJoinsTwoOfTheDocumentsThreads() throws {
        XCTAssertEqual(Set(graph.parents(of: "pencme_andromon").map(\.id)),
                       ["revolmon", "guardromon"])
        XCTAssertEqual(try targets(of: "pencme_andromon"),
                       ["pencme_hiandromon", "pencme_mugendramon"])

        let earned = try node("pencme_andromon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["pencme_mugendramon"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the second climb must be earned")

        // Mugendramon is still reachable without it, through Cyberdramon's default edge.
        XCTAssertEqual(Set(graph.parents(of: "pencme_mugendramon").map(\.id)),
                       ["pencme_andromon", "cyberdramon"])
        XCTAssertEqual(Set(graph.parents(of: "knightmon").map(\.id)),
                       ["tankmon", "thunderballmon"])
    }

    // MARK: - AC4: reachable from a Digitama, end to end

    /// The egg is a real ROSTER Digitama rather than a line-scoped one, and that is a playability
    /// requirement rather than taste: `maps.json` grants a Digitama by roster id, an alias has no
    /// roster entry, and a line whose egg can never drop is a line no player can start.
    ///
    /// It is also the first egg in the file that belongs to no rung of its own tree: US-141's was
    /// at least a Rookie of the Wind Guardians, while NONE of ToyAgumon, Kokuwamon, Hagurumon and
    /// Junkmon has an egg on disk. What is left of the rule is "a real roster Digitama that a map
    /// drops", and `06_industrial` — the machine map — drops this one.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("funbee_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let industrial = try XCTUnwrap(MapCatalog.bundled.maps.first { $0.id == "06_industrial" },
                                       "06_industrial is not a map in this app")
        XCTAssertTrue(industrial.digitamaSlots.map(\.digitamaId).contains(egg.id),
                      "06_industrial does not drop \(egg.id), so the line is unstartable")

        // One egg per line until US-144, which hangs `espi_digitama` off this line rather than opening a
        // one-node line for a species this tree already reaches; US-145 added `phasco_digitama` the
        // same way, Phascomon evolving from Caprimon. The line's OWN egg is still the first of
        // them, and still the one the rest of this file reasons about.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "espi_digitama", "phasco_digitama"])

        // No Rookie of this tree has an egg of its own, which is why the choice went outside it.
        for rookie in ["toyagumon", "kokuwamon", "hagurumon", "junkmon"] {
            let stem = String(rookie.dropLast("mon".count))
            XCTAssertNil(Roster.bundled.entries.first {
                $0.stage == .digitama && $0.id.hasPrefix(stem)
            }, "\(rookie) has an egg after all and should have rooted this line")
        }
    }

    /// Since US-144 the seed is every Digitama of the line, not just this tree's own: the first
    /// orphan sweep gives a line a second egg where the species it belongs to is already wired
    /// here. What the test still means is unchanged — nothing in the line is stranded above the
    /// eggs — and `testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant` is what pins
    /// which eggs those are.
    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains("funbee_digitama"), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 34)
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The eight line-scoped aliases, and the orphans this story really removed

    /// Eight of this tree's thirty-two Digimon already had a node in another line, so eight are
    /// line-scoped: the piyo_yuramon pattern. Each is asserted to be the SAME Digimon — same art,
    /// same display name, same rung — under a second id, because the failure this guards against is
    /// an alias silently pointing at a different sheet from the Digimon it stands in for.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencme_greymon", "greymon", "dmc-v1"),
            ("pencme_metalgreymon", "metalgreymon", "dmc-v1"),
            ("pencme_wargreymon", "wargreymon", "dmc-v1"),
            ("pencme_andromon", "andromon", "dmc-v3"),
            ("pencme_hiandromon", "hiandromon", "dmc-v3"),
            ("pencme_mugendramon", "mugendramon", "dmc-v5"),
            ("pencme_venomvamdemon", "venomvamdemon", "penc-nso"),
            ("pencme_raremon", "raremon", "dmc-v5"),
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

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencme_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")
    }

    /// The Agumon thread was the second TRIPLE in the file when this story landed, and US-143 made
    /// it a QUADRUPLE — which is what the count here was written to catch, and did: the V0 Virus
    /// Busters section draws Agumon over Greymon, MetalGreymon and WarGreymon as well, so four
    /// trees now share those three roster entries. Restated rather than deleted, because the claim
    /// still worth guarding is that this tree is ONE of them and that no fifth copy has appeared.
    func testTheGreymonThreadIsDrawnByExactlyFourTrees() throws {
        for plain in ["greymon", "metalgreymon", "wargreymon"] {
            let name = try node(plain).displayName
            let copies = graph.nodes.filter { $0.displayName == name }
            XCTAssertEqual(Set(copies.map(\.line)), ["dmc-v1", "penc-nsp", "penc-vb", line])
            XCTAssertEqual(copies.count, 4, "\(plain) has a fifth copy")
        }
    }

    /// AC12, asserted rather than only counted in the notes: an ALIAS removes no orphan, because it
    /// shares a roster entry that some earlier story already wired. Twenty-four of this tree's
    /// thirty-two nodes carry a plain roster id, and those twenty-four are the orphans this story
    /// really took off the pile.
    func testTwentyFourOfTheThirtyTwoNodesCarryAPlainRosterIdAndSoRemoveAnOrphan() throws {
        // US-144 hung `espi_digitama` on this line. That egg is not one of this story's nodes, so it is
        // excluded by NAME rather than by bumping the totals: the numbers below are the claim this
        // story's notes made, and a total quietly one higher would no longer be that claim.
        let sweepEggs: Set<String> = ["espi_digitama", "phasco_digitama"]
        let mine = graph.nodes.filter { $0.line == line && !sweepEggs.contains($0.id) }
        let plain = mine.filter { Roster.bundled.entry(id: $0.id) != nil }
        let scoped = mine.filter { Roster.bundled.entry(id: $0.id) == nil }

        XCTAssertEqual(mine.count, 32)
        XCTAssertEqual(plain.count, 24, "the orphan count in the notes is off")
        XCTAssertEqual(scoped.count, 8)

        // And none of the twenty-four was already carried by another line under the same id.
        for node in plain {
            XCTAssertEqual(graph.nodes.filter { $0.id == node.id }.count, 1,
                           "\(node.id) is a duplicate id, not an orphan removed")
        }
    }

    /// `pencme_raremon` is this tree's Pumpmon case, the third in the file and the first where the
    /// plain id is JUNK in both lines: Raremon is the Digital Monster Ver.5 tree's junk Champion and
    /// this tree's too. One node could not be both, because each has to fall to its own line's junk
    /// Perfect — Vademon there, Locomon here.
    func testRaremonIsTheJunkChampionOfTwoTreesUnderTwoIds() throws {
        XCTAssertEqual(try node("raremon").line, "dmc-v5")
        XCTAssertEqual(try node("raremon").evolutions.first(where: \.isDefault)?.to, "vademon")
        XCTAssertEqual(try node("pencme_raremon").evolutions.first(where: \.isDefault)?.to, "locomon")
        XCTAssertEqual(try node("raremon").displayName, try node("pencme_raremon").displayName)
    }

    /// Every one of the eight needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencme_") {
            let plain = String(node.id.dropFirst("pencme_".count))
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
    /// nonetheless needs an `isDefault` edge reachable by doing nothing, so US-142 chose a chain off
    /// sheets that were orphans, the way US-138 to US-141 did: Raremon -> Locomon -> GrandLocomon.
    ///
    /// It is the best-supported junk chain of the five. Wikimon lists Raremon in Junkmon's Evolves
    /// To, Locomon's prior forms as Raremon, Guardromon, Mechanorimon, Tankmon, Minotaurmon and
    /// Machmon — six of this tree's nine Champions — and GrandLocomon as Locomon's own Mega. Every
    /// arrow of the invented branch is an arrow the source material already draws.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("pencme_raremon").stage, .adult)
        XCTAssertEqual(try node("locomon").stage, .perfect)
        XCTAssertEqual(try node("grandlocomon").stage, .ultimate)

        for id in ["pencme_raremon", "locomon", "grandlocomon"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("pencme_raremon").evolutions.first(where: \.isDefault)?.to, "locomon")
        XCTAssertEqual(try node("locomon").evolutions.first(where: \.isDefault)?.to, "grandlocomon")

        // Every Rookie falls to the same Champion — that is what makes it the tree's junk branch.
        for rookie in ["toyagumon", "kokuwamon", "hagurumon", "junkmon"] {
            XCTAssertEqual(try node(rookie).evolutions.first(where: \.isDefault)?.to,
                           "pencme_raremon")
        }
        // And every Champion falls to the same Perfect.
        for champion in graph.nodes.filter({ $0.line == line && $0.stage == .adult }) {
            XCTAssertEqual(champion.evolutions.first(where: \.isDefault)?.to, "locomon",
                           "\(champion.id) does not fall to this tree's junk Perfect")
        }

        // The section really is silent. Raremon is the reason this asks about the SECTION rather
        // than the whole document: the Ver.5 Digital Monster tree fourteen lines further up draws
        // it three times, and a whole-file grep would have rejected a pick that is fine here.
        let section = try metalEmpireSection()
        for name in ["Raremon", "Locomon", "GrandLocomon"] {
            XCTAssertFalse(section.contains(name), "\(name) IS in the Metal Empire section after all")
        }
        XCTAssertTrue(try document().contains("Raremon"), "Raremon is drawn elsewhere in the file")
        XCTAssertFalse(try document().contains("Locomon"), "Locomon IS in the document after all")
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesRaremon() throws {
        for rookie in ["toyagumon", "kokuwamon", "hagurumon", "junkmon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "pencme_raremon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The junk Champion keeps one way back UP, so a player who neglected a Rookie and then worked
    /// is not locked out of the tree — the same shape US-138 gave PlatinumScumon, US-139 gave
    /// Diginorimon, US-140 gave Gokimon and US-141 gave Zassoumon. Here it is canon: Wikimon lists
    /// Rebellimon as something Raremon really evolves into, and Rebellimon is the rung the
    /// unlockable slot's thread is built around.
    func testTheJunkChampionKeepsOneEarnedWayBackIntoTheTree() throws {
        let earned = try node("pencme_raremon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["rebellimon"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the way back must be earned, not free")

        // And that leaves Rebellimon with two parents, the earned one and the way back.
        XCTAssertEqual(Set(graph.parents(of: "rebellimon").map(\.id)),
                       ["minotaurmon", "pencme_raremon"])
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
            ("toyagumon", [(.vitality, "pencme_greymon"), (.strength, "revolmon")]),
            ("kokuwamon", [(.strength, "tankmon"), (.stamina, "thunderballmon"),
                           (.spirit, "clockmon")]),
            ("hagurumon", [(.vitality, "guardromon"), (.strength, "mechanorimon")]),
            ("junkmon", [(.stamina, "minotaurmon")]),
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

        // The In-Training rung forks four ways, one per Rookie the section draws.
        for (energy, expected) in [(EnergyType.vitality, "toyagumon"),
                                   (.strength, "kokuwamon"),
                                   (.spirit, "hagurumon"),
                                   (.stamina, "junkmon")] {
            var totals = EnergyTotals.zero
            totals[energy] = 150
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: try node("caprimon"), stageEnergy: totals,
                                                dominant: energy, careMistakes: 0, battleWins: 0,
                                                conditions: met),
                expected, "a well-raised \(energy.rawValue) Caprimon does not reach \(expected)")
        }
    }

    /// Each branching node's earned edges need distinct dominant types, or one of them is
    /// unreachable — `EvolutionEngine` picks on the dominant energy first and two branches sharing
    /// one would make the second dead data. Kokuwamon is the test that matters here: it is the only
    /// Rookie in the file with THREE earned Champions, so it spends three of the four energies.
    func testEveryBranchingNodeInTheLineUsesDistinctEnergies() throws {
        for id in ["caprimon", "toyagumon", "kokuwamon", "hagurumon", "junkmon"] {
            let earned = try node(id).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(id) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(id) offers two branches on the same energy")
        }
        XCTAssertEqual(try node("kokuwamon").evolutions.filter { !$0.isDefault }.count, 3)
    }

    /// US-138's Angoramon, US-139's Jellymon and US-141's Pteromon were the document's "Rookie
    /// (Unlockable Slot N)", and each got the tree's one conditioned In-Training edge. This section
    /// numbers no slot, but marks one the same way, and Junkmon IS drawn — so the shape holds: the
    /// `caprimon -> junkmon` edge is the only one out of the In-Training rung gated on anything more
    /// than dominant energy.
    func testTheUnlockableSlotIsTheOnlyConditionedInTrainingEdge() throws {
        let caprimon = try node("caprimon")
        XCTAssertEqual(caprimon.evolutions.count, 4, "one edge per Rookie the section draws")

        for edge in caprimon.evolutions {
            XCTAssertNotNil(edge.requiredEnergy)
            if edge.to == "junkmon" {
                XCTAssertFalse(edge.conditions.isEmpty, "the unlockable slot must be unlocked")
                XCTAssertFalse(edge.isDefault)
            } else {
                XCTAssertTrue(edge.conditions.isEmpty,
                              "\(edge.to) is conditioned, but only the spare slot is unlockable")
            }
        }

        XCTAssertTrue(try metalEmpireSection().contains("Rookie (Unlockable Slot): Junkmon"))
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

        XCTAssertTrue(try comment(on: "funbee_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "funbee_digitama").contains("06_industrial"),
                      "the egg must name the map that actually drops it")
        XCTAssertTrue(try comment(on: "pencme_raremon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")

        // The two stand-ins, each naming the reference it came from and the name it replaces.
        for (id, absent) in [("minotaurmon", "Machmon"), ("gundramon", "HeavyMetaldramon")] {
            XCTAssertTrue(try comment(on: id).contains("Wikimon"),
                          "\(id) must name the reference it came from")
            XCTAssertTrue(try comment(on: id).contains(absent),
                          "\(id) must name the undrawable Digimon it stands in for")
        }
        XCTAssertTrue(try comment(on: "gundramon").contains("Chaosdramon"),
                      "the Mega must say why the other candidate was left alone")
        XCTAssertTrue(try comment(on: "locomon").contains("Wikimon"))

        // The renamings, each recorded on the node that carries the substitute spelling.
        XCTAssertTrue(try comment(on: "caprimon").contains("Kapurimon"))
        XCTAssertTrue(try comment(on: "revolmon").contains("Deputymon"))
        XCTAssertTrue(try comment(on: "mechanorimon").contains("Mekanorimon"))
        XCTAssertTrue(try comment(on: "pencme_mugendramon").contains("Machinedramon"))
        XCTAssertTrue(try comment(on: "pencme_venomvamdemon").contains("VenomMyotismon"))
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg). Stronger than "the
    /// file exists": an idle-only 16x16 sprite fails here rather than shipping as a Digimon that
    /// cannot animate, which is exactly the trap Machmon set.
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
                               "\(node.id) -> \(edge.to) is earned but gated on nothing")
            }
            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.conditions, [], "\(node.id)'s junk edge carries criteria")
            XCTAssertEqual(fallback.minEnergy, 0)
        }

        for node in graph.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    XCTAssertFalse(
                        condition.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(node.id) -> \(edge.to) has a blank hint on \(condition.metric)")
                }
            }
        }
    }

    /// AC10, stated where this story can see it: the shipped file validates with no findings at all.
    func testTheWholeFileStillValidatesWithZeroFindings() throws {
        XCTAssertEqual(try EvolutionGraph.load().validate(), [])
    }
}
