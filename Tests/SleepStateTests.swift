import Foundation
import XCTest

@testable import DigiVPet

/// Hands back its fixture samples regardless of the window asked for, as `SleepQueryTests`'
/// fetcher does and for the same reason: the shipped fetcher's predicate really does return sleep
/// from outside the window, so a fixture that pre-filtered would be testing itself.
private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    var samples: [SleepSample] = []
    var error: Error?

    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] {
        if let error { throw error }
        return samples
    }
}

/// No steps, calories or exercise minutes — this file is about sleep, and the other three metrics
/// would only add energy that could evolve the fixture mid-test.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private enum SleepClock {
    /// Los Angeles, well away from UTC, so a window computed in the wrong time zone is caught
    /// rather than passing by coincidence.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func at(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("Unparseable fixture date '\(iso)'")
        }
        return date
    }

    /// One ordinary night, 23:30 to 06:15 — long enough to be a habit, and NOT the fallback's
    /// 22:00-07:00, so every assertion below can tell the inferred window from the default one.
    static let night = SleepSample(start: at("2026-03-10 23:30"), end: at("2026-03-11 06:15"),
                                   category: .asleepCore)
}

// MARK: - AC1/AC2/AC4: the window itself

final class SleepScheduleTests: XCTestCase {
    private let calendar = SleepClock.calendar

    /// AC4 on the fallback window: inside is inside, outside is outside, and the two ends behave
    /// asymmetrically on purpose — bedtime inclusive, waking exclusive.
    func testTheFallbackWindowIsTenPmToSeven() {
        let schedule = SleepSchedule.fallback
        XCTAssertEqual(schedule.bedtimeMinute, 22 * 60)
        XCTAssertEqual(schedule.wakeMinute, 7 * 60)

        for asleep in ["2026-03-10 22:00", "2026-03-10 23:59", "2026-03-11 00:00",
                       "2026-03-11 03:14", "2026-03-11 06:59"] {
            XCTAssertTrue(schedule.contains(SleepClock.at(asleep), calendar: calendar),
                          "\(asleep) is inside 22:00-07:00")
        }
        for awake in ["2026-03-11 07:00", "2026-03-11 12:00", "2026-03-11 18:30",
                      "2026-03-11 21:59"] {
            XCTAssertFalse(schedule.contains(SleepClock.at(awake), calendar: calendar),
                           "\(awake) is outside 22:00-07:00")
        }
    }

    /// AC1: the window follows the user's actual hours rather than the default's.
    func testAWindowIsInferredFromTheNightsSpan() throws {
        let block = SleepBlock(
            span: DateInterval(start: SleepClock.at("2026-03-10 23:30"),
                               end: SleepClock.at("2026-03-11 06:15")),
            asleepDuration: 6.75 * 3600)
        let schedule = try XCTUnwrap(SleepSchedule(inferredFrom: block, calendar: calendar))

        XCTAssertEqual(schedule.bedtimeMinute, 23 * 60 + 30)
        XCTAssertEqual(schedule.wakeMinute, 6 * 60 + 15)
        XCTAssertTrue(schedule.wrapsMidnight)

        XCTAssertTrue(schedule.contains(SleepClock.at("2026-03-11 02:00"), calendar: calendar))
        // 22:30 and 06:30 are the proof this is the INFERRED window and not the fallback: the
        // fallback answers the opposite way at both of them.
        XCTAssertFalse(schedule.contains(SleepClock.at("2026-03-11 22:30"), calendar: calendar),
                       "this user is not in bed yet at 22:30, though the fallback would be")
        XCTAssertFalse(schedule.contains(SleepClock.at("2026-03-11 06:30"), calendar: calendar),
                       "already up at 06:30, though the fallback would still be asleep")
    }

    /// The span is used, not the asleep duration: an awakening in the middle must not wake the
    /// Digimon up alongside the user rolling over.
    func testTheWindowSpansTheWholeNightIncludingItsAwakenings() throws {
        let block = SleepBlock(
            span: DateInterval(start: SleepClock.at("2026-03-10 23:00"),
                               end: SleepClock.at("2026-03-11 07:00")),
            // Eight hours of span, seven of it asleep — an hour of it awake, somewhere inside.
            asleepDuration: 7 * 3600)
        let schedule = try XCTUnwrap(SleepSchedule(inferredFrom: block, calendar: calendar))

        XCTAssertEqual(schedule.wakeMinute, 7 * 60, "the span's end, not an hour earlier")
        XCTAssertTrue(schedule.contains(SleepClock.at("2026-03-11 03:30"), calendar: calendar))
    }

