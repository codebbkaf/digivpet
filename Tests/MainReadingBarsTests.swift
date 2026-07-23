import XCTest

@testable import DigiVPet

/// US-196 — the main screen keeps two readings, map steps and Zz sleep, each as a `DashBar`, and
/// retires the STEP/KCAL/EXER energy bars.
///
/// What arithmetic can reach: that the map-step bar lights the right fraction of its fixed dashes,
/// with the same floor-never-round and clamp rules the rest of the bars follow. That there are
/// exactly two bars, drawn and legible on a 41mm watch, is a Simulator measurement recorded in
/// progress.txt.
@MainActor
final class MainReadingBarsTests: XCTestCase {
    private let dashes = MainReadingBarLayout.dashes

    /// The bar fills in proportion: a half-walked map lights half its dashes.
    func testAHalfWalkedMapLightsHalfItsDashes() {
        XCTAssertEqual(MainStepBar.filled(recorded: 12_500, total: 25_000, dashes: dashes), dashes / 2)
    }

    /// An untouched map shows an empty bar, and a finished one shows a full bar.
    func testAnUntouchedMapIsEmptyAndAFinishedMapIsFull() {
        XCTAssertEqual(MainStepBar.filled(recorded: 0, total: 25_000, dashes: dashes), 0)
        XCTAssertEqual(MainStepBar.filled(recorded: 25_000, total: 25_000, dashes: dashes), dashes)
    }

    /// Floored, never rounded, like every step counter (`MapListRow.recordedSteps`): one step short
    /// of the finish shows every dash but the last rather than reading as complete.
    func testTheBarIsFlooredSoItNeverReadsAStepEarly() {
        XCTAssertEqual(MainStepBar.filled(recorded: 24_999, total: 25_000, dashes: dashes), dashes - 1)
        // A sliver into the first dash's worth of steps is still zero dashes, not a rounded-up one.
        XCTAssertEqual(MainStepBar.filled(recorded: 1, total: 25_000, dashes: dashes), 0)
    }

    /// A counter past the finish line — a finished map is not capped at `totalSteps` — cannot ask for
    /// a phantom dash beyond the bar.
    func testAnOvershootIsClampedToAFullBar() {
        XCTAssertEqual(MainStepBar.filled(recorded: 30_000, total: 25_000, dashes: dashes), dashes)
    }

    /// A zero-length map or a bar with no dashes draws nothing rather than dividing by zero.
    func testDegenerateInputsDrawNothing() {
        XCTAssertEqual(MainStepBar.filled(recorded: 100, total: 0, dashes: dashes), 0)
        XCTAssertEqual(MainStepBar.filled(recorded: 100, total: 25_000, dashes: 0), 0)
    }

    /// The map bar and the Zz bar are the same length, so the two lines read as a pair. The Zz bar's
    /// length is `MainScreenModel.sleepHoursDisplayCap`.
    func testTheTwoBarsAreTheSameLength() {
        XCTAssertEqual(MainReadingBarLayout.dashes, MainScreenModel.sleepHoursDisplayCap)
    }

    /// End to end: the numbers the strip exposes are the ones the bar fills, in the right order —
    /// `recordedSteps` as the fill and `totalSteps` as the length, not swapped. A half-walked map
    /// through the real `MapStrip.make` seam lights half the bar.
    func testTheStripsStepsFeedTheBarWithoutBeingSwapped() {
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "m", displayName: "M", assetName: "01_grassland",
                         tier: 1, totalSteps: 25_000),
        ])
        let profile = PlayerProfile(selectedMapId: "m")
        profile.record(steps: 12_500, forMap: "m")

        let strip = try! XCTUnwrap(MapStrip.make(in: catalog, progress: profile))

        XCTAssertEqual(strip.recordedSteps, 12_500)
        XCTAssertEqual(strip.totalSteps, 25_000)
        XCTAssertEqual(
            MainStepBar.filled(recorded: strip.recordedSteps, total: strip.totalSteps, dashes: dashes),
            dashes / 2)
    }
}
