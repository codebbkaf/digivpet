import CoreGraphics
import SwiftUI

/// How much of the Dex detail sheet the three stat rows are allowed to cost (US-187).
///
/// The same arithmetic-not-literals treatment `MoveRowLayout` and `TypeBadgeLayout` get: the sheet
/// is fought over pixel by pixel on a 41mm screen, so what the stat block spends is stated here
/// where a later edit has to argue with it rather than buried in a `body`.
enum StatBarsLayout {
    /// One dash bar's height. Level with the sleep bar's `DashBar` above it and shorter than the
    /// currency bars on the main screen — three of these stack, so each is kept lean.
    static let barHeight: CGFloat = 5

    /// Between the three stacked rows.
    static let rowSpacing: CGFloat = 3

    /// The label glyph's point size, a shade under the move name above so the identity block reads
    /// name → attack → stats in a descending weight rather than as three equal shouts.
    static let iconSize: CGFloat = 9

    /// A fixed column for the glyph so all three bars start at one left edge no matter how wide the
    /// heart, the burst and the hare each draw.
    static let iconWidth: CGFloat = 12

    /// Between the glyph and its bar.
    static let spacing: CGFloat = 4

    /// The whole vertical cost the block may add to the sheet: three bars and the two gaps between
    /// them. Stated so the candidate tiles US-064 fought above the fold have a known budget to
    /// measure this addition against.
    static let budget: CGFloat = 3 * barHeight + 2 * rowSpacing
}

/// One of the three battle stats every playable Digimon carries (US-187), paired with how it draws.
///
/// A stat's bar length IS its value — `filled == total`, all dashes solid — so a Perfect's longer HP
/// bar reads as more health than a Child's at a glance, with no number anywhere. Training bonuses
/// (US-192) will later fill toward a `base + cap` total; the base stat is all this story shows.
enum BattleStat: CaseIterable {
    case hp
    case attack
    case agility

    /// This stat's value out of a stage's table.
    func value(in stats: StageStats) -> Int {
        switch self {
        case .hp: return stats.baseHP
        case .attack: return stats.baseAttack
        case .agility: return stats.baseAgility
        }
    }

    /// The SF Symbol that labels the row. A heart for health, an impact burst for attack, a hare for
    /// agility — icons rather than words, so the block stays legible on the narrowest watch.
    var symbol: String {
        switch self {
        case .hp: return "heart.fill"
        case .attack: return "burst.fill"
        case .agility: return "hare.fill"
        }
    }

    /// The bar's hue, distinct per stat so the three read apart at a glance and the glyph and its
    /// dashes are plainly one row.
    var tint: Color {
        switch self {
        case .hp: return .red
        case .attack: return .orange
        case .agility: return .green
        }
    }

    /// What VoiceOver speaks for the row — the label the AC asks the bars to carry. The value is
    /// spoken here for a screen reader even though no digit is drawn, exactly as `DashBar` speaks
    /// its own "N of N".
    var accessibilityName: String {
        switch self {
        case .hp: return "Health"
        case .attack: return "Attack"
        case .agility: return "Agility"
        }
    }
}

/// What the Dex detail sheet's stat block shows, resolved without a view.
///
/// Split out for the reason `DexMoveRow` and `DexTypeBadges` are: "shown exactly when discovered and
/// playable" is then a fact a test can assert directly, with no view graph to stand up.
enum DexStatBars {
    /// This entry's base battle stats, or nil when the block must not be shown.
    ///
    /// Nil for an UNDISCOVERED entry — the block is then absent entirely, the same withholding the
    /// attack row and type badges apply, so an unmet Digimon leaks neither how strong it is nor that
    /// it fights at all. Nil for a `dexOnly` idle-only entry and for a Digitama, which have no
    /// combat stats (`ConsumptionConfig.stats(for:)`). Every other playable, discovered Digimon
    /// resolves all three off its stage.
    static func stats(for row: DexRow,
                      roster: Roster = .bundled,
                      config: ConsumptionConfig = .bundled) -> StageStats? {
        guard row.isDiscovered, let entry = roster.entry(id: row.id) else { return nil }
        return config.stats(for: entry)
    }
}

/// The three labelled stat dash bars — HP, Attack, Agility — on the Dex detail sheet (US-187).
///
/// Stacked rather than side by side so each bar gets the sheet's full width and its length reads as
/// the stat's magnitude. Every bar is `filled == total`, all solid: the base stat is a fixed value,
/// not a progress meter, so there is nothing to leave as outline yet.
struct StatBarsRow: View {
    let stats: StageStats

    var body: some View {
        VStack(spacing: StatBarsLayout.rowSpacing) {
            ForEach(BattleStat.allCases, id: \.self) { stat in
                let value = stat.value(in: stats)
                HStack(spacing: StatBarsLayout.spacing) {
                    Image(systemName: stat.symbol)
                        .font(.system(size: StatBarsLayout.iconSize))
                        .foregroundStyle(stat.tint)
                        .frame(width: StatBarsLayout.iconWidth)

                    DashBar(filled: value, total: value, tint: stat.tint,
                            dashHeight: StatBarsLayout.barHeight)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stat.accessibilityName): \(value)")
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    VStack(spacing: 8) {
        StatBarsRow(stats: StageStats(baseHP: 5, baseAttack: 3, baseAgility: 3, trainingCap: 4))
        Divider()
        StatBarsRow(stats: StageStats(baseHP: 9, baseAttack: 7, baseAgility: 5, trainingCap: 8))
    }
    .padding()
}
