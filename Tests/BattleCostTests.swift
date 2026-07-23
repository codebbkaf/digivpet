import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-108 — what a battle costs, now that US-032's five-a-day cap is gone.
///
/// Three layers:
/// - `EnergyPurchaseTests` — the shared "charge the richest payable energy" rule on its own, which is
///   the one implementation training and battling both call.
/// - `BattleDayCountTests` — the day arithmetic `ConditionEvaluator` still reads, including the
///   rollover that has to happen while the app is CLOSED. It gates nothing any more; it is kept
///   because `.day`-window battle conditions are authored against it.
/// - `BattleCostApplyTests` — the real `MainScreenModel` over a real store: six battles in one day,
///   a broke Digimon refused, and the energy never handed back.
///
/// The clock is injected and MOVED between assertions rather than waited on — a count that resets at
/// local midnight is untestable in real time.

// MARK: - The one payment rule

final class EnergyPurchaseTests: XCTestCase {

    private func makeState(strength: Int, stamina: Int) -> GameState {
        let state = GameState(currentDigimonId: "hero", now: Date(timeIntervalSince1970: 0))
        state.stageEnergy.strength = strength
        state.stageEnergy.stamina = stamina
        return state
    }

    /// AC15's first case: the richer of the two pays.
    func testTheRicherEnergyPays() {
        let state = makeState(strength: 7, stamina: 6)

        let payer = EnergyPurchase.charge(BattleCost.energy, from: BattleCost.payableWith, in: state)

        XCTAssertEqual(payer, .strength)
        XCTAssertEqual(state.stageEnergy.strength, 2)
        XCTAssertEqual(state.stageEnergy.stamina, 6, "the one that did not pay is untouched")
    }

    /// AC15's second case: it really is the richest and not just the first listed.
    func testTheRicherEnergyPaysWhenItIsStamina() {
        let state = makeState(strength: 6, stamina: 7)

        let payer = EnergyPurchase.charge(BattleCost.energy, from: BattleCost.payableWith, in: state)

        XCTAssertEqual(payer, .stamina)
        XCTAssertEqual(state.stageEnergy.stamina, 2)
        XCTAssertEqual(state.stageEnergy.strength, 6)
    }

    /// AC15's third case: a tie goes to Strength, by `payableWith` order — the same tie-break
    /// `TrainAction` has always had.
    func testATieGoesToStrength() {
        let state = makeState(strength: 7, stamina: 7)

        XCTAssertEqual(EnergyPurchase.charge(BattleCost.energy, from: BattleCost.payableWith, in: state),
                       .strength)
        XCTAssertEqual(state.stageEnergy.strength, 2)
        XCTAssertEqual(state.stageEnergy.stamina, 7)
    }

    /// Not enough in EITHER energy spends nothing at all — the two cannot be pooled to make up a
    /// cost, which is what "whichever it holds more of pays" means.
    func testTooLittleInBothSpendsNothing() {
        let state = makeState(strength: 4, stamina: 4)

        XCTAssertNil(EnergyPurchase.charge(BattleCost.energy, from: BattleCost.payableWith, in: state))
        XCTAssertEqual(state.stageEnergy.strength, 4)
        XCTAssertEqual(state.stageEnergy.stamina, 4)
    }

    /// `payer` answers the same question without spending, which is what lets a button disable itself
    /// against exactly the rule that would have refused the tap.
    func testPayerAnswersWithoutSpending() {
        let state = makeState(strength: 5, stamina: 0)

        XCTAssertEqual(EnergyPurchase.payer(for: BattleCost.energy,
                                            from: BattleCost.payableWith, in: state), .strength)
        XCTAssertEqual(state.stageEnergy.strength, 5, "asking is free")
        XCTAssertNil(EnergyPurchase.payer(for: BattleCost.energy + 1,
                                          from: BattleCost.payableWith, in: state),
                     "and a point short is short")
    }

    /// A battle spends the physical energy pair, five points, richest first. Until US-177 this
    /// borrowed `TrainAction`'s constants; training moved to a calorie-bought charge that spends no
    /// energy, so battling is the last action that spends energy and pins the numbers itself now.
    func testABattleSpendsFivePointsOfThePhysicalPair() {
        XCTAssertEqual(BattleCost.energy, 5)
        XCTAssertEqual(BattleCost.payableWith, [.strength, .stamina])
        XCTAssertEqual(BattleCost.insufficientEnergyReason,
                       "Not enough Strength or Stamina. Move to earn more.")
    }
}

