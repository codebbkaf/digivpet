import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-120 — the map strip on the main screen.
///
/// What arithmetic can reach: what the row says in each of its two states, the exact spelling of
/// the counter, that the party button is not a live-looking dead target yet, and that choosing a map
/// moves the strip, the background and the save together. The rest of the story — that the row is
/// readable and untruncated on a 41mm watch, and what it costs the sprite — is a Simulator
/// measurement, recorded in progress.txt. Same split as `MapListTests`.
private enum Fixture {
    /// Two maps, deliberately NOT the shipped catalog: a test that pinned `01_grassland`'s real
    /// 3,000 steps would start failing the day someone retunes it, which is a data edit and not a
    /// bug. `MapCatalogTests` is where the shipped numbers are pinned.
    static let catalog = MapCatalog(maps: [
        AdventureMap(id: "first", displayName: "First", assetName: "01_grassland",
                     tier: 1, totalSteps: 25_000),
        AdventureMap(id: "second", displayName: "Second", assetName: "02_river",
                     tier: 2, totalSteps: 50_000, unlockedBy: "first"),
    ])

    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static let morning = Date(timeIntervalSince1970: 1_770_000_000)

    static func strip(_ progress: PlayerProfile?) -> MapStrip {
        MapStrip.make(in: catalog, progress: progress)!
    }
}

// MARK: - What the row says

final class MapStripTests: XCTestCase {
    /// AC1: the leading control is labelled with the SELECTED map's name and its counter.
    func testTheStripNamesTheSelectedMapAndItsProgress() {
        let progress = PlayerProfile(selectedMapId: "second")
        progress.record(steps: 1_222, forMap: "second")

        let strip = Fixture.strip(progress)

        XCTAssertEqual(strip.mapName, "Second")
        XCTAssertEqual(strip.progressText, "1222 / 50000")
        XCTAssertEqual(strip.mapId, "second")
        XCTAssertFalse(strip.isPrompt)
    }

    /// AC6: with nothing selected the strip names the FIRST map, as a prompt to choose one.
    func testWithNoMapSelectedTheStripPromptsWithTheFirstMap() {
        let strip = Fixture.strip(PlayerProfile())

        XCTAssertEqual(strip.mapName, "First")
        XCTAssertEqual(strip.progressText, "0 / 25000")
        XCTAssertTrue(strip.isPrompt)
        // Nil rather than "first": the strip NAMES map one, it does not claim the player is there.
        // US-118's accrual reads the selection, so a strip that reported one would be a lie the
        // step counter would then contradict.
        XCTAssertNil(strip.mapId)
    }

    /// Before `start()` finishes there is no `PlayerProfile` at all. The strip still draws, as a
    /// prompt, rather than disappearing for a frame and shoving the layout about when it arrives.
    func testWithNoSaveYetTheStripStillPrompts() {
        let strip = Fixture.strip(nil)

        XCTAssertEqual(strip.mapName, "First")
        XCTAssertEqual(strip.progressText, "0 / 25000")
        XCTAssertTrue(strip.isPrompt)
    }

    /// A save that has walked somewhere but has no selection — possible only by hand-editing, since
    /// `selectMap(nil)` is the only way back to nowhere — still prompts, and still with map one,
    /// which is the map that is always open.
    func testProgressWithoutASelectionStillPrompts() {
        let progress = PlayerProfile()
        progress.record(steps: 900, forMap: "second")

        let strip = Fixture.strip(progress)

        XCTAssertEqual(strip.mapName, "First")
        XCTAssertTrue(strip.isPrompt)
    }

    /// The counter is FLOORED, never rounded: `PlayerProfile` carries a `Double` because a
    /// `HealthReading` does, and a strip reading `25000 / 25000` on a map that is not finished
    /// would be the screen contradicting itself. Same rule as `MapListRow.recordedSteps`.
    func testTheCounterIsFlooredRatherThanRounded() {
        let progress = PlayerProfile(selectedMapId: "first")
        progress.record(steps: 24_999.6, forMap: "first")

        XCTAssertEqual(Fixture.strip(progress).progressText, "24999 / 25000")
    }

