import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, so "midnight" means one thing regardless of
/// where this suite runs. A test that passed only in the machine's zone would be no test at all.
private enum Fixture {
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

    static func startOfDay(_ iso: String) -> Date {
        losAngeles.startOfDay(for: date(iso))
    }

    /// A fresh Digimon and a ledger opened on the same day, which is the state every credit runs
    /// against on a first launch.
    static func newGame(on day: String = "2026-07-17 08:00") -> (GameState, EnergyLedger) {
        (
            GameState(currentDigimonId: "agu_digitama", now: date(day)),
            EnergyLedger(day: startOfDay(day))
        )
    }
}

/// Fixture readers for `HealthEnergySource`. They answer whatever they are told to, ignoring the
/// window — the point is only that Spirit is asked of the sleep reader and nothing else is.
private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    var samples: [SleepSample] = []

    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] {
        samples
    }
}

final class EnergyRatesTests: XCTestCase {
    /// THE AC, literally: the four v1 rates. Asserted at the boundary in BOTH directions rather
    /// than at one convenient multiple — 100 steps must buy a point and 99 must not, which is what
    /// pins the rate to 100 instead of merely to "something 100 divides".
    func testTheFourRatesAreOnePointPerTheSpecifiedMeasurement() {
        XCTAssertEqual(EnergyRates.points(from: 99, of: .strength), 0, "1 Strength per 100 steps")
        XCTAssertEqual(EnergyRates.points(from: 100, of: .strength), 1)

        XCTAssertEqual(EnergyRates.points(from: 19, of: .vitality), 0, "1 Vitality per 20 kcal")
        XCTAssertEqual(EnergyRates.points(from: 20, of: .vitality), 1)

        XCTAssertEqual(EnergyRates.points(from: 14, of: .spirit), 0, "1 Spirit per 15 min asleep")
        XCTAssertEqual(EnergyRates.points(from: 15, of: .spirit), 1)

        XCTAssertEqual(EnergyRates.points(from: 1, of: .stamina), 0, "1 Stamina per 2 exercise min")
        XCTAssertEqual(EnergyRates.points(from: 2, of: .stamina), 1)
    }

    /// A realistic day, so the rates are checked somewhere other than at 1x. Each number is
    /// hand-divided rather than recomputed from the constant, so a changed rate fails here instead
    /// of quietly agreeing with itself.
    func testARealisticDayConvertsAtTheStatedRates() {
        XCTAssertEqual(EnergyRates.points(from: 8_432, of: .strength), 84)
        XCTAssertEqual(EnergyRates.points(from: 517, of: .vitality), 25)
        XCTAssertEqual(EnergyRates.points(from: 447, of: .spirit), 29)
        XCTAssertEqual(EnergyRates.points(from: 37, of: .stamina), 18)
    }

    /// Rounds DOWN: a point means the whole activity behind it was really done.
    func testPartialProgressRoundsDown() {
        XCTAssertEqual(EnergyRates.points(from: 199, of: .strength), 1)
        XCTAssertEqual(EnergyRates.points(from: 299.99, of: .strength), 2)
    }

    /// Both silences are worth zero rather than an error, so one denied metric costs its own energy
    /// type and nothing else (US-011). A real zero is worth zero too — it just isn't the same fact.
    func testSilenceAndZeroAreBothWorthNothing() {
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .noData, of: .strength), 0)
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .unavailable, of: .strength), 0)
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .value(0), of: .strength), 0)
    }

    /// HealthKit samples are written by any app on the phone, so the number is not ours to trust.
    /// `Int(Double)` TRAPS out of range: without the guards this crashes rather than caps.
    func testAnAbsurdReadingCapsInsteadOfCrashing() {
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .value(.infinity), of: .strength), 0)
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .value(.nan), of: .strength), 0)
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .value(1e308), of: .strength), 100)
        XCTAssertEqual(EnergyRates.cappedDailyPoints(from: .value(-5_000), of: .strength), 0,
                       "a negative measurement is not negative energy")
    }
}

final class EnergyCreditingTests: XCTestCase {
    private func credit(
        _ readings: [EnergyType: HealthReading],
        _ state: GameState,
        _ ledger: EnergyLedger,
        at instant: String = "2026-07-17 12:00"
    ) -> EnergyTotals {
        EnergyCreditor.credit(
            readings,
            to: state,
            ledger: ledger,
            now: Fixture.date(instant),
            calendar: Fixture.losAngeles
        )
    }

