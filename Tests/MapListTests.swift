import Foundation
import XCTest

@testable import DigiVPet

/// US-119 — the map list.
///
/// What arithmetic can reach: the rows, the exact spelling of the progress figure, which maps are
/// shut, what a shut one is allowed to say, and what a tap on one does. The rest of the story —
/// that nothing truncates on a 41mm watch at `50000 / 50000` — is a Simulator screenshot, recorded
/// in progress.txt. Same split as `MapBackgroundTests` and `LightScrimExtentTests`.
private enum Fixture {
    /// Three short maps in a chain, deliberately NOT the shipped catalog: a test that walked
    /// `01_grassland`'s real 3,000 steps would start failing the day someone retunes it, which is a
    /// data edit and not a bug. `MapCatalogTests` is where the shipped numbers are pinned.
    static let catalog = MapCatalog(maps: [
        AdventureMap(id: "first", displayName: "First", assetName: "01_grassland",
                     tier: 1, totalSteps: 1_000,
                     opponentPool: ["a", "b", "c"],
                     digitamaSlots: [DigitamaSlot(digitamaId: "agu_digitama")]),
        AdventureMap(id: "second", displayName: "Second", assetName: "02_river",
                     tier: 2, totalSteps: 25_000, unlockedBy: "first",
                     opponentPool: ["d"],
                     digitamaSlots: [DigitamaSlot(digitamaId: "pyoco_digitama"),
                                     DigitamaSlot(digitamaId: "puni_digitama")]),
        AdventureMap(id: "third", displayName: "Third", assetName: "03_ocean",
                     tier: 3, totalSteps: 50_000, unlockedBy: "second"),
    ])

    static let noon = Date(timeIntervalSince1970: 1_770_000_000)

    static func rows(_ progress: PlayerProfile?) -> [MapListRow] {
        MapListRow.rows(in: catalog, progress: progress)
    }

    static func row(_ id: String, _ progress: PlayerProfile?) -> MapListRow {
        let row = rows(progress).first { $0.id == id }
        return row!
    }
}

// MARK: - The rows themselves

final class MapListRowTests: XCTestCase {
    /// AC2: one row per map, in tier order — which is catalog order, and the order the file
    /// authors. Not sorted here and not sorted in the view: the catalog IS the order.
    func testThereIsOneRowPerMapInCatalogOrder() {
        let rows = Fixture.rows(PlayerProfile())

        XCTAssertEqual(rows.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(rows.map(\.displayName), ["First", "Second", "Third"])
    }

    /// The shipped catalog draws all sixteen, in the tier order US-116 authored. The one place this
    /// suite touches the real file, because "every map" is the criterion.
    func testTheShippedCatalogDrawsAllSixteenMaps() {
        let rows = MapListRow.rows(in: .bundled, progress: PlayerProfile())

        XCTAssertEqual(rows.count, 16)
        XCTAssertEqual(rows.map(\.id), MapCatalog.bundled.maps.map(\.id))
        // Tier order, said as an invariant rather than as a list of sixteen strings that would have
        // to be re-typed the day a map is retuned.
        let tiers = rows.compactMap { MapCatalog.bundled.map(id: $0.id)?.tier }
        XCTAssertEqual(tiers, tiers.sorted(), "the list draws the catalog in tier order")
    }

    /// AC2: the row carries the map's art, which is what the thumbnail draws — the same imageset
    /// `MapBackgroundView` paints behind the Digimon, so the row is a picture of where you would be.
    func testEachRowCarriesTheMapsOwnArt() {
        let rows = Fixture.rows(PlayerProfile())

        XCTAssertEqual(rows.map(\.assetName), ["01_grassland", "02_river", "03_ocean"])
    }

    /// Steps recorded show up on the row they were walked on, and nowhere else.
    func testRecordedStepsComeFromTheSave() {
        let progress = PlayerProfile(recorded: ["first": 450])

        XCTAssertEqual(Fixture.row("first", progress).recordedSteps, 450)
        XCTAssertEqual(Fixture.row("second", progress).recordedSteps, 0)
    }

    /// A `HealthReading` is a `Double`, so the counter is one. It is FLOORED for display and never
    /// rounded: a counter that read `3000 / 3000` on a map with 2,999.6 steps banked would show a
    /// finish that has not happened.
    func testAPartStepIsFlooredRatherThanRounded() {
        let progress = PlayerProfile(recorded: ["first": 999.7])

        XCTAssertEqual(Fixture.row("first", progress).recordedSteps, 999)
    }

    /// A nil save — the moment before `start()` finishes — reads as a player who has walked
    /// nowhere, rather than as no list at all.
    func testWithNoSaveEveryMapReadsAsUnwalked() {
        let rows = Fixture.rows(nil)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.recordedSteps), [0, 0, 0])
        XCTAssertEqual(rows.filter(\.isSelected).count, 0)
    }
}