    /// A night-shift sleeper's window lies inside one calendar day, so it must NOT be read as
    /// wrapping midnight — that would invert it and put them asleep all day.
    func testADaytimeWindowDoesNotWrapMidnight() throws {
        let block = SleepBlock(
            span: DateInterval(start: SleepClock.at("2026-03-11 02:00"),
                               end: SleepClock.at("2026-03-11 10:00")),
            asleepDuration: 8 * 3600)
        let schedule = try XCTUnwrap(SleepSchedule(inferredFrom: block, calendar: calendar))

        XCTAssertFalse(schedule.wrapsMidnight)
        XCTAssertTrue(schedule.contains(SleepClock.at("2026-03-11 06:00"), calendar: calendar))
        XCTAssertFalse(schedule.contains(SleepClock.at("2026-03-11 23:00"), calendar: calendar))
        XCTAssertFalse(schedule.contains(SleepClock.at("2026-03-11 01:00"), calendar: calendar))
    }

    /// A nap is not a habit. Its hours must not become the window, or a 20:15 doze would put the
    /// Digimon to bed at 20:15 every night.
    func testANapIsTooShortToBecomeTheWindow() {
        let nap = SleepBlock(
            span: DateInterval(start: SleepClock.at("2026-03-10 20:15"),
                               end: SleepClock.at("2026-03-10 20:55")),
            asleepDuration: 40 * 60)
        XCTAssertNil(SleepSchedule(inferredFrom: nap, calendar: calendar))
    }

    func testExactlyTheMinimumIsLongEnough() {
        let block = SleepBlock(
            span: DateInterval(start: SleepClock.at("2026-03-11 01:00"),
                               end: SleepClock.at("2026-03-11 04:00")),
            asleepDuration: SleepSchedule.minimumInferableSleep)
        XCTAssertNotNil(SleepSchedule(inferredFrom: block, calendar: calendar))
    }

    /// AC1: the frames the sleep loop draws, asserted by NUMBER as well as by name — the numbers
    /// are what the sheet layout pins down, and a mis-numbered case would draw the wrong art and
    /// still read fine here.
    func testTheSleepLoopIsFramesFourAndFive() {
        XCTAssertEqual(SpriteAnimation.sleep.stageFrames, [.sleep1, .sleep2])
        XCTAssertEqual(SpriteFrame.sleep1.rawValue, 4)
        XCTAssertEqual(SpriteFrame.sleep2.rawValue, 5)
        XCTAssertNotEqual(SpriteAnimation.sleep.stageFrames, SpriteAnimation.idle.stageFrames,
                          "a sleeping Digimon must not be drawing the walk loop")
    }
}

// MARK: - AC1/AC2/AC3/AC4 through the model

