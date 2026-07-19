import Foundation
import XCTest

@testable import DigiVPet

/// US-035 — local notifications and their toggles.
///
/// Three layers, the shape US-028/US-029 established: `NotificationRuleTests` pins the two gates
/// (the toggle and the sleep window) in isolation, `DeathWarningRuleTests` pins the 24-hours-left
/// moment, and `NotificationDeliveryTests` drives the REAL `refresh()` against a real store so that
/// "a notification fires on evolution" is asserted about the code that actually evolves the
/// Digimon, not about a hand-built call.
///
/// Everything is asserted through a spy deliverer, because a suppressed notification leaves no
/// other trace: the only difference between "correctly suppressed" and "silently broken" is what
/// the spy did NOT receive.
///
/// No test waits real time — every entry point takes an injected clock.

private enum NoteClock {
    /// Los Angeles, as the sickness and death suites use: a window computed in the wrong time zone
    /// is caught rather than passing by coincidence. It matters more here than usual, because the
    /// sleep window is a time OF DAY.
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

    /// Inside the 22:00–07:00 fallback sleep window, which is the window a model with no HealthKit
    /// sleep history gets — i.e. every model in this file.
    static let nightTime = at("2026-03-10 23:30")
    /// Outside it, by a wide margin.
    static let dayTime = at("2026-03-10 12:00")
}

/// Records what would have been delivered, in order.
@MainActor
private final class SpyDeliverer: PetNotificationDelivering {
    private(set) var delivered: [PetNotification] = []
    /// What was withdrawn, in order. Kept separate from `delivered` rather than removing from it,
    /// so a test can tell "sent then cancelled" from "never sent" — US-054 AC5 is about the first.
    private(set) var cancelled: [NotificationKind] = []

    func deliver(_ notification: PetNotification) {
        delivered.append(notification)
    }

    func cancel(_ kind: NotificationKind) {
        cancelled.append(kind)
    }

    var kinds: [NotificationKind] { delivered.map(\.kind) }

    func received(_ kind: NotificationKind) -> Bool { kinds.contains(kind) }
}

/// A settings object over a throwaway suite, so a test neither reads nor writes the simulator's real
/// preferences — which would otherwise leak a toggle from one test method into the next.
@MainActor
private func isolatedSettings() -> NotificationSettings {
    let name = "NotificationTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        preconditionFailure("Could not open a test defaults suite")
    }
    return NotificationSettings(defaults: defaults)
}

// MARK: - The two gates

@MainActor
final class NotificationRuleTests: XCTestCase {
    /// AC3's default: a fresh install has every kind switched ON, and each is switched
    /// INDIVIDUALLY — turning one off leaves the other two alone.
    func testEveryKindDefaultsOnAndTogglesIndependently() {
        let settings = isolatedSettings()
        for kind in NotificationKind.allCases {
            XCTAssertTrue(settings.isEnabled(kind), "\(kind.rawValue) should default on")
        }

        settings.setEnabled(false, for: .sickness)

        XCTAssertFalse(settings.isEnabled(.sickness))
        XCTAssertTrue(settings.isEnabled(.evolution), "turning sickness off must not touch evolution")
        XCTAssertTrue(settings.isEnabled(.deathWarning))
    }

    /// AC3: a kind switched off is not delivered, and switching it back on restores it. Asserted
    /// awake, so the sleep gate cannot be what is doing the suppressing.
    func testASwitchedOffKindIsNotDelivered() {
        let settings = isolatedSettings()
        let spy = SpyDeliverer()
        let dispatcher = NotificationDispatcher(settings: settings, deliverer: spy)

        settings.setEnabled(false, for: .evolution)
        XCTAssertFalse(dispatcher.send(.evolution, body: "b", isAsleep: false))
        XCTAssertEqual(spy.delivered, [], "a switched-off kind reaches the system at all")

        settings.setEnabled(true, for: .evolution)
        XCTAssertTrue(dispatcher.send(.evolution, body: "b", isAsleep: false))
        XCTAssertEqual(spy.kinds, [.evolution])
    }

