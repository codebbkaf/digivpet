import Foundation
import SwiftData

/// One of the four energy types, each earned from a different HealthKit metric.
///
/// Raw values are the persisted spelling, so renaming a case rewrites saved games — change
/// `displayName` instead if the wording needs to shift.
enum EnergyType: String, Codable, CaseIterable {
    /// Steps.
    case strength
    /// Active calories.
    case vitality
    /// Sleep.
    case spirit
    /// Exercise minutes.
    case stamina

    /// What the UI calls this. Free to change — unlike `rawValue`, nothing persists it.
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .vitality: return "Vitality"
        case .spirit: return "Spirit"
        case .stamina: return "Stamina"
        }
    }

    /// The single glyph that labels this type's energy bar. Like `displayName`, nothing persists
    /// it — a bar is one glyph wide because four of them share a 41mm screen with the Digimon.
    var symbol: String {
        switch self {
        case .strength: return "力"
        case .vitality: return "活"
        case .spirit: return "心"
        case .stamina: return "耐"
        }
    }
}

/// A Digimon's stage of life.
///
/// The raw value is the sprite subfolder name on disk, so a stage names the folder its art
/// lives in: `DigimonSpriteView(stage: state.stage.rawValue, name: ...)` needs no mapping table.
enum Stage: String, Codable, CaseIterable {
    case digitama = "Digitama"
    case babyI = "Baby I"
    case babyII = "Baby II"
    case child = "Child"
    case adult = "Adult"
    case perfect = "Perfect"
    case ultimate = "Ultimate-Super Ultimate"
    /// A side branch, not a rung on the ladder — hence no `ladderIndex`.
    case armorHybrid = "Armor-Hybrid"

    /// What the UI calls this stage. Free to change — unlike `rawValue`, nothing persists it.
    ///
    /// It differs from `rawValue` only where the folder name is not a stage name: the art for the
    /// final stage is filed under "Ultimate-Super Ultimate" because that one folder holds both,
    /// but the stage a Digimon reaches is the PRD's sixth rung, Ultimate.
    var displayName: String {
        switch self {
        case .ultimate: return "Ultimate"
        default: return rawValue
        }
    }

    /// Position on the linear Digitama -> Ultimate ladder, or nil for stages off it.
    ///
    /// Nil is why this is not just `allCases.firstIndex(of:)`: Armor-Hybrid has no rung, so a
    /// skip check must treat it as "unknown", not as the rung after Ultimate.
    var ladderIndex: Int? {
        switch self {
        case .digitama: return 0
        case .babyI: return 1
        case .babyII: return 2
        case .child: return 3
        case .adult: return 4
        case .perfect: return 5
        case .ultimate: return 6
        case .armorHybrid: return nil
        }
    }
}

/// Whether the Digimon is being cared for well enough.
enum HealthStatus: String, Codable, CaseIterable {
    case healthy
    case sick
    case dead
}

/// A running total per energy type.
///
/// A struct rather than four loose Ints so the same shape serves both the per-stage total and
/// the lifetime total, and so callers can address a total by `EnergyType` without a switch.
struct EnergyTotals: Codable, Equatable {
    var strength: Int = 0
    var vitality: Int = 0
    var spirit: Int = 0
    var stamina: Int = 0

    static let zero = EnergyTotals()

    subscript(type: EnergyType) -> Int {
        get {
            switch type {
            case .strength: return strength
            case .vitality: return vitality
            case .spirit: return spirit
            case .stamina: return stamina
            }
        }
        set {
            switch type {
            case .strength: strength = newValue
            case .vitality: vitality = newValue
            case .spirit: spirit = newValue
            case .stamina: stamina = newValue
            }
        }
    }

    /// Summed across all four types.
    var total: Int { strength + vitality + spirit + stamina }
}

/// When each energy type last went up, or nil for one that never has.
///
/// Exists only to break a tie for `dominantEnergyType`. Dates rather than a counter because the
/// clock is already injected everywhere energy is earned, so a test can order two increments
/// without waiting real time.
struct EnergyRecency: Codable, Equatable {
    var strength: Date?
    var vitality: Date?
    var spirit: Date?
    var stamina: Date?

    static let never = EnergyRecency()

    subscript(type: EnergyType) -> Date? {
        get {
            switch type {
            case .strength: return strength
            case .vitality: return vitality
            case .spirit: return spirit
            case .stamina: return stamina
            }
        }
        set {
            switch type {
            case .strength: strength = newValue
            case .vitality: vitality = newValue
            case .spirit: spirit = newValue
            case .stamina: stamina = newValue
            }
        }
    }
}

