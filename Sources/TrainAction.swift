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

/// What happened when a training round was ENTERED — the half of `TrainOutcome` that is known
/// before a minigame has been played (US-075).
///
/// Split out because the two halves answer at different times: eligibility and the charge are
/// settled the instant Train is tapped, and the gain is not known until the round ends. A single
/// call could not express that, and folding the charge into the ending would make dismissing a bad
/// round a free retry.
enum TrainingStart: Equatable {
    /// The round is paid for and may begin: `cost` was taken from `spent`.
    case started(spent: EnergyType, cost: Int)
    /// The round never started, for a reason worth showing the user. Nothing was charged.
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

    /// How much `strengthStat` an UNGRADED session buys — a plain Train tap with no minigame behind
    /// it yet. It is `good`'s gain, so the graded scale (US-075) extends the old payout upward
    /// rather than repricing it: nothing a player earned before is worth less now.
    static let strengthGainPerTraining = TrainingResult.good.strengthGain

    /// The two energies training can be paid with, richest first at the point of spending.
    ///
    /// Strength and Stamina are the physical pair — steps and exercise minutes. Spirit (sleep) and
    /// Vitality (calories) are deliberately excluded: Vitality is feeding's currency, and spending
    /// sleep to get stronger is not a trade the game makes.
    static let payableWith: [EnergyType] = [.strength, .stamina]

    /// Why a session is refused when neither payable energy can cover it. Names the remedy rather
    /// than only the refusal — the energy comes from walking, so there is something to do about it.
    ///
    /// Shared with battling (`BattleCost.insufficientEnergyReason`), which charges the same cost from
    /// the same pair: two wordings for one rule would read as two different rules.
    static let insufficientEnergyReason = "Not enough Strength or Stamina. Move to earn more."

    /// Enters a training round: checks eligibility, charges the energy, and counts the session.
    ///
    /// Whichever of the two payable energies the Digimon holds more of pays, so a walker and a
    /// gym-goer can both train without having to know which currency the game wanted. Ties go to
    /// Strength, by `payableWith` order.
    ///
    /// Checks run asleep -> sick -> funds, so a sleeping Digimon that is also broke is reported as
    /// asleep: the state the user can do something about tonight, rather than the one they cannot.
    ///
    /// **The charge is taken HERE and never given back.** A minigame that ends in a `miss`, or is
    /// dismissed halfway, has still spent the energy — otherwise walking out of a round the user was
    /// losing would be free, and the button would be a slot machine rather than a cost.
    ///
    /// **The session is counted HERE too, for the same reason and one more**: evolution branches on
    /// how OFTEN the user trained, never on how well (see `GameState.stageTrainingSessions`), so the
    /// count cannot wait on a grade that may never arrive. Exactly one per started round, and none
    /// at all when blocked.
    ///
    /// - Parameter isAsleep: whether the Digimon is in its sleep window. Passed in rather than read
    ///   off `state` for the same reason `FeedAction.feed` takes it — sleep is DERIVED from the
    ///   user's sleep history (US-026), not saved-game state.
    @discardableResult
    static func begin(_ state: GameState, isAsleep: Bool) -> TrainingStart {
        guard !isAsleep else {
            return .blocked(reason: "Asleep — let it rest.")
        }
        guard state.healthStatus == .healthy else {
            return .blocked(reason: state.healthStatus == .dead ? "It cannot train." : "Too sick to train.")
        }
        // The charge itself lives in `EnergyPurchase`, which US-108 extracted so that battling could
        // spend the same way rather than growing a second copy of it: richest payer, `stageEnergy`
        // only, and never given back.
        guard let payer = EnergyPurchase.charge(energyCostPerTraining, from: payableWith, in: state) else {
            return .blocked(reason: insufficientEnergyReason)
        }
        state.recordTrainingSession()
        return .started(spent: payer, cost: energyCostPerTraining)
    }

    /// Pays out a round that has been graded, and answers with the `strengthStat` it bought.
    ///
    /// Charges nothing and checks nothing: `begin` already took the money and already decided the
    /// Digimon was fit to train. A round graded after the Digimon fell asleep or fell ill still pays
    /// — it was fought under the conditions that were checked when it started, and refusing to pay
    /// at the end would punish the user for the clock.
    @discardableResult
    static func finish(_ state: GameState, result: TrainingResult) -> Int {
        state.strengthStat += result.strengthGain
        return result.strengthGain
    }

    /// One whole round, entered and graded in a single call.
    ///
    /// NOT what the Train button does since US-083 — the button calls `begin`, puts a minigame on
    /// screen, and calls `finish` with the grade that game hands back, which is the only arrangement
    /// where walking out of a losing round still costs the energy. This is the convenience the payout
    /// rule is TESTED through: both halves, no view, no grade to wait for. `result` defaults to
    /// `good`, which is exactly the one point a session paid before grading existed.
    @discardableResult
    static func train(_ state: GameState, isAsleep: Bool,
                      result: TrainingResult = .good) -> TrainOutcome {
        switch begin(state, isAsleep: isAsleep) {
        case .blocked(let reason):
            return .blocked(reason: reason)
        case .started(let spent, let cost):
            return .trained(spent: spent, cost: cost, gain: finish(state, result: result))
        }
    }
}
