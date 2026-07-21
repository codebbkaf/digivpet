import Foundation
import UIKit
import XCTest

@testable import DigiVPet

/// US-116 — the shipped map catalog.
///
/// The whole point of the file being data is that it can be retuned without a build, so these
/// tests pin the things a retune must NOT break: the sixteen maps, their art, the FR-6 tiers and
/// step totals, and the single linear unlock chain.
final class MapCatalogTests: XCTestCase {

    // MARK: - The shipped file

    /// THE AC: `MapCatalog.bundled` decodes and holds exactly sixteen maps — one per `NN_*`
    /// imageset, which is the complete set of map art that ships (FR-4, and the PRD's non-goal
    /// "no new map art").
    func testBundledCatalogHoldsExactlySixteenMaps() throws {
        let catalog = try MapCatalog.load()

        XCTAssertEqual(catalog.maps.count, 16)
        XCTAssertEqual(MapCatalog.bundled.maps.count, 16)
    }

    func testMapIdsAreUnique() throws {
        let ids = try MapCatalog.load().maps.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// THE AC: every `assetName` resolves to a real image at runtime. `UIImage(named:)` is the same
    /// lookup `Image(_:)` does, so a name that drifted from `Assets.xcassets` fails here instead of
    /// drawing an empty room behind the Digimon.
    func testEveryAssetNameResolvesToAnImage() throws {
        for map in try MapCatalog.load().maps {
            XCTAssertFalse(map.assetName.isEmpty, "\(map.id) names no art")
            XCTAssertNotNil(
                UIImage(named: map.assetName),
                "\(map.id) names an imageset that is not in Assets.xcassets: \(map.assetName)")
        }
    }

    /// And the art is drawable through the US-115 layer that actually paints it — a name that is
    /// in the catalog but that `MapBackgroundView` would decline to draw is a map with no room.
    func testEveryMapIsDrawableByTheBackgroundLayer() throws {
        for map in try MapCatalog.load().maps {
            XCTAssertTrue(
                MapBackgroundLayout.shouldDraw(assetName: map.assetName), map.id)
        }
    }

    // MARK: - The FR-6 table

    /// THE AC, spelled out rather than derived: the order, the tiers and the step totals are the
    /// PRD's table verbatim. Deriving them from the file would make this test agree with whatever
    /// the file happens to say, which is the one thing it must not do.
    func testTiersOrderAndStepTotalsMatchTheTable() throws {
        let expected: [(id: String, tier: Int, totalSteps: Int)] = [
            ("01_grassland", 1, 3000),
            ("14_farmland", 1, 5000),
            ("02_river", 2, 8000),
            ("08_jungle", 2, 10000),
            ("09_lake", 2, 12000),
            ("04_desert", 3, 16000),
            ("07_mountains", 3, 18000),
            ("16_iceland", 3, 20000),
            ("03_ocean", 3, 22000),
            ("05_wasteland", 4, 26000),
            ("06_industrial", 4, 28000),
            ("13_factory_town", 4, 30000),
            ("10_city_dusk", 4, 32000),
            ("15_dungeon", 5, 38000),
            ("11_city_night", 5, 42000),
            ("12_cyberpunk", 5, 50000),
        ]

        let maps = try MapCatalog.load().maps
        XCTAssertEqual(maps.count, expected.count)

        for (map, want) in zip(maps, expected) {
            XCTAssertEqual(map.id, want.id)
            XCTAssertEqual(map.assetName, want.id, "\(map.id) draws another map's art")
            XCTAssertEqual(map.tier, want.tier, want.id)
            XCTAssertEqual(map.totalSteps, want.totalSteps, want.id)
        }
    }

    /// A map is a distance to walk, so it has to be one: a zero-step map would be finished the
    /// moment it was selected, and the maps get longer as they get harder.
    func testMapsGetLongerAndNeverHaveZeroLength() throws {
        let maps = try MapCatalog.load().maps

        for map in maps {
            XCTAssertGreaterThan(map.totalSteps, 0, map.id)
            XCTAssertTrue((1...5).contains(map.tier), "\(map.id) is at tier \(map.tier)")
        }
        for (earlier, later) in zip(maps, maps.dropFirst()) {
            XCTAssertLessThan(earlier.totalSteps, later.totalSteps, "\(later.id) is not longer")
            XCTAssertLessThanOrEqual(earlier.tier, later.tier, "\(later.id) drops a tier")
        }
    }

    /// Every map is named, and named SHORTLY: the US-120 strip puts the name and a progress figure
    /// on one line of a 41mm watch.
    func testEveryMapHasAShortDisplayName() throws {
        for map in try MapCatalog.load().maps {
            XCTAssertFalse(map.displayName.isEmpty, map.id)
            XCTAssertLessThanOrEqual(map.displayName.count, 16, map.displayName)
        }
    }

    // MARK: - The unlock chain

    /// THE AC: `unlockedBy` is a single linear chain — exactly one map is open from the start and
    /// every other names the map immediately before it. A branch or a second entry point would
    /// make the US-119 list's one-line "Finish <previous map name>" a lie.
    func testTheUnlockChainIsLinear() throws {
        let maps = try MapCatalog.load().maps

        XCTAssertNil(maps[0].unlockedBy, "\(maps[0].id) should be open from the start")
        for (earlier, later) in zip(maps, maps.dropFirst()) {
            XCTAssertEqual(later.unlockedBy, earlier.id, "\(later.id) does not follow \(earlier.id)")
        }

        XCTAssertEqual(maps.filter { $0.unlockedBy == nil }.count, 1, "more than one starting map")
        XCTAssertEqual(try MapCatalog.load().startingMap?.id, "01_grassland")
    }

    /// Following the chain from the start reaches every map. Belt and braces on the test above: a
    /// chain can be linear pair-by-pair and still strand a map if the file is reordered.
    func testEveryMapIsReachableFromTheStartingMap() throws {
        let catalog = try MapCatalog.load()
        let successors = Dictionary(
            catalog.maps.compactMap { map in map.unlockedBy.map { ($0, map) } },
            uniquingKeysWith: { first, _ in first })

        var reached: [String] = []
        var current = catalog.startingMap
        while let map = current, !reached.contains(map.id) {
            reached.append(map.id)
            current = successors[map.id]
        }

        XCTAssertEqual(reached.count, catalog.maps.count, "unreachable maps: \(reached)")
    }

    // MARK: - What lives in a map

    /// Every map has somewhere to fight and something to find. An empty pool would leave US-122's
    /// opponent pick with nothing to draw from on that map.
    func testEveryMapHasOpponentsAndDigitama() throws {
        for map in try MapCatalog.load().maps {
            XCTAssertFalse(map.opponentPool.isEmpty, "\(map.id) has no opponents")
            XCTAssertFalse(map.digitamaSlots.isEmpty, "\(map.id) has no Digitama")
        }
    }

    /// FR-12: all 57 Digitama on disk are placed, and none is placed twice — an egg in two maps
    /// would be findable in whichever the player reached first, which is not what "each appears in
    /// exactly one map" means.
    func testEveryDigitamaIsPlacedExactlyOnce() throws {
        let placed = try MapCatalog.load().maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        let onDisk = Roster.bundled.entries(at: .digitama).map(\.id)

        XCTAssertEqual(placed.count, Set(placed).count, "a Digitama is placed in two maps")
        XCTAssertEqual(Set(placed), Set(onDisk), "unplaced: \(Set(onDisk).subtracting(placed))")
    }

    /// Every gate the player is asked to meet is one they can be TOLD about. The blank-hint rule is
    /// the US-117 validator's to enforce over the whole file; this is the shipped file honouring it
    /// from the day it lands, because a condition with no hint reads to a player as an egg that
    /// drops at random.
    func testEveryDigitamaConditionCanBeExplained() throws {
        for map in try MapCatalog.load().maps {
            for slot in map.digitamaSlots {
                XCTAssertFalse(slot.conditions.isEmpty, "\(slot.digitamaId) has no conditions")
                for condition in slot.conditions {
                    XCTAssertFalse(
                        condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(slot.digitamaId) has a condition with no hint")
                    XCTAssertNotNil(
                        condition.knownMetric,
                        "\(slot.digitamaId) names an unknown metric: \(condition.metric)")
                }
            }
        }
    }

    // MARK: - Decoding

    /// The optional fields really are optional: the first map carries no `unlockedBy`, and a map
    /// authored with neither a pool nor slots decodes to empty lists rather than failing the load.
    func testOmittedFieldsDecodeToTheirEmptyValue() throws {
        let json = Data(
            """
            {"maps": [
              {"id": "x", "displayName": "X", "assetName": "01_grassland",
               "tier": 1, "totalSteps": 100}
            ]}
            """.utf8)

        let catalog = try JSONDecoder().decode(MapCatalog.self, from: json)
        let map = try XCTUnwrap(catalog.map(id: "x"))

        XCTAssertNil(map.unlockedBy)
        XCTAssertEqual(map.opponentPool, [])
        XCTAssertEqual(map.digitamaSlots, [])
    }

    /// A map with no length or no art is a broken file, not a map with defaults — it fails the
    /// decode, which `bundled` turns into a launch trap naming the file.
    func testAMapMissingARequiredFieldFailsTheDecode() {
        let json = Data(
            """
            {"maps": [{"id": "x", "displayName": "X", "assetName": "01_grassland", "tier": 1}]}
            """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MapCatalog.self, from: json))
    }

    /// A bundle with no `maps.json` throws the named error rather than trapping — that is what
    /// makes `load(from:)` usable in a test at all.
    func testLoadingFromABundleWithoutTheFileThrows() {
        XCTAssertThrowsError(try MapCatalog.load(from: Bundle(for: MapCatalogTests.self))) { error in
            XCTAssertEqual(error as? MapCatalog.LoadError, .fileNotBundled)
        }
    }

    // MARK: - Lookup

    func testLookupFindsAMapByIdAndMissesOnAnUnknownOne() throws {
        let catalog = try MapCatalog.load()

        XCTAssertEqual(catalog.map(id: "12_cyberpunk")?.displayName, "Cyberpunk")
        XCTAssertNil(catalog.map(id: "17_moonbase"))
    }

    func testMapsAtATierAreTheOnesAtThatTier() throws {
        let catalog = try MapCatalog.load()

        XCTAssertEqual(catalog.maps(atTier: 1).map(\.id), ["01_grassland", "14_farmland"])
        XCTAssertEqual(
            catalog.maps(atTier: 5).map(\.id), ["15_dungeon", "11_city_night", "12_cyberpunk"])
        XCTAssertEqual(catalog.maps(atTier: 9), [])
    }
}
