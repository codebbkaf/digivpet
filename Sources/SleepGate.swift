import Foundation

/// The accumulated-sleep evolution gate (US-183) and the dash bar that draws it, as pure
/// arithmetic that a test can check without a view graph.
///
/// A `health.sleep` condition with `window: .lifetime` and `comparison: .atLeast` is an
/// *accumulated-sleep* gate: the Digimon must have banked at least that much lifetime sleep before
/// the edge opens — e.g. Agumon needs 16 hours to reach Greymon. The threshold is authored in
/// MINUTES, the unit `MetricLedger` credits `health.sleep` in and the unit every other
/// `health.sleep` condition in `evolutions.json` uses; the player-facing bar speaks whole HOURS,
/// because "16 hours" is how the requirement reads to the person raising the pet.
///
/// The gate itself is answered by the ordinary `ConditionEvaluator` — nothing here re-implements the
/// comparison. This type exists only to turn the same authored minutes and the same lifetime total
/// the gate reads into the `(filled, total)` a `DashBar` needs, so the bar can never disagree with
/// the gate about how much sleep is left.
enum SleepGate {
    /// Minutes to an hour — the one place the bar's unit conversion lives.
    static let minutesPerHour = 60.0

    /// The largest accumulated-sleep requirement across `conditions`, in whole hours, or nil when
    /// none of them gate on accumulated sleep so no bar is drawn.
    ///
    /// The largest rather than the first: a node with two sleep-gated branches shows the bar the
    /// deeper one needs, and a player who fills that has filled the shallower one on the way.
    static func requiredHours(in conditions: [EvolutionCondition]) -> Int? {
        guard let minutes = conditions.filter(isAccumulatedSleep).map(\.value).max() else {
            return nil
        }
        return Int((minutes / minutesPerHour).rounded())
    }

    /// The lifetime sleep the context reports, in whole hours, FLOORED — the same total the gate
    /// compares, so the bar's solid count is exactly the progress the gate has made toward opening.
    /// `.unknown` (a Simulator with no sleep data, or a save from before sleep was credited) reads
    /// as 0 earned rather than as a phantom dash.
    static func earnedHours(in context: ConditionContext) -> Int {
        guard case .known(let minutes) = context.value(for: .healthSleep, window: .lifetime) else {
            return 0
        }
        return Int((minutes / minutesPerHour).rounded(.down))
    }

    /// True for a condition that gates on accumulated (lifetime) sleep being at least a threshold.
    /// An `atMost` sleep gate ("keep it up past its bedtime") is deliberately excluded: it is a
    /// ceiling, not something the player fills toward, so a bar counting up to it would read
    /// backwards.
    private static func isAccumulatedSleep(_ condition: EvolutionCondition) -> Bool {
        condition.knownMetric == .healthSleep
            && condition.window == .lifetime
            && condition.comparison == .atLeast
    }
}
