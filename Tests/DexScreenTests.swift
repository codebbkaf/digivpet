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

    // MARK: - AC: the Dex root is a grid over ALL roster entries, and the header counts them

    func testAnUntouchedDexShowsTheWholeRosterAsUndiscovered() throws {
        let model = DexModel(makeStore: { try self.makeStore() })

        model.load()

        XCTAssertEqual(model.totalCount, Roster.bundled.entries.count)
        XCTAssertEqual(model.discoveredCount, 0)
        XCTAssertTrue(model.rows.allSatisfy { !$0.isDiscovered })
    }

    /// The point of US-063: the grid is the ROSTER, not the ~88 Digimon an authored line reaches.
    /// A row per roster entry, and every roster entry with a row.
    func testTheGridCoversEveryRosterEntryAndNothingElse() {
        let model = DexModel(makeStore: { try self.makeStore() })

        model.load()

        XCTAssertEqual(Set(model.rows.map(\.id)), Set(Roster.bundled.entries.map(\.id)))
        XCTAssertEqual(model.rows.count, Roster.bundled.entries.count)
        XCTAssertGreaterThan(model.rows.count, EvolutionGraph.bundled.nodes.count,
                             "The roster is far larger than the graph; that is what the grid adds.")
    }

    /// The Digimon that are only ever met — the dexOnly ones with no animated sheet and no edge —
    /// were invisible while the Dex listed lines. They are most of the grid.
    func testDexOnlyDigimonAreOnTheGrid() throws {
        let model = DexModel(makeStore: { try self.makeStore() })

        model.load()

        let dexOnly = Roster.bundled.entries.filter(\.dexOnly)
        XCTAssertFalse(dexOnly.isEmpty, "The shipped roster has idle-frame-only Digimon.")
        for entry in dexOnly {
            XCTAssertNotNil(model.rows.first { $0.id == entry.id },
                            "\(entry.id) has art on disk, so it belongs on the grid.")
        }
    }

    /// A cell draws from the row alone, so a row has to carry the sprite the roster names for it —
    /// getting this wrong would draw the right name over another Digimon's art.
    func testARowCarriesItsRosterEntrysNameStageAndSprite() throws {
        let model = DexModel(makeStore: { try self.makeStore() })

        model.load()

        let entry = try XCTUnwrap(Roster.bundled.entry(id: "agumon"))
        let row = try XCTUnwrap(model.rows.first { $0.id == "agumon" })
        XCTAssertEqual(row.displayName, entry.displayName)
        XCTAssertEqual(row.stage, entry.stage)
        XCTAssertEqual(row.spriteFile, entry.spriteFile)
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

        XCTAssertEqual(model.rows.count, Roster.bundled.entries.count)
        XCTAssertEqual(spy.count, 0, "Building 1,022 rows must not decode a single sprite.")

        // What one visible cell costs, drawn the way `DexCell` draws it.
        let shown = try XCTUnwrap(model.rows.first)
        _ = cache.image(stage: shown.stage.rawValue, name: shown.spriteFile)
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

        let undiscovered = model.rows.filter { !$0.isDiscovered }.map(\.displayName)
        XCTAssertEqual(undiscovered, undiscovered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - AC: the screen lists evolution lines, each opening its tree

    func testEachLineInTheRosterBecomesOneSection() throws {
        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })

        model.load()

        var expected: [String] = []
        for node in EvolutionGraph.bundled.nodes where !node.dexOnly {
            if !expected.contains(node.line) { expected.append(node.line) }
        }
        XCTAssertEqual(model.sections.filter(\.isLine).map(\.id), expected,
                       "One section per line, in the order the roster first mentions each.")
        XCTAssertTrue(model.sections.allSatisfy(\.isLine),
                      "The shipped roster has no dexOnly entries, so there is no Others section.")
    }

    /// A line is named after its namesake node, so the heading keeps the roster's own casing.
    func testALineIsTitledAfterItsNamesakeDigimon() throws {
        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })

        model.load()

        let ver1 = try XCTUnwrap(model.sections.first { $0.id == "dmc-v1" })
        XCTAssertEqual(ver1.title, "Color Ver.1")
    }

    /// The tree's columns must read as the JSON lists them. `rows` is sorted discovered-first for
    /// the flat grid, so a section that reused it would reshuffle a branch as the player played.
    func testALinesRowsKeepAuthoredOrderEvenAsDiscoveriesChangeTheFlatOrder() throws {
        let store = try makeStore()
        // Sorts last in the line as authored, but discovering it floats it to the top of `rows`.
        store.recordDiscovery(id: "wargreymon", now: Self.met)
        try store.save()

        let model = DexModel(graph: .bundled, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(model.rows.first?.id, "wargreymon", "The flat grid still sorts met-first.")

        let ver1 = try XCTUnwrap(model.sections.first { $0.id == "dmc-v1" })
        let authored = EvolutionGraph.bundled.nodes.filter { $0.line == "dmc-v1" }.map(\.id)
        XCTAssertEqual(ver1.rows.map(\.id), authored)
    }

    /// The sections partition the GRAPH, not the roster — since US-063 those are different sizes,
    /// and the header counts the roster. What still has to hold is that every graph node lands in
    /// exactly one section, so a Digimon cannot be drawn in two trees or fall out of all of them.
    func testTheSectionsPartitionTheGraphExactlyOnce() throws {
        let store = try makeStore()
        store.recordDiscovery(id: "agumon", now: Self.met)
        store.recordDiscovery(id: "gabumon", now: Self.met)
        try store.save()

        let model = DexModel(makeStore: { try self.makeStore() })
        model.load()

        let sectioned = model.sections.flatMap { $0.rows.map(\.id) }
        XCTAssertEqual(Set(sectioned), Set(EvolutionGraph.bundled.nodes.map(\.id)))
        XCTAssertEqual(sectioned.count, Set(sectioned).count,
                       "No Digimon may appear in two sections.")
        XCTAssertLessThan(sectioned.count, model.totalCount,
                          "The trees cover only the authored lines; the grid covers the roster.")
    }

    /// A section's `nodes` is what `EvolutionTreeView` lays its columns out from, and its `rows`
    /// is what those cells draw — so the two must line up index for index or a tree would draw one
    /// Digimon's sprite in another's position.
    func testASectionsNodesAndRowsAreTheSameDigimonInTheSameOrder() throws {
        let model = DexModel(makeStore: { try self.makeStore() })

        model.load()

        for section in model.sections where section.isLine {
            XCTAssertEqual(section.nodes.map(\.id), section.rows.map(\.id), section.title)
        }
    }

    // MARK: - AC: dexOnly entries stay reachable in a flat Others section

    /// The shipped roster has no dexOnly nodes yet, so this is the only place the Others section
    /// is exercised. A dexOnly node carries a line like anything else but may be named by no edge,
    /// so on its line's tree it would be an unreachable node floating beside the ladder.
    func testDexOnlyEntriesAreMovedOutOfTheirLineIntoOthers() throws {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "agumon", displayName: "Agumon", stage: .child,
                          line: "agumon", spriteFile: "Agumon"),
            EvolutionNode(id: "aquilamon", displayName: "Aquilamon", stage: .adult,
                          line: "agumon", spriteFile: "Aquilamon", dexOnly: true),
        ])
        let model = DexModel(graph: graph, makeStore: { try self.makeStore() })

        model.load()

        XCTAssertEqual(model.sections.map(\.id), ["agumon", DexSection.othersID])
        XCTAssertEqual(model.sections.first?.rows.map(\.id), ["agumon"],
                       "A dexOnly node must not be left in its line's tree.")
        XCTAssertEqual(model.sections.first?.nodes.map(\.id), ["agumon"])

        let others = try XCTUnwrap(model.sections.last)
        XCTAssertFalse(others.isLine, "Others is a flat grid, not a tree.")
        XCTAssertEqual(others.title, "Others")
        XCTAssertEqual(others.rows.map(\.id), ["aquilamon"])
        XCTAssertTrue(others.nodes.isEmpty, "Others is a grid; it has no tree to lay out.")
    }

    // MARK: - US-067 AC: the owning line's tree is reachable from a detail sheet

    /// The link's whole job: an entry that IS on a tree resolves to the section that draws it.
    func testALineMemberResolvesToTheSectionThatDrawsIt() throws {
        let model = DexModel(makeStore: { try self.makeStore() })
        model.load()

        let section = try XCTUnwrap(DexSection.line(containing: "greymon", in: model.sections))

        XCTAssertEqual(section.id, "dmc-v1", "Greymon is on the Digital Monster Ver.1 line.")
        XCTAssertTrue(section.isLine, "A grid section has no tree to push to.")
        XCTAssertTrue(section.rows.contains { $0.id == "greymon" },
                      "The section handed to the tree must contain the Digimon it was opened from.")
        XCTAssertFalse(section.nodes.isEmpty,
                       "EvolutionTreeView lays out from `nodes`; an empty one is a blank tree.")
    }

    /// The ~930 roster entries with no graph node at all — the common case since US-063 — get no
    /// tree affordance rather than a link onto an empty one.
    func testARosterOnlyEntryBelongsToNoLine() throws {
        let model = DexModel(makeStore: { try self.makeStore() })
        model.load()

        let rosterOnly = try XCTUnwrap(
            model.rows.first { EvolutionGraph.bundled.node(id: $0.id) == nil },
            "US-063 bundled 1,022 roster entries against ~88 graph nodes; some must have no node.")

        XCTAssertNil(DexSection.line(containing: rosterOnly.id, in: model.sections))
    }

    /// A dexOnly node carries a `line` key but is deliberately pulled into `Others`, which has no
    /// nodes. Matching on the built sections rather than on that key is what keeps it out of a tree
    /// it was excluded from — a lone cell with no connector.
    func testADexOnlyEntryBelongsToNoLineEvenThoughItCarriesALineKey() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "agumon", displayName: "Agumon", stage: .child,
                          line: "agumon", spriteFile: "Agumon"),
            EvolutionNode(id: "aquilamon", displayName: "Aquilamon", stage: .adult,
                          line: "agumon", spriteFile: "Aquilamon", dexOnly: true),
        ])
        let model = DexModel(graph: graph, makeStore: { try self.makeStore() })
        model.load()

        XCTAssertEqual(DexSection.line(containing: "agumon", in: model.sections)?.id, "agumon")
        XCTAssertNil(DexSection.line(containing: "aquilamon", in: model.sections),
                     "A dexOnly node is on no tree, so it must offer no way onto one.")
    }

    /// An id nothing in the Dex knows is nil rather than a crash or a wrong tree.
    func testAnUnknownIdBelongsToNoLine() {
        let model = DexModel(makeStore: { try self.makeStore() })
        model.load()

        XCTAssertNil(DexSection.line(containing: "not-a-digimon", in: model.sections))
    }

    /// Every entry the trees draw can be got back to from its own detail sheet — the AC read
    /// literally, over the whole shipped graph rather than over one hand-picked example.
    func testEveryDigimonOnAShippedTreeCanReachThatTree() {
        let model = DexModel(makeStore: { try self.makeStore() })
        model.load()

        for section in model.sections where section.isLine {
            for row in section.rows {
                XCTAssertEqual(DexSection.line(containing: row.id, in: model.sections)?.id, section.id,
                               "\(row.id) must lead back to the tree that draws it.")
            }
        }
    }

    // MARK: - Line headings

    /// Every line the graph ships gets a real heading. `DexModel.title(ofLine:)` falls back to the
    /// raw key when neither an authored title nor a node of that name exists, which is a heading
    /// reading `penc-me` — cosmetic, so it would never fail a build, and so it needs a test of its
    /// own. Derived from the graph rather than listed, so the next Phase E tree is told to add its
    /// title instead of shipping its slug.
    ///
    /// `palmon` is the one exception, and by the older convention rather than by omission: it is a
    /// node id, so the line is named after its namesake's display name.
    func testEveryShippedLineHasAHeadingThatIsNotItsRawKey() {
        let graph = EvolutionGraph.bundled
        for line in Set(graph.nodes.map(\.line)) {
            let title = DexModel.lineTitles[line] ?? graph.node(id: line)?.displayName
            XCTAssertNotNil(title, "line '\(line)' would head its section with its own key")
            XCTAssertNotEqual(title, line, "line '\(line)' heads its section with its own key")
        }
        XCTAssertEqual(DexModel.lineTitles["penc-me"], "Pendulum ME")
        XCTAssertEqual(DexModel.lineTitles["penc-vb"], "Pendulum VB")
        XCTAssertNil(DexModel.lineTitles["palmon"], "palmon is titled by its namesake node")
    }

    // MARK: - Degradation

    /// A Dex that cannot be read still shows the roster: it is a side screen, and losing it must
    /// not be louder than losing the game.
    func testAnUnopenableStoreLeavesAnAllUndiscoveredDex() {
        struct Unopenable: Error {}
        let model = DexModel(makeStore: { throw Unopenable() })

        model.load()

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.totalCount, Roster.bundled.entries.count)
        XCTAssertEqual(model.discoveredCount, 0)
    }
}

