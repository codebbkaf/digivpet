import XCTest

@testable import DigiVPet

/// US-171 — the reusable dash-bar layout: `total` dashes, the first `filled` solid and the rest
/// outline, no digits. These pin the arithmetic the sightless bar depends on — the counts and the
/// clamping — so a later story that restyles the view cannot quietly change what it shows.
final class DashBarTests: XCTestCase {

    private func counts(filled: Int, total: Int) -> (solid: Int, outline: Int) {
        let dashes = DashBarLayout.dashes(filled: filled, total: total)
        return (dashes.filter { $0 == .solid }.count, dashes.filter { $0 == .outline }.count)
    }

    /// THE AC: solid dashes == min(filled, total) and outline dashes == total - min(filled, total),
    /// across filled in {0, half, total, total+1}.
    func testDashCountsAcrossFilledValues() {
        let total = 16
        for filled in [0, total / 2, total, total + 1] {
            let (solid, outline) = counts(filled: filled, total: total)
            let expectedSolid = min(filled, total)
            XCTAssertEqual(solid, expectedSolid, "solid count at filled=\(filled)")
            XCTAssertEqual(outline, total - expectedSolid, "outline count at filled=\(filled)")
            XCTAssertEqual(solid + outline, total, "every dash is one or the other at filled=\(filled)")
        }
    }

    /// total==0 renders nothing.
    func testTotalZeroRendersNoDashes() {
        XCTAssertTrue(DashBarLayout.dashes(filled: 3, total: 0).isEmpty)
        XCTAssertTrue(DashBarLayout.dashes(filled: 0, total: 0).isEmpty)
        XCTAssertTrue(DashBarLayout.dashes(filled: 3, total: -1).isEmpty)
    }

    /// A negative filled clamps to zero solid rather than stealing from the outline count.
    func testNegativeFilledClampsToZeroSolid() {
        let (solid, outline) = counts(filled: -5, total: 8)
        XCTAssertEqual(solid, 0)
        XCTAssertEqual(outline, 8)
    }

    /// The first `filled` dashes are the solid ones and the tail is outline — order, not just count.
    func testSolidDashesLeadAndOutlineFollows() {
        let dashes = DashBarLayout.dashes(filled: 6, total: 16)
        XCTAssertEqual(dashes.prefix(6), ArraySlice(repeating: .solid, count: 6))
        XCTAssertEqual(dashes.suffix(10), ArraySlice(repeating: .outline, count: 10))
    }
}

private extension ArraySlice where Element == Dash {
    init(repeating value: Dash, count: Int) {
        self = ArraySlice(Array(repeating: value, count: count))
    }
}

/// US-212 — every progress ring in the action grid is cut into the same ten segments with the same
/// divider gap, whatever the economy behind it counts, and a partial value fills a floored number of
/// them. These pin the arithmetic the five rings now share; that they LOOK alike in a row is a
/// Simulator screenshot recorded in progress.txt.
@MainActor
final class DashRingLayoutTests: XCTestCase {
    /// AC3: ten segments, one spacing, one place. "10 space" is the whole point of the story, so it
    /// is pinned as a number rather than left to whatever the last ring happened to pass.
    func testTheGridHasOneSegmentCountAndOneSpacing() {
        XCTAssertEqual(DashRingLayout.segments, 10)
        XCTAssertGreaterThan(DashRingLayout.gapDegrees, 0, "a ring with no gaps is one circle")
        // A gap is carved off BOTH ends of each 36° segment, so anything from 36° up would leave no
        // arc at all to draw.
        XCTAssertLessThan(DashRingLayout.gapDegrees, 360.0 / Double(DashRingLayout.segments),
                          "the gap must not swallow the segment it divides")
    }

    /// AC3, through the view: the five rings the grid draws are built from five DIFFERENT caps — meat
    /// 20, train 10, battle 10, clean 8, and a map tens of thousands of steps long — and every one of
    /// them still shows ten segments, empty at zero and all ten when full. Before this story each ring
    /// drew one arc per unit, so those five caps gave three different tick densities in one row.
    func testEveryRingIsTenSegmentsWhateverItsEconomyCounts() {
        let config = ConsumptionConfig.bundled
        let caps = [config.meatCap, config.maxTrainCharges, config.maxBattleCharges,
                    config.maxCleanCharges, 25_000]

        for cap in caps {
            XCTAssertEqual(DashRing(filled: 0, total: cap).solid, 0, "empty, at a cap of \(cap)")
            XCTAssertEqual(DashRing(filled: cap, total: cap).solid, DashRingLayout.segments,
                           "full, at a cap of \(cap)")
            XCTAssertEqual(DashRing(filled: cap / 2, total: cap).solid,
                           DashRingLayout.segments / 2, "half, at a cap of \(cap)")
        }
    }

    /// AC4: a partial value lights the floored share of the ten. A cap of 20 puts two units in each
    /// segment, so 7 meat is three and a half segments' worth and lights three.
    func testAPartialValueLightsTheFlooredShareOfTheTen() {
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 7, total: 20), 3)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 8, total: 20), 4)
        // A cap that is not a multiple of ten rounds the same way: 1 clean charge of 8 is 1.25
        // segments and lights one; 7 of 8 is 8.75 and lights eight.
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 1, total: 8), 1)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 7, total: 8), 8)
    }

    /// AC4's rounding rule at both ends: nothing is ever shown a step early, and a ring reads full
    /// only when the value actually is. A value below a tenth of its cap shows an empty ring — the
    /// documented cost of ten segments standing for twenty units.
    func testTheFillIsFlooredSoNothingReadsEarly() {
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 24_999, total: 25_000),
                       DashRingLayout.segments - 1, "one step short of the end is not the end")
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 19, total: 20),
                       DashRingLayout.segments - 1, "one meal short of a full larder is not full")
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 1, total: 20), 0,
                       "half a segment's worth lights no segment")
    }

    /// A count read mid-tick that overshoots its cap, and a map walked past its finish line, cannot
    /// light an eleventh arc; a negative value cannot unlight one.
    func testAnOvershootIsClampedAndANegativeIsFloored() {
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 30_000, total: 25_000),
                       DashRingLayout.segments)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 21, total: 20), DashRingLayout.segments)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: -3, total: 20), 0)
    }

    /// An economy that does not exist fills nothing rather than dividing by zero — the same rule the
    /// ring's `opacity` follows when it hides itself at `total <= 0`.
    func testAnAbsentEconomyFillsNothing() {
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 100, total: 0), 0)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 100, total: -1), 0)
        XCTAssertEqual(DashRingLayout.solidSegments(filled: 100, total: 20, segments: 0), 0)
    }
}
