import Foundation

/// How much of a condition the player has earned the right to be told.
///
/// Three levels and not a percentage, because a percentage IS the number — "73% of the way to
/// 10,000 steps" hands back the threshold by division, which is the one thing `ConditionHint`
/// exists to withhold. Three coarse buckets carry the only information the player actually needs
/// out of a hint ("am I pushing the right way?") while leaving the line itself undiscoverable by
/// arithmetic.
enum RevealLevel: Equatable, CaseIterable {
    /// Under halfway. The flavour text alone — no acknowledgement that anything has moved.
    case far
    /// Halfway or better, but not there. The flavour text plus a warmer qualifier.
    case close
    /// The condition holds. Drawn with a checkmark.
    case met

    /// The extra sentence appended to the hint at this level, if any.
    ///
    /// Only `close` has one. `far` says nothing extra because a nudge at 0% and a nudge at 49%
    /// should read identically — a qualifier that appeared at 10% would let a player bisect the
    /// threshold by watching for when the wording changes. `met` says nothing extra because the
    /// checkmark has already said it, and a sentence beside a checkmark is the same fact twice.
    var qualifier: String? {
        switch self {
        case .far: return nil
        case .close: return "It is starting to notice."
        case .met: return nil
        }
    }
}

/// Turns a condition plus what is currently true into the one line the player sees.
///
/// Pure and view-free, exactly like `ConditionHint`: it takes a `ConditionContext` value and
/// returns text and a level, so `ConditionRevealTests` can pin every boundary without a store, a
/// clock or SwiftUI. The view's only job is to pick a symbol for the level.
enum ConditionReveal {
    /// The fraction of `progress` at which a hint warms up. Named rather than inlined because the
    /// boundary is the thing under test — `just under`, `exactly`, and `met` in the story's words.
    static let closeThreshold = 0.5

    /// How far along this condition is, from 0 through 1.
    ///
    /// **Never leaves this file's vocabulary as a number the player can see** — it feeds `level`
    /// and nothing else. It is `internal` only so the tests can pin the boundary arithmetic
    /// directly rather than inferring it from which bucket came out.
    ///
    /// Three cases, and the two unobvious ones are deliberate:
    ///
    /// - **Unknown reads as 0, not as "no opinion".** A metric nothing can answer — denied
    ///   authorization, a standing measurement with no reading — must not warm a hint up. The
    ///   player would read the warmer line as "keep doing what you are doing" when the app cannot
    ///   see whether they are doing it at all. This is the same call `ConditionEvaluator` makes for
    ///   the same reason.
    /// - **An unsatisfied `atMost` is 0, not a ratio.** An `atMost` gate starts satisfied and can
    ///   only ever be broken: every counter it is authored against — overfeeds, sleep
    ///   disturbances, training sessions on a junk branch — grows and never shrinks within a
    ///   stage. So there is no "getting closer" to it, only "still fine" and "spent". Grading the
    ///   overshoot would show a hint cooling from close to far as the player did more of the
    ///   wrong thing, which reads as progress in the wrong direction.
    static func progress(of condition: EvolutionCondition, in context: ConditionContext) -> Double {
        if ConditionEvaluator.isSatisfied(condition, in: context) { return 1 }
        // Unsatisfied and `atMost` means overshot; unsatisfied and `atLeast` with a threshold at or
        // below zero is unreachable (any known value would satisfy it), so both are nothing earned.
        guard condition.comparison == .atLeast, condition.value > 0 else { return 0 }
        guard let metric = condition.knownMetric,
              case .known(let value) = context.value(for: metric, window: condition.window)
        else { return 0 }
        return min(max(value / condition.value, 0), 1)
    }

    /// Which of the three levels this condition is at.
    ///
    /// `met` is decided by `ConditionEvaluator`, not by `progress >= 1`, so the checkmark and the
    /// evolution engine can never disagree about whether a criterion holds — one of them rounding
    /// differently than the other would put a checkmark on a branch that does not open.
    static func level(of condition: EvolutionCondition, in context: ConditionContext) -> RevealLevel {
        if ConditionEvaluator.isSatisfied(condition, in: context) { return .met }
        return progress(of: condition, in: context) >= closeThreshold ? .close : .far
    }

    /// The full line for a condition: its hint, warmed up if the player has earned it.
    ///
    /// The hint is left EXACTLY as authored when there is no qualifier — this is the line US-065
    /// wrote and pinned, and the only thing that may follow it is the warmer sentence.
    static func line(for condition: EvolutionCondition, in context: ConditionContext) -> String {
        let level = level(of: condition, in: context)
        let hint = ConditionHint.resolve(for: condition)
        guard let qualifier = level.qualifier else { return hint }
        return "\(sentence(hint)) \(qualifier)"
    }

    /// A hint with a full stop, so a qualifier joined onto it reads as two sentences.
    ///
    /// The metric defaults all end in one; the hints authored in `evolutions.json` are fragments
    /// that do not ("Walk with it most days"). Concatenating those gave "Walk with it most days It
    /// is starting to notice." on the 41mm screenshot, which reads as one broken sentence. Punctuate
    /// here rather than editing the authored hints, because a hint is shown UNqualified far more
    /// often than not and the fragment is the right shape for that.
    private static func sentence(_ hint: String) -> String {
        guard let last = hint.last, !".!?".contains(last) else { return hint }
        return hint + "."
    }

    /// Whether every one of `conditions` holds — what makes a candidate a candidate you have
    /// actually earned.
    ///
    /// An edge with NO conditions is all-met, which is vacuously true and also the honest answer:
    /// there is no criterion left for the player to satisfy on it. It is not a promise the edge
    /// will be taken — `requiredEnergy`, `minEnergy` and `maxCareMistakes` still gate it, and
    /// `EvolutionEngine` remains the only thing that decides.
    static func allMet(_ conditions: [EvolutionCondition], in context: ConditionContext) -> Bool {
        conditions.allSatisfy { ConditionEvaluator.isSatisfied($0, in: context) }
    }
}
