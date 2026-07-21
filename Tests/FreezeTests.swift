import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-125 — a Digimon put away in the box is exactly as it was left.
///
/// The story has two mechanisms and every test here is deliberately about one of them:
///
/// - `FreezeAccrualTests` pins the GUARDS — an inactive `GameState` runs none of the rules that
///   move a counter.
/// - `FreezeOffsetTests` pins the SHIFT — the readings derived fresh from a saved date, which no
///   guard can protect because nothing runs to guard them. These are the tests that would still
///   fail if the guards were perfect: they thaw and then run the real rules, so a shift that was
///   forgotten shows up as the frozen span being handed over in one lump.
/// - `FreezeThroughTheStoreTests` drives the real `refresh()` over a real box, which is the only
///   way to assert AC5–AC7 about the code that actually runs rather than about a hand-built call.
///
/// No test waits real time; every entry point takes an injected clock.

private enum FreezeClock {
    /// Los Angeles, as the sickness, death and notification suites use — a window or a day boundary
    /// computed in the wrong time zone is caught rather than passing by coincidence.
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
    static let day: TimeInterval = 24 * hour

    /// Mid-May, and the month is the point: every span in this suite is a whole number of 86,400s
    /// days, so a freeze that straddled a DST change would shift the timeline by three days minus an
    /// hour and drift the LOCAL-DAY assertions by an hour for reasons that have nothing to do with
    /// freezing. Both March and November transitions are far away from here.
    static let noon = at("2026-05-12 12:00")
}

// MARK: - AC1: an inactive Digimon accrues nothing

/// The guards, each asserted against the SAME rule run on an active Digimon, so a test that passed
/// because the rule does nothing at all cannot hide here.
final class FreezeAccrualTests: XCTestCase {
    private let start = FreezeClock.noon

    private func makeDigimon(active: Bool) -> GameState {
        GameState(currentDigimonId: "hero", stage: .child, isActive: active, now: start)
    }

    // MARK: hunger

    func testAFrozenDigimonDoesNotGetHungry() {
        let frozen = makeDigimon(active: false)
        let out = makeDigimon(active: true)

        let muchLater = start.addingTimeInterval(30 * FreezeClock.day)
        frozen.advanceHunger(now: muchLater)
        out.advanceHunger(now: muchLater)

        XCTAssertEqual(frozen.hunger, 0)
        XCTAssertEqual(frozen.hungerUpdatedAt, start, "its hunger clock was not even restamped")
        XCTAssertEqual(out.hunger, HungerClock.maximumHunger, "the same 30 days starves the one out")
    }

    // MARK: poop

    func testAFrozenDigimonMakesNoMess() {
        let frozen = makeDigimon(active: false)
        let out = makeDigimon(active: true)

        let muchLater = start.addingTimeInterval(30 * FreezeClock.day)
        frozen.advancePoop(isAsleep: false, now: muchLater)
        out.advancePoop(isAsleep: false, now: muchLater)

        XCTAssertEqual(frozen.poopCount, 0)
        XCTAssertEqual(frozen.poopUpdatedAt, start)
        XCTAssertEqual(out.poopCount, PoopClock.maximumPoops)
    }

    // MARK: care mistakes

    func testAFrozenDigimonIsChargedNoCareMistakesForTheDaysItWasAway() {
        let frozen = makeDigimon(active: false)
        let out = makeDigimon(active: true)

        // Four silent days: the audit charges one mistake per whole local day that went by with no
        // health data, today excepted.
        let muchLater = start.addingTimeInterval(4 * FreezeClock.day)
        frozen.auditCareMistakes(now: muchLater, health: .silent, calendar: FreezeClock.calendar)
        out.auditCareMistakes(now: muchLater, health: .silent, calendar: FreezeClock.calendar)

        XCTAssertEqual(frozen.careMistakeCount, 0)
        XCTAssertEqual(frozen.healthDataLastSeen, start, "nor was its marker moved")
        XCTAssertEqual(out.careMistakeCount, 3, "the one out is charged for the three whole days")
    }

