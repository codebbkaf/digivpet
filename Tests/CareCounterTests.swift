import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-084 — the stage-scoped care counters the Digital Monster Color branches on.
///
/// Every test drives an injected `now` and an injected calendar, so nothing here waits for midnight
/// or for a stage to elapse — the same fixture shape `MetricTotalsTests` uses, and for the same
/// reason.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    /// A trainable Digimon: awake, healthy, and holding enough training charges (US-177) for several
    /// sessions.
    static func trainable(on day: String = "2026-07-17 08:00") -> GameState {
        let state = GameState(currentDigimonId: "greymon", stage: .adult, now: date(day))
        state.stageEnergy[.strength] = 100
        state.trainCharges = 10
        return state
    }
}

final class CareCounterTests: XCTestCase {

    // MARK: - AC1: a fresh Digimon has counted nothing

    func testANewGameStartsEveryCounterAtZero() {
        let state = Fixture.trainable()

        XCTAssertEqual(state.stageTrainingSessions, 0)
        XCTAssertEqual(state.stageOverfeeds, 0)
        XCTAssertEqual(state.stageSleepDisturbances, 0)
    }

    // MARK: - AC2: training counts sessions, not outcomes

    func testTrainingIncrementsTheSessionCounter() {
        let state = Fixture.trainable()

        TrainAction.train(state, isAsleep: false)
        TrainAction.train(state, isAsleep: false)
        TrainAction.train(state, isAsleep: false)

        XCTAssertEqual(state.stageTrainingSessions, 3)
    }

    /// A session that never ran must not be counted, or a broke Digimon could farm the counter by
    /// tapping Train at an empty charge bar.
    func testABlockedTrainingIsNotASession() {
        let state = Fixture.trainable()
        state.trainCharges = 0

        let outcome = TrainAction.train(state, isAsleep: false)

        guard case .blocked = outcome else { return XCTFail("expected the training to be blocked") }
        XCTAssertEqual(state.stageTrainingSessions, 0)
    }

    /// AC2 and AC8, the one that matters most: a session graded a MISS still counts.
    ///
    /// US-075's minigame will decide how much `strengthStat` a session pays out, and a missed
    /// session may well pay out nothing. Evolution reads `stageTrainingSessions`, which is filed by
    /// `recordTrainingSession` independently of any gain — so this drives that seam directly, as
    /// the graded path will, and pins that a zero-gain session is still a session. If a later story
    /// makes the count conditional on the grade, this test fails, which is the point.
    func testAMissGradedSessionStillCountsAsTraining() {
        let state = Fixture.trainable()
        let strengthBefore = state.strengthStat

        state.recordTrainingSession()

        XCTAssertEqual(state.stageTrainingSessions, 1,
                       "DMC counts training whether it succeeded or not")
        XCTAssertEqual(state.strengthStat, strengthBefore,
                       "a missed session pays out nothing, and the counter must not care")
    }

    // MARK: - AC3: overfeeds are stage-long, refusalCount is daily

