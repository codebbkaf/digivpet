import Foundation

/// How much meat a battle win drops (US-175), an inclusive `min...max` range rolled from an
/// injected generator. A struct rather than two loose fields so the range is validated and passed
/// as one thing.
struct MeatRange: Codable, Equatable {
    let min: Int
    let max: Int
}

/// Rolls a battle-win meat drop and returns how much can actually be banked (US-175).
///
/// The drop is a whole number in `range.min...range.max` inclusive, drawn from an injected
/// generator so a test pins the roll without waiting on real randomness. What is RETURNED is that
/// drop clamped to the room left under `cap` — `max(0, cap - current)` — so a win at a full larder
/// drops nothing rather than pushing the pool past its ceiling. The number shown on the result
/// screen and the number added to the pool are this ONE value, so they can never disagree.
enum MeatReward {
    static func rolled<G: RandomNumberGenerator>(
        from range: MeatRange, current: Int, cap: Int, using generator: inout G
    ) -> Int {
        let drop = Int.random(in: range.min...range.max, using: &generator)
        return min(drop, max(0, cap - current))
    }
}

/// The agility dodge / hit-rate formula's constants (US-186).
///
/// The chance an attack LANDS is `base` when the two combatants have equal Agility, adjusted by
/// `agilityWeight` per point the defender is more (or less) agile, then clamped to `floor...ceiling`
/// so nothing is ever a guaranteed hit or a guaranteed dodge. The formula lives in battle code; the
/// numbers live here so the economy can be retuned without a build.
struct HitRateCoefficients: Codable, Equatable {
    /// Hit chance at equal Agility, 0...1.
    let base: Double
    /// How much hit chance moves per point of Agility difference.
    let agilityWeight: Double
    /// Lowest a hit chance may be clamped to — a floor of 0 would let a foe become un-hittable.
    let floor: Double
    /// Highest a hit chance may be clamped to — a ceiling of 1 would make a hit a certainty.
    let ceiling: Double
}

/// The attacker-vs-defender element matchup multipliers on real damage (US-189).
///
/// Attack is scaled by one of these three depending on whether the attacker's element beats, ties
/// or loses to the defender's (from `ElementCatalog`), with the result never dropping below
/// `minimum` so a hit always dents at least one HP dash.
struct ElementDamageMultipliers: Codable, Equatable {
    let advantage: Double
    let neutral: Double
    let disadvantage: Double
    /// Damage floor after the multiplier — at least this many HP dashes per landed hit.
    let minimum: Int
}

/// One stage's base battle stats and how far training can push them (US-190, US-192).
///
/// `trainingCap` is the maximum BONUS training may add on top of the base, so a Digimon's ceiling
/// on a stat is `base + trainingCap`. Higher stages carry both a higher base and a larger cap, so
/// evolving is what unlocks the room to grow.
struct StageStats: Codable, Equatable {
    let baseHP: Int
    let baseAttack: Int
    let baseAgility: Int
    let trainingCap: Int
}

/// Every HealthKit-to-game conversion constant, shipped as data (US-170).
///
/// In the shape of `MapCatalog` on purpose, down to the `fatalError`-on-bad-data `bundled`: these
/// are the same kind of object — a shipped table the game reads and never writes. Before this file
/// the constants were scattered across `FeedAction`, `TrainAction` and `Battle`'s `BattleLimits`,
/// so retuning the economy meant a code change; now it is a data edit.
struct ConsumptionConfig: Codable, Equatable {
    /// Active kcal that buy one training charge (US-173).
    let kcalPerTrain: Int
    /// The most training charges a Digimon may bank at once (US-177).
    let maxTrainCharges: Int
    /// Steps that buy one battle charge (US-176).
    let stepsPerBattleCharge: Int
    /// The most battle charges a Digimon may bank at once.
    let maxBattleCharges: Int
    /// HealthKit handwashing events that buy one cleaning charge (US-177).
    let handwashPerCleanCharge: Int
    /// The most cleaning charges the player may bank at once.
    let maxCleanCharges: Int
    /// How much meat a battle win drops (US-175).
    let meatPerBattleWin: MeatRange
    /// The most meat the global pool may hold (US-174).
    let meatCap: Int
    /// The dodge / hit-rate formula's constants (US-186).
    let hitRate: HitRateCoefficients
    /// The element matchup damage multipliers (US-189).
    let elementDamage: ElementDamageMultipliers
    /// Base stats and training caps keyed by `Stage.rawValue` (US-190, US-192). Digitama has no
    /// entry — an egg never battles.
    let stageStats: [String: StageStats]

