import Foundation

/// One side's effective power, and every factor that produced it.
///
/// The factors are kept rather than multiplied away on purpose: US-094 shows the user WHY they won,
/// and a breakdown it had to recompute from the two typings would be a second implementation of D-4
/// that could disagree with the one the battle was actually fought with.
struct BattleSideModifiers: Equatable {
    /// What `BattlePower.power(stage:strengthStat:lifetimeEnergy:)` said before any matchup.
    let basePower: Int
    /// 1.25 / 1.0 / 0.8 — or 1.0 for a mutual pairing like light vs dark, where both apply.
    let elementFactor: Double
    /// 1.1 / 1.0 / 0.9, on the same rule.
    let attributeFactor: Double
    /// The pre-battle training grade's multiplier. Always 1.0 on the opponent's side — an AI
    /// Digimon does not play a minigame.
    let trainingFactor: Double
    /// `max(1, round(basePower x element x attribute x training))`. Floored at 1 so `BattleEngine`
    /// may divide by the sum of two of these without guarding.
    let effectivePower: Int

    /// The three factors as one number, for a display that wants "x1.44" rather than three columns.
    var totalFactor: Double { elementFactor * attributeFactor * trainingFactor }
}

/// A resolved matchup: both sides' effective powers, and how each axis fell out.
///
/// Effectiveness is reported FROM THE PLAYER'S SIDE — `.advantage` means the player's element beats
/// the opponent's — because it exists for the one screen that has a player to talk to.
struct BattleMatchup: Equatable {
    let player: BattleSideModifiers
    let opponent: BattleSideModifiers
    /// Derived from `player.elementFactor`, NOT from `DigimonElement.effectiveness(against:)`.
    /// Those two disagree exactly where it matters: light vs dark reports `.advantage` on the
    /// vocabulary type (both sides are strong) while the arithmetic nets 1.0, and it is the
    /// arithmetic the battle was fought with that the user must be shown.
    let elementEffectiveness: Effectiveness
    let attributeEffectiveness: Effectiveness

    /// The two numbers `BattleEngine.resolve` takes, in its argument order.
    var playerPower: Int { player.effectivePower }
    var opponentPower: Int { opponent.effectivePower }
}

/// Effective battle power: `BattlePower` scaled by the typing matchup and the pre-battle training
/// grade (D-4).
///
/// PURE — no clock, no store, no randomness, exactly like `BattlePower` itself. The dice still
/// belong to `BattleEngine`; this only decides what they are rolled against, which is what lets a
/// test pin an outcome as arithmetic instead of as a seed.
///
/// MULTIPLIES, NEVER REPLACES. `BattlePower` stays the base and stage stays dominant: a rung is 8
/// points there, and everything here together spans roughly ±40%. So a perfectly-played,
/// well-matched underdog can beat one rung up and cannot beat three — the matchup is a thumb on the
/// scale, not the scale.
///
/// BOTH DIRECTIONS ARE TESTED SEPARATELY on each axis, and both may apply. That is how a mutual
/// rivalry expresses itself in a ratio engine: light beats dark AND dark beats light, so the player
/// gets 1.25 x 0.8 = 1.0 and so does the opponent — the pairing is a wash rather than a coin flip.
/// See `docs/elements.md`.
enum BattleModifiers {
    /// Applied when my element beats theirs. The headline axis, and the biggest single modifier in
    /// the game — a good matchup is worth about two thirds of an evolution rung.
    static let elementAdvantage = 1.25

    /// Applied when their element beats mine. Not `1 / 1.25`, deliberately: a matchup that cuts
    /// harder than it helps would make the safe play "never battle a type I do not know".
    static let elementDisadvantage = 0.8

    /// Applied when my attribute beats theirs. A tenth, because the canon triangle is the quiet
    /// axis — it breaks ties between evenly-elemented Digimon rather than deciding fights.
    static let attributeAdvantage = 1.1

    /// Applied when their attribute beats mine.
    static let attributeDisadvantage = 0.9

