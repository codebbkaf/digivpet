import SwiftUI

/// What one energy bar shows: how much of a type this stage has earned, and the threshold that
/// energy is working toward.
struct EnergyGoal: Equatable, Identifiable {
    let type: EnergyType
    let earned: Int

    /// The nearest `minEnergy` among the current node's edges gated on THIS type, or nil when no
    /// edge out of the node names it.
    ///
    /// Nil is a real answer, not a missing one: nothing out of Agumon is gated on Vitality, and
    /// nothing at all is out of a terminal node. That energy still accrues and still counts toward
    /// `dominantEnergyType`, so the bar shows the amount — it simply has no threshold to fill
    /// toward, and claiming one would be inventing a rule the graph does not contain.
    let target: Int?

    var id: EnergyType { type }
}

/// The four bars for the node currently being raised.
struct EnergyProgress: Equatable {
    /// One goal per energy type, in `EnergyType.allCases` order.
    let goals: [EnergyGoal]

    /// The threshold on TOTAL energy across all four types, for a node gated that way.
    ///
    /// Only a Digitama is: its hatch edge leaves `requiredEnergy` nil because US-018 hatches on
    /// the sum, so no single type gates it — and US-009's validator is what guarantees every other
    /// node's edges name a type, which is why the hatch row below may say "Hatch" outright.
    ///
    /// The four bars then fill toward their SHARE of this, and the hatch row shows the gate
    /// itself. Both are needed: a bar alone would read a 25+25 egg as half way there when it is
    /// in fact ready, and the row alone would not say which types got it there.
    let totalGate: Int?

    /// Energy earned this stage across all four types — what `totalGate` is compared against.
    let totalEarned: Int

    /// How full this type's bar is, in 0...1.
    func fraction(of goal: EnergyGoal) -> Double {
        // A type with no gate of its own falls back to the shared one, where its earnings are a
        // real contribution. With neither, there is nothing to be a fraction OF.
        guard let gate = goal.target ?? totalGate else { return 0 }
        // A threshold of zero is already met. It is legal data, and dividing by it is not.
        guard gate > 0 else { return 1 }
        return min(1, max(0, Double(goal.earned) / Double(gate)))
    }
}

extension EvolutionNode {
    /// The bars to show while this Digimon is the one being raised.
    func energyProgress(for energy: EnergyTotals) -> EnergyProgress {
        EnergyProgress(
            goals: EnergyType.allCases.map { type in
                EnergyGoal(type: type, earned: energy[type], target: target(for: type))
            },
            totalGate: totalGate,
            totalEarned: energy.total
        )
    }

    /// The edges a bar may aim at: the EARNED ones, falling back to the whole list when there are
    /// none.
    ///
    /// US-061 gave every branching Child and Adult a junk fallback at `minEnergy: 0`, reachable by
    /// doing nothing — and a junk edge usually shares an earned branch's type. Aiming at it would
    /// make the lowest-wins rule below pick zero, so the bar would read as already full and the row
    /// would show a target of nothing. A fallback is not a goal; it is what happens when you miss.
    ///
    /// The `earned.isEmpty` case is not a corner: a Digitama's hatch edge is its default, and so is
    /// the single edge out of most Baby and Perfect nodes. Where the fallback is the ONLY way
    /// forward it is genuinely what the bars are working toward, and dropping it would leave a
    /// non-terminal Digimon with four dead bars.
    private var aimableEdges: [EvolutionEdge] {
        let earned = evolutions.filter { !$0.isDefault }
        return earned.isEmpty ? evolutions : earned
    }

    /// The nearest threshold gated on `type`, or nil if no edge out of here names it.
    ///
    /// Lowest wins: several edges may name one type at different thresholds, and what a bar is
    /// working toward is whichever unlocks first.
    private func target(for type: EnergyType) -> Int? {
        aimableEdges.filter { $0.requiredEnergy == type }.map(\.minEnergy).min()
    }

    /// The nearest threshold gated on total energy rather than on any one type.
    private var totalGate: Int? {
        aimableEdges.filter { $0.requiredEnergy == nil }.map(\.minEnergy).min()
    }
}

/// The four energy bars: what this stage has been fed, and how close each type is to the next
/// evolution it can unlock.
struct EnergyBarsView: View {
    let progress: EnergyProgress

    /// Drawn distinct from the other three. Nil for a Digimon that has earned nothing yet, where
    /// there is genuinely no leaning to show (US-015) — so a fresh egg highlights nothing rather
    /// than crowning whichever type happens to sort first.
    let dominant: EnergyType?

