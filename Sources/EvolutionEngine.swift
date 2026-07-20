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
        battleWins: Int,
        conditions context: ConditionContext = .unknown
    ) -> String? {
        node.evolutions
            .filter { qualifies($0, stageEnergy: stageEnergy, dominant: dominant,
                                careMistakes: careMistakes, battleWins: battleWins,
                                conditions: context) }
            // `max(by:)` returns the last of equal maxima; ties are unreachable in practice, since
            // two qualifying edges would need the same `requiredEnergy` (dominant is one type) and
            // the same `minEnergy`, which is ambiguous data US-009 would be right to flag.
            .max(by: { $0.minEnergy < $1.minEnergy })?
            .to
    }

    /// The id to evolve into once the stage's time gate has opened, or nil while it is still
    /// closed (or the node is terminal). This is the full US-020 decision, layered over the pure
    /// energy chooser `evolutionTarget`:
    ///
    ///  1. Before the stage's minimum time has elapsed, nothing evolves — even holding the energy
    ///     for the next stage. `EvolutionTiming` owns that gate.
    ///  2. Once the gate is open, a qualifying branch wins exactly as `evolutionTarget` decides.
    ///  3. If the gate is open but NOTHING qualifies, the node's `isDefault` edge is taken, so a
    ///     Digimon whose owner never earned the precise branch energy is never permanently stuck.
    ///
    /// A Digitama has no evolution gate (`EvolutionTiming.minimumStageDuration` is nil), so this is
    /// always nil for an egg — hatching stays `EggHatcher`'s job and the egg's `isDefault` hatch
    /// edge is never taken on the clock.
    static func scheduledEvolutionTarget(
        for node: EvolutionNode,
        stageEnergy: EnergyTotals,
        dominant: EnergyType?,
        careMistakes: Int,
        battleWins: Int,
        stageEnteredAt: Date,
        now: Date,
        conditions context: ConditionContext = .unknown
    ) -> String? {
        guard EvolutionTiming.hasClearedTimeGate(
            stage: node.stage, enteredAt: stageEnteredAt, now: now
        ) else { return nil }

        if let qualified = evolutionTarget(for: node, stageEnergy: stageEnergy, dominant: dominant,
                                           careMistakes: careMistakes, battleWins: battleWins,
                                           conditions: context) {
            return qualified
        }
        return defaultEdge(of: node)?.to
    }

    /// The node's fallback edge — the one marked `isDefault` — or nil if it has none (a terminal
    /// node). US-009 guarantees at most one per node, so `first` is unambiguous.
    static func defaultEdge(of node: EvolutionNode) -> EvolutionEdge? {
        node.evolutions.first { $0.isDefault }
    }

    /// Whether a single edge qualifies to be taken right now.
    ///
    /// All four original gates must hold: the dominant energy type matches `requiredEnergy`, the
    /// earned energy of that type has reached `minEnergy`, care mistakes are within
    /// `maxCareMistakes`, and battle wins meet `minBattleWins` when the edge sets one (an edge that
    /// does not is ungated on battles).
    ///
    /// On top of those, EVERY one of the edge's US-056 `conditions` must hold (US-060). They are
    /// conjunctive with each other and with the four above — an edge is a list of things that are
    /// all true of a Digimon that earned it, never a list of ways to earn it. That is what makes a
    /// BAND work: `atLeast 8` plus `atMost 31` on one metric is a closed interval, and 32 fails the
    /// second half and drops the overtrained Digimon to the `isDefault` junk branch.
    ///
    /// An edge with no conditions is decided entirely by the four gates, exactly as before — which
    /// is every edge in the shipped graph until US-061 authors some.
    static func qualifies(
        _ edge: EvolutionEdge,
        stageEnergy: EnergyTotals,
        dominant: EnergyType?,
        careMistakes: Int,
        battleWins: Int,
        conditions context: ConditionContext = .unknown
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
        // `allSatisfy` on an empty list is true, so a conditionless edge is untouched by this line.
        return edge.conditions.allSatisfy { ConditionEvaluator.isSatisfied($0, in: context) }
    }
}
