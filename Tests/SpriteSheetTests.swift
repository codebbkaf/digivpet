import CoreGraphics
import Foundation
import XCTest

@testable import DigiVPet

final class SpriteSheetTests: XCTestCase {
    // MARK: - Frame layout

    func testFrameIndicesMatchTheSheetLayout() {
        XCTAssertEqual(SpriteFrame.allCases.map(\.rawValue), Array(0...11))
        XCTAssertEqual(SpriteFrame.walk1.rawValue, 0)
        XCTAssertEqual(SpriteFrame.attack.rawValue, 11)
        XCTAssertEqual(EggFrame.allCases.map(\.rawValue), Array(0...2))
    }

    /// Spot-checks the row-major math against rects read off the sheet by hand, rather than
    /// recomputing `(i % 3, i / 3)` in the test and asserting the formula against itself.
    func testFramesSliceToTheirSourceRects() {
        XCTAssertEqual(SpriteFrame.attack.sourceRect, CGRect(x: 32, y: 48, width: 16, height: 16))
        XCTAssertEqual(SpriteFrame.walk1.sourceRect, CGRect(x: 0, y: 0, width: 16, height: 16))
        XCTAssertEqual(SpriteFrame.eat1.sourceRect, CGRect(x: 32, y: 0, width: 16, height: 16))
        XCTAssertEqual(SpriteFrame.eat2.sourceRect, CGRect(x: 0, y: 16, width: 16, height: 16))
        XCTAssertEqual(SpriteFrame.hurt1.sourceRect, CGRect(x: 0, y: 48, width: 16, height: 16))
        XCTAssertEqual(EggFrame.hatch.sourceRect, CGRect(x: 32, y: 0, width: 16, height: 16))
    }

    // MARK: - Slicing

    func testStageSheetYields12FramesOf16x16() throws {
        let sheet = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Child", name: "Agumon"))
        XCTAssertEqual(sheet.kind, .stage)
        XCTAssertEqual(sheet.frames.count, 12)
        for frame in sheet.frames {
            XCTAssertEqual(frame.width, 16)
            XCTAssertEqual(frame.height, 16)
        }
    }

    func testDigitamaYieldsExactlyThreeFrames() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))
        XCTAssertEqual(egg.kind, .egg)
        XCTAssertEqual(egg.frames.count, 3)
        XCTAssertNotNil(egg[EggFrame.hatch])
    }

    /// An egg has no attack frame at all — index 11 does not exist on a 48x16 sheet.
    func testRequestingAStageFrameOnAnEggReturnsNil() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))
        XCTAssertNil(egg[SpriteFrame.attack])
        XCTAssertNil(egg[SpriteFrame.walk1])
    }

    /// The mirror case: a stage sheet's first 3 frames are walk1/walk2/eat1, not the egg's
    /// idle/wobble/hatch, so indexing one with `EggFrame` must fail rather than return art
    /// that means something else.
    func testRequestingAnEggFrameOnAStageSheetReturnsNil() throws {
        let sheet = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Child", name: "Agumon"))
        XCTAssertNil(sheet[EggFrame.hatch])
        XCTAssertNil(sheet[EggFrame.idle])
    }

    func testFramesAreDistinctRegionsOfTheSheet() throws {
        let sheet = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Child", name: "Agumon"))
        let walk1 = try pixels(of: XCTUnwrap(sheet[.walk1]))
        let attack = try pixels(of: XCTUnwrap(sheet[.attack]))
        let sleep1 = try pixels(of: XCTUnwrap(sheet[.sleep1]))

        // Different rects must yield different art; identical bytes would mean the crop
        // rect never moved and every "frame" is the same corner of the sheet.
        XCTAssertNotEqual(walk1, attack)
        XCTAssertNotEqual(walk1, sleep1)
        XCTAssertNotEqual(sleep1, attack)
    }

    /// A sheet that is neither 48x64 nor 48x16 is rejected instead of producing garbage frames.
    func testMalformedSheetIsRejected() throws {
        XCTAssertNil(SpriteSheet(sheet: try solidImage(width: 32, height: 32)))
        XCTAssertNil(SpriteSheet(sheet: try solidImage(width: 48, height: 40)))
        XCTAssertNil(SpriteSheet(sheet: try solidImage(width: 16, height: 16)))
        XCTAssertNotNil(SpriteSheet(sheet: try solidImage(width: 48, height: 64)))
        XCTAssertNotNil(SpriteSheet(sheet: try solidImage(width: 48, height: 16)))
    }

    func testMissingSpriteYieldsNilSheetRatherThanCrashing() {
        XCTAssertNil(SpriteSheetCache.shared.sheet(stage: "Child", name: "NotADigimon"))
    }

    // MARK: - Caching

    func testSheetIsDecodedOnlyOncePerDigimon() {
        var decodes: [String] = []
        let cache = SpriteSheetCache { stage, name in
            decodes.append("\(stage)/\(name)")
            return SpriteLoader.loadSheet(stage: stage, name: name)
        }

        XCTAssertNotNil(cache.sheet(stage: "Child", name: "Agumon"))
        XCTAssertNotNil(cache.sheet(stage: "Child", name: "Agumon"))
        XCTAssertNotNil(cache.sheet(stage: "Child", name: "Agumon"))
        XCTAssertEqual(decodes, ["Child/Agumon"])

        // A different Digimon is a different key and does decode.
        XCTAssertNotNil(cache.sheet(stage: "Child", name: "Gabumon"))
        XCTAssertEqual(decodes, ["Child/Agumon", "Child/Gabumon"])
    }

    /// The frames must be cropped once at load, not per animation tick: a second request
    /// hands back the very same CGImage objects.
    func testCachedFramesAreNotRecropped() throws {
        let cache = SpriteSheetCache()
        let first = try XCTUnwrap(cache.sheet(stage: "Child", name: "Agumon"))
        let second = try XCTUnwrap(cache.sheet(stage: "Child", name: "Agumon"))

        for (lhs, rhs) in zip(first.frames, second.frames) {
            XCTAssertTrue(lhs === rhs)
        }
    }

    /// A missing sheet must not re-hit the disk on every tick either.
    func testFailedLoadIsCachedToo() {
        var decodeCount = 0
        let cache = SpriteSheetCache { stage, name in
            decodeCount += 1
            return SpriteLoader.loadSheet(stage: stage, name: name)
        }

        XCTAssertNil(cache.sheet(stage: "Child", name: "NotADigimon"))
        XCTAssertNil(cache.sheet(stage: "Child", name: "NotADigimon"))
        XCTAssertEqual(decodeCount, 1)
    }

    // MARK: - Helpers

    /// Renders an image into a known-format bitmap so two frames' pixels can be compared.
    /// Cropped frames share the sheet's backing buffer, so their raw data provider is the
    /// whole sheet — they have to be drawn to be compared.
    private func pixels(of image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data)
        return Data(bytes: data, count: image.width * image.height * 4)
    }

    private func solidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