    /// The two mistakes charged at a MOMENT rather than over a span. Nobody can offer food to a
    /// Digimon in the box or prod it awake, so neither can ever be owed by one.
    func testAFrozenDigimonRefusesNoFoodAndIsDisturbedByNobody() {
        let frozen = makeDigimon(active: false)

        for _ in 0..<CareMistakes.refusalsPerMistake {
            frozen.recordRefusal(now: start, calendar: FreezeClock.calendar)
        }
        frozen.recordWakingEarly(now: start, calendar: FreezeClock.calendar)

        XCTAssertEqual(frozen.careMistakeCount, 0)
        XCTAssertEqual(frozen.refusalCount, 0)
        XCTAssertEqual(frozen.stageOverfeeds, 0)
        XCTAssertEqual(frozen.stageSleepDisturbances, 0)
    }

    // MARK: sickness and death

    /// Both directions. The cure matters as much as the illness: `energyEarnedToday` comes off the
    /// shared `EnergyLedger`, so without the guard the steps the player walked with the Digimon they
    /// actually have out would quietly cure — and wipe the care record of — one in the box.
    func testAFrozenDigimonNeitherFallsIllNorIsCured() {
        let sickening = makeDigimon(active: false)
        sickening.careMistakeCount = Sickness.careMistakesUntilSick
        sickening.updateSickness(energyEarnedToday: 0)
        XCTAssertEqual(sickening.healthStatus, .healthy)

        let ill = makeDigimon(active: false)
        ill.healthStatus = .sick
        ill.careMistakeCount = Sickness.careMistakesUntilSick
        ill.updateSickness(energyEarnedToday: Sickness.energyInADayToCure)
        XCTAssertEqual(ill.healthStatus, .sick)
        XCTAssertEqual(ill.careMistakeCount, Sickness.careMistakesUntilSick, "its record is not wiped")
    }

    func testAFrozenDigimonDoesNotAgeTowardDeath() {
        let frozen = makeDigimon(active: false)
        frozen.healthStatus = .sick
        frozen.sickSince = start

        // Ten times over the 72 hours an untreated illness takes to kill.
        let muchLater = start.addingTimeInterval(30 * FreezeClock.day)
        frozen.updateDeath(now: muchLater)

        XCTAssertEqual(frozen.healthStatus, .sick)
        XCTAssertNil(frozen.diedAt)
        XCTAssertFalse(frozen.claimDeathWarning(now: muchLater), "nor is a warning owed about it")
        XCTAssertNil(frozen.deathWarningSentAt, "and none is claimed on its behalf either")
    }

    /// The claim matters as much as the notice: a marker stamped while the Digimon is away would
    /// swallow the one its next real mess deserves.
    func testNoMessNoticeIsOwedOrClaimedForAFrozenDigimon() {
        let frozen = makeDigimon(active: false)
        frozen.poopCount = PoopClock.maximumPoops

        XCTAssertFalse(frozen.claimPoopNotification())
        XCTAssertFalse(frozen.poopNotified)
    }
}

// MARK: - AC2/AC3/AC4: the offset

final class FreezeOffsetTests: XCTestCase {
    private let start = FreezeClock.noon

    private func makeDigimon() -> GameState {
        GameState(currentDigimonId: "hero", stage: .child, now: start)
    }

    // MARK: the clock itself

    func testFreezingStampsFrozenSince() {
        let state = makeDigimon()
        XCTAssertNil(state.frozenSince)

        state.freeze(at: start)

        XCTAssertEqual(state.frozenSince, start)
        XCTAssertEqual(state.frozenDuration, 0, "nothing has elapsed yet")
    }

    func testABornFrozenDigimonIsFrozenFromBirth() {
        let born = GameState(currentDigimonId: "hero", isActive: false, now: start)
        XCTAssertEqual(born.frozenSince, start)
    }

    func testThawingBanksTheSpanItSpentAway() {
        let state = makeDigimon()
        state.freeze(at: start)
        state.thaw(at: start.addingTimeInterval(3 * FreezeClock.day))

        XCTAssertNil(state.frozenSince)
        XCTAssertEqual(state.frozenDuration, 3 * FreezeClock.day)
    }

    func testFrozenDurationAccumulatesOverSeveralSpells() {
        let state = makeDigimon()
        state.freeze(at: start)
        state.thaw(at: start.addingTimeInterval(3 * FreezeClock.day))
        state.freeze(at: start.addingTimeInterval(4 * FreezeClock.day))
        state.thaw(at: start.addingTimeInterval(9 * FreezeClock.day))

        XCTAssertEqual(state.frozenDuration, 8 * FreezeClock.day, "3 days away, then 5 more")
    }

