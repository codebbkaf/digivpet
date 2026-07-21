import CoreGraphics
import SwiftUI

/// How much of the Dex detail sheet the type badge row is allowed to cost (US-088).
///
/// Free-standing arithmetic rather than literals inside the view, for the reason `SickBadgeLayout`
/// is: US-064 spent two rounds of 41mm screenshots buying enough height to keep the candidate tiles
/// above the fold, and a budget that only exists as a `.font(.system(size: 9))` somewhere in a
/// `body` is one a later edit spends without noticing. A test asserts the sum below.
enum TypeBadgeLayout {
    /// The whole vertical cost the row may add to the sheet — the AC's number, verbatim.
    static let budget: CGFloat = 16

    /// The row's own height. Fixed with `.frame(height:)` rather than left to the text, so a
    /// Dynamic Type setting cannot grow it into the tiles below.
    static let height: CGFloat = 14

    /// The `VStack` spacing the sheet pays once for having one more child. Not read by the view —
    /// `DexDetailView` owns the stack — but it is part of what inserting the row costs, so it is
    /// part of what the budget is checked against.
    static let stackSpacing: CGFloat = 2

    /// The badge caption's point size. Smaller than the 10pt subtitle above it: the badges are a
    /// label on the Digimon, not another line of prose.
    static let textSize: CGFloat = 9

    /// The symbol's point size, a shade under the text so the glyph reads as a bullet beside the
    /// word rather than competing with it.
    static let symbolSize: CGFloat = 8

    /// Between the two badges. Wide enough that "FIRE" and "VAC" never read as one word on 41mm.
    static let spacing: CGFloat = 4
}

/// What the Dex detail sheet's badge row shows, resolved without a view.
///
/// Split out so "a discovered entry has a typing, an unmet one has none" is a fact a test can
/// assert directly — the same reason `SickBadgeLayout` is not a computed property on its view.
enum DexTypeBadges {
    /// This row's typing, or nil when it must not be shown.
    ///
    /// Nil for an UNDISCOVERED entry, because the typing is part of what discovery reveals: telling
    /// a player that the "?" three branches away is a Dark Virus would answer the question the Dex
    /// exists to make them go and answer, exactly as naming it would (`DexCandidateCell`).
    ///
    /// Never nil for a discovered one. The ~776 roster Digimon nobody has typed resolve to
    /// `DigimonType.unauthored`, and Neutral/Free are drawn as badges like any other pair — an
    /// empty row where every other Digimon has two badges reads as a bug, and "we have not typed
    /// this one" is a true thing to say out loud.
    static func type(for row: DexRow,
                     in graph: EvolutionGraph = .bundled,
                     catalog: ElementCatalog = .bundled) -> DigimonType? {
        guard row.isDiscovered else { return nil }
        return catalog.type(for: row.id, in: graph)
    }
}

/// The element and attribute badges, side by side (US-088).
///
/// Both halves are drawn the same way on purpose, even though the element is the headline axis and
/// the attribute is the weaker canon triangle (D-2): the pair is read as one answer to "what am I
/// looking at", and styling one louder than the other would suggest a precedence the battle
/// arithmetic does not have.
///
/// Not a `Button` and not a `NavigationLink`. The counter chart is US-086's `beats` table and has
/// no screen yet; a badge that looked tappable and went nowhere would be worse than a badge that
/// plainly does not.
struct TypeBadgeRow: View {
    let type: DigimonType

    var body: some View {
        HStack(spacing: TypeBadgeLayout.spacing) {
            badge(symbol: type.element.symbolName, text: type.element.badgeText,
                  tint: type.element.color, label: "Element: \(type.element.displayName)")

            badge(symbol: type.attribute.symbolName, text: type.attribute.badgeText,
                  tint: type.attribute.color, label: "Attribute: \(type.attribute.displayName)")
        }
        .frame(height: TypeBadgeLayout.height)
    }

    /// One badge: symbol, short name, and a capsule of its own colour at low opacity.
    ///
    /// The fill is faint rather than solid because `DigimonElement.light` is white and `.neutral`
    /// is `.secondary` — a solid capsule would need a second, contrasting foreground colour per
    /// element, which is a second table to keep in step with the first.
    private func badge(symbol: String, text: String, tint: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: TypeBadgeLayout.symbolSize))

            Text(text)
                .font(.system(size: TypeBadgeLayout.textSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(tint.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack(spacing: 6) {
        TypeBadgeRow(type: DigimonType(element: .fire, attribute: .vaccine))
        TypeBadgeRow(type: .unauthored)
    }
}
