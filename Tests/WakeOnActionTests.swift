import Foundation
import XCTest

@testable import DigiVPet

/// US-110 — feeding, training or battling wakes a sleeping Digimon.
///
/// Until this story the three actions charged the waking-early care mistake and then REFUSED: the
/// user paid for a disturbance and got nothing back. They now wake the Digimon first and go ahead,
/// which is what makes the mistake honest.
///
/// Everything here runs on the INJECTED clock — a `var now` the model's closure captures — so the
/// five-minute grace period is sampled at chosen instants rather than waited out. Nothing in this
/// file sleeps.
@MainActor
final class WakeOnActionTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WakeOnAction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Fixture

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func at(_ stamp: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: stamp)!
    }

    /// No steps, calories or exercise minutes. The Simulator has none either, and an empty reader is
    /// also what keeps `energyEarnedToday` below the cure threshold in the sickness test.
    private final class NoSamples: HealthSampleFetching, @unchecked Sendable {
        func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
    }

    /// No sleep history either, so every model here infers the 22:00-07:00 fallback window. That is
    /// the point: 02:00 is inside it, and nothing hand-sets `isAsleep`.
    private final class NoSleep: SleepSampleFetching, @unchecked Sendable {
        func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] { [] }
    }

    /// An egg, the fire Child that is played and fought as, and one plant Baby II to be matched
    /// against — the same shape `PreBattleRoundTests` uses, and for the same reason: exactly one
    /// eligible opponent, so matchmaking never varies between runs.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "agumon", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "agumon", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "tanemon", displayName: "Tanemon", stage: .babyII, spriteFile: "Tanemon")
        ])
    }

    /// Stamps every marker whose rule would otherwise charge a care mistake of its own.
    ///
    /// Four of them, and each is a rule this file is NOT about — a count polluted by starvation or by
    /// a lamp left on cannot say anything about disturbances:
    /// - `healthDataLastSeen`: the empty readers are a silent day, charged once per day elapsed.
    /// - `hungerUpdatedAt` and `hunger`: a Digimon left at maximum hunger is charged for starving,
    ///   and these tests jump a whole night at a time.
    /// - `poopUpdatedAt`: a full screen left uncleaned is charged too, and twelve hours fills it.
    /// - the light: US-101 charges for a night spent under it, and every date here is 02:00. Put out
    ///   rather than restamped, because being off is what the rule actually asks for.
    private func quieten(_ state: GameState, at date: Date) {
        state.healthDataLastSeen = date
        state.hunger = 3
        state.hungerUpdatedAt = date
        state.poopCount = 0
        state.poopUpdatedAt = date
        state.setLight(.off, now: date)
    }

    /// A started model over a real store, with the clock the returned setter moves.
    ///
    /// The clock is a captured `var` rather than a fixed date because the grace period is the thing
    /// under test: every assertion about it is "the same model, five minutes later".
    private func startedModel(named name: String, at start: Date, strength: Int = 100)
        async throws -> (MainScreenModel, URL, (Date) -> Void) {
        let url = storeDirectory.appendingPathComponent("\(name).store")
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "egg", now: start)
        state.currentDigimonId = "agumon"
        state.stage = .child
        state.stageEnteredDate = start
        state.stageEnergy[.vitality] = 100
        state.stageEnergy[.strength] = strength
        quieten(state, at: start)
        try seeding.save()

        var now = start
        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05,
            makeBattleGenerator: { SeededGenerator(seed: 1) }
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        // Feeding spends meat since US-174; stock the larder so a fed test eats rather than blocks.
        model.profile?.meat = 10
        // Battling spends a charge since US-176; stock it so a battle test fights rather than blocks.
        model.state?.battleCharges = ConsumptionConfig.bundled.maxBattleCharges
        // Training spends a charge since US-177; stock it so a train test opens rather than blocks.
        model.state?.trainCharges = ConsumptionConfig.bundled.maxTrainCharges
        return (model, url, { now = $0 })
    }

    // MARK: - AC5: the grace period is a named five minutes

    func testTheWakeGracePeriodIsFiveMinutes() {
        XCTAssertEqual(SleepSchedule.wakeGracePeriod, 5 * 60)
    }

    // MARK: - AC6/AC7/AC9 as pure arithmetic on the window

    /// The override itself, with no model and no store: inside the window a live marker means awake,
    /// an expired one means asleep, and no marker at all means the window has its old meaning.
    func testTheMarkerOverridesTheWindowOnlyWhileItIsLive() {
        let window = SleepSchedule.fallback
        let woken = Self.at("2026-03-11 02:00")
        let awakeUntil = woken.addingTimeInterval(SleepSchedule.wakeGracePeriod)

        XCTAssertTrue(window.isAsleep(at: woken, wokenUntil: nil, calendar: Self.calendar),
                      "undisturbed at 02:00, so asleep")
        XCTAssertFalse(window.isAsleep(at: woken.addingTimeInterval(4 * 60 + 59),
                                       wokenUntil: awakeUntil, calendar: Self.calendar),
                       "4m59s in, still awake")
        XCTAssertTrue(window.isAsleep(at: woken.addingTimeInterval(5 * 60 + 1),
                                      wokenUntil: awakeUntil, calendar: Self.calendar),
                      "5m01s in, back asleep with no user action")
    }

    /// AC9: an absolute instant cannot leak. The marker from one night is long past by the next, so
    /// the following night is asleep at the same hour.
    func testAnOldMarkerDoesNotLeakIntoTheNextNight() {
        let window = SleepSchedule.fallback
        let lastNight = Self.at("2026-03-11 02:00").addingTimeInterval(SleepSchedule.wakeGracePeriod)

        XCTAssertTrue(window.isAsleep(at: Self.at("2026-03-12 02:00"), wokenUntil: lastNight,
                                      calendar: Self.calendar))
        // And the daytime between them is awake for the ordinary reason, not because of the marker.
        XCTAssertFalse(window.isAsleep(at: Self.at("2026-03-11 12:00"), wokenUntil: lastNight,
                                       calendar: Self.calendar))
    }

    // MARK: - AC1/AC3/AC14: the feed at 02:00

    func testFeedingAtTwoAmFeedsAndChargesTheDisturbance() async throws {
        let (model, _, _) = try await startedModel(named: "twoAm", at: Self.at("2026-03-11 02:00"))
        XCTAssertTrue(model.isAsleep, "02:00 is inside the inferred fallback window")
        let state = try XCTUnwrap(model.state)
        let before = state.careMistakeCount

        XCTAssertEqual(model.feed(), .fed)

        XCTAssertEqual(state.hunger, 2, "the meal was really eaten")
        XCTAssertEqual(state.careMistakeCount, before + 1)
        XCTAssertEqual(state.stageSleepDisturbances, 1)
        XCTAssertEqual(state.awakeUntil,
                       Self.at("2026-03-11 02:00").addingTimeInterval(SleepSchedule.wakeGracePeriod))
    }

    // MARK: - AC6: awake means awake — the walk loop, and it wanders

    func testAWokenDigimonWalksAndWanders() async throws {
        let (model, _, setNow) = try await startedModel(named: "walks", at: Self.at("2026-03-11 02:00"))
        XCTAssertEqual(model.animation, .sleep)
        XCTAssertFalse(model.isWandering)

        model.feed()
        setNow(Self.at("2026-03-11 02:01"))
        await model.refresh()
        XCTAssertFalse(model.isAsleep)
        XCTAssertEqual(model.restingAnimation, .idle, "the walk loop, not sleep1 <-> sleep2")

        // The eat pose is held for `actionDuration` by a real timer, not by the injected clock, so
        // this is the one wait in the file — and it is the pose reverting, never the sleep rule.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle)
        XCTAssertTrue(model.isWandering, "a woken Digimon walks about like any other awake one")
    }

    // MARK: - AC8: the refresh must not undo the wake

    /// The way this story is most likely to ship broken: `updateSleepState()` runs on every
    /// foregrounding and re-derives `isAsleep` from the window. Asking the window alone would put
    /// the Digimon straight back to sleep, seconds after the user was charged for waking it.
    func testARefreshDuringTheGracePeriodDoesNotUndoTheWake() async throws {
        let (model, _, setNow) = try await startedModel(named: "refresh", at: Self.at("2026-03-11 02:00"))
        model.feed()
        XCTAssertFalse(model.isAsleep)

        for minute in ["02:01", "02:02", "02:04"] {
            setNow(Self.at("2026-03-11 \(minute)"))
            await model.refresh()
            XCTAssertFalse(model.isAsleep, "still inside the grace at \(minute)")
        }
    }

    // MARK: - AC7/AC17: awake at 4m59s, asleep again at 5m01s

    /// Through the real model and the real refresh, so what is pinned is the shipped derivation
    /// rather than the pure helper it delegates to. No user action returns it to sleep — only time.
    func testItIsAwakeAtFourFiftyNineAndAsleepAgainAtFiveOhOne() async throws {
        let woken = Self.at("2026-03-11 02:00")
        let (model, _, setNow) = try await startedModel(named: "boundary", at: woken)
        model.feed()

        setNow(woken.addingTimeInterval(4 * 60 + 59))
        await model.refresh()
        XCTAssertFalse(model.isAsleep, "4m59s after the wake")

        setNow(woken.addingTimeInterval(5 * 60 + 1))
        await model.refresh()
        XCTAssertTrue(model.isAsleep, "5m01s after it, with nothing tapped")
        // `restingAnimation` rather than `animation`, because the eat pose from the feed is held by
        // a real timer this test deliberately does not wait out — what the sleep rule decides is the
        // pose it returns TO, and `settleRestingPose` swaps it in the moment that timer fires.
        XCTAssertEqual(model.restingAnimation, .sleep, "and back in the sleep loop")
    }

    // MARK: - AC18: the marker expiring outside the window changes nothing

    func testAWakeAtSixFiftyEightIsSimplyAwakeAtSevenOhOne() async throws {
        let (model, _, setNow) = try await startedModel(named: "dawn", at: Self.at("2026-03-11 06:58"))
        XCTAssertTrue(model.isAsleep, "the fallback window runs to 07:00")
        model.feed()

        // 07:03 is when the grace runs out, so 07:01 is inside it and 07:05 is past it. Both are
        // outside the window, so both are awake and the marker never gets a say.
        setNow(Self.at("2026-03-11 07:01"))
        await model.refresh()
        XCTAssertFalse(model.isAsleep)

        setNow(Self.at("2026-03-11 07:05"))
        await model.refresh()
        XCTAssertFalse(model.isAsleep, "morning, not a Digimon put back to bed by an expired marker")
    }

    // MARK: - AC4/AC19: the marker is saved, so a relaunch mid-grace finds it awake

    func testAReloadedModelMidGraceStillReportsItAwake() async throws {
        let woken = Self.at("2026-03-11 02:00")
        let (model, url, _) = try await startedModel(named: "relaunch", at: woken)
        model.feed()
        XCTAssertFalse(model.isAsleep)

        // A cold read off disk, as a relaunch does it — nothing is carried over from the model above.
        let reopened = try GameStore(url: url)
        let saved = try reopened.loadOrCreate(digitamaId: "egg", now: woken)
        XCTAssertEqual(saved.awakeUntil, woken.addingTimeInterval(SleepSchedule.wakeGracePeriod),
                       "the marker reached disk")

        var now = woken.addingTimeInterval(60)
        let relaunched = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
        await relaunched.start()

        XCTAssertFalse(relaunched.isAsleep, "force-quitting must not put it back to sleep")
        XCTAssertEqual(relaunched.animation, .idle)

        // And the same relaunched model settles back down on its own once the grace runs out.
        now = woken.addingTimeInterval(SleepSchedule.wakeGracePeriod + 1)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isAsleep)
    }

    // MARK: - AC15: three disturbances in one night, one care mistake

    /// Spaced past the grace period on purpose: an action taken while the Digimon is ALREADY awake is
    /// not a disturbance, so three prods only means three disturbances if it went back to sleep in
    /// between. That is the arrangement `stageSleepDisturbances` counts and the daily cap does not.
    func testFeedThenTrainThenBattleInOneNightIsThreeDisturbancesAndOneMistake() async throws {
        let (model, _, setNow) = try await startedModel(named: "threeProds",
                                                        at: Self.at("2026-03-11 02:00"))
        let state = try XCTUnwrap(model.state)
        let before = state.careMistakeCount

        XCTAssertEqual(model.feed(), .fed)

        setNow(Self.at("2026-03-11 02:10"))
        await model.refresh()
        XCTAssertTrue(model.isAsleep, "the grace ran out, so the next prod is a fresh disturbance")
        guard case .started = try XCTUnwrap(model.train()) else {
            return XCTFail("expected the training round to open")
        }
        model.finishTraining(.good)

        setNow(Self.at("2026-03-11 02:20"))
        await model.refresh()
        XCTAssertTrue(model.isAsleep)
        XCTAssertNotNil(model.battle(), "and the battle round opens too")

        XCTAssertEqual(state.stageSleepDisturbances, 3, "every prod counts")
        XCTAssertEqual(state.careMistakeCount, before + 1, "but one bad night is one mistake")
    }

    // MARK: - AC16: two nights, two mistakes

    func testDisturbancesOnTwoConsecutiveNightsAreTwoCareMistakes() async throws {
        let (model, _, setNow) = try await startedModel(named: "twoNights",
                                                        at: Self.at("2026-03-11 02:00"))
        let state = try XCTUnwrap(model.state)
        let before = state.careMistakeCount

        model.feed()
        XCTAssertEqual(state.careMistakeCount, before + 1)

        let secondNight = Self.at("2026-03-12 02:00")
        setNow(secondNight)
        // A whole day has elapsed, so the four unrelated rules are stood down again — see `quieten`.
        quieten(state, at: secondNight)
        await model.refresh()
        XCTAssertTrue(model.isAsleep, "and last night's marker has not leaked into tonight")

        model.feed()
        XCTAssertEqual(state.careMistakeCount, before + 2, "a new local day is a new mistake")
        XCTAssertEqual(state.stageSleepDisturbances, 2)
    }

    // MARK: - AC20: three disturbed nights make it ill

    /// The mistakes are REAL mistakes: they reach the same counter sickness is decided from, so a
    /// user who prods their Digimon awake three nights running finds it ill on the third.
    func testThreeDisturbedNightsMakeTheDigimonSick() async throws {
        let (model, _, setNow) = try await startedModel(named: "sicken",
                                                        at: Self.at("2026-03-11 02:00"))
        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.careMistakeCount, 0, "the fixture starts with a clean record")

        for day in ["2026-03-11", "2026-03-12", "2026-03-13"] {
            let night = Self.at("\(day) 02:00")
            setNow(night)
            quieten(state, at: night)
            await model.refresh()
            XCTAssertTrue(model.isAsleep, "asleep at 02:00 on \(day)")
            model.feed()
        }

        XCTAssertEqual(state.careMistakeCount, Sickness.careMistakesUntilSick)
        // Sickness is settled by the refresh, not by the tap that earned the third mistake.
        let morning = Self.at("2026-03-13 09:00")
        setNow(morning)
        quieten(state, at: morning)
        await model.refresh()
        XCTAssertEqual(state.healthStatus, .sick)
    }

    // MARK: - AC10: the death guard sits before the wake

    /// Waking a corpse is not a thing, so a dead Digimon is neither woken nor charged for it — the
    /// old code charged the mistake here, which was a mistake for a disturbance that could not have
    /// happened.
    func testADeadDigimonIsNeitherWokenNorFedTrainedOrBattled() async throws {
        let (model, _, _) = try await startedModel(named: "dead", at: Self.at("2026-03-11 02:00"))
        let state = try XCTUnwrap(model.state)
        state.healthStatus = .dead
        let before = state.careMistakeCount

        guard case .blocked = model.feed() else { return XCTFail("expected the feed to be blocked") }
        guard case .blocked = try XCTUnwrap(model.train()) else {
            return XCTFail("expected the training to be blocked")
        }
        XCTAssertNil(model.battle())

        XCTAssertTrue(model.isAsleep, "not woken")
        XCTAssertNil(state.awakeUntil)
        XCTAssertEqual(state.careMistakeCount, before, "and not charged for waking it")
        XCTAssertEqual(state.stageSleepDisturbances, 0)
        XCTAssertNil(model.pendingTraining)
        XCTAssertNil(model.pendingBattleRound)
        XCTAssertEqual(state.hunger, 3, "nothing was eaten")
    }

    // MARK: - AC11: a sick Digimon's blocks are unchanged

    /// Training still refuses a sick Digimon, exactly as before. It IS woken first, and charged for
    /// it — being dragged out of bed for a session that then does not happen is a disturbance that
    /// really happened, which is the same reasoning US-108 applies to a Digimon with no energy.
    func testASickDigimonIsWokenButStillCannotTrain() async throws {
        let (model, _, _) = try await startedModel(named: "sick", at: Self.at("2026-03-11 02:00"))
        let state = try XCTUnwrap(model.state)
        state.healthStatus = .sick
        let chargesBefore = state.trainCharges

        guard case .blocked(let reason) = try XCTUnwrap(model.train()) else {
            return XCTFail("expected the sick block to stand")
        }
        XCTAssertEqual(reason, "Too sick to train.")
        XCTAssertNil(model.pendingTraining, "and no game either")
        XCTAssertEqual(state.trainCharges, chargesBefore, "nothing charged")
        XCTAssertFalse(model.isAsleep, "but it was genuinely woken")
        XCTAssertEqual(state.stageSleepDisturbances, 1)

        // Feeding a sick Digimon was never blocked, and still is not — eating is how a neglected
        // Digimon is looked after.
        XCTAssertEqual(model.feed(), .fed)
    }
}