    /// The strip and the map list spell the same figure the same way — space, slash, space, no
    /// abbreviation and no grouping separator. Asserted against `MapListRow` itself rather than
    /// against a second copy of the literal, so the two cannot drift apart.
    func testTheStripSpellsProgressExactlyAsTheMapListDoes() {
        let progress = PlayerProfile(selectedMapId: "second")
        progress.record(steps: 1_222, forMap: "second")

        let row = MapListRow.rows(in: Fixture.catalog, progress: progress).first { $0.id == "second" }

        XCTAssertEqual(Fixture.strip(progress).progressText, row?.progressText)
    }

    /// No `NumberFormatter` anywhere near this: it is locale-dependent, so the same 50,000 renders
    /// as "50.000" in a German locale and as "50 000" — with a NON-BREAKING space — in a French one.
    /// US-119 wrote this test for the list; the strip is the second place the figure appears and so
    /// the second place it could drift.
    func testTheCounterCarriesNoGroupingSeparator() {
        let progress = PlayerProfile(selectedMapId: "second")
        progress.record(steps: 12_345, forMap: "second")

        let text = Fixture.strip(progress).progressText

        XCTAssertEqual(text, "12345 / 50000")
        XCTAssertFalse(text.contains(","))
        XCTAssertFalse(text.contains("."))
        XCTAssertFalse(text.contains("\u{00A0}"))
    }

    /// The two states are tellable apart at a glance, without reading the counter — which says
    /// `0 / 25000` in both of them on a fresh save.
    func testTheTravellingAndPromptStatesUseDifferentGlyphs() {
        let travelling = Fixture.strip(PlayerProfile(selectedMapId: "first"))
        let prompting = Fixture.strip(PlayerProfile())

        XCTAssertNotEqual(travelling.symbol, prompting.symbol)
        XCTAssertEqual(travelling.symbol, MapStripMarks.travellingSymbol)
        XCTAssertEqual(prompting.symbol, MapStripMarks.promptSymbol)
        XCTAssertFalse(MapStripMarks.travellingSymbol.isEmpty)
        XCTAssertFalse(MapStripMarks.promptSymbol.isEmpty)
    }

    /// And apart to VoiceOver, which cannot see a glyph at all.
    func testTheTwoStatesReadDifferentlyToVoiceOver() {
        let travelling = Fixture.strip(PlayerProfile(selectedMapId: "first"))
        let prompting = Fixture.strip(PlayerProfile())

        XCTAssertEqual(travelling.accessibilityLabel, "Adventuring in First")
        XCTAssertEqual(prompting.accessibilityLabel, "Choose a map. First")
    }

    /// An empty catalog has no map to name, so there is no strip — the row is absent rather than
    /// drawn blank. Impossible in the shipped file (US-117 would reject it) and reachable from a
    /// fixture, which is exactly when a `guard` earns its keep.
    func testAnEmptyCatalogHasNoStrip() {
        XCTAssertNil(MapStrip.make(in: MapCatalog(maps: []), progress: PlayerProfile()))
    }

    /// The shipped catalog prompts with `01_grassland`, the one map that is open from the start.
    func testTheShippedCatalogPromptsWithTheStartingMap() {
        let strip = MapStrip.make(in: .bundled, progress: PlayerProfile())

        XCTAssertEqual(strip?.mapId, nil)
        XCTAssertEqual(strip?.mapName, MapCatalog.bundled.maps.first?.displayName)
        XCTAssertEqual(strip?.mapName, MapCatalog.bundled.startingMap?.displayName)
    }
}

// MARK: - The controls

final class MapStripLayoutTests: XCTestCase {
    /// AC2: the party button must not be a dead tap target that LOOKS live. Until US-126 lands it
    /// is both unreachable and visibly faded — either alone would be a half-measure, since a fully
    /// bright disabled control reads as a bug and a bright-but-inert one reads as a broken tap.
    func testThePartyButtonIsUnreachableAndVisiblyFadedUntilItLeadsSomewhere() {
        XCTAssertFalse(MapStripLayout.isPartyReachable)
        XCTAssertLessThan(MapStripLayout.disabledOpacity, 1)
        // Not invisible either: a control that vanishes takes the row's shape with it, and US-126
        // would then move everything sideways the day it lands.
        XCTAssertGreaterThan(MapStripLayout.disabledOpacity, 0)
    }

