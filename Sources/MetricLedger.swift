import Foundation
import HealthKit
import SwiftData

/// A running total per `ConditionMetric`.
///
/// A dictionary rather than `EnergyTotals`' four named fields, because the vocabulary here is
/// open: `ConditionMetric` gained 27 cases in US-056 and will gain more, and a struct with a
/// property per metric would have to be edited — and migrated — every time one is added. Keyed by
/// `rawValue` for the same reason `EvolutionCondition.metric` is a String: an unknown key must read
/// as zero, not as a decode failure that takes the whole saved game down with it.
struct MetricTotals: Codable, Equatable {
    /// Metric raw value -> total. Absent means zero; nothing writes an explicit 0.
    var values: [String: Double]

    static let zero = MetricTotals(values: [:])

    init(values: [String: Double] = [:]) {
        self.values = values
    }

    subscript(metric: ConditionMetric) -> Double {
        get { values[metric.rawValue] ?? 0 }
        set { values[metric.rawValue] = newValue }
    }
}

extension ConditionMetric {
    /// Whether a stage-long or lifetime TOTAL of this metric means anything.
    ///
    /// This is the gate on what may be accumulated at all, and it exists because most of the
    /// vocabulary accumulates and a loud minority does not. Steps, minutes and event counts add up:
    /// 4,000 steps today and 4,000 tomorrow is 8,000 steps this stage. A resting heart rate does
    /// not — it is a measurement of a standing state, and a stage-long "total" resting heart rate
    /// is a five-figure number that satisfies every criterion ever written, which is the exact trap
    /// US-057 built `HealthMetricAggregation.averageQuantity` to avoid. A condition on one of those
    /// must be answered by reading the window directly through `HealthMetricReader`, which averages
    /// it, and never off this ledger.
    ///
    /// `care.*` is false because those counters are not daily cumulative readings at all — the game
    /// keeps them itself on `GameState`, and crediting a delta of one would be inventing a second,
    /// disagreeing copy.
    var accumulatesOverTime: Bool {
        // Sleep is absent from `ReadableHealthMetric` by construction (it needs `SleepAnalysis`'
        // cross-source de-duplication), but the number it yields is MINUTES, and minutes accumulate
        // exactly like exercise minutes do. Whoever reads the night is free to bank it here.
        if self == .healthSleep { return true }
        guard let readable = ReadableHealthMetric(self) else { return false }
        switch readable.aggregation {
        case .averageQuantity: return false
        case .sumQuantity, .countEvents, .countStoodHours, .sumDurationMinutes: return true
        }
    }
}

/// What today's per-metric readings have already been banked, so refreshing twice does not
/// double-count.
///
/// The same shape and the same reasoning as `EnergyLedger`, and separate from it for the same
/// reason it is separate from `GameState`: health readings are cumulative daily totals — "steps
/// today" is 4,000 at noon and still those same 4,000 at 18:00 — so crediting the reading itself
/// would pay for the same steps at every refresh. This remembers what was already banked, and only
/// the difference is added.
///
/// A SECOND ledger rather than more fields on `EnergyLedger`, because the two answer to different
/// caps and different lifetimes: `EnergyLedger.creditedToday` is clamped by
/// `EnergyRates.dailyCapPerEnergyType` and is a currency, while these are raw measurements with no
/// cap at all. Folding them together would put one day's `min` in the way of the other's total.
@Model
final class MetricLedger {
    /// The local day `creditedToday` describes — midnight, from the calendar the readings were
    /// taken in.
    var day: Date

    /// Backing store for `creditedToday`. A plain `[String: Double]`, which SwiftData stores
    /// directly, rather than a `MetricTotals` composite — the wrapper is a value-type convenience
    /// and does not need to be the persisted shape.
    private var creditedTodayStorage: [String: Double]

    init(day: Date, creditedToday: MetricTotals = .zero) {
        self.day = day
        self.creditedTodayStorage = creditedToday.values
    }
}

