import Foundation
import HealthKit
import XCTest

@testable import DigiVPet

/// A stand-in for HealthKit that hands back its fixture samples REGARDLESS of the window asked for,
/// and records what was asked.
///
/// Ignoring the window is the point, exactly as in `HealthQueryTests`: the shipped fetcher uses an
/// overlap predicate, so HealthKit really does return sleep from outside the window. A fixture that
/// pre-filtered would test itself and let an analysis with no windowing at all pass.
private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    var samples: [SleepSample] = []
    var error: Error?

    private(set) var requestedWindows: [DateInterval] = []

    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] {
        requestedWindows.append(window)
        if let error { throw error }
        return samples
    }
}

private enum SleepFixture {
    /// Los Angeles, so the local day is nowhere near UTC's — an analysis that quietly used UTC
    /// would put 18:00 and noon in the wrong places and be caught.
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

    static func sample(_ category: SleepCategory, from: String, to: String) -> SleepSample {
        SleepSample(start: date(from), end: date(to), category: category)
    }

    /// The night of 16 -> 17 July 2026, which every test below reads.
    static let night = DateInterval(start: date("2026-07-16 18:00"), end: date("2026-07-17 12:00"))

    /// A morning inside that night's window, when a user might open the app.
    static let morningAfter = date("2026-07-17 08:00")
}

final class SleepQueryTests: XCTestCase {

    // MARK: - The window

    /// THE AC: sleep is read in the window 18:00 the previous day to 12:00 today.
    func testTheWindowRunsFromSixLastNightToNoonToday() {
        let window = SleepNight.window(for: SleepFixture.morningAfter, calendar: SleepFixture.losAngeles)

        XCTAssertEqual(window.start, SleepFixture.date("2026-07-16 18:00"))
        XCTAssertEqual(window.end, SleepFixture.date("2026-07-17 12:00"))
        XCTAssertEqual(window.duration, 18 * 3600)
    }

    /// The window is anchored to the local DAY, not to `now`, so it does not drift while the user
    /// watches: every moment of 17 July asks about the same night.
    func testTheWindowIsTheSameAllDay() {
        let atDawn = SleepNight.window(for: SleepFixture.date("2026-07-17 03:00"), calendar: SleepFixture.losAngeles)
        let atNoon = SleepNight.window(for: SleepFixture.date("2026-07-17 12:30"), calendar: SleepFixture.losAngeles)
        let lateAtNight = SleepNight.window(for: SleepFixture.date("2026-07-17 23:00"), calendar: SleepFixture.losAngeles)

        XCTAssertEqual(atDawn, SleepFixture.night)
        XCTAssertEqual(atNoon, SleepFixture.night)
        XCTAssertEqual(lateAtNight, SleepFixture.night, "sleep beginning at 22:30 tonight is not last night's")
    }

    /// Checking the app at 03:00 reads the night IN PROGRESS — the window opened at 18:00 yesterday
    /// and has not closed.
    func testAnEarlyMorningCheckSeesTheNightInProgress() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = [SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 03:00")]
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.date("2026-07-17 03:00"))

