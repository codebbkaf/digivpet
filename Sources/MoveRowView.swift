import CoreGraphics
import SwiftUI

/// How much of the Dex detail sheet the attack row is allowed to cost (US-089).
///
/// The same arithmetic-not-literals treatment `TypeBadgeLayout` gets, and for a sharper reason: the
/// 41mm screenshot US-088 left behind had about zero slack under the candidate tiles, so this row is
/// the second thing in a row to be charged against a 215pt screen. A budget stated here is one a
/// later edit has to argue with; a `.font(.system(size: 9))` buried in a `body` is not.
enum MoveRowLayout {
    /// The whole vertical cost the row may add to the sheet — matched to `TypeBadgeLayout.budget`
    /// so the two identity rows together cost a known 32pt rather than whatever they grow into.
    static let budget: CGFloat = 16

    /// The row's own height. Fixed with `.frame(height:)` rather than left to the text, for the
    /// reason the badge row is: a Dynamic Type setting must not push the tiles below the fold.
    static let height: CGFloat = 14

    /// The `VStack` spacing the sheet pays once for having one more child. Not read by the view —
    /// `DexDetailView` owns the stack — but it is part of what inserting the row costs.
    static let stackSpacing: CGFloat = 2

    /// The move name's point size. Level with the badge captions above it: the two rows are one
    /// identity block, and a larger name here would read as a heading over the badges.
    static let textSize: CGFloat = 9

    /// The projectile glyph's point size, a shade over the text so the thing being thrown is what
    /// the eye lands on. The reverse of `TypeBadgeLayout`, where the symbol is the bullet and the
    /// word is the answer; here the glyph IS the answer and the name labels it.
    static let symbolSize: CGFloat = 10

    /// Between the glyph and the name.
    static let spacing: CGFloat = 3
}

/// What the Dex detail sheet's attack row shows, resolved without a view.
///
/// Split out for the reason `DexTypeBadges` is: "shown exactly when discovered" is then a fact a
/// test can assert directly, with no view graph to stand up.
enum DexMoveRow {
    /// This row's attack identity, or nil when it must not be shown.
    ///
    /// Nil for an UNDISCOVERED entry, and the row is then absent entirely rather than greyed out.
    /// A placeholder would leak that a signature exists and roughly how long its name is, which is
    /// the same leak `DexCandidateCell` withholds a candidate's NAME to avoid — a dimmed
    /// "Pepper Breath"-shaped smudge answers most of the question the Dex exists to ask.
    ///
    /// Never nil for a discovered one: `MoveCatalog` falls back id → line → stage and the bundled
    /// file authors every stage, so every one of the 1,022 roster entries throws something.
    static func move(for row: DexRow,
                     in graph: EvolutionGraph = .bundled,
                     roster: Roster = .bundled,
                     catalog: MoveCatalog = .bundled) -> Move? {
        guard row.isDiscovered else { return nil }
        return catalog.move(for: row.id, in: graph, roster: roster)
    }
}

/// The projectile glyph and the signature move's name, on one line (US-089).
///
/// The ORDINARY projectile's symbol rather than the signature's, even though the name beside it is
/// the signature's: the projectile is what this Digimon throws every turn, so it is the truer
/// picture of what fighting it looks like, and on most authored moves the two glyphs are the same
/// anyway. `BattleView` is where the signature symbol earns its size, on the one turn it lands.
///
/// Not a `Button` and not a `NavigationLink`, as `TypeBadgeRow` is not: there is no move detail
/// screen to reach, and a row that looked tappable and went nowhere would be worse than one that
/// plainly does not.
struct MoveRow: View {
    let move: Move

    var body: some View {
        HStack(spacing: MoveRowLayout.spacing) {
            Image(systemName: move.projectileSymbol)
                .font(.system(size: MoveRowLayout.symbolSize, weight: .bold))

            Text(move.signatureName)
                .font(.system(size: MoveRowLayout.textSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // Both halves in the move's tint, glyph and name alike, so the row reads as one attack
        // rather than as a coloured icon with an unrelated caption. It is the same pairing
        // `signatureBanner` draws in the arena, which is where the player sees it next.
        .foregroundStyle(move.tint.color)
        .frame(height: MoveRowLayout.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signature move: \(move.signatureName)")
    }
}

#Preview {
    VStack(spacing: 6) {
        MoveRow(move: Move(projectileSymbol: "flame.fill", tint: .red,
                           signatureName: "Pepper Breath", signatureSymbol: "flame.fill"))
        MoveRow(move: .placeholder)
    }
}
