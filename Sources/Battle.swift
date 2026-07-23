import Foundation

/// A deterministic random source, so a battle can be replayed exactly from its seed.
///
/// SplitMix64 — the algorithm is four lines, has no state to warm up, and is the one every
/// implementation agrees on, which matters because a test pins literal outcomes against it. The
/// point is NOT cryptographic quality; it is that `SeededGenerator(seed: 42)` produces the same
/// battle on every machine and every OS version, which `SystemRandomNumberGenerator` cannot promise.
///
/// A `struct` passed `inout` rather than a class, so a caller cannot accidentally share one draw
/// sequence between two battles and wonder why the second is not reproducible.
/// `Equatable` so a half-played battle can be carried in a published value: US-093 picks the
/// opponent when the pre-battle round opens and rolls the fight when it is graded, which means the
/// draw sequence has to survive between the two — one seed, one whole bout, as before the round
/// existed.
struct SeededGenerator: RandomNumberGenerator, Equatable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Which of the two Digimon in a battle. There are only ever two — the PRD rules out PvP, so this
/// never needs to become a list of combatants.
enum BattleSide: Equatable, CaseIterable {
    case player
    case opponent

    var other: BattleSide { self == .player ? .opponent : .player }

    /// Index into the engine's two-element hit-point and power arrays.
    fileprivate var index: Int { self == .player ? 0 : 1 }
}

/// One exchange: somebody swung, and this is what it cost the other one.
///
/// The whole battle is resolved up front into a list of these and only THEN animated, which is what
/// lets the resolution be a pure function a test can assert on without a screen. The view walks the
/// list frame by frame: `attacker` plays the attack frame, the defender plays the hurt loop.
struct BattleTurn: Equatable {
    let attacker: BattleSide
    let damage: Int
    /// The defender's hit points after taking `damage`. Zero means this turn ended the battle.
    let defenderRemainingHitPoints: Int

    var isKnockout: Bool { defenderRemainingHitPoints == 0 }
}

/// A resolved battle: who fought, blow by blow, and who won.
struct BattleReport: Equatable {
    let playerPower: Int
    let opponentPower: Int
    /// Every exchange in order. Never empty — a battle is at least one swing.
    let turns: [BattleTurn]
    let winner: BattleSide

    /// Each side's MAX hit points — the length of its HP dash bar (US-188). Per-Digimon since
    /// US-188: a 5-HP Child shows five dashes and a 12-HP Ultimate twelve, so the bar's total reads
    /// the combatant's health at a glance. Defaulted to `BattleEngine.startingHitPoints` so a bout
    /// hand-built by a test or a preview that only cares about the frames still has a full bar to
    /// draw without naming a stat.
    var playerMaxHitPoints: Int = BattleEngine.startingHitPoints
    var opponentMaxHitPoints: Int = BattleEngine.startingHitPoints

    var playerWon: Bool { winner == .player }

    /// The MAX hit points on `side`, the total the HP dash bar is drawn to.
    func maxHitPoints(_ side: BattleSide) -> Int {
        side == .player ? playerMaxHitPoints : opponentMaxHitPoints
    }
}

/// Turn-based battle resolution (PRD FR-32).
///
/// PURE, and driven entirely by an injected `RandomNumberGenerator`: the same seed and the same two
/// powers always produce the same `BattleReport`, which is what US-031's "deterministic winner"
/// test asserts and what makes the whole thing testable without a watch.
///
/// THE MODEL: each side starts on its OWN max hit points (US-188) — the per-stage `baseHP` from
/// `ConsumptionConfig`, so a 5-HP Child and a 12-HP Ultimate carry visibly different HP bars — while
/// `BattlePower` still decides how hard each one HITS. Before US-188 both sides shared a flat pool,
/// which kept every battle the same length; the per-Digimon pool is the price of the dash HP bar
/// reading a combatant's real health. `resolve` still defaults both sides to `startingHitPoints`, so
/// a caller that only wants the power model — every test predating US-188 — keeps the old behaviour.
///
/// The damage roll is `1...maximumDamage`, and `maximumDamage` is the attacker's SHARE of the two
/// powers rather than its absolute power. So it is the RATIO that matters: an evenly matched pair
/// each roll 1...4, and doubling your power raises your ceiling to 5 rather than to 8. Absolute
/// scaling would mean an Ultimate one-shots a Child and two Ultimates trade 40-point blows, which
/// is the same battle with bigger numbers. A ratio also keeps an upset possible — the underdog
/// still rolls, so training improves your odds without making the outcome a foregone conclusion.
enum BattleEngine {
    /// What both sides start on. Shared, per the model note above.
    static let startingHitPoints = 10

