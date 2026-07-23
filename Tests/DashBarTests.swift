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