// MARK: - AC3: the progress figure, spelled exactly

final class MapListProgressTextTests: XCTestCase {
    /// THE AC, verbatim: `1222 / 25000` — space, slash, space, no abbreviation, no rounding.
    func testProgressIsRenderedExactlyAsTheStoryAsks() {
        let progress = PlayerProfile(recorded: ["second": 1_222], finishedAt: ["first": Fixture.noon])

        XCTAssertEqual(Fixture.row("second", progress).progressText, "1222 / 25000")
    }

    /// No grouping separator, which is the tempting wrong answer: a `NumberFormatter` would render
    /// this as "1,222 / 25,000" in en_US and as "1.222 / 25.000" in de_DE — three different strings
    /// for one criterion that names one.
    func testTheFigureCarriesNoGroupingSeparator() {
        let progress = PlayerProfile(recorded: ["third": 42_000],
                                   finishedAt: ["first": Fixture.noon, "second": Fixture.noon])
        let text = Fixture.row("third", progress).progressText

        XCTAssertEqual(text, "42000 / 50000")
        XCTAssertFalse(text.contains(","), text)
        XCTAssertFalse(text.contains("."), text)
        XCTAssertFalse(text.contains("\u{00A0}"), "no non-breaking space either: \(text)")
    }

    /// The widest realistic figure — a finished map 16 — is five digits either side, which is what
    /// the 41mm screenshot was taken to settle. Asserted here so the day someone lengthens a map
    /// past six digits, the suite says so before the screen does.
    func testTheWidestShippedFigureIsFiveDigitsEachSide() throws {
        let last = try XCTUnwrap(MapCatalog.bundled.maps.last)
        let progress = PlayerProfile(recorded: [last.id: Double(last.totalSteps)])
        let row = try XCTUnwrap(
            MapListRow.rows(in: .bundled, progress: progress).first { $0.id == last.id })

        XCTAssertEqual(row.progressText, "\(last.totalSteps) / \(last.totalSteps)")
        XCTAssertEqual(String(last.totalSteps).count, 5, "map 16's total is five digits")
    }

    /// Not capped at the total, per US-118: the counter keeps climbing past a finish and the row
    /// says so rather than parking on `3000 / 3000` forever.
    func testTheCounterIsNotCappedAtTheTotal() {
        let progress = PlayerProfile(recorded: ["first": 4_500])

        XCTAssertEqual(Fixture.row("first", progress).progressText, "4500 / 1000")
    }
}

// MARK: - AC4: the two marks

final class MapListMarkTests: XCTestCase {
    /// THE AC: the finished mark and the selected mark are visually DIFFERENT from each other. A
    /// row can be both at once — you go on walking the map you have crossed — so one glyph doing
    /// two jobs would make "finished" and "here" indistinguishable exactly when both are true.
    func testTheFinishedAndSelectedMarksAreDifferentGlyphs() {
        XCTAssertNotEqual(MapListMarks.finishedSymbol, MapListMarks.selectedSymbol)
        XCTAssertNotEqual(MapListMarks.finishedSymbol, MapListMarks.lockedSymbol)
        XCTAssertNotEqual(MapListMarks.selectedSymbol, MapListMarks.lockedSymbol)
    }

    /// And none of them is blank, which is the way a "they are different" assertion passes
    /// vacuously.
    func testEveryMarkIsANamedSymbol() {
        for symbol in [MapListMarks.finishedSymbol, MapListMarks.selectedSymbol,
                       MapListMarks.lockedSymbol] {
            XCTAssertFalse(symbol.isEmpty)
        }
    }

