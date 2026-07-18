import Foundation

/// Decides whether a node evolves on the energy it has earned, and into which of its branches.
///
/// This is the branch chooser and NOTHING else. It deliberately does not gate on time: US-020 owns
/// the minimum-time-in-stage rule and the `isDefault` fallback for a node whose gate has opened but
/// which has nothing qualifying. Here an edge either qualifies on its own merits or it does not, and
/// if none does the answer is simply "not yet".
///
/// Hatching is not evolution: a Digitama's hatch edge is gated on TOTAL energy across all four
/// types (US-018) and leaves `requiredEnergy` nil, so it is `EggHatcher`'s job. Such an edge never
/// qualifies here — see `qualifies`.
enum EvolutionEngine {
    /// The id of the node to evolve into, or nil if no outgoing edge qualifies.
    ///
    /// When several edges qualify, the one with the highest `minEnergy` wins: the harder-earned
    /// branch takes precedence over an easier one the Digimon also happens to satisfy.
    static func evolutionTarget(
        for node: EvolutionNode,
        stageEnergy: EnergyTotals,
        dominant: EnergyType?,
        careMistakes: Int,
        battleWins: Int
    ) -> String? {
        node.evolutions
            .filter { qualifies($0, stageEnergy: stageEnergy, dominant: dominant,
                                careMistakes: careMistakes, battleWins: battleWins) }
            // `max(by:)` returns the last of equal maxima; ties are unreachable in practice, since
            // two qualifying edges would need the same `requiredEnergy` (dominant is one type) and
            // the same `minEnergy`, which is ambiguous data US-009 would be right to flag.
            .max(by: { $0.minEnergy < $1.minEnergy })?
            .to
    }

    /// Whether a single edge qualifies to be taken right now.
    ///
    /// All four gates must hold: the dominant energy type matches `requiredEnergy`, the earned
    /// energy of that type has reached `minEnergy`, care mistakes are within `maxCareMistakes`, and
    /// battle wins meet `minBattleWins` when the edge sets one (an edge that does not is ungated on
    /// battles).
    static func qualifies(
        _ edge: EvolutionEdge,
        stageEnergy: EnergyTotals,
        dominant: EnergyType?,
        careMistakes: Int,
        battleWins: Int
    ) -> Bool {
        // A nil `requiredEnergy` is only ever a Digitama's hatch edge (US-007/US-009). Letting it
        // "match" a nil dominant would evolve a fresh, zero-energy egg the instant it existed, so
        // the branch engine never takes it — hatching goes through `EggHatcher`.
        guard let requiredEnergy = edge.requiredEnergy else { return false }
        guard dominant == requiredEnergy else { return false }
        // The threshold is per the required type, matching how US-017's bars aim: the required type
        // is the dominant one, so this is the amount that bar has been filling.
        guard stageEnergy[requiredEnergy] >= edge.minEnergy else { return false }
        guard careMistakes <= edge.maxCareMistakes else { return false }
        if let minBattleWins = edge.minBattleWins {
            guard battleWins >= minBattleWins else { return false }
        }
        return true
    }
}