/// US-064: what the detail sheet lists under "Evolves into".
final class DexEvolutionCandidateTests: XCTestCase {
    private static let met = Date(timeIntervalSince1970: 1_760_000_000)

    private static func node(
        _ id: String, stage: Stage = .child, to targets: [String] = []
    ) -> EvolutionNode {
        EvolutionNode(
            id: id, displayName: id.capitalized, stage: stage, spriteFile: id,
            evolutions: targets.map { EvolutionEdge(to: $0, minEnergy: 0, maxCareMistakes: 99) }
        )
    }

    private static func pool(_ rows: [DexRow]) -> [String: DexRow] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - AC: every outgoing edge's target is listed

    /// Authored order, not sorted: a branch should read the way the JSON lists it, so adding a
    /// sibling cannot reshuffle the ones already there.
    func testEveryOutgoingEdgeBecomesACandidateInAuthoredOrder() {
        let graph = EvolutionGraph(nodes: [
            Self.node("agumon", to: ["greymon", "meramon", "numemon"]),
            Self.node("greymon", stage: .adult),
            Self.node("meramon", stage: .adult),
            Self.node("numemon", stage: .adult),
        ])

        let candidates = DexRow.evolutionCandidates(of: "agumon", in: graph, resolvedAgainst: [:])

        XCTAssertEqual(candidates.map(\.id), ["greymon", "meramon", "numemon"])
    }