    /// AC4 AND AC5, as one table: asleep suppresses evolution and sickness but NOT the death
    /// warning, and awake delivers all three. The awake column is the control — without it a
    /// dispatcher that suppressed everything always would pass the sleep half.
    func testSleepSuppressesEverythingExceptTheDeathWarning() {
        for (isAsleep, expected) in [(false, NotificationKind.allCases), (true, [.deathWarning])] {
            let spy = SpyDeliverer()
            let dispatcher = NotificationDispatcher(settings: isolatedSettings(), deliverer: spy)

            for kind in NotificationKind.allCases {
                dispatcher.send(kind, body: "b", isAsleep: isAsleep)
            }

            XCTAssertEqual(spy.kinds, expected, "asleep: \(isAsleep)")
        }
    }

    /// The exception is pinned to the death warning specifically, so a later kind added with
    /// `firesWhileAsleep` true has to be a deliberate act rather than a copied default.
    func testOnlyTheDeathWarningFiresWhileAsleep() {
        XCTAssertEqual(NotificationKind.allCases.filter(\.firesWhileAsleep), [.deathWarning])
    }
}

// MARK: - The 24-hours-left moment

final class DeathWarningRuleTests: XCTestCase {
    private func sickState(hoursSick: Double, now: Date) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .child,
                              now: now.addingTimeInterval(-10 * 24 * NoteClock.hour))
        state.healthStatus = .sick
        state.sickSince = now.addingTimeInterval(-hoursSick * NoteClock.hour)
        return state
    }

    /// AC2's timing: the warning is due at 48 hours sick, which is 24 hours before the 72-hour
    /// death — and 47 hours is not yet. The boundary is asserted from both sides, so this cannot be
    /// passing under a looser "sick for a while" rule.
    func testTheWarningIsDueTwentyFourHoursBeforeDeathAndNotBefore() {
        for (hoursSick, expected) in [(0.0, false), (47, false), (47.9, false),
                                      (48, true), (60, true)] {
            let now = NoteClock.at("2026-03-10 12:00")
            let state = sickState(hoursSick: hoursSick, now: now)

            XCTAssertEqual(state.claimDeathWarning(now: now), expected, "\(hoursSick) hours sick")
        }
    }

    /// The lead time is the named constant, not a number written into the rule.
    func testTheLeadTimeIsTwentyFourHours() {
        XCTAssertEqual(Death.secondsWarningBeforeDeath, 24 * 60 * 60)
        XCTAssertEqual(Death.secondsSickUntilWarning, 48 * 60 * 60)
    }

    /// Claimed once per illness, however many refreshes run: a user opening the app five times on
    /// the last day is told their Digimon is dying once.
    func testTheWarningIsClaimedOnlyOnce() {
        let now = NoteClock.at("2026-03-10 12:00")
        let state = sickState(hoursSick: 50, now: now)

        XCTAssertTrue(state.claimDeathWarning(now: now))
        XCTAssertFalse(state.claimDeathWarning(now: now.addingTimeInterval(NoteClock.hour)))
        XCTAssertFalse(state.claimDeathWarning(now: now.addingTimeInterval(20 * NoteClock.hour)))
    }

    /// A cure clears the claim, so the NEXT illness gets its own warning rather than inheriting a
    /// spent one — which would leave the user unwarned for the illness that actually kills.
    func testACureRearmsTheWarningForTheNextIllness() {
        let now = NoteClock.at("2026-03-10 12:00")
        let state = sickState(hoursSick: 50, now: now)
        XCTAssertTrue(state.claimDeathWarning(now: now))

        // Cured: `updateDeath`'s healthy branch is what clears both markers.
        state.healthStatus = .healthy
        state.updateDeath(now: now)
        XCTAssertNil(state.deathWarningSentAt)

        // Ill again, and 48 hours into THIS illness.
        let later = now.addingTimeInterval(10 * 24 * NoteClock.hour)
        state.healthStatus = .sick
        state.sickSince = later.addingTimeInterval(-48 * NoteClock.hour)
        XCTAssertTrue(state.claimDeathWarning(now: later))
    }

    /// A Digimon already dead is past warning: the memorial is the message.
    func testADeadDigimonIsNotWarned() {
        let now = NoteClock.at("2026-03-10 12:00")
        let state = sickState(hoursSick: 80, now: now)
        state.updateDeath(now: now)
        XCTAssertEqual(state.healthStatus, .dead)

        XCTAssertFalse(state.claimDeathWarning(now: now))
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
final class NotificationDeliveryTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotificationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// An egg that hatches into `hero` on 5 energy, and a `hero` that evolves into `champ` on 5
    /// more — so an evolution can be provoked without any health data at all, by seeding the
    /// energy directly.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 5, maxCareMistakes: 99)]),
            // `requiredEnergy` is what makes this an EVOLUTION edge rather than a hatch edge — an
            // edge without one never qualifies in `EvolutionEngine`, by design.
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon",
                          evolutions: [EvolutionEdge(to: "champ", requiredEnergy: .strength,
                                                     minEnergy: 5, maxCareMistakes: 99)]),
            EvolutionNode(id: "champ", displayName: "Champ", stage: .babyII, spriteFile: "Koromon")
        ])
    }

    private func makeModel(url: URL, now: Date, spy: SpyDeliverer,
                           settings: NotificationSettings) -> MainScreenModel {
        MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: NoteClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: NoteClock.calendar)
            ),
            calendar: NoteClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05,
            notificationSettings: settings,
            notificationDeliverer: spy
        )
    }

    /// Seeds a saved game at `hero` with enough stage energy to evolve on the next refresh, and its
    /// stage gate already open. Care markers are stamped at `now` so the audit adds nothing.
    private func seedEvolvingGame(url: URL, now: Date) throws {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        state.stageEnteredDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        state.stageEnergy = EnergyTotals(strength: 50, vitality: 0, spirit: 0, stamina: 0)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        try store.save()
    }

    /// Seeds a game at `hero` that is one care mistake short of nothing — three mistakes already
    /// banked and still `healthy`, so the very next refresh is the one that diagnoses it.
    private func seedSickeningGame(url: URL, now: Date) throws {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        // Far enough in the past that the stage gate is open but there is no energy to evolve on,
        // so the only thing this refresh can announce is the illness.
        state.stageEnteredDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        state.careMistakeCount = Sickness.careMistakesUntilSick
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        try store.save()
    }

    /// Seeds a game at `hero` that has been sick for `hoursSick` — 48 puts the death warning due on
    /// the next refresh.
    private func seedDyingGame(url: URL, now: Date, hoursSick: Double) throws {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        state.stageEnteredDate = now.addingTimeInterval(-6 * 24 * NoteClock.hour)
        state.healthStatus = .sick
        state.careMistakeCount = Sickness.careMistakesUntilSick
        state.sickSince = now.addingTimeInterval(-hoursSick * NoteClock.hour)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        try store.save()
    }

    // MARK: AC1 — evolution

    /// AC1 through the real evolution path: the refresh that moves `hero` to `champ` is the one
    /// that notifies, and the body names both forms.
    func testEvolvingFiresANotification() async throws {
        let url = storeURL("Evolve")
        try seedEvolvingGame(url: url, now: NoteClock.dayTime)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "champ", "the control: it really evolved")
        XCTAssertEqual(spy.kinds, [.evolution])
        XCTAssertEqual(spy.delivered.first?.body, "Hero digivolved into Champ!")
    }

    /// AC3 end to end: with the evolution toggle off, the same evolution happens and says nothing.
    func testEvolvingSaysNothingWhenTheToggleIsOff() async throws {
        let url = storeURL("EvolveMuted")
        try seedEvolvingGame(url: url, now: NoteClock.dayTime)
        let spy = SpyDeliverer()
        let settings = isolatedSettings()
        settings.setEnabled(false, for: .evolution)
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: settings)

        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "champ", "the evolution itself is unaffected")
        XCTAssertEqual(spy.delivered, [])
    }

    // MARK: AC2 — sickness onset

    /// AC2's first half: the refresh that diagnoses the illness notifies, and a SECOND refresh over
    /// the same illness does not — the notification is owed for the transition, not for being ill.
    func testFallingIllFiresOnceAndNotAgain() async throws {
        let url = storeURL("Sicken")
        try seedSickeningGame(url: url, now: NoteClock.dayTime)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()
        XCTAssertEqual(model.state?.healthStatus, .sick, "the control: it really fell ill")
        XCTAssertEqual(spy.kinds, [.sickness])

        await model.refresh()
        XCTAssertEqual(spy.kinds, [.sickness], "still ill is not news")
    }

    // MARK: AC2 — the death warning

    /// AC2's second half, through the real `refresh()`: 48 hours sick warns, 47 does not.
    func testTheDeathWarningFiresAtFortyEightHoursSickAndNotAtFortySeven() async throws {
        let dueURL = storeURL("Warned")
        try seedDyingGame(url: dueURL, now: NoteClock.dayTime, hoursSick: 48)
        let dueSpy = SpyDeliverer()
        let due = makeModel(url: dueURL, now: NoteClock.dayTime, spy: dueSpy,
                            settings: isolatedSettings())
        await due.start()
        XCTAssertEqual(dueSpy.kinds, [.deathWarning])

        let earlyURL = storeURL("Unwarned")
        try seedDyingGame(url: earlyURL, now: NoteClock.dayTime, hoursSick: 47)
        let earlySpy = SpyDeliverer()
        let early = makeModel(url: earlyURL, now: NoteClock.dayTime, spy: earlySpy,
                              settings: isolatedSettings())
        await early.start()
        XCTAssertEqual(earlySpy.delivered, [], "the control: one hour short says nothing")
    }

    /// The claim is SAVED, so relaunching the app on the last day does not warn a second time.
    /// This is the one part of the rule an in-memory flag would get wrong.
    func testTheDeathWarningIsNotRepeatedOnTheNextLaunch() async throws {
        let url = storeURL("WarnedOnce")
        try seedDyingGame(url: url, now: NoteClock.dayTime, hoursSick: 48)

        let firstSpy = SpyDeliverer()
        let first = makeModel(url: url, now: NoteClock.dayTime, spy: firstSpy,
                              settings: isolatedSettings())
        await first.start()
        XCTAssertEqual(firstSpy.kinds, [.deathWarning])

        // A whole new model over the same store: a fresh launch, an hour later.
        let laterSpy = SpyDeliverer()
        let later = makeModel(url: url, now: NoteClock.dayTime.addingTimeInterval(NoteClock.hour),
                              spy: laterSpy, settings: isolatedSettings())
        await later.start()
        XCTAssertEqual(laterSpy.delivered, [], "the claim survived the relaunch")
    }

    // MARK: AC4 and AC5 — asleep, through the real model

    /// AC5, the required test, driven through the REAL sleep derivation rather than by setting
    /// `isAsleep` by hand: at 23:30 the model has no sleep history, so it takes the 22:00–07:00
    /// fallback window and is genuinely asleep. The sickness notification is suppressed; the death
    /// warning, due in the same refresh, is not.
    func testDuringSleepTheSicknessNoticeIsSuppressedButTheDeathWarningIsNot() async throws {
        // One game that both falls ill and crosses the 48-hour mark is impossible — an illness 48
        // hours old is one the Digimon already had — so this is two games at the same night hour.
        let sickURL = storeURL("AsleepSicken")
        try seedSickeningGame(url: sickURL, now: NoteClock.nightTime)
        let sickSpy = SpyDeliverer()
        let sickening = makeModel(url: sickURL, now: NoteClock.nightTime, spy: sickSpy,
                                  settings: isolatedSettings())
        await sickening.start()

        XCTAssertTrue(sickening.isAsleep, "the control: 23:30 is inside the fallback sleep window")
        XCTAssertEqual(sickening.state?.healthStatus, .sick,
                       "the control: it really fell ill, so there WAS something to suppress")
        XCTAssertEqual(sickSpy.delivered, [], "AC4: no notice while asleep")

        let dyingURL = storeURL("AsleepDying")
        try seedDyingGame(url: dyingURL, now: NoteClock.nightTime, hoursSick: 48)
        let dyingSpy = SpyDeliverer()
        let dying = makeModel(url: dyingURL, now: NoteClock.nightTime, spy: dyingSpy,
                              settings: isolatedSettings())
        await dying.start()

        XCTAssertTrue(dying.isAsleep)
        XCTAssertEqual(dyingSpy.kinds, [.deathWarning],
                       "AC4's exception: the death warning wakes the user")
    }

    /// The other half of AC5's control: the same sickening game in daylight DOES notify, so the
    /// suppression above is the sleep window and not the seeding.
    func testTheSameIllnessDoesNotifyWhenAwake() async throws {
        let url = storeURL("AwakeSicken")
        try seedSickeningGame(url: url, now: NoteClock.dayTime)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()

        XCTAssertFalse(model.isAsleep)
        XCTAssertEqual(spy.kinds, [.sickness])
    }

    // MARK: US-054 — the mess notice

    /// Seeds a healthy `hero` whose poop clock was last stamped `hoursOfMess` ago, so the first
    /// refresh accrues the mess through the SHIPPED rule rather than hand-setting `poopCount` —
    /// 12 hours is four 3h intervals, i.e. exactly `PoopClock.maximumPoops`.
    ///
    /// Every other care marker is stamped at `now` so the audit charges nothing: the only thing a
    /// refresh over this game can have to say is about the mess.
    private func seedMessyGame(url: URL, now: Date, hoursOfMess: Double) throws {
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "egg", now: now)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.birthDate = now.addingTimeInterval(-6 * NoteClock.hour * 24)
        state.stageEnteredDate = now.addingTimeInterval(-6 * NoteClock.hour * 24)
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        state.poopCount = 0
        state.poopUpdatedAt = now.addingTimeInterval(-hoursOfMess * NoteClock.hour)
        try store.save()
    }

    /// AC1 and AC4 together, through the real `refresh()`: the refresh that fills the screen
    /// notifies, and a second refresh over the same uncleaned mess does not.
    func testAFullScreenNotifiesOnceAndNotAgain() async throws {
        let url = storeURL("Messy")
        try seedMessyGame(url: url, now: NoteClock.dayTime, hoursOfMess: 12)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()

        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops, "the control: it really filled")
        XCTAssertEqual(spy.kinds, [.poop])
        XCTAssertEqual(spy.delivered.first?.body, "Hero's screen is filthy. Clean it before it gets sick.")

        await model.refresh()
        XCTAssertEqual(spy.kinds, [.poop], "a mess that is still there is not new news")
    }

    /// AC4's harder half: the claim is SAVED, so relaunching onto the same uncleaned mess does not
    /// notify a second time. An in-memory flag would pass the test above and fail this one.
    func testTheMessNoticeIsNotRepeatedOnTheNextLaunch() async throws {
        let url = storeURL("MessyRelaunch")
        try seedMessyGame(url: url, now: NoteClock.dayTime, hoursOfMess: 12)

        let firstSpy = SpyDeliverer()
        let first = makeModel(url: url, now: NoteClock.dayTime, spy: firstSpy,
                              settings: isolatedSettings())
        await first.start()
        XCTAssertEqual(firstSpy.kinds, [.poop])

        // A whole new model over the same store: a fresh launch, an hour later.
        let laterSpy = SpyDeliverer()
        let later = makeModel(url: url, now: NoteClock.dayTime.addingTimeInterval(NoteClock.hour),
                              spy: laterSpy, settings: isolatedSettings())
        await later.start()

        XCTAssertEqual(later.poopCount, PoopClock.maximumPoops, "the control: still filthy")
        XCTAssertEqual(laterSpy.delivered, [], "the mess was already announced")
    }

    /// The control for AC1's threshold: nine hours is three poops, one short of the ceiling, and
    /// says nothing. Without this the test above would pass under a "there is any poop at all" rule.
    func testAPartlyDirtyScreenSaysNothing() async throws {
        let url = storeURL("PartlyMessy")
        try seedMessyGame(url: url, now: NoteClock.dayTime, hoursOfMess: 9)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()

        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops - 1, "the control: one short")
        XCTAssertEqual(spy.delivered, [])
    }

    /// AC3: with the Mess toggle off, the screen still fills and nothing is delivered.
    func testTheMessNoticeIsSuppressedWhenTheToggleIsOff() async throws {
        let url = storeURL("MessyMuted")
        try seedMessyGame(url: url, now: NoteClock.dayTime, hoursOfMess: 12)
        let spy = SpyDeliverer()
        let settings = isolatedSettings()
        settings.setEnabled(false, for: .poop)
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: settings)

        await model.start()

        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops, "the mess itself is unaffected")
        XCTAssertEqual(spy.delivered, [])
    }

    /// AC5: cleaning withdraws the notice that asked for it.
    func testCleaningCancelsTheMessNotice() async throws {
        let url = storeURL("MessyCleaned")
        try seedMessyGame(url: url, now: NoteClock.dayTime, hoursOfMess: 12)
        let spy = SpyDeliverer()
        let model = makeModel(url: url, now: NoteClock.dayTime, spy: spy, settings: isolatedSettings())

        await model.start()
        XCTAssertEqual(spy.kinds, [.poop])
        XCTAssertEqual(spy.cancelled, [], "nothing is withdrawn before it is cleaned")

        XCTAssertTrue(model.clean())

        XCTAssertEqual(model.poopCount, 0)
        XCTAssertEqual(spy.cancelled, [.poop])
    }

    /// AC4's other edge: cleaning re-arms the claim, so a screen left to fill AGAIN is a new mess
    /// and earns its own notice. Without the re-arm a user who cleans once is never told again.
    func testARefilledScreenIsNotifiedAfresh() async throws {
        let url = storeURL("MessyRefilled")
        // Morning rather than `dayTime`, because this test runs the clock twelve hours forward and
        // noon plus twelve is midnight — inside the 22:00–07:00 fallback sleep window, where poop
        // is PAUSED and the screen would never refill. 08:00 + 12h = 20:00 is still awake.
        let morning = NoteClock.at("2026-03-10 08:00")
        try seedMessyGame(url: url, now: morning, hoursOfMess: 12)
        let spy = SpyDeliverer()
        var currentTime = morning
        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: NoteClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: NoteClock.calendar)
            ),
            calendar: NoteClock.calendar,
            now: { currentTime },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05,
            notificationSettings: isolatedSettings(),
            notificationDeliverer: spy
        )

        await model.start()
        XCTAssertEqual(spy.kinds, [.poop])

        XCTAssertTrue(model.clean())
        // Twelve more hours: the clock restarted at the clean, so this fills the screen a second
        // time.
        currentTime = morning.addingTimeInterval(12 * NoteClock.hour)
        await model.refresh()

        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops, "the control: it filled again")
        XCTAssertEqual(spy.kinds, [.poop, .poop], "a second mess is a second notice")
    }
}