    /// `activate` freezes every record it did not just thaw, so this runs on Digimon that have been
    /// in the box for weeks. Restamping would hand each of them the whole spell it had served.
    func testFreezingAnAlreadyFrozenDigimonDoesNotRestampItsClock() {
        let state = makeDigimon()
        state.freeze(at: start)
        state.freeze(at: start.addingTimeInterval(3 * FreezeClock.day))

        XCTAssertEqual(state.frozenSince, start)
    }

    func testThawingADigimonThatIsNotFrozenShiftsNothing() {
        let state = makeDigimon()
        state.thaw(at: start.addingTimeInterval(3 * FreezeClock.day))

        XCTAssertEqual(state.birthDate, start)
        XCTAssertEqual(state.frozenDuration, 0)
    }

    /// A `now` before the freeze means the device clock or the timezone moved, not that the Digimon
    /// came out before it went in.
    func testAClockThatWentBackwardsShiftsNothing() {
        let state = makeDigimon()
        state.freeze(at: start)
        state.thaw(at: start.addingTimeInterval(-FreezeClock.day))

        XCTAssertNil(state.frozenSince, "it is out either way")
        XCTAssertEqual(state.frozenDuration, 0)
        XCTAssertEqual(state.birthDate, start, "and it is no younger than it was")
    }

    // MARK: AC3/AC4 — the readings are exactly what they were

    /// Everything the acceptance criteria name, over the span they name, run through the REAL rules
    /// after the thaw rather than merely read back. Without the shift each of these assertions fails
    /// in the same direction: the frozen span arrives all at once.
    private func assertReadingsSurvive(_ days: Double, file: StaticString = #filePath, line: UInt = #line) {
        let state = makeDigimon()
        state.birthDate = start.addingTimeInterval(-5 * FreezeClock.day)
        state.stageEnteredDate = start.addingTimeInterval(-2 * FreezeClock.day)
        // One hour into the current hunger interval, and three of the four units already accrued:
        // one more hour of unfrozen time would be worth nothing, one more DAY would be worth the
        // rest of the meter.
        state.hunger = 3
        state.hungerUpdatedAt = start.addingTimeInterval(-FreezeClock.hour)
        state.healthDataLastSeen = start
        state.careMistakeCount = 1
        state.poopCount = 1
        state.poopUpdatedAt = start.addingTimeInterval(-FreezeClock.hour)

        let ageAtFreeze = start.timeIntervalSince(state.birthDate)
        let stageAgeAtFreeze = start.timeIntervalSince(state.stageEnteredDate)

        state.isActive = false
        state.freeze(at: start)

        let thawed = start.addingTimeInterval(days * FreezeClock.day)
        state.isActive = true
        state.thaw(at: thawed)

        XCTAssertEqual(thawed.timeIntervalSince(state.birthDate), ageAtFreeze, accuracy: 0.001,
                       "age", file: file, line: line)
        XCTAssertEqual(thawed.timeIntervalSince(state.stageEnteredDate), stageAgeAtFreeze,
                       accuracy: 0.001, "time in stage", file: file, line: line)

        // The rules a refresh runs the instant the Digimon comes out.
        state.advanceHunger(now: thawed)
        state.advancePoop(isAsleep: false, now: thawed)
        state.auditCareMistakes(now: thawed, health: .silent, calendar: FreezeClock.calendar)

        XCTAssertEqual(state.hunger, 3, "hunger", file: file, line: line)
        XCTAssertEqual(state.poopCount, 1, "poop", file: file, line: line)
        XCTAssertEqual(state.careMistakeCount, 1, "care mistakes", file: file, line: line)
    }

    func testAfterThreeDaysFrozenEveryReadingIsWhatItWasAtTheFreeze() {
        assertReadingsSurvive(3)
    }

    /// The same over thirty days, so the offset cannot be quietly clamped to a day — or to anything
    /// else short of the whole span.
    func testAfterThirtyDaysFrozenEveryReadingIsStillWhatItWasAtTheFreeze() {
        assertReadingsSurvive(30)
    }

