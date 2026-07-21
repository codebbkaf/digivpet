import CoreGraphics
import UIKit
import XCTest

@testable import DigiVPet

/// US-115 — the adventure map behind the Digimon.
///
/// What arithmetic can reach: how strongly the map is painted, and whether it is painted at all.
/// The rest of the story — that the map sits BELOW the sprite and below the scrim, that it is
/// clipped to the slot, that a Digimon is still legible over `01_grassland` — is a Simulator
/// screenshot, recorded in progress.txt. Same split as `LightScrimExtentTests`.
final class MapBackgroundTests: XCTestCase {
    /// THE AC: the opacity is inside the authored band. The map is scenery behind a 16-pixel-wide
    /// sprite with no outline, and a later edit that brightens it past 0.50 to "make the maps pop"
    /// fails here rather than in front of a player who can no longer find their Digimon.
    func testTheMapOpacityStaysInsideTheAuthoredBand() {
        XCTAssertGreaterThanOrEqual(MapBackgroundLayout.opacity, MapBackgroundLayout.minimumOpacity)
        XCTAssertLessThanOrEqual(MapBackgroundLayout.opacity, MapBackgroundLayout.maximumOpacity)
    }

    /// The band itself, spelled out — a test that only compared `opacity` against the two constants
    /// would still pass if someone widened the band to 0..1 and then brightened the map.
    func testTheBandIsTheOneTheStoryAuthored() {
        XCTAssertEqual(MapBackgroundLayout.minimumOpacity, 0.30)
        XCTAssertEqual(MapBackgroundLayout.maximumOpacity, 0.50)
        XCTAssertEqual(MapBackgroundLayout.opacity, 0.35, "the default the story shipped")
    }

    /// The map is scenery, not a veil: it must never be so strong that it reads as the subject of
    /// the screen, and never so faint it is not worth the layer.
    func testTheMapIsFainterThanWhateverIsDrawnOverIt() {
        XCTAssertLessThan(MapBackgroundLayout.opacity, 1)
        XCTAssertGreaterThan(MapBackgroundLayout.opacity, 0)
    }

    /// AC6: with no map selected, nothing is drawn — the screen is what US-114 left. The tempting
    /// wrong answer is a default of `01_grassland`, which would put a map on a fresh save that has
    /// never been anywhere.
    func testWithNoMapSelectedNothingIsDrawn() {
        XCTAssertFalse(MapBackgroundLayout.shouldDraw(assetName: nil))
    }

    /// An empty name is not a map either. `Image("")` draws the missing-resource placeholder, which
    /// is a grey box in the middle of the room.
    func testAnEmptyAssetNameDrawsNothing() {
        XCTAssertFalse(MapBackgroundLayout.shouldDraw(assetName: ""))
    }

    /// And a real selection does draw.
    func testASelectedMapIsDrawn() {
        XCTAssertTrue(MapBackgroundLayout.shouldDraw(assetName: "01_grassland"))
    }

    /// Every one of the sixteen shipped backgrounds is drawable by its catalog name — the names the
    /// US-116 catalog will hand over, checked here so a rename in `Assets.xcassets` that is not
    /// mirrored in the catalog is caught by the suite rather than by an empty room.
    func testAllSixteenShippedMapAssetsExistAndAreDrawable() throws {
        let names = [
            "01_grassland", "02_river", "03_ocean", "04_desert",
            "05_wasteland", "06_industrial", "07_mountains", "08_jungle",
            "09_lake", "10_city_dusk", "11_city_night", "12_cyberpunk",
            "13_factory_town", "14_farmland", "15_dungeon", "16_iceland",
        ]

        for name in names {
            XCTAssertTrue(MapBackgroundLayout.shouldDraw(assetName: name), name)
            // The asset really is in the bundle under that name. `UIImage(named:)` is the same
            // lookup `Image(_:)` does, so a missing set fails here and not on screen.
            XCTAssertNotNil(UIImage(named: name), "\(name) is missing from Assets.xcassets")
        }
    }
}
