import Foundation
import XCTest

@testable import DigiVPet

/// US-029 — death, the memorial, and rebirth.
///
/// Three layers, extending the shape US-027/US-028 established: `DeathRuleTests` pins the 72-hour
/// rule itself, `MemorialTests` pins what the screen is handed, and `RebirthTests` drives the real
/// store so "the Dex and the lifetime total survive" is asserted against something actually read
/// back off disk rather than off an object still in memory.
///
/// No test waits real time — every entry point takes an injected clock.

private enum DeathClock {
    /// Los Angeles, as `SicknessTests` and `CareMistakeTests` use: a threshold computed in the wrong
    /// time zone is caught rather than passing by coincidence.
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

// MARK: - The rule

final class DeathRuleTests: XCTestCase {
    private let birth = DeathClock.at("2026-03-01 08:00")

    private func sickState(since: Date) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .child, now: birth)
        state.healthStatus = .sick
        state.sickSince = since
        return state
    }

    // MARK: AC1 and AC6 — 72 hours sick is death, 71 is not

    /// AC1 and AC6, both halves: the boundary is really 72 hours. 71 hours leaves the Digimon sick
    /// but alive, 72 kills it — so this cannot be passing under a looser "sick for a while" rule.
    func testSeventyTwoHoursSickKillsItAndSeventyOneDoesNot() {
        for (hoursSick, expected) in [(0.0, HealthStatus.sick), (71, .sick), (71.9, .sick),
                                      (72, .dead), (100, .dead)] {
            let now = DeathClock.at("2026-03-10 12:00")
            let state = sickState(since: now.addingTimeInterval(-hoursSick * DeathClock.hour))
            state.updateDeath(now: now)

            XCTAssertEqual(state.healthStatus, expected, "\(hoursSick) hours sick")
        }
    }

    /// AC5: the threshold is the named constant and not a number written into the rule — so moving
    /// the constant really does move the boundary, which is what "lives in the constants file"
    /// means operationally.
    func testTheThresholdIsSeventyTwoHours() {
        XCTAssertEqual(Death.secondsSickUntilDeath, 72 * 60 * 60)
    }

    /// The countdown starts at the refresh that first SAW the illness, not at some unmarked earlier
    /// moment: a Digimon diagnosed this instant has a nil marker, and the first `updateDeath` stamps
    /// it rather than measuring against nothing and killing it immediately.
    func testTheCountdownStartsAtTheRefreshThatDiagnosedTheIllness() {
        let now = DeathClock.at("2026-03-10 12:00")
        let state = GameState(currentDigimonId: "hero", stage: .child, now: birth)
        state.healthStatus = .sick

        state.updateDeath(now: now)
        XCTAssertEqual(state.healthStatus, .sick, "nothing has elapsed yet")
        XCTAssertEqual(state.sickSince, now, "the countdown started here")

        // ...and 72 hours after THAT, it dies.
        state.updateDeath(now: now.addingTimeInterval(72 * DeathClock.hour))
        XCTAssertEqual(state.healthStatus, .dead)
    }

    /// Being cured stops the countdown, so a Digimon that falls ill again months later starts from
    /// its own beginning rather than inheriting a marker that is already past the threshold.
    func testACureClearsTheCountdownSoTheNextIllnessStartsOver() {
        let firstIllness = DeathClock.at("2026-03-10 12:00")
        let state = sickState(since: firstIllness)

        // Cured: 30 energy in a day, through the real rule.
        state.careMistakeCount = 3
        state.updateSickness(energyEarnedToday: 30)
        XCTAssertEqual(state.healthStatus, .healthy)

        state.updateDeath(now: firstIllness.addingTimeInterval(DeathClock.hour))
        XCTAssertNil(state.sickSince, "the cure stopped the clock")

        // Sick again a month later. The stale marker must not kill it on the spot.
        let relapse = firstIllness.addingTimeInterval(30 * 24 * DeathClock.hour)
        state.healthStatus = .sick
        state.updateDeath(now: relapse)
        XCTAssertEqual(state.healthStatus, .sick, "measured from the relapse, not the first illness")
        XCTAssertEqual(state.sickSince, relapse)
    }

    /// Settling death twice changes nothing the second time, which is what lets `refresh()` call it
    /// on every foregrounding. `diedAt` in particular must not creep forward, or the memorial's
    /// lifespan would grow every time the app was opened.
    func testSettlingDeathTwiceIsIdempotent() {
        let now = DeathClock.at("2026-03-10 12:00")
        let state = sickState(since: now.addingTimeInterval(-80 * DeathClock.hour))
        state.updateDeath(now: now)
        let died = state.diedAt

        state.updateDeath(now: now.addingTimeInterval(50 * DeathClock.hour))

        XCTAssertEqual(state.healthStatus, .dead)
        XCTAssertEqual(state.diedAt, died, "the moment of death does not move")
    }

    /// A healthy Digimon is never killed however long ago it was last ill, and a clock that has been
    /// wound backwards does not kill anything either.
    func testAHealthyDigimonAndABackwardsClockNeverKillIt() {
        let now = DeathClock.at("2026-03-10 12:00")

        let well = GameState(currentDigimonId: "hero", stage: .child, now: birth)
        well.updateDeath(now: now.addingTimeInterval(1_000 * DeathClock.hour))
        XCTAssertEqual(well.healthStatus, .healthy)

        // Sick "since" a week in the future: the watch's clock or timezone moved.
        let confused = sickState(since: now.addingTimeInterval(7 * 24 * DeathClock.hour))
        confused.updateDeath(now: now)
        XCTAssertEqual(confused.healthStatus, .sick)
    }
}