/// The saved game: one record, holding everything about the Digimon currently being raised.
///
/// Time-based state (hunger, care mistakes, sickness, death) is stored as the timestamps it is
/// derived from rather than as ticked-forward counters, so it stays correct after the app has
/// been closed for days.
@Model
final class GameState {
    /// Node id in the evolution graph — not the sprite filename, which the graph resolves.
    var currentDigimonId: String
    var stage: Stage
    /// Energy earned since this stage began. Reset on evolution; decides the branch taken.
    var stageEnergy: EnergyTotals
    /// Energy earned over the Digimon's whole life. Survives evolution and death.
    var lifetimeEnergy: EnergyTotals
    /// Backing store for `energyLastEarned`, and the reason it is optional: this property was
    /// added to an already-shipped model, and an OPTIONAL attribute is the one shape SwiftData
    /// will migrate into an existing store without a default. A non-optional composite is not —
    /// it opens, then fails validation on the next save with "energyLastEarned is a required
    /// value", because the macro's default never reaches the store. `nil` means "written before
    /// this existed", which is exactly what `.never` means, so nothing is lost by folding them
    /// together.
    private var energyLastEarnedStorage: EnergyRecency?
    var birthDate: Date
    var stageEnteredDate: Date
    var careMistakeCount: Int
    var hunger: Int
    var strengthStat: Int
    var healthStatus: HealthStatus
    var battleWins: Int
    var battleLosses: Int

    /// A brand new Digimon: an unhatched egg with nothing accumulated yet.
    ///
    /// Every other field is `var`, so a test or a migration can set them individually rather
    /// than needing a twelve-argument initializer.
    init(currentDigimonId: String, stage: Stage = .digitama, now: Date) {
        self.currentDigimonId = currentDigimonId
        self.stage = stage
        self.stageEnergy = .zero
        self.lifetimeEnergy = .zero
        self.energyLastEarnedStorage = .never
        self.birthDate = now
        self.stageEnteredDate = now
        self.careMistakeCount = 0
        self.hunger = 0
        self.strengthStat = 0
        self.healthStatus = .healthy
        self.battleWins = 0
        self.battleLosses = 0
    }
}

extension GameState {
    /// When each type of `stageEnergy` last went up. Read only to break a `dominantEnergyType`
    /// tie, and written everywhere `stageEnergy` is — miss one and that increment silently stops
    /// counting as recent.
    ///
    /// Computed, so the optionality that persistence needs stops at the model boundary: a saved
    /// game from before this property existed reads as `.never` rather than as a `nil` every
    /// caller would have to remember to unwrap.
    var energyLastEarned: EnergyRecency {
        get { energyLastEarnedStorage ?? .never }
        set { energyLastEarnedStorage = newValue }
    }

    /// The energy type this stage has earned the most of — the branch the evolution engine takes.
    ///
    /// Deliberately `stageEnergy`, not `lifetimeEnergy`: the branch is chosen by what this stage
    /// was fed, so a Digimon that spent its childhood walking can still evolve down the sleep
    /// branch if that is how it spends adulthood.
    ///
    /// Nil while all four totals are zero. A caller must get "no leaning yet" rather than an
    /// arbitrary type, because a fresh egg has genuinely not chosen anything and picking for it
    /// would silently hard-code the first branch.
    var dominantEnergyType: EnergyType? {
        guard stageEnergy.total > 0 else { return nil }
        // `allCases` order decides nothing on its own — `outranks` is a strict test, so a later
        // type replaces an earlier one only by really beating it.
        return EnergyType.allCases.reduce(nil) { leader, type in
            guard let leader else { return type }
            return outranks(type, leader) ? type : leader
        }
    }

    /// Whether `type` beats `other`: more energy wins, and a tie goes to the one earned most
    /// recently.
    private func outranks(_ type: EnergyType, _ other: EnergyType) -> Bool {
        guard stageEnergy[type] == stageEnergy[other] else {
            return stageEnergy[type] > stageEnergy[other]
        }
        // Tied. A type never earned this stage cannot outrank one that has; if neither has a
        // timestamp, or both were earned in the same instant — every type credited by one read
        // shares its `now` — nothing distinguishes them, so the incumbent keeps it and the answer
        // stays stable across calls.
        guard let mine = energyLastEarned[type] else { return false }
        guard let theirs = energyLastEarned[other] else { return true }
        return mine > theirs
    }
}
