import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-032 — the daily battle cap and the win/loss record.
///
/// Two layers:
/// - `BattleAllowanceTests` — the day arithmetic on `GameState` alone, including the rollover that
///   has to happen while the app is CLOSED.
/// - `BattleLimitApplyTests` — the real `MainScreenModel` over a real store: the sixth tap of a day
///   is refused, the counter resets the next day, and the record survives a reopen so the evolution
///   engine's `minBattleWins` can read it.
///
/// The clock is injected and MOVED between assertions rather than waited on — a cap that resets at
/// local midnight is untestable in real time.

// MARK: - The day arithmetic

final class BattleAllowanceTests: XCTestCase {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Wall-clock rather than an interval, so "the next day" below really does cross a local
    /// midnight in this calendar's time zone instead of landing wherever the epoch falls.
    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    private func makeState(now: Date) -> GameState {
        GameState(currentDigimonId: "egg", now: now)
    }

    /// A fresh Digimon has the whole day's allowance and has fought none of it.
    func testAFreshStateHasTheFullAllowance() {
        let now = Self.date("2026-07-17 10:00")
        let state = makeState(now: now)

        XCTAssertEqual(state.battlesFought(now: now, calendar: Self.calendar), 0)
        XCTAssertEqual(state.battlesRemaining(now: now, calendar: Self.calendar), BattleLimits.perDay)
    }

    /// AC1: five battles is the cap. Asserted as a walk down the remaining count rather than just at
    /// the end, so an off-by-one that allowed six or only four is caught at the step it happens.
    func testTheAllowanceIsSpentOneBattleAtATime() {
        let now = Self.date("2026-07-17 10:00")
        let state = makeState(now: now)

        for spent in 1...BattleLimits.perDay {
            state.consumeBattleAllowance(now: now, calendar: Self.calendar)
            XCTAssertEqual(state.battlesFought(now: now, calendar: Self.calendar), spent)
            XCTAssertEqual(state.battlesRemaining(now: now, calendar: Self.calendar),
                           BattleLimits.perDay - spent)
        }

        XCTAssertEqual(state.battlesRemaining(now: now, calendar: Self.calendar), 0,
                       "the cap is \(BattleLimits.perDay) a day")
    }

    /// AC1: the reset is at LOCAL MIDNIGHT, not 24 hours after the last battle. Five battles at
    /// 23:00 leaves a full allowance an hour later, because that hour crossed the day boundary.
    func testTheAllowanceResetsAtLocalMidnightNotOnAnElapsedDay() {
        let lateNight = Self.date("2026-07-17 23:00")
        let state = makeState(now: lateNight)
        for _ in 0..<BattleLimits.perDay {
            state.consumeBattleAllowance(now: lateNight, calendar: Self.calendar)
        }
        XCTAssertEqual(state.battlesRemaining(now: lateNight, calendar: Self.calendar), 0)

        let justAfterMidnight = Self.date("2026-07-18 00:30")
        XCTAssertEqual(state.battlesRemaining(now: justAfterMidnight, calendar: Self.calendar),
                       BattleLimits.perDay,
                       "an hour and a half later, but a new local day")
        XCTAssertEqual(state.battlesFought(now: justAfterMidnight, calendar: Self.calendar), 0)
    }

    /// The rollover is READ, not written — nothing runs at midnight, and the app may have been shut
    /// the whole time. `battlesFought` must report zero for the new day without anyone having
    /// touched the state since yesterday.
    func testTheRolloverNeedsNothingToRunAtMidnight() {
        let yesterday = Self.date("2026-07-17 10:00")
        let state = makeState(now: yesterday)
        state.consumeBattleAllowance(now: yesterday, calendar: Self.calendar)
        state.consumeBattleAllowance(now: yesterday, calendar: Self.calendar)

        // Nothing is called in between: this is the app being closed overnight.
        let today = Self.date("2026-07-18 10:00")
        XCTAssertEqual(state.battlesFought(now: today, calendar: Self.calendar), 0)
        XCTAssertEqual(state.battleCount, 2, "yesterday's raw count is still sitting there")
        XCTAssertEqual(state.battleDay, Self.calendar.startOfDay(for: yesterday),
                       "and still stamped with yesterday, which is what makes it read as zero")
    }

    /// Spending on a new day rolls the count over rather than adding to yesterday's.
    func testSpendingOnANewDayStartsTheCountOver() {
        let yesterday = Self.date("2026-07-17 10:00")
        let state = makeState(now: yesterday)
        for _ in 0..<BattleLimits.perDay {
            state.consumeBattleAllowance(now: yesterday, calendar: Self.calendar)
        }

        let today = Self.date("2026-07-18 09:00")
        state.consumeBattleAllowance(now: today, calendar: Self.calendar)

        XCTAssertEqual(state.battleCount, 1, "not 6")
        XCTAssertEqual(state.battleDay, Self.calendar.startOfDay(for: today))
        XCTAssertEqual(state.battlesRemaining(now: today, calendar: Self.calendar),
                       BattleLimits.perDay - 1)
    }

