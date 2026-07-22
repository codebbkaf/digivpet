import Foundation
import XCTest

@testable import DigiVPet

final class RosterTests: XCTestCase {

    // MARK: - The shipped file

    /// The AC: the whole roster is bundled and complete. 1,022 is the number of sprites on disk —
    /// `scripts/build_roster.py` emits exactly one entry per file and skips nothing, so a drift
    /// here means either a sprite appeared or the generator started dropping entries.
    func testBundledRosterHasEveryEntry() throws {
        let roster = try Roster.load()

        XCTAssertEqual(roster.entries.count, 1022)
        XCTAssertEqual(roster.entries.count, Roster.bundled.entries.count)
    }

    func testEntryIdsAreUnique() throws {
        let ids = try Roster.load().entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// The AC, and the reason this is a test rather than an eyeball: 1,022 paths cannot be
    /// checked by inspection, and a wrong one is invisible until that Digimon's tile draws blank.
    /// Resolution matches the app's — under the stage folder, or the flat `Idle Frame Only`
    /// folder for a dexOnly entry, whose art is not filed by stage.
    func testEverySpriteFileExistsOnDisk() throws {
        for entry in try Roster.load().entries {
            let folder = entry.dexOnly ? SpriteLoader.idleFrameOnlyFolder : entry.stage.rawValue
            XCTAssertNotNil(
                SpriteLoader.url(stage: folder, name: entry.spriteFile),
                "\(entry.id) names art that is not bundled: \(folder)/\(entry.spriteFile).png")
        }
    }

    /// Decoding at all proves no entry carries `"stage": null` — `stage` is non-optional, so one
    /// null would have thrown. This pins the consequence that matters: every entry lands under a
    /// real Dex heading, including the idle-only Digimon the sprite tree says nothing about.
    func testEveryEntryHasARealStage() throws {
        let roster = try Roster.load()
        let byStage = Dictionary(grouping: roster.entries, by: \.stage).mapValues(\.count)

        XCTAssertEqual(byStage.values.reduce(0, +), roster.entries.count)
        for stage in Stage.allCases {
            XCTAssertGreaterThan(byStage[stage] ?? 0, 0, "no entry at stage \(stage.rawValue)")
        }
        // The idle-only Digimon whose stage exists in no artifact on disk and comes from
        // `scripts/dex_only_stages.json`. Poyomon is the PRD's named example.
        XCTAssertEqual(roster.entry(id: "poyomon")?.stage, .babyI)
        XCTAssertEqual(roster.entry(id: "poyomon")?.dexOnly, true)
        XCTAssertEqual(roster.entry(id: "ancientgreymon")?.stage, .ultimate)
    }

    /// The roster is a flat list of what exists, NOT a second copy of the graph. If either key
    /// ever appears here, the two files have started to overlap and the next reader will not know
    /// which one to author into.
    func testTheShippedFileCarriesNoLineAndNoEvolutions() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "roster", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(raw["entries"] as? [[String: Any]])

        XCTAssertEqual(entries.count, 1022)
        for entry in entries {
            let id = entry["id"] as? String ?? "?"
            XCTAssertNil(entry["line"], "\(id) carries a line — that belongs in evolutions.json")
            XCTAssertNil(entry["evolutions"], "\(id) carries evolutions — those belong in the graph")
            XCTAssertTrue(Set(entry.keys).isSubset(of: ["id", "displayName", "stage",
                                                        "spriteFile", "variant", "dexOnly"]),
                          "\(id) has unexpected keys: \(entry.keys.sorted())")
        }
    }

