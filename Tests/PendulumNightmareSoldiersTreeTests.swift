import XCTest
@testable import DigiVPet

/// US-140: the Pendulum Color V3 Nightmare Soldiers tree, wired end to end.
///
/// Source: `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, Part 2, "Version 3:
/// Nightmare Soldiers (NSo)", line 124. Every test here reads the REAL `evolutions.json`.
///
/// The third Phase E tree with no seed line behind it, and the one where the respelling problem is
/// worst: FIFTEEN of the section's twenty-eight names are filed under a spelling the document does
/// not use. Six of those the document disambiguates itself, in brackets — Tapirmon (Bakumon),
/// DemiDevimon (PicoDevimon), Apemon (Hanumon), SkullMeramon (DeathMeramon), Myotismon (Vamdemon)
/// and PetitMeramon. The other NINE it does not, and every one of them would have been reported
/// absent by a `find` on the document's spelling alone: Candlemon/Candmon, Wizardmon/Wizarmon,
/// Mammothmon/Mammon, SkullMammothmon/SkullMammon, Pumpkinmon/Pumpmon,
/// NoblePumpkinmon/NoblePumpmon, VenomMyotismon/VenomVamdemon, Piedmon/Piemon and
/// Soloogamon/Soloogarmon. `testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpelling
/// TheArtUses` is what pins that.
///
/// Two names really are absent: **Loogamon** and **Helloogamon**, the Rookie and Champion of the
/// unlockable sixth slot. See `testTheTwoAbsentNamesAreAbsentFromTheWholeSpritePack`.
final class PendulumNightmareSoldiersTreeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let line = "penc-nso"

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

    /// The tree as the document writes it, less the two names with no sheet. `Fresh` is Baby I,
    /// `In-Training` is Baby II, `Rookie` is Child, `Champion` is Adult, the document's `Ultimate`
    /// is Perfect and its `Mega` is this app's `Ultimate-Super Ultimate`.
    private static let sectionMembers: [(id: String, stage: Stage)] = [
        ("mokumon", .babyI),
        ("petimeramon", .babyII),
        ("bakumon", .child),
        ("candmon", .child),
        ("picodevimon", .child),
        ("hanumon", .adult),
        ("pencnso_garurumon", .adult),
        ("pencnso_meramon", .adult),
        ("wizarmon", .adult),
        ("pencnso_devimon", .adult),
        ("pencnso_bakemon", .adult),
        ("dokugumon", .adult),
        ("mammon", .perfect),
        ("pencnso_weregarurumon", .perfect),
        ("deathmeramon", .perfect),
        ("pencnso_pumpmon", .perfect),
        ("vamdemon", .perfect),
        ("phantomon", .perfect),
        ("soloogarmon", .perfect),
        ("pencnso_skullmammon", .ultimate),
        ("pencnso_metalgarurumon", .ultimate),
        ("pencnso_boltmon", .ultimate),
        ("pencnso_noblepumpmon", .ultimate),
        ("venomvamdemon", .ultimate),
        ("piemon", .ultimate),
        ("fenriloogamon", .ultimate),
    ]

    func testEveryNameInTheSectionIsANodeOnTheCorrectStageInTheNightmareSoldiersLine() throws {
        XCTAssertEqual(Self.sectionMembers.count, 26,
                       "the section draws twenty-eight Digimon, two of which have no sheet")
        for (id, stage) in Self.sectionMembers {
            let node = try self.node(id)
            XCTAssertEqual(node.stage, stage, "\(id) is on the wrong rung")
            XCTAssertEqual(node.line, line, "\(id) is not in the Nightmare Soldiers tree")
            XCTAssertFalse(node.dexOnly, "\(id) has no animated sheet and cannot be playable")
        }
    }

    /// AC11's other half: fifteen of the section's names are not the names the ART is filed under,
    /// and nine of those return NOTHING at all to a `find -iname` on the document's spelling —
    /// which is what makes this the tree where taking the document at face value would have cost
    /// the most. Every substitute was searched for over the whole pack before it was accepted.
    ///
    /// Unlike US-139's, none of these is a dexOnly-twin case: no document spelling here resolves to
    /// an idle-only entry. They are dub names (Mammothmon, Wizardmon, Pumpkinmon, Piedmon,
    /// Myotismon) and alternate romanizations (Candmon, PetiMeramon), and the substitution is the
    /// same one every time — wire the Digimon under the spelling its sheet uses.
    ///
    /// The asserted direction matters: it is not "this id exists" but "the document's spelling has
    /// no PLAYABLE roster entry of its own", which is the thing that would make the substitution
    /// wrong.
    func testEveryNameInTheSectionResolvesToAPlayableSheetUnderTheSpellingTheArtUses() throws {
        // The document's spelling -> the id actually wired.
        let renamed = [("PetitMeramon", "petimeramon"), ("Tapirmon", "bakumon"),
                       ("Candlemon", "candmon"), ("DemiDevimon", "picodevimon"),
                       ("Apemon", "hanumon"), ("Wizardmon", "wizarmon"),
                       ("Mammothmon", "mammon"), ("SkullMammothmon", "pencnso_skullmammon"),
                       ("SkullMeramon", "deathmeramon"), ("Pumpkinmon", "pencnso_pumpmon"),
                       ("NoblePumpkinmon", "pencnso_noblepumpmon"), ("Myotismon", "vamdemon"),
                       ("VenomMyotismon", "venomvamdemon"), ("Piedmon", "piemon"),
                       ("Soloogamon", "soloogarmon")]

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
        for name in ["Mokumon", "Bakemon", "Dokugumon", "Garurumon", "WereGarurumon",
                     "MetalGarurumon", "Meramon", "Devimon", "Phantomon", "Boltmon",
                     "Fenriloogamon"] {
            XCTAssertNotNil(Roster.bundled.entries.first { $0.displayName == name && !$0.dexOnly },
                            "\(name) has no playable roster entry, so it cannot be wired")
        }
    }

    /// AC11 proper. Two of the section's twenty-eight names have NO sheet anywhere in the pack, and
    /// both are on the unlockable sixth slot's thread:
    ///
    /// - **Loogamon**, the Rookie. `find -iname '*loog*'` over the whole pack returns exactly three
    ///   files and none of them is a Child.
    /// - **Helloogamon**, the Champion. `find -iname '*hell*'` returns only Shellmon and
    ///   MoriShellmon. Wikimon lists Helloogarmon as a Digimon Loogarmon evolves INTO, so it is a
    ///   real Digimon that this art pack simply does not draw.
    ///
    /// The rest of the thread survives because `Adult/Loogarmon.png` is the rung Wikimon puts
    /// directly above Loogamon — see `loogarmon`'s node comment.
    func testTheTwoAbsentNamesAreAbsentFromTheWholeSpritePack() throws {
        for absent in ["Loogamon", "Helloogamon"] {
            XCTAssertNil(Roster.bundled.entries.first { $0.displayName == absent },
                         "\(absent) IS in the roster after all and should be wired")
            XCTAssertNil(graph.node(id: absent.lowercased()))
        }

        // The document really does name both, so this records a gap rather than inventing one.
        let text = try document()
        XCTAssertTrue(text.contains("Rookie (Unlockable Slot 6): Loogamon"))
        XCTAssertTrue(text.contains("Champion: Helloogamon"))

        // The three rungs of that thread that DO have sheets are all wired.
        for id in ["loogarmon", "soloogarmon", "fenriloogamon"] {
            XCTAssertEqual(try node(id).line, line)
        }
    }

    // MARK: - AC3: every arrow in the section is an edge

    func testEveryArrowInTheSectionIsAnEdge() throws {
        XCTAssertTrue(try targets(of: "baku_digitama").contains("mokumon"))
        XCTAssertTrue(try targets(of: "mokumon").contains("petimeramon"))
        for rookie in ["bakumon", "candmon", "picodevimon"] {
            XCTAssertTrue(try targets(of: "petimeramon").contains(rookie),
                          "PetiMeramon does not reach \(rookie)")
        }

        // Rookie -> Champion, exactly as the document draws them.
        XCTAssertTrue(try targets(of: "bakumon").isSuperset(of: ["hanumon", "pencnso_garurumon"]))
        XCTAssertTrue(try targets(of: "candmon").isSuperset(of: ["pencnso_meramon", "wizarmon"]))
        XCTAssertTrue(try targets(of: "picodevimon")
            .isSuperset(of: ["pencnso_devimon", "pencnso_bakemon", "dokugumon"]))

        // Champion -> Ultimate -> Mega, every thread the document draws.
        let threads = [("hanumon", "mammon", "pencnso_skullmammon"),
                       ("pencnso_garurumon", "pencnso_weregarurumon", "pencnso_metalgarurumon"),
                       ("pencnso_meramon", "deathmeramon", "pencnso_boltmon"),
                       ("wizarmon", "pencnso_pumpmon", "pencnso_noblepumpmon"),
                       ("pencnso_devimon", "vamdemon", "venomvamdemon"),
                       ("pencnso_bakemon", "phantomon", "piemon"),
                       ("loogarmon", "soloogarmon", "fenriloogamon")]

        XCTAssertEqual(threads.count, 7, "the section draws seven Champion-to-Mega threads")
        for (champion, perfect, mega) in threads {
            XCTAssertTrue(try targets(of: champion).contains(perfect),
                          "\(champion) must reach \(perfect)")
            XCTAssertTrue(try targets(of: perfect).contains(mega), "\(perfect) must reach \(mega)")
            XCTAssertTrue(try node(mega).evolutions.isEmpty, "\(mega) is the top of its thread")
        }
    }

    /// The document writes ONE of its threads with two Champions on it —
    /// "Champion: Bakemon / Dokugumon -> Ultimate: Phantomon" — so the slash is an arrow from each
    /// of them into the same Perfect rather than a choice between two trees.
    func testTheSlashedChampionRowIsTwoChampionsOnOneThread() throws {
        XCTAssertTrue(try document().contains("Champion: Bakemon / Dokugumon -> Ultimate: Phantomon"))
        XCTAssertTrue(try targets(of: "pencnso_bakemon").contains("phantomon"))
        XCTAssertTrue(try targets(of: "dokugumon").contains("phantomon"))
        XCTAssertEqual(Set(graph.parents(of: "phantomon").map(\.id)),
                       ["pencnso_bakemon", "dokugumon", "gokimon"],
                       "Phantomon's parents are the document's two Champions plus the junk way back")
    }

    // MARK: - AC4: reachable from a Digitama, end to end

    /// The egg is a real ROSTER Digitama rather than a line-scoped one, and that is a playability
    /// requirement rather than taste: `maps.json` grants a Digitama by roster id, an alias has no
    /// roster entry, and a line whose egg can never drop is a line no player can start.
    func testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant() throws {
        let egg = try node("baku_digitama")
        XCTAssertEqual(egg.stage, .digitama)
        XCTAssertEqual(egg.line, line)
        XCTAssertNotNil(Roster.bundled.entry(id: egg.id), "the egg must be grantable")

        let slots = MapCatalog.bundled.maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        XCTAssertTrue(slots.contains(egg.id), "no map drops \(egg.id), so the line is unstartable")

        // One egg per line until US-144, which hangs `cand_digitama` off this line rather than opening a
        // one-node line for a species this tree already reaches. The line's OWN egg is still the
        // first of them, and still the one the rest of this file reasons about.
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id),
                       [egg.id, "cand_digitama", "picodevi_digitama", "vorvo_digitama"])
    }

    /// Since US-144 the seed is every Digitama of the line, not just this tree's own: the first
    /// orphan sweep gives a line a second egg where the species it belongs to is already wired
    /// here. What the test still means is unchanged — nothing in the line is stranded above the
    /// eggs — and `testTheLineIsRootedAtARealRosterDigitamaThatAMapCanActuallyGrant` is what pins
    /// which eggs those are.
    func testEveryNodeInTheLineIsReachableFromItsDigitama() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == line }.map(\.id)
        XCTAssertTrue(eggs.contains("baku_digitama"), "the line's own egg is gone")

        var reached = Set(eggs)
        var frontier = eggs
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let inLine = graph.nodes.filter { $0.line == line }.map(\.id)
        XCTAssertEqual(inLine.count, 49,
                       "US-147 hung Sunmon and Coronamon here, US-148 Firamon, US-149 Gotsumon and "
                           + "Icemon, US-150 PetitMamon, Vorvomon and Lavorvomon, US-154 Musyamon, "
                           + "US-155 ShimaUnimon, US-157 Archnemon and BlueMeramon, US-158 "
                           + "Fantomon, Flaremon and Apollomon")
        XCTAssertEqual(inLine.filter { !reached.contains($0) }, [],
                       "unreachable from any egg of the line, so not playable end to end")
    }

    func testTheLineCoversEveryRungOfTheLadder() {
        let stages = Set(graph.nodes.filter { $0.line == line }.map(\.stage))
        XCTAssertEqual(stages, [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
    }

    // MARK: - The ten line-scoped aliases

    /// Ten of this tree's thirty-one Digimon already had a node in another line, so ten are
    /// line-scoped: the piyo_yuramon pattern. Each is asserted to be the SAME Digimon — same art,
    /// same display name, same rung — under a second id, because the failure this guards against is
    /// an alias silently pointing at a different sheet from the Digimon it stands in for.
    ///
    /// Three of them are the first TRIPLES in the file: V2's Garurumon thread is drawn by the
    /// Pendulum V1 and V3 sections as well, so Garurumon, WereGarurumon and MetalGarurumon are each
    /// three nodes on one roster entry now.
    func testEveryLineScopedAliasIsTheSameDigimonAsThePlainIdItStandsIn() throws {
        let aliases: [(scoped: String, plain: String, ownedBy: String)] = [
            ("pencnso_garurumon", "garurumon", "dmc-v2"),
            ("pencnso_weregarurumon", "weregarurumon", "dmc-v2"),
            ("pencnso_metalgarurumon", "metalgarurumon", "dmc-v2"),
            ("pencnso_skullmammon", "skullmammon", "dmc-v2"),
            ("pencnso_meramon", "meramon", "dmc-v1"),
            ("pencnso_devimon", "devimon", "dmc-v1"),
            ("pencnso_bakemon", "bakemon", "dmc-v3"),
            ("pencnso_boltmon", "boltmon", "dmc-v4"),
            ("pencnso_pumpmon", "pumpmon", "penc-nsp"),
            ("pencnso_noblepumpmon", "noblepumpmon", "penc-nsp"),
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

        XCTAssertEqual(graph.nodes.filter { $0.id.hasPrefix("pencnso_") }.count, aliases.count,
                       "an alias was added or removed without updating this list")

        // The Garurumon thread was the file's first triple and is a QUADRUPLE since US-143: the V0
        // Virus Busters section draws Gabumon over Garurumon, WereGarurumon and MetalGarurumon too,
        // which is the fourth tree to draw that thread. This assertion is what caught it.
        for plain in ["garurumon", "weregarurumon", "metalgarurumon"] {
            let name = try node(plain).displayName
            let copies = graph.nodes.filter { $0.displayName == name }
            XCTAssertEqual(Set(copies.map(\.line)), ["dmc-v2", "penc-nsp", "penc-vb", line],
                           "\(plain) is drawn by four trees")
        }
    }

    /// Every one of the ten needs its own `elements.json` and `moves.json` entry as well as its
    /// node, and the move's `signatureName` must be globally unique — so it cannot simply be copied
    /// from the Digimon it aliases.
    func testEveryAliasCarriesItsOwnTypeAndItsOwnDistinctSignatureMove() throws {
        for node in graph.nodes where node.id.hasPrefix("pencnso_") {
            let plain = String(node.id.dropFirst("pencnso_".count))
            XCTAssertNotNil(ElementCatalog.bundled.types[node.id], "\(node.id) has no element")

            let mine = try XCTUnwrap(MoveCatalog.bundled.moves[node.id], "\(node.id) has no move")
            let theirs = try XCTUnwrap(MoveCatalog.bundled.moves[plain])
            XCTAssertNotEqual(mine.signatureName, theirs.signatureName,
                              "\(node.id) reuses \(plain)'s signature, which must be unique")
        }
    }

    /// `pencnso_pumpmon` is the sharpest case in the file of why a line-scoped alias is not merely
    /// tidiness: the SAME Digimon is Nature Spirits' invented junk Perfect and this tree's earned
    /// branch above Wizardmon. One node could not be both, because `EvolutionCriteriaTests` requires
    /// `pumpmon` to be a junk target and this story requires it to be gated behind two conditions.
    func testPumpmonIsJunkInNatureSpiritsAndEarnedHere() throws {
        XCTAssertEqual(try node("pumpmon").line, "penc-nsp")
        let junkEdge = try XCTUnwrap(
            graph.node(id: "symbareangoramon")?.evolutions.first { $0.to == "pumpmon" })
        XCTAssertTrue(junkEdge.isDefault, "Nature Spirits reaches Pumpmon by neglect")

        let earnedEdge = try XCTUnwrap(
            try node("wizarmon").evolutions.first { $0.to == "pencnso_pumpmon" })
        XCTAssertFalse(earnedEdge.isDefault, "Nightmare Soldiers must EARN its Pumpkinmon")
        XCTAssertFalse(earnedEdge.conditions.isEmpty)
    }

    // MARK: - The junk chain, which this document does not supply

    /// The five Digital Monster Color trees each name their own junk Champion. The Pendulum Color
    /// sections name NONE: they draw only the earned tree. Every Child and Adult in this app
    /// nonetheless needs an `isDefault` edge reachable by doing nothing, so US-140 chose a chain off
    /// sheets that were orphans, the way US-138 and US-139 did:
    /// Gokimon -> Darumamon -> Deathmon.
    func testTheJunkChainIsThisAppsChoiceAndRunsAllTheWayToAnUltimate() throws {
        XCTAssertEqual(try node("gokimon").stage, .adult)
        XCTAssertEqual(try node("darumamon").stage, .perfect)
        XCTAssertEqual(try node("deathmon").stage, .ultimate)

        for id in ["gokimon", "darumamon", "deathmon"] {
            XCTAssertEqual(try node(id).line, line)
        }
        XCTAssertEqual(try node("gokimon").evolutions.first(where: \.isDefault)?.to, "darumamon")
        XCTAssertEqual(try node("darumamon").evolutions.first(where: \.isDefault)?.to, "deathmon")

        // Every Rookie falls to the same Champion — that is what makes it the tree's junk branch.
        for rookie in ["bakumon", "candmon", "picodevimon"] {
            XCTAssertEqual(try node(rookie).evolutions.first(where: \.isDefault)?.to, "gokimon")
        }
        // And every Champion falls to the same Perfect — every one that has an out-edge at all.
        // US-148 hung Firamon over Coronamon and left it a leaf until the Adult sweeps, exactly as
        // US-147 left this line's Coronamon one; a rung-at-a-time sweep always opens the rung above
        // as leaves, so the guard is the same one the Child loop grew.
        for champion in graph.nodes.filter({ $0.line == line && $0.stage == .adult
                                             && !$0.evolutions.isEmpty }) {
            XCTAssertEqual(champion.evolutions.first(where: \.isDefault)?.to, "darumamon",
                           "\(champion.id) does not fall to this tree's junk Perfect")
        }

        // The section really is silent — none of the three is named anywhere in the tree markdown.
        let text = try document()
        for name in ["Gokimon", "Darumamon", "Deathmon"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the document after all")
        }

        // And the one that WAS: WaruMonzaemon was the first choice for the Perfect rung, and the
        // grep above is what caught it. The Version 5 Metal Empire section draws it over
        // Mekanorimon, so it is US-142's earned Ultimate and cannot be this tree's junk.
        //
        // This assertion was written as `XCTAssertNil(graph.node(id: "warumonzaemon"))` and was
        // MEANT to fail the day that story landed — the marker-test shape US-130 recorded. US-142
        // landed it, so it now states the thing it was always guarding: WaruMonzaemon is a node,
        // it belongs to the Metal Empire tree, and it is EARNED there rather than junk anywhere.
        XCTAssertTrue(text.contains("Ultimate: WaruMonzaemon"))
        let warumonzaemon = try XCTUnwrap(graph.node(id: "warumonzaemon"))
        XCTAssertEqual(warumonzaemon.line, "penc-me")
        XCTAssertNotEqual(warumonzaemon.line, line, "it must not have landed in this tree after all")
        let intoIt = graph.parents(of: "warumonzaemon").flatMap { parent in
            parent.evolutions.filter { $0.to == "warumonzaemon" }
        }
        XCTAssertFalse(intoIt.isEmpty)
        XCTAssertTrue(intoIt.allSatisfy { !$0.isDefault },
                      "WaruMonzaemon is somebody's junk fallback after all")
    }

    /// Stated through the engine rather than by reading the file: a Digimon of this tree whose owner
    /// did nothing at all still evolves, and what it becomes is junk.
    func testARookieThatDidNothingBecomesGokimon() throws {
        for rookie in ["bakumon", "candmon", "picodevimon"] {
            let target = EvolutionEngine.scheduledEvolutionTarget(
                for: try node(rookie),
                stageEnergy: .zero,
                dominant: nil,
                careMistakes: 0,
                battleWins: 0,
                stageEnteredAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 60 * 24 * 60 * 60),
                conditions: .unknown)

            XCTAssertEqual(target, "gokimon", "\(rookie) does not fall to this tree's junk")
        }
    }

    /// The junk Champion keeps one way back UP, so a player who neglected a Rookie and then worked
    /// is not locked out of the tree — the same shape US-138 gave PlatinumScumon and US-139 gave
    /// Diginorimon.
    func testTheJunkChampionKeepsOneEarnedWayBackIntoTheTree() throws {
        let earned = try node("gokimon").evolutions.filter { !$0.isDefault }
        XCTAssertEqual(earned.map(\.to), ["phantomon"])
        XCTAssertFalse(earned[0].conditions.isEmpty, "the way back must be earned, not free")
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
            ("bakumon", [(.strength, "hanumon"), (.vitality, "pencnso_garurumon"),
                         (.stamina, "loogarmon")]),
            ("candmon", [(.strength, "pencnso_meramon"), (.spirit, "wizarmon")]),
            ("picodevimon", [(.spirit, "pencnso_devimon"), (.vitality, "pencnso_bakemon"),
                             (.stamina, "dokugumon")]),
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
    /// the second dead data. The same is true of the In-Training rung, which forks three ways here.
    func testEveryBranchingNodeInTheLineUsesDistinctEnergies() throws {
        for id in ["petimeramon", "bakumon", "candmon", "picodevimon"] {
            let earned = try node(id).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(id) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(id) offers two branches on the same energy")
        }
    }

    /// US-138's Angoramon and US-139's Jellymon were the document's "Rookie (Unlockable Slot 6)",
    /// and each got the tree's one conditioned In-Training edge. This tree's slot-6 Rookie is
    /// Loogamon, which has no sheet — so there is no fourth Rookie and every edge out of the
    /// In-Training rung is gated on dominant energy alone. Asserted so that adding a Loogamon sheet
    /// later shows up as a decision to revisit rather than as silence.
    /// US-149 hung a FOURTH edge here — Gotsumon, whose only free cited In-Training was Peti
    /// Meramon — and that edge IS conditioned, because an orphan sweep's branches are earned. So
    /// the claim is scoped to the three Rookies the tree itself draws rather than to the rung: the
    /// TREE conditions nothing, and a later sweep adding to the same node does not change that.
    func testTheInTrainingRungIsUnconditionedBecauseTheUnlockableRookieHasNoSheet() throws {
        let petimeramon = try node("petimeramon")
        let drawnByTheTree = ["bakumon", "candmon", "picodevimon"]
        let treeEdges = petimeramon.evolutions.filter { drawnByTheTree.contains($0.to) }
        XCTAssertEqual(treeEdges.count, 3, "one edge per Rookie this tree can draw")
        for edge in treeEdges {
            XCTAssertTrue(edge.conditions.isEmpty,
                          "\(edge.to) is conditioned, but this tree has no unlockable slot")
            XCTAssertNotNil(edge.requiredEnergy)
        }
        XCTAssertNil(Roster.bundled.entries.first { $0.displayName == "Loogamon" })
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

        XCTAssertTrue(try comment(on: "baku_digitama").contains("maps.json"),
                      "the egg must say why it is a roster id rather than a scoped one")
        XCTAssertTrue(try comment(on: "gokimon").contains("US-061"),
                      "the invented junk Champion must say where the rule came from")
        XCTAssertTrue(try comment(on: "loogarmon").contains("Wikimon"),
                      "the only rehomed node must name the reference it came from")
        XCTAssertTrue(try comment(on: "loogarmon").contains("Helloogamon"),
                      "the rehoming must name the absent Champion it stands in for")

        // The renamings, each recorded on the node that carries the substitute spelling.
        XCTAssertTrue(try comment(on: "petimeramon").contains("PetitMeramon"))
        XCTAssertTrue(try comment(on: "candmon").contains("Candlemon"))
        XCTAssertTrue(try comment(on: "wizarmon").contains("Wizardmon"))
        XCTAssertTrue(try comment(on: "mammon").contains("Mammothmon"))
        XCTAssertTrue(try comment(on: "vamdemon").contains("Myotismon"))
        XCTAssertTrue(try comment(on: "piemon").contains("Piedmon"))
        XCTAssertTrue(try comment(on: "pencnso_pumpmon").contains("Pumpkinmon"))
        // And the one name that needed checking rather than substituting.
        XCTAssertTrue(try comment(on: "phantomon").contains("Fantomon"))
    }

    /// Every node of the line slices as a real 48x64 sheet (48x16 for the egg). Stronger than "the
    /// file exists": an idle-only 16x16 sprite fails here rather than shipping as a Digimon that
    /// cannot animate, which is exactly the trap thirteen respelled names set.
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

    /// TWENTY-ONE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 713 before, 692 after. Asserted rather than merely noted, because the count is the one claim
    /// in `notes` a later reader cannot re-derive from the diff.
    ///
    /// Twenty-one of the thirty-one new nodes carry a plain roster id and so remove an orphan; the
    /// other ten are line-scoped aliases of Digimon that were already wired, and an alias removes
    /// nothing — the roster entry it shares was never orphaned. That ratio is the worst of any tree
    /// so far, and it is what the V3 section is: a Nightmare Soldiers device that borrows the whole
    /// Garurumon thread from V2 and its Pumpkinmon thread from the V1 Pendulum.
    func testTheTwentyOneOrphansThisStoryRemovedAreTheNodesWithRosterIds() throws {
        let removed = ["baku_digitama", "mokumon", "petimeramon", "bakumon", "candmon",
                       "picodevimon", "hanumon", "loogarmon", "wizarmon", "dokugumon", "gokimon",
                       "mammon", "soloogarmon", "deathmeramon", "vamdemon", "phantomon",
                       "darumamon", "fenriloogamon", "venomvamdemon", "piemon", "deathmon"]
        XCTAssertEqual(removed.count, 21)

        for id in removed {
            let node = try self.node(id)
            XCTAssertEqual(node.line, line)
            XCTAssertNotNil(Roster.bundled.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(node.evolutions.isEmpty && graph.parents(of: id).isEmpty,
                           "\(id) is still an orphan")
        }

        // `cand_digitama` is US-144's, not this story's, so it is excluded rather than counted.
        // `sunmon` and `coronamon` are US-147's and `firamon` is US-148's, excluded the same way.
        // `petitmamon`, `vorvomon` and `lavorvomon` are US-150's, excluded the same way.
        let sweepEggs: Set<String> = ["cand_digitama", "picodevi_digitama", "vorvo_digitama",
                                      "sunmon", "coronamon", "firamon",
                                      "gotsumon", "icemon",
                                      "petitmamon", "vorvomon", "lavorvomon",
                                      "musyamon", "shimaunimon",
                                      // US-157's, hung off Dokugumon and Meramon.
                                      "archnemon", "bluemeramon",
                                      // US-158's, hung off Wizarmon and the leaf Firamon US-148
                                      // left, plus the Apollomon that finished Coronamon's thread.
                                      "fantomon", "flaremon", "apollomon"]
        XCTAssertEqual(graph.nodes.filter { $0.line == line && !sweepEggs.contains($0.id) }.count, 31)
        XCTAssertEqual(graph.nodes.filter { $0.line == line && Roster.bundled.entry(id: $0.id) == nil }.count,
                       10, "the ten aliases, which remove no orphan")
    }
}
