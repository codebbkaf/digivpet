import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-101 — a night spent under the light is a care mistake.
///
/// US-098 pinned the RULE (`LightsOutRule.shouldChargeMistake`) and the once-a-night marker
/// (`recordLightsLeftOn`) as pure, unit-tested pieces that nothing called. This suite is about the
/// wiring: the audit `refresh()` now runs beside `auditCareMistakes`, and what it does to a saved
/// game that has actually been left alone overnight.
///
/// Everything below drives the REAL `MainScreenModel` over a REAL `GameStore` on disk, because the
/// story is about launches — the app is closed at 21:00 and opened at 08:00, which is a thing only a
/// store can express. The clock is injected and no test waits real time.
///
/// Every fixture quiets the other four mistakes (see `seedGame`), or a test about the lamp would be
/// measuring hunger and mess as well.

private enum NeglectClock {
    /// Los Angeles, for the reason `LightTests` picks it: a night boundary computed in the wrong
    /// time zone fails here rather than passing by coincidence.
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
}

/// No steps, calories or exercise minutes: nothing here is about earned energy, and an empty reader
/// is also what keeps `energyEarnedToday` below the cure threshold in the sickness test.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

/// No sleep history, so the schedule stays at the 22:00–07:00 fallback every fixture below is
/// written against.
private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - Walking back over the nights nobody was there for

final class LightsOutNightWalkTests: XCTestCase {
    private let calendar = NeglectClock.calendar

    /// The step the multi-night audit takes, and it has to agree with `mostRecentWindowStart` about
    /// which nights exist — it is defined in terms of it precisely so it cannot drift.
    func testTheStepBackLandsOnTheNightBefore() {
        XCTAssertEqual(
            LightsOutRule.previousWindowStart(before: NeglectClock.at("2026-03-11 22:00"),
                                              schedule: .fallback, calendar: calendar),
            NeglectClock.at("2026-03-10 22:00"))

        // The non-wrapping branch: a 02:00 bedtime steps back a whole day like any other.
        let dayShift = SleepSchedule(bedtimeMinute: 2 * 60, wakeMinute: 10 * 60)
        XCTAssertEqual(
            LightsOutRule.previousWindowStart(before: NeglectClock.at("2026-03-11 02:00"),
                                              schedule: dayShift, calendar: calendar),
            NeglectClock.at("2026-03-10 02:00"))
    }

    /// Repeated stepping walks a run of consecutive nights rather than sticking or skipping.
    func testSteppingBackRepeatedlyWalksOneNightAtATime() {
        var night = NeglectClock.at("2026-03-11 22:00")
        var walked: [Date] = []
        for _ in 0..<3 {
            night = LightsOutRule.previousWindowStart(before: night, schedule: .fallback,
                                                      calendar: calendar)
            walked.append(night)
        }
        XCTAssertEqual(walked, [NeglectClock.at("2026-03-10 22:00"),
                                NeglectClock.at("2026-03-09 22:00"),
                                NeglectClock.at("2026-03-08 22:00")])
    }
}

// MARK: - The audit through the real model and the real store