    /// The selected map is the one the save says steps are accruing to, and only that one.
    func testExactlyTheSelectedMapIsMarkedSelected() {
        let progress = PlayerProfile(selectedMapId: "first")

        XCTAssertEqual(Fixture.rows(progress).filter(\.isSelected).map(\.id), ["first"])
    }

    /// A save that has chosen nowhere marks nothing — the state every save is in until US-120 ships
    /// the picker.
    func testWithNoSelectionNoRowIsMarked() {
        XCTAssertTrue(Fixture.rows(PlayerProfile()).allSatisfy { !$0.isSelected })
    }

    /// Finished comes off the STAMP, not off `recorded >= total`. The difference bites the day a
    /// map is retuned longer in an update: the player really did cross the old finish line, and a
    /// derived flag would take it back off them.
    func testFinishedIsReadOffTheStampRatherThanRecomputed() {
        let stamped = PlayerProfile(recorded: ["first": 10], finishedAt: ["first": Fixture.noon])
        XCTAssertTrue(Fixture.row("first", stamped).isFinished,
                      "a stamped map stays finished even under a raised total")

        let past = PlayerProfile(recorded: ["first": 9_999])
        XCTAssertFalse(Fixture.row("first", past).isFinished,
                       "no stamp is no finish, however high the counter")
    }

    /// Both marks on one row: the map you finished and are still walking.
    func testAMapCanBeFinishedAndSelectedAtOnce() {
        let progress = PlayerProfile(selectedMapId: "first", recorded: ["first": 1_000],
                                   finishedAt: ["first": Fixture.noon])
        let row = Fixture.row("first", progress)

        XCTAssertTrue(row.isFinished)
        XCTAssertTrue(row.isSelected)
    }
}

// MARK: - AC5: locks

final class MapListLockTests: XCTestCase {
    /// The first map is open from the start; the rest are shut until their predecessor is finished.
    func testOnlyTheStartingMapIsOpenOnAFreshSave() {
        let rows = Fixture.rows(PlayerProfile())

        XCTAssertEqual(rows.filter { !$0.isLocked }.map(\.id), ["first"])
    }

    /// Finishing a map opens exactly the next one, and no more.
    func testFinishingAMapOpensTheNextOneOnly() {
        let progress = PlayerProfile(finishedAt: ["first": Fixture.noon])
        let rows = Fixture.rows(progress)

        XCTAssertEqual(rows.filter { !$0.isLocked }.map(\.id), ["first", "second"])
    }

    /// Walking most of the way is not finishing it. The gate is the stamp, as everywhere else.
    func testPartProgressDoesNotOpenTheNextMap() {
        let progress = PlayerProfile(recorded: ["first": 999])

        XCTAssertTrue(Fixture.row("second", progress).isLocked)
    }

    /// THE AC: a locked row states its condition in one line, naming the map by its DISPLAY name —
    /// "Finish First", never "Finish first" and never an id like "02_river".
    func testALockedRowStatesItsUnlockConditionInOneLine() {
        let rows = Fixture.rows(PlayerProfile())

        XCTAssertEqual(Fixture.row("second", PlayerProfile()).unlockLine, "Finish First")
        XCTAssertEqual(Fixture.row("third", PlayerProfile()).unlockLine, "Finish Second")
        // One line means one line: no newline can get into it.
        XCTAssertTrue(rows.compactMap(\.unlockLine).allSatisfy { !$0.contains("\n") })
    }

    /// Over the shipped chain, every locked row names a real map — the sentence is only useful if
    /// the player can find the place it names.
    func testEveryShippedLockNamesARealMapByItsDisplayName() {
        let rows = MapListRow.rows(in: .bundled, progress: PlayerProfile())
        let names = Set(MapCatalog.bundled.maps.map(\.displayName))

        XCTAssertEqual(rows.filter(\.isLocked).count, 15, "fifteen of sixteen are shut at the start")
        for row in rows where row.isLocked {
            let line = row.unlockLine ?? ""
            XCTAssertTrue(line.hasPrefix("Finish "), line)
            XCTAssertTrue(names.contains(String(line.dropFirst("Finish ".count))), line)
        }
    }

