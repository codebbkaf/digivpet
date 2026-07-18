import Foundation

/// How long a Digimon must stay in a stage before it may evolve out of it.
///
/// The gate is what stops a Digimon skipping its whole life in one session: even holding the
/// energy for the next stage, the clock has to advance first. Every threshold lives here and
/// nowhere else, matching `EnergyRates` — retuning the pacing is editing these numbers, not
/// hunting through the engine.
enum EvolutionTiming {
    /// Minimum time in a Baby I or Baby II stage: one real day.
    static let babyMinimumStageDuration: TimeInterval = 24 * 60 * 60
    /// Minimum time in Child and every stage above it: three real days.
    static let matureMinimumStageDuration: TimeInterval = 72 * 60 * 60

    /// How long a Digimon must spend in `stage` before it may evolve, or nil for a stage that is
    /// not time-gated for evolution.
    ///
    /// Digitama returns nil: an egg does not evolve, it HATCHES, and hatching is gated on total
    /// energy alone with no time floor (US-018). If the evolution gate fired for a Digitama it
    /// would take the egg's `isDefault` (hatch) edge on the clock, hatching a starved egg — so the
    /// gate must never open for it, and `EggHatcher` stays the only path off the egg.
    static func minimumStageDuration(for stage: Stage) -> TimeInterval? {
        switch stage {
        case .digitama: return nil
        case .babyI, .babyII: return babyMinimumStageDuration
        case .child, .adult, .perfect, .ultimate, .armorHybrid: return matureMinimumStageDuration
        }
    }

    /// Whether a Digimon that entered `stage` at `enteredAt` has been there long enough, as of
    /// `now`, to be allowed to evolve.
    ///
    /// The comparison is `>=`, so the gate opens exactly on the threshold: a Baby I clears at 24h
    /// on the nose, not a tick later. A stage with no gate (Digitama) never clears — it does not
    /// evolve at all.
    static func hasClearedTimeGate(stage: Stage, enteredAt: Date, now: Date) -> Bool {
        guard let minimum = minimumStageDuration(for: stage) else { return false }
        return now.timeIntervalSince(enteredAt) >= minimum
    }
}