// MARK: - What the memorial says

final class MemorialTests: XCTestCase {
    /// AC2: the memorial carries the name, the lifespan in days, and the final stats.
    func testTheMemorialCarriesTheNameLifespanAndFinalStats() {
        let birth = DeathClock.at("2026-03-01 08:00")
        let state = GameState(currentDigimonId: "agumon", stage: .child, now: birth)
        // Handed in rather than set on the state: since US-123 the lifetime total is the PLAYER's,
        // and a memorial reports it because the next Digimon inherits it.
        let lifetime = EnergyTotals(strength: 120, vitality: 80, spirit: 40, stamina: 30)
        state.strengthStat = 7
        state.battleWins = 3
        state.battleLosses = 1
        state.healthStatus = .sick
        state.sickSince = birth.addingTimeInterval(6 * 24 * DeathClock.hour - 72 * DeathClock.hour)
        // Six days and two hours after birth, so the day count is a floor and not a round.
        state.updateDeath(now: birth.addingTimeInterval(6 * 24 * DeathClock.hour + 2 * DeathClock.hour))

        let memorial = try? XCTUnwrap(state.memorial(displayName: "Agumon",
                                                     lifetimeEnergy: lifetime))
        XCTAssertEqual(memorial?.displayName, "Agumon")
        XCTAssertEqual(memorial?.lifespanDays, 6, "six days and two hours is six whole days")
        XCTAssertEqual(memorial?.lifetimeEnergy.total, 270)
        XCTAssertEqual(memorial?.strengthStat, 7)
        XCTAssertEqual(memorial?.battleWins, 3)
        XCTAssertEqual(memorial?.battleLosses, 1)
    }

    /// A living Digimon has no memorial, which is what keeps the screen from appearing over a
    /// perfectly healthy game.
    func testALivingDigimonHasNoMemorial() {
        let state = GameState(currentDigimonId: "agumon", stage: .child,
                              now: DeathClock.at("2026-03-01 08:00"))
        XCTAssertNil(state.memorial(displayName: "Agumon", lifetimeEnergy: .zero))

        state.healthStatus = .sick
        XCTAssertNil(state.memorial(displayName: "Agumon", lifetimeEnergy: .zero),
                     "sick is not dead")
    }

