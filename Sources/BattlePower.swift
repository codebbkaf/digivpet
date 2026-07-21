import Foundation

/// How strong a Digimon fights — the single number US-031's battles are resolved from.
///
/// A PURE function of saved state, with no clock, no store and no randomness. Two Digimon with the
/// same stage, `strengthStat` and lifetime energy have the same power, always: the roll belongs to
/// the battle, not to the stat it is rolled against. That is also what makes it testable without a
/// screen, like `FeedAction` and `TrainAction`.
///
/// THE FORMULA (PRD FR-31 — "derive battle power from stage, strength stat, and lifetime energy"),
/// with each term's weight and why it is that size:
///
///     power = base
///           + pointsPerStage        * battleRung(stage)   //  8 per rung, 0...48
///           + pointsPerStrengthStat * strengthStat        //  3 per training session
///           + lifetimeEnergy.total / energyPerPoint       //  1 per 25 energy earned, ever
///
/// - `base` (1) keeps power strictly positive, so a caller may take a ratio of two powers without
///   guarding a fresh Digitama's zero.
/// - STAGE is the dominant term by design: evolving is the reward the whole game is built around, so
///   a rung is worth 8 points — nearly three training sessions — and reaching Ultimate is worth 48.
/// - `strengthStat` at 3 makes training the fastest thing a user can DO about their power today.
///   `TrainAction` gives one stat per session and costs 5 energy, so a session buys 3 power for what
///   75 energy would buy through the lifetime term: deliberate, because spending energy on purpose
///   should beat merely accumulating it.
/// - LIFETIME ENERGY at 1 per 25 is the slow floor, and it is `lifetimeEnergy` rather than
///   `stageEnergy` on purpose: it is the only term that survives evolution, so a Digimon that walked
///   its whole life stays stronger than one that idled to the same stage. `EnergyRates` credits
///   roughly 10-40 energy on an active day, so this is worth about a point a day.
///
/// Integer arithmetic throughout — a battle compares powers and never needs a fraction, and an Int
/// is what US-032's record and any future display can show without rounding decisions.
enum BattlePower {
    /// The floor every Digimon starts from. See the formula note: it exists so power is never zero.
    static let base = 1

    /// Power per rung climbed on the Digitama -> Ultimate ladder.
    static let pointsPerStage = 8

    /// Power per point of `strengthStat`, i.e. per completed training session.
    static let pointsPerStrengthStat = 3

    /// Lifetime energy — summed across all four types — that buys one point of power.
    static let energyPerPoint = 25

    /// The rung `stage` counts as when fighting.
    ///
    /// This is `Stage.ladderIndex` for everything ON the ladder. Armor-Hybrid is the one stage with
    /// no rung of its own — it is a side branch, not a step — and it is scored here as an Adult (4),
    /// which is the tier it branches off toward. Defaulting it to 0 instead would make an Armored
    /// Digimon fight like an egg, which is the one answer that is certainly wrong.
    static func battleRung(_ stage: Stage) -> Int {
        stage.ladderIndex ?? Stage.adult.ladderIndex!
    }

    /// Battle power for the given stats. See the type's documentation for the formula.
    static func power(stage: Stage, strengthStat: Int, lifetimeEnergy: EnergyTotals) -> Int {
        base
            + pointsPerStage * battleRung(stage)
            + pointsPerStrengthStat * strengthStat
            + lifetimeEnergy.total / energyPerPoint
    }
}

extension GameState {
    /// This Digimon's battle power. Sugar over `BattlePower.power` so the screen and the battle
    /// engine need not unpack three fields to ask one question.
    ///
    /// The lifetime total is passed IN rather than read off the state, because since US-123 it
    /// belongs to the player and not to the Digimon — see `PlayerProfile`. A parameter and not a
    /// stored mirror: a copy on the state is a copy that can go stale between two refreshes.
    func battlePower(lifetimeEnergy: EnergyTotals) -> Int {
        BattlePower.power(stage: stage, strengthStat: strengthStat, lifetimeEnergy: lifetimeEnergy)
    }
}