    /// The two sides' combined damage ceiling, split between them by power. Eight, so an evenly
    /// matched pair each roll 1...4 and a 10-point Digimon takes about four landed blows to fell —
    /// long enough to feel like a battle, short enough to animate.
    static let damageScale = 8

    /// Every swing lands for at least this. A hopeless underdog still chips away, so a battle always
    /// terminates and a hurt frame always has something to show.
    static let minimumDamage = 1

    /// Hard stop on the exchange count. Unreachable in practice — at `minimumDamage` a side is felled
    /// in `startingHitPoints` swings, so 40 is double the worst case — but the loop must terminate
    /// on its own even if those constants are retuned into a stalemate.
    static let maximumTurns = 40

    /// The top of `attacker`'s damage roll against `defender`: its share of the two powers.
    ///
    /// Powers are floored at 1 (as `BattlePower.base` already guarantees for real Digimon) so the
    /// division can never be by zero even if a caller hands in a hand-built 0.
    static func maximumDamage(attacker: Int, defender: Int) -> Int {
        let attack = max(1, attacker)
        let defence = max(1, defender)
        return max(minimumDamage, (damageScale * attack) / (attack + defence))
    }

    /// Fights the battle out and reports it.
    ///
    /// The PLAYER swings first, always. A battle is something the user chose to start, and losing
    /// the initiative to a coin flip they cannot see reads as the game cheating.
    static func resolve<G: RandomNumberGenerator>(
        playerPower: Int,
        opponentPower: Int,
        playerMaxHitPoints: Int = startingHitPoints,
        opponentMaxHitPoints: Int = startingHitPoints,
        using generator: inout G
    ) -> BattleReport {
        let power = [max(1, playerPower), max(1, opponentPower)]
        // Floored at 1 so a hand-built 0 (or a stage with no stats) still terminates on the first
        // landed hit rather than starting the loser already dead — a 0-HP bar is a battle with no bar.
        var hitPoints = [max(1, playerMaxHitPoints), max(1, opponentMaxHitPoints)]
        var turns: [BattleTurn] = []
        var attacker = BattleSide.player

        while turns.count < maximumTurns {
            let defender = attacker.other
            let ceiling = maximumDamage(attacker: power[attacker.index],
                                        defender: power[defender.index])
            let damage = Int.random(in: minimumDamage...ceiling, using: &generator)
            hitPoints[defender.index] = max(0, hitPoints[defender.index] - damage)
            turns.append(BattleTurn(attacker: attacker,
                                    damage: damage,
                                    defenderRemainingHitPoints: hitPoints[defender.index]))

            if hitPoints[defender.index] == 0 {
                return BattleReport(playerPower: playerPower, opponentPower: opponentPower,
                                    turns: turns, winner: attacker,
                                    playerMaxHitPoints: max(1, playerMaxHitPoints),
                                    opponentMaxHitPoints: max(1, opponentMaxHitPoints))
            }
            attacker = defender
        }

        // The turn cap, reachable only if the constants above are retuned into a stalemate. Whoever
        // is left standing taller wins; a tie goes to the stronger, and a tie THERE goes to the
        // opponent, because a draw is not something the player gets to bank as a win.
        let winner: BattleSide
        if hitPoints[0] != hitPoints[1] {
            winner = hitPoints[0] > hitPoints[1] ? .player : .opponent
        } else {
            winner = power[0] > power[1] ? .player : .opponent
        }
        return BattleReport(playerPower: playerPower, opponentPower: opponentPower,
                            turns: turns, winner: winner,
                            playerMaxHitPoints: max(1, playerMaxHitPoints),
                            opponentMaxHitPoints: max(1, opponentMaxHitPoints))
    }
}

/// The AI Digimon on the other side: which one it is, and how hard it hits.
struct BattleOpponent: Equatable {
    let node: EvolutionNode
    let power: Int
}

/// Picks who the player fights.
///
/// From the ROSTER (the evolution graph), near the player's own stage — the PRD's "opponent selected
/// near the player's stage". Near and not identical, so the pool is not one node wide at a stage the
/// authored lines only reach once, and not the whole 865 either: being an egg matched against an
/// Ultimate is not a battle, it is a formality.
enum BattleMatchmaker {
    /// How many rungs either side of the player's own count as "near".
    static let maximumRungGap = 1

