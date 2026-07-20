import Foundation
import XCTest

@testable import DigiVPet

/// US-028 — sickness and its cure.
///
/// Two layers, as US-027's suite keeps: `SicknessRuleTests` pins the rule itself, and
/// `SicknessApplyTests` drives the real `refresh()`, the real ledger and the real store, so the
/// rule is exercised through the code that actually counts the mistakes and credits the energy.
///
/// No test waits real time — every entry point takes an injected clock.

private enum SickClock {
    /// Los Angeles for the same reason `CareMistakeTests` uses it: a day boundary computed in the
    /// wrong time zone is caught rather than passing by coincidence.
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

// MARK: - The rule

final class SicknessRuleTests: XCTestCase {
    private func healthyState() -> GameState {
        GameState(currentDigimonId: "hero", stage: .babyI, now: SickClock.at("2026-03-10 08:00"))
    }

    // MARK: AC1 — three care mistakes make it sick

    /// AC1 and half of AC4: the threshold is really three. Two mistakes leave it well, three make
    /// it sick — so this cannot be passing under a looser "any neglect at all" rule.
    func testThreeCareMistakesMakeItSickAndTwoDoNot() {
        for (mistakes, expected) in [(0, HealthStatus.healthy), (2, .healthy), (3, .sick), (7, .sick)] {
            let state = healthyState()
            state.careMistakeCount = mistakes
            state.updateSickness(energyEarnedToday: 0)

            XCTAssertEqual(state.healthStatus, expected, "\(mistakes) care mistakes")
        }
    }

    /// Settling sickness twice changes nothing the second time, which is what lets `refresh()` call
    /// it on every foregrounding.
    func testSettlingSicknessTwiceIsIdempotent() {
        let state = healthyState()
        state.careMistakeCount = 3
        state.updateSickness(energyEarnedToday: 0)
        state.updateSickness(energyEarnedToday: 0)

        XCTAssertEqual(state.healthStatus, .sick)
        XCTAssertEqual(state.careMistakeCount, 3, "being sick does not itself add mistakes")
    }

    // MARK: AC3 — 30 energy in a day cures it

    /// AC3 and the other half of AC4: thirty energy in a day cures a sick Digimon and wipes its
    /// care record. Twenty-nine does not, so the boundary is really thirty.
    func testThirtyEnergyInADayCuresItAndTwentyNineDoesNot() {
        for (earned, expected) in [(0, HealthStatus.sick), (29, .sick), (30, .healthy), (55, .healthy)] {
            let state = healthyState()
            state.healthStatus = .sick
            state.careMistakeCount = 3
            state.updateSickness(energyEarnedToday: earned)

            XCTAssertEqual(state.healthStatus, expected, "\(earned) energy earned today")
            // AC3's second clause: the cure resets the mistakes, and only the cure does.
            XCTAssertEqual(state.careMistakeCount, expected == .healthy ? 0 : 3,
                           "\(earned) energy earned today")
        }
    }

    /// The cure is checked BEFORE the illness, so a Digimon that falls sick on an active day is not
    /// instantly made well again by energy it had already earned before it fell ill. It really does
    /// go sick on this refresh — the next one is what cures it.
    func testFallingSickOnAnActiveDayIsNotUndoneInTheSameRefresh() {
        let state = healthyState()
        state.careMistakeCount = 3
        state.updateSickness(energyEarnedToday: 100)

        XCTAssertEqual(state.healthStatus, .sick)
        XCTAssertEqual(state.careMistakeCount, 3)

        // ...and the following refresh, by which point the day's energy postdates the diagnosis,
        // is the one that cures it.
        state.updateSickness(energyEarnedToday: 100)
        XCTAssertEqual(state.healthStatus, .healthy)
        XCTAssertEqual(state.careMistakeCount, 0)
    }

    /// A cured Digimon does not relapse on its very next refresh off the three mistakes it was just
    /// forgiven — which is the whole reason the cure resets the count rather than only the status.
    func testACuredDigimonDoesNotRelapseImmediately() {
        let state = healthyState()
        state.healthStatus = .sick
        state.careMistakeCount = 3
        state.updateSickness(energyEarnedToday: 30)
        state.updateSickness(energyEarnedToday: 0)

        XCTAssertEqual(state.healthStatus, .healthy)
    }