    /// An unlocked row has no unlock line at all — there is nothing left to do about it.
    func testAnUnlockedRowHasNoUnlockLine() {
        XCTAssertNil(Fixture.row("first", PlayerProfile()).unlockLine)
    }

    /// THE AC: a locked map hides its Digitama and its opponent pool. A lock that still counted the
    /// eggs behind it would be a peephole.
    func testALockedRowHidesItsDigitamaAndOpponents() {
        XCTAssertNil(Fixture.row("second", PlayerProfile()).contents)
        XCTAssertNil(Fixture.row("third", PlayerProfile()).contents)
    }

    /// And an unlocked one shows them — otherwise "hides" would be true of every row and the
    /// assertion above would mean nothing.
    func testAnUnlockedRowShowsWhatLivesThere() {
        let contents = Fixture.row("first", PlayerProfile()).contents

        XCTAssertEqual(contents?.digitamaCount, 1)
        XCTAssertEqual(contents?.opponentCount, 3)
    }

    /// The same map, before and after its lock opens: the contents appear when it does.
    func testContentsAppearTheMomentTheLockOpens() {
        XCTAssertNil(Fixture.row("second", PlayerProfile()).contents)

        let opened = PlayerProfile(finishedAt: ["first": Fixture.noon])
        XCTAssertEqual(Fixture.row("second", opened).contents?.digitamaCount, 2)
        XCTAssertEqual(Fixture.row("second", opened).contents?.opponentCount, 1)
    }
}

// MARK: - AC6: tapping

final class MapListSelectionTests: XCTestCase {
    /// THE AC: tapping a LOCKED map does not change the selection. It hands back exactly what was
    /// selected before, rather than nil — "no change" and "no map" are different answers, and the
    /// second would silently move a walking player nowhere.
    func testTappingALockedMapLeavesTheSelectionExactlyAsItWas() {
        let locked = Fixture.row("third", PlayerProfile())

        XCTAssertEqual(MapListSelector.selection(tapping: locked, current: "first"), "first")
        XCTAssertNil(MapListSelector.selection(tapping: locked, current: nil))
    }

    /// A locked row is not selectable, which is what the view disables the button on — so the
    /// refusal is visible before it is felt.
    func testALockedRowIsNotSelectable() {
        XCTAssertFalse(Fixture.row("second", PlayerProfile()).isSelectable)
        XCTAssertTrue(Fixture.row("first", PlayerProfile()).isSelectable)
    }

    /// An unlocked map is what a tap moves the selection to.
    func testTappingAnUnlockedMapSelectsIt() {
        let progress = PlayerProfile(selectedMapId: "first", finishedAt: ["first": Fixture.noon])
        let unlocked = Fixture.row("second", progress)

        XCTAssertEqual(MapListSelector.selection(tapping: unlocked, current: "first"), "second")
    }

    /// The whole rule, played out as the view plays it: taps down a list where only the first map
    /// is open leave the player on the first map, however many locked rows they poke.
    func testAWalkDownTheListOnlyEverLandsOnAnOpenMap() {
        let progress = PlayerProfile()
        var selection: String?

        for row in Fixture.rows(progress) {
            selection = MapListSelector.selection(tapping: row, current: selection)
        }

        XCTAssertEqual(selection, "first")
    }
}

// MARK: - The model seam US-120 pushes this screen from

@MainActor
final class MapListModelTests: XCTestCase {
    /// `MainScreenModel.mapRows` is what `MapListView` is handed, and it is built off the injected
    /// catalog rather than the shipped one — the same seam `selectedMapAsset` uses.
    func testTheModelPublishesRowsForTheCatalogItWasGiven() {
        let model = MainScreenModel(maps: Fixture.catalog)

        // Before `start()` there is no save, and the list still draws — sixteen empty rows are a
        // better answer than a blank screen while the store opens.
        XCTAssertEqual(model.mapRows.map(\.id), ["first", "second", "third"])
        XCTAssertTrue(model.mapRows.allSatisfy { $0.recordedSteps == 0 })
    }
}