    /// A day that skips several days forward is still a clean slate — the reset is "is this today?",
    /// not "was this yesterday?".
    func testAGapOfSeveralDaysAlsoResets() {
        let long = Self.date("2026-07-01 12:00")
        let state = makeState(now: long)
        for _ in 0..<BattleLimits.perDay {
            state.consumeBattleAllowance(now: long, calendar: Self.calendar)
        }

        let muchLater = Self.date("2026-07-19 12:00")
        XCTAssertEqual(state.battlesRemaining(now: muchLater, calendar: Self.calendar),
                       BattleLimits.perDay)
    }

    /// Remaining never goes negative, so a save written under a higher cap reads as "none left"
    /// rather than as a number the UI would have to defend against.
    func testRemainingIsClampedAtZero() {
        let now = Self.date("2026-07-17 10:00")
        let state = makeState(now: now)
        for _ in 0..<(BattleLimits.perDay + 3) {
            state.consumeBattleAllowance(now: now, calendar: Self.calendar)
        }

        XCTAssertEqual(state.battlesRemaining(now: now, calendar: Self.calendar), 0)
    }
}

// MARK: - AC3: the button's disabled state and its reason

final class BattleControlsLimitTests: XCTestCase {
    /// The rule moved from `BattleControls` to `ActionControls` in US-038; the assertions did not,
    /// because the limit is the same limit wherever the button is drawn.
    private func controls(battlesLeft: Int) -> ActionControls<EmptyView> {
        ActionControls(battlesLeft: battlesLeft, feed: {}, train: {}, battle: {}) { EmptyView() }
    }

    /// AC3: at the cap the button is disabled and the reason is the SAME string the model refuses
    /// with, so what the user reads can never disagree with what was enforced.
    func testTheButtonIsDisabledWithTheModelsOwnReasonAtTheCap() {
        let controls = controls(battlesLeft: 0)

        XCTAssertTrue(controls.isBattleDisabled)
        XCTAssertEqual(controls.limitCaption, MainScreenModel.battleLimitReason)
    }

    /// Below the cap the button works and the caption counts down, so a user can see it coming.
    func testTheCaptionCountsDownWhileBattlesRemain() {
        let controls = controls(battlesLeft: 2)

        XCTAssertFalse(controls.isBattleDisabled)
        XCTAssertEqual(controls.limitCaption, "2 left today")
    }

    /// With the full allowance there is no caption at all — a permanent "5 left" would be noise on a
    /// screen this small.
    func testThereIsNoCaptionOnAFullAllowance() {
        let controls = controls(battlesLeft: BattleLimits.perDay)

        XCTAssertFalse(controls.isBattleDisabled)
        XCTAssertNil(controls.limitCaption)
    }
}

// MARK: - Through the real model and the real store

private final class EmptyLimitSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptyLimitSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class BattleLimitApplyTests: XCTestCase {
    private var storeDirectory: URL!
    /// The injected clock, MOVED by a test rather than waited on. A box rather than a `let`, because
    /// the whole point is to step over a local midnight without the model being rebuilt.
    private var currentTime: Date = BattleLimitApplyTests.morning

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        currentTime = Self.morning
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    /// Mid-morning on purpose: the fallback sleep window is 22:00-07:00, and a sleeping Digimon
    /// refuses to battle for a reason that has nothing to do with the cap.
    private static let morning = date("2026-07-17 10:00")
    /// Mid-morning the NEXT local day.
    private static let nextMorning = date("2026-07-18 10:00")

