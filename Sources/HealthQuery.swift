import Foundation
import HealthKit

/// One HealthKit sample reduced to what a daily total needs.
///
/// `end` is carried even though today's totals only look at `start` (see `HealthReading.total`):
/// US-013's sleep de-duplication needs the span, and a sample without its end is not a sample.
struct HealthSample: Equatable {
    let start: Date
    let end: Date
    let value: Double

    init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }
}

/// The three metrics accumulated over the local day: steps, active calories, exercise minutes.
///
/// Sleep is deliberately NOT a case here. It is read over a different window (18:00 yesterday to
/// 12:00 today), it is a category type rather than a quantity, and it needs cross-source
/// de-duplication — all of which belong to US-013. Leaving it out is what makes "ask for today's
/// sleep from midnight" impossible to write, for the same reason `SpriteFrame` and `EggFrame` are
/// separate enums: a shared type would let the wrong question compile and answer plausibly.
enum QuantityMetric: String, CaseIterable {
    case steps
    case activeEnergy
    case exercise

    /// The wider metric this is — the one authorization is requested for.
    var metric: HealthMetric {
        switch self {
        case .steps: return .steps
        case .activeEnergy: return .activeEnergy
        case .exercise: return .exercise
        }
    }

    var energyType: EnergyType { metric.energyType }

    var quantityType: HKQuantityType {
        switch self {
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .exercise: return HKQuantityType(.appleExerciseTime)
        }
    }

    /// The unit every sample of this metric is read in. US-014's conversion rates are written
    /// against exactly these units — steps, kilocalories, minutes — so changing one here silently
    /// rescales that energy type.
    var unit: HKUnit {
        switch self {
        case .steps: return .count()
        case .activeEnergy: return .kilocalorie()
        case .exercise: return .minute()
        }
    }
}

/// The local day a daily metric is summed over.
enum HealthDay {
    /// The local day containing `now`, from midnight to the next midnight.
    ///
    /// The end comes from calendar arithmetic rather than `start + 86400` so that the 23- and
    /// 25-hour days at a daylight-saving boundary are still exactly one day.
    static func interval(containing now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        // A calendar with no such day cannot exist for the Gregorian calendar this ships with;
        // fall back to a flat 24h rather than trap, since a wrong window beats no Digimon.
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }
}

extension HealthReading {
    /// Totals the samples belonging to `interval`.
    ///
    /// A sample belongs to the day its START falls in. That counts each sample exactly once and in
    /// exactly one day, so a walk from 23:50 to 00:10 lands wholly in the day it began — no
    /// splitting, and never counted twice.
    ///
    /// The bounds are half-open, `[start, end)`. `DateInterval.contains` is deliberately NOT used:
    /// it includes the end instant, so a sample starting exactly at midnight would belong to both
    /// days at once.
    ///
    /// No samples in the interval is `noData`, never `value(0)` — the app was told nothing, which
    /// is not the same as being told zero. Samples that sum to zero are a real `value(0)`.
    static func total(of samples: [HealthSample], in interval: DateInterval) -> HealthReading {
        let belonging = samples.filter { $0.start >= interval.start && $0.start < interval.end }
        guard !belonging.isEmpty else { return .noData }
        return .value(belonging.reduce(0) { $0 + $1.value })
    }
}

enum HealthQueryError: Error {
    /// No HealthKit on this device at all.
    case healthDataUnavailable
}

/// The HealthKit read `TodayHealthReader` needs, behind a protocol so tests drive it with fixture
/// samples — the Simulator has no health data, so a test against a live query proves nothing.
protocol HealthSampleFetching {
    /// Every sample TOUCHING `interval` — overlapping the edges included. Deciding which of those
    /// belong to the day is the reader's job, not the fetcher's.
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample]
}

/// The real thing: a sample query against `HKHealthStore`.
struct HealthKitSampleFetcher: HealthSampleFetching {
    private let store = HKHealthStore()

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthQueryError.healthDataUnavailable }

        // The predicate is an OVERLAP predicate on purpose — no `.strictStartDate`. It is a fetch
        // limit, not the day rule: `HealthReading.total` decides what belongs to today, in one
        // place. With `.strictStartDate` that rule would live half in a HealthKit flag and half in
        // Swift, and every fixture test below would still pass with the flag set wrong, since
        // fixtures never go through a predicate. The cost is at most a couple of boundary samples.
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: metric.quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = metric.unit
                let quantities = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: quantities.map {
                    HealthSample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                })
            }
            store.execute(query)
        }
    }
}

/// Reads today's steps, active calories and exercise minutes, from local-timezone midnight.
///
/// Sleep is not read here — US-013 owns it, with its own window. See `QuantityMetric`.
struct TodayHealthReader {
    private let fetcher: HealthSampleFetching
    private let calendar: Calendar

    /// - Parameter calendar: supplies the time zone that decides when midnight is. Injectable so a
    ///   test can pin a zone; the app uses `.current`, so a user flying across zones gets the
    ///   local midnight of wherever they are.
    init(fetcher: HealthSampleFetching = HealthKitSampleFetcher(), calendar: Calendar = .current) {
        self.fetcher = fetcher
        self.calendar = calendar
    }

    /// Today's total for one metric.
    ///
    /// A read that fails is `unavailable` rather than `noData`: both convert to zero energy, but
    /// they are not the same fact, and US-027 must not record a care mistake for a HealthKit error
    /// the user did nothing to cause.
    func read(_ metric: QuantityMetric, now: Date) async -> HealthReading {
        let interval = HealthDay.interval(containing: now, calendar: calendar)
        do {
            let samples = try await fetcher.samples(of: metric, in: interval)
            return .total(of: samples, in: interval)
        } catch {
            return .unavailable
        }
    }

    /// Today's total for all three metrics.
    ///
    /// Each metric is read on its own, so one failing or unauthorized type costs its own energy
    /// type and nothing else — the partial-authorization rule US-011 established.
    func readToday(now: Date) async -> [QuantityMetric: HealthReading] {
        var readings: [QuantityMetric: HealthReading] = [:]
        for metric in QuantityMetric.allCases {
            readings[metric] = await read(metric, now: now)
        }
        return readings
    }
}