    /// The roster and the graph are separate files, but a Digimon in a line lives in both and the
    /// two must agree — otherwise a Dex tile and its evolution tree would disagree about the same
    /// Digimon's stage or art. Three graph nodes reuse another node's sprite under a second id
    /// (`piyo_tanemon` draws Tanemon) and correctly get no Dex tile of their own.
    func testGraphNodesAgreeWithTheirRosterEntry() throws {
        let roster = try Roster.load()
        var aliases: [String] = []
        var differentArt: [String] = []

        for node in try EvolutionGraph.load().nodes {
            guard let entry = roster.entry(id: node.id) else {
                aliases.append(node.id)
                continue
            }
            XCTAssertEqual(entry.stage, node.stage, "\(node.id): stage differs from the graph")
            XCTAssertEqual(entry.dexOnly, node.dexOnly, "\(node.id): dexOnly differs")
            if entry.spriteFile != node.spriteFile {
                differentArt.append(node.id)
            }
        }
        // `dmcv1_shinmonzaemon` is US-133's line-scoped ShinMonzaemon, `dmcv2_vademon` /
        // `dmcv2_ebemon` are US-134's line-scoped Vademon and Ebemon (the dmc-v5 line owns the
        // plain ids), and `dmcv4_palmon` is US-136's line-scoped Palmon (the palmon line owns
        // that one). All four are the piyo_yuramon pattern: one roster entry, two nodes, so the
        // second id is an alias with no entry of its own.
        //
        // The twelve `pencnsp_` ids are US-138's, and they are the same pattern at a scale no
        // earlier story needed: the Pendulum Color V1 Nature Spirits tree shares twelve of its
        // thirty Digimon with the Digital Monster Color trees — Botamon and Koromon with V1's
        // Fresh and In-Training, the whole Agumon-to-WarGreymon thread with V1, Leomon with V4,
        // and Kabuterimon/Garurumon/WereGarurumon/MetalGarurumon with V2. A node's `line` is
        // single-valued, so a Digimon in two trees is two nodes on one roster entry.
        //
        // The five `pencds_` ids are US-139's, and two of them are the first aliases in the file
        // whose PLAIN id belongs to another Pendulum tree rather than to a Digital Monster one:
        // Deep Savers draws MegaSeadramon and MetalSeadramon over Coelamon, and US-138 had already
        // given both plain ids to Nature Spirits.
        //
        // The ten `pencnso_` ids are US-140's Nightmare Soldiers tree, and they include the first
        // TRIPLE in the file: Garurumon, WereGarurumon and MetalGarurumon are drawn by the V2, V1
        // Pendulum and V3 Pendulum sections alike, so each of those three Digimon is now three
        // nodes on one roster entry. `pencnso_pumpmon` and `pencnso_noblepumpmon` are the second
        // pair whose plain id belongs to another Pendulum tree: US-138 chose Pumpmon as Nature
        // Spirits' invented JUNK Perfect and the V3 document draws it as an earned branch.
        //
        // The six `pencwg_` ids are US-141's Wind Guardians tree. Three of them are the first
        // three-rung THREAD to be scoped whole: Togemon, Lilimon and Rosemon have belonged to the
        // `palmon` line since US-008 and the V4 Pendulum draws all three over Floramon.
        // `pencwg_gerbemon` is the second Pumpmon case — junk in `dmc-v2`, earned here.
        //
        // The eight `pencme_` ids are US-142's Metal Empire tree. `pencme_greymon`,
        // `pencme_metalgreymon` and `pencme_wargreymon` make that thread the second TRIPLE in the
        // file, after US-140's Garurumon one — three trees draw Agumon's Champion and up.
        // `pencme_raremon` is the third Pumpmon case and the first where the plain id is junk in
        // BOTH lines: Raremon is `dmc-v5`'s junk Champion and this tree's too.
        //
        // The fifteen `pencvb_` ids are US-143's Virus Busters / ZERO tree, and they are HALF of
        // that tree — the worst ratio in the file, because the V0 device is the one every earlier
        // tree borrowed from. Both of the file's triples become QUADRUPLES here: Greymon /
        // MetalGreymon / WarGreymon are now drawn by `dmc-v1`, `penc-nsp`, `penc-me` and this
        // tree, and Garurumon / WereGarurumon / MetalGarurumon by `dmc-v2`, `penc-nsp`,
        // `penc-nso` and this tree.
        //
        // `diablomon_gerbemon` is US-160's and the first alias authored for a JUNK floor rather
        // than for a shared thread: `diablomon` needed a junk Perfect before Meicoomon could
        // branch, and every unused Perfect sheet left in the pack is a real Digimon rather than a
        // gag one — so the floor draws Gerbemon, which `dmc-v2` already owns as `gerbemon`.
        //
        // `vital_darumamon` and `xros_etemon` are US-161's, and they are the same junk-floor case
        // twice over: that story opened the Perfect rung on `vital` and on `xros`, the pack still
        // has no unused junk-flavoured Perfect sheet, and each floor is cited from its own line's
        // Champions — Darumamon from Kokeshimon, Etemon from Targetmon. `penc-nso` already owns
        // `darumamon` and `dmc-v3` already owns `etemon`.
        XCTAssertEqual(aliases.sorted(),
                       ["diablomon_gerbemon",
                        "dmcv1_shinmonzaemon", "dmcv2_ebemon", "dmcv2_vademon", "dmcv4_palmon",
                        "pencds_coelamon", "pencds_megaseadramon",
                        "pencds_metalseadramon", "pencds_seadramon", "pencds_whamon",
                        "pencme_andromon", "pencme_greymon", "pencme_hiandromon",
                        "pencme_metalgreymon", "pencme_mugendramon", "pencme_raremon",
                        "pencme_venomvamdemon", "pencme_wargreymon",
                        "pencnso_bakemon", "pencnso_boltmon", "pencnso_devimon",
                        "pencnso_garurumon", "pencnso_meramon", "pencnso_metalgarurumon",
                        "pencnso_noblepumpmon", "pencnso_pumpmon", "pencnso_skullmammon",
                        "pencnso_weregarurumon",
                        "pencnsp_agumon", "pencnsp_botamon", "pencnsp_garurumon",
                        "pencnsp_greymon", "pencnsp_kabuterimon", "pencnsp_koromon",
                        "pencnsp_leomon", "pencnsp_metalgarurumon", "pencnsp_metalgreymon",
                        "pencnsp_seadramon", "pencnsp_wargreymon", "pencnsp_weregarurumon",
                        "pencvb_agumon", "pencvb_angemon", "pencvb_angewomon",
                        "pencvb_asuramon", "pencvb_gabumon", "pencvb_garurumon",
                        "pencvb_greymon", "pencvb_leomon", "pencvb_metalgarurumon",
                        "pencvb_metalgreymon", "pencvb_saberleomon", "pencvb_tailmon",
                        "pencvb_wargreymon", "pencvb_weregarurumon", "pencvb_wizarmon",
                        "pencwg_birdramon", "pencwg_gerbemon", "pencwg_lilimon",
                        "pencwg_piyomon", "pencwg_rosemon", "pencwg_togemon",
                        "piyo_tanemon", "piyo_yuramon",
                        "vital_darumamon", "xros_etemon", "xros_hagurumon"])

        // The art tree really does hold BOTH `Hi-Andromon.png` and `HiAndromon.png`, so the
        // roster has an entry per file (`hi-andromon`, `hiandromon`) while the graph's
        // `hiandromon` node points at the hyphenated sheet on purpose (see its `comment`). One
        // known divergence, pinned so a second one shows up as a failure rather than as a Dex
        // tile quietly drawing different art from the evolution tree.
        XCTAssertEqual(differentArt, ["hiandromon"])
    }

