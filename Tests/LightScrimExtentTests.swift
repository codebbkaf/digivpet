import CoreGraphics
import XCTest

@testable import DigiVPet

/// US-112 — how far the scrim reaches.
///
/// `LightLayer.scrimRect(spriteSlot:)` is the one part of the layering a test can reach: everything
/// else about the light on screen (that the lamp is painted above the scrim, that the action row is
/// bright at `off`) is a Simulator screenshot, recorded in progress.txt.
///
/// The rects here are the shape of a real 41mm screen — a slot with the stats strip above it and
/// the name line, the bars and the action row below — so "not the screen" is asserted against a
/// screen the slot really is a part of, rather than against an arbitrary bigger rectangle.
final class LightScrimExtentTests: XCTestCase {
    /// A 41mm screen in points.
    private let screen = CGRect(x: 0, y: 0, width: 176, height: 215)

    /// The sprite's slot inside it: below the stats strip, above the name line.
    private let slot = CGRect(x: 0, y: 44, width: 176, height: 80)

    /// THE AC: the scrim covers the Digimon's room and not the screen.
    func testTheScrimCoversTheSpriteSlotAndNotTheScreen() {
        XCTAssertEqual(LightLayer.scrimRect(spriteSlot: slot), slot)
        XCTAssertNotEqual(LightLayer.scrimRect(spriteSlot: slot), screen)
    }

    /// The same claim said in terms of what has to stay bright: there is screen above the scrim
    /// (the stats strip and the nav bar the Dex button sits in) and screen below it (the name line,
    /// the energy bars and the action row), and neither is painted over.
    func testChromeAboveAndBelowTheSlotIsOutsideTheScrim() throws {
        let scrim = try XCTUnwrap(LightLayer.scrimRect(spriteSlot: slot))

        XCTAssertGreaterThan(scrim.minY, screen.minY, "nothing above the slot is dimmed")
        XCTAssertLessThan(scrim.maxY, screen.maxY, "nothing below it is dimmed")
        XCTAssertLessThan(scrim.height, screen.height)
    }

    /// AC9: before the first layout pass there is no slot, and an unmeasured slot draws NOTHING.
    /// The tempting fallback — the layer's own bounds — is the whole screen blacked out.
    func testWithNoSlotMeasuredYetTheScrimPaintsNothing() {
        XCTAssertNil(LightLayer.scrimRect(spriteSlot: nil))
    }

    /// A degenerate slot is still that slot rather than a reason to reach for the screen: a zero
    /// rect paints a zero rect, which is invisible for the one pass it can happen in.
    func testAZeroSlotPaintsAZeroRectRatherThanTheScreen() {
        XCTAssertEqual(LightLayer.scrimRect(spriteSlot: .zero), .zero)
    }

    /// The scrim's darkness is not what this story changed, and this is the guard on that: the
    /// three states still dim by exactly what US-099 authored. Only the extent moved.
    func testTheScrimsDarknessIsUnchanged() {
        XCTAssertEqual(LightState.on.dimOpacity, 0)
        XCTAssertEqual(LightState.semi.dimOpacity, 0.5)
        XCTAssertEqual(LightState.off.dimOpacity, 0.85)
    }
}