    /// The shipped graph, not a fixture: the real Agumon branch is the screen this story is for.
    /// US-133 gave it a fourth candidate, Devimon, so this is also the two-row case.
    func testTheShippedAgumonBranchListsItsFourTargets() {
        let candidates = DexRow.evolutionCandidates(
            of: "agumon", in: .bundled, resolvedAgainst: [:])

        XCTAssertEqual(candidates.map(\.id), ["greymon", "meramon", "devimon", "numemon"])
    }

    // MARK: - AC: discovered candidates show art and name; undiscovered are withheld

    /// The whole point of resolving against a pool rather than building rows from graph nodes: a
    /// node has no discovery date, and the date is what decides whether the cell shows the art.
    func testADiscoveredCandidateKeepsItsRowAndItsDate() throws {
        let graph = EvolutionGraph(nodes: [
            Self.node("agumon", to: ["greymon", "meramon"]),
            Self.node("greymon", stage: .adult),
            Self.node("meramon", stage: .adult),
        ])
        let pool = Self.pool([
            DexRow(id: "greymon", displayName: "Greymon", stage: .adult,
                   spriteFile: "Greymon", firstDiscovered: Self.met),
            DexRow(id: "meramon", displayName: "Meramon", stage: .adult,
                   spriteFile: "Meramon", firstDiscovered: nil),
        ])

        let candidates = DexRow.evolutionCandidates(
            of: "agumon", in: graph, resolvedAgainst: pool)

        let greymon = try XCTUnwrap(candidates.first { $0.id == "greymon" })
        XCTAssertTrue(greymon.isDiscovered)
        XCTAssertEqual(greymon.firstDiscovered, Self.met)
        XCTAssertEqual(greymon.spriteFile, "Greymon")

        let meramon = try XCTUnwrap(candidates.first { $0.id == "meramon" })
        XCTAssertFalse(meramon.isDiscovered, "Never met, so the cell withholds its name.")
    }