    /// The same three-node fixture US-031 uses: one eligible opponent, so matchmaking cannot be what
    /// varies between runs.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "foe", displayName: "Foe", stage: .adult, spriteFile: "Greymon")
        ])
    }

    private func makeModel(storeName: String = "Limit", strength: Int = 8) throws -> (MainScreenModel, GameStore) {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("\(storeName).store"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.morning)
        state.stage = .child
        state.strengthStat = strength
        // US-027: without these the audit charges a mistake per day since the epoch and sickens the
        // Digimon before the cap is ever reached.
        state.healthDataLastSeen = Self.morning
        state.hungerUpdatedAt = Self.morning
        state.stageEnteredDate = Self.morning
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptyLimitSampleFetcher(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptyLimitSleepFetcher(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { [weak self] in self?.currentTime ?? Self.morning },
            chooseStartingDigitama: { $0.first },
            // A fresh seed per battle, as the app does, so five battles are five different fights
            // rather than the same one replayed.
            makeBattleGenerator: { SeededGenerator(seed: UInt64.random(in: 0..<10_000)) }
        )
        return (model, store)
    }

    /// AC4, the headline criterion: five battles go through and the SIXTH is refused, with the
    /// reason shown and nothing recorded for it.
    func testTheSixthBattleOfADayIsRefused() async throws {
        let (model, _) = try makeModel()
        await model.start()

        for attempt in 1...BattleLimits.perDay {
            XCTAssertNotNil(model.battle(), "battle \(attempt) of \(BattleLimits.perDay) is allowed")
            model.finishBattle()
        }

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.battleWins + state.battleLosses, BattleLimits.perDay)
        XCTAssertEqual(model.battlesRemainingToday, 0)

        XCTAssertNil(model.battle(), "the sixth is refused")
        XCTAssertNil(model.pendingBattle, "and no battle screen comes up")
        XCTAssertEqual(model.actionMessage, MainScreenModel.battleLimitReason)
        XCTAssertEqual(state.battleWins + state.battleLosses, BattleLimits.perDay,
                       "the refused battle is not recorded")
    }

    /// AC4's second half: the counter resets the next day, so the sixth tap that was refused
    /// yesterday succeeds this morning. The clock is moved, not waited on.
    func testTheCounterResetsTheNextDay() async throws {
        let (model, _) = try makeModel()
        await model.start()

        for _ in 0..<BattleLimits.perDay {
            model.battle()
            model.finishBattle()
        }
        XCTAssertNil(model.battle(), "spent for today")

        currentTime = Self.nextMorning
        await model.refresh()

        XCTAssertEqual(model.battlesRemainingToday, BattleLimits.perDay, "a new day, a new allowance")
        XCTAssertNotNil(model.battle(), "and the battle that was refused now goes ahead")
        model.finishBattle()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.battleWins + state.battleLosses, BattleLimits.perDay + 1)
        XCTAssertEqual(model.battlesRemainingToday, BattleLimits.perDay - 1)
    }

    /// The allowance is spent when the fight STARTS, not when its result is dismissed — otherwise
    /// walking away from the result screen would hand it back and the cap would be farmable.
    func testTheAllowanceIsSpentEvenIfTheResultIsNeverDismissed() async throws {
        let (model, _) = try makeModel()
        await model.start()

        XCTAssertNotNil(model.battle())
        // No `finishBattle()`: the user is still staring at the result.
        XCTAssertEqual(model.battlesRemainingToday, BattleLimits.perDay - 1)

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.battlesFought(now: Self.morning, calendar: Self.calendar), 1)
    }

    /// AC2: the record and the day's count both survive the app being closed and reopened, which is
    /// what makes `battleWins` usable as an evolution edge's `minBattleWins` and what stops a
    /// force-quit from refilling the allowance.
    func testTheRecordAndTheCountSurviveAReopen() async throws {
        let (model, store) = try makeModel()
        await model.start()

        for _ in 0..<3 {
            model.battle()
            model.finishBattle()
        }
        let fought = try XCTUnwrap(model.state)
        let wins = fought.battleWins
        let losses = fought.battleLosses
        XCTAssertEqual(wins + losses, 3)
        try store.save()

        // The same call the app makes on launch.
        let reopened = try GameStore(url: storeDirectory.appendingPathComponent("Limit.store"))
        let saved = try reopened.loadOrCreate(digitamaId: "egg", now: Self.morning)

        XCTAssertEqual(saved.battleWins, wins, "readable by the evolution engine's minBattleWins")
        XCTAssertEqual(saved.battleLosses, losses)
        XCTAssertEqual(saved.battlesFought(now: Self.morning, calendar: Self.calendar), 3)
        XCTAssertEqual(saved.battlesRemaining(now: Self.morning, calendar: Self.calendar),
                       BattleLimits.perDay - 3, "quitting does not refill the allowance")
        // And it is the DAY that expires it, not the reopen.
        XCTAssertEqual(saved.battlesRemaining(now: Self.nextMorning, calendar: Self.calendar),
                       BattleLimits.perDay)
    }

    /// AC2's second half: the record is what `EvolutionEngine` reads for `minBattleWins` — asserted
    /// by feeding the state's own fields into the engine, so a record that stopped persisting or a
    /// renamed input fails here rather than silently ungating an edge.
    func testTheStoredRecordIsWhatGatesAMinBattleWinsEdge() async throws {
        let (model, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.stageEnergy.strength = 40
        state.energyLastEarned.strength = Self.morning

        let edge = EvolutionEdge(to: "foe", requiredEnergy: .strength, minEnergy: 40,
                                 maxCareMistakes: 99, minBattleWins: 2)
        func qualifies() -> Bool {
            EvolutionEngine.qualifies(edge,
                                      stageEnergy: state.stageEnergy,
                                      dominant: state.dominantEnergyType,
                                      careMistakes: state.careMistakeCount,
                                      battleWins: state.battleWins)
        }

        state.battleWins = 1
        XCTAssertFalse(qualifies(), "one win is not enough for a two-win edge")

        state.battleWins = 2
        XCTAssertTrue(qualifies(), "the persisted record is what opens the edge")
    }

    /// A blocked-by-the-cap tap is NOT a care mistake — the cap is a rule of the game, not neglect.
    /// (Prodding a SLEEPING Digimon still is, which US-031 covers.)
    func testHittingTheCapIsNotACareMistake() async throws {
        let (model, _) = try makeModel()
        await model.start()

        for _ in 0..<BattleLimits.perDay {
            model.battle()
            model.finishBattle()
        }
        let before = try XCTUnwrap(model.state).careMistakeCount

        model.battle()
        model.battle()

        XCTAssertEqual(model.state?.careMistakeCount, before, "the cap is a rule, not neglect")
    }
}