    // MARK: - Decoding

    func testAnOmittedVariantAndDexOnlyDecodeToNilAndFalse() throws {
        let json = """
        {"entries": [{"id": "agumon", "displayName": "Agumon", "stage": "Child",
                      "spriteFile": "Agumon"}]}
        """
        let roster = try JSONDecoder().decode(Roster.self, from: Data(json.utf8))

        XCTAssertNil(roster.entries[0].variant)
        XCTAssertFalse(roster.entries[0].dexOnly)
    }

    func testVariantAndDexOnlyDecodeWhenPresent() throws {
        let json = """
        {"entries": [{"id": "poyomon", "displayName": "Poyomon", "stage": "Baby I",
                      "spriteFile": "Poyomon", "variant": "X", "dexOnly": true}]}
        """
        let roster = try JSONDecoder().decode(Roster.self, from: Data(json.utf8))

        XCTAssertEqual(roster.entries[0].variant, "X")
        XCTAssertTrue(roster.entries[0].dexOnly)
    }

    /// The AC: a null stage is REJECTED, not defaulted. The generator emits null for an entry it
    /// could not resolve, and defaulting one here would file that Digimon under a rung it is not
    /// on — silently, and forever, since nothing downstream would ever notice.
    func testANullStageFailsTheLoadRatherThanDefaulting() {
        let json = """
        {"entries": [{"id": "mystery", "displayName": "Mystery", "stage": null,
                      "spriteFile": "Poyomon"}]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(Roster.self, from: Data(json.utf8)))
    }

    func testAMissingStageKeyAlsoFailsTheLoad() {
        let json = """
        {"entries": [{"id": "mystery", "displayName": "Mystery", "spriteFile": "Poyomon"}]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(Roster.self, from: Data(json.utf8)))
    }

    func testLookupByIdAndByStage() throws {
        let roster = Roster(entries: [
            RosterEntry(id: "agumon", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            RosterEntry(id: "gabumon", displayName: "Gabumon", stage: .child, spriteFile: "Gabumon"),
            RosterEntry(id: "greymon", displayName: "Greymon", stage: .adult, spriteFile: "Greymon"),
        ])

        XCTAssertEqual(roster.entry(id: "gabumon")?.displayName, "Gabumon")
        XCTAssertNil(roster.entry(id: "nosuchmon"))
        XCTAssertEqual(roster.entries(at: .child).map(\.id), ["agumon", "gabumon"])
        XCTAssertEqual(roster.entries(at: .ultimate), [])
    }

    func testLoadFromABundleWithNoRosterThrows() {
        XCTAssertThrowsError(try Roster.load(from: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? Roster.LoadError, .fileNotBundled)
        }
    }
}
