import Foundation
import HealthKit

/// How one metric's samples become a single number.
///
/// The split exists because HealthKit sample types disagree about what their `value` means, and a
/// reader with one rule would answer plausibly and wrongly for most of the vocabulary: summing a
/// resting heart rate over a month gives a five-figure BPM, and summing a category value gives the
/// sum of `HKCategoryValueNotApplicable`, which is zero however long you brushed your teeth.
enum HealthMetricAggregation: Equatable {
    /// Total the sample values, read in this unit. For metrics that accumulate — steps, metres,
    /// kilocalories, minutes.
    case sumQuantity(HKUnit)

    /// Mean of the sample values, read in this unit. For DISCRETE quantities, where each sample is
    /// a measurement of a standing state rather than an amount earned: VO2 max, resting heart rate,
    /// HRV, respiratory rate, blood oxygen, effort, audio exposure. A total of those is not a
    /// bigger version of the thing, it is a different thing and a meaningless one.
    case averageQuantity(HKUnit)

    /// Count the samples, ignoring their values. THE category rule: a handwashing sample's value is
    /// `HKCategoryValueNotApplicable` — the event carries no magnitude, only the fact that it
    /// happened. Also how workouts are counted, one `HKWorkout` being one workout.
    case countEvents

    /// Count only the samples HealthKit marked `.stood`. `.appleStandHour` records an entry for
    /// every hour of the day, `stood` or `idle`, so a plain event count would report 24 for a day
    /// spent motionless — the exact opposite of what a stand-hour criterion asks.
    case countStoodHours

    /// Total the samples' DURATIONS, in minutes. For `.mindfulSession`, whose value is a category
    /// (no magnitude) but whose span is the number the metric is named for.
    case sumDurationMinutes
}

/// A `health.*` metric this reader can actually total, paired with the HealthKit type and rule it
/// is read by.
///
/// It is a struct with a FAILABLE init rather than a second enum listing the same cases, and that
/// failability is load-bearing: it is the only way to hold a metric this reader can read. Passing
/// `care.trainingSessions` or `health.sleep` to `HealthMetricReader` therefore does not compile
/// into a plausible wrong answer — it does not compile at all. Same reasoning as `QuantityMetric`
/// excluding sleep, and `SpriteFrame`/`EggFrame` being separate enums.
///
/// **`health.sleep` is deliberately not readable here.** Sleep needs cross-source de-duplication
/// and a longest-block rule that a flat total cannot express — `SleepAnalysis` owns it, and
/// counting sleep samples as events would hand back a number of *segments*, which is a number, and
/// wrong. A condition on `health.sleep` must route to `LastNightSleepReader`.
struct ReadableHealthMetric: Equatable {
    let metric: ConditionMetric
    let sampleType: HKSampleType
    let aggregation: HealthMetricAggregation

    /// Nil for `care.*` (no HealthKit type at all) and for `health.sleep` (see above).
    init?(_ metric: ConditionMetric) {
        guard let source = Self.source(for: metric) else { return nil }
        self.metric = metric
        self.sampleType = source.0
        self.aggregation = source.1
    }

    /// Every metric this reader can read. Sleep and the `care.*` counters are absent by
    /// construction, since `init?` returns nil for them.
    static let all: [ReadableHealthMetric] = ConditionMetric.allCases.compactMap(ReadableHealthMetric.init)

