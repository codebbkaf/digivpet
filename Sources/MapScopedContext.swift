import Foundation

/// The counters a MAP's Digitama conditions are judged on (US-206).
///
/// A map's egg asks "what have you done HERE", not "what have you ever done". Before this story the
/// same `ConditionContext` answered both questions — it was built from `GameState`, whose totals are
/// stage-long and lifetime — so a veteran player arriving in a fresh map found its slots already
/// satisfied by history earned somewhere else entirely, and `MapDetailView` marked them "Ready to
/// find" before a single step had been walked there.
///
/// The fix is a context built from `PlayerProfile`'s per-map counters instead, which accrue only
/// while that map is selected. It is the SAME `ConditionContext` type and the same
/// `ConditionReveal`/`ConditionEvaluator` reading of it, so the map detail's hints, its "Ready to
/// find" mark and `DigitamaDropEngine.eligibleSlots` still cannot disagree — only the numbers they
/// are warmed against have changed.
extension ConditionContext {
    /// The map-scoped counters for `mapId`.
    ///
    /// **Every window reads the map's running total**, deliberately. `stage`, `lifetime` and `day`
    /// are spans of the player's life, and a map is not a span of anybody's life — it is a place.
    /// A slot authored `health.steps day atLeast 2000` means "walk 2,000 steps in this map", and
    /// answering it with the best DAY the player ever had is the exact global reading this story
    /// exists to remove. So all three windows are answered from `PlayerProfile.mapMetrics`, and an
    /// author choosing a window is choosing only how the hint reads.
    ///
    /// What stays global, and why:
    /// - `lightState` is a NOW reading with no span at all (US-185) — "the light is off" is true or
    ///   false this instant, and there is no per-map version of it to keep.
    /// - `readings` are today's direct health reads, which answer only the STANDING measurements a
    ///   running total cannot hold (a resting heart rate, a VO2 max). Those cannot be accumulated per
    ///   map either; they are passed through so a slot on one is still answerable, and so an
    ///   `.unavailable` read still overrides a total exactly as it does everywhere else.
    ///
    /// An un-credited health metric is absent from the totals and so reads `.unknown`, which fails its
    /// condition whichever way the comparison points — that is what makes a fresh map's slots start
    /// LOCKED. The `care.*` counters are flattened to a real 0 instead, because the game keeps them
    /// itself and "you have disturbed its sleep zero times here" is a fact, not an absence.
    static func mapScoped(
        _ mapId: String,
        profile: PlayerProfile,
        lightState: LightState? = nil,
        readings: [ConditionMetric: HealthReading] = [:]
    ) -> ConditionContext {
        let totals = profile.mapMetrics(forMap: mapId)
        let fought = profile.battlesFought(forMap: mapId)
        let won = profile.battlesWon(forMap: mapId)
        return ConditionContext(
            stageTotals: totals,
            lifetimeTotals: totals,
            bestDayThisStage: totals,
            trainingSessionsThisStage: Int(totals[.careTrainingSessions]),
            overfeedsThisStage: Int(totals[.careOverfeeds]),
            sleepDisturbancesThisStage: Int(totals[.careSleepDisturbances]),
            battlesToday: fought,
            battlesLifetime: fought,
            // Zero battles is 0.0 and never a divide by zero, matching `GameState.battleWinRatio`
            // exactly: a player who has not fought here has not won here.
            battleWinRatioLifetime: fought > 0 ? Double(won) / Double(fought) : 0,
            lightState: lightState,
            readings: readings)
    }
}