@MainActor
final class SleepStateTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SleepStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// A Baby I with no outgoing edges, so the Spirit energy last night's sleep credits cannot
    /// evolve the fixture out from under the assertions. Same shape as `FeedApplyTests`'.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    /// A started model reading a saved game at "hero", with `samples` as the user's sleep history
    /// and the clock pinned at `now`.
    private func startedModel(named name: String, now: Date, samples: [SleepSample],
                             error: Error? = nil, vitality: Int = 0, strength: Int = 0)
        async throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("\(name).store")
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.hunger = 3
        state.stageEnergy[.vitality] = vitality
        state.stageEnergy[.strength] = strength
        try seeding.save()

        let fetcher = FixtureSleepFetcher()
        fetcher.samples = samples
        fetcher.error = error

        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: SleepClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: fetcher, calendar: SleepClock.calendar)
            ),
            calendar: SleepClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }

    // MARK: AC4 — true inside the inferred window, false outside it

    /// The same night of sleep read at three different hours. The window inferred from it is
    /// 23:30-06:15, so 22:00 — which the FALLBACK would call bedtime — must come back awake.
    func testIsAsleepIsTrueInsideTheInferredWindowAndFalseOutside() async throws {
        let inside = try await startedModel(named: "inside", now: SleepClock.at("2026-03-11 01:00"),
                                            samples: [SleepClock.night])
        XCTAssertTrue(inside.isAsleep)
        XCTAssertEqual(inside.sleepSchedule.bedtimeMinute, 23 * 60 + 30,
                       "inferred from the history, not the 22:00 fallback")

        let morning = try await startedModel(named: "morning", now: SleepClock.at("2026-03-11 09:00"),
                                             samples: [SleepClock.night])
        XCTAssertFalse(morning.isAsleep)

        let evening = try await startedModel(named: "evening", now: SleepClock.at("2026-03-11 22:00"),
                                             samples: [SleepClock.night])
        XCTAssertFalse(evening.isAsleep, "this user is not asleep at 22:00, though the fallback is")
    }

    // MARK: AC2 — the fallback when there is no history

    func testWithNoSleepHistoryTheFallbackWindowIsUsed() async throws {
        let night = try await startedModel(named: "fallbackNight",
                                           now: SleepClock.at("2026-03-11 23:00"), samples: [])
        XCTAssertEqual(night.sleepSchedule, .fallback)
        XCTAssertTrue(night.isAsleep, "22:00-07:00 covers 23:00")

        let noon = try await startedModel(named: "fallbackNoon",
                                          now: SleepClock.at("2026-03-11 12:00"), samples: [])
        XCTAssertEqual(noon.sleepSchedule, .fallback)
        XCTAssertFalse(noon.isAsleep)
    }

    /// A failing read is unavailable history too, not a reason to leave the Digimon awake forever.
    func testAFailedSleepReadFallsBackRatherThanStayingAwake() async throws {
        struct Denied: Error {}
        let model = try await startedModel(named: "denied", now: SleepClock.at("2026-03-11 23:00"),
                                           samples: [], error: Denied())
        XCTAssertEqual(model.sleepSchedule, .fallback)
        XCTAssertTrue(model.isAsleep)
    }

    /// A night of nothing but naps is history that says nothing about bedtime.
    func testANapOnlyNightFallsBack() async throws {
        let nap = SleepSample(start: SleepClock.at("2026-03-10 20:15"),
                              end: SleepClock.at("2026-03-10 20:55"), category: .asleepCore)
        let model = try await startedModel(named: "nap", now: SleepClock.at("2026-03-11 23:00"),
                                           samples: [nap])
        XCTAssertEqual(model.sleepSchedule, .fallback)
    }

    // MARK: AC1/AC3 — the sleep loop instead of the idle loop

    func testASleepingDigimonShowsTheSleepLoopAndAnAwakeOneIdles() async throws {
        let asleep = try await startedModel(named: "poseAsleep",
                                            now: SleepClock.at("2026-03-11 01:00"),
                                            samples: [SleepClock.night])
        XCTAssertEqual(asleep.animation, .sleep)
        XCTAssertEqual(asleep.animation.stageFrames, [.sleep1, .sleep2],
                       "frames 4 and 5, i.e. not idle-animating")

        let awake = try await startedModel(named: "poseAwake", now: SleepClock.at("2026-03-11 09:00"),
                                           samples: [SleepClock.night])
        XCTAssertEqual(awake.animation, .idle)
    }

    /// US-037: a sleeping Digimon does not wander. Driven by the DERIVED sleep state, same as the
    /// test above — nothing here says "asleep" except the sleep history, so this cannot pass by
    /// someone having set a flag.
    func testASleepingDigimonDoesNotWanderAndAnAwakeOneDoes() async throws {
        let asleep = try await startedModel(named: "wanderAsleep",
                                            now: SleepClock.at("2026-03-11 01:00"),
                                            samples: [SleepClock.night])
        XCTAssertTrue(asleep.isAsleep)
        XCTAssertFalse(asleep.isWandering, "a sleeping Digimon must not walk about")

        let awake = try await startedModel(named: "wanderAwake",
                                           now: SleepClock.at("2026-03-11 09:00"),
                                           samples: [SleepClock.night])
        XCTAssertFalse(awake.isAsleep)
        XCTAssertTrue(awake.isWandering, "and an awake one must, or nothing moves at all")
    }

    // MARK: AC3 — cannot be fed or trained

    /// Driven by the DERIVED sleep state rather than by setting `isAsleep` by hand, which is the
    /// part US-024 and US-025 could not test: nothing here says "asleep" except the sleep history.
    func testASleepingDigimonCannotBeFedOrTrained() async throws {
        let model = try await startedModel(named: "blocked", now: SleepClock.at("2026-03-11 01:00"),
                                           samples: [SleepClock.night], vitality: 30, strength: 30)
        XCTAssertTrue(model.isAsleep)

        guard case .blocked = model.feed() else { return XCTFail("expected feeding to be blocked") }
        XCTAssertEqual(model.state?.hunger, 3, "nothing was eaten")
        XCTAssertEqual(model.state?.stageEnergy[.vitality], 30, "nothing was spent")
        XCTAssertNotNil(model.actionMessage, "the reason is what the screen shows")
        XCTAssertEqual(model.animation, .sleep, "still asleep, not knocked back into the walk loop")

        guard case .blocked = model.train() else { return XCTFail("expected training to be blocked") }
        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertEqual(model.state?.stageEnergy[.strength], 30)
        XCTAssertEqual(model.animation, .sleep)
    }

    /// The same game one window later feeds normally — so the block above is the WINDOW's doing
    /// and not something permanently wrong with the fixture.
    func testTheSameDigimonCanBeFedOnceItIsOutOfTheWindow() async throws {
        let model = try await startedModel(named: "awakeFeed", now: SleepClock.at("2026-03-11 09:00"),
                                           samples: [SleepClock.night], vitality: 30)
        XCTAssertFalse(model.isAsleep)
        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.animation, .eat)
    }

    /// An action started while awake still reverts to the RESTING pose, and a refresh that happens
    /// mid-action does not stamp on the action's own frames.
    func testAnActionRevertsToTheSleepLoopWhenTheDigimonIsAsleep() async throws {
        let model = try await startedModel(named: "revert", now: SleepClock.at("2026-03-11 01:00"),
                                           samples: [SleepClock.night], vitality: 30)
        // Awake for a moment, long enough to eat.
        model.isAsleep = false
        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.animation, .eat)

        // The window reasserts itself while the eat loop is still playing.
        await model.refresh()
        XCTAssertTrue(model.isAsleep)
        XCTAssertEqual(model.animation, .eat, "mid-action frames are left alone")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .sleep, "back to resting, which is now the sleep loop")
    }
}
