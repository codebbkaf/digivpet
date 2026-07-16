import CoreGraphics
import Foundation
import XCTest

@testable import DigiVPet

final class SpriteLoaderTests: XCTestCase {
    func testLoadsChildAgumonAt48x64() throws {
        let sheet = try XCTUnwrap(SpriteLoader.loadSheet(stage: "Child", name: "Agumon"))
        XCTAssertEqual(sheet.width, 48)
        XCTAssertEqual(sheet.height, 64)
    }

    func testMissingSpriteReturnsNilRatherThanCrashing() {
        XCTAssertNil(SpriteLoader.loadSheet(stage: "Child", name: "NotADigimon"))
        XCTAssertNil(SpriteLoader.loadSheet(stage: "NotAStage", name: "Agumon"))
    }

    /// `Bundle.url(forResource:)` treats an empty name like nil and hands back an arbitrary PNG
    /// from the directory (Child yields Morphomon), so an empty name must be rejected up front
    /// or a blank spriteFile would quietly load the wrong Digimon instead of failing.
    func testEmptyNameOrStageReturnsNilRatherThanAnArbitrarySprite() {
        XCTAssertNil(SpriteLoader.loadSheet(stage: "Child", name: ""))
        XCTAssertNil(SpriteLoader.loadSheet(stage: "", name: "Agumon"))
        XCTAssertNil(SpriteLoader.loadSheet(stage: "", name: ""))
    }

    /// The folder reference must preserve stage subfolders — the same filename can exist in
    /// several stages, so a flattened bundle would make sheets unaddressable.
    func testStageSubfoldersArePreserved() throws {
        XCTAssertNotNil(SpriteLoader.url(stage: "Digitama", name: "Agu_Digitama"))
        XCTAssertNotNil(SpriteLoader.url(stage: "Idle Frame Only", name: "Agumon_2006"))

        // Agumon is a Child; it must not be reachable at the folder root.
        XCTAssertNil(Bundle.main.url(
            forResource: "Agumon", withExtension: "png", subdirectory: SpriteLoader.spriteRoot))
    }

    func testDigitamaSheetIs48x16() throws {
        let egg = try XCTUnwrap(SpriteLoader.loadSheet(stage: "Digitama", name: "Agu_Digitama"))
        XCTAssertEqual(egg.width, 48)
        XCTAssertEqual(egg.height, 16)
    }

    /// sprites_cut/ is dev-tool output for eyeballing frames. The app slices at runtime and
    /// must never ship pre-cut frames.
    func testSpritesCutIsNotBundled() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: resources.appendingPathComponent("sprites_cut").path))
    }
}
