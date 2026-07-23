import SwiftUI

/// The reading the main screen still shows above the action area: how much the active Digimon has
/// slept, as a `DashBar` (US-171) — the app's one value language.
///
/// It was two readings between US-196 and US-212. The STEP/KCAL/EXER energy bars left in US-196
/// because their readings are already spent elsewhere — steps, calories and exercise convert into
/// train points and battle time — leaving map progress and sleep. US-212 then moved map steps onto a
/// green `DashRing` around the grid's Map button, where every other currency already reads, so the
/// map line is gone from here and the Zz line stands alone. (US-213 rings the Zz reading around a
/// Sleep button the same way, which retires this view entirely.)
struct MainReadingBars: View {
    /// The active Digimon's accumulated sleep hours and the nominal full-bar ceiling (US-182), the
    /// same values the Zz `DashBar` filled while it lived among the energy bars.
    let sleepHours: Int
    let sleepTotal: Int

    var body: some View {
        VStack(spacing: MainReadingBarLayout.rowSpacing) {
            // Zz sleep. The same "Zz" label and bar the sleep row wore among the energy bars,
            // unchanged through two moves — out of the 2×2 grid in US-196, and left standing alone
            // when US-212 took the map line onto the Map button's ring.
            ReadingRow(filled: sleepHours,
                       total: sleepTotal,
                       tint: .secondary,
                       accessibilityLabel: EnergyType.spirit.displayName,
                       accessibilityValue:
                        "\(min(max(sleepHours, 0), max(sleepTotal, 0))) of \(sleepTotal) hours slept") {
                Text(EnergyType.spirit.shortName)
                    .font(.system(size: MainReadingBarLayout.labelFontSize))
            }
        }
    }
}

/// The sizes the reading bar is built from.
///
/// Free-standing for `EnergyBarLayout`'s reason: what the row is made of is checkable here without a
/// Simulator. `MainStepBar` — the map bar's proportional fill — lived here until US-212 moved the
/// reading onto the Map button; the arithmetic went with it and now lives, generalised to every ring
/// in the grid, as `DashRingLayout.solidSegments`.
enum MainReadingBarLayout {
    /// The leading label column, matched to `EnergyBarLayout.nameWidth` so the bar lines its dashes
    /// up exactly where the energy grid used to.
    static let labelWidth: CGFloat = 21

    /// Size 8, matching the energy grid's name column the Zz "Zz" once sat in.
    static let labelFontSize: CGFloat = 8

    /// Between the label and the bar, matched to `EnergyBarLayout.columnSpacing`.
    static let columnSpacing: CGFloat = 3

    /// Between rows. One point, the same gap the energy grid closed to in US-120. One row is left to
    /// space since US-212; it stays because it is the row spacing of this stack, not of a pair.
    static let rowSpacing: CGFloat = 1

    /// The dash height, matched to the four currency bars beneath so every bar on the screen is the
    /// same weight.
    static let barHeight: CGFloat = 5
}

/// One reading line: a leading label and a `DashBar`, sharing `MainReadingBarLayout`'s label width.
/// The label is injected so a row can carry either an SF Symbol or text ("Zz").
private struct ReadingRow<Label: View>: View {
    let filled: Int
    let total: Int
    let tint: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: MainReadingBarLayout.columnSpacing) {
            label()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: MainReadingBarLayout.labelWidth, alignment: .leading)

            // No value column — a `DashBar` shows no number, the dashes are the whole reading.
            DashBar(filled: filled, total: total, tint: tint,
                    dashHeight: MainReadingBarLayout.barHeight, spacing: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}

#Preview {
    MainReadingBars(sleepHours: 6, sleepTotal: 16)
        .padding()
}