    /// A `dexOnly` node is never picked, for the same reason it is never playable: it has no
    /// animated sheet, so its attack and hurt frames do not exist and the battle would animate as
    /// two placeholders.
    ///
    /// Distance is measured with `BattlePower.battleRung`, not `Stage.ladderIndex`, so Armor-Hybrid
    /// — which has no rung of its own — is matched as the Adult it fights like rather than dropping
    /// out of every pool.
    static func candidates(in graph: EvolutionGraph, rung: Int, excluding id: String) -> [EvolutionNode] {
        graph.nodes.filter { node in
            !node.dexOnly
                && node.id != id
                && abs(BattlePower.battleRung(node.stage) - rung) <= maximumRungGap
        }
    }

    /// Picks an opponent for the Digimon with this id, or nil if the roster offers nobody at all.
    ///
    /// The opponent's `strengthStat` is rolled from its stage rather than stored, because the roster
    /// is a list of Digimon and not a list of save files — there is no AI training record to read.
    /// The roll tops out around what a player at that stage would have trained to, so a player who
    /// HAS trained is favoured: battles are meant to pay off the work, and the damage roll is what
    /// keeps an upset on the table. Lifetime energy is zero for the same reason — an AI has not
    /// lived a life to have earned any.
    static func choose<G: RandomNumberGenerator>(
        in graph: EvolutionGraph,
        playerId: String,
        using generator: inout G
    ) -> BattleOpponent? {
        guard let player = graph.node(id: playerId) else { return nil }
        let rung = BattlePower.battleRung(player.stage)

        // Widened rather than given up on, so a sparsely authored stage still gets a fight.
        var pool = candidates(in: graph, rung: rung, excluding: playerId)
        if pool.isEmpty {
            pool = graph.nodes.filter { !$0.dexOnly && $0.id != playerId }
        }
        guard let node = pool.randomElement(using: &generator) else { return nil }
        return rolled(node, using: &generator)
    }

    /// Rolls this node's strength and turns it into an opponent.
    ///
    /// Split out of `choose` so US-122's map-banded pick shares it rather than spelling the roll a
    /// second time: the two paths differ in WHO they draw, and a second copy of the strength rule
    /// would let a map fight be quietly easier than a roster fight.
    static func rolled<G: RandomNumberGenerator>(
        _ node: EvolutionNode,
        using generator: inout G
    ) -> BattleOpponent {
        let opponentRung = BattlePower.battleRung(node.stage)
        let strength = Int.random(in: 0...(opponentRung + 2), using: &generator)
        return BattleOpponent(
            node: node,
            power: BattlePower.power(stage: node.stage, strengthStat: strength, lifetimeEnergy: .zero)
        )
    }
}

/// What a battle costs, and — since US-108 — the only thing that limits how many can be fought.
///
/// **This replaces US-032's five-a-day cap, and it replaces what the cap was FOR.** The cap existed
/// so that a win/loss record could not be farmed into an evolution edge's `minBattleWins` in an
/// afternoon of tapping. That protection has not been dropped; it has changed form. Energy is
/// credited from real HealthKit steps and exercise minutes (`EnergyRates`), so twenty battles now
/// costs 100 points of Strength or Stamina — 40,000 steps, or four hours of exercise — where twenty
/// taps used to cost nothing but time. The new brake is arguably the stronger one, and unlike a
/// counter it is something the user can act on by moving rather than wait out.
enum BattleCost {
    /// Points spent per battle — 5. Until US-177 this borrowed `TrainAction`'s number; training moved
    /// to a calorie-bought charge that spends no energy, so the constant lives here now, where the
    /// last energy cost of an action still is.
    static let energy = 5

    /// The energies a battle can be paid with — the physical pair, Strength (steps) and Stamina
    /// (exercise minutes), and richest first at the point of spending. Spirit (sleep) and Vitality
    /// (calories) are excluded: Vitality is feeding's currency and sleep is not spent to fight.
    static let payableWith: [EnergyType] = [.strength, .stamina]

    /// Why a battle is refused when neither payable energy can cover it. Names the remedy rather than
    /// only the refusal — the energy comes from moving, so there is something to do about it.
    static let insufficientEnergyReason = "Not enough Strength or Stamina. Move to earn more."
}

extension GameState {
    /// Files a finished battle in the win/loss record — and does NOTHING else.
    ///
    /// That "nothing else" is US-031's acceptance criterion, not an omission: LOSING NEVER KILLS AND
    /// NEVER COUNTS AS A CARE MISTAKE. `healthStatus`, `careMistakeCount`, `hunger` and `sickSince`
    /// are all deliberately untouched here, so a losing streak can never cost a Digimon its life —
    /// the only thing that does that is neglect (US-027/US-028/US-029). Battling is meant to be
    /// something a user can try without risking the pet they have raised for a week.
    func recordBattle(_ report: BattleReport) {
        if report.playerWon {
            battleWins += 1
        } else {
            battleLosses += 1
        }
    }
}
