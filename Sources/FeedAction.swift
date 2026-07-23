import Foundation

/// What happened when the user tapped Feed.
///
/// One value covers all three endings because the screen has to respond to each differently: a feed
/// plays the eat loop, a refusal holds the refuse frame, and a block shows a reason instead of
/// animating anything. Returning an outcome rather than a `Bool` is what lets the view say WHY.
enum FeedOutcome: Equatable {
    /// The Digimon ate: one meat spent from the global larder, one unit of hunger gone.
    case fed
    /// It was not hungry, so it turned the food down. Nothing was spent; the refusal was counted.
    case refused
    /// The feed never happened, for a reason worth showing the user.
    case blocked(reason: String)
}

/// Feeding: the one place earned meat is spent, and the only thing that lowers hunger.
///
/// Pure and clock-injected like `HungerClock`, so the whole rule is testable without a screen, a
/// store or a wait. The screen's job is only to render the outcome.
enum FeedAction {
    /// Meat spent per feed — one unit off the global larder (US-174).
    ///
    /// A meal is one meat, flat: meat is the whole-box currency you battle to earn (US-175), so a
    /// unit-per-feed price is what makes "go and win a battle" the answer to an empty larder rather
    /// than an errand whose cost the player has to do arithmetic on.
    static let meatCostPerFeed = 1

    /// Spends one meat from the global larder to take one unit off `state.hunger`.
    ///
    /// Order matters and is deliberate: asleep is checked before hunger, so a sleeping Digimon that
    /// is also full is reported as asleep rather than being counted as a refusal it never made.
    ///
    /// - Parameter isAsleep: whether the Digimon is currently asleep. Passed in rather than read off
    ///   `state`, because sleep is DERIVED from the user's sleep history (US-026) and is not
    ///   saved-game state.
    ///
    ///   **The Feed button never passes `true` here.** Since US-110, `MainScreenModel.feed()` wakes a
    ///   sleeping Digimon first and then calls this with the woken answer, so the sleep arm above is
    ///   not what the user meets — it is the contract for a caller that has NOT woken it, and the
    ///   reason this stays a pure function of what it is told rather than a rule with a policy in it.
    ///   Do not delete it as dead code: it is what makes "you may not feed a sleeping Digimon"
    ///   true of `FeedAction` itself rather than true only of one call site.
    ///
    /// - Parameter profile: the player's global larder. Passed in rather than read off `state`
    ///   because meat is the box's, not this Digimon's (US-174) — a switch of the active Digimon
    ///   must feed off the same larder. Its `meat` is the fund the meal is bought from.
    @discardableResult
    static func feed(
        _ state: GameState,
        profile: PlayerProfile,
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
        // The funds check comes AFTER the refusal: a full Digimon turns food down for free, so an
        // empty larder never stops a meal that would not have been eaten anyway. The block names the
        // way to refill it — meat is earned in battle (US-175), not by moving.
        guard profile.meat >= meatCostPerFeed else {
            return .blocked(reason: "No meat — go battle.")
        }

        // Spent from the global larder. `lifetimeEnergy` and the energy ledger are untouched — meat
        // is its own currency now, so a meal no longer draws on the four energy types the evolution
        // branch is steered by.
        profile.meat -= meatCostPerFeed
        state.hunger -= 1
        // Restamping is REQUIRED, not cosmetic: `HungerClock` freezes `hungerUpdatedAt` at the
        // instant hunger hit the maximum, so feeding a starving Digimon without moving it forward
        // would immediately re-accrue every interval the stale timestamp sat there and the feed
        // would look like it did nothing. See `HungerClock.advance`.
        state.hungerUpdatedAt = now
        return .fed
    }
}