    // MARK: - Delta crediting

    /// THE AC: reading twice with no new health data credits zero the second time.
    func testReadingTwiceWithNoNewHealthDataCreditsZeroTheSecondTime() {
        let (state, ledger) = Fixture.newGame()
        let readings: [EnergyType: HealthReading] = [.strength: .value(1_000)]

        let first = credit(readings, state, ledger, at: "2026-07-17 12:00")
        let second = credit(readings, state, ledger, at: "2026-07-17 18:00")

        XCTAssertEqual(first.strength, 10, "1,000 steps is 10 Strength")
        XCTAssertEqual(second.strength, 0, "the same 1,000 steps must not be paid for twice")
        XCTAssertEqual(state.stageEnergy.strength, 10)
        XCTAssertEqual(state.lifetimeEnergy.strength, 10)
    }

    /// The other half of delta crediting: new activity IS credited, but only the new part. A reader
    /// that skipped the second read entirely would also pass the test above.
    func testOnlyTheNewPartOfARisingDayIsCredited() {
        let (state, ledger) = Fixture.newGame()

        let morning = credit([.strength: .value(1_000)], state, ledger, at: "2026-07-17 09:00")
        let evening = credit([.strength: .value(1_500)], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(morning.strength, 10)
        XCTAssertEqual(evening.strength, 5, "500 new steps, not all 1,500 again")
        XCTAssertEqual(state.stageEnergy.strength, 15, "15 points for 1,500 steps, not 25")
    }

    /// Ten opens in an afternoon is normal use, and is where a double-credit would actually be felt.
    func testCreditingRepeatedlyIsWorthTheSameAsCreditingOnce() {
        let (state, ledger) = Fixture.newGame()

        for _ in 0..<10 {
            credit([.strength: .value(2_500), .vitality: .value(300)], state, ledger)
        }

        XCTAssertEqual(state.stageEnergy.strength, 25)
        XCTAssertEqual(state.stageEnergy.vitality, 15)
    }

    /// Health data can be deleted from the Health app, and a night still being written can shrink
    /// when a source revises it. Energy is never taken back.
    func testAShrinkingReadingNeverTakesEnergyBack() {
        let (state, ledger) = Fixture.newGame()

        credit([.strength: .value(1_000)], state, ledger, at: "2026-07-17 09:00")
        let after = credit([.strength: .value(200)], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(after.strength, 0, "a smaller reading credits nothing — it does not refund")
        XCTAssertEqual(state.stageEnergy.strength, 10)
    }

    /// A metric going silent must not un-credit what it already paid for, or a denied permission
    /// mid-day would erase the morning's energy.
    func testAMetricFallingSilentDoesNotUndoWhatItPaidFor() {
        let (state, ledger) = Fixture.newGame()

        credit([.strength: .value(1_000)], state, ledger, at: "2026-07-17 09:00")
        credit([.strength: .noData], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(state.stageEnergy.strength, 10)
    }

    // MARK: - The daily cap

    /// THE AC: the 100/day cap holds when a huge sample arrives.
    func testTheDailyCapHoldsWhenAHugeSampleArrives() {
        let (state, ledger) = Fixture.newGame()

        let credited = credit([.strength: .value(1_000_000)], state, ledger)

        XCTAssertEqual(credited.strength, 100, "1,000,000 steps is 10,000 points, capped to 100")
        XCTAssertEqual(state.stageEnergy.strength, 100)
        XCTAssertEqual(state.lifetimeEnergy.strength, 100, "the cap binds the lifetime total too")
    }

    /// The cap is a ceiling on the day, not a per-read allowance: a huge sample must not buy 100
    /// again on the next open.
    func testTheCapIsNotRefreshedByReadingAgainTheSameDay() {
        let (state, ledger) = Fixture.newGame()

        credit([.strength: .value(1_000_000)], state, ledger, at: "2026-07-17 09:00")
        let second = credit([.strength: .value(1_000_000)], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(second.strength, 0)
        XCTAssertEqual(state.stageEnergy.strength, 100, "still 100, not 200")
    }

    /// Per type, not across all four — a marathon must not also max out Spirit.
    func testTheCapIsPerEnergyTypeNotSharedAcrossTheFour() {
        let (state, ledger) = Fixture.newGame()

        let credited = credit([
            .strength: .value(1_000_000),
            .vitality: .value(1_000_000),
            .spirit: .value(1_000_000),
            .stamina: .value(1_000_000),
        ], state, ledger)

        XCTAssertEqual(credited, EnergyTotals(strength: 100, vitality: 100, spirit: 100, stamina: 100))
        XCTAssertEqual(state.stageEnergy.total, 400, "a day's ceiling is 400, not 100")
    }

    /// Capping one type must not cap the others: a huge step count leaves Vitality free to earn its
    /// own honest 15.
    func testACappedTypeDoesNotHoldBackTheOthers() {
        let (state, ledger) = Fixture.newGame()

        let credited = credit([.strength: .value(1_000_000), .vitality: .value(300)], state, ledger)

        XCTAssertEqual(credited.strength, 100)
        XCTAssertEqual(credited.vitality, 15)
    }

    /// The cap binds a day that walks up to it in pieces, not just one that arrives huge.
    func testADayThatReachesTheCapGraduallyStopsAtIt() {
        let (state, ledger) = Fixture.newGame()

        credit([.strength: .value(8_000)], state, ledger, at: "2026-07-17 09:00")
        let later = credit([.strength: .value(30_000)], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(later.strength, 20, "80 already paid, so only the 20 up to the cap remain")
        XCTAssertEqual(state.stageEnergy.strength, 100)
    }

    // MARK: - The day boundary

    /// A new day starts a fresh cap and a fresh baseline. Without the reset, today's 1,000 steps
    /// would look like a shrink from yesterday's 12,000 and buy nothing until they beat it.
    func testANewDayCreditsAgainstAFreshBaselineAndAFreshCap() {
        let (state, ledger) = Fixture.newGame(on: "2026-07-17 08:00")

        credit([.strength: .value(1_000_000)], state, ledger, at: "2026-07-17 21:00")
        let tomorrow = credit([.strength: .value(1_000)], state, ledger, at: "2026-07-18 09:00")

        XCTAssertEqual(tomorrow.strength, 10, "tomorrow's first 1,000 steps are tomorrow's to earn")
        XCTAssertEqual(state.stageEnergy.strength, 110)
        XCTAssertEqual(ledger.day, Fixture.startOfDay("2026-07-18 00:00"))
        XCTAssertEqual(ledger.creditedToday.strength, 10, "the ledger now describes the new day only")
    }

    /// The rollover happens at LOCAL midnight, not 24h after the last read. Crossing it is what
    /// resets the cap, so a late-evening read and an early-morning one are different days.
    func testTheDayRollsOverAtLocalMidnight() {
        let (state, ledger) = Fixture.newGame(on: "2026-07-17 08:00")

        credit([.strength: .value(5_000)], state, ledger, at: "2026-07-17 23:55")
        let justAfter = credit([.strength: .value(100)], state, ledger, at: "2026-07-18 00:05")

        XCTAssertEqual(justAfter.strength, 1, "ten minutes later, but a different day")
        XCTAssertEqual(state.stageEnergy.strength, 51)
    }

    /// Two reads inside one day must NOT reset the cap, which is the mirror of the test above: a
    /// creditor that rolled the day over on every call would pass that one and double-credit here.
    func testTwoReadsInsideOneDayDoNotRollTheDayOver() {
        let (state, ledger) = Fixture.newGame(on: "2026-07-17 08:00")

        credit([.strength: .value(5_000)], state, ledger, at: "2026-07-17 09:00")
        credit([.strength: .value(5_000)], state, ledger, at: "2026-07-17 23:00")

        XCTAssertEqual(state.stageEnergy.strength, 50, "the same 5,000 steps, one day, one payment")
    }

    // MARK: - Where the energy lands

    /// THE AC: energy accrues to both stageEnergy and lifetimeEnergy.
    func testEnergyAccruesToBothStageAndLifetimeTotals() {
        let (state, ledger) = Fixture.newGame()

        credit([
            .strength: .value(1_000),
            .vitality: .value(300),
            .spirit: .value(447),
            .stamina: .value(37),
        ], state, ledger)

        let expected = EnergyTotals(strength: 10, vitality: 15, spirit: 29, stamina: 18)
        XCTAssertEqual(state.stageEnergy, expected)
        XCTAssertEqual(state.lifetimeEnergy, expected)
    }

    /// The two totals are separate accumulators, not one value read twice — which is the whole
    /// reason lifetime energy can outlive an evolution. Pins that crediting after a stage reset
    /// tops up the stage from zero while lifetime keeps counting.
    func testAfterAStageResetLifetimeKeepsCountingAndStageStartsOver() {
        let (state, ledger) = Fixture.newGame(on: "2026-07-17 08:00")
        credit([.strength: .value(1_000)], state, ledger, at: "2026-07-17 09:00")

        // What US-019's evolution will do to the state.
        state.stageEnergy = .zero

        credit([.strength: .value(3_000)], state, ledger, at: "2026-07-17 21:00")

        XCTAssertEqual(state.stageEnergy.strength, 20, "only the 2,000 new steps, into an empty stage")
        XCTAssertEqual(state.lifetimeEnergy.strength, 30, "lifetime never reset")
    }

    /// Each type lands in its own total. A crossed wire here would send sleep to Strength and still
    /// look like a working app, since the numbers would all be plausible.
    func testEachEnergyTypeLandsInItsOwnTotal() {
        let (state, ledger) = Fixture.newGame()

        credit([.spirit: .value(450)], state, ledger)

        XCTAssertEqual(state.stageEnergy, EnergyTotals(strength: 0, vitality: 0, spirit: 30, stamina: 0))
    }

    /// A metric that was never read is not a zero reading — it is simply absent, and must credit
    /// nothing rather than trap on a missing key.
    func testAMissingReadingCreditsNothing() {
        let (state, ledger) = Fixture.newGame()

        let credited = credit([:], state, ledger)

        XCTAssertEqual(credited, .zero)
        XCTAssertEqual(state.stageEnergy, .zero)
    }
}

/// The ledger has to survive a cold launch, which is the literal claim in "reopening the app never
/// double-credits". Everything above runs in one process and would pass with a purely in-memory
/// baseline, so these are the tests that actually cover the AC.
@MainActor
final class EnergyLedgerPersistenceTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("EnergyLedger.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EnergyLedgerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: storeDirectory)
        storeDirectory = nil
        try super.tearDownWithError()
    }

    /// THE AC, against the disk: credit, drop the whole SwiftData stack, open a NEW one on the same
    /// file, and credit the same day's steps again. This is what an app relaunch is.
    func testReopeningTheAppDoesNotCreditTheSameDayAgain() throws {
        let morning = Fixture.date("2026-07-17 09:00")
        let evening = Fixture.date("2026-07-17 21:00")
        let readings: [EnergyType: HealthReading] = [.strength: .value(4_000)]

        var store: GameStore! = try GameStore(url: storeURL)
        var state = try store.loadOrCreate(digitamaId: "agu_digitama", now: morning)
        var ledger = try store.loadOrCreateLedger(now: morning, calendar: Fixture.losAngeles)
        EnergyCreditor.credit(readings, to: state, ledger: ledger, now: morning, calendar: Fixture.losAngeles)
        try store.save()
        XCTAssertEqual(state.stageEnergy.strength, 40)

        // The relaunch: nothing of the first stack survives but the file.
        store = nil

        let reopened = try GameStore(url: storeURL)
        state = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: evening)
        ledger = try reopened.loadOrCreateLedger(now: evening, calendar: Fixture.losAngeles)
        let credited = EnergyCreditor.credit(
            readings, to: state, ledger: ledger, now: evening, calendar: Fixture.losAngeles
        )

        XCTAssertEqual(credited.strength, 0, "the same 4,000 steps, paid for before the relaunch")
        XCTAssertEqual(state.stageEnergy.strength, 40, "still 40 — not 80")
        XCTAssertEqual(ledger.creditedToday.strength, 40, "the baseline came off disk")
    }

    /// The control for the test above: without it, "credits zero after a relaunch" would also pass
    /// on a store that lost the GameState too and silently credited into a discarded object.
    func testAReopenedStoreStillCreditsGenuinelyNewActivity() throws {
        let morning = Fixture.date("2026-07-17 09:00")
        let evening = Fixture.date("2026-07-17 21:00")

        var store: GameStore! = try GameStore(url: storeURL)
        var state = try store.loadOrCreate(digitamaId: "agu_digitama", now: morning)
        var ledger = try store.loadOrCreateLedger(now: morning, calendar: Fixture.losAngeles)
        EnergyCreditor.credit(
            [.strength: .value(4_000)], to: state, ledger: ledger, now: morning, calendar: Fixture.losAngeles
        )
        try store.save()

        store = nil

        let reopened = try GameStore(url: storeURL)
        state = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: evening)
        ledger = try reopened.loadOrCreateLedger(now: evening, calendar: Fixture.losAngeles)
        let credited = EnergyCreditor.credit(
            [.strength: .value(9_000)], to: state, ledger: ledger, now: evening, calendar: Fixture.losAngeles
        )

        XCTAssertEqual(credited.strength, 50, "the 5,000 steps walked since the last read")
        XCTAssertEqual(state.stageEnergy.strength, 90, "and the morning's 40 came off disk with it")
    }

    /// A rebirth must not refund the day's cap: the day belongs to the watch, not to whoever is
    /// currently living on it. This is why the ledger is not a field on `GameState`, which
    /// `resetGame` wipes entirely.
    func testResettingTheGameDoesNotRefundTheDaysCap() throws {
        let now = Fixture.date("2026-07-17 09:00")
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: now)
        let ledger = try store.loadOrCreateLedger(now: now, calendar: Fixture.losAngeles)
        EnergyCreditor.credit(
            [.strength: .value(1_000_000)], to: state, ledger: ledger, now: now, calendar: Fixture.losAngeles
        )
        try store.save()

        let reborn = try store.resetGame(digitamaId: "gabu_digitama", now: now)
        let sameLedger = try store.loadOrCreateLedger(now: now, calendar: Fixture.losAngeles)
        let credited = EnergyCreditor.credit(
            [.strength: .value(1_000_000)], to: reborn, ledger: sameLedger, now: now, calendar: Fixture.losAngeles
        )

        XCTAssertEqual(reborn.stageEnergy.strength, 0, "today's steps were already spent")
        XCTAssertEqual(credited.strength, 0)
        XCTAssertEqual(sameLedger.creditedToday.strength, 100, "the ledger outlived the Digimon")
    }

    /// Adding `EnergyLedger` to `GameStore.schema` changes the model a saved game was written
    /// under, and a store that cannot migrate throws on open — which for the app is a crash at
    /// launch, on exactly the watches that already have a Digimon. Nothing else here would catch
    /// it: every other test writes its store under the CURRENT schema, so the old one is never
    /// exercised. This opens a store written with GameState ALONE, the way it was before this
    /// story, and asserts the ledger arrives without taking the saved game with it.
    ///
    /// US-018 adds the Dex as another `@Model` on this same schema. This is the test that tells it
    /// whether the addition was safe.
    func testAStoreWrittenBeforeTheLedgerExistedStillOpens() throws {
        let now = Fixture.date("2026-07-17 09:00")

        // The store as US-006 shipped it: GameState is the only model in the schema.
        let oldSchema = Schema([GameState.self])
        let oldContainer = try ModelContainer(
            for: oldSchema,
            configurations: ModelConfiguration(schema: oldSchema, url: storeURL)
        )
        oldContainer.mainContext.insert(GameState(currentDigimonId: "agu_digitama", now: now))
        try oldContainer.mainContext.save()

        // The upgrade: same file, new schema.
        let upgraded = try GameStore(url: storeURL)
        let state = try upgraded.loadOrCreate(digitamaId: "gabu_digitama", now: now)
        let ledger = try upgraded.loadOrCreateLedger(now: now, calendar: Fixture.losAngeles)

        XCTAssertEqual(state.currentDigimonId, "agu_digitama",
                       "the saved game survived the migration — it was not replaced by a new one")
        XCTAssertEqual(ledger.creditedToday, .zero, "and the new store gets a fresh ledger")

        EnergyCreditor.credit(
            [.strength: .value(1_000)], to: state, ledger: ledger, now: now, calendar: Fixture.losAngeles
        )
        try upgraded.save()
        XCTAssertEqual(state.stageEnergy.strength, 10, "a migrated store still credits")
    }

    /// A fresh install opens a ledger on today with nothing spent, so the first launch credits the
    /// day it lands in rather than refusing until tomorrow.
    func testAFirstLaunchOpensAnEmptyLedgerOnToday() throws {
        let now = Fixture.date("2026-07-17 09:00")
        let store = try GameStore(url: storeURL)

        let ledger = try store.loadOrCreateLedger(now: now, calendar: Fixture.losAngeles)

        XCTAssertEqual(ledger.day, Fixture.startOfDay("2026-07-17 00:00"))
        XCTAssertEqual(ledger.creditedToday, .zero)
    }
}

/// `HealthEnergySource` is the seam where the two readers become one set of readings. Its one real
/// claim is that Spirit is asked of the SLEEP reader — `TodayHealthReader` cannot answer it, and
/// wiring Spirit to a quantity metric would credit a category raw value as minutes.
final class HealthEnergySourceTests: XCTestCase {
    func testSpiritComesFromSleepAndTheOtherThreeFromTodaysQuantities() async {
        let quantities = FixtureSampleFetcher()
        quantities.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 09:00"), end: Fixture.date("2026-07-17 09:30"), value: 4_000)
        ]
        quantities.samples[.activeEnergy] = [
            HealthSample(start: Fixture.date("2026-07-17 09:00"), end: Fixture.date("2026-07-17 09:30"), value: 300)
        ]
        quantities.samples[.exercise] = [
            HealthSample(start: Fixture.date("2026-07-17 09:00"), end: Fixture.date("2026-07-17 09:30"), value: 30)
        ]

