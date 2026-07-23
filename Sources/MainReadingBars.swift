import SwiftUI

/// The two readings the main screen still shows after US-196 retired the STEP/KCAL/EXER energy bars:
/// how far the active Digimon has walked across the current map, and how much it has slept. Each is a
/// `DashBar` (US-171) — the app's one value language — and the two stack as exactly two lines
/// directly above the action area.
///
/// The three spirit-energy bars left the screen because their readings are already spent elsewhere:
/// steps, calories and exercise are converted into train points and battle time. Map progress and
/// sleep are the two things a glance at the raising screen still needs, so they are the two that stay.
struct MainReadingBars: View {
    /// The current map's floored step counter and its length, straight off `MapStrip` — the same
    /// numbers the strip used to spell as "1500 / 25000" before US-196 moved the reading into a bar.
    let mapRecorded: Int
    let mapTotal: Int

    /// The map the steps cross, for VoiceOver: a bare "12 of 16" dash reading says nothing spoken.
    let mapName: String

    /// The active Digimon's accumulated sleep hours and the nominal full-bar ceiling (US-182), the
    /// same values the Zz `DashBar` filled while it lived among the energy bars.
    let sleepHours: Int
    let sleepTotal: Int

    var body: some View {
        VStack(spacing: MainReadingBarLayout.rowSpacing) {
            // Line 1 — map steps. A proportional bar over a FIXED number of dashes, not one dash per
            // step: a map is tens of thousands of steps across, so the reading is the fraction walked
            // drawn as `MainReadingBarLayout.dashes` ticks, the same way the Zz bar draws lifetime
            // sleep against a nominal ceiling rather than a dash per hour lived.
            ReadingRow(filled: MainStepBar.filled(recorded: mapRecorded, total: mapTotal,
                                                  dashes: MainReadingBarLayout.dashes),
                       total: MainReadingBarLayout.dashes,
                       tint: .green,
                       accessibilityLabel: "Adventuring in \(mapName)",
                       accessibilityValue: "\(mapRecorded) of \(mapTotal) steps") {
                // The walking figure the strip used to carry (US-120) makes its home here in US-196,
                // labelling the reading it actually measures rather than sitting redundantly beside
                // the map's name.
                Image(systemName: MainReadingBarLayout.mapSymbol)
                    .font(.system(size: MainReadingBarLayout.labelFontSize))
            }

            // Line 2 — Zz sleep. The same "Zz" label and bar the sleep row wore among the energy
            // bars, unchanged but now standing beside the map bar rather than inside a 2×2 grid.
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

/// The proportional fill of the map-step `DashBar`: how many of `dashes` ticks are solid for a map
/// that is `recorded` of `total` steps walked.
///
/// Free-standing arithmetic rather than a literal buried in `body`, in the spirit of `DashBarLayout`
/// and `EnergyBarLayout`: a test should be able to check that a half-walked map lights half its
/// dashes without standing up a view graph.
enum MainStepBar {
    /// The solid-dash count, floored so the bar never reads as one step further than the player has
    /// actually walked (`MapListRow.recordedSteps`' rule, applied to the dashes): a map at
    /// `total - 1` steps shows every dash but the last, and only `recorded >= total` fills them all.
    /// Clamped to `0...dashes` so a counter that overshoots `total` — a finished map is not capped at
    /// its finish line — cannot ask for a phantom dash.
    static func filled(recorded: Int, total: Int, dashes: Int) -> Int {
        guard total > 0, dashes > 0 else { return 0 }
        let solid = Int((Double(recorded) / Double(total) * Double(dashes)).rounded(.down))
        return min(dashes, max(0, solid))
    }
}

/// The sizes the two reading bars are built from, and the fixed dash count the map-step bar fills.
///
/// Free-standing for `EnergyBarLayout`'s reason: the one fact that is an acceptance criterion — that
/// there are exactly two bars, drawn as dashes — is checkable here without a Simulator.
enum MainReadingBarLayout {
    /// How many dashes the map-step bar is drawn as. Matched to the Zz bar's `sleepHoursDisplayCap`
    /// of 16 so the two lines are the same length and read as a pair rather than as two unrelated
    /// widths.
    static let dashes = 16

    /// The leading label column, matched to `EnergyBarLayout.nameWidth` so the two bars line up their
    /// dashes exactly where the energy grid used to.
    static let labelWidth: CGFloat = 21

    /// Size 8, matching the energy grid's name column the Zz "Zz" once sat in.
    static let labelFontSize: CGFloat = 8

    /// Between the label and the bar, matched to `EnergyBarLayout.columnSpacing`.
    static let columnSpacing: CGFloat = 3

    /// Between the two rows. One point, the same gap the energy grid closed to in US-120.
    static let rowSpacing: CGFloat = 1

    /// The dash height, matched to the four currency bars beneath so every bar on the screen is the
    /// same weight.
    static let barHeight: CGFloat = 5

    /// The map-step bar's leading glyph — the walking figure that used to mark the travelling strip.
    static let mapSymbol = "figure.walk"
}

/// One reading line: a leading label and a `DashBar`, sharing `MainReadingBarLayout`'s label width so
/// the map and Zz bars align. The label is injected so one row can carry an SF Symbol (the walking
/// figure) and the other text ("Zz").
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
    MainReadingBars(mapRecorded: 1_500, mapTotal: 25_000, mapName: "Grassland",
                    sleepHours: 6, sleepTotal: 16)
        .padding()
}
