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
        // `dmcv1_shinmonzaemon` is US-133's line-scoped ShinMonzaemon, the piyo_yuramon pattern:
        // one roster entry, two nodes, so the second id is an alias with no entry of its own.
        XCTAssertEqual(aliases.sorted(),
                       ["dmcv1_shinmonzaemon", "extyranomon", "piyo_tanemon", "piyo_yuramon"])

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