    /// AC3: one line, at a size that is still a size. The row's whole cost to the screen is its
    /// font, so a later edit that grows it is one a test should argue with.
    func testTheRowIsOneLegibleLine() {
        XCTAssertGreaterThanOrEqual(MapStripLayout.fontSize, 9)
        // Smaller than the name line above it (12pt in `ContentView`), which is the row this one
        // must not compete with for attention or for height.
        XCTAssertLessThan(MapStripLayout.fontSize, 12)
        XCTAssertLessThan(MapStripLayout.iconSize, 12)
    }

    /// The party glyph is a real symbol name, and not the same as either map glyph — three marks on
    /// one row that could be confused with each other would be worse than none.
    func testThePartyGlyphIsItsOwn() {
        XCTAssertFalse(MapStripMarks.partySymbol.isEmpty)
        XCTAssertNotEqual(MapStripMarks.partySymbol, MapStripMarks.travellingSymbol)
        XCTAssertNotEqual(MapStripMarks.partySymbol, MapStripMarks.promptSymbol)
    }
}

// MARK: - Choosing a map, through the model and the save

@MainActor
final class MapStripSelectionTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("MapStrip.store") }

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

    private func makeModel() -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            maps: Fixture.catalog,
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first }
        )
    }

    /// AC6: the game is fully playable with no map chosen. The strip prompts, the background is
    /// absent, and there is still a Digimon on screen with bars to fill — nothing is gated.
    func testWithNoMapChosenTheGameIsFullyPlayable() async throws {
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.phase, .playing)
        XCTAssertNotNil(model.presentation)
        XCTAssertNotNil(model.energyProgress)
        XCTAssertNil(model.selectedMapAsset)
        XCTAssertTrue(try XCTUnwrap(model.mapStrip).isPrompt)
    }

    /// AC5: choosing a map moves the strip's text and US-115's background together, off the one
    /// saved selection.
    func testChoosingAMapMovesTheStripAndTheBackground() async throws {
        let model = makeModel()
        await model.start()

        model.selectMap("second")

        let strip = try XCTUnwrap(model.mapStrip)
        XCTAssertEqual(strip.mapName, "Second")
        XCTAssertEqual(strip.mapId, "second")
        XCTAssertFalse(strip.isPrompt)
        XCTAssertEqual(model.selectedMapAsset, "02_river")
    }

    /// AC5, the half a screenshot cannot show: the selection PERSISTS. A second model over the same
    /// store file is what a cold launch is, and it reads back the same strip.
    func testTheChosenMapSurvivesARelaunch() async throws {
        let first = makeModel()
        await first.start()
        first.selectMap("second")

        let second = makeModel()
        await second.start()

        XCTAssertEqual(second.mapStrip?.mapName, "Second")
        XCTAssertEqual(second.mapStrip?.mapId, "second")
        XCTAssertEqual(second.selectedMapAsset, "02_river")
    }

    /// The counter on the strip is the same one the list shows, credited from the same save — so
    /// steps banked while adventuring show up on the main screen without a second tap.
    func testTheStripCounterFollowsTheStepsCreditedToTheMap() async throws {
        let model = makeModel()
        await model.start()
        model.selectMap("first")

        let progress = try XCTUnwrap(model.profile)
        MapStepCreditor.credit(steps: 1_500, to: progress, catalog: Fixture.catalog,
                               now: Fixture.morning)

        XCTAssertEqual(model.mapStrip?.progressText, "1500 / 25000")
        XCTAssertEqual(model.mapRows.first { $0.id == "first" }?.progressText, "1500 / 25000")
    }

    /// The strip's own destination is the list, and what the list hands back is `selectMap(_:)` —
    /// so a tap on a list row is the same call this test makes. `MapListSelector` is what US-119
    /// tests; this is that its answer reaches the strip.
    func testWhatTheListHandsBackIsWhatTheStripThenShows() async throws {
        let model = makeModel()
        await model.start()

        let rows = model.mapRows
        let tapped = try XCTUnwrap(rows.first { $0.id == "first" })
        let next = MapListSelector.selection(tapping: tapped, current: nil)
        model.selectMap(next)

        XCTAssertEqual(model.mapStrip?.mapName, "First")
        XCTAssertFalse(try XCTUnwrap(model.mapStrip).isPrompt)
    }
}
