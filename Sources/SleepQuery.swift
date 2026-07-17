import Foundation
import HealthKit

/// What HealthKit recorded a stretch of the night as.
///
/// The raw values ARE `HKCategoryValueSleepAnalysis`'s, so a sample's `value` maps straight onto a
/// case (`testSleepCategoryRawValuesAreHealthKitsOwn` pins them). Only the four `asleep*` cases
/// count toward Spirit: `inBed` is time on a mattress rather than time asleep, and `awake` is
/// HealthKit saying the opposite of asleep.
enum SleepCategory: Int, CaseIterable {
    case inBed = 0
    /// HealthKit's deprecated plain `.asleep` shares this raw value.
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        case .inBed, .awake: return false
        }
    }
}

/// One sleep-analysis sample: a span, and what the span was.
///
/// Deliberately not `HealthSample`, whose `value` is a quantity. A sleep sample's value is a
/// CATEGORY, and the number Spirit is paid for is its duration instead — a shared type would let
/// `HealthReading.total` sum sleep and hand back the sum of six category raw values, which is a
/// number, and wrong. Same reasoning as US-004's separate `SpriteFrame`/`EggFrame`.
struct SleepSample: Equatable {
    let start: Date
    let end: Date
    let category: SleepCategory

    init(start: Date, end: Date, category: SleepCategory) {
        self.start = start
        self.end = end
        self.category = category
    }

    /// The part of this sample lying inside `window`, or nil if none of it does.
    ///
    /// Sleep is CLIPPED to its window where US-012's daily quantities are assigned whole to the day
    /// they start in. The two rules differ because the data does: a 900-step sample never says when
    /// each step was taken, so splitting it would be invention, while a sleep sample's value IS its
    /// span and clipping it is exact. It matters at the 18:00 edge — someone asleep at 17:30 would
    /// otherwise lose the whole night, since no other night's window would claim it either.
    func clipped(to window: DateInterval) -> SleepSample? {
        let clippedStart = Swift.max(start, window.start)
        let clippedEnd = Swift.min(end, window.end)
        guard clippedEnd > clippedStart else { return nil }
        return SleepSample(start: clippedStart, end: clippedEnd, category: category)
    }
}

/// The window "last night" means.
enum SleepNight {
    /// Last night, relative to the local day `now` falls in: 18:00 the previous day to 12:00 today.
    ///
    /// It is anchored to the day rather than to `now`, so the answer does not move while the user
    /// watches. Checking the app at 03:00 mid-sleep still reads the night in progress; checking at
    /// 23:00 reads the night that ended this morning, not the one just beginning.
    ///
    /// Consecutive windows do not overlap, so no sample can be counted for two nights: last night's
    /// ends at noon and tonight's opens at 18:00. Sleep starting in that afternoon gap belongs to
    /// neither, which is the intent — an afternoon nap is not last night's sleep.
    static func window(for now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        // The fallbacks cannot fire for the Gregorian calendar this ships with; a flat offset beats
        // trapping, since a slightly wrong window still leaves a Digimon fed.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday)
            ?? yesterday.addingTimeInterval(18 * 3600)
        let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)
            ?? today.addingTimeInterval(12 * 3600)
        return DateInterval(start: start, end: end)
    }
}

/// One run of sleep: the asleep stretches between two long breaks, taken together.
struct SleepBlock: Equatable {
    /// First asleep instant to last asleep instant. Brief awakenings inside are part of the span.
    let span: DateInterval
    /// Time actually asleep within the span — the awake gaps are NOT counted.
    let asleepDuration: TimeInterval

    /// What Spirit is paid for. US-014 rates it at 1 point per 15 minutes, so minutes are the unit.
    var asleepMinutes: Double { asleepDuration / 60 }
}

/// Reduces a night of sleep samples to the minutes Spirit is paid for.
enum SleepAnalysis {
    /// How long a break can be before it starts a NEW block rather than interrupting this one.
    ///
    /// A block has to survive an ordinary awakening: Apple Watch records those as `awake` segments
    /// minutes long, and splitting the night at each one would report a fragment of it. It also has
    /// to keep an evening nap separate from the main sleep, which are hours apart. An hour sits in
    /// the wide gap between those. Nothing in the data picks the exact number — it is a v1
    /// judgement, tunable here, and `gapTolerance` is injectable so a test names its own.
    static let blockGapTolerance: TimeInterval = 60 * 60

    /// The longest asleep block inside `window`, or nil if there was no sleep in it.
    ///
    /// "Longest" is measured in time ASLEEP, not in span: a 5-hour block padded out to 9 hours by
    /// lying awake must not beat 8 hours of solid sleep, since the minutes asleep are the thing
    /// being ranked.
    static func longestAsleepBlock(
        in samples: [SleepSample],
        window: DateInterval,
        gapTolerance: TimeInterval = blockGapTolerance
    ) -> SleepBlock? {
        let asleep = samples.compactMap { $0.clipped(to: window) }.filter { $0.category.isAsleep }
        return blocks(of: union(of: asleep), gapTolerance: gapTolerance)
            .max { $0.asleepDuration < $1.asleepDuration }
    }