        let sleep = FixtureSleepFetcher()
        // 23:00 to 07:00 — eight hours inside last night's window.
        sleep.samples = [
            SleepSample(
                start: Fixture.date("2026-07-16 23:00"),
                end: Fixture.date("2026-07-17 07:00"),
                category: .asleepCore
            )
        ]

        let source = HealthEnergySource(
            todayReader: TodayHealthReader(fetcher: quantities, calendar: Fixture.losAngeles),
            sleepReader: LastNightSleepReader(fetcher: sleep, calendar: Fixture.losAngeles)
        )

        let readings = await source.readings(now: Fixture.date("2026-07-17 12:00"))

        XCTAssertEqual(readings[.strength], .value(4_000))
        XCTAssertEqual(readings[.vitality], .value(300))
        XCTAssertEqual(readings[.stamina], .value(30))
        XCTAssertEqual(readings[.spirit], .value(480), "eight hours, in MINUTES — not a category value")
    }

    /// The readings feed straight into a credit, which is the path the app actually takes: real
    /// sleep must arrive as 32 Spirit rather than as some plausible other number.
    func testTheReadingsCreditAtTheStatedRates() async {
        let quantities = FixtureSampleFetcher()
        quantities.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 09:00"), end: Fixture.date("2026-07-17 09:30"), value: 4_000)
        ]
        let sleep = FixtureSleepFetcher()
        sleep.samples = [
            SleepSample(
                start: Fixture.date("2026-07-16 23:00"),
                end: Fixture.date("2026-07-17 07:00"),
                category: .asleepCore
            )
        ]
        let source = HealthEnergySource(
            todayReader: TodayHealthReader(fetcher: quantities, calendar: Fixture.losAngeles),
            sleepReader: LastNightSleepReader(fetcher: sleep, calendar: Fixture.losAngeles)
        )
        let now = Fixture.date("2026-07-17 12:00")
        let (state, ledger) = Fixture.newGame()

        let readings = await source.readings(now: now)
        EnergyCreditor.credit(readings, to: state, ledger: ledger, now: now, calendar: Fixture.losAngeles)

        XCTAssertEqual(state.stageEnergy.strength, 40, "4,000 steps at 1 per 100")
        XCTAssertEqual(state.stageEnergy.spirit, 32, "480 minutes at 1 per 15")
        XCTAssertEqual(state.stageEnergy.vitality, 0, "nothing recorded, so nothing earned")
    }
}
