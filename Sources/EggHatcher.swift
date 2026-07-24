import Foundation

/// The rule for when a Digitama hatches, and into what.
///
/// A Digitama is the one node whose evolution is NOT branched on a dominant energy type: hatching
/// is driven by TOTAL energy across all four types reaching a threshold (v1: 50), which is exactly
/// why a Digitama's hatch edge leaves `requiredEnergy` nil. The threshold is that edge's
/// `minEnergy`, so the number lives in the graph data and not in a second place here.
///
/// US-222 adds two more ways out of the egg without removing that one: five minutes on the clock,
/// or 500 steps walked since this egg appeared. The energy rule is the interesting one and stays
/// first; the other two exist so that a player who has no health data at all — the Simulator, a
/// watch worn for the first time — is not left staring at an egg that may never crack.
enum EggHatcher {
    // The pacing knobs, together and named, in the spirit of `EvolutionTiming`: retuning how long
    // an egg lasts is editing these two numbers, not hunting through the engine.

    /// How long a Digitama may sit before it hatches on the clock alone: five real minutes.
    ///
    /// Wall-clock against `stageEnteredDate`, not a counter, so an app closed on an egg and
    /// reopened six minutes later finds a hatched Baby I and `BackgroundRefresh` can hatch one
    /// without a foreground. A frozen egg does not age toward it — `Freeze.shiftTimeline` moves
    /// `stageEnteredDate` forward by exactly the span spent in the box.
    static let maximumEggDuration: TimeInterval = 5 * 60
    /// How many steps walked since this egg appeared hatch it on their own.
    ///
    /// Read off `stageMetricTotals`, which `enterStage(at:)` clears, so the count is this egg's and
    /// a second egg starts again from zero.
    static let stepsToHatch: Double = 500

    /// The Baby I id this egg hatches into, or nil if `node` is not a Digitama, has no hatch edge,
    /// or has met none of the three hatch conditions.
    ///
    /// Pure, with the clock passed in: nothing here reads `Date()`, so a test never waits.
    ///
    /// Every comparison is `>=`, so each threshold hatches exactly on its boundary: 50 energy, five
    /// minutes on the nose, the 500th step.
    static func hatchTarget(for node: EvolutionNode,
                            stageEnergy: EnergyTotals,
                            stageEnteredAt: Date,
                            stageMetrics: MetricTotals,
                            now: Date) -> String? {
        guard node.stage == .digitama, let edge = node.evolutions.first else { return nil }
        let earnedIt = stageEnergy.total >= edge.minEnergy
        let waitedIt = now.timeIntervalSince(stageEnteredAt) >= maximumEggDuration
        // Through the subscript, not `known(_:)`: an un-credited step total means this path is
        // simply not met yet, and 0 is the right answer for a `>=` gate — unlike an `atMost`
        // condition, where unknown must never satisfy (US-180).
        let walkedIt = stageMetrics[.healthSteps] >= stepsToHatch
        guard earnedIt || waitedIt || walkedIt else { return nil }
        return edge.to
    }
}
