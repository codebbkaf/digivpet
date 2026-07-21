import Foundation
import XCTest

@testable import DigiVPet

/// US-027 — care mistakes.
///
/// Two layers, as US-023's and US-026's suites keep: `CareMistakeRuleTests` pins each of the four
/// rules against an injected clock, and `CareMistakeApplyTests` drives the real `refresh()` and the
/// real store, so the rules are exercised through the code that actually reads and saves the
/// markers.
///
/// No test waits real time. The "clock" is only ever chosen `Date`s a fixed distance apart, which is
/// AC3 — every entry point here takes both `now` and the calendar.

private enum CareClock {
    /// Los Angeles, well away from UTC, so a day boundary computed in the wrong time zone is caught
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

    static let hour: TimeInterval = 60 * 60
}

// MARK: - The four rules

final class CareMistakeRuleTests: XCTestCase {
    private let calendar = CareClock.calendar

    /// A Digimon that has been starving since `starvingSince`, with the health-data rule neutralised
    /// so the only thing that can move the count is starvation.
    private func starvingState(since starvingSince: Date) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .babyI, now: starvingSince)
        state.hunger = HungerClock.maximumHunger
        // `HungerClock` freezes this at the instant hunger hit the maximum, which is exactly what
        // the rule measures from. Set here rather than accrued, so the fixture says its own premise.
        state.hungerUpdatedAt = starvingSince
        return state
    }

    /// Audits with the health-data rule held still: data was seen at this very instant, so no whole
    /// day can have gone by empty and any change to the count belongs to the rule under test.
    private func auditStarvation(_ state: GameState, at now: Date) {
        state.healthDataLastSeen = now
        state.auditCareMistakes(now: now, health: .seen, calendar: calendar)
    }

    // MARK: AC4 — hunger at maximum for 8h or more

    /// AC4, the story's headline number: nine mock hours at maximum hunger is EXACTLY one care
    /// mistake — not zero, and not one per hour.
    func testNineHoursAtMaximumHungerRecordsExactlyOneCareMistake() {
        let state = starvingState(since: CareClock.at("2026-03-10 08:00"))
        auditStarvation(state, at: CareClock.at("2026-03-10 17:00"))

        XCTAssertEqual(state.careMistakeCount, 1)
    }

    /// The threshold is really eight hours. 7h59m is worth nothing and 8h is worth one, so the
    /// nine-hour case above cannot be passing by a looser rule that charges any long spell.
    func testTheStarvationMistakeLandsOnTheEightHourBoundary() {
        let cases: [(hours: Double, expected: Int)] = [
            (0, 0), (4, 0), (7.98, 0), (8, 1), (9, 1), (15.9, 1), (16, 2), (24, 3)
        ]
        for (hours, expected) in cases {
            let start = CareClock.at("2026-03-10 08:00")
            let state = starvingState(since: start)
            auditStarvation(state, at: start.addingTimeInterval(hours * CareClock.hour))
            XCTAssertEqual(state.careMistakeCount, expected, "after \(hours)h at maximum hunger")
        }
    }

    /// Auditing repeatedly inside one spell charges the spell once, which is what lets the main
    /// screen audit on every refresh without the count tracking how often the app is opened.
    func testRepeatedAuditsWithinOneSpellChargeItOnce() {
        let start = CareClock.at("2026-03-10 08:00")
        let state = starvingState(since: start)

        for hours in stride(from: 8.0, through: 15.5, by: 0.5) {
            auditStarvation(state, at: start.addingTimeInterval(hours * CareClock.hour))
        }
        XCTAssertEqual(state.careMistakeCount, 1, "one eight-hour spell, however often it was read")

        // And the second spell still lands when its own eight hours are up.
        auditStarvation(state, at: start.addingTimeInterval(16 * CareClock.hour))
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    /// Feeding ends the spell, and the next one starts from zero rather than inheriting a count
    /// that would make its first hour instantly another mistake.
    func testFeedingEndsTheSpellAndTheNextOneStartsOver() {
        let start = CareClock.at("2026-03-10 08:00")
        let state = starvingState(since: start)
        auditStarvation(state, at: start.addingTimeInterval(9 * CareClock.hour))
        XCTAssertEqual(state.careMistakeCount, 1)

        // Fed: off the maximum, and restamped as US-024 restamps it.
        state.hunger = 0
        state.hungerUpdatedAt = start.addingTimeInterval(9 * CareClock.hour)
        auditStarvation(state, at: start.addingTimeInterval(10 * CareClock.hour))
        XCTAssertEqual(state.careMistakeCount, 1, "a fed Digimon is not being neglected")
        XCTAssertEqual(state.starvationMistakesCharged, 0, "and the spell's tally was cleared")

        // Starving again, from the new stamp: eight hours from THERE, not from the old spell.
        state.hunger = HungerClock.maximumHunger
        state.hungerUpdatedAt = start.addingTimeInterval(10 * CareClock.hour)
        auditStarvation(state, at: start.addingTimeInterval(17 * CareClock.hour))
        XCTAssertEqual(state.careMistakeCount, 1, "seven hours into the new spell is not yet a mistake")
        auditStarvation(state, at: start.addingTimeInterval(18 * CareClock.hour))
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    /// An absurd elapsed time must saturate, not trap: `Int(Double)` traps outside `Int`'s range and
    /// elapsed time is only as sane as the device clock.
    func testAnAbsurdStarvationSaturatesRatherThanTrapping() {
        let state = starvingState(since: .distantPast)
        auditStarvation(state, at: .distantFuture)

        XCTAssertEqual(state.careMistakeCount, CareMistakes.maximumStarvationMistakesCharged)
    }

    // MARK: AC5 — a full day with no health data

    /// A state whose last health data landed at `lastSeen`, with hunger empty so starvation cannot
    /// contribute.
    private func silentState(lastSeen: Date) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .babyI, now: lastSeen)
        state.hunger = 0
        state.healthDataLastSeen = lastSeen
        return state
    }

    /// AC5: one whole day went by with nothing from HealthKit, so exactly one care mistake — read
    /// on the day after, when that empty day is over.
    func testADayWithNoHealthDataRecordsExactlyOneCareMistake() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))
        state.auditCareMistakes(now: CareClock.at("2026-03-12 12:00"), health: .silent,
                                calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 1, "the 11th went by empty; the 12th is still in play")
    }

    /// TODAY IS NEVER CHARGED. A user who simply has not moved yet this morning has neglected
    /// nothing, and charging the day in progress would make the count depend on the hour it is read.
    func testTheDayInProgressIsNeverCharged() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))

        // Later the same day, and the next day — neither has a WHOLE empty day between them.
        for now in ["2026-03-10 23:00", "2026-03-11 07:00", "2026-03-11 23:59"] {
            state.auditCareMistakes(now: CareClock.at(now), health: .silent, calendar: calendar)
            XCTAssertEqual(state.careMistakeCount, 0, "nothing whole has elapsed by \(now)")
        }
    }

    /// AC2's "computed from elapsed real time": three silent days are charged in ONE audit, with no
    /// intervening ticks — the shape of an app that was closed all weekend.
    func testSeveralSilentDaysAreAllChargedInOneAudit() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))
        state.auditCareMistakes(now: CareClock.at("2026-03-14 09:00"), health: .silent,
                                calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 3, "the 11th, 12th and 13th; the 14th is in progress")
    }

    /// The days already charged are not charged again on the next look, and the day that was still
    /// in progress is charged once it is over — never twice.
    func testSilentDaysAreChargedOnceEach() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))
        state.auditCareMistakes(now: CareClock.at("2026-03-12 08:00"), health: .silent,
                                calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1)

        // Read again the same day: nothing new is owed.
        state.auditCareMistakes(now: CareClock.at("2026-03-12 20:00"), health: .silent,
                                calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1)

        // The 12th is now over, so it costs one — and the 11th is not re-charged alongside it.
        state.auditCareMistakes(now: CareClock.at("2026-03-13 08:00"), health: .silent,
                                calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    /// Data seen means no neglect, however long the app was closed for.
    func testDaysWithHealthDataAreNotCharged() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))
        for day in 11...14 {
            state.auditCareMistakes(now: CareClock.at("2026-03-\(day) 12:00"), health: .seen,
                                    calendar: calendar)
        }
        XCTAssertEqual(state.careMistakeCount, 0)
    }

    /// A read that could not happen is NOT neglect. HealthKit being off, or every query failing, is
    /// nothing the user did — and `HealthReading.unavailable` exists to say so.
    func testAnUnreadableDayIsNotCharged() {
        let state = silentState(lastSeen: CareClock.at("2026-03-10 12:00"))
        state.auditCareMistakes(now: CareClock.at("2026-03-14 12:00"), health: .unreadable,
                                calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 0, "four days HealthKit could not be read is not neglect")
        XCTAssertEqual(state.healthDataLastSeen, CareClock.at("2026-03-14 12:00"),
                       "and they are written off, not banked for the first read that works")
    }

    /// The verdict is derived from the readings, and this is the line that matters: a set of
    /// readings that all FAILED must not look like a set that came back empty.
    func testTheVerdictSeparatesAFailedReadFromAnEmptyOne() {
        XCTAssertEqual(CareMistakes.HealthDataVerdict([.value(1200), .noData, .unavailable]), .seen,
                       "one real number means the day was not empty")
        XCTAssertEqual(CareMistakes.HealthDataVerdict([.noData, .noData, .unavailable]), .silent,
                       "HealthKit answered for at least one metric, and had nothing")
        XCTAssertEqual(CareMistakes.HealthDataVerdict([.unavailable, .unavailable]), .unreadable,
                       "nothing could be read, so the day is unknowable")
    }

    /// A save written before this was tracked has no baseline, so the clock STARTS now rather than
    /// charging for every day since the epoch.
    func testAnAbsentMarkerStartsTheClockWithoutCharging() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: CareClock.at("2026-03-10 12:00"))
        state.hunger = 0
        state.healthDataLastSeen = nil

        let now = CareClock.at("2026-03-14 12:00")
        state.auditCareMistakes(now: now, health: .silent, calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 0, "no baseline, so nothing is owed")
        XCTAssertEqual(state.healthDataLastSeen, now, "but the clock starts now")
    }

    /// A backwards clock (the user changed the time, or a timezone moved) is not data arriving, and
    /// must not charge anything either.
    func testABackwardsClockChargesNothing() {
        let state = silentState(lastSeen: CareClock.at("2026-03-14 12:00"))
        state.auditCareMistakes(now: CareClock.at("2026-03-10 12:00"), health: .silent,
                                calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 0)
    }

    // MARK: AC1 — three refusals in one day

    /// The third refusal of a day is the mistake. The first two are not, or a Digimon that refused
    /// twice would be counted as neglected.
    func testThreeRefusalsInOneDayRecordExactlyOneCareMistake() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: CareClock.at("2026-03-10 08:00"))

        state.recordRefusal(now: CareClock.at("2026-03-10 08:00"), calendar: calendar)
        state.recordRefusal(now: CareClock.at("2026-03-10 09:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 0, "two refusals is not yet overfeeding")

        state.recordRefusal(now: CareClock.at("2026-03-10 10:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1)
    }

    /// The fourth and fifth refusals of a day do not each add another. One bad day of overfeeding is
    /// one mistake.
    func testFurtherRefusalsTheSameDayAddNothing() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: CareClock.at("2026-03-10 08:00"))
        for hour in 8...14 {
            state.recordRefusal(now: CareClock.at("2026-03-10 \(hour):00"), calendar: calendar)
        }
        XCTAssertEqual(state.refusalCount, 7)
        XCTAssertEqual(state.careMistakeCount, 1)
    }

    /// A new day is a new chance to overfeed — and the refusals do NOT carry over, so someone who
    /// refuses twice a day forever is never charged.
    func testRefusalsAreCountedPerDay() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: CareClock.at("2026-03-10 08:00"))
        for hour in 8...10 {
            state.recordRefusal(now: CareClock.at("2026-03-10 \(hour):00"), calendar: calendar)
        }
        XCTAssertEqual(state.careMistakeCount, 1)

        // Two the next day: a lifetime counter would trip on the very first of them.
        state.recordRefusal(now: CareClock.at("2026-03-11 08:00"), calendar: calendar)
        state.recordRefusal(now: CareClock.at("2026-03-11 09:00"), calendar: calendar)
        XCTAssertEqual(state.refusalCount, 2, "the day rolled over")
        XCTAssertEqual(state.careMistakeCount, 1, "still just the one day's overfeeding")

        state.recordRefusal(now: CareClock.at("2026-03-11 10:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    // MARK: AC1 — waking the Digimon early

    /// Disturbing a sleeping Digimon costs one mistake, and prodding it repeatedly the same night
    /// costs one — that is one bad night's care, not six.
    func testWakingTheDigimonEarlyIsChargedOncePerDay() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: CareClock.at("2026-03-10 08:00"))

        state.recordWakingEarly(now: CareClock.at("2026-03-10 03:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1)

        for minute in ["03:01", "03:05", "04:30"] {
            state.recordWakingEarly(now: CareClock.at("2026-03-10 \(minute)"), calendar: calendar)
        }
        XCTAssertEqual(state.careMistakeCount, 1)

        // The next night is its own mistake.
        state.recordWakingEarly(now: CareClock.at("2026-03-11 03:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    // MARK: All four together

    /// The four rules feed ONE counter, and each contributes independently — a state that has done
    /// all four is charged four times, not once.
    func testAllFourKindsOfNeglectAddToTheSameCount() {
        let start = CareClock.at("2026-03-10 08:00")
        let state = GameState(currentDigimonId: "hero", stage: .babyI, now: start)
        state.hunger = HungerClock.maximumHunger
        state.hungerUpdatedAt = start
        state.healthDataLastSeen = CareClock.at("2026-03-08 12:00")

        for hour in 8...10 {
            state.recordRefusal(now: CareClock.at("2026-03-10 \(hour):00"), calendar: calendar)
        }
        state.recordWakingEarly(now: CareClock.at("2026-03-10 03:00"), calendar: calendar)
        // 08:00 -> 17:00 is nine hours starving, and the 9th went by with no health data.
        state.auditCareMistakes(now: CareClock.at("2026-03-10 17:00"), health: .silent,
                                calendar: calendar)

        XCTAssertEqual(state.careMistakeCount, 4, "refusals + waking + starvation + one silent day")
    }
}

// MARK: - The rules through the model and the store

/// No steps, calories or exercise minutes: the Simulator has no HealthKit data anyway, and an empty
/// reader is what "a day with no health data" means at this layer.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

/// Hands back its fixture samples regardless of the window asked for, as `SleepStateTests`' fetcher
/// does — the shipped fetcher's predicate really does return sleep from outside the window.
private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    var samples: [SleepSample] = []

    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { samples }
}

@MainActor
final class CareMistakeApplyTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CareMistakeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve and any change to the saved game
    /// is the audit's doing alone.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    private func makeModel(url: URL, now: Date, sleep: [SleepSample] = []) -> MainScreenModel {
        let fetcher = FixtureSleepFetcher()
        fetcher.samples = sleep
        return MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: CareClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: fetcher, calendar: CareClock.calendar)
            ),
            calendar: CareClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// AC4 and AC2 end to end: a Digimon left starving comes back one mistake heavier, through the
    /// same `refresh()` the app runs when it comes to the front — and the app was CLOSED for the
    /// nine hours, so the count was computed from elapsed time rather than from ticks.
    func testLaunchingAfterNineStarvingHoursRecordsOneCareMistake() async throws {
        let url = storeURL("Starving")
        let start = CareClock.at("2026-03-10 08:00")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: start)
            state.stage = .babyI
            state.hunger = HungerClock.maximumHunger
            state.hungerUpdatedAt = start
            state.healthDataLastSeen = start
            try store.save()
            XCTAssertEqual(state.careMistakeCount, 0, "a new game has a clean record")
        }

        let model = makeModel(url: url, now: start.addingTimeInterval(9 * CareClock.hour))
        await model.start()

        XCTAssertEqual(model.state?.careMistakeCount, 1)
    }

    /// AC2's persistence half: the count and its markers are actually FLUSHED. Without this, a
    /// count that rose in memory would rise again from the old marker on the next launch and
    /// double-charge the same neglect.
    func testTheCountAndItsMarkersArePersisted() async throws {
        let url = storeURL("Persist")
        let start = CareClock.at("2026-03-10 08:00")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: start)
            state.stage = .babyI
            state.hunger = HungerClock.maximumHunger
            state.hungerUpdatedAt = start
            state.healthDataLastSeen = start
            try store.save()

            let model = makeModel(url: url, now: start.addingTimeInterval(9 * CareClock.hour))
            await model.start()
            XCTAssertEqual(model.state?.careMistakeCount, 1)
        }

        // A second launch an hour later: the first spell is already paid for, so nothing is added.
        let reopened = try GameStore(url: url)
        let saved = try reopened.loadOrCreate(digitamaId: "hero",
                                              now: start.addingTimeInterval(10 * CareClock.hour))
        XCTAssertEqual(saved.careMistakeCount, 1, "read back off disk")
        XCTAssertEqual(saved.starvationMistakesCharged, 1, "and the marker came back with it")

        let model = makeModel(url: url, now: start.addingTimeInterval(10 * CareClock.hour))
        await model.start()
        XCTAssertEqual(model.state?.careMistakeCount, 1, "the same spell is not charged twice")
    }

    /// AC5 through the real refresh: the readers hand back nothing, which is a day with no health
    /// data, and the day between the last data and today is charged exactly once.
    func testLaunchingAfterASilentDayRecordsOneCareMistake() async throws {
        let url = storeURL("Silent")
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: CareClock.at("2026-03-10 12:00"))
            state.stage = .babyI
            state.hunger = 0
            // Fed at the launch instant, so the two elapsed days accrue no hunger and the silent
            // day is the only rule that can move the count. Left at the seeding date instead, this
            // Digimon would also be starving by the second morning and be charged for that too —
            // correctly, but it would stop being a test of THIS rule.
            state.hungerUpdatedAt = CareClock.at("2026-03-12 12:00")
            // And restamped for exactly the same reason (US-053): two elapsed days would otherwise
            // fill the screen with poop and leave it full, which is neglect this rule is not about.
            state.poopUpdatedAt = CareClock.at("2026-03-12 12:00")
            // And the light put out (US-101), for the third time and the same reason: the two nights
            // between the seed and the launch were both spent under it in a new game, and this test
            // is about the silent day rather than about the lamp.
            state.setLight(.off, now: CareClock.at("2026-03-10 12:00"))
            state.healthDataLastSeen = CareClock.at("2026-03-10 12:00")
            try store.save()
        }

        let model = makeModel(url: url, now: CareClock.at("2026-03-12 12:00"))
        await model.start()

        XCTAssertEqual(model.state?.careMistakeCount, 1)
    }

    /// AC1's fourth rule where the user meets it: an action taken inside the sleep window is charged.
    /// Driven by the derived sleep state, with nothing hand-set.
    ///
    /// Since US-110 the feed also GOES AHEAD — the mistake is for a disturbance that really happened
    /// rather than for a refusal — so the second prod is checked against the grace period instead of
    /// against a second block: the Digimon is already awake, so there is nothing left to disturb and
    /// nothing more to charge.
    func testAFeedWhileAsleepIsChargedAsACareMistake() async throws {
        let url = storeURL("Waking")
        let night = SleepSample(start: CareClock.at("2026-03-10 23:30"),
                                end: CareClock.at("2026-03-11 06:15"), category: .asleepCore)
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: CareClock.at("2026-03-11 01:00"))
            state.stage = .babyI
            state.hunger = 3
            state.stageEnergy[.vitality] = 30
            try store.save()
        }

        let model = makeModel(url: url, now: CareClock.at("2026-03-11 01:00"), sleep: [night])
        await model.start()
        XCTAssertTrue(model.isAsleep)
        let before = try XCTUnwrap(model.state?.careMistakeCount)

        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.state?.careMistakeCount, before + 1)
        XCTAssertFalse(model.isAsleep, "and it is really awake, not merely charged for")

        // A second prod the same night costs nothing more.
        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.state?.careMistakeCount, before + 1)
    }

    /// The mirror of the test above: an action that is NOT blocked by sleep charges nothing, so the
    /// mistake belongs to the sleep window rather than to every blocked action.
    func testAFeedWhileAwakeChargesNoCareMistake() async throws {
        let url = storeURL("Awake")
        let night = SleepSample(start: CareClock.at("2026-03-10 23:30"),
                                end: CareClock.at("2026-03-11 06:15"), category: .asleepCore)
        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: CareClock.at("2026-03-11 09:00"))
            state.stage = .babyI
            state.hunger = 3
            state.stageEnergy[.vitality] = 30
            try store.save()
        }

        let model = makeModel(url: url, now: CareClock.at("2026-03-11 09:00"), sleep: [night])
        await model.start()
        XCTAssertFalse(model.isAsleep)
        let before = try XCTUnwrap(model.state?.careMistakeCount)

        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))
        XCTAssertEqual(model.state?.careMistakeCount, before)
    }
}
