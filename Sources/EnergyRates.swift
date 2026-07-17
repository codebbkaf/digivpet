import Foundation

/// The v1 conversion rates: how much of a health metric buys one point of each energy type.
///
/// Every rate lives here and nowhere else, so retuning the game is editing four numbers rather
/// than hunting through the reader, the ledger and the UI.
///
/// **The rates are written against the units the readers hand back**, and only those:
/// steps (`.count()`), active kilocalories (`.kilocalorie()`), exercise minutes (`.minute()`) and
/// asleep minutes (`SleepBlock.asleepMinutes`). Reading exercise in seconds instead of minutes
/// would inflate Stamina 60-fold and still look like a working query, which is why
/// `QuantityMetric.unit` and `SleepQuery` pin their units in tests of their own.
enum EnergyRates {
    /// 1 Strength per 100 steps.
    static let stepsPerStrengthPoint = 100.0
    /// 1 Vitality per 20 active kcal.
    static let activeKilocaloriesPerVitalityPoint = 20.0
    /// 1 Spirit per 15 minutes asleep.
    static let sleepMinutesPerSpiritPoint = 15.0
    /// 1 Stamina per 2 exercise minutes.
    static let exerciseMinutesPerStaminaPoint = 2.0

    /// The most one energy type can earn in a single local day.
    ///
    /// Per type, not across all four: a marathon day should not also max out Spirit. Four types at
    /// 100 means a day's ceiling is 400, and only for someone who slept 25 hours while running one.
    static let dailyCapPerEnergyType = 100

    /// How much of its source metric one point of `type` costs, in that metric's unit.
    static func measurementPerPoint(of type: EnergyType) -> Double {
        switch type {
        case .strength: return stepsPerStrengthPoint
        case .vitality: return activeKilocaloriesPerVitalityPoint
        case .spirit: return sleepMinutesPerSpiritPoint
        case .stamina: return exerciseMinutesPerStaminaPoint
        }
    }

    /// What `measurement` is worth, rounded DOWN.
    ///
    /// Down, so a point always means the whole activity behind it was really done: 199 steps is one
    /// point, not two. Rounding up would let four short walks buy four points from 4 steps.
    static func points(from measurement: Double, of type: EnergyType) -> Int {
        // `Int(Double)` TRAPS when the double is outside Int's range, and neither NaN nor infinity
        // is ours to rule out — the number comes from HealthKit, which is free to hand back a
        // sample written by any app on the phone. A wrong Digimon beats a crashed one.
        guard measurement.isFinite, measurement > 0 else { return 0 }
        let raw = (measurement / measurementPerPoint(of: type)).rounded(.down)
        guard raw < Double(Int.max) else { return .max }
        return Int(raw)
    }

    /// What a whole day's `reading` is worth, capped at the daily maximum.
    ///
    /// `noData` and `unavailable` are worth zero rather than an error, per US-011: one denied or
    /// failing metric costs its own energy type and nothing else.
    static func cappedDailyPoints(from reading: HealthReading, of type: EnergyType) -> Int {
        min(points(from: reading.energyValue, of: type), dailyCapPerEnergyType)
    }
}
