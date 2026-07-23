import Foundation
import XCTest

@testable import DigiVPet

/// US-117 — the map catalog validator, against hand-built broken catalogs, plus the AC's run over
/// the REAL shipped `maps.json`.
///
/// Two different jobs in one file, exactly as `EvolutionGraphValidatorTests` does it: the fixtures
/// prove each rule FIRES (a validator that returned [] always would sail through a green-file
/// test), and the real-file test is what fails the build the day someone retunes a map and takes
/// an opponent id or an imageset name with them.
final class MapCatalogValidatorTests: XCTestCase {

    // MARK: - Fixtures

    /// Art existence is stubbed for fixture catalogs — they name imagesets that need not ship, and
    /// a test for the other rules must not fail on that. The real-file tests use the real check.
    private let allAssetsExist: MapCatalog.AssetExistsCheck = { _ in true }

    /// A roster small enough to read: one egg, one playable opponent, one idle-only Digimon.
    private func fixtureRoster() -> Roster {
        Roster(entries: [
            RosterEntry(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama"),
            RosterEntry(id: "foe", displayName: "Foe", stage: .child, spriteFile: "Agumon"),
            RosterEntry(
                id: "idle_only", displayName: "Idle Only", stage: .child, spriteFile: "Poyomon",
                dexOnly: true),
        ])
    }

    private func slot(_ digitamaId: String, hint: String = "Walk 1,000 steps") -> DigitamaSlot {
        DigitamaSlot(
            digitamaId: digitamaId,
            conditions: [EvolutionCondition(
                metric: .healthSteps, window: .stage, comparison: .atLeast, value: 1000,
                hint: hint)])
    }

    /// A minimal SOUND catalog: two maps in a chain, one opponent, one egg. Every fixture below is
    /// this with exactly one thing broken, so a reported error can only be the thing that was
    /// broken.
    private func soundCatalog() -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, opponentPool: ["foe"], digitamaSlots: [slot("egg")]),
            AdventureMap(
                id: "second", displayName: "Second", assetName: "02_river", tier: 2,
                totalSteps: 2000, unlockedBy: "first", opponentPool: ["foe"]),
        ])
    }

    private func errors(_ catalog: MapCatalog) -> [MapValidationError] {
        catalog.validate(roster: fixtureRoster(), assetExists: allAssetsExist)
    }

    /// The control. Without it, every "exactly one error" assertion below could be passing because
    /// the validator flags something unrelated in the baseline.
    func testASoundCatalogHasNoErrors() {
        XCTAssertEqual(errors(soundCatalog()), [])
    }

    // MARK: - AC: rejects an assetName with no matching imageset

    func testReportsAnAssetNameThatResolvesToNoImageset() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "17_moonbase", tier: 1,
                totalSteps: 1000),
        ])

        let found = catalog.validate(roster: fixtureRoster(), assetExists: { $0 == "01_grassland" })

        XCTAssertEqual(found, [.missingAsset(map: "first", assetName: "17_moonbase")])
    }

    /// An empty name is the same finding: `Image("")` draws a missing-resource placeholder rather
    /// than nothing, so it is art that does not exist and not a map without art.
    func testReportsAnEmptyAssetName() {
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "first", displayName: "First", assetName: "", tier: 1, totalSteps: 1000),
        ])

        XCTAssertEqual(
            catalog.validate(roster: fixtureRoster(), assetExists: MapCatalog.assetExists()),
            [.missingAsset(map: "first", assetName: "")])
    }

    // MARK: - AC: rejects an opponentPool id absent from the roster

    func testReportsAnOpponentThatIsInNoRosterEntry() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, opponentPool: ["foe", "nosuchmon"]),
        ])

        XCTAssertEqual(errors(catalog), [.unknownOpponent(map: "first", opponent: "nosuchmon")])
    }

    // MARK: - AC: rejects an opponentPool id whose roster entry is dexOnly

    func testReportsADexOnlyOpponent() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, opponentPool: ["idle_only"]),
        ])

        XCTAssertEqual(errors(catalog), [.dexOnlyOpponent(map: "first", opponent: "idle_only")])
    }

    // MARK: - AC: rejects a digitamaSlots id that is not a roster entry at Stage.digitama

    func testReportsADigitamaSlotThatIsInNoRosterEntry() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, digitamaSlots: [slot("nosuchegg")]),
        ])

        XCTAssertEqual(errors(catalog), [.unknownDigitama(map: "first", digitamaId: "nosuchegg")])
    }

    func testReportsADigitamaSlotNamingSomethingThatIsNotAnEgg() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, digitamaSlots: [slot("foe")]),
        ])

        XCTAssertEqual(
            errors(catalog), [.notADigitama(map: "first", digitamaId: "foe", stage: .child)])
    }

    // MARK: - AC: rejects an unlockedBy that names no map

    func testReportsAnUnlockedByThatNamesNoMap() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, unlockedBy: "atlantis"),
        ])

        XCTAssertEqual(
            errors(catalog), [.unknownUnlockedBy(map: "first", unlockedBy: "atlantis")])
    }

    // MARK: - AC: rejects any cycle in the unlock chain

    func testReportsACycleInTheUnlockChain() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "a", displayName: "A", assetName: "01_grassland", tier: 1, totalSteps: 1000,
                unlockedBy: "c"),
            AdventureMap(
                id: "b", displayName: "B", assetName: "02_river", tier: 1, totalSteps: 2000,
                unlockedBy: "a"),
            AdventureMap(
                id: "c", displayName: "C", assetName: "03_ocean", tier: 1, totalSteps: 3000,
                unlockedBy: "b"),
        ])

        XCTAssertEqual(errors(catalog), [.unlockCycle(maps: ["a", "b", "c"])])
    }

    /// A map that unlocks itself is the degenerate cycle, and the one a naive "did I come back to
    /// where I started" check misses.
    func testReportsAMapThatUnlocksItself() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "a", displayName: "A", assetName: "01_grassland", tier: 1, totalSteps: 1000,
                unlockedBy: "a"),
        ])

        XCTAssertEqual(errors(catalog), [.unlockCycle(maps: ["a"])])
    }

    /// One cycle is ONE finding however many maps hang off it. Three maps walk into the same loop
    /// here, and a per-map report would say the same thing three times.
    func testACycleIsReportedOnceHoweverManyMapsReachIt() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "a", displayName: "A", assetName: "01_grassland", tier: 1, totalSteps: 1000,
                unlockedBy: "b"),
            AdventureMap(
                id: "b", displayName: "B", assetName: "02_river", tier: 1, totalSteps: 2000,
                unlockedBy: "a"),
            AdventureMap(
                id: "tail", displayName: "Tail", assetName: "03_ocean", tier: 1, totalSteps: 3000,
                unlockedBy: "a"),
        ])

        XCTAssertEqual(errors(catalog), [.unlockCycle(maps: ["a", "b"])])
    }

    // MARK: - AC: rejects a DigitamaSlot condition with a blank hint

    func testReportsASlotConditionWithABlankHint() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, digitamaSlots: [slot("egg", hint: "   ")]),
        ])

        XCTAssertEqual(
            errors(catalog),
            [.emptyConditionHint(map: "first", digitamaId: "egg", metric: "health.steps")])
    }

    /// A blank hint is reported even when the slot's id is broken too. The two are independent
    /// mistakes, and reporting only the id would hand the author a second failing run.
    func testABrokenSlotIdDoesNotHideItsBlankHint() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000, digitamaSlots: [slot("nosuchegg", hint: "")]),
        ])

        XCTAssertEqual(errors(catalog), [
            .emptyConditionHint(map: "first", digitamaId: "nosuchegg", metric: "health.steps"),
            .unknownDigitama(map: "first", digitamaId: "nosuchegg"),
        ])
    }

    // MARK: - US-184: rejects a slot condition over a window the evaluator can never answer

    /// The three unanswerable pairs the PRD names fire the rule on a slot exactly as they do on an
    /// edge: `care.battleCount` has no per-STAGE counter, `care.battleWinRatio` is LIFETIME-only,
    /// and `care.trainingSessions` is STAGE-only. This is the Digitama-slot bug class US-184 catches.
    func testReportsSlotConditionsAuthoredOverAnUnanswerableWindow() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000,
                digitamaSlots: [DigitamaSlot(
                    digitamaId: "egg",
                    conditions: [
                        EvolutionCondition(metric: .careBattleCount, window: .stage, comparison: .atLeast, value: 5, hint: "Battle 5 times"),
                        EvolutionCondition(metric: .careBattleWinRatio, window: .day, comparison: .atLeast, value: 0.5, hint: "Win half your battles"),
                        EvolutionCondition(metric: .careTrainingSessions, window: .lifetime, comparison: .atLeast, value: 3, hint: "Train 3 times"),
                    ])]),
        ])

        XCTAssertEqual(errors(catalog), [
            .unanswerableConditionWindow(map: "first", digitamaId: "egg", metric: "care.battleCount", window: .stage),
            .unanswerableConditionWindow(map: "first", digitamaId: "egg", metric: "care.battleWinRatio", window: .day),
            .unanswerableConditionWindow(map: "first", digitamaId: "egg", metric: "care.trainingSessions", window: .lifetime),
        ])
    }

    /// The same metrics over the window each IS kept in draw no finding — the rule rejects the
    /// mis-windowing, not the metric.
    func testAcceptsSlotCareMetricsOverTheirAnswerableWindows() {
        let catalog = MapCatalog(maps: [
            AdventureMap(
                id: "first", displayName: "First", assetName: "01_grassland", tier: 1,
                totalSteps: 1000,
                digitamaSlots: [DigitamaSlot(
                    digitamaId: "egg",
                    conditions: [
                        EvolutionCondition(metric: .careBattleCount, window: .lifetime, comparison: .atLeast, value: 5, hint: "Battle 5 times"),
                        EvolutionCondition(metric: .careTrainingSessions, window: .stage, comparison: .atLeast, value: 3, hint: "Train 3 times"),
                    ])]),
        ])

        XCTAssertEqual(errors(catalog), [])
    }

    // MARK: - The shipped file

    /// THE AC, and the reason the rest of this file exists: the catalog that ships is sound —
    /// against the REAL roster and the REAL asset catalog, not a stub.
    ///
    /// US-184 added the unanswerable-window rule but deferred the data fix; US-186 did it — the
    /// `care.battleCount`/`care.battleWinRatio` slots that were windowed per `stage` (a window neither
    /// counter is kept over, so their eggs could never drop) are now `lifetime`, and the lone
    /// `care.trainingSessions` slot windowed per `lifetime` is now `stage`. So the shipped catalog
    /// reports NOTHING — the allowlist that tracked those findings is gone and this is `== []` again.
    func testTheShippedCatalogHasNoFindings() throws {
        let found = try MapCatalog.load().validate()
        XCTAssertEqual(found, [], found.map(\.description).joined(separator: "\n"))
    }

    /// And the real asset check is a check: a name that ships resolves, one that does not, does
    /// not. Without this the test above could be green because `assetExists` said yes to
    /// everything.
    func testTheRealAssetCheckDistinguishesShippedArtFromMissingArt() {
        let assetExists = MapCatalog.assetExists()

        XCTAssertTrue(assetExists("01_grassland"))
        XCTAssertFalse(assetExists("17_moonbase"))
        XCTAssertFalse(assetExists(""))
    }
}
