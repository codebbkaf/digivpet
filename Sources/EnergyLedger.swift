import Foundation
import SwiftData

/// What today's health data has already been paid for.
///
/// This is what makes crediting a DELTA rather than a sum. The health metrics are cumulative daily
/// totals — "steps today" is 4,000 at noon and still counts those same 4,000 at 18:00 — so an app
/// that credited the reading itself would pay for the same steps every time it was opened. The
/// ledger remembers what was already bought, and only the difference is charged.
///
/// It has to outlive the PROCESS, which is why it is persisted at all: "reopening the app never
/// double-credits" is a statement about a cold launch, and an in-memory baseline would be zero
/// again on every one of them.
///
/// Deliberately NOT part of `GameState`: `resetGame` is a total wipe, so a ledger living there
/// would hand a reborn Digimon today's full 400 points a second time, out of the same day's steps.
/// The day belongs to the watch, not to whoever is currently living on it.
@Model
final class EnergyLedger {
    /// The local day `creditedToday` describes — midnight, from the same calendar the readings
    /// were taken in.
    var day: Date
    /// Points already credited for `day`, per type. Never exceeds `EnergyRates.dailyCapPerEnergyType`.
    var creditedToday: EnergyTotals

    init(day: Date, creditedToday: EnergyTotals = .zero) {
        self.day = day
        self.creditedToday = creditedToday
    }
}

/// Turns a day's health readings into energy, charging only for what has not been paid for yet.
enum EnergyCreditor {
    /// Credits `readings` into `state`, and returns the points added by this call.
    ///
    /// `readings` are whole-day totals — today's steps, today's kcal, today's exercise minutes and
    /// last night's asleep minutes. All four are anchored to the local day containing `now`, which
    /// is the same day the ledger keys on, so a reading and its baseline can never fall on
    /// different sides of a midnight.
    ///
    /// - Parameter calendar: decides when midnight is, and must be the one the readings were taken
    ///   with. The app uses `.current` throughout.
    @discardableResult
    static func credit(
        _ readings: [EnergyType: HealthReading],
        to state: GameState,
        ledger: EnergyLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> EnergyTotals {
        let today = calendar.startOfDay(for: now)
        if ledger.day != today {
            // A new day. Yesterday's baseline is not today's: the readings restarted at zero at
            // midnight too, so keeping it would refuse to credit today until it out-earned
            // yesterday. The cap starts over with it.
            ledger.day = today
            ledger.creditedToday = .zero
        }

        var credited = EnergyTotals.zero
        for type in EnergyType.allCases {
            let earned = EnergyRates.cappedDailyPoints(from: readings[type] ?? .noData, of: type)
            // `max(0,)`: a day's reading can go DOWN. Health data can be deleted from the Health
            // app, and a night still being written can shrink when a source revises it. Energy is
            // never taken back — a Digimon does not un-grow because the watch changed its mind.
            let delta = max(0, earned - ledger.creditedToday[type])
            guard delta > 0 else { continue }
            credited[type] = delta
            ledger.creditedToday[type] += delta
            // Both totals accrue in the same place, so they cannot drift apart. They diverge only
            // where they are meant to: evolution resets `stageEnergy` and leaves `lifetimeEnergy`.
            state.stageEnergy[type] += delta
            state.lifetimeEnergy[type] += delta
            // Stamped with the read time, not the moment the activity happened — the readings are
            // whole-day totals and cannot say when within the day a step was taken. It only ever
            // orders one type against another, and every type this read credits is stamped alike.
            state.energyLastEarned[type] = now
        }
        return credited
    }
}

/// Reads all four energy metrics: the three daily quantities, plus last night's sleep.
///
/// The two readers exist because the questions differ — Spirit comes from a category type over a
/// different window (18:00 yesterday to noon today) needing cross-source de-duplication, and
/// `TodayHealthReader` cannot be asked for sleep at all, by construction. This is the seam where
/// the two answers become one set of readings, keyed by the thing energy actually cares about.
struct HealthEnergySource {
    private let todayReader: TodayHealthReader
    private let sleepReader: LastNightSleepReader

    init(
        todayReader: TodayHealthReader = TodayHealthReader(),
        sleepReader: LastNightSleepReader = LastNightSleepReader()
    ) {
        self.todayReader = todayReader
        self.sleepReader = sleepReader
    }

    /// Every energy type's whole-day reading. Each is read independently, so one denied or failing
    /// metric costs its own energy type and nothing else.
    func readings(now: Date) async -> [EnergyType: HealthReading] {
        var readings: [EnergyType: HealthReading] = [:]
        for (metric, reading) in await todayReader.readToday(now: now) {
            readings[metric.energyType] = reading
        }
        readings[.spirit] = await sleepReader.read(now: now)
        return readings
    }
}