    var body: some View {
        // Two by two rather than four stacked rows (US-039). Measured on a 42mm screen, four rows
        // cost 44 of the 136 points the whole screen has; the same four bars in two rows cost 22,
        // and that 22 is most of the difference between a 32pt Digimon and a 48pt one. The pairing
        // is by `EnergyType.allCases` order, so a type does not move between builds.
        VStack(spacing: 2) {
            ForEach(Array(rowPairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 6) {
                    ForEach(pair) { goal in
                        EnergyBarRow(
                            goal: goal,
                            fraction: progress.fraction(of: goal),
                            isDominant: goal.type == dominant
                        )
                    }
                }
            }

            if let gate = progress.totalGate {
                Text("Hatch \(progress.totalEarned)/\(gate)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The goals two at a time. Not `chunked` — there is no such thing in the standard library, and
    /// a stride is clearer than importing Algorithms for one call.
    private var rowPairs: [[EnergyGoal]] {
        stride(from: 0, to: progress.goals.count, by: 2).map { start in
            Array(progress.goals[start..<min(start + 2, progress.goals.count)])
        }
    }
}

/// The widths one energy bar is built from, and the arithmetic that says two of them fit.
///
/// Free-standing rather than constants on the view, in the same spirit as `SpriteScale`: a test
/// should not have to build a view graph to check that a row fits the narrowest screen.
enum EnergyBarLayout {
    /// The name column. Wide enough for the longest of the four short names at `nameFontSize`, in
    /// its BOLD weight — the dominant bar's name is bold — so no label truncates and all four
    /// columns line up.
    ///
    /// That longest label is now four characters, not five: US-113 turned Sleep's "SLEEP" into
    /// "Zz", and the widest thing left to fit is "KCAL", measured at 20.91pt bold on watchOS.
    /// The 4pt this gave back went to `barMinWidth`, not to padding.
    static let nameWidth: CGFloat = 21

    /// Size 8, matching the value column. A word needs more room than the single glyph this
    /// replaced, and the row is as tall as its tallest element, so the point the name gives up in
    /// height is a point the sprite keeps.
    static let nameFontSize: CGFloat = 8

    /// Wide enough for the seed's longest label ("150/150") so the bars line up regardless of
    /// what any one type has earned. Two of these now share a screen width, so it is as tight as
    /// that label allows rather than as tight as it looks.
    static let valueWidth: CGFloat = 28

    static let barHeight: CGFloat = 4

    /// The floor on the bar itself. A bar is the one flexible column, so without a floor a wider
    /// name column would be paid for by the thing the row exists to draw.
    ///
    /// 22 and not 18 since US-113: the 4pt the name column gave up is the bar's, at the floor as
    /// well as above it. `nameWidth + barMinWidth` is unchanged at 43, which is what makes that a
    /// transfer and not a slackening — `rowWidth` still comes to exactly what it did.
    static let barMinWidth: CGFloat = 22

    /// Between the three columns of one bar.
    static let columnSpacing: CGFloat = 3

    /// Between the two bars that share a row.
    static let pairSpacing: CGFloat = 6

    /// The narrowest screen this has to fit: 41mm, 176 points wide. What `rowWidth` is measured
    /// against, and the reason every width above is the tightest that fits rather than whatever
    /// looks comfortable.
    static let narrowestScreenWidth: CGFloat = 176

    /// What two bars cost, with the bars themselves at their floor. Everything left over past this
    /// is width the two bars grow into.
    static var rowWidth: CGFloat {
        2 * (nameWidth + columnSpacing + barMinWidth + columnSpacing + valueWidth) + pairSpacing
    }
}

private struct EnergyBarRow: View {
    let goal: EnergyGoal
    let fraction: Double
    let isDominant: Bool

    /// The dominant bar's colour.
    ///
    /// A literal, deliberately NOT `Color.accentColor`: this target has no asset catalog at all —
    /// the sprites are a folder reference (US-002) — so there is no AccentColor for it to resolve
    /// and watchOS falls back to a neutral gray. Measured on a 41mm screenshot, that gray came out
    /// at (128,128,128) against the (156,156,162) of the `.secondary` used for the other three:
    /// the "highlighted" bar was rendering DIMMER than the ones it is supposed to stand out from.
    /// It built and it ran; only a screenshot could say it was wrong.
    private static let dominantColor = Color.orange

    private var tint: Color { isDominant ? Self.dominantColor : .secondary }

    var body: some View {
        HStack(spacing: EnergyBarLayout.columnSpacing) {
            // Weight carries the distinction too, so the dominant bar is not marked by hue alone.
            // The name says where the energy comes from — STEP, not Strength — so a user reading
            // the bar learns that walking is what fills it (US-085).
            Text(goal.type.shortName)
                .font(.system(size: EnergyBarLayout.nameFontSize,
                              weight: isDominant ? .bold : .regular))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(width: EnergyBarLayout.nameWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: EnergyBarLayout.barHeight)
            .frame(minWidth: EnergyBarLayout.barMinWidth)

            Text(label)
                .font(.system(size: 8, weight: isDominant ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: EnergyBarLayout.valueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.type.displayName)
        .accessibilityValue(accessibilityValue)
    }

    /// A type with no threshold shows its amount alone — "12/0" or "12/—" would both imply a gate
    /// that is not there.
    private var label: String {
        goal.target.map { "\(goal.earned)/\($0)" } ?? "\(goal.earned)"
    }

    private var accessibilityValue: String {
        let amount = goal.target.map { "\(goal.earned) of \($0)" } ?? "\(goal.earned)"
        return isDominant ? "\(amount), dominant" : amount
    }
}