    /// Last night's minutes asleep: the longest block's, and none of the shorter ones'.
    ///
    /// `noData` is reserved for a window HealthKit said nothing about at all. A night it DID
    /// describe — in bed, or awake — is a real `value(0)`, per US-012's rule: being told nothing is
    /// not the same as being told zero, and US-027 charges a care mistake for only one of them.
    static func asleepMinutes(
        in samples: [SleepSample],
        window: DateInterval,
        gapTolerance: TimeInterval = blockGapTolerance
    ) -> HealthReading {
        let inWindow = samples.compactMap { $0.clipped(to: window) }
        guard !inWindow.isEmpty else { return .noData }
        let block = longestAsleepBlock(in: inWindow, window: window, gapTolerance: gapTolerance)
        return .value(block?.asleepMinutes ?? 0)
    }

    /// THE DE-DUPLICATION. Overlapping samples collapse into the span they jointly cover, so an
    /// hour two sources both recorded is an hour, not two. Touching samples merge as well: an
    /// asleepCore ending exactly where an asleepREM begins is one stretch of sleep, not two.
    private static func union(of samples: [SleepSample]) -> [DateInterval] {
        let sorted = samples
            .map { DateInterval(start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in sorted {
            guard let last = merged.last, interval.start <= last.end else {
                merged.append(interval)
                continue
            }
            if interval.end > last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: interval.end)
            }
            // Otherwise the interval lies wholly inside one already merged — one source repeating
            // what another already said. It adds nothing.
        }
        return merged
    }

    /// Groups already-merged, sorted stretches into blocks, breaking wherever the gap exceeds the
    /// tolerance. A block's `asleepDuration` sums the stretches only, so the awake gaps it spans
    /// are excluded from the total even though they are inside it.
    private static func blocks(of merged: [DateInterval], gapTolerance: TimeInterval) -> [SleepBlock] {
        var blocks: [SleepBlock] = []
        var start: Date?
        var end: Date?
        var asleep: TimeInterval = 0

        func close() {
            guard let start, let end else { return }
            blocks.append(SleepBlock(span: DateInterval(start: start, end: end), asleepDuration: asleep))
        }

        for interval in merged {
            if let previousEnd = end, interval.start.timeIntervalSince(previousEnd) > gapTolerance {
                close()
                start = nil
                asleep = 0
            }
            if start == nil { start = interval.start }
            end = interval.end
            asleep += interval.duration
        }
        close()
        return blocks
    }
}

/// The HealthKit read `LastNightSleepReader` needs, behind a protocol so tests drive it with
/// fixture samples — the Simulator has no health data, least of all sleep.
protocol SleepSampleFetching {
    /// Every sleep sample TOUCHING `window`, edges included. Deciding what counts is the analysis's
    /// job, not the fetcher's.
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample]
}

/// The real thing: a sample query against `HKHealthStore`.
struct HealthKitSleepFetcher: SleepSampleFetching {
    private let store = HKHealthStore()

    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthQueryError.healthDataUnavailable }

        // An overlap predicate, as in `HealthKitSampleFetcher`, and here the samples it drags in
        // from over the edges are wanted: `SleepSample.clipped(to:)` keeps the part inside the
        // window. `.strictStartDate` would throw away the first hours of a sleep that began at
        // 17:30 rather than clipping it.
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categories = samples as? [HKCategorySample] ?? []
                // A raw value this app has no case for is dropped rather than guessed at. It cannot
                // be counted as sleep without knowing that it is sleep.
                continuation.resume(returning: categories.compactMap { sample in
                    SleepCategory(rawValue: sample.value).map {
                        SleepSample(start: sample.startDate, end: sample.endDate, category: $0)
                    }
                })
            }
            store.execute(query)
        }
    }
}

/// Reads last night's sleep, in minutes, for Spirit energy.
struct LastNightSleepReader {
    private let fetcher: SleepSampleFetching
    private let calendar: Calendar

    /// - Parameter calendar: supplies the time zone that decides where the local day is, and so
    ///   when 18:00 and noon are. The app uses `.current`.
    init(fetcher: SleepSampleFetching = HealthKitSleepFetcher(), calendar: Calendar = .current) {
        self.fetcher = fetcher
        self.calendar = calendar
    }

    /// Minutes asleep in last night's longest block.
    ///
    /// A read that fails is `unavailable` rather than `noData`, per US-012: both convert to zero
    /// energy, but only one of them is the user's doing.
    func read(now: Date) async -> HealthReading {
        let window = SleepNight.window(for: now, calendar: calendar)
        do {
            let samples = try await fetcher.sleepSamples(in: window)
            return SleepAnalysis.asleepMinutes(in: samples, window: window)
        } catch {
            return .unavailable
        }
    }

    /// Last night's longest block itself. US-026 infers the Digimon's sleep window from it; energy
    /// only needs `read(now:)`.
    func readBlock(now: Date) async -> SleepBlock? {
        let window = SleepNight.window(for: now, calendar: calendar)
        guard let samples = try? await fetcher.sleepSamples(in: window) else { return nil }
        return SleepAnalysis.longestAsleepBlock(in: samples, window: window)
    }
}
