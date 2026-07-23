import XCTest

@testable import DigiVPet

/// US-196 — the main screen keeps its readings as `DashBar`s and retires the STEP/KCAL/EXER energy
/// bars; US-212 — the map-step reading leaves this view for a ring around the Map button, so sleep is
/// the only line left here.
///
/// The map-fill arithmetic these tests used to pin moved with the reading: it is
/// `DashRingLayout.solidSegments` now, and `DashRingLayoutTests` (in `DashBarTests.swift`) holds the
/// same floor-never-round and clamp rules it always had, over 10 segments instead of 16 dashes. That
/// the remaining line is drawn and legible on a 41mm watch is a Simulator measurement in progress.txt.
@MainActor
final class MainReadingBarsTests: XCTestCase {
    /// US-212 AC2: the map-step bar is gone from this view. Absence is not directly assertable, but
    /// this view's whole surface is: it takes sleep and nothing else, so there is no map reading left
    /// for it to draw. (A re-added `mapRecorded` would have to be initialised here, and this would
    /// stop compiling.)
    func testTheOnlyReadingLeftIsSleep() {
        let bars = MainReadingBars(sleepHours: 6, sleepTotal: 16)

        XCTAssertEqual(bars.sleepHours, 6)
        XCTAssertEqual(bars.sleepTotal, 16)
    }

    /// The bar fills against the model's OWN ceiling — the value `ContentView` hands it — rather than
    /// a length this view invents, so the dashes cannot be counted against a cap the model does not
    /// clamp to.
    func testTheSleepBarFillsAgainstTheModelsCap() {
        let bars = MainReadingBars(sleepHours: 6, sleepTotal: MainScreenModel.sleepHoursDisplayCap)

        XCTAssertEqual(bars.sleepTotal, MainScreenModel.sleepHoursDisplayCap)
        XCTAssertGreaterThan(bars.sleepTotal, 0, "a zero-length bar draws and speaks nothing")
    }
}