// MARK: - The mess claim, without a model

/// The threshold and the re-arm, asserted directly on `GameState` — the model tests above drive the
/// same rule through `refresh()`, but these pin the boundary without a store or a clock.
final class PoopNotificationClaimTests: XCTestCase {
    private func state(poopCount: Int) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .child,
                              now: NoteClock.at("2026-03-01 12:00"))
        state.poopCount = poopCount
        return state
    }

    /// The claim is owed at the ceiling and at nothing below it.
    func testOnlyAFullScreenIsClaimed() {
        for count in 0...PoopClock.maximumPoops {
            let expected = count >= PoopClock.maximumPoops
            XCTAssertEqual(state(poopCount: count).claimPoopNotification(), expected,
                           "\(count) poops")
        }
    }

    /// Claimed once however many times it is asked, which is what makes AC4 hold across refreshes.
    func testTheClaimIsTakenOnlyOnce() {
        let messy = state(poopCount: PoopClock.maximumPoops)

        XCTAssertTrue(messy.claimPoopNotification())
        XCTAssertFalse(messy.claimPoopNotification())
        XCTAssertFalse(messy.claimPoopNotification())
    }

    /// Dropping off the ceiling re-arms it: the next mess is claimed afresh.
    func testCleaningRearmsTheClaim() {
        let messy = state(poopCount: PoopClock.maximumPoops)
        XCTAssertTrue(messy.claimPoopNotification())

        messy.poopCount = 0
        XCTAssertFalse(messy.claimPoopNotification(), "an empty screen owes nothing")
        XCTAssertFalse(messy.poopNotified, "and the marker is re-armed by asking")

        messy.poopCount = PoopClock.maximumPoops
        XCTAssertTrue(messy.claimPoopNotification())
    }

    /// A fresh game has never been notified — the default matters because `poopNotified` is backed
    /// by an optional for migration, and a save written before US-054 must read as "not yet told"
    /// rather than as "already told", which would swallow the first notice on every upgraded game.
    func testAFreshGameHasNotBeenNotified() {
        XCTAssertFalse(state(poopCount: 0).poopNotified)
    }
}