    // Units are the ones US-055 probed the types with, and `HealthMetricReaderTests` asserts every
    // one is `is(compatibleWith:)` its quantity type — `doubleValue(for:)` raises an Objective-C
    // exception on a mismatched unit, which no fixture test could ever catch, because fixtures
    // never carry an `HKQuantity`.
    private static func source(for metric: ConditionMetric) -> (HKSampleType, HealthMetricAggregation)? {
        switch metric {
        // Quantities that accumulate.
        case .healthSteps:
            return (HKQuantityType(.stepCount), .sumQuantity(.count()))
        case .healthDistanceWalkingRunning:
            return (HKQuantityType(.distanceWalkingRunning), .sumQuantity(.meter()))
        case .healthFlightsClimbed:
            return (HKQuantityType(.flightsClimbed), .sumQuantity(.count()))
        case .healthExerciseMinutes:
            return (HKQuantityType(.appleExerciseTime), .sumQuantity(.minute()))
        case .healthStandTime:
            return (HKQuantityType(.appleStandTime), .sumQuantity(.minute()))
        case .healthActiveEnergy:
            return (HKQuantityType(.activeEnergyBurned), .sumQuantity(.kilocalorie()))
        case .healthBasalEnergy:
            return (HKQuantityType(.basalEnergyBurned), .sumQuantity(.kilocalorie()))
        case .healthDistanceSwimming:
            return (HKQuantityType(.distanceSwimming), .sumQuantity(.meter()))
        case .healthDistanceCycling:
            return (HKQuantityType(.distanceCycling), .sumQuantity(.meter()))
        case .healthWater:
            return (HKQuantityType(.dietaryWater), .sumQuantity(.liter()))
        case .healthDaylight:
            return (HKQuantityType(.timeInDaylight), .sumQuantity(.minute()))

        // Discrete quantities — averaged, never totalled.
        case .healthVO2Max:
            let millilitres = HKUnit.literUnit(with: .milli)
            let perKilogramMinute = HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())
            return (HKQuantityType(.vo2Max), .averageQuantity(millilitres.unitDivided(by: perKilogramMinute)))
        case .healthRestingHeartRate:
            return (HKQuantityType(.restingHeartRate), .averageQuantity(HKUnit.count().unitDivided(by: .minute())))
        case .healthHeartRateVariability:
            return (HKQuantityType(.heartRateVariabilitySDNN), .averageQuantity(.secondUnit(with: .milli)))
        case .healthRespiratoryRate:
            return (HKQuantityType(.respiratoryRate), .averageQuantity(HKUnit.count().unitDivided(by: .minute())))
        case .healthOxygenSaturation:
            return (HKQuantityType(.oxygenSaturation), .averageQuantity(.percent()))
        case .healthPhysicalEffort:
            let perHourKilogram = HKUnit.hour().unitMultiplied(by: .gramUnit(with: .kilo))
            return (HKQuantityType(.physicalEffort), .averageQuantity(HKUnit.kilocalorie().unitDivided(by: perHourKilogram)))
        case .healthAudioExposure:
            return (HKQuantityType(.environmentalAudioExposure), .averageQuantity(.decibelAWeightedSoundPressureLevel()))

        // Categories.
        case .healthHandwashing:
            return (HKCategoryType(.handwashingEvent), .countEvents)
        case .healthToothbrushing:
            return (HKCategoryType(.toothbrushingEvent), .countEvents)
        case .healthHighHeartRateEvents:
            return (HKCategoryType(.highHeartRateEvent), .countEvents)
        case .healthLowCardioFitnessEvents:
            return (HKCategoryType(.lowCardioFitnessEvent), .countEvents)
        case .healthWalkingSteadinessEvents:
            return (HKCategoryType(.appleWalkingSteadinessEvent), .countEvents)
        case .healthStandHours:
            return (HKCategoryType(.appleStandHour), .countStoodHours)
        case .healthMindfulMinutes:
            return (HKCategoryType(.mindfulSession), .sumDurationMinutes)

        // Workouts: one grant covers every activity type, so bucketing by activity is a filter at
        // read time rather than a metric of its own (US-055).
        case .healthWorkouts:
            return (HKWorkoutType.workoutType(), .countEvents)

        // Not readable here.
        case .healthSleep:
            return nil
        case .careTrainingSessions, .careOverfeeds, .careSleepDisturbances,
             .careBattleCount, .careBattleWinRatio:
            return nil
        }
    }
}