    /// The element multiplier for `mine` fighting `theirs`. See the type note on why both halves
    /// are tested rather than switching on a single `Effectiveness`.
    static func elementFactor(_ mine: DigimonElement, against theirs: DigimonElement) -> Double {
        var factor = 1.0
        if mine.beats.contains(theirs) { factor *= elementAdvantage }
        if theirs.beats.contains(mine) { factor *= elementDisadvantage }
        return factor
    }

    /// The attribute multiplier for `mine` fighting `theirs`, on the same rule.
    static func attributeFactor(_ mine: DigimonAttribute, against theirs: DigimonAttribute) -> Double {
        var factor = 1.0
        if mine.beats.contains(theirs) { factor *= attributeAdvantage }
        if theirs.beats.contains(mine) { factor *= attributeDisadvantage }
        return factor
    }

    /// What a factor means to the side it was computed for. Exactly 1.0 is `.even`, which is the
    /// case a mutual pairing lands in — see `BattleMatchup.elementEffectiveness`.
    static func effectiveness(of factor: Double) -> Effectiveness {
        if factor > 1 { return .advantage }
        if factor < 1 { return .disadvantage }
        return .even
    }

    /// D-4's formula, floored at 1. Rounded to the nearest whole point because `BattleEngine` fights
    /// in integers — a power is a thing the Dex and the result screen can show without deciding how
    /// many decimals a Digimon has.
    static func effectivePower(
        basePower: Int,
        elementFactor: Double,
        attributeFactor: Double,
        trainingFactor: Double
    ) -> Int {
        let scaled = Double(basePower) * elementFactor * attributeFactor * trainingFactor
        return max(1, Int(scaled.rounded()))
    }

    /// Resolves a whole matchup into the two numbers the battle is fought with.
    ///
    /// `training` is the grade from the pre-battle round (D-3) and reaches the PLAYER ONLY. The
    /// opponent is an AI with no minigame to have played, so giving it a grade would mean inventing
    /// one — and a `perfect` the user earned must not be silently matched by their opponent.
    static func matchup(
        playerPower: Int,
        playerType: DigimonType,
        opponentPower: Int,
        opponentType: DigimonType,
        training: TrainingResult
    ) -> BattleMatchup {
        let playerElement = elementFactor(playerType.element, against: opponentType.element)
        let playerAttribute = attributeFactor(playerType.attribute, against: opponentType.attribute)
        let opponentElement = elementFactor(opponentType.element, against: playerType.element)
        let opponentAttribute = attributeFactor(opponentType.attribute, against: playerType.attribute)

        let player = BattleSideModifiers(
            basePower: playerPower,
            elementFactor: playerElement,
            attributeFactor: playerAttribute,
            trainingFactor: training.battleMultiplier,
            effectivePower: effectivePower(basePower: playerPower,
                                           elementFactor: playerElement,
                                           attributeFactor: playerAttribute,
                                           trainingFactor: training.battleMultiplier))

        let opponent = BattleSideModifiers(
            basePower: opponentPower,
            elementFactor: opponentElement,
            attributeFactor: opponentAttribute,
            trainingFactor: 1.0,
            effectivePower: effectivePower(basePower: opponentPower,
                                           elementFactor: opponentElement,
                                           attributeFactor: opponentAttribute,
                                           trainingFactor: 1.0))

        return BattleMatchup(
            player: player,
            opponent: opponent,
            elementEffectiveness: effectiveness(of: playerElement),
            attributeEffectiveness: effectiveness(of: playerAttribute))
    }
}

extension TrainingResult {
    /// What this grade multiplies the player's battle power by (D-4).
    ///
    /// Centred on `good` at 1.0, the way `strengthGain` is centred on it at 1 — an average round
    /// leaves the fight exactly as `BattlePower` scored it, so the modifier is a reward for playing
    /// well rather than a tax on battling at all. A `miss` at 0.8 still costs less than a bad
    /// element matchup, because the user can lose a round to a mistimed tap and should not be
    /// handed a hopeless fight for it.
    var battleMultiplier: Double {
        switch self {
        case .miss: return 0.8
        case .good: return 1.0
        case .great: return 1.15
        case .perfect: return 1.3
        }
    }
}