    /// Death is final: no amount of walking brings a Digimon back. US-029 owns that state, and this
    /// pins the boundary before it is written.
    func testADeadDigimonIsNeitherSickenedNorCured() {
        let state = healthyState()
        state.healthStatus = .dead
        state.careMistakeCount = 9
        state.updateSickness(energyEarnedToday: 400)

        XCTAssertEqual(state.healthStatus, .dead)
        XCTAssertEqual(state.careMistakeCount, 9)
    }
}

// MARK: - Through the model and the store

private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class SicknessApplyTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SicknessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I that CAN evolve, on an edge with every gate wide open — so if the sick Digimon in
    /// `testASickDigimonDoesNotEvolve` stays put, only its illness can be what held it.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 5, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon",
                          evolutions: [EvolutionEdge(to: "grown", minEnergy: 1, maxCareMistakes: 99,
                                                     isDefault: true)]),
            EvolutionNode(id: "grown", displayName: "Grown", stage: .babyII, spriteFile: "Koromon")
        ])
    }

    /// - Parameter steps: today's step count. 100 steps is one Strength point (`EnergyRates`), so
    ///   3,000 steps is exactly the 30 energy that cures.
    private func makeModel(url: URL, now: Date, steps: Double = 0) -> MainScreenModel {
        let quantities = FixtureSampleFetcher()
        if steps > 0 {
            quantities.samples[.steps] = [
                HealthSample(start: now.addingTimeInterval(-3600), end: now, value: steps)
            ]
        }
        return MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: quantities, calendar: SickClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                 calendar: SickClock.calendar)
            ),
            calendar: SickClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// Seeds a saved game at `hero` with `mistakes` already on its record, and its care markers
    /// stamped at `now` so the audit adds nothing of its own — anything the assertions see is the
    /// sickness rule's doing. (The stamps are the ones US-027's notes say every fixture now needs.)
    private func seed(url: URL, now: Date, mistakes: Int,
                      status: HealthStatus = .healthy) throws {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: now)
        state.stage = .babyI
        state.careMistakeCount = mistakes
        state.healthStatus = status
        // Two days into the stage, so US-020's 24h Baby time gate is already open and the evolution
        // control below really can fire. Without it every model here would stay put for the timing
        // reason and the "sick Digimon does not evolve" assertion would prove nothing.
        state.stageEnteredDate = now.addingTimeInterval(-2 * 24 * 60 * 60)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        try store.save()
    }

    /// AC1 end to end: three care mistakes on the record turn into a sick Digimon the first time
    /// the app comes to the front, through the real `refresh()`.
    func testThreeCareMistakesMakeItSickOnRefresh() async throws {
        let url = storeURL("Sicken")
        let now = SickClock.at("2026-03-10 12:00")
        try seed(url: url, now: now, mistakes: 3)

        let model = makeModel(url: url, now: now)
        await model.start()

        XCTAssertEqual(model.state?.healthStatus, .sick)
    }

    /// US-028 AC2 asked for a sick Digimon not to IDLE-animate, and US-068 asked for it to play the
    /// slow hurt loop instead. Both hold at once: it no longer walks, and what it does instead is
    /// frames 9 <-> 10 at a third of the walk's speed.
    func testASickDigimonPlaysTheSlowHurtLoopAndNotTheWalk() async throws {
        let url = storeURL("Angry")
        let now = SickClock.at("2026-03-10 12:00")
        try seed(url: url, now: now, mistakes: 3)

        let model = makeModel(url: url, now: now)
        await model.start()

        XCTAssertEqual(model.animation, .sick)
        XCTAssertEqual(model.restingAnimation, .sick)
        XCTAssertEqual(model.animation.stageFrames.map(\.rawValue), [9, 10],
                       "US-068 names the frames by index")
        XCTAssertNotEqual(model.animation, .idle, "and it is emphatically not walking")
    }

    /// AC2's third clause: evolution is paused. The edge out of `hero` is a default with every gate
    /// open, so a healthy Digimon in this exact fixture DOES evolve — the control below proves it,
    /// which is what makes the sick one staying put mean something.
    func testASickDigimonDoesNotEvolveButAHealthyOneDoes() async throws {
        let now = SickClock.at("2026-03-10 12:00")

        let sickURL = storeURL("SickNoEvolve")
        try seed(url: sickURL, now: now, mistakes: 3)
        let sick = makeModel(url: sickURL, now: now)
        await sick.start()
        XCTAssertEqual(sick.state?.healthStatus, .sick)
        XCTAssertEqual(sick.state?.currentDigimonId, "hero", "evolution is paused while sick")

        let wellURL = storeURL("WellEvolves")
        try seed(url: wellURL, now: now, mistakes: 0)
        let well = makeModel(url: wellURL, now: now)
        await well.start()
        XCTAssertEqual(well.state?.currentDigimonId, "grown", "the control: this edge does fire")
    }

    /// AC3 end to end, and the second half of AC4: a sick Digimon whose user walks 3,000 steps —
    /// exactly 30 energy at `EnergyRates`' 100 steps a point — is cured, and its care record wiped,
    /// through the real ledger rather than a hand-passed number.
    func testEarningThirtyEnergyInADayCuresIt() async throws {
        let url = storeURL("Cure")
        let now = SickClock.at("2026-03-10 12:00")
        try seed(url: url, now: now, mistakes: 3, status: .sick)

        let model = makeModel(url: url, now: now, steps: 3_000)
        await model.start()

        XCTAssertEqual(model.state?.lifetimeEnergy.total, 30, "3,000 steps is exactly 30 energy")
        XCTAssertEqual(model.state?.healthStatus, .healthy)
        XCTAssertEqual(model.state?.careMistakeCount, 0)
        XCTAssertEqual(model.animation, .idle, "cured, so back to pacing about")
    }

    /// The same day's walk one point short: 2,900 steps is 29 energy, and the Digimon stays sick.
    /// Without this the cure above could be passing off any activity at all.
    func testTwentyNineEnergyDoesNotCureIt() async throws {
        let url = storeURL("NotEnough")
        let now = SickClock.at("2026-03-10 12:00")
        try seed(url: url, now: now, mistakes: 3, status: .sick)

        let model = makeModel(url: url, now: now, steps: 2_900)
        await model.start()

        XCTAssertEqual(model.state?.lifetimeEnergy.total, 29)
        XCTAssertEqual(model.state?.healthStatus, .sick)
    }

    /// The status and the wiped record are FLUSHED, not just changed in memory: a second cold
    /// launch reads a healthy Digimon off the disk.
    func testTheCureIsPersisted() async throws {
        let url = storeURL("Persisted")
        let noon = SickClock.at("2026-03-10 12:00")
        try seed(url: url, now: noon, mistakes: 3, status: .sick)

        await makeModel(url: url, now: noon, steps: 3_000).start()

        // A second launch an hour later, with no new steps to credit.
        let later = makeModel(url: url, now: noon.addingTimeInterval(3_600))
        await later.start()

        XCTAssertEqual(later.state?.healthStatus, .healthy)
        XCTAssertEqual(later.state?.careMistakeCount, 0)
    }
}
