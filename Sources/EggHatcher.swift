import Foundation

/// The rule for when a Digitama hatches, and into what.
///
/// A Digitama is the one node whose evolution is NOT branched on a dominant energy type: hatching
/// is driven by TOTAL energy across all four types reaching a threshold (v1: 50), which is exactly
/// why a Digitama's hatch edge leaves `requiredEnergy` nil. The threshold is that edge's
/// `minEnergy`, so the number lives in the graph data and not in a second place here.
enum EggHatcher {
    /// The Baby I id this egg hatches into, or nil if `node` is not a Digitama, has no hatch edge,
    /// or has not yet reached its hatch threshold.
    ///
    /// The comparison is `>=`: an egg with exactly the threshold's worth of total energy hatches.
    static func hatchTarget(for node: EvolutionNode, stageEnergy: EnergyTotals) -> String? {
        guard node.stage == .digitama, let edge = node.evolutions.first else { return nil }
        guard stageEnergy.total >= edge.minEnergy else { return nil }
        return edge.to
    }
}
