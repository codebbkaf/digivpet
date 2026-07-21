import CoreGraphics
import XCTest

@testable import DigiVPet

/// US-089. What the Dex detail sheet's attack row shows, and what it refuses to show.
///
/// `MoveCatalogTests` owns the two-tier lookup and the authored file; this file owns only the
/// screen's rule — the projectile and signature for a discovered entry, nothing at all for an unmet
/// one — and the height budget the row is allowed to spend.
final class DexMoveRowTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled
    private var catalog: MoveCatalog { MoveCatalog.bundled }

    private func row(_ id: String, discovered: Bool) throws -> DexRow {
        let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not in the roster")
        return DexRow(entry: entry, firstDiscovered: discovered ? Date(timeIntervalSince1970: 0) : nil)
    }

    // MARK: - AC: shown for a discovered entry, with the catalog's move

    func testADiscoveredEntryShowsTheMoveTheCatalogResolves() throws {
        let move = try XCTUnwrap(DexMoveRow.move(for: row("agumon", discovered: true),
                                                 in: graph, roster: roster, catalog: catalog))

        XCTAssertEqual(move, catalog.move(for: "agumon", in: graph, roster: roster))
    }

    /// The two things the row actually draws, checked against the catalog rather than against
    /// literals: the glyph is the move's `projectileSymbol` and the name beside it is its
    /// `signatureName`, not the signature's symbol and not some other pairing.
    func testTheSymbolAndNameShownAreTheCatalogsForThatId() throws {
        let move = try XCTUnwrap(DexMoveRow.move(for: row("agumon", discovered: true),
                                                 in: graph, roster: roster, catalog: catalog))
        let expected = catalog.move(for: "agumon", in: graph, roster: roster)

        XCTAssertEqual(move.projectileSymbol, expected.projectileSymbol)
        XCTAssertEqual(move.signatureName, expected.signatureName)
        XCTAssertEqual(move.tint, expected.tint)
    }

    /// A roster-only Digimon with no graph node, so the row is proved to reach the STAGE tier of
    /// the same lookup the battle uses — not just the authored per-id table.
    func testARosterOnlyEntryIsResolvedByTheSameLookup() throws {
        XCTAssertNil(graph.node(id: "megaseadramon"), "test assumes megaseadramon has no node")

        let move = try XCTUnwrap(DexMoveRow.move(for: row("megaseadramon", discovered: true),
                                                 in: graph, roster: roster, catalog: catalog))
        let entry = try XCTUnwrap(roster.entry(id: "megaseadramon"))

        XCTAssertEqual(move, catalog.move(forId: "megaseadramon", line: nil, stage: entry.stage))
    }

    // MARK: - AC: an undiscovered entry shows no row at all

    func testAnUndiscoveredEntryShowsNoRowAtAll() throws {
        let unmet = try row("agumon", discovered: false)

        XCTAssertNil(DexMoveRow.move(for: unmet, in: graph, roster: roster, catalog: catalog))
    }

    /// The rule stated over the whole roster rather than on one hand-picked id: presence is EXACTLY
    /// `isDiscovered`, in both directions, for all 1,022 entries.
    func testPresenceIsExactlyDiscoveryAcrossTheWholeRoster() {
        for entry in roster.entries {
            let met = DexRow(entry: entry, firstDiscovered: Date(timeIntervalSince1970: 0))
            let unmet = DexRow(entry: entry, firstDiscovered: nil)

            XCTAssertNotNil(DexMoveRow.move(for: met, in: graph, roster: roster, catalog: catalog),
                            "\(entry.id) was met and still showed no attack row")
            XCTAssertNil(DexMoveRow.move(for: unmet, in: graph, roster: roster, catalog: catalog),
                         "\(entry.id) leaked its signature before it was ever met")
        }
    }

    /// Every move the roster can produce has something to draw in both slots. A blank glyph or an
    /// empty name is the greyed-out placeholder the AC forbids, arrived at by a different route.
    func testEveryMoveTheRosterCanProduceHasASymbolAndAName() {
        for entry in roster.entries {
            let move = catalog.move(for: entry.id, in: graph, roster: roster)
            XCTAssertFalse(move.projectileSymbol.isEmpty, "\(entry.id) projectile symbol")
            XCTAssertFalse(move.signatureName.isEmpty, "\(entry.id) signature name")
        }
    }

    // MARK: - the row's height budget

    func testTheRowAndTheSpacingItAddsFitTheBudget() {
        XCTAssertEqual(MoveRowLayout.budget, TypeBadgeLayout.budget,
                       "the two identity rows are budgeted alike, so the sheet's cost stays known")
        XCTAssertLessThanOrEqual(MoveRowLayout.height + MoveRowLayout.stackSpacing,
                                 MoveRowLayout.budget)
    }

    /// The content has to fit inside the fixed frame, or the row clips instead of growing. 2pt of
    /// vertical padding above and below the taller of the glyph and the name.
    func testTheRowContentFitsInsideTheFixedRowHeight() {
        let tallest = max(MoveRowLayout.textSize, MoveRowLayout.symbolSize)
        XCTAssertLessThanOrEqual(tallest + 2 * 2, MoveRowLayout.height)
    }
}