    /// The gaps BETWEEN the shifted instants are preserved too, because they all move together —
    /// which is what makes an interrupted illness resume rather than restart or finish in the dark.
    func testAnIllnessResumesExactlyAsFarAlongAsItWasAtTheFreeze() {
        let state = makeDigimon()
        state.healthStatus = .sick
        state.sickSince = start.addingTimeInterval(-24 * FreezeClock.hour)

        state.isActive = false
        state.freeze(at: start)
        let thawed = start.addingTimeInterval(30 * FreezeClock.day)
        state.isActive = true
        state.thaw(at: thawed)

        state.updateDeath(now: thawed)
        XCTAssertEqual(state.healthStatus, .sick, "30 days in the box is not 30 days untreated")
        XCTAssertEqual(thawed.timeIntervalSince(state.sickSince!), 24 * FreezeClock.hour,
                       accuracy: 0.001, "still 24 hours in, with 48 to run")
        XCTAssertFalse(state.claimDeathWarning(now: thawed), "and the warning is still 24h off")

        // And the countdown really is only paused: 48 more hours of being out kills it.
        state.updateDeath(now: thawed.addingTimeInterval(48 * FreezeClock.hour))
        XCTAssertEqual(state.healthStatus, .dead)
    }

    /// The LOCAL-DAY keys are deliberately left where they are — they are not spans, they are
    /// "has this already been charged today", and a day that passed while the Digimon was in the box
    /// is over. A key dragged forward into today would forgive the first real mistake of the day the
    /// player is actually living in.
    func testTheLocalDayKeysAreNotShiftedForward() {
        let state = makeDigimon()
        state.recordRefusal(now: start, calendar: FreezeClock.calendar)
        state.recordBattleStarted(now: start, calendar: FreezeClock.calendar)
        let dayAtFreeze = FreezeClock.calendar.startOfDay(for: start)
        XCTAssertEqual(state.refusalDay, dayAtFreeze)

        state.isActive = false
        state.freeze(at: start)
        let thawed = start.addingTimeInterval(3 * FreezeClock.day)
        state.isActive = true
        state.thaw(at: thawed)

        XCTAssertEqual(state.refusalDay, dayAtFreeze, "still keyed to the day it happened on")
        XCTAssertEqual(state.battleDay, dayAtFreeze)
        XCTAssertEqual(state.battlesFought(now: thawed, calendar: FreezeClock.calendar), 0,
                       "so today reads as a fresh day, which is what it is")
    }

    // MARK: the rollback

    /// `GameStore.activate` needs a thaw it can take back if the save that was to make it durable
    /// fails, or the freeze clock and the `isActive` flag would disagree about a spell that never
    /// happened.
    func testUndoingAThawPutsEveryShiftedInstantBack() {
        let state = makeDigimon()
        state.birthDate = start.addingTimeInterval(-5 * FreezeClock.day)
        state.stageEnteredDate = start.addingTimeInterval(-2 * FreezeClock.day)
        state.hungerUpdatedAt = start.addingTimeInterval(-FreezeClock.hour)
        state.poopUpdatedAt = start.addingTimeInterval(-FreezeClock.hour)
        state.healthDataLastSeen = start
        state.sickSince = start
        state.awakeUntil = start
        state.deathWarningSentAt = start
        state.lightStateChangedAt = start
        state.energyLastEarned = EnergyRecency(strength: start, vitality: nil, spirit: start,
                                               stamina: nil)
        let before = snapshot(of: state)

        state.freeze(at: start)
        guard let change = state.thaw(at: start.addingTimeInterval(3 * FreezeClock.day)) else {
            return XCTFail("a frozen Digimon has something to thaw")
        }
        XCTAssertNotEqual(snapshot(of: state), before, "the thaw really did move things")

        state.undo(change)

        XCTAssertEqual(snapshot(of: state), before)
        XCTAssertEqual(state.frozenSince, start, "and it is in the box again")
        XCTAssertEqual(state.frozenDuration, 0, "with nothing banked")
    }

    func testUndoingAFreezeTakesTheStampBackOff() {
        let state = makeDigimon()
        guard let change = state.freeze(at: start) else {
            return XCTFail("an unfrozen Digimon has something to freeze")
        }
        state.undo(change)

        XCTAssertNil(state.frozenSince)
    }