    /// The tree screen's pool is one line, and three shipped ids are in the graph but not the
    /// roster. A miss must still produce a cell — an undiscovered one — not drop the candidate.
    func testACandidateMissingFromThePoolFallsBackToItsNodeAsUndiscovered() throws {
        let graph = EvolutionGraph(nodes: [
            Self.node("agumon", to: ["greymon"]),
            Self.node("greymon", stage: .adult),
        ])

        let candidates = DexRow.evolutionCandidates(of: "agumon", in: graph, resolvedAgainst: [:])

        let greymon = try XCTUnwrap(candidates.first)
        XCTAssertEqual(greymon.id, "greymon")
        XCTAssertEqual(greymon.stage, .adult)
        XCTAssertFalse(greymon.isDiscovered)
    }

    // MARK: - AC: no edges, or absent from the graph, is a message rather than an empty section

    func testATerminalNodeHasNoCandidates() {
        let graph = EvolutionGraph(nodes: [Self.node("greymon", stage: .adult)])

        XCTAssertTrue(
            DexRow.evolutionCandidates(of: "greymon", in: graph, resolvedAgainst: [:]).isEmpty)
    }

    /// Since US-063 this is the COMMON case: the grid is the 1,022-entry roster and only ~88 of
    /// those have a node at all. It must be empty, not a crash and not a wrong list.
    func testARosterEntryWithNoGraphNodeHasNoCandidates() {
        XCTAssertTrue(
            DexRow.evolutionCandidates(
                of: "not-a-digimon", in: .bundled, resolvedAgainst: [:]).isEmpty)
    }

