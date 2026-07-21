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
        profile: PlayerProfile,
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
            // where they are meant to: evolution resets the Digimon's `stageEnergy` and leaves the
            // player's `lifetimeEnergy` — which since US-123 is on the PROFILE, so it survives the
            // Digimon that earned it without anything having to copy it across.
            state.stageEnergy[type] += delta
            profile.lifetimeEnergy[type] += delta
            // Stamped with the read time, not the moment the activity happened — the readings are
            // whole-day totals and cannot say when within the day a step was taken. It only ever
            // orders one type against another, and every type this read credits is stamped alike.
            state.energyLastEarned[type] = now
        }
        return credited
    }
}

/// One refresh's health read, before anything has been made of it.
///
/// Exists so the readings can be spent twice without being read twice: energy wants them keyed by
/// `EnergyType` and converted at `EnergyRates`, while US-118's map accrual wants the raw step
/// count. Keeping both off one read is what makes "the map is credited from the SAME reading the
/// energy came from" structurally true rather than a comment.
struct HealthDayReadings {
    /// Today's totals for the three daily quantities, keyed as they were read.
    let quantities: [QuantityMetric: HealthReading]

    /// Last night's asleep minutes — a different window and a different reader. See
    /// `HealthEnergySource`.
    let sleep: HealthReading

    /// What `EnergyCreditor` takes: one reading per energy type, sleep included as Spirit.
    var byEnergyType: [EnergyType: HealthReading] {
        var readings: [EnergyType: HealthReading] = [:]
        for (metric, reading) in quantities {
            readings[metric.energyType] = reading
        }
        readings[.spirit] = sleep
        return readings
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
        await dayReadings(now: now).byEnergyType
    }

    /// The same one read, kept in the shape it was read in.
    ///
    /// US-118 needs the STEP total specifically — a map records steps, not Strength — and
    /// `byEnergyType` has already thrown that away: `.strength` says how much energy the steps
    /// bought, capped and divided by the rate, which is not a number of steps. Reading HealthKit a
    /// second time for it would be a second read of the same day, one refresh apart, and the two
    /// answers would not have to agree.
    func dayReadings(now: Date) async -> HealthDayReadings {
        HealthDayReadings(quantities: await todayReader.readToday(now: now),
                          sleep: await sleepReader.read(now: now))
    }

    /// Last night's longest asleep block, or nil if there was none to read.
    ///
    /// Separate from `readings` because the two want different things out of the same night: energy
    /// is paid for the MINUTES asleep, while US-026's sleep window needs WHEN the block was. Routed
    /// through here rather than by handing `MainScreenModel` its own reader, so a test that has
    /// already injected a fixture sleep fetcher drives both answers from the one seam.
    func lastNightSleepBlock(now: Date) async -> SleepBlock? {
        await sleepReader.readBlock(now: now)
    }
}
