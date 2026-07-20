import Foundation
import HealthKit
import XCTest

@testable import DigiVPet

/// A stand-in for HealthKit that hands back its fixture samples REGARDLESS of the interval asked
/// for, and records what was asked.
///
/// Ignoring the interval is the point, as in `HealthQueryTests`: the shipped fetcher uses an
/// overlap predicate, so HealthKit really does return samples from outside the window. A fixture
/// that pre-filtered would test itself and let a reader with no filter at all pass.
private final class FixtureMetricFetcher: HealthMetricSampleFetching, @unchecked Sendable {
    var samples: [ConditionMetric: [HealthSample]] = [:]
    var errors: [ConditionMetric: Error] = [:]

    private(set) var requestedIntervals: [ConditionMetric: DateInterval] = [:]

    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample] {
        requestedIntervals[metric.metric] = interval
        if let error = errors[metric.metric] { throw error }
        return samples[metric.metric] ?? []
    }
}

private enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static func sample(at start: String, value: Double, minutes: Double = 10) -> HealthSample {
        let from = date(start)
        return HealthSample(start: from, end: from.addingTimeInterval(minutes * 60), value: value)
    }

    /// A three-day window, wide enough that "over a stage" is not secretly "over a day".
    static let window = DateInterval(start: date("2026-07-18 00:00"), end: date("2026-07-21 00:00"))

    static func reader(_ fetcher: FixtureMetricFetcher) -> HealthMetricReader {
        HealthMetricReader(fetcher: fetcher)
    }

    static func readable(_ metric: ConditionMetric) -> ReadableHealthMetric {
        guard let readable = ReadableHealthMetric(metric) else {
            preconditionFailure("\(metric.rawValue) is not readable")
        }
        return readable
    }
}

final class HealthMetricReaderTests: XCTestCase {

    // MARK: - Quantity totals

