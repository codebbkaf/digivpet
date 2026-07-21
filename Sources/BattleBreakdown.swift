import CoreGraphics

/// What the battle screens SAY about the matchup — the stare-down's caption and the result screen's
/// breakdown of where the player's effective power came from (US-094).
///
/// PURE, and read entirely off the `BattleMatchup` THE FIGHT WAS RESOLVED FROM. Nothing here
/// consults `DigimonElement.beats` or `TrainingResult.battleMultiplier` again, which is the whole
/// point: a second derivation could disagree with the first, and the one case where it certainly
/// would is light vs dark — `DigimonElement.effectiveness(against:)` calls that `.advantage` on both
/// sides while the arithmetic nets exactly 1.0. A screen that recomputed would print "Super
/// effective" over a fight that got no bonus at all.
enum BattleBreakdown {
    /// One thing that moved the player's power, and by how much.
    struct Contribution: Equatable {
        /// What to call it: the grade's name, or the two sides of an axis — "Fire vs Plant".
        let label: String
        /// The signed whole percentage. Never zero; a factor of exactly 1.0 produces no
        /// contribution at all rather than a "+0%" row (AC4).
        let percent: Int

        /// "Perfect +30%", "Water vs Fire -20%".
        var text: String { "\(label) \(percent > 0 ? "+" : "")\(percent)%" }
    }

    /// A multiplier as a signed whole percentage: 1.25 → 25, 0.8 → -20, 1.0 → 0.
    ///
    /// Rounded rather than truncated, so 1.15 is +15% and not +14% — `Double` cannot hold 0.15
    /// exactly, and a grade the user earned must not read a point light because of it.
    static func percent(of factor: Double) -> Int {
        Int(((factor - 1) * 100).rounded())
    }

    /// Every contribution to the PLAYER's effective power, in the order they are applied to it:
    /// the training grade, then the element axis, then the attribute axis.
    ///
    /// Neutral factors are dropped, so an even matchup after an average round lists nothing at all.
    static func contributions(for matchup: BattleMatchup) -> [Contribution] {
        let axes: [(String, Double)] = [
            (matchup.training.displayName, matchup.player.trainingFactor),
            ("\(matchup.playerType.element.displayName) vs \(matchup.opponentType.element.displayName)",
             matchup.player.elementFactor),
            ("\(matchup.playerType.attribute.displayName) vs \(matchup.opponentType.attribute.displayName)",
             matchup.player.attributeFactor)
        ]
        return axes.compactMap { label, factor in
            let percent = percent(of: factor)
            return percent == 0 ? nil : Contribution(label: label, percent: percent)
        }
    }

    /// The contributions as one line, or nil when nothing moved the power — AC4's "no percentage row
    /// at all, rather than a row of +0%".
    static func text(for matchup: BattleMatchup) -> String? {
        let contributions = contributions(for: matchup)
        guard !contributions.isEmpty else { return nil }
        return contributions.map(\.text).joined(separator: separator)
    }

    /// Between two contributions. A middle dot rather than a comma, because every contribution
    /// already ends in a "%" and a comma after it reads as a decimal.
    static let separator = " · "

    /// "PWR 41 → 73", or just "PWR 41" when the matchup left the power exactly where `BattlePower`
    /// scored it — an arrow from a number to itself is noise.
    ///
    /// Both numbers come off the matchup: `basePower` is what `BattlePower` said, `effectivePower`
    /// is what `BattleEngine` was actually handed. So the arrow cannot disagree with the fight.
    static func powerText(for matchup: BattleMatchup) -> String {
        let base = matchup.player.basePower
        let effective = matchup.player.effectivePower
        return base == effective ? "PWR \(base)" : "PWR \(base) → \(effective)"
    }

    /// What the stare-down calls the element pairing, or nil when it is even and there is nothing to
    /// say. Driven by the matchup's `elementEffectiveness`, which is derived from the FACTOR — see
    /// the type note above.
    static func effectivenessCaption(_ effectiveness: Effectiveness) -> String? {
        switch effectiveness {
        case .advantage: return "Super effective"
        case .disadvantage: return "Not very effective"
        case .even: return nil
        }
    }
}

/// What the breakdown costs the two battle screens (US-094 AC5).
///
/// Free-standing for the reason `TypeBadgeLayout` is: the result screen has a sprite, a headline, a
/// line of prose and a Done button already, and the room the breakdown may take is a budget rather
/// than a literal somebody drops into a `body`.
enum BattleBreakdownLayout {
    /// The breakdown's point size — the AC's number, and the same 9pt the result screen's flavour
    /// line beside it uses.
    static let textSize: CGFloat = 9

    /// How far the text may shrink before it truncates instead. The AC's number.
    static let minimumScale: CGFloat = 0.7

    /// Lines the contribution row may wrap to.
    ///
    /// Two rather than one, as headroom for the longest labels. "Perfect +30% · Fire vs Water -20% ·
    /// Vaccine vs Data -10%" — all three axes at once — was screenshotted fitting a 42mm line at the
    /// floor above, but the widest pairing the chart can produce ("Electric vs Machine") is a fifth
    /// longer again, and a truncated breakdown would drop the number it ends on.
    static let lineLimit = 2

    /// The "PWR 41 → 73" line. Larger than the contributions above it and monospaced-digit, because
    /// it is the ANSWER and they are the working.
    static let powerSize: CGFloat = 12

    /// The result screen's stack spacing. Tightened from the 6 it used before the breakdown existed:
    /// two more children at 6pt would have pushed the Done button off a 42mm screen, which is the
    /// one thing AC5 rules out.
    static let resultSpacing: CGFloat = 4
}