    /// Every instant `shiftTimeline` is responsible for, in one comparable value — so a field added
    /// to the shift without being added here is caught by the "the thaw really did move things"
    /// assertion above going quiet.
    private func snapshot(of state: GameState) -> [Date?] {
        [state.birthDate, state.stageEnteredDate, state.hungerUpdatedAt, state.poopUpdatedAt,
         state.healthDataLastSeen, state.awakeUntil, state.sickSince, state.diedAt,
         state.deathWarningSentAt, state.lightStateChangedAt,
         state.energyLastEarned.strength, state.energyLastEarned.vitality,
         state.energyLastEarned.spirit, state.energyLastEarned.stamina]
    }
}

// MARK: - Through the store and the real refresh

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

/// Records what would have been delivered, in order.
@MainActor
private final class SpyDeliverer: PetNotificationDelivering {
    private(set) var delivered: [PetNotification] = []
    private(set) var scheduled: [PetNotification] = []

    func deliver(_ notification: PetNotification) { delivered.append(notification) }
    func deliver(_ notification: PetNotification, at date: Date) { scheduled.append(notification) }
    func cancel(_ kind: NotificationKind) {}

    var bodies: [String] { (delivered + scheduled).map(\.body) }
}

@MainActor
final class FreezeThroughTheStoreTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("Freeze.store") }
    /// The store `seedBox` built, held for the whole test. Held for two reasons: a `GameStore` that
    /// goes out of scope resets its context and every `GameState` fetched from it becomes unusable,
    /// and `makeModel` hands this same instance to the model — see there for why a second one on the
    /// same file would make the assertions vacuous.
    private var seedStore: GameStore?

    private let start = FreezeClock.noon

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FreezeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        seedStore = nil
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// `hero` evolves into `champ` on 5 strength once its stage gate has opened. Names are distinct
    /// so a notification body or a complication can be attributed to one Digimon and not the other.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 5, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon",
                          evolutions: [EvolutionEdge(to: "champ", requiredEnergy: .strength,
                                                     minEnergy: 5, maxCareMistakes: 99)]),
            EvolutionNode(id: "champ", displayName: "Champ", stage: .babyII, spriteFile: "Koromon")
        ])
    }

    /// - Parameter spy: nil for a fresh one nothing asserts on. Nil rather than a default value
    ///   because a default argument is evaluated in the CALLER's context, which is not this actor.
    private func makeModel(now: @escaping () -> Date, spy: SpyDeliverer? = nil)
        -> MainScreenModel {
        // THE MODEL IS HANDED THE SEEDED STORE ITSELF rather than a second one on the same file,
        // and that is what makes every assertion below about the frozen record mean anything: a
        // second container would give the test its own copy, so a refresh that DID move the Digimon
        // in the box would leave the test's copy — and the test — looking exactly like success.
        let store = seedStore
        let model = MainScreenModel(
            makeStore: { try store ?? GameStore(url: self.storeURL) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: FreezeClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: FreezeClock.calendar)
            ),
            calendar: FreezeClock.calendar,
            now: now,
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05,
            notificationDeliverer: spy ?? SpyDeliverer()
        )
        // Kept out of the shared app-group directory, so a snapshot published by a test cannot be
        // read back by another one — or by the app.
        model.complicationDirectory = directory
        return model
    }

    /// A Digimon at `hero` whose stage gate is long open, its care markers stamped at `at` so a
    /// refresh owes it nothing, and its light already out so US-100's nudge stays out of the way.
    private func settle(_ state: GameState, at: Date) {
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = at.addingTimeInterval(-6 * FreezeClock.day)
        state.stageEnteredDate = at.addingTimeInterval(-6 * FreezeClock.day)
        state.healthDataLastSeen = at
        state.hungerUpdatedAt = at
        state.poopUpdatedAt = at
        state.setLight(.off, now: at.addingTimeInterval(-FreezeClock.day))
    }

    /// A box holding the Digimon the player has out and one frozen beside it. The frozen one is
    /// returned second.
    @discardableResult
    private func seedBox(configureFrozen: (GameState) -> Void = { _ in })
        throws -> (GameStore, GameState, GameState) {
        let store = try GameStore(url: storeURL)
        let out = try store.loadOrCreate(digitamaId: "egg", now: start)
        settle(out, at: start)

        let boxed = GameState(currentDigimonId: "egg", isActive: false, now: start)
        store.container.mainContext.insert(boxed)
        settle(boxed, at: start)
        configureFrozen(boxed)

        try store.save()
        seedStore = store
        return (store, out, boxed)
    }

    // MARK: AC2 — the clock survives a relaunch

    func testTheFreezeClockRoundTripsThroughDisk() throws {
        let thawTime = start.addingTimeInterval(3 * FreezeClock.day)
        do {
            let (store, out, boxed) = try seedBox()
            try store.activate(boxed, now: thawTime)
            XCTAssertNotNil(out.frozenSince, "the one that was out went into the box")
        }
        // Closed before reopening, so what is read below came off DISK rather than out of the
        // first container's cache.
        seedStore = nil

        let reopened = try GameStore(url: storeURL)
        let box = try reopened.allStates()
        let thawed = try XCTUnwrap(reopened.activeState())
        let frozen = try XCTUnwrap(box.first { !$0.isActive })

        XCTAssertNil(thawed.frozenSince)
        XCTAssertEqual(thawed.frozenDuration, 3 * FreezeClock.day, "banked, and on disk")
        XCTAssertEqual(frozen.frozenSince, thawTime)
        XCTAssertEqual(frozen.frozenDuration, 0)
    }

    /// Activating moves both halves of the fact at once: `isActive` and the freeze clock. A record
    /// the store does not hold is refused before either is touched.
    func testARefusedActivateLeavesTheFreezeClockExactlyAsItStood() throws {
        let (store, out, _) = try seedBox()
        let alien = GameState(currentDigimonId: "egg", now: start)
        let otherStore = try GameStore(url: directory.appendingPathComponent("Other.store"))
        otherStore.container.mainContext.insert(alien)
        try otherStore.save()

        XCTAssertThrowsError(try store.activate(alien, now: start.addingTimeInterval(FreezeClock.day)))

        XCTAssertTrue(out.isActive)
        XCTAssertNil(out.frozenSince, "still out, and never stamped")
        XCTAssertEqual(out.frozenDuration, 0)
    }

    /// The one already out is thawed as a no-op, so tapping the row the player is on cannot shift a
    /// timeline.
    func testActivatingTheDigimonAlreadyOutShiftsNothing() throws {
        let (store, out, _) = try seedBox()
        let birth = out.birthDate

        try store.activate(out, now: start.addingTimeInterval(3 * FreezeClock.day))

        XCTAssertEqual(out.birthDate, birth)
        XCTAssertEqual(out.frozenDuration, 0)
    }

    // MARK: AC1/AC5 — the refresh processes the active Digimon only

    /// AC5 through the code that really runs. The frozen Digimon is seeded starving, filthy, days
    /// behind on its health data and holding the energy to evolve — every one of which the refresh
    /// would act on if it reached it.
    ///
    /// WHAT THIS PROVES, precisely: that the refresh never REACHES the record in the box. Measured,
    /// by deleting every `isActive` guard and re-running: this test still passes, because
    /// `MainScreenModel` is built on `loadOrCreate` and so only ever holds the active record. That
    /// is the structural fact AC5 asks about, and it is worth pinning here because a later story
    /// that hands the model the whole box would break it. The GUARDS are pinned separately, by
    /// `FreezeAccrualTests` — all seven of which fail when they are removed.
    func testARefreshTouchesTheActiveDigimonOnly() async throws {
        var clock = start
        let (store, out, boxed) = try seedBox { frozen in
            frozen.stageEnergy = EnergyTotals(strength: 50, vitality: 0, spirit: 0, stamina: 0)
            frozen.hunger = HungerClock.maximumHunger
            frozen.poopCount = PoopClock.maximumPoops
        }
        // The one out has the same energy, so what separates them is only which is in the box.
        out.stageEnergy = EnergyTotals(strength: 50, vitality: 0, spirit: 0, stamina: 0)
        try store.save()

        let model = makeModel(now: { clock })
        await model.start()
        clock = start.addingTimeInterval(5 * FreezeClock.day)
        await model.refresh()

        XCTAssertEqual(model.state?.currentDigimonId, "champ", "the one out evolved")
        XCTAssertEqual(boxed.currentDigimonId, "hero", "the one in the box was never evaluated")
        XCTAssertEqual(boxed.hunger, HungerClock.maximumHunger, "no hungrier than it went in")
        XCTAssertEqual(boxed.hungerUpdatedAt, start, "its clock was not even restamped")
        XCTAssertEqual(boxed.poopCount, PoopClock.maximumPoops)
        XCTAssertEqual(boxed.careMistakeCount, 0, "five days of silence charged it nothing")
        XCTAssertEqual(boxed.healthStatus, .healthy)
    }

    /// AC5's other half: a background wake runs the very same `refresh()`, so it inherits the same
    /// answer rather than having a second, weaker version of the rule.
    func testABackgroundRefreshAlsoTouchesTheActiveDigimonOnly() async throws {
        var clock = start
        let (_, _, boxed) = try seedBox { $0.hunger = 1 }

        let model = makeModel(now: { clock })
        await model.start()
        let coordinator = BackgroundRefreshCoordinator(model: model,
                                                       scheduler: SpyScheduler(),
                                                       observer: SpyObserver(),
                                                       now: { clock })
        clock = start.addingTimeInterval(5 * FreezeClock.day)
        await coordinator.performRefresh()

        XCTAssertEqual(boxed.hunger, 1)
        XCTAssertEqual(boxed.careMistakeCount, 0)
        XCTAssertGreaterThan(model.state?.hunger ?? 0, 1, "while the one out really did get hungry")
    }

    // MARK: AC6 — the complication

    func testTheComplicationSnapshotPublishesTheActiveDigimon() async throws {
        var clock = start
        let (store, _, boxed) = try seedBox()
        boxed.currentDigimonId = "champ"
        try store.save()

        let model = makeModel(now: { clock })
        await model.start()
        clock = start.addingTimeInterval(FreezeClock.hour)
        await model.refresh()

        XCTAssertEqual(model.complicationSnapshot?.displayName, "Hero")

        // And after a switch it publishes the OTHER one, so "the active Digimon" is really what it
        // tracks rather than the first record in the box.
        try store.activate(boxed, now: clock)
        let after = makeModel(now: { clock })
        await after.start()

        XCTAssertEqual(after.complicationSnapshot?.displayName, "Champ")
    }

    // MARK: AC7 — notifications

    /// The frozen Digimon is seeded owed all three notices the game can send about one: it is one
    /// refresh from falling ill (the sickness notice), its screen is already full (the mess notice)
    /// and it holds the energy to evolve past an open stage gate (the evolution notice).
    ///
    /// **Every one of those is owed the moment the refresh runs, with nothing elapsed**, and that is
    /// deliberate: an hour is all this test moves the clock, so the Digimon the player really has
    /// out cannot fall ill or get filthy on its own and stand in for the one in the box. A first
    /// draft of this test advanced five days and failed for exactly that reason.
    func testNoNotificationIsEverSentAboutAFrozenDigimon() async throws {
        var clock = start
        let (store, _, boxed) = try seedBox { frozen in
            frozen.careMistakeCount = Sickness.careMistakesUntilSick
            frozen.poopCount = PoopClock.maximumPoops
            frozen.stageEnergy = EnergyTotals(strength: 50, vitality: 0, spirit: 0, stamina: 0)
        }
        try store.save()

        let spy = SpyDeliverer()
        let model = makeModel(now: { clock }, spy: spy)
        await model.start()
        clock = start.addingTimeInterval(FreezeClock.hour)
        await model.refresh()

        XCTAssertEqual(spy.delivered, [], "nothing was said about the Digimon in the box")
        XCTAssertEqual(spy.bodies, [], "including nothing queued for later")
        XCTAssertEqual(boxed.healthStatus, .healthy, "and it was not made ill in the first place")
        XCTAssertEqual(boxed.currentDigimonId, "hero", "nor evolved")
        XCTAssertFalse(boxed.poopNotified, "nor was its mess notice claimed on its behalf")
    }
}

/// The two collaborators a coordinator needs and cannot have in a test bundle. Nothing here is
/// asserted on — the coordinator is only used for the path it shares with a foregrounding.
@MainActor
private final class SpyScheduler: BackgroundRefreshScheduling {
    func scheduleRefresh(at date: Date) {}
}

@MainActor
private final class SpyObserver: HealthUpdateObserving {
    func startObserving(_ metrics: [HealthMetric], onUpdate: @escaping () -> Void) {}
}
