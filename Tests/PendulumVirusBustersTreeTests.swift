import XCTest
@testable import DigiVPet

/// US-143: the Pendulum Color V0 Virus Busters / ZERO tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 0:
/// Virus Busters (VB) / ZERO", line 166. Every test here reads the REAL `evolutions.json`.
///
/// The sixth Phase E tree with no seed line behind it and the LAST of the eleven device trees. It
/// is the only one with no absent name and no dexOnly twin: all twenty-six Digimon the section
/// draws have a playable 48x64 sheet, three of them under a spelling the document does not use
/// (SnowBotamon/`YukimiBotamon`, Salamon/`Plotmon`, Gatomon/`Tailmon`, Wizardmon/`Wizarmon`,
/// Stefilmon/`Stiffilmon`). Its one real oddity is that the document draws the SAME Digimon twice
/// under two names — HolyAngemon over Angemon and MagnaAngemon over Wizardmon — and one node
/// carries both drawings. See `testHolyAngemonCarriesBothOfTheDocumentsDrawingsOfIt`.
final class PendulumVirusBustersTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-vb"

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

    /// Just this device's section. It is the LAST section of the file, so it runs to the end rather
    /// than to the next `### Version` heading.
    private func virusBustersSection() throws -> String {
        let text = try document()
        let start = try XCTUnwrap(text.range(of: "### Version 0: Virus Busters (VB) / ZERO"))
        return String(text[start.lowerBound...])
    }

    // MARK: - AC1/AC2: every playable name in the section is a node, on the right rung, in the line

    /// The tree as the document writes it. `Fresh` is Baby I, `In-Training` is Baby II, `Rookie` is
    /// Child, `Champion` is Adult, the document's `Ultimate` is Perfect and its `Mega` is this
    /// app's `Ultimate-Super Ultimate`. Its `Ultra` row is a Jogress and so is not a node here.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("yukimibotamon", .babyI),
        ("nyaromon", .babyII),
        ("pencvb_agumon", .child),
        ("pencvb_gabumon", .child),
        ("plotmon", .child),
        ("herissmon", .child),
        ("pencvb_greymon", .adult),
        ("pencvb_leomon", .adult),
        ("pencvb_garurumon", .adult),
        ("pencvb_angemon", .adult),
        ("pencvb_tailmon", .adult),
        ("pencvb_wizarmon", .adult),
        ("filmon", .adult),
        ("pencvb_metalgreymon", .perfect),
        ("pencvb_asuramon", .perfect),
        ("pencvb_weregarurumon", .perfect),
        ("holyangemon", .perfect),
        ("pencvb_angewomon", .perfect),
        ("stiffilmon", .perfect),
        ("pencvb_wargreymon", .ultimate),
        ("pencvb_saberleomon", .ultimate),
        ("pencvb_metalgarurumon", .ultimate),
        ("seraphimon", .ultimate),
        ("ophanimon", .ultimate),
        ("cherubimon_virtue", .ultimate),
        ("rasenmon", .ultimate),
    ]

    func testEveryNameInTheSectionIsANodeOnTheCorrectStageInTheVirusBustersLine() throws {
        XCTAssertEqual(Self.sectionMembers.count, 26,
                       "the section draws twenty-six distinct Digimon below its Jogress row")
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Virus Busters tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's other half, and the reason this tree has no absent name at all: five of its Digimon
    /// are filed under a spelling the document does not use. The document brackets two of them
    /// itself (Salamon/Plotmon, Gatomon/Tailmon) and for the other three gives only the dub name,
    /// which returns NOTHING to a `find -iname`: SnowBotamon/YukimiBotamon, Wizardmon/Wizarmon and
    /// Stefilmon/Stiffilmon.
    ///
    /// The asserted direction matters: it is not "this id exists" but "the document's spelling has
    /// no PLAYABLE roster entry of its own", which is the thing that would make the substitution
    /// wrong.
    func testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses() throws {
        // The document's spelling -> the id actually wired.
        let renamed = [("SnowBotamon", "yukimibotamon"), ("Salamon", "plotmon"),
                       ("Gatomon", "pencvb_tailmon"), ("Wizardmon", "pencvb_wizarmon"),
                       ("Stefilmon", "stiffilmon")]

        for (documentName, wiredId) in renamed {
            let wired = try node(wiredId)
            XCTAssertFalse(wired.dexOnly, "\(wiredId) must be playable")
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == documentName
                                                        && !$0.dexOnly },
                         "\(documentName) is playable after all and should be wired under its own name")
            XCTAssertTrue(try virusBustersSection().contains(documentName),
                          "\(documentName) is not the document's spelling after all")
        }

        // Everything else in the section is wired under the document's own spelling.
        for name in ["Nyaromon", "Agumon", "Greymon", "MetalGreymon", "WarGreymon", "Leomon",
                     "Asuramon", "SaberLeomon", "Gabumon", "Garurumon", "WereGarurumon",
                     "MetalGarurumon", "Angemon", "HolyAngemon", "Seraphimon", "Angewomon",
                     "Ophanimon", "Herissmon", "Filmon", "Rasenmon"] {
            XCTAssertNotNil(Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly },
                            "\(name) has no playable roster entry, so it cannot be wired")
        }
    }

    /// AC11 proper, and this is the first Phase E tree where the answer is "none". Every name the
    /// section draws has a playable sheet, so nothing was skipped and no Wikimon stand-in was
    /// needed — the first tree since US-139's Deep Savers with a clean sheet, and the only one of
    /// the six Pendulum trees with no rehomed rung at all.
    ///
    /// Asserted as a sweep over the section's own text rather than as a sentence in the notes: every
    /// capitalised Digimon name the section contains must resolve to a playable roster entry, under
    /// its own spelling or under the one `renamed` above records.
    func testNoNameInTheSectionIsMissingAPlayableSheet() throws {
        let substituted = ["SnowBotamon": "YukimiBotamon", "Salamon": "Plotmon",
                           "Gatomon": "Tailmon", "Wizardmon": "Wizarmon",
                           "Stefilmon": "Stiffilmon", "MagnaAngemon": "HolyAngemon",
                           "Cherubimon": "Cherubimon Virtue"]
        let drawn = try virusBustersSection()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.hasSuffix("mon") && $0.count > 3 }

        XCTAssertGreaterThan(drawn.count, 26, "the section's names were not extracted")
        for name in Set(drawn) where name != "Omegamon" {
            let wanted = substituted[name] ?? name
            XCTAssertNotNil(
                Roster.bundled.entries.first { $0.displayName == wanted && !$0.dexOnly },
                "\(name) has no playable sheet under \(wanted) and was skipped silently")
        }
    }

    /// Omegamon is the one name the sweep above excuses, and this is why: the document draws it as
    /// the section's `Ultra` row on BOTH the Agumon and the Gabumon thread, and it is a Jogress —
    /// a recipe in `jogress.json`, not an edge, which is the treatment every other tree's Ultra row
    /// got. `penc-nsp` was the first line to hold both of that recipe's parents; this is the second,
    /// and the one whose own document actually draws the fusion.
    func testTheOmegamonRowIsAJogressRecipeRatherThanAnEdge() throws {
        XCTAssertTrue(try virusBustersSection().contains("Ultra: Omegamon (Jogress)"))
        XCTAssertNil(graph.node(id: "omegamon"), "Omegamon is a Jogress result, not a node here")

        XCTAssertNotNil(JogressCatalog.bundled.recipe(for: "wargreymon", and: "metalgarurumon"),
                        "the Virus Busters Ultra row has no recipe in jogress.json")
        XCTAssertTrue(try node("pencvb_wargreymon").evolutions.isEmpty)
        XCTAssertTrue(try node("pencvb_metalgarurumon").evolutions.isEmpty)

        // The recipe is authored against the ROSTER ids, which is why the line-scoped copies here
        // do not need one of their own.
        XCTAssertEqual(try node("pencvb_wargreymon").spriteFile,
                       Roster.bundled.entry(id: "wargreymon")?.spriteFile)
        XCTAssertEqual(try node("pencvb_metalgarurumon").spriteFile,
                       Roster.bundled.entry(id: "metalgarurumon")?.spriteFile)
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        XCTAssertTrue(try targets(of: "heriss_digitama").contains("yukimibotamon"))
        XCTAssertTrue(try targets(of: "yukimibotamon").contains("nyaromon"))
        for rookie in ["pencvb_agumon", "pencvb_gabumon", "plotmon", "herissmon"] {
            XCTAssertTrue(try targets(of: "nyaromon").contains(rookie),
                          "Nyaromon does not reach \(rookie)")
        }

        // Rookie -> Champion, exactly as the document draws them: two apiece, one for the
        // unlockable slot.
        XCTAssertTrue(try targets(of: "pencvb_agumon")
            .isSuperset(of: ["pencvb_greymon", "pencvb_leomon"]))
        XCTAssertTrue(try targets(of: "pencvb_gabumon")
            .isSuperset(of: ["pencvb_garurumon", "pencvb_angemon"]))
        XCTAssertTrue(try targets(of: "plotmon")
            .isSuperset(of: ["pencvb_tailmon", "pencvb_wizarmon"]))
        XCTAssertTrue(try targets(of: "herissmon").contains("filmon"))

        // Champion -> Ultimate -> Mega, every thread the document draws. HolyAngemon appears in two
        // of them, because the document draws it twice under two names.
        let threads = [("pencvb_greymon", "pencvb_metalgreymon", "pencvb_wargreymon"),
                       ("pencvb_leomon", "pencvb_asuramon", "pencvb_saberleomon"),
                       ("pencvb_garurumon", "pencvb_weregarurumon", "pencvb_metalgarurumon"),
                       ("pencvb_angemon", "holyangemon", "seraphimon"),
                       ("pencvb_tailmon", "pencvb_angewomon", "ophanimon"),
                       ("pencvb_wizarmon", "holyangemon", "cherubimon_virtue"),
                       ("filmon", "stiffilmon", "rasenmon")]

        XCTAssertEqual(threads.count, 7, "the section draws seven Champion-to-Mega threads")
        for (champion, perfect, mega) in threads {
            XCTAssertTrue(try targets(of: champion).contains(perfect),
                          "\(champion) must reach \(perfect)")
            XCTAssertTrue(try targets(of: perfect).contains(mega), "\(perfect) must reach \(mega)")
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is the top of its thread")
        }
    }

    /// The section's one genuine oddity. It draws "Angemon -> Ultimate: HolyAngemon -> Mega:
    /// Seraphimon" on one thread and "Wizardmon -> Ultimate: MagnaAngemon -> Mega: Cherubimon
    /// (Virtue)" on another — and MagnaAngemon IS HolyAngemon, the dub name of the same Digimon.
    /// There is one sheet, so there is one node, and it carries both drawings: two parents and two
    /// children, the second node in the file with that shape after US-142's `pencme_andromon`.
    func testHolyAngemonCarriesBothOfTheDocumentsDrawingsOfIt() throws {
        let section = try virusBustersSection()
        XCTAssertTrue(section.contains("Ultimate: HolyAngemon"))
        XCTAssertTrue(section.contains("Ultimate: MagnaAngemon"))

        // MagnaAngemon is not a sheet, a roster entry or a node — the substitution is forced.
        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "MagnaAngemon" })
        XCTAssertNil(graph.node(id: "magnaangemon"))

        // US-151 hung BlackTailmon here as a THIRD parent, on the arrow Wikimon draws for it
        // (Pendulum Progress 2.0, Digimon World Re:Digitize Decode), and US-152 GulusGammamon as a
        // FOURTH, on the arrow Wikimon draws for THAT (Pendulum COLOR ZERO Virus Busters). The
        // document's own two drawings — the pair this test is about — are unchanged.
        XCTAssertEqual(Set(graph.parents(of: "holyangemon").map(\.id)),
                       ["pencvb_angemon", "pencvb_wizarmon", "blacktailmon", "gulusgammamon"])
        XCTAssertEqual(try targets(of: "holyangemon"), ["seraphimon", "cherubimon_virtue"])

        // Exactly one isDefault climb, and the second one EARNED — the pencme_andromon shape.
        let earned = try node("holyangemon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["cherubimon_virtue"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the second climb must be earned")
        XCTAssertEqual(try node("holyangemon").evolutions.first(where: \.isDefault)?.to,
                       "seraphimon")
    }

    // MARK: - AC4: reachable from a Digitama, end to end

    /// The egg is a real ROSTER Digitama rather than a line-scoped one, and that is a playability
    /// requirement rather than taste: `maps.json` grants a Digitama by roster id, an alias has no
    /// roster entry, and a line whose egg can never drop is a line no player can start.
    ///
    /// It is Herissmon's rather than Agumon's for US-141's reason: `agu_digitama` roots `dmc-v1`
    /// and one egg cannot root two lines, so the egg is the next Rookie of this tree that has one.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("heriss_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let farmland = try XCTUnwrap(MapCatalog.bundled.maps.first { $0.id == "14_farmland" },
                                     "14_farmland is not a map in this app")
        XCTAssertTrue(farmland.digitamaSlots.map(\.digitamaId).contains(egg.id),
                      "14_farmland does not drop \(egg.id), so the line is unstartable")

        // One egg per line until US-144, which hangs `kuda_digitama` and `kuda2006_digitama` off this line rather than opening a
        // one-node line for a species this tree already reaches. The line's OWN egg is still the
        // first of them, and still the one the rest of this file reasons about.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "kuda_digitama", "kuda2006_digitama", "plot_digitama"])

        // The default Rookie's own egg was not available: it roots the Digital Monster Ver.1 tree.
        XCTAssertEqual(try node("agu_digitama").line, "dmc-v1")
        XCTAssertEqual(try node("heriss_digitama").evolutions.first?.to, "yukimibotamon")
    }

    /// Since US-144 the seed is every Digitama of the line, not just this tree's own: the first
    /// orphan sweep gives a line a second egg where the species it belongs to is already wired
    /// here. What the test still means is unchanged — nothing in the line is stranded above the
    /// eggs — and `testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant` is what pins
    /// which eggs those are.
    ///
    /// US-146 puts TWO nodes beyond the eggs' reach, and they are listed rather than excused.
    /// Pusurimon's only Child is Herissmon, which is already a node here, so Pusurimon can sit on
    /// no other line — and its only parent is Pusumon, which comes with it. Neither can ever gain
    /// an in-edge from above: US-144 and US-145 spent all 57 Digitama, and `EggHatcher.hatchTarget`
    /// reads `evolutions.first`, so no egg has a second hatch to give. Pinned as a list, not
    /// dropped from the check, so a THIRD stranded node fails.
    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains("heriss_digitama"), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 55,
                       "US-147 hung Hiyarimon and Penmon here, US-149 Gammamon and BetelGammamon, "
                           + "US-150 Plotmon X, Tailmon X and Cockatrimon, US-151 BlackTailmon, "
                           + "US-152 GulusGammamon, US-153 KausGammamon, US-154 Mikemon and "
                           + "Nefertimon X, US-156 WezenGammamon and Canoweissmon, US-158 Entmon "
                           + "over the Cockatrimon US-150 left a leaf")
        XCTAssertEqual(inLine.filter { !reached.contains($0) }.sorted(), ["pusumon", "pusurimon"],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The fifteen line-scoped aliases, and the orphans this story really removed

    /// HALF of this tree already had a node in another line — the worst ratio in the file, and not
    /// a surprise: the V0 device is the one every earlier tree borrowed from, so Agumon, Gabumon
    /// and everything above them were spent long before this story reached them. Each alias is
    /// asserted to be the SAME Digimon — same art, same display name, same rung — under a second
    /// id, because the failure this guards against is an alias silently pointing at a different
    /// sheet from the Digimon it stands in for.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencvb_agumon", "agumon", "dmc-v1"),
            ("pencvb_greymon", "greymon", "dmc-v1"),
            ("pencvb_metalgreymon", "metalgreymon", "dmc-v1"),
            ("pencvb_wargreymon", "wargreymon", "dmc-v1"),
            ("pencvb_leomon", "leomon", "dmc-v4"),
            ("pencvb_asuramon", "asuramon", "penc-nsp"),
            ("pencvb_saberleomon", "saberleomon", "penc-nsp"),
            ("pencvb_gabumon", "gabumon", "dmc-v2"),
            ("pencvb_garurumon", "garurumon", "dmc-v2"),
            ("pencvb_weregarurumon", "weregarurumon", "dmc-v2"),
            ("pencvb_metalgarurumon", "metalgarurumon", "dmc-v2"),
            ("pencvb_angemon", "angemon", "dmc-v2"),
            ("pencvb_tailmon", "tailmon", "penc-nsp"),
            ("pencvb_angewomon", "angewomon", "penc-nsp"),
            ("pencvb_wizarmon", "wizarmon", "penc-nso"),
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

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencvb_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")
    }

    /// Both of the file's TRIPLES become quadruples here, and for the same reason: the V0 device is
    /// where the Agumon and Gabumon threads come from, so every tree that borrowed one of them is
    /// now standing beside the tree that owns it.
    func testBothOfTheFilesTriplesAreQuadruplesNow() throws {
        for plain in ["greymon", "metalgreymon", "wargreymon"] {
            let copies = graph.nodes.filter { $0.displayName == (try? node(plain).displayName) }
            XCTAssertEqual(Set(copies.map(\.line)), ["dmc-v1", "penc-nsp", "penc-me", line])
        }
        for plain in ["garurumon", "weregarurumon", "metalgarurumon"] {
            let copies = graph.nodes.filter { $0.displayName == (try? node(plain).displayName) }
            XCTAssertEqual(Set(copies.map(\.line)), ["dmc-v2", "penc-nsp", "penc-nso", line])
        }
    }

    /// AC12, asserted rather than only counted in the notes: an ALIAS removes no orphan, because it
    /// shares a roster entry that some earlier story already wired. Fifteen of this tree's thirty
    /// nodes carry a plain roster id, and those fifteen are the orphans this story really took off
    /// the pile.
    func testFifteenOfTheThirtyNodesCarryAPlainRosterIdAndSoRemoveAnOrphan() throws {
        // US-144 hung `kuda_digitama` and `kuda2006_digitama` on this line. That egg is not one of this story's nodes, so it is
        // excluded by NAME rather than by bumping the totals: the numbers below are the claim this
        // story's notes made, and a total quietly one higher would no longer be that claim.
        // `pusumon` and `pusurimon` are US-146's and excluded for the same reason.
        // `hiyarimon` and `penmon` are US-147's, excluded for the same reason.
        // `plotmon_x`, `tailmon_x` and `cockatrimon` are US-150's, excluded the same way.
        let sweepEggs: Set<String> = ["kuda_digitama", "kuda2006_digitama", "plot_digitama",
                                      "pusumon", "pusurimon", "hiyarimon", "penmon",
                                      "gammamon", "betelgammamon",
                                      "plotmon_x", "tailmon_x", "cockatrimon",
                                      "blacktailmon", "gulusgammamon", "kausgammamon",
                                      "mikemon", "nefertimon_x",
                                      "wezengammamon", "canoweissmon",
                                      // US-157's four, hung off Turuiemon, Tailmon X and Leomon,
                                      // and US-158's Entmon, hung off Cockatrimon.
                                      "andiramon_data", "angewomon_x", "caturamon", "ophanimon_x",
                                      "entmon",
                                      // US-161's one: Regulusmon over the bolded GulusGammamon,
                                      // climbing this line's own MetalGarurumon.
                                      "regulusmon"]
        let mine = graph.nodes.filter { $0.line == line && !sweepEggs.contains($0.id) }
        let plain = mine.filter { Roster.bundled.entry(id: $0.id) != nil }
        let scoped = mine.filter { Roster.bundled.entry(id: $0.id) == nil }

        XCTAssertEqual(mine.count, 30)
        XCTAssertEqual(plain.count, 15, "the orphan count in the notes is off")
        XCTAssertEqual(scoped.count, 15)

        // And none of the fifteen was already carried by another line under the same id.
        for node in plain {
            XCTAssertEqual(graph.nodes.filter { $0.id == node.id }.count, 1,
                           "\(node.id) is a duplicate id, not an orphan removed")
        }
    }

    /// Every one of the fifteen needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencvb_") {
            let plain = String(node.id.dropFirst("pencvb_".count))
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
    /// nonetheless needs an `isDefault` edge reachable by doing nothing, so US-143 chose a chain off
    /// sheets that were orphans, the way US-138 to US-142 did: Turuiemon -> Andiramon (Virus) ->
    /// Cherubimon (Vice).
    ///
    /// It is the Lopmon line's fall as Wikimon draws it — Turuiemon evolves into Andiramon (Virus),
    /// which evolves into Cherubimon (Vice) — and it is chosen for what it means rather than only
    /// for being spare: Cherubimon (Vice) is the counterpart of the Cherubimon (Virtue) this
    /// document itself puts over Wizardmon, so neglecting a Virus Buster ends it as the thing the
    /// tree exists to fight.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("turuiemon").stage, .adult)
        XCTAssertEqual(try node("andiramon_virus").stage, .perfect)
        XCTAssertEqual(try node("cherubimon_vice").stage, .ultimate)

        for id in ["turuiemon", "andiramon_virus", "cherubimon_vice"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("turuiemon").evolutions.first(where: \.isDefault)?.to,
                       "andiramon_virus")
        XCTAssertEqual(try node("andiramon_virus").evolutions.first(where: \.isDefault)?.to,
                       "cherubimon_vice")

        // Every Rookie falls to the same Champion — that is what makes it the tree's junk branch.
        for rookie in ["pencvb_agumon", "pencvb_gabumon", "plotmon", "herissmon"] {
            XCTAssertEqual(try node(rookie).evolutions.first(where: \.isDefault)?.to, "turuiemon")
        }
        // And every Champion falls to the same Perfect — every one that has an out-edge at all.
        // US-149 hung BetelGammamon over Gammamon and left it a leaf until the Adult sweeps; a
        // rung-at-a-time sweep always opens the rung above as leaves, which is the same guard
        // US-148 had to add to the Nightmare Soldiers tree.
        for champion in graph.nodes.filter({ $0.line == line && $0.stage == .adult
                                             && !$0.evolutions.isEmpty }) {
            XCTAssertEqual(champion.evolutions.first(where: \.isDefault)?.to, "andiramon_virus",
                           "\(champion.id) does not fall to this tree's junk Perfect")
        }

        // The document is silent about all three, and this is the WHOLE-file grep US-140's notes
        // insist on rather than a section one: a name a later section draws cannot be spent on
        // junk, and this being the last section there is no later one — but the earlier ten could
        // have drawn any of them.
        let text = try document()
        for name in ["Turuiemon", "Andiramon", "Antylamon", "Lopmon", "Cherubimon (Vice)"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the tree document after all")
        }
        // Its Virtue counterpart, by contrast, IS drawn — as this tree's own earned Mega.
        XCTAssertTrue(text.contains("Cherubimon (Virtue)"))
        XCTAssertEqual(try node("cherubimon_virtue").line, line)
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesTuruiemon() throws {
        for rookie in ["pencvb_agumon", "pencvb_gabumon", "plotmon", "herissmon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "turuiemon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The junk Champion keeps one way back UP, so a player who neglected a Rookie and then worked
    /// is not locked out of the tree — the same shape US-138 gave PlatinumScumon, US-139 gave
    /// Diginorimon, US-140 gave Gokimon, US-141 gave Zassoumon and US-142 gave Raremon. Unlike
    /// US-141's and US-142's this climb is NOT a Wikimon arrow, and the node's `comment` says so:
    /// it is flavour, Turuiemon being a Beast Man and Asuramon heading the Beast Man thread here.
    func testTheJunkChampionKeepsOneEarnedWayBackIntoTheTree() throws {
        // US-157 gave Turuiemon a SECOND earned climb, Andiramon Data — the one arrow on this
        // node that Wikimon actually bolds — so what is pinned is that the flavour way back is
        // still there and still earned, not that it is the only one.
        let earned = try node("turuiemon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["pencvb_asuramon", "andiramon_data"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the way back must be earned, not free")

        // And that leaves Asuramon with two parents, the earned one and the way back.
        XCTAssertEqual(Set(graph.parents(of: "pencvb_asuramon").map(\.id)),
                       ["pencvb_leomon", "turuiemon"])
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
            ("pencvb_agumon", [(.strength, "pencvb_greymon"), (.stamina, "pencvb_leomon")]),
            ("pencvb_gabumon", [(.strength, "pencvb_garurumon"), (.spirit, "pencvb_angemon")]),
            ("plotmon", [(.vitality, "pencvb_tailmon"), (.spirit, "pencvb_wizarmon")]),
            ("herissmon", [(.stamina, "filmon")]),
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
        for (energy, expected) in [(EnergyType.vitality, "pencvb_agumon"),
                                   (.strength, "pencvb_gabumon"),
                                   (.spirit, "plotmon"),
                                   (.stamina, "herissmon")] {
            var totals = EnergyTotals.zero
            totals[energy] = 150
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: try node("nyaromon"), stageEnergy: totals,
                                                dominant: energy, careMistakes: 0, battleWins: 0,
                                                conditions: met),
                expected, "a well-raised \(energy.rawValue) Nyaromon does not reach \(expected)")
        }
    }

    /// Each branching node's earned edges need distinct dominant types, or one of them is
    /// unreachable — `EvolutionEngine` picks on the dominant energy first and two branches sharing
    /// one would make the second dead data.
    func testEveryBranchingNodeInTheLineUsesDistinctEnergies() throws {
        for id in ["nyaromon", "pencvb_agumon", "pencvb_gabumon", "plotmon", "herissmon",
                   "turuiemon"] {
            let earned = try node(id).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(id) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(id) offers two branches on the same energy")
        }
    }

    /// US-138's Angoramon, US-139's Jellymon, US-141's Pteromon and US-142's Junkmon were the
    /// document's "Rookie (Unlockable Slot)", and each got its tree's one conditioned In-Training
    /// edge. Herissmon is the fifth, and the shape holds: the `nyaromon -> herissmon` edge is the
    /// only one out of the In-Training rung gated on anything more than dominant energy.
    func testTheUnlockableSlotIsTheOnlyConditionedInTrainingEdge() throws {
        let nyaromon = try node("nyaromon")
        XCTAssertEqual(nyaromon.evolutions.count, 4, "one edge per Rookie the section draws")

        for edge in nyaromon.evolutions {
            XCTAssertNotNil(edge.requiredEnergy)
            if edge.to == "herissmon" {
                XCTAssertFalse(edge.conditions.isEmpty, "the unlockable slot must be unlocked")
                XCTAssertFalse(edge.isDefault)
            } else {
                XCTAssertTrue(edge.conditions.isEmpty,
                              "\(edge.to) is conditioned, but only the spare slot is unlockable")
            }
        }

        XCTAssertTrue(try virusBustersSection().contains("Rookie (Unlockable Slot): Herissmon"))
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

        XCTAssertTrue(try comment(on: "heriss_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "heriss_digitama").contains("14_farmland"),
                      "the egg must name the map that actually drops it")
        XCTAssertTrue(try comment(on: "turuiemon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")
        XCTAssertTrue(try comment(on: "turuiemon").contains("Wikimon"),
                      "the junk chain must name the reference its arrows came from")

        // The one node that carries two of the document's rungs.
        XCTAssertTrue(try comment(on: "holyangemon").contains("MagnaAngemon"))

        // The renamings, each recorded on the node that carries the substitute spelling.
        XCTAssertTrue(try comment(on: "yukimibotamon").contains("SnowBotamon"))
        XCTAssertTrue(try comment(on: "plotmon").contains("Salamon"))
        XCTAssertTrue(try comment(on: "pencvb_tailmon").contains("Gatomon"))
        XCTAssertTrue(try comment(on: "pencvb_wizarmon").contains("Wizardmon"))
        XCTAssertTrue(try comment(on: "stiffilmon").contains("Stefilmon"))
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
        for node in graph.nodes
        where node.line == line && !node.evolutions.isEmpty
            && (node.stage == .child || node.stage == .adult) {
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

    /// The last of the eleven device trees, stated as the claim the whole of Phase E's first half
    /// was for: every `### Version` section of the tree document now has a line in the graph.
    func testEveryDeviceSectionOfTheDocumentNowHasALine() throws {
        let sections = try document().components(separatedBy: "\n### ").dropFirst().count
        XCTAssertEqual(sections, 11, "the document draws eleven device trees")

        // Eleven device lines plus `palmon`, what is left of the US-008 seed. Asserted as a
        // SUBSET rather than as a total since US-144: Phase E's orphan sweeps open lines that no
        // device section draws, so a total would fail on every one of the twenty-six and say
        // nothing about the eleven this test is for.
        let deviceLines: Set<String> = ["dmc-v1", "dmc-v2", "dmc-v3", "dmc-v4", "dmc-v5",
                                        "penc-nsp", "penc-ds", "penc-nso", "penc-wg", "penc-me",
                                        "penc-vb"]
        XCTAssertTrue(deviceLines.isSubset(of: Set(graph.nodes.map(\.line))),
                      "a device section has lost its line")
        XCTAssertNotNil(graph.nodes.first { $0.line == "palmon" })
    }
}
