import Foundation

/// What happened when the user tapped Train.
///
/// Shaped like `FeedOutcome` and for the same reason: the screen has to respond differently to a
/// training that landed and one that never happened, and a `Bool` could not say WHY it was refused.
/// Unlike feeding there is no "refused" ending — a Digimon is never too full to train.
enum TrainOutcome: Equatable {
    /// It trained: `cost` spent from `spent`, and `strengthStat` went up by `gain`.
    case trained(spent: EnergyType, cost: Int, gain: Int)
    /// The training never happened, for a reason worth showing the user.
    case blocked(reason: String)
}

/// Training: spends the physical energies to buy `strengthStat`, which is what steers a Digimon
/// toward the stronger evolution branches and (US-030) what it fights with.
///
/// Pure and clock-free like `FeedAction`, so the whole rule is testable without a screen or a store.
/// The screen's job is only to render the outcome.
enum TrainAction {
    /// Energy spent per session — 5 points, matching `FeedAction.vitalityCostPerFeed` so the two
    /// actions cost the same and neither is the obvious one to spam. At `EnergyRates`' 2000
    /// steps/point that is 10,000 steps' worth of Strength, or 30 minutes of Stamina.
    ///
    /// The PRD fixes that training COSTS Strength or Stamina but not how much; this is a
    /// game-balance number chosen here.
    static let energyCostPerTraining = 5

    /// How much `strengthStat` one session buys. One, so the stat reads as "sessions trained" and
    /// there is no exchange rate to remember.
    static let strengthGainPerTraining = 1

    /// The two energies training can be paid with, richest first at the point of spending.
    ///
    /// Strength and Stamina are the physical pair — steps and exercise minutes. Spirit (sleep) and
    /// Vitality (calories) are deliberately excluded: Vitality is feeding's currency, and spending
    /// sleep to get stronger is not a trade the game makes.
    static let payableWith: [EnergyType] = [.strength, .stamina]

    /// Spends Strength or Stamina to raise `state.strengthStat`.
    ///
    /// Whichever of the two the Digimon holds more of pays, so a walker and a gym-goer can both
    /// train without having to know which currency the game wanted. Ties go to Strength, by
    /// `payableWith` order.
    ///
    /// Checks run asleep -> sick -> funds, so a sleeping Digimon that is also broke is reported as
    /// asleep: the state the user can do something about tonight, rather than the one they cannot.
    ///
    /// - Parameter isAsleep: whether the Digimon is in its sleep window. Passed in rather than read
    ///   off `state` for the same reason `FeedAction.feed` takes it — sleep is DERIVED from the
    ///   user's sleep history (US-026), not saved-game state.
    @discardableResult
    static func train(_ state: GameState, isAsleep: Bool) -> TrainOutcome {
        guard !isAsleep else {
            return .blocked(reason: "Asleep — let it rest.")
        }
        guard state.healthStatus == .healthy else {
            return .blocked(reason: state.healthStatus == .dead ? "It cannot train." : "Too sick to train.")
        }
        guard let payer = payableWith.max(by: { state.stageEnergy[$0] < state.stageEnergy[$1] }),
              state.stageEnergy[payer] >= energyCostPerTraining else {
            return .blocked(reason: "Not enough Strength or Stamina. Move to earn more.")
        }

        // Spent from `stageEnergy` alone, exactly as feeding is: `lifetimeEnergy` records what was
        // ever EARNED, and the ledger keys on what was credited rather than on what is held, so a
        // spend can never be re-credited by the next health read.
        state.stageEnergy[payer] -= energyCostPerTraining
        state.strengthStat += strengthGainPerTraining
        // Filed here rather than alongside the gain, because the two answer to different rules: the
        // gain is what the session EARNED and US-075 is about to grade it, while the count is that
        // the session HAPPENED, which no grade can change. See `GameState.stageTrainingSessions`.
        state.recordTrainingSession()
        return .trained(spent: payer, cost: energyCostPerTraining, gain: strengthGainPerTraining)
    }
}