extension MetricLedger {
    /// Each metric's whole-day reading already banked for `day`.
    var creditedToday: MetricTotals {
        get { MetricTotals(values: creditedTodayStorage) }
        set { creditedTodayStorage = newValue.values }
    }

    /// Starts the day's baselines over when the local day has turned.
    ///
    /// Yesterday's baseline is not today's — the readings restarted at zero at midnight too, so
    /// keeping it would refuse to credit today until it out-walked yesterday.
    ///
    /// - Parameter calendar: decides when midnight is, and must be the one the readings were taken
    ///   with. The app uses `.current` throughout.
    func rollDay(to now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        guard day != today else { return }
        day = today
        creditedToday = .zero
    }

    /// Banks whatever part of this metric's whole-day reading has not been banked yet, and hands
    /// that delta back to the caller.
    ///
    /// **The one place the de-duplication rule lives**, so every consumer of a metric — the stage
    /// and lifetime totals `MetricCreditor` keeps, and the per-map step accrual of US-118 — is
    /// spending the SAME delta rather than each computing its own from a private baseline. Two
    /// baselines over one reading is how "walking 1,000 steps credited the map 2,000" happens.
    ///
    /// `max(0,)`: a day's reading can go DOWN. Health data can be deleted from the Health app, and
    /// a source can revise a sample downward. Progress is never taken back.
    ///
    /// A claimed delta is spent: calling this twice for the same reading returns 0 the second time.
    /// That is the point of it, and it is also the constraint on adding a second caller — see
    /// `MainScreenModel.creditMapSteps`, which is today the only claimer of `health.steps`.
    func claim(_ metric: ConditionMetric, dayTotal: Double, now: Date, calendar: Calendar = .current) -> Double {
        rollDay(to: now, calendar: calendar)
        let delta = max(0, dayTotal - creditedToday[metric])
        guard delta > 0 else { return 0 }
        creditedToday[metric] += delta
        return delta
    }
}

/// Banks a day's per-metric readings into the stage, lifetime and best-day totals a `window:`
/// condition is compared against.
enum MetricCreditor {
    /// Credits `readings` into `state`, and returns what this call added.
    ///
    /// `readings` are WHOLE-DAY totals for the local day containing `now` — the same anchoring
    /// `EnergyCreditor` requires, so a reading and its baseline can never fall on opposite sides of
    /// a midnight. Metrics that do not accumulate, and readings that are not a real `value`, are
    /// skipped: being told nothing is not being told zero.
    ///
    /// - Parameter calendar: decides when midnight is, and must be the one the readings were taken
    ///   with. The app uses `.current` throughout.
    @discardableResult
    static func credit(
        _ readings: [ConditionMetric: HealthReading],
        to state: GameState,
        ledger: MetricLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> MetricTotals {
        ledger.rollDay(to: now, calendar: calendar)

        var credited = MetricTotals.zero
        for (metric, reading) in readings {
            guard metric.accumulatesOverTime else { continue }
            guard case .value(let dayTotal) = reading else { continue }

            // The best single day is judged on the DAY'S total, not on this call's delta: a day is
            // read many times as it fills, and the last read of it is the whole day. Recorded even
            // when the delta is zero, so a day re-read after a restart still counts.
            if dayTotal > state.stageBestDayMetrics[metric] {
                state.stageBestDayMetrics[metric] = dayTotal
            }

            // Through `claim` rather than inline, so this and US-118's map accrual share one
            // baseline and one "a reading can go DOWN" rule — see `MetricLedger.claim`.
            let delta = ledger.claim(metric, dayTotal: dayTotal, now: now, calendar: calendar)
            guard delta > 0 else { continue }
            credited[metric] = delta
            // Both totals accrue in the same place so they cannot drift apart. They diverge only
            // where they are meant to: `enterStage` clears the stage totals and leaves the
            // lifetime ones standing.
            state.stageMetricTotals[metric] += delta
            state.lifetimeMetricTotals[metric] += delta
        }
        return credited
    }
}
