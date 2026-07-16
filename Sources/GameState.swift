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