extension HealthReading {
    /// Reduces the samples belonging to `interval` to one reading.
    ///
    /// Belonging is by START instant, half-open `[start, end)` — the same rule as
    /// `HealthReading.total`, deliberately, so a sample counts exactly once and in exactly one
    /// window whichever reader sees it.
    ///
    /// No samples in the window is `noData`, never `value(0)`: being told nothing is not being told
    /// zero. A window that DID contain samples always yields a real `value`, including the
    /// stand-hour case where every one of them was `idle` — that is a genuine zero.
    static func aggregate(
        _ samples: [HealthSample],
        in interval: DateInterval,
        using aggregation: HealthMetricAggregation
    ) -> HealthReading {
        let belonging = samples.filter { $0.start >= interval.start && $0.start < interval.end }
        guard !belonging.isEmpty else { return .noData }

        switch aggregation {
        case .sumQuantity:
            return .value(belonging.reduce(0) { $0 + $1.value })
        case .averageQuantity:
            return .value(belonging.reduce(0) { $0 + $1.value } / Double(belonging.count))
        case .countEvents:
            return .value(Double(belonging.count))
        case .countStoodHours:
            let stood = belonging.filter { $0.value == Double(HKCategoryValueAppleStandHour.stood.rawValue) }
            return .value(Double(stood.count))
        case .sumDurationMinutes:
            return .value(belonging.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
    }
}

/// The HealthKit read `HealthMetricReader` needs, behind a protocol so tests drive it with fixture
/// samples — the Simulator has no health data, so a test against a live query proves nothing.
protocol HealthMetricSampleFetching {
    /// Every sample TOUCHING `interval`, edges included. Deciding which of them belong to the
    /// window is the reader's job, not the fetcher's.
    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample]
}

/// The real thing: a sample query against `HKHealthStore`.
struct HealthKitMetricFetcher: HealthMetricSampleFetching {
    private let store = HKHealthStore()

    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthQueryError.healthDataUnavailable }

        // An overlap predicate, as in `HealthKitSampleFetcher`: the window rule lives in
        // `HealthReading.aggregate`, in one place, rather than half in a HealthKit flag that no
        // fixture test would ever exercise.
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: metric.sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples ?? []).map { Self.reading($0, as: metric) })
            }
            store.execute(query)
        }
    }

    /// One HealthKit sample flattened to start/end/value.
    ///
    /// `value` means whatever the aggregation will ask of it: the quantity in the metric's unit,
    /// the raw category value (which only `.countStoodHours` looks at), or 1 for a workout, whose
    /// value is its own existence.
    private static func reading(_ sample: HKSample, as metric: ReadableHealthMetric) -> HealthSample {
        let value: Double
        switch metric.aggregation {
        case .sumQuantity(let unit), .averageQuantity(let unit):
            value = (sample as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
        case .countEvents, .countStoodHours, .sumDurationMinutes:
            value = Double((sample as? HKCategorySample)?.value ?? 0)
        }
        return HealthSample(start: sample.startDate, end: sample.endDate, value: value)
    }
}

/// Totals any readable `health.*` metric over an arbitrary window, so an evolution criterion is no
/// longer limited to the four energy metrics.
///
/// The window is passed in rather than computed: US-058 measures over a stage, which starts
/// whenever the Digimon evolved, and `ConditionWindow` also offers `day` and `lifetime`. A reader
/// that decided its own window could only ever answer one of the three.
struct HealthMetricReader {
    private let fetcher: HealthMetricSampleFetching

    init(fetcher: HealthMetricSampleFetching = HealthKitMetricFetcher()) {
        self.fetcher = fetcher
    }

    /// One metric's number over `interval`.
    ///
    /// A read that fails — HealthKit off, type unauthorized, query error — is `unavailable` and
    /// never a throw, matching `TodayHealthReader.read`. A condition is then simply unmet, rather
    /// than an evolution check exploding halfway through and leaving the Digimon in limbo.
    func read(_ metric: ReadableHealthMetric, in interval: DateInterval) async -> HealthReading {
        do {
            let samples = try await fetcher.samples(of: metric, in: interval)
            return .aggregate(samples, in: interval, using: metric.aggregation)
        } catch {
            return .unavailable
        }
    }

    /// Convenience for the caller that holds a `ConditionMetric`: `nil` where that metric is not
    /// readable here (`care.*`, `health.sleep`), so the caller must decide what to do about it
    /// rather than receive a number that looks fine.
    func read(_ metric: ConditionMetric, in interval: DateInterval) async -> HealthReading? {
        guard let readable = ReadableHealthMetric(metric) else { return nil }
        return await read(readable, in: interval)
    }

    /// Reads every metric in `metrics` over `interval`, keyed by its `ConditionMetric`.
    ///
    /// Sequential, matching `TodayHealthReader.readToday`: the fixture fetchers a test drives this
    /// with answer instantly, and a real read happens on scene activation or when the Dex opens,
    /// not in a hot loop. The caller that wants every readable metric passes `ReadableHealthMetric.all`.
    func readings(
        of metrics: [ReadableHealthMetric],
        in interval: DateInterval
    ) async -> [ConditionMetric: HealthReading] {
        var result: [ConditionMetric: HealthReading] = [:]
        for metric in metrics {
            result[metric.metric] = await read(metric, in: interval)
        }
        return result
    }
}