        XCTAssertEqual(reading, .value(240))
    }

    /// Pins that the TIME ZONE decides where 18:00 and noon are. The same instant sits in different
    /// local days in Los Angeles and Auckland, so each gets its own night.
    func testTheTimeZoneDecidesWhereTheNightIs() {
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!

        // 2026-07-17 08:00 in Los Angeles is already 2026-07-18 03:00 in Auckland.
        let instant = SleepFixture.date("2026-07-17 08:00")

        let here = SleepNight.window(for: instant, calendar: SleepFixture.losAngeles)
        let there = SleepNight.window(for: instant, calendar: auckland)

        XCTAssertEqual(here, SleepFixture.night)
        XCTAssertEqual(there.start, SleepFixture.date("2026-07-16 23:00"), "Auckland's 18:00, in LA terms")
        XCTAssertEqual(there.end, SleepFixture.date("2026-07-17 17:00"), "Auckland's noon, in LA terms")
        XCTAssertNotEqual(here, there)
    }

    /// The spring-forward night is 17 hours long, not 18. Building the window by adding offsets to
    /// midnight would run an hour past noon and into the afternoon it must never claim.
    func testADaylightSavingNightIsStillSixToNoon() {
        // US DST 2026 begins Sunday 8 March, at 02:00 — inside this window.
        let springForward = SleepNight.window(for: SleepFixture.date("2026-03-08 09:00"), calendar: SleepFixture.losAngeles)

        XCTAssertEqual(springForward.start, SleepFixture.date("2026-03-07 18:00"))
        XCTAssertEqual(springForward.end, SleepFixture.date("2026-03-08 12:00"))
        XCTAssertEqual(springForward.duration, 17 * 3600, "an hour of this night did not exist")
    }

    /// Consecutive nights cannot overlap, so no sample is ever counted for two of them. The
    /// afternoon between noon and 18:00 belongs to neither night, by design.
    func testConsecutiveNightsDoNotOverlap() {
        let tonight = SleepNight.window(for: SleepFixture.date("2026-07-17 08:00"), calendar: SleepFixture.losAngeles)
        let lastNight = SleepNight.window(for: SleepFixture.date("2026-07-16 08:00"), calendar: SleepFixture.losAngeles)

        XCTAssertLessThan(lastNight.end, tonight.start)
        XCTAssertNil(lastNight.intersection(with: tonight))
    }

    // MARK: - Which categories count

    /// THE AC: inBed samples are excluded from the total.
    func testInBedSamplesAreExcludedFromTheTotal() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = [
            // In bed for eight hours, reading for the first two of them.
            SleepFixture.sample(.inBed, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 01:00", to: "2026-07-17 07:00"),
        ]
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        // The six hours asleep. Counting inBed too would report 14 hours; letting inBed merge with
        // the sleep it contains would report 8.
        XCTAssertEqual(reading, .value(360))
    }

    /// `awake` is HealthKit saying the opposite of asleep. It must not pay Spirit, and it must not
    /// bridge the sleep on either side of it into extra minutes.
    func testAwakeSamplesAreExcludedFromTheTotal() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 02:00"),
            SleepFixture.sample(.awake, from: "2026-07-17 02:00", to: "2026-07-17 02:30"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 02:30", to: "2026-07-17 06:00"),
        ]

        let reading = SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night)

        // 3h + 3.5h. The half hour awake is inside the block's span but is not sleep.
        XCTAssertEqual(reading, .value(390))
    }

    /// THE AC: all four asleep categories count. A reader that knew only `asleepCore` would still
    /// look like it worked on most nights.
    func testEveryAsleepCategoryCounts() {
        let samples = [
            SleepFixture.sample(.asleepUnspecified, from: "2026-07-16 23:00", to: "2026-07-17 00:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 00:00", to: "2026-07-17 02:00"),
            SleepFixture.sample(.asleepDeep, from: "2026-07-17 02:00", to: "2026-07-17 03:00"),
            SleepFixture.sample(.asleepREM, from: "2026-07-17 03:00", to: "2026-07-17 04:00"),
        ]

        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(300))

        for category in SleepCategory.allCases {
            let one = [SleepFixture.sample(category, from: "2026-07-17 01:00", to: "2026-07-17 02:00")]
            let expected: HealthReading = category.isAsleep ? .value(60) : .value(0)
            XCTAssertEqual(SleepAnalysis.asleepMinutes(in: one, window: SleepFixture.night), expected, "\(category)")
        }
    }

    /// The raw values are HealthKit's own, asserted BY IDENTITY. A case wired to the wrong number
    /// would silently read deep sleep as time awake.
    func testSleepCategoryRawValuesAreHealthKitsOwn() {
        XCTAssertEqual(SleepCategory.inBed.rawValue, HKCategoryValueSleepAnalysis.inBed.rawValue)
        XCTAssertEqual(SleepCategory.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        XCTAssertEqual(SleepCategory.awake.rawValue, HKCategoryValueSleepAnalysis.awake.rawValue)
        XCTAssertEqual(SleepCategory.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue)
        XCTAssertEqual(SleepCategory.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
        XCTAssertEqual(SleepCategory.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue)

        XCTAssertEqual(SleepCategory(rawValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue), .asleepREM)
        XCTAssertNil(SleepCategory(rawValue: 99), "an unknown category is dropped, never guessed at")
    }

    // MARK: - De-duplication

    /// THE AC: two overlapping sources produce the UNION, not the sum.
    func testTwoOverlappingSourcesProduceTheUnionNotTheSum() {
        let samples = [
            // The watch: eight hours.
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
            // A sleep-tracking app that saw the same night, an hour off at each end.
            SleepFixture.sample(.asleepUnspecified, from: "2026-07-17 00:00", to: "2026-07-17 08:00"),
        ]

        let reading = SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night)

        // 23:00 -> 08:00 is nine hours. Summing the two sources would pay for sixteen.
        XCTAssertEqual(reading, .value(540))
    }

    /// The simplest double-count: two sources reporting the very same night.
    func testIdenticalSamplesFromTwoSourcesAreCountedOnce() {
        let watch = SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 07:00")
        let phone = SleepFixture.sample(.asleepUnspecified, from: "2026-07-16 23:00", to: "2026-07-17 07:00")

        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: [watch], window: SleepFixture.night), .value(480))
        XCTAssertEqual(
            SleepAnalysis.asleepMinutes(in: [watch, phone], window: SleepFixture.night),
            .value(480),
            "a second source saying the same thing adds no sleep"
        )
    }

    /// A sample wholly inside another's span adds nothing — and must not truncate it either. The
    /// merge has to keep the wider end, which an unconditional overwrite would lose.
    func testASampleContainedInAnotherAddsNothingAndTruncatesNothing() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
            SleepFixture.sample(.asleepDeep, from: "2026-07-17 01:00", to: "2026-07-17 02:00"),
        ]

        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(480))
    }

    /// De-duplication must not depend on the order HealthKit happens to return samples in.
    func testDeDuplicationDoesNotDependOnSampleOrder() {
        let samples = [
            SleepFixture.sample(.asleepREM, from: "2026-07-17 05:00", to: "2026-07-17 07:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 06:00"),
            SleepFixture.sample(.asleepDeep, from: "2026-07-17 02:00", to: "2026-07-17 03:00"),
        ]

        // 23:00 -> 07:00, however they arrive.
        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(480))
        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples.reversed(), window: SleepFixture.night), .value(480))
    }

    /// Consecutive stages are one stretch of sleep, not two: an asleepCore ending exactly where an
    /// asleepREM begins touches, and touching merges. This is the normal shape of a real night.
    func testTouchingStagesAreOneStretch() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 01:00"),
            SleepFixture.sample(.asleepREM, from: "2026-07-17 01:00", to: "2026-07-17 02:00"),
        ]

        let block = SleepAnalysis.longestAsleepBlock(in: samples, window: SleepFixture.night)

        XCTAssertEqual(block?.asleepMinutes, 180)
        XCTAssertEqual(block?.span, DateInterval(
            start: SleepFixture.date("2026-07-16 23:00"),
            end: SleepFixture.date("2026-07-17 02:00")
        ))
    }

    // MARK: - The longest block

    /// THE AC: the LONGEST asleep block is selected. An evening nap is in the window and is not
    /// last night's sleep — summing the window would pay for both.
    func testTheLongestBlockIsSelectedAndTheNapIsNot() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 19:00", to: "2026-07-16 20:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 10:00", to: "2026-07-17 10:30"),
        ]

        let block = SleepAnalysis.longestAsleepBlock(in: samples, window: SleepFixture.night)

        XCTAssertEqual(block?.asleepMinutes, 480, "the night, not the nap and not the lie-in")
        XCTAssertEqual(block?.span.start, SleepFixture.date("2026-07-16 23:00"))
        XCTAssertEqual(block?.span.end, SleepFixture.date("2026-07-17 07:00"))
        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(480))
    }

    /// A brief awakening must not split the night into two blocks and throw half of it away.
    func testABriefAwakeningDoesNotSplitTheNight() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 03:00"),
            SleepFixture.sample(.awake, from: "2026-07-17 03:00", to: "2026-07-17 03:05"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 03:05", to: "2026-07-17 07:00"),
        ]

        let block = SleepAnalysis.longestAsleepBlock(in: samples, window: SleepFixture.night)

        // 4h + 3h55m as one block; the five minutes awake are inside its span but are not sleep.
        XCTAssertEqual(block?.asleepMinutes, 475)
        XCTAssertEqual(block?.span.duration, 8 * 3600)
    }

    /// The other side of the tolerance: a gap longer than it really is a separate sleep.
    func testAGapLongerThanTheToleranceStartsANewBlock() {
        let samples = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 20:00", to: "2026-07-16 22:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 00:00", to: "2026-07-17 07:00"),
        ]

        // Two hours apart: two blocks, and the longer wins.
        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(420))

        // Named explicitly rather than leaning on the shipped default, so this asserts the rule and
        // not the constant: half an hour apart is one block of nine hours.
        let close = [
            SleepFixture.sample(.asleepCore, from: "2026-07-16 22:00", to: "2026-07-17 00:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 00:30", to: "2026-07-17 07:30"),
        ]
        XCTAssertEqual(
            SleepAnalysis.asleepMinutes(in: close, window: SleepFixture.night, gapTolerance: 60 * 60),
            .value(540)
        )
        XCTAssertEqual(
            SleepAnalysis.asleepMinutes(in: close, window: SleepFixture.night, gapTolerance: 10 * 60),
            .value(420),
            "a tolerance under the gap splits the same night in two"
        )
    }

    /// "Longest" means most time ASLEEP, not the widest span. A restless five hours spread over
    /// nine must not beat eight hours of solid sleep.
    func testTheLongestBlockIsTheOneWithTheMostSleepNotTheWidestSpan() {
        let samples = [
            // Restless: 19:00 -> 04:00, but only five hours of it asleep.
            SleepFixture.sample(.asleepCore, from: "2026-07-16 19:00", to: "2026-07-16 21:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-16 21:45", to: "2026-07-16 23:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-16 23:45", to: "2026-07-17 01:00"),
            SleepFixture.sample(.asleepCore, from: "2026-07-17 01:30", to: "2026-07-17 02:00"),
            // Solid: six hours, hours later.
            SleepFixture.sample(.asleepCore, from: "2026-07-17 04:00", to: "2026-07-17 10:00"),
        ]

        let block = SleepAnalysis.longestAsleepBlock(in: samples, window: SleepFixture.night)

        XCTAssertEqual(block?.asleepMinutes, 360)
        XCTAssertEqual(block?.span.start, SleepFixture.date("2026-07-17 04:00"))
        XCTAssertEqual(block?.span.duration, 6 * 3600, "the restless block's span is longer, at 7 hours")
    }

    // MARK: - Windowing the samples

    /// Sleep that began before 18:00 is CLIPPED to the window, not discarded. Nothing else would
    /// claim it: last night's window closed at noon.
    func testSleepStartingBeforeTheWindowIsClippedToIt() {
        let samples = [SleepFixture.sample(.asleepCore, from: "2026-07-16 17:30", to: "2026-07-17 01:30")]

        // 18:00 -> 01:30, so seven and a half of the eight hours.
        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(450))
    }

    /// And the same at the far edge: a lie-in past noon counts up to noon.
    func testSleepRunningPastTheWindowIsClippedToIt() {
        let samples = [SleepFixture.sample(.asleepCore, from: "2026-07-17 09:00", to: "2026-07-17 14:00")]

        XCTAssertEqual(SleepAnalysis.asleepMinutes(in: samples, window: SleepFixture.night), .value(180))
    }

    /// The afternoon nap belongs to no night at all — it is after last night's noon and before
    /// tonight's 18:00. A window that reached back a flat 24 hours would pay Spirit for it.
    func testAnAfternoonNapIsNotLastNightsSleep() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = [SleepFixture.sample(.asleepCore, from: "2026-07-16 14:00", to: "2026-07-16 15:30")]
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(reading, .noData, "the fetcher offered it; the window rejected it")
    }

    // MARK: - No data versus a real zero

    /// Nothing recorded at all is `noData` — the app was told nothing. US-027 must be able to tell
    /// that from a night the user genuinely did not sleep.
    func testNoSleepSamplesIsNoDataNotZero() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = []
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(reading, .noData)
        XCTAssertNotEqual(reading, .value(0), "being told nothing is not being told zero")
        XCTAssertFalse(reading.hasData)
        XCTAssertEqual(reading.energyValue, 0, "but it still converts to zero energy")
    }

    /// The other half: a night HealthKit DID describe, in which no sleep happened, is a real zero.
    /// Lying in bed awake all night is data.
    func testInBedButNeverAsleepIsARealZero() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = [
            SleepFixture.sample(.inBed, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
            SleepFixture.sample(.awake, from: "2026-07-16 23:00", to: "2026-07-17 07:00"),
        ]
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(reading, .value(0))
        XCTAssertTrue(reading.hasData)
        XCTAssertNil(SleepAnalysis.longestAsleepBlock(in: fetcher.samples, window: SleepFixture.night))
    }

    // MARK: - Failure

    /// A failed read is `unavailable`, not `noData`, per US-012: both read zero energy, but only
    /// one of them is the user's doing.
    func testAFailedReadIsUnavailableRatherThanNoData() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.error = HealthQueryError.healthDataUnavailable
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(reading, .unavailable)
        XCTAssertEqual(reading.energyValue, 0, "it must read zero rather than erroring")
    }

    // MARK: - What is read

    /// THE AC: sleepAnalysis is what gets queried, over last night's window. The type is asserted
    /// against the one authorization asked for, so sleep cannot be authorized as one type and read
    /// as another.
    func testReadsSleepAnalysisOverLastNightsWindow() async {
        let fetcher = FixtureSleepFetcher()
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        _ = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(fetcher.requestedWindows, [SleepFixture.night])
        XCTAssertEqual(HealthMetric.sleep.objectType, HKCategoryType(.sleepAnalysis))
        XCTAssertEqual(HealthMetric.sleep.energyType, .spirit)
    }

    /// Minutes are the unit US-014's rate is written against — 1 Spirit per 15 minutes asleep.
    /// Returning seconds would inflate Spirit 60-fold and still look like a working query.
    func testTheReadingIsInMinutes() async {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = [SleepFixture.sample(.asleepCore, from: "2026-07-16 23:00", to: "2026-07-17 07:00")]
        let reader = LastNightSleepReader(fetcher: fetcher, calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: SleepFixture.morningAfter)

        XCTAssertEqual(reading, .value(480), "eight hours is 480 minutes")
    }

    // MARK: - The real fetcher

    /// Everything above drives a fixture, which cannot catch `HealthKitSleepFetcher` itself being
    /// mis-plumbed. This is the one test that runs a real `HKSampleQuery` for sleep.
    ///
    /// The Simulator has no sleep data and this container has not been granted access, so what
    /// comes back is empty or an error — either is fine, and asserting which would be flaky. What
    /// it proves is that the real query RESUMES its continuation: a query that resumes on no path,
    /// or twice, is a hang or a crash no fixture would ever show.
    func testRealFetcherAnswersWithoutHanging() async {
        let reader = LastNightSleepReader(fetcher: HealthKitSleepFetcher(), calendar: SleepFixture.losAngeles)

        let reading = await reader.read(now: Date())

        XCTAssertEqual(reading.energyValue, 0, "no seeded sleep data in the Simulator")
        XCTAssertFalse(reading.hasData)
    }
}