// MARK: - The day count evolution conditions still read

final class BattleDayCountTests: XCTestCase {

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

    func testAFreshStateHasFoughtNothingToday() {
        let now = Self.date("2026-07-17 10:00")
        XCTAssertEqual(makeState(now: now).battlesFought(now: now, calendar: Self.calendar), 0)
    }

    /// The count goes up one battle at a time and — since US-108 — is not capped at any number.
    func testTheCountRisesOneBattleAtATimeAndIsNotCapped() {
        let now = Self.date("2026-07-17 10:00")
        let state = makeState(now: now)

        for fought in 1...9 {
            state.recordBattleStarted(now: now, calendar: Self.calendar)
            XCTAssertEqual(state.battlesFought(now: now, calendar: Self.calendar), fought)
        }
    }

    /// The reset is at LOCAL MIDNIGHT, not 24 hours after the last battle.
    func testTheCountResetsAtLocalMidnightNotOnAnElapsedDay() {
        let lateNight = Self.date("2026-07-17 23:00")
        let state = makeState(now: lateNight)
        for _ in 0..<5 {
            state.recordBattleStarted(now: lateNight, calendar: Self.calendar)
        }
        XCTAssertEqual(state.battlesFought(now: lateNight, calendar: Self.calendar), 5)

        let justAfterMidnight = Self.date("2026-07-18 00:30")
        XCTAssertEqual(state.battlesFought(now: justAfterMidnight, calendar: Self.calendar), 0,
                       "an hour and a half later, but a new local day")
    }

    /// The rollover is READ, not written — nothing runs at midnight, and the app may have been shut
    /// the whole time. `battlesFought` must report zero for the new day without anyone having
    /// touched the state since yesterday.
    func testTheRolloverNeedsNothingToRunAtMidnight() {
        let yesterday = Self.date("2026-07-17 10:00")
        let state = makeState(now: yesterday)
        state.recordBattleStarted(now: yesterday, calendar: Self.calendar)
        state.recordBattleStarted(now: yesterday, calendar: Self.calendar)

        // Nothing is called in between: this is the app being closed overnight.
        let today = Self.date("2026-07-18 10:00")
        XCTAssertEqual(state.battlesFought(now: today, calendar: Self.calendar), 0)
        XCTAssertEqual(state.battleCount, 2, "yesterday's raw count is still sitting there")
        XCTAssertEqual(state.battleDay, Self.calendar.startOfDay(for: yesterday),
                       "and still stamped with yesterday, which is what makes it read as zero")
    }

    /// Counting on a new day rolls over rather than adding to yesterday's.
    func testCountingOnANewDayStartsOver() {
        let yesterday = Self.date("2026-07-17 10:00")
        let state = makeState(now: yesterday)
        for _ in 0..<5 {
            state.recordBattleStarted(now: yesterday, calendar: Self.calendar)
        }

        let today = Self.date("2026-07-18 09:00")
        state.recordBattleStarted(now: today, calendar: Self.calendar)

        XCTAssertEqual(state.battleCount, 1, "not 6")
        XCTAssertEqual(state.battleDay, Self.calendar.startOfDay(for: today))
    }

    /// A gap of several days is still a clean slate — the reset is "is this today?", not "was this
    /// yesterday?".
    func testAGapOfSeveralDaysAlsoResets() {
        let long = Self.date("2026-07-01 12:00")
        let state = makeState(now: long)
        for _ in 0..<5 {
            state.recordBattleStarted(now: long, calendar: Self.calendar)
        }

        XCTAssertEqual(state.battlesFought(now: Self.date("2026-07-19 12:00"), calendar: Self.calendar), 0)
    }
}

// The button's disabled state and its caption were asserted here in US-108 against a bare `Bool`.
// US-109 moved them to `ActionControlsTests`, where the rest of the row's rules live, and drove them
// through `EnergyPurchase` over a real `GameState` instead — the 4-and-4 versus 5 case the bool
// could not express. Nothing was dropped: see `testBattleIsDisabledWithFourPointsInBothEnergies…`
// and `testTheCaptionNamesEnergyOnlyWhileABattleIsUnaffordable`.