    /// A real roster entry, to prove the empty case is reached by ordinary data rather than only by
    /// a made-up id. Most of the roster is exactly this.
    ///
    /// Stated as a FLOOR that cannot move on purpose, and the reasoning is worth keeping. The
    /// literal was `> 800`, then "more than half the roster" — both were readings of "the roster
    /// dwarfs the graph", and Phase E is wiring the roster in a rung at a time, so both were
    /// eventually going to be false. Half stopped being true in US-150, which took the graph past
    /// 599 nodes against a 1,025-entry roster.
    ///
    /// What the test is really claiming is that the empty case is reached by ORDINARY data rather
    /// than only by a made-up id, and the 157 idle-only Digimon guarantee that for good: a dexOnly
    /// entry may never sit on an edge (`EvolutionGraphValidator.edgeToDexOnlyNode`), so it can
    /// never gain a node however far Phase E runs. That is the floor asserted here.
    func testMostOfTheShippedRosterHasNoCandidates() throws {
        let withoutNodes = Roster.bundled.entries.filter {
            EvolutionGraph.bundled.node(id: $0.id) == nil
        }
        let dexOnly = Roster.bundled.entries.filter(\.dexOnly).count
        XCTAssertEqual(dexOnly, 157)
        XCTAssertGreaterThanOrEqual(withoutNodes.count, dexOnly,
                                    "every idle-only Digimon is a roster entry with no node; "
                                        + "that is why the empty case needs a message.")

        let entry = try XCTUnwrap(withoutNodes.first)
        XCTAssertTrue(
            DexRow.evolutionCandidates(of: entry.id, in: .bundled, resolvedAgainst: [:]).isEmpty)
    }

    /// A broken edge is the validator's to report. The Dex must not invent a cell for a Digimon
    /// that does not exist — that would be a "?" the player can never resolve.
    func testAnEdgeToANonexistentTargetIsDroppedRatherThanShownAsUnknown() {
        let graph = EvolutionGraph(nodes: [
            Self.node("agumon", to: ["greymon", "ghostmon"]),
            Self.node("greymon", stage: .adult),
        ])

        let candidates = DexRow.evolutionCandidates(of: "agumon", in: graph, resolvedAgainst: [:])

        XCTAssertEqual(candidates.map(\.id), ["greymon"])
    }

    // MARK: - AC: one to three candidates fit 41mm without scrolling

    /// The section is a three-column grid, so one to three candidates are a single line and a
    /// fourth wraps onto a second. US-133 raised the ceiling from three to four — the V1 tree gives
    /// Agumon a third earned Champion — and US-134 raised it to five: the V2 tree gives Gabumon and
    /// Elecmon five Champions each, all of them drawable, so five is what the shipped file holds.
    /// Three and four rows have been screenshotted on 41mm and five was measured there for US-134;
    /// all of them are two rows at most and inside the sheet's `ScrollView`. This pins the data
    /// half: a SIXTH candidate is the first that nobody has seen — and V4's Palmon and V5's
    /// Gizamon are six-wide in the source document, so US-136/US-137 will meet this again.
    func testNoShippedDigimonHasMoreThanFiveCandidates() {
        for node in EvolutionGraph.bundled.nodes {
            let candidates = DexRow.evolutionCandidates(
                of: node.id, in: .bundled, resolvedAgainst: [:])
            XCTAssertLessThanOrEqual(candidates.count, 5, "\(node.id) would wrap to a third line.")
        }
    }
}
