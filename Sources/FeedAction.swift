import Foundation

/// What happened when the user tapped Feed.
///
/// One value covers all three endings because the screen has to respond to each differently: a feed
/// plays the eat loop, a refusal holds the refuse frame, and a block shows a reason instead of
/// animating anything. Returning an outcome rather than a `Bool` is what lets the view say WHY.
enum FeedOutcome: Equatable {
    /// The Digimon ate: `cost` Vitality spent, one unit of hunger gone.
    case fed(cost: Int)
    /// It was not hungry, so it turned the food down. Nothing was spent; the refusal was counted.
    case refused
    /// The feed never happened, for a reason worth showing the user.
    case blocked(reason: String)
}

/// Feeding: the one place earned Vitality is spent, and the only thing that lowers hunger.
///
/// Pure and clock-injected like `HungerClock`, so the whole rule is testable without a screen, a
/// store or a wait. The screen's job is only to render the outcome.
enum FeedAction {
    /// Vitality spent per feed — 5 points, i.e. 100 active kcal at `EnergyRates`' 20 kcal/point.
    ///
    /// The PRD fixes that feeding COSTS Vitality but not how much, so this is a game-balance number
    /// chosen here: a starving Digimon (4 units) costs 20 Vitality to fill, a fifth of the 100/day
    /// per-type cap. Cheap enough that an ordinary day feeds it comfortably, dear enough that the
    /// energy is really being spent.
    static let vitalityCostPerFeed = 5

    /// Spends Vitality to take one unit off `state.hunger`.
    ///
    /// Order matters and is deliberate: asleep is checked before hunger, so a sleeping Digimon that
    /// is also full is reported as asleep rather than being counted as a refusal it never made.
    ///
    /// - Parameter isAsleep: whether the Digimon is currently in its sleep window. Passed in rather
    ///   than read off `state`, because sleep is DERIVED from the user's sleep history (US-026) and
    ///   is not saved-game state — this keeps the rule honest until US-026 computes it for real.
    @discardableResult
    static func feed(
        _ state: GameState,
        isAsleep: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> FeedOutcome {
        guard !isAsleep else {
            return .blocked(reason: "Asleep — let it rest.")
        }
        // Checked here rather than left to the memorial screen covering the button, so the rule is
        // true of `FeedAction` itself. Mirrors `TrainAction`'s asleep -> health -> funds order.
        // Sickness deliberately does NOT block feeding, unlike training: eating is how a neglected
        // Digimon is looked after, and refusing to let the user feed it would be cruel.
        guard state.healthStatus != .dead else {
            return .blocked(reason: "It cannot eat.")
        }
        guard state.hunger > 0 else {
            state.recordRefusal(now: now, calendar: calendar)
            return .refused
        }
        guard state.stageEnergy[.vitality] >= vitalityCostPerFeed else {
            return .blocked(reason: "Not enough Vitality. Move to earn more.")
        }

        // Spent from `stageEnergy` alone. `lifetimeEnergy` is the record of what was ever EARNED, so
        // spending must not rewrite it — and the ledger keys on what was credited, not on what is
        // held, so a spend can never be re-credited by the next health read.
        state.stageEnergy[.vitality] -= vitalityCostPerFeed
        state.hunger -= 1
        // Restamping is REQUIRED, not cosmetic: `HungerClock` freezes `hungerUpdatedAt` at the
        // instant hunger hit the maximum, so feeding a starving Digimon without moving it forward
        // would immediately re-accrue every interval the stale timestamp sat there and the feed
        // would look like it did nothing. See `HungerClock.advance`.
        state.hungerUpdatedAt = now
        return .fed(cost: vitalityCostPerFeed)
    }
}
