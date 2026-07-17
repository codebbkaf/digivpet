import Foundation
import HealthKit
import XCTest

@testable import DigiVPet

/// A stand-in for HealthKit that hands back its fixture samples REGARDLESS of the interval asked
/// for, and records what was asked.
///
/// Ignoring the interval is the point. The shipped fetcher uses an overlap predicate, so HealthKit
/// really does return samples from outside the day — a fixture that pre-filtered would test itself
/// and let a reader with no filter at all pass.
private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]
    var errors: [QuantityMetric: Error] = [:]

    private(set) var requestedIntervals: [QuantityMetric: DateInterval] = [:]
    private(set) var fetchCount = 0

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        fetchCount += 1
        requestedIntervals[metric] = interval
        if let error = errors[metric] { throw error }
        return samples[metric] ?? []
    }
}

private enum Fixture {
    /// Los Angeles, so the day boundary is nowhere near UTC midnight — a reader that quietly used
    /// UTC would put the evening samples on the wrong day and be caught.
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String, in calendar: Calendar = losAngeles) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    /// A sample of `value`, spanning ten minutes from `start`.
    static func sample(at start: String, value: Double, minutes: Double = 10) -> HealthSample {
        let from = date(start)
        return HealthSample(start: from, end: from.addingTimeInterval(minutes * 60), value: value)
    }
}

final class HealthQueryTests: XCTestCase {

    // MARK: - Today's window

    /// THE AC: today runs from LOCAL-timezone midnight.
    func testTodayStartsAtLocalMidnightAndEndsAtTheNext() {
        let interval = HealthDay.interval(
            containing: Fixture.date("2026-07-17 14:30"),
            calendar: Fixture.losAngeles
        )

        XCTAssertEqual(interval.start, Fixture.date("2026-07-17 00:00"))
        XCTAssertEqual(interval.end, Fixture.date("2026-07-18 00:00"))
    }

    /// Pins that the time zone is what decides the day, not UTC. The SAME instant is a different
    /// day in Los Angeles and in Auckland, and each must get its own local midnight.
    func testTheTimeZoneDecidesWhereTheDayStarts() {
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!

        // 2026-07-17 20:00 in Los Angeles is already 2026-07-18 15:00 in Auckland.
        let instant = Fixture.date("2026-07-17 20:00")

        let here = HealthDay.interval(containing: instant, calendar: Fixture.losAngeles)
        let there = HealthDay.interval(containing: instant, calendar: auckland)

        XCTAssertEqual(here.start, Fixture.date("2026-07-17 00:00"))
        XCTAssertEqual(there.start, Fixture.date("2026-07-17 05:00"), "Auckland's midnight, in LA terms")
        XCTAssertNotEqual(here.start, there.start)
    }

    /// The spring-forward day is 23 hours long. A window built as `midnight + 86400` would run an
    /// hour into the next day and steal its first samples; calendar arithmetic does not.
    func testADaylightSavingDayIsStillExactlyOneDay() {
        // US DST 2026 begins Sunday 8 March.
        let springForward = HealthDay.interval(
            containing: Fixture.date("2026-03-08 12:00"),
            calendar: Fixture.losAngeles
        )
        XCTAssertEqual(springForward.duration, 23 * 3600, "spring forward is a 23-hour day")
        XCTAssertEqual(springForward.end, Fixture.date("2026-03-09 00:00"))

        // And back again in November.
        let fallBack = HealthDay.interval(
            containing: Fixture.date("2026-11-01 12:00"),
            calendar: Fixture.losAngeles
        )
        XCTAssertEqual(fallBack.duration, 25 * 3600, "fall back is a 25-hour day")
        XCTAssertEqual(fallBack.end, Fixture.date("2026-11-02 00:00"))
    }

    // MARK: - Totalling

    /// THE AC: only today's samples are summed and yesterday's are excluded.
    func testOnlyTodaysSamplesAreSummedAndYesterdaysAreExcluded() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.samples[.steps] = [
            Fixture.sample(at: "2026-07-16 08:00", value: 900),   // yesterday morning
            Fixture.sample(at: "2026-07-16 23:50", value: 90),    // yesterday, right up against midnight
            Fixture.sample(at: "2026-07-17 07:15", value: 500),   // today
            Fixture.sample(at: "2026-07-17 18:40", value: 250),   // today
            Fixture.sample(at: "2026-07-18 00:10", value: 700),   // tomorrow
        ]
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let reading = await reader.read(.steps, now: Fixture.date("2026-07-17 20:00"))