@MainActor
final class LightsOutChargeTests: XCTestCase {
    private var storeDirectory: URL!
    /// Settable, so the one test that seeds several games gives each its own file rather than
    /// deleting and re-creating one — SQLite leaves a write-ahead log beside the store, and a
    /// half-removed one is a fixture bleeding into the next case.
    private var storeName = "LightNeglect"
    private var storeURL: URL { storeDirectory.appendingPathComponent("\(storeName).store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LightNeglectTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// A Baby I with nowhere to go, so any change to the saved game is the audit's doing alone.
    private func stuckGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    /// The same Baby I with one way out, gated on a spotless care record — the edge AC6 is about.
    private func gatedGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon",
                          evolutions: [EvolutionEdge(to: "grown", requiredEnergy: .strength,
                                                     minEnergy: 1, maxCareMistakes: 0)]),
            EvolutionNode(id: "grown", displayName: "Grown", stage: .child, spriteFile: "Agumon")
        ])
    }

    /// Writes a saved game and CLOSES the store, which is what "the user put the watch down" means
    /// here — every launch below reads it back off disk through a store of its own.
    ///
    /// `quietAt` is where the other four mistakes are silenced: hunger and the mess start from zero
    /// at that instant and the health data was last seen then. Passing the launch instant writes off
    /// the whole closure as far as they are concerned, which is how a fixture can span three days
    /// and still charge for nothing but the lamp.
    private func seedGame(born: Date, light: LightState = .on, quietAt: Date? = nil,
                          strength: Int = 0, stageEntered: Date? = nil) throws {
        let store = try GameStore(url: storeURL)
        let state = try store.loadOrCreate(digitamaId: "hero", now: born)
        state.stage = .babyI
        // Through `setLight`, so the state and its "since when" stamp are set the one way the rule
        // can read. `.on` is already the state a new game is in, so that call is a deliberate no-op
        // and the stamp stays at birth.
        state.setLight(light, now: born)

        let quiet = quietAt ?? born
        state.hunger = 0
        state.hungerUpdatedAt = quiet
        state.poopCount = 0
        state.poopUpdatedAt = quiet
        state.healthDataLastSeen = quiet
        state.stageEnergy[.strength] = strength
        state.stageEnteredDate = stageEntered ?? born
        try store.save()
    }

    private func makeModel(now: Date, graph: EvolutionGraph? = nil) -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: graph ?? stuckGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: NeglectClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: NeglectClock.calendar)
            ),
            calendar: NeglectClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// Opens the game at `now` the way the app does when it comes to the front.
    ///
    /// Hands back the MODEL rather than the state, and that is not a style choice: the state belongs
    /// to the model's `ModelContainer`, and a container released while a test still holds one of its
    /// objects resets the context out from under it — reading a field off it then traps inside
    /// SwiftData. So the caller keeps the model alive for as long as it asks the game anything.
    @discardableResult
    private func launch(at now: Date, graph: EvolutionGraph? = nil) async -> MainScreenModel {
        let model = makeModel(now: now, graph: graph)
        await model.start()
        return model
    }

    /// Re-silences the other four rules at `instant`, between two launches days apart. Without it a
    /// second morning brings 24 hours of hunger and mess with it — real neglect, but not this one's.
    private func quietOtherRules(at instant: Date) throws {
        let store = try GameStore(url: storeURL)
        let state = try XCTUnwrap(try store.savedState())
        state.hunger = 0
        state.hungerUpdatedAt = instant
        state.poopCount = 0
        state.poopUpdatedAt = instant
        state.healthDataLastSeen = instant
        try store.save()
    }

    // MARK: AC1/AC3 — the night nobody was there for

    /// THE HEADLINE, and AC3 literally: the store is closed at 21:00 with the light on and opened
    /// again at 08:00, having run not once in between. Exactly one mistake, charged by the refresh
    /// that opening it ran.
    func testANightSleptUnderTheLightIsChargedOnTheNextLaunch() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))
        let state = try XCTUnwrap(model.state)

        XCTAssertEqual(state.careMistakeCount, 1)
        XCTAssertEqual(state.lightAuditedNight, NeglectClock.at("2026-03-10 22:00"),
                       "and the night it was charged for is the one that began at bedtime")
    }

    /// The control: the same eleven hours with the light PUT OUT at 21:00 cost nothing at all. Every
    /// assertion above would pass on an audit that charged unconditionally.
    func testANightSleptInTheDarkCostsNothing() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"), light: .off)

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))
        let state = try XCTUnwrap(model.state)

        XCTAssertEqual(state.careMistakeCount, 0)
        XCTAssertNil(state.lightAuditedNight, "no night was charged, so none was claimed")
    }

    // MARK: AC5 — what counts as out

    /// AC5's first half. The night light is the whole reason `LightState` has three cases: it looks
    /// like bedtime and it is still a light left on.
    func testSemiHeldAllNightIsStillCharged() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"), light: .semi)

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))

        XCTAssertEqual(model.state?.careMistakeCount, 1)
    }

    /// AC5's second half, at both ends of the grace: put out at teatime, and put out at the last
    /// minute the grace allows. Neither costs anything.
    func testLightsOutAnyTimeBeforeTheGraceExpiresCostsNothing() async throws {
        for changed in ["2026-03-10 17:00", "2026-03-10 21:59", "2026-03-10 22:29",
                        "2026-03-10 22:30"] {
            storeName = "Grace-\(changed)"
            // Born at midday, so the light has a whole evening of history behind the hour under
            // test — and the other rules quieted at the LAUNCH instant, because twenty hours is long
            // enough for the screen to fill and that mistake would be indistinguishable from this
            // one in the count.
            try seedGame(born: NeglectClock.at("2026-03-10 12:00"),
                         quietAt: NeglectClock.at("2026-03-11 08:00"))
            // Seeded lit and then put out at the hour under test, which is the order a real evening
            // goes in — a fixture that was never lit could not tell a working rule from a dead one.
            do {
                let store = try GameStore(url: storeURL)
                let seeded = try XCTUnwrap(try store.savedState())
                seeded.setLight(.off, now: NeglectClock.at(changed))
                try store.save()
            }

            let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))
            XCTAssertEqual(model.state?.careMistakeCount, 0, "put out at \(changed)")
            XCTAssertNil(model.state?.lightAuditedNight, "no night claimed, put out at \(changed)")
        }
    }

    // MARK: AC2 — once a night, and the guard is on disk

    /// However many times the app is opened, one night is one mistake — and the guard survives the
    /// app being torn down, because it is read back off disk by each launch rather than remembered.
    func testTheNightIsChargedOnceHoweverOftenTheAppIsOpened() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"))

        await launch(at: NeglectClock.at("2026-03-11 08:00"))
        await launch(at: NeglectClock.at("2026-03-11 09:00"))
        let third = await launch(at: NeglectClock.at("2026-03-11 12:00"))

        XCTAssertEqual(third.state?.careMistakeCount, 1, "three launches, one night, one mistake")

        // Read through a brand new store on the same file, so what is asserted came off disk rather
        // than out of the last model's memory.
        let reopened = try GameStore(url: storeURL)
        let saved = try XCTUnwrap(try reopened.savedState())
        XCTAssertEqual(saved.careMistakeCount, 1)
        XCTAssertEqual(saved.lightAuditedNight, NeglectClock.at("2026-03-10 22:00"),
                       "the marker that guards it was saved")
    }

    // MARK: AC4 — two nights

    /// AC4 with the app opened each morning: two nights, two mistakes, and the marker ends on the
    /// second one rather than sticking on the first.
    func testTwoConsecutiveNeglectedNightsChargeExactlyTwo() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"))

        let first = await launch(at: NeglectClock.at("2026-03-11 08:00"))
        XCTAssertEqual(first.state?.careMistakeCount, 1)

        try quietOtherRules(at: NeglectClock.at("2026-03-12 08:00"))
        let second = await launch(at: NeglectClock.at("2026-03-12 08:00"))

        XCTAssertEqual(second.state?.careMistakeCount, 2)
        XCTAssertEqual(second.state?.lightAuditedNight, NeglectClock.at("2026-03-11 22:00"))
    }

    /// AC4's harder half, and the reason `auditLights` walks back at all: the SAME two nights with
    /// the app shut through both of them still cost two. An audit that charged only the night it had
    /// just woken up in would score this one, and `ClosedAppRecomputeTests` would be right to fail.
    func testTwoNightsSleptThroughWithTheAppShutStillChargeTwo() async throws {
        try seedGame(born: NeglectClock.at("2026-03-09 21:00"),
                     quietAt: NeglectClock.at("2026-03-11 08:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))
        let state = try XCTUnwrap(model.state)

        XCTAssertEqual(state.careMistakeCount, 2, "one for each bedtime the closure crossed")
        XCTAssertEqual(state.lightAuditedNight, NeglectClock.at("2026-03-10 22:00"),
                       "the marker ends on the most recent night, not the oldest one charged")
    }

    /// The walk stops at the Digimon's own history rather than running back through nights that
    /// never happened: a game born this afternoon owes nothing for last week.
    func testNothingIsChargedForNightsBeforeTheLightWasEverOn() async throws {
        try seedGame(born: NeglectClock.at("2026-03-11 14:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 20:00"))

        XCTAssertEqual(model.state?.careMistakeCount, 0)
        XCTAssertNil(model.state?.lightAuditedNight)
    }

    // MARK: AC6 — the same counter as every other mistake

    /// Three neglected nights are three mistakes, which is exactly `Sickness.careMistakesUntilSick`
    /// — so the lamp makes a Digimon ill through the count, with nothing plumbed for it.
    func testThreeNeglectedNightsMakeTheDigimonSick() async throws {
        try seedGame(born: NeglectClock.at("2026-03-08 21:00"),
                     quietAt: NeglectClock.at("2026-03-11 08:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"))

        XCTAssertEqual(model.state?.careMistakeCount, Sickness.careMistakesUntilSick)
        XCTAssertEqual(model.state?.healthStatus, .sick,
                       "the count is what US-028 reads, and it read it")
    }

    /// The other half of AC6: an edge gated on a spotless record is closed by one night under the
    /// light, in the very refresh that charged it.
    func testANeglectedNightClosesAnEdgeGatedOnCareMistakes() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"),
                     quietAt: NeglectClock.at("2026-03-11 08:00"),
                     strength: 10, stageEntered: NeglectClock.at("2026-03-07 21:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"), graph: gatedGraph())
        let state = try XCTUnwrap(model.state)

        XCTAssertEqual(state.careMistakeCount, 1)
        XCTAssertEqual(state.currentDigimonId, "hero", "one mistake is past this edge's ceiling")
        XCTAssertEqual(state.stage, .babyI)
    }

    /// The control the test above needs: everything else about that fixture qualifies, so the SAME
    /// game with the light put out really does take the edge. Without this, a graph that simply
    /// never evolved would pass.
    func testTheSameGameWithTheLightOutTakesTheEdge() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"), light: .off,
                     quietAt: NeglectClock.at("2026-03-11 08:00"),
                     strength: 10, stageEntered: NeglectClock.at("2026-03-07 21:00"))

        let model = await launch(at: NeglectClock.at("2026-03-11 08:00"), graph: gatedGraph())

        XCTAssertEqual(model.state?.careMistakeCount, 0)
        XCTAssertEqual(model.state?.currentDigimonId, "grown", "a spotless record still evolves")
    }

    // MARK: AC7 — the light audit does not double-charge for battle losses

    /// Since US-192 losing a fight IS a care mistake (reversing US-031), but it must ride the same
    /// counter every other mistake does rather than tripping this story's light audit. Twenty-five
    /// losses charge twenty-five mistakes; the refresh that settles every audit adds nothing of its
    /// own and never records a light-neglect night, so the count is exactly the losses.
    ///
    /// `BattleTests.testLosingAFoughtBattleWhileHealthyChargesACareMistake` covers the charge through
    /// a battle actually fought; what this adds is that the light audit does not pile on top of it.
    func testLosingBattlesChargeCareMistakesWithoutTrippingTheLightAudit() async throws {
        try seedGame(born: NeglectClock.at("2026-03-10 21:00"), light: .off)
        let model = makeModel(now: NeglectClock.at("2026-03-11 08:00"))
        await model.start()
        let state = try XCTUnwrap(model.state)

        for _ in 0..<25 {
            state.recordBattle(
                BattleReport(playerPower: 10, opponentPower: 10,
                             turns: [BattleTurn(attacker: .opponent, damage: 10,
                                                defenderRemainingHitPoints: 0)],
                             winner: .opponent))
        }
        await model.refresh()

        XCTAssertEqual(state.battleLosses, 25)
        XCTAssertEqual(state.careMistakeCount, 25, "each healthy loss is one care mistake (US-192)")
        XCTAssertNil(state.lightAuditedNight, "and the light audit adds no night of its own")
    }
}
