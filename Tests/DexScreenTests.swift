import CoreGraphics
import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// Synthetic sprites, so a decode can be counted without touching the bundle.
private enum SpriteFixture {
    /// A solid image of the given size. `IdleSpriteCache` inspects dimensions to decide whether a
    /// file from the flat folder is a real 16x16 idle sprite, so size is the part that matters.
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    static let idleFrame = image(width: 16, height: 16)
    static let stageSheet = image(width: 48, height: 64)
}

/// Records every folder+name it is asked for, so a test can prove what was and was not decoded.
private final class DecodeSpy {
    private(set) var requests: [(folder: String, name: String)] = []
    var images: [String: CGImage] = [:]

    var count: Int { requests.count }

    func decode(_ folder: String, _ name: String) -> CGImage? {
        requests.append((folder, name))
        return images[folder]
    }
}

final class IdleSpriteCacheTests: XCTestCase {
    // MARK: - AC: entries use the flat "Idle Frame Only" 16x16 sprites

    func testTheIdleFolderIsPreferredOverTheAnimatedSheet() {
        let spy = DecodeSpy()
        spy.images = [
            SpriteLoader.idleFrameOnlyFolder: SpriteFixture.idleFrame,
            "Child": SpriteFixture.stageSheet,
        ]
        let cache = IdleSpriteCache(decode: spy.decode)

        let image = cache.image(stage: "Child", name: "Agumon")

        XCTAssertEqual(image, SpriteFixture.idleFrame)
        XCTAssertEqual(spy.requests.map(\.folder), [SpriteLoader.idleFrameOnlyFolder],
                       "The stage sheet must not be decoded when the idle frame resolves.")
    }

    /// The Digitama are the reason the fallback exists: they have no entry in `Idle Frame Only`.
    func testAStageSheetsFirstFrameIsUsedWhenTheIdleFolderHasNothing() {
        let spy = DecodeSpy()
        spy.images = ["Digitama": SpriteFixture.stageSheet]
        let cache = IdleSpriteCache(decode: spy.decode)

        let image = cache.image(stage: "Digitama", name: "Agu_Digitama")

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, SpriteSheet.frameSize)
        XCTAssertEqual(image?.height, SpriteSheet.frameSize)
        XCTAssertEqual(spy.requests.map(\.folder), [SpriteLoader.idleFrameOnlyFolder, "Digitama"])
    }

    /// A wrongly-sized file in the flat folder would slip through as art of the wrong shape.
    func testAnOversizedFileInTheIdleFolderIsRejected() {
        let spy = DecodeSpy()
        spy.images = [SpriteLoader.idleFrameOnlyFolder: SpriteFixture.stageSheet]
        let cache = IdleSpriteCache(decode: spy.decode)

        XCTAssertNil(cache.image(stage: "Child", name: "Agumon"),
                     "A 48x64 file in the flat folder is not an idle frame.")
    }

    func testMissingArtIsNilRatherThanACrash() {
        let cache = IdleSpriteCache(decode: DecodeSpy().decode)
        XCTAssertNil(cache.image(stage: "Child", name: "NotADigimon"))
    }

    // MARK: - AC: images load lazily; the full roster is never decoded eagerly

    func testASpriteIsDecodedOnceNoMatterHowOftenItIsDrawn() {
        let spy = DecodeSpy()
        spy.images = [SpriteLoader.idleFrameOnlyFolder: SpriteFixture.idleFrame]
        let cache = IdleSpriteCache(decode: spy.decode)

        for _ in 0..<10 { _ = cache.image(stage: "Child", name: "Agumon") }

        XCTAssertEqual(spy.count, 1, "Every draw after the first must be a dictionary lookup.")
    }

    /// A miss must be cached too, or a Digimon with no art re-hits the disk on every redraw.
    func testAMissIsCachedAsWellAsAHit() {
        let spy = DecodeSpy()
        let cache = IdleSpriteCache(decode: spy.decode)

        _ = cache.image(stage: "Child", name: "NotADigimon")
        _ = cache.image(stage: "Child", name: "NotADigimon")

        XCTAssertEqual(spy.count, 2, "One resolve = two folder probes; the second call adds none.")
    }

    /// The shipped art, not a fixture: proves the flat folder really is where the Dex's sprites
    /// come from and that they really are 16x16.
    func testTheBundledIdleSpriteForARosterDigimonIsARealSixteenPixelFrame() throws {
        let agumon = try XCTUnwrap(EvolutionGraph.bundled.node(id: "agumon"))
        let image = try XCTUnwrap(IdleSpriteCache().image(stage: agumon.stage.rawValue,
                                                          name: agumon.spriteFile))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
    }
}