    /// The stats for a stage, or nil if the config has none (Digitama, or a table that is missing a
    /// rung). Keyed on `rawValue` because that is what persists and what the JSON authors.
    func stats(for stage: Stage) -> StageStats? {
        stageStats[stage.rawValue]
    }

    /// The base battle stats for a roster entry, or nil when it never fights (US-187).
    ///
    /// Nil for a `dexOnly` entry — an idle-only Digimon is never playable — and nil for a Digitama,
    /// which resolves through `stats(for:)` returning nil for the one stage the table omits (an egg
    /// has no combat stats). Every other playable Digimon reads its HP/Attack/Agility straight off
    /// its stage's row, so a Perfect out-stats a Child by construction and no per-Digimon table is
    /// needed to give all 868 playable entries all three stats.
    func stats(for entry: RosterEntry) -> StageStats? {
        guard !entry.dexOnly else { return nil }
        return stats(for: entry.stage)
    }
}

extension ConsumptionConfig {
    /// Every value that must be strictly positive, named for both the validator and the range test.
    ///
    /// A rate of zero or below is nonsense the game cannot recover from: zero `kcalPerTrain` divides
    /// by zero, a zero `hitRate.ceiling` makes every attack miss. Exposed rather than inlined so the
    /// validator and `ConsumptionConfigTests` check the SAME list — a field added to the config and
    /// forgotten here is invisible to both, so this is the one place to keep current.
    var rates: [(name: String, value: Double)] {
        [
            ("kcalPerTrain", Double(kcalPerTrain)),
            ("stepsPerBattleCharge", Double(stepsPerBattleCharge)),
            ("handwashPerCleanCharge", Double(handwashPerCleanCharge)),
            ("hitRate.base", hitRate.base),
            ("hitRate.floor", hitRate.floor),
            ("hitRate.ceiling", hitRate.ceiling),
            ("elementDamage.advantage", elementDamage.advantage),
            ("elementDamage.neutral", elementDamage.neutral),
            ("elementDamage.disadvantage", elementDamage.disadvantage),
        ]
    }

    /// Every value that must be non-negative — a cap, a floor or an amount. Zero is allowed (a
    /// `meatCap` of 0 is a valid "no meat economy"), only negatives are rejected.
    var caps: [(name: String, value: Int)] {
        [
            ("maxTrainCharges", maxTrainCharges),
            ("maxBattleCharges", maxBattleCharges),
            ("maxCleanCharges", maxCleanCharges),
            ("meatCap", meatCap),
            ("meatPerBattleWin.min", meatPerBattleWin.min),
            ("meatPerBattleWin.max", meatPerBattleWin.max),
            ("elementDamage.minimum", elementDamage.minimum),
        ]
    }
}

extension ConsumptionConfig {
    /// Basename of the bundled config file.
    static let resourceName = "consumption"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(ConsumptionConfig.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the config from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> ConsumptionConfig {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(ConsumptionConfig.self, from: try Data(contentsOf: url))
    }

    /// The shipped config, decoded once on first use.
    ///
    /// Traps like `MapCatalog.bundled` and `Roster.bundled`, for the same reason: an undecodable
    /// shipped file is a broken build, not a runtime condition. Degrading to defaults would hide the
    /// break and quietly reprice the whole economy.
    static let bundled: ConsumptionConfig = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the consumption config: \(error)")
        }
    }()
}