        // 500 + 250, and none of the 1,690 steps from the neighbouring days.
        XCTAssertEqual(reading, .value(750))
    }

    /// A sample that straddles midnight belongs wholly to the day it STARTED in — counted once,
    /// never split, never counted in both days.
    func testASampleStraddlingMidnightBelongsToTheDayItStartedIn() {
        let straddler = Fixture.sample(at: "2026-07-16 23:50", value: 200, minutes: 20)
        let yesterday = HealthDay.interval(containing: Fixture.date("2026-07-16 12:00"), calendar: Fixture.losAngeles)
        let today = HealthDay.interval(containing: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(HealthReading.total(of: [straddler], in: yesterday), .value(200))
        XCTAssertEqual(HealthReading.total(of: [straddler], in: today), .noData)
    }

    /// The bounds are half-open: midnight opens today, the next midnight opens tomorrow. If the
    /// interval were treated as closed at both ends (as `DateInterval.contains` is), the second
    /// sample here would be counted on both days.
    func testTheDayBoundaryIsHalfOpen() {
        let today = HealthDay.interval(containing: Fixture.date("2026-07-17 12:00"), calendar: Fixture.losAngeles)
        let atMidnight = Fixture.sample(at: "2026-07-17 00:00", value: 5)
        let atNextMidnight = Fixture.sample(at: "2026-07-18 00:00", value: 7)

        XCTAssertEqual(HealthReading.total(of: [atMidnight], in: today), .value(5), "midnight belongs to today")
        XCTAssertEqual(HealthReading.total(of: [atNextMidnight], in: today), .noData, "the next midnight does not")
    }

    // MARK: - No data versus a real zero

    /// THE AC: each value exposes a "no data" state distinct from a real zero.
    func testNoSamplesIsNoDataAndNotZero() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.samples[.steps] = []
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let reading = await reader.read(.steps, now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(reading, .noData)
        XCTAssertNotEqual(reading, .value(0), "being told nothing is not being told zero")
        XCTAssertFalse(reading.hasData)
        XCTAssertEqual(reading.energyValue, 0, "but it still converts to zero energy")
    }

    /// The other half of the distinction: samples that really do sum to zero are a VALUE, not
    /// silence. US-027 leans on this to tell a lazy day from a day HealthKit said nothing.
    func testSamplesSummingToZeroAreARealZero() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.samples[.activeEnergy] = [Fixture.sample(at: "2026-07-17 09:00", value: 0)]
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let reading = await reader.read(.activeEnergy, now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(reading, .value(0))
        XCTAssertTrue(reading.hasData)
        XCTAssertNotEqual(reading, .noData)
    }

    /// Yesterday's samples must not rescue today from being silent — filtering happens first, and
    /// only then is emptiness judged.
    func testADayWithOnlyYesterdaysSamplesIsNoData() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.samples[.steps] = [Fixture.sample(at: "2026-07-16 08:00", value: 900)]
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let reading = await reader.read(.steps, now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(reading, .noData)
    }

    // MARK: - Failure

    /// A failed read is `unavailable`, not `noData`. Both read zero energy, but only one of them
    /// is the user's doing, and US-027 charges a care mistake for the other.
    func testAFailedReadIsUnavailableRatherThanNoData() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.errors[.steps] = HealthQueryError.healthDataUnavailable
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let reading = await reader.read(.steps, now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(reading, .unavailable)
        XCTAssertEqual(reading.energyValue, 0, "it must read zero rather than erroring")
    }

    /// THE PARTIAL-AUTHORIZATION RULE from US-011, now against real reads: one denied or broken
    /// metric costs its own energy type and nothing else.
    func testOneFailingMetricDoesNotDisturbTheOthers() async {
        let fetcher = FixtureSampleFetcher()
        fetcher.errors[.activeEnergy] = HealthQueryError.healthDataUnavailable
        fetcher.samples[.steps] = [Fixture.sample(at: "2026-07-17 07:15", value: 4_000)]
        fetcher.samples[.exercise] = [Fixture.sample(at: "2026-07-17 07:15", value: 30)]
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let readings = await reader.readToday(now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(readings[.activeEnergy], .unavailable)
        XCTAssertEqual(readings[.steps], .value(4_000))
        XCTAssertEqual(readings[.exercise], .value(30))
    }

    // MARK: - What is read

    /// THE AC: stepCount, activeEnergyBurned and appleExerciseTime are what gets queried, each
    /// over today's window. Asserts the HealthKit types BY IDENTITY — a metric wired to the wrong
    /// type would still count three.
    func testReadsTheThreeMetricsOverTodaysWindow() async {
        let fetcher = FixtureSampleFetcher()
        let reader = TodayHealthReader(fetcher: fetcher, calendar: Fixture.losAngeles)

        let readings = await reader.readToday(now: Fixture.date("2026-07-17 20:00"))

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(fetcher.fetchCount, 3)
        let today = DateInterval(start: Fixture.date("2026-07-17 00:00"), end: Fixture.date("2026-07-18 00:00"))
        for metric in QuantityMetric.allCases {
            XCTAssertEqual(fetcher.requestedIntervals[metric], today, "\(metric) was not read over today")
        }

        XCTAssertEqual(QuantityMetric.steps.quantityType, HKQuantityType(.stepCount))
        XCTAssertEqual(QuantityMetric.activeEnergy.quantityType, HKQuantityType(.activeEnergyBurned))
        XCTAssertEqual(QuantityMetric.exercise.quantityType, HKQuantityType(.appleExerciseTime))
    }

    /// The units US-014's conversion rates are written against: 1 Strength per 100 STEPS, 1
    /// Vitality per 20 active KCAL, 1 Stamina per 2 exercise MINUTES. Reading exercise in seconds
    /// would inflate Stamina 60-fold and still look like a working query.
    func testEachMetricIsReadInTheUnitTheEnergyRatesAssume() {
        XCTAssertEqual(QuantityMetric.steps.unit, .count())
        XCTAssertEqual(QuantityMetric.activeEnergy.unit, .kilocalorie())
        XCTAssertEqual(QuantityMetric.exercise.unit, .minute())
    }

    /// `QuantityMetric` restates types that `HealthMetric` also names. Pin them together, so a
    /// metric cannot be authorized as one type and then read as another.
    func testQuantityMetricsAgreeWithTheMetricsAuthorizationAsksFor() {
        for metric in QuantityMetric.allCases {
            XCTAssertEqual(metric.quantityType, metric.metric.objectType, "\(metric) reads a type it never asked for")
            XCTAssertEqual(metric.energyType, metric.metric.energyType)
            XCTAssertTrue(HealthMetric.allCases.contains(metric.metric))
        }
    }

    /// Sleep is US-013's, with a different window and de-duplication. It must not be readable as a
    /// from-midnight quantity — the type system is what keeps that question from compiling, and
    /// this pins that no one has quietly added it.
    func testSleepIsNotAMetricThisReaderCanBeAskedFor() {
        XCTAssertEqual(QuantityMetric.allCases.count, 3)
        XCTAssertFalse(QuantityMetric.allCases.map(\.metric).contains(.sleep))
        XCTAssertFalse(QuantityMetric.allCases.map(\.energyType).contains(.spirit))
    }

    // MARK: - The real fetcher

    /// Everything above drives a fixture, which cannot catch `HealthKitSampleFetcher` itself being
    /// mis-plumbed. This is the one test that runs a real `HKSampleQuery`.
    ///
    /// The Simulator has no health data and this container has not been granted access, so what
    /// comes back is empty or an error — either is fine and asserting which would be flaky. What
    /// it proves is that the real query RESUMES its continuation: a query that resumes on no path,
    /// or twice, is a hang or a crash that no fixture would ever show.
    func testRealFetcherAnswersWithoutHanging() async {
        let reader = TodayHealthReader(fetcher: HealthKitSampleFetcher(), calendar: Fixture.losAngeles)

        let reading = await reader.read(.steps, now: Date())

        XCTAssertEqual(reading.energyValue, 0, "no seeded health data in the Simulator")
        XCTAssertFalse(reading.hasData)
    }
}