    func testOverfeedsAccumulateAcrossDaysWhileRefusalCountRollsOver() {
        let state = Fixture.trainable()

        state.recordRefusal(now: Fixture.date("2026-07-17 09:00"), calendar: Fixture.losAngeles)
        state.recordRefusal(now: Fixture.date("2026-07-17 10:00"), calendar: Fixture.losAngeles)
        state.recordRefusal(now: Fixture.date("2026-07-18 09:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageOverfeeds, 3,
                       "three refusals this stage, whatever days they fell on")
        XCTAssertEqual(state.refusalCount, 1,
                       "the daily count rolled over at midnight, unchanged by US-084")
    }

    /// AC7: the daily care-mistake rule is untouched. Three refusals in ONE day is still exactly one
    /// mistake, and the stage counter riding alongside must not add a second.
    func testTheDailyRefusalMistakeIsUnchanged() {
        let state = Fixture.trainable()
        let today = "2026-07-17"

        for hour in ["09:00", "10:00", "11:00", "12:00", "13:00"] {
            state.recordRefusal(now: Fixture.date("\(today) \(hour)"), calendar: Fixture.losAngeles)
        }

        XCTAssertEqual(state.careMistakeCount, 1, "the fourth and fifth refusals add no mistake")
        XCTAssertEqual(state.refusalMistakeDay, Fixture.losAngeles.startOfDay(for: Fixture.date("\(today) 09:00")))
        XCTAssertEqual(state.stageOverfeeds, 5, "the stage counter sees all five")
    }

    // MARK: - AC4: sleep disturbances are counted, not marked

    func testEveryDisturbanceIsCountedEvenWithinOneNight() {
        let state = Fixture.trainable()

        state.recordWakingEarly(now: Fixture.date("2026-07-18 02:00"), calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.date("2026-07-18 02:30"), calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.date("2026-07-19 03:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageSleepDisturbances, 3, "the count is per disturbance")
    }

    /// AC7 again: the mistake stays capped at one a night even though the count is not.
    func testTheOncePerNightWakeMistakeIsUnchanged() {
        let state = Fixture.trainable()

        state.recordWakingEarly(now: Fixture.date("2026-07-18 02:00"), calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.date("2026-07-18 02:30"), calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.date("2026-07-18 04:00"), calendar: Fixture.losAngeles)

        XCTAssertEqual(state.careMistakeCount, 1, "six prods is one bad night, not six")
        XCTAssertEqual(state.wakeMistakeDay,
                       Fixture.losAngeles.startOfDay(for: Fixture.date("2026-07-18 02:00")))
        XCTAssertEqual(state.stageSleepDisturbances, 3)
    }

    // MARK: - AC5: all three reset on evolution

    func testEvolvingClearsAllThreeCounters() {
        let state = Fixture.trainable()
        TrainAction.train(state, isAsleep: false)
        state.recordRefusal(now: Fixture.date("2026-07-17 09:00"), calendar: Fixture.losAngeles)
        state.recordWakingEarly(now: Fixture.date("2026-07-18 02:00"), calendar: Fixture.losAngeles)
        XCTAssertEqual(state.stageTrainingSessions, 1)
        XCTAssertEqual(state.stageOverfeeds, 1)
        XCTAssertEqual(state.stageSleepDisturbances, 1)

        state.enterStage(at: Fixture.date("2026-07-19 12:00"))

        XCTAssertEqual(state.stageTrainingSessions, 0)
        XCTAssertEqual(state.stageOverfeeds, 0)
        XCTAssertEqual(state.stageSleepDisturbances, 0)
        XCTAssertEqual(state.stageEnteredDate, Fixture.date("2026-07-19 12:00"),
                       "the reset and the stage clock move together")
    }

    /// The counters are stage-scoped; the lifetime record and the daily care state are not this
    /// story's to clear. Pins that `enterStage` cleared exactly the three it owns.
    func testEvolvingLeavesTheLifetimeAndDailyRecordsStanding() {
        let state = Fixture.trainable()
        state.battleWins = 4
        state.battleLosses = 1
        state.careMistakeCount = 2
        state.recordRefusal(now: Fixture.date("2026-07-17 09:00"), calendar: Fixture.losAngeles)

        state.enterStage(at: Fixture.date("2026-07-17 12:00"))

        XCTAssertEqual(state.battleWins, 4)
        XCTAssertEqual(state.battleLosses, 1)
        XCTAssertEqual(state.careMistakeCount, 2)
        XCTAssertEqual(state.refusalCount, 1, "today's refusal count is a DAY's, not a stage's")
    }

    // MARK: - AC6: the win ratio, including zero battles

    func testBattleWinRatioIsZeroWithNoBattlesFought() {
        let state = Fixture.trainable()

        XCTAssertEqual(state.battleWinRatio, 0,
                       "never fought is never won — and never a divide by zero")
        XCTAssertTrue(state.battleWinRatio.isFinite, "a 0/0 would be NaN and would pass an atMost gate")
    }

    func testBattleWinRatioIsWinsOverBattlesFought() {
        let state = Fixture.trainable()
        state.battleWins = 12
        state.battleLosses = 3

        XCTAssertEqual(state.battleWinRatio, 0.8, accuracy: 0.0001,
                       "DMC's 80% gate is 12 wins in 15 battles")
    }

    func testBattleWinRatioIsOneWhenNothingWasLost() {
        let state = Fixture.trainable()
        state.battleWins = 5

        XCTAssertEqual(state.battleWinRatio, 1.0, accuracy: 0.0001)
    }

    /// The ratio derives, so filing a battle through the real path moves it without anything having
    /// to remember to update a stored copy.
    func testRecordingBattlesMovesTheDerivedRatio() {
        let state = Fixture.trainable()

        state.recordBattle(BattleReport(playerPower: 10, opponentPower: 5, turns: [], winner: .player))
        XCTAssertEqual(state.battleWinRatio, 1.0, accuracy: 0.0001)

        state.recordBattle(BattleReport(playerPower: 10, opponentPower: 20, turns: [], winner: .opponent))
        XCTAssertEqual(state.battleWinRatio, 0.5, accuracy: 0.0001)
    }
}

/// AC1's "all persisted": a `window: .stage` gate spans days, and every one of those days contains a
/// cold launch. Mirrors `MetricTotalsPersistenceTests`.
@MainActor
final class CareCounterPersistenceTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("CareCounters.store") }

    private let t0 = Date(timeIntervalSinceReferenceDate: 900_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CareCounterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// Writes all three, drops the container, then reads through a brand new one pointed at the same
    /// file — so what is asserted came off disk and not out of the first context's cache.
    func testCountersRoundTripThroughTheStore() throws {
        do {
            let store = try GameStore(url: storeURL)
            let state = GameState(currentDigimonId: "greymon", stage: .adult, now: t0)
            state.stageTrainingSessions = 14
            state.stageOverfeeds = 3
            state.stageSleepDisturbances = 2
            store.container.mainContext.insert(state)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let loaded = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        XCTAssertEqual(loaded.stageTrainingSessions, 14)
        XCTAssertEqual(loaded.stageOverfeeds, 3)
        XCTAssertEqual(loaded.stageSleepDisturbances, 2)
    }
}