    /// THE AC: a quantity metric is TOTALLED over the injected window.
    func testQuantityMetricIsTotalledOverTheWindow() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthFlightsClimbed] = [
            Fixture.sample(at: "2026-07-18 09:00", value: 3),
            Fixture.sample(at: "2026-07-19 18:30", value: 5),
            Fixture.sample(at: "2026-07-20 07:15", value: 4)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthFlightsClimbed), in: Fixture.window)

        XCTAssertEqual(reading, .value(12))
    }

    /// The window is honoured, not just carried: samples outside it are dropped, and the fetcher is
    /// handed exactly the interval that was asked for.
    func testSamplesOutsideTheWindowAreNotCounted() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthSteps] = [
            Fixture.sample(at: "2026-07-17 23:59", value: 1_000),   // the day before — out
            Fixture.sample(at: "2026-07-18 00:00", value: 2_000),   // exactly the start — in
            Fixture.sample(at: "2026-07-20 12:00", value: 500),     // inside — in
            Fixture.sample(at: "2026-07-21 00:00", value: 9_000)    // exactly the end — OUT, [start, end)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthSteps), in: Fixture.window)

        XCTAssertEqual(reading, .value(2_500))
        XCTAssertEqual(fetcher.requestedIntervals[.healthSteps], Fixture.window)
    }

    /// A discrete quantity is AVERAGED. Totalling a resting heart rate over three days would report
    /// a number in the hundreds and satisfy any criterion ever written against it.
    func testDiscreteQuantityMetricIsAveragedRatherThanTotalled() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthRestingHeartRate] = [
            Fixture.sample(at: "2026-07-18 06:00", value: 58),
            Fixture.sample(at: "2026-07-19 06:00", value: 62),
            Fixture.sample(at: "2026-07-20 06:00", value: 60)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthRestingHeartRate), in: Fixture.window)

        XCTAssertEqual(reading, .value(60))
    }

    // MARK: - Category metrics

    /// THE AC: a category metric counts EVENTS. Every value here is
    /// `HKCategoryValueNotApplicable` (0), so a reader that summed values would report 0.
    func testCategoryMetricCountsEventsRatherThanSummingValues() async {
        let notApplicable = Double(HKCategoryValue.notApplicable.rawValue)
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthHandwashing] = [
            Fixture.sample(at: "2026-07-18 08:00", value: notApplicable),
            Fixture.sample(at: "2026-07-18 13:00", value: notApplicable),
            Fixture.sample(at: "2026-07-19 19:00", value: notApplicable)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthHandwashing), in: Fixture.window)

        XCTAssertEqual(reading, .value(3))
        XCTAssertNotEqual(reading, .value(0), "summing category values would give zero here")
    }

    /// THE AC: `.appleStandHour` counts only `stood`. HealthKit records an entry for EVERY hour,
    /// idle ones included, so a plain event count would report a motionless day as a perfect one.
    func testStandHoursCountOnlyStoodSamples() async {
        let stood = Double(HKCategoryValueAppleStandHour.stood.rawValue)
        let idle = Double(HKCategoryValueAppleStandHour.idle.rawValue)
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthStandHours] = [
            Fixture.sample(at: "2026-07-18 09:00", value: stood, minutes: 60),
            Fixture.sample(at: "2026-07-18 10:00", value: idle, minutes: 60),
            Fixture.sample(at: "2026-07-18 11:00", value: idle, minutes: 60),
            Fixture.sample(at: "2026-07-19 14:00", value: stood, minutes: 60)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthStandHours), in: Fixture.window)

        XCTAssertEqual(reading, .value(2), "4 samples, 2 of them stood")
    }

    /// A day HealthKit described, in which the user never stood, is a real zero — not `noData`.
    /// US-027's distinction: being told nothing is not being told zero.
    func testAnAllIdleWindowIsARealZeroRatherThanNoData() async {
        let idle = Double(HKCategoryValueAppleStandHour.idle.rawValue)
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthStandHours] = [
            Fixture.sample(at: "2026-07-18 09:00", value: idle, minutes: 60),
            Fixture.sample(at: "2026-07-18 10:00", value: idle, minutes: 60)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthStandHours), in: Fixture.window)

        XCTAssertEqual(reading, .value(0))
    }

    /// `health.mindfulMinutes` is named for the span, not the count: two 20-minute sessions are 40
    /// minutes, not 2.
    func testMindfulMinutesTotalsDurationsRatherThanCountingSessions() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthMindfulMinutes] = [
            Fixture.sample(at: "2026-07-18 07:00", value: 0, minutes: 20),
            Fixture.sample(at: "2026-07-19 07:00", value: 0, minutes: 20)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthMindfulMinutes), in: Fixture.window)

        XCTAssertEqual(reading, .value(40))
    }

    /// Workouts are counted, one `HKWorkout` being one workout.
    func testWorkoutsAreCounted() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthWorkouts] = [
            Fixture.sample(at: "2026-07-18 17:00", value: 1, minutes: 45),
            Fixture.sample(at: "2026-07-20 17:00", value: 1, minutes: 30)
        ]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthWorkouts), in: Fixture.window)

        XCTAssertEqual(reading, .value(2))
    }

    // MARK: - Nothing there, and nothing working

    /// THE AC: an empty window is `noData`.
    func testEmptyWindowIsNoData() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthSteps] = []

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthSteps), in: Fixture.window)

        XCTAssertEqual(reading, .noData)
    }

    /// Samples exist, but all of them fall outside the window — still `noData`, since this window
    /// was told nothing.
    func testWindowWithNoBelongingSamplesIsNoData() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.samples[.healthSteps] = [Fixture.sample(at: "2026-07-25 09:00", value: 4_000)]

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthSteps), in: Fixture.window)

        XCTAssertEqual(reading, .noData)
    }

    /// THE AC: a failing or unauthorized read is `unavailable` and never throws, matching
    /// `TodayHealthReader.read`.
    func testFailingReadIsUnavailableAndDoesNotThrow() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.errors[.healthSteps] = HealthQueryError.healthDataUnavailable

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthSteps), in: Fixture.window)

        XCTAssertEqual(reading, .unavailable)
    }

    /// The unauthorized case specifically: HealthKit's own `authorizationNotDetermined`, which
    /// US-055 observed for all 23 not-yet-granted types.
    func testUnauthorizedReadIsUnavailable() async {
        let fetcher = FixtureMetricFetcher()
        fetcher.errors[.healthVO2Max] = NSError(
            domain: HKErrorDomain,
            code: HKError.errorAuthorizationNotDetermined.rawValue)

        let reading = await Fixture.reader(fetcher)
            .read(Fixture.readable(.healthVO2Max), in: Fixture.window)

        XCTAssertEqual(reading, .unavailable)
    }

    // MARK: - The vocabulary this reader covers

    /// Every `health.*` metric except sleep is readable, and no `care.*` one is.
    func testEveryHealthMetricExceptSleepIsReadableAndNoCareMetricIs() {
        for metric in ConditionMetric.allCases {
            let readable = ReadableHealthMetric(metric)
            if metric == .healthSleep {
                XCTAssertNil(readable, "sleep belongs to SleepAnalysis, not here")
            } else if metric.isHealthMetric {
                XCTAssertNotNil(readable, "\(metric.rawValue) has no source")
            } else {
                XCTAssertNil(readable, "\(metric.rawValue) is a game counter, not a HealthKit read")
            }
        }
    }

    /// THE CRASH THIS PREVENTS: `HKQuantity.doubleValue(for:)` raises an Objective-C exception on a
    /// unit the type does not support, and no fixture test could catch it — fixtures carry a
    /// `Double`, never an `HKQuantity`. `is(compatibleWith:)` answers it without any samples.
    func testEveryQuantityMetricsUnitIsCompatibleWithItsType() {
        for readable in ReadableHealthMetric.all {
            let unit: HKUnit
            switch readable.aggregation {
            case .sumQuantity(let quantityUnit), .averageQuantity(let quantityUnit):
                unit = quantityUnit
            case .countEvents, .countStoodHours, .sumDurationMinutes:
                continue
            }
            guard let quantityType = readable.sampleType as? HKQuantityType else {
                XCTFail("\(readable.metric.rawValue) aggregates a quantity but is not a quantity type")
                continue
            }
            XCTAssertTrue(
                quantityType.is(compatibleWith: unit),
                "\(readable.metric.rawValue): \(unit) is not a valid unit for \(quantityType.identifier)")
        }
    }

    /// A category or workout metric must never be given a quantity aggregation — the mirror of the
    /// test above, so the two together pin every entry in the table to the right family.
    func testEveryCountedMetricIsACategoryOrWorkoutType() {
        for readable in ReadableHealthMetric.all {
            switch readable.aggregation {
            case .sumQuantity, .averageQuantity:
                continue
            case .countEvents, .countStoodHours, .sumDurationMinutes:
                let isCategory = readable.sampleType is HKCategoryType
                let isWorkout = readable.sampleType is HKWorkoutType
                XCTAssertTrue(
                    isCategory || isWorkout,
                    "\(readable.metric.rawValue) is counted but is a \(type(of: readable.sampleType))")
            }
        }
    }

    /// The `ConditionMetric` convenience returns nil rather than a number for what it cannot read,
    /// so a caller holding an authored metric cannot mistake sleep for zero.
    func testConditionMetricConvenienceReturnsNilForUnreadableMetrics() async {
        let reader = Fixture.reader(FixtureMetricFetcher())

        let sleep = await reader.read(ConditionMetric.healthSleep, in: Fixture.window)
        let training = await reader.read(ConditionMetric.careTrainingSessions, in: Fixture.window)
        let steps = await reader.read(ConditionMetric.healthSteps, in: Fixture.window)

        XCTAssertNil(sleep)
        XCTAssertNil(training)
        XCTAssertEqual(steps, .noData, "readable, but the fixture has no samples")
    }
}