// MARK: - Through the real model and the real store

private final class EmptyLimitSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptyLimitSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class BattleCostApplyTests: XCTestCase {
    private var storeDirectory: URL!
    /// The injected clock, MOVED by a test rather than waited on. A box rather than a `let`, because
    /// the whole point is to step over a local midnight without the model being rebuilt.
    private var currentTime: Date = BattleCostApplyTests.morning

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
    /// refuses to battle for a reason that has nothing to do with the cost.
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

    /// - Parameter strengthEnergy: `stageEnergy.strength`, which is what a battle is now PAID with —
    ///   distinct from `strengthStat`, which is what it is fought with.
    private func makeModel(storeName: String = "Cost", strength: Int = 8,
                           strengthEnergy: Int = 100) throws -> (MainScreenModel, GameStore) {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("\(storeName).store"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.morning)
        state.stage = .child
        state.strengthStat = strength
        state.stageEnergy.strength = strengthEnergy
        // US-176: a battle also spends a charge walked up from steps, and the empty readers walk
        // none. Ten is enough for the six-in-a-day case this file's headline test drives.
        state.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        // US-027: without these the audit charges a mistake per day since the epoch and sickens the
        // Digimon before the sixth battle is ever reached.
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
            // A fresh seed per battle, as the app does, so six battles are six different fights
            // rather than the same one replayed.
            makeBattleGenerator: { SeededGenerator(seed: UInt64.random(in: 0..<10_000)) }
        )
        return (model, store)
    }

    /// AC13, the headline criterion: SIX battles in one local day all go through — the case the old
    /// five-a-day cap forbade — and cost 5 points each.
    func testSixBattlesInOneDayAllGoThrough() async throws {
        let (model, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        let before = state.stageEnergy.strength

        for attempt in 1...6 {
            XCTAssertNotNil(model.battle(), "battle \(attempt) of 6 is allowed")
            // US-093: the tap opens the pre-battle round, and grading it is what fights the fight.
            // `good` throughout, so nothing is measured against a stray multiplier.
            model.finishBattleRound(.good)
            model.finishBattle()
        }

        XCTAssertEqual(state.battleWins + state.battleLosses, 6)
        XCTAssertEqual(state.battlesFought(now: Self.morning, calendar: Self.calendar), 6)
        XCTAssertEqual(state.stageEnergy.strength, before - 6 * BattleCost.energy)
    }

    /// AC14: four points in both payable energies is not enough, and the refused tap spends nothing,
    /// opens no game and is not recorded.
    func testABrokeDigimonIsRefusedAndSpendsNothing() async throws {
        let (model, _) = try makeModel(strengthEnergy: 4)
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.stageEnergy.stamina = 4

        XCTAssertFalse(model.canAffordBattle)
        XCTAssertNil(model.battle(), "four points cannot buy a five-point battle")

        XCTAssertNil(model.pendingBattleRound, "and no minigame comes up")
        XCTAssertNil(model.pendingBattle)
        XCTAssertEqual(model.actionMessage, BattleCost.insufficientEnergyReason)
        XCTAssertEqual(state.stageEnergy.strength, 4, "nothing spent")
        XCTAssertEqual(state.stageEnergy.stamina, 4)
        XCTAssertEqual(state.battleWins + state.battleLosses, 0, "the refused battle is not recorded")
        XCTAssertEqual(state.battlesFought(now: Self.morning, calendar: Self.calendar), 0)
    }

    /// AC16: one battle takes exactly `BattleCost.energy` from `stageEnergy` and NOTHING from
    /// `lifetimeEnergy` — which records what was ever earned, and would re-credit the spend on the
    /// next health read if it moved.
    func testABattleCostsFivePointsOfStageEnergyAndNothingOfLifetime() async throws {
        let (model, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        // On the PROFILE since US-123, which is what makes "a battle cannot touch it" structural:
        // `BattleCost` is handed a `GameState` and the state no longer has a lifetime total on it.
        let profile = try XCTUnwrap(model.profile)
        profile.lifetimeEnergy.strength = 120
        profile.lifetimeEnergy.stamina = 30
        let stageBefore = state.stageEnergy

        XCTAssertNotNil(model.battle())

        XCTAssertEqual(state.stageEnergy.strength, stageBefore.strength - 5)
        XCTAssertEqual(state.stageEnergy.stamina, stageBefore.stamina, "only one energy pays")
        XCTAssertEqual(state.stageEnergy.vitality, stageBefore.vitality)
        XCTAssertEqual(state.stageEnergy.spirit, stageBefore.spirit)
        XCTAssertEqual(profile.lifetimeEnergy.strength, 120, "lifetime is a record of earnings")
        XCTAssertEqual(profile.lifetimeEnergy.stamina, 30)
    }

    /// A battle is paid for when the round OPENS, not when its result is dismissed — otherwise
    /// walking away mid-round would be a free retry.
    func testTheCostIsSpentEvenIfTheRoundIsNeverFinished() async throws {
        let (model, _) = try makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        let before = state.stageEnergy.strength

        XCTAssertNotNil(model.battle())
        // Neither `finishBattleRound` nor `finishBattle()`: the user is still mid-round.
        XCTAssertEqual(state.stageEnergy.strength, before - BattleCost.energy)
        XCTAssertEqual(state.battlesFought(now: Self.morning, calendar: Self.calendar), 1)
    }

    /// The record and the spend both survive the app being closed and reopened, which is what makes
    /// `battleWins` usable as an evolution edge's `minBattleWins` and what stops a force-quit from
    /// refunding the energy.
    func testTheRecordAndTheSpendSurviveAReopen() async throws {
        let (model, store) = try makeModel()
        await model.start()

        for _ in 0..<3 {
            model.battle()
            model.finishBattleRound(.good)
            model.finishBattle()
        }
        let fought = try XCTUnwrap(model.state)
        let wins = fought.battleWins
        let losses = fought.battleLosses
        let spent = fought.stageEnergy.strength
        XCTAssertEqual(wins + losses, 3)
        try store.save()

        // The same call the app makes on launch.
        let reopened = try GameStore(url: storeDirectory.appendingPathComponent("Cost.store"))
        let saved = try reopened.loadOrCreate(digitamaId: "egg", now: Self.morning)

        XCTAssertEqual(saved.battleWins, wins, "readable by the evolution engine's minBattleWins")
        XCTAssertEqual(saved.battleLosses, losses)
        XCTAssertEqual(saved.stageEnergy.strength, spent, "quitting does not refund the energy")
        XCTAssertEqual(saved.battlesFought(now: Self.morning, calendar: Self.calendar), 3)
        XCTAssertEqual(saved.battlesFought(now: Self.nextMorning, calendar: Self.calendar), 0,
                       "and the day's count is a day's count")
    }

    /// The record is what `EvolutionEngine` reads for `minBattleWins` — asserted by feeding the
    /// state's own fields into the engine, so a record that stopped persisting or a renamed input
    /// fails here rather than silently ungating an edge.
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

    /// AC10 stood on US-031's "losing is not neglect"; US-192 reverses that, so what this now pins is
    /// that the ENERGY cost is still only the tap's — the outcome charges no extra energy — while each
    /// healthy loss adds exactly one care mistake and nothing else. No refresh runs between the bouts,
    /// so the Digimon stays healthy throughout and every loss charges, giving an exact count.
    func testLosingChargesOneCareMistakePerLossAndNoExtraEnergy() async throws {
        let (model, _) = try makeModel(strength: 0)
        await model.start()
        let state = try XCTUnwrap(model.state)
        let mistakesBefore = state.careMistakeCount

        for _ in 0..<6 {
            model.battle()
            model.finishBattleRound(.miss)
            model.finishBattle()
        }

        XCTAssertGreaterThan(state.battleLosses, 0, "an untrained Digimon loses at least one of six")
        XCTAssertEqual(state.careMistakeCount, mistakesBefore + state.battleLosses,
                       "one care mistake per healthy loss (US-192), and only that")
    }

    /// Being broke is not a care mistake either — it is a rule of the game, not neglect. (Prodding a
    /// SLEEPING Digimon still is, which US-031 covers.)
    func testBeingBrokeIsNotACareMistake() async throws {
        let (model, _) = try makeModel(strengthEnergy: 0)
        await model.start()
        let before = try XCTUnwrap(model.state).careMistakeCount

        model.battle()
        model.battle()

        XCTAssertEqual(model.state?.careMistakeCount, before, "the cost is a rule, not neglect")
    }
}
