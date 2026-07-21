import CoreGraphics
import XCTest

@testable import DigiVPet

/// US-088. What the Dex detail sheet's badge row shows, and what it refuses to show.
///
/// `ElementTests` owns the vocabulary and `ElementCatalogTests` owns the authored data; this file
/// owns only the screen's rule — badges for a discovered entry, nothing at all for an unmet one —
/// and the height budget the row is allowed to spend.
final class DexTypeBadgeTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled
    private var catalog: ElementCatalog { ElementCatalog.bundled }

    private func row(_ id: String, discovered: Bool) throws -> DexRow {
        let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not in the roster")
        return DexRow(entry: entry, firstDiscovered: discovered ? Date(timeIntervalSince1970: 0) : nil)
    }

    // MARK: - AC: shown for discovered entries, with the catalog's typing

    func testADiscoveredEntryShowsTheTypingTheCatalogResolves() throws {
        let type = try XCTUnwrap(DexTypeBadges.type(for: row("agumon", discovered: true),
                                                    in: graph, catalog: catalog))

        XCTAssertEqual(type, catalog.type(for: "agumon", in: graph))
        XCTAssertEqual(type, DigimonType(element: .fire, attribute: .vaccine))
    }

    /// A roster-only Digimon typed by the keyword tier, so the row is proved to read the same
    /// lookup the battle will — not just the authored `types` table.
    func testARosterOnlyEntryIsTypedByTheSameLookup() throws {
        XCTAssertNil(graph.node(id: "megaseadramon"), "test assumes megaseadramon has no node")

        let type = try XCTUnwrap(DexTypeBadges.type(for: row("megaseadramon", discovered: true),
                                                    in: graph, catalog: catalog))

        XCTAssertEqual(type.element, .water)
    }

    // MARK: - AC: an undiscovered entry shows neither badge

    func testAnUndiscoveredEntryShowsNoBadgesAtAll() throws {
        let unmet = try row("agumon", discovered: false)

        XCTAssertNil(DexTypeBadges.type(for: unmet, in: graph, catalog: catalog))
    }

    /// The rule stated over the whole roster rather than on two hand-picked ids: presence is
    /// EXACTLY `isDiscovered`, in both directions, for all 1,022 entries.
    func testPresenceIsExactlyDiscoveryAcrossTheWholeRoster() {
        for entry in roster.entries {
            let met = DexRow(entry: entry, firstDiscovered: Date(timeIntervalSince1970: 0))
            let unmet = DexRow(entry: entry, firstDiscovered: nil)

            XCTAssertNotNil(DexTypeBadges.type(for: met, in: graph, catalog: catalog),
                            "\(entry.id) was met and still showed no badges")
            XCTAssertNil(DexTypeBadges.type(for: unmet, in: graph, catalog: catalog),
                         "\(entry.id) leaked its typing before it was ever met")
        }
    }

    // MARK: - AC: neutral/free shows those badges rather than an empty row

    func testAnUntypedDigimonShowsNeutralAndFreeRatherThanNothing() throws {
        let untyped = try XCTUnwrap(
            roster.entries.first { catalog.type(for: $0.id, in: graph) == .unauthored },
            "the roster no longer has an untyped Digimon to check the floor with")

        let type = try XCTUnwrap(DexTypeBadges.type(for: row(untyped.id, discovered: true),
                                                    in: graph, catalog: catalog))

        XCTAssertEqual(type, .unauthored)
        XCTAssertEqual(type.element.badgeText, "NEUT")
        XCTAssertEqual(type.attribute.badgeText, "FREE")
    }

    /// Every typing the roster can produce has something to draw in both slots. A badge with an
    /// empty caption is the "empty row" the AC forbids, one badge at a time.
    func testEveryBadgeTheRosterCanProduceHasACaptionAndASymbol() {
        for entry in roster.entries {
            let type = catalog.type(for: entry.id, in: graph)
            XCTAssertFalse(type.element.badgeText.isEmpty, "\(entry.id) element caption")
            XCTAssertFalse(type.element.symbolName.isEmpty, "\(entry.id) element symbol")
            XCTAssertFalse(type.attribute.badgeText.isEmpty, "\(entry.id) attribute caption")
            XCTAssertFalse(type.attribute.symbolName.isEmpty, "\(entry.id) attribute symbol")
        }
    }

    // MARK: - AC: the row costs no more than 16pt of height

    func testTheRowAndTheSpacingItAddsFitTheSixteenPointBudget() {
        XCTAssertEqual(TypeBadgeLayout.budget, 16, "the AC's number, not a knob to loosen")
        XCTAssertLessThanOrEqual(TypeBadgeLayout.height + TypeBadgeLayout.stackSpacing,
                                 TypeBadgeLayout.budget)
    }

    /// The content has to fit inside the fixed frame, or the badges clip instead of the row
    /// growing. 2pt of vertical padding above and below the taller of the two glyphs.
    func testTheBadgeContentFitsInsideTheFixedRowHeight() {
        let tallest = max(TypeBadgeLayout.textSize, TypeBadgeLayout.symbolSize)
        XCTAssertLessThanOrEqual(tallest + 2 * 2, TypeBadgeLayout.height)
    }
}