@MainActor
final class DexModelTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("Dex.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> GameStore {
        try GameStore(url: storeURL)
    }

    private static let met = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - AC: header shows discovered/total count

    func testAnUntouchedDexShowsTheWholeRosterAsUndiscovered() throws {
        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })

        model.load()

        XCTAssertEqual(model.totalCount, EvolutionGraph.bundled.nodes.count)
        XCTAssertEqual(model.discoveredCount, 0)
        XCTAssertTrue(model.rows.allSatisfy { !$0.isDiscovered })
    }

    func testDiscoveredCountRisesWithEachDiscovery() throws {
        let store = try makeStore()
        store.recordDiscovery(id: "agumon", now: Self.met)
        store.recordDiscovery(id: "greymon", now: Self.met)
        try store.save()

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(model.discoveredCount, 2)
        XCTAssertLessThan(model.discoveredCount, model.totalCount,
                          "The roster must be bigger than what one game discovers.")
    }

    // MARK: - AC: undiscovered entries render a placeholder / discovered ones carry their date

    func testOnlyTheDiscoveredDigimonCarriesItsDate() throws {
        let store = try makeStore()
        store.recordDiscovery(id: "agumon", now: Self.met)
        try store.save()

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        let agumon = try XCTUnwrap(model.rows.first { $0.id == "agumon" })
        XCTAssertEqual(agumon.firstDiscovered, Self.met)
        XCTAssertTrue(agumon.isDiscovered)

        let greymon = try XCTUnwrap(model.rows.first { $0.id == "greymon" })
        XCTAssertNil(greymon.firstDiscovered)
        XCTAssertFalse(greymon.isDiscovered, "An unmet Digimon must render as a placeholder.")
    }

    /// The date shown is the FIRST sighting — raising the same Digimon twice must not rewrite it.
    func testTheFirstSightingDateSurvivesARediscovery() throws {
        let store = try makeStore()
        store.recordDiscovery(id: "agumon", now: Self.met)
        store.recordDiscovery(id: "agumon", now: Self.met.addingTimeInterval(86_400))
        try store.save()

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(model.rows.filter { $0.id == "agumon" }.count, 1)
        XCTAssertEqual(model.rows.first { $0.id == "agumon" }?.firstDiscovered, Self.met)
    }

    // MARK: - AC: images load lazily; the full roster is never decoded eagerly

    /// The model is what the grid is built from, so if IT decoded art, `LazyVGrid` being lazy
    /// would not save anything. Rows must carry the node and nothing more, leaving the decode to
    /// the cells that are actually shown — which is what the second half measures: one on-screen
    /// cell costs one decode, so N cells cost N, not the whole roster.
    func testASpriteIsDecodedPerShownCellAndNotWhenRowsAreBuilt() throws {
        let spy = DecodeSpy()
        spy.images = [SpriteLoader.idleFrameOnlyFolder: SpriteFixture.idleFrame]
        let cache = IdleSpriteCache(decode: spy.decode)

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(model.rows.count, EvolutionGraph.bundled.nodes.count)
        XCTAssertEqual(spy.count, 0, "Building rows must not decode a single sprite.")

        // What one visible cell costs, drawn the way `DexCell` draws it.
        let shown = try XCTUnwrap(model.rows.first)
        _ = cache.image(stage: shown.node.stage.rawValue, name: shown.node.spriteFile)
        XCTAssertEqual(spy.count, 1, "A shown cell decodes its own sprite and no one else's.")
    }

    // MARK: - Ordering

    func testDiscoveredEntriesSortFirstThenAlphabetically() throws {
        let store = try makeStore()
        // Greymon sorts after Agumon alphabetically but is the only one met, so it must lead.
        store.recordDiscovery(id: "greymon", now: Self.met)
        try store.save()

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(model.rows.first?.id, "greymon")

        let undiscovered = model.rows.filter { !$0.isDiscovered }.map(\.node.displayName)
        XCTAssertEqual(undiscovered, undiscovered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - Degradation

    /// A Dex that cannot be read still shows the roster: it is a side screen, and losing it must
    /// not be louder than losing the game.
    func testAnUnopenableStoreLeavesAnAllUndiscoveredDex() {
        struct Unopenable: Error {}
        let model = DexModel(graph: .bundled, makeStore: { throw Unopenable() })

        model.load()

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.totalCount, EvolutionGraph.bundled.nodes.count)
        XCTAssertEqual(model.discoveredCount, 0)
    }
}
