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

private struct EnergyBarRow: View {
    let goal: EnergyGoal
    let fraction: Double
    let isDominant: Bool

    /// Wide enough for the seed's longest label ("150/150") so the bars line up regardless of
    /// what any one type has earned. Two of these now share a screen width, so it is as tight as
    /// that label allows rather than as tight as it looks.
    private static let labelWidth: CGFloat = 28
    private static let barHeight: CGFloat = 4

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
        HStack(spacing: 3) {
            // Weight carries the distinction too, so the dominant bar is not marked by hue alone.
            // Size 9, not 11: the row is as tall as its tallest element, so the symbol's line
            // height — not the 4pt bar — is what four of these rows actually cost the sprite.
            Text(goal.type.symbol)
                .font(.system(size: 9, weight: isDominant ? .bold : .regular))
                .foregroundStyle(tint)
                .frame(width: 11)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: Self.barHeight)

            Text(label)
                .font(.system(size: 8, weight: isDominant ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.labelWidth, alignment: .trailing)
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