    /// The lifespan is pluralised, because a Digimon that dies young is exactly the case where a
    /// "1 days" bug would show.
    func testTheLifespanIsPluralisedCorrectly() {
        func text(days: Int) -> String {
            MemorialView(
                memorial: Memorial(displayName: "Agumon", stage: .child, lifespanDays: days,
                                   lifetimeEnergy: .zero, strengthStat: 0,
                                   battleWins: 0, battleLosses: 0),
                onDismiss: {},
                playHaptic: {}
            ).lifespanText
        }
        XCTAssertEqual(text(days: 1), "Lived 1 day")
        XCTAssertEqual(text(days: 0), "Lived 0 days")
        XCTAssertEqual(text(days: 6), "Lived 6 days")
    }
}

// MARK: - Through the model and the store

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class RebirthTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DeathTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// Two eggs, so `chooseStartingDigitama` picking the first is a real choice rather than the only
    /// one available, and `hero` is reachable by hatching.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 5, maxCareMistakes: 99)]),
            EvolutionNode(id: "egg2", displayName: "Egg Two", stage: .digitama,
                          spriteFile: "Bota_Digitama"),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    private func makeModel(url: URL, now: Date) -> MainScreenModel {
        MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: DeathClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: DeathClock.calendar)
            ),
            calendar: DeathClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// Seeds a saved game at `hero` that has been sick for `hoursSick`, with a Dex and a lifetime
    /// total distinctive enough that "they survived" cannot pass by coincidence. Care markers are
    /// stamped at `now` so the audit adds nothing of its own.
    @discardableResult
    private func seedDyingGame(url: URL, now: Date, hoursSick: Double) throws -> URL {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = now.addingTimeInterval(-6 * 24 * DeathClock.hour)
        state.stageEnteredDate = now.addingTimeInterval(-2 * 24 * DeathClock.hour)
        try store.loadOrCreateProfile().lifetimeEnergy =
            EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444)
        state.strengthStat = 9
        state.healthStatus = .sick
        state.careMistakeCount = 3
        state.sickSince = now.addingTimeInterval(-hoursSick * DeathClock.hour)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        // A Dex with something in it beyond the starting egg, so "the Dex survives" is a real claim.
        store.recordDiscovery(id: "hero", now: now)
        try store.save()
        return url
    }

    /// AC1 end to end, and AC6's boundary through the REAL `refresh()`: 72 hours sick is found dead
    /// the first time the app comes to the front, and 71 is not.
    func testTheDigimonIsFoundDeadAfterSeventyTwoHoursSickAndAliveAfterSeventyOne() async throws {
        let now = DeathClock.at("2026-03-10 12:00")

        let deadURL = storeURL("Dead")
        try seedDyingGame(url: deadURL, now: now, hoursSick: 72)
        let dead = makeModel(url: deadURL, now: now)
        await dead.start()
        XCTAssertEqual(dead.state?.healthStatus, .dead)

        let aliveURL = storeURL("Alive")
        try seedDyingGame(url: aliveURL, now: now, hoursSick: 71)
        let alive = makeModel(url: aliveURL, now: now)
        await alive.start()
        XCTAssertEqual(alive.state?.healthStatus, .sick, "the control: one hour short is still alive")
        XCTAssertNil(alive.memorial, "and it gets no memorial")
    }

    /// AC2 through the model: the memorial the screen is handed names the Digimon the graph knows,
    /// and carries the lifespan and the final stats off the saved game.
    func testTheModelOffersAMemorialForTheDeadDigimon() async throws {
        let url = storeURL("Memorial")
        let now = DeathClock.at("2026-03-10 12:00")
        try seedDyingGame(url: url, now: now, hoursSick: 72)

        let model = makeModel(url: url, now: now)
        await model.start()

        let memorial = try XCTUnwrap(model.memorial)
        XCTAssertEqual(memorial.displayName, "Hero", "the name comes from the graph, not the id")
        XCTAssertEqual(memorial.lifespanDays, 6)
        XCTAssertEqual(memorial.lifetimeEnergy.total, 1_110)
        XCTAssertEqual(memorial.strengthStat, 9)
        XCTAssertEqual(model.animation, .still(.hurt2), "and it is not pacing about")
    }

    /// AC3: dismissing the memorial starts a new Digitama — a fresh egg, at stage zero, with the
    /// care record and the death markers all cleared, and the memorial gone with it.
    func testDismissingTheMemorialStartsANewDigitama() async throws {
        let url = storeURL("Rebirth")
        let now = DeathClock.at("2026-03-10 12:00")
        try seedDyingGame(url: url, now: now, hoursSick: 72)

        let model = makeModel(url: url, now: now)
        await model.start()
        XCTAssertNotNil(model.memorial, "precondition: the memorial is up")

        model.dismissMemorial()

        XCTAssertNil(model.memorial, "the memorial is dismissed")
        XCTAssertEqual(model.state?.currentDigimonId, "egg", "a new Digitama")
        XCTAssertEqual(model.state?.stage, .digitama)
        XCTAssertEqual(model.state?.healthStatus, .healthy)
        XCTAssertEqual(model.state?.careMistakeCount, 0)
        XCTAssertNil(model.state?.sickSince)
        XCTAssertNil(model.state?.diedAt)
        XCTAssertEqual(model.state?.stageEnergy, .zero, "the new life starts from nothing")
        XCTAssertEqual(model.state?.strengthStat, 0)
        XCTAssertEqual(model.animation, .idle, "and it is back to wobbling, not lying dead")
    }

    /// AC4, and the heart of the story: the lifetime total and the Dex come across the death, and
    /// are read back off DISK on a fresh launch rather than off the object still in memory.
    func testLifetimeEnergyAndTheDexSurviveDeath() async throws {
        let url = storeURL("Survives")
        let now = DeathClock.at("2026-03-10 12:00")
        try seedDyingGame(url: url, now: now, hoursSick: 72)

        let model = makeModel(url: url, now: now)
        await model.start()
        model.dismissMemorial()

        // A second cold launch an hour later, opening the same store from scratch.
        let store = try GameStore(url: url)
        let reloaded = try store.loadOrCreate(digitamaId: "egg",
                                              now: now.addingTimeInterval(DeathClock.hour))

        XCTAssertEqual(reloaded.currentDigimonId, "egg", "the reborn egg, not the dead Digimon")
        XCTAssertEqual(try store.loadOrCreateProfile().lifetimeEnergy,
                       EnergyTotals(strength: 111, vitality: 222, spirit: 333, stamina: 444),
                       "AC4: the lifetime totals are never wiped")
        XCTAssertNotNil(reloaded, "and the reborn egg is the one that came back")

        // AC7: the Dex is intact — both the egg the dead Digimon started at and the form it grew
        // into are still there, plus the egg the new life started at.
        let dex = try store.dexIds()
        XCTAssertTrue(dex.contains("hero"), "AC7: the dead Digimon is still in the Dex")
        XCTAssertTrue(dex.contains("egg"))
    }

    /// A dead Digimon is inert: it does not hatch on the energy that was already sitting there, and
    /// it cannot be fed. Neither is reachable while the memorial covers the screen, but the rules
    /// should be true of themselves rather than of the view that happens to be on top.
    func testADeadDigimonNeitherHatchesNorEats() async throws {
        let url = storeURL("Inert")
        let now = DeathClock.at("2026-03-10 12:00")

        // A dead EGG, sitting on more than enough energy to hatch.
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.stageEnergy = EnergyTotals(strength: 50, vitality: 0, spirit: 0, stamina: 0)
        state.hunger = 3
        state.healthStatus = .sick
        state.sickSince = now.addingTimeInterval(-72 * DeathClock.hour)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        try store.save()

        let model = makeModel(url: url, now: now)
        await model.start()

        XCTAssertEqual(model.state?.healthStatus, .dead)
        XCTAssertEqual(model.state?.currentDigimonId, "egg", "a dead egg does not hatch")
        // Blocked, and blocked for being an EGG rather than for being dead since US-218: this
        // fixture is both, and the egg guard runs ahead of `FeedAction`'s own death arm. What the
        // test is about — the feed does not happen and nothing is eaten — is unchanged; only which
        // of two true reasons is shown moved.
        XCTAssertEqual(model.feed(), .blocked(reason: MainScreenModel.eggActionReason))
        XCTAssertEqual(model.state?.hunger, 3, "and nothing was eaten")
    }
}
