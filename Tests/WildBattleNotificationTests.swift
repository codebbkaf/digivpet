import Foundation
import XCTest

@testable import DigiVPet

/// US-205 — a best-effort background step check that raises a wild-battle notification.
///
/// Driven against the real `MainScreenModel` over a real store, because every criterion is about
/// what a background `refresh(background:)` does with the map's saved counter and the saved
/// "already nudged" marker. No test waits real time: the clock is injected and the "step source" is
/// the map's recorded total, seeded directly, exactly as US-201's suite does.
///
/// The split under test is foreground vs background: a foregrounding raises the on-screen BATTLE/FLEE
/// dialog (US-201), a background wake raises a local notification instead — asserted through a spy
/// deliverer, since a suppressed or de-duplicated notification leaves no other trace.
@MainActor
final class WildBattleNotificationTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
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

    private static func at(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    /// Mid-morning, so the fallback 22:00–07:00 sleep window cannot swallow the awake tests.
    private static let dayTime = at("2026-07-17 10:00")
    /// Inside the fallback sleep window, for the asleep test.
    private static let nightTime = at("2026-07-17 23:30")

    private static let winMap = "winmap"
    private static let weakling = "weakling"

    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: Self.weakling, displayName: "Weakling", stage: .babyI, spriteFile: "Botamon"),
        ])
    }

    private func fixtureCatalog() -> MapCatalog {
        MapCatalog(maps: [
            AdventureMap(id: Self.winMap, displayName: "Win", assetName: "01_grassland",
                         tier: 1, totalSteps: 100_000, opponentPool: [Self.weakling]),
        ])
    }

    /// Seeds a healthy `hero` with every care marker stamped at `now` (so a refresh charges no
    /// mistakes) and the light already OUT (so US-100's nudge cannot contaminate the spy), then
    /// returns a model over the same store wired to `spy`/`settings`.
    private func makeModel(storeName: String = "Wild",
                           now: Date = WildBattleNotificationTests.dayTime,
                           spy: SpyNotificationDeliverer,
                           settings: NotificationSettings) throws -> MainScreenModel {
        let url = storeDirectory.appendingPathComponent("\(storeName).store")
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: now)
        state.stage = .child
        state.strengthStat = 30
        state.healthDataLastSeen = now
        state.hungerUpdatedAt = now
        state.stageEnteredDate = now
        state.poopUpdatedAt = now
        state.setLight(.off, now: now.addingTimeInterval(-24 * 60 * 60))
        try store.save()

        return MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            maps: fixtureCatalog(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoWildSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoWildSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            makeBattleGenerator: { SeededGenerator(seed: 1) },
            notificationSettings: settings,
            notificationDeliverer: spy
        )
    }

    private func walked(_ steps: Double, into mapId: String, on model: MainScreenModel) {
        model.selectMap(mapId)
        model.profile?.record(steps: steps, forMap: mapId)
    }

    // MARK: - AC1: a background refresh raises the notification

    func testABackgroundRefreshRaisesAWildBattleNotificationWhenDue() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)

        XCTAssertEqual(spy.kinds, [.wildBattle], "500 steps in the background nudge to battle")
        XCTAssertEqual(spy.delivered.first?.title, "A wild Digimon appeared!")
        XCTAssertEqual(spy.delivered.first?.body,
                       "Hero has walked into a wild Digimon. Open the app to battle.")
        // A background wake sets NO on-screen dialog — that is the foreground refresh's job (US-201).
        XCTAssertNil(model.pendingWildEncounter, "the notification, not a dialog nobody can see")
    }

    /// The control for the 500 threshold: 499 in the background says nothing.
    func testAShortWalkRaisesNothing() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(499, into: Self.winMap, on: model)

        await model.refresh(background: true)

        XCTAssertEqual(spy.delivered, [], "499 of 500 is not across")
    }

    // MARK: - Foreground still raises the dialog, not a notification

    func testAForegroundRefreshRaisesTheDialogAndNoNotification() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh()

        XCTAssertNotNil(model.pendingWildEncounter, "a foregrounding shows the BATTLE/FLEE dialog")
        XCTAssertEqual(spy.delivered, [], "and does not also nudge — the player is already here")
    }

    // MARK: - AC2: one notification per crossing, and never while an encounter is pending

    func testTheNotificationIsNotRaisedTwiceForTheSameCrossing() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)
        XCTAssertEqual(spy.kinds, [.wildBattle])
        // The marker was stamped AND saved, so the dedup survives a relaunch, not just this process.
        XCTAssertEqual(model.profile?.wildBattleNotifiedMarker(forMap: Self.winMap), 0)

        // A second background wake, no steps taken and nothing resolved: the same crossing must not
        // nudge again.
        await model.refresh(background: true)
        XCTAssertEqual(spy.kinds, [.wildBattle], "one crossing, one nudge")
    }

    func testTheNotificationDefersWhileAnEncounterIsAlreadyPending() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)
        // Foreground surfaces the dialog first.
        model.checkForWildEncounter()
        XCTAssertNotNil(model.pendingWildEncounter)

        await model.refresh(background: true)

        XCTAssertEqual(spy.delivered, [], "no nudge over a dialog that is already up")
    }

    // MARK: - The tap-to-open path withdraws the nudge

    /// Tapping the notification launches the app, whose foreground refresh surfaces the dialog — and
    /// surfacing it withdraws the now-stale "go and battle" notice, exactly as cleaning withdraws the
    /// mess notice.
    func testSurfacingTheDialogCancelsTheNotification() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)
        XCTAssertEqual(spy.kinds, [.wildBattle])
        XCTAssertEqual(spy.cancelled, [], "nothing withdrawn before the app opens")

        // The app comes to the front (the tap) and the dialog is re-derived (US-201).
        await model.refresh()

        XCTAssertNotNil(model.pendingWildEncounter, "the dialog is waiting")
        XCTAssertEqual(spy.cancelled, [.wildBattle], "and the nudge is withdrawn")
    }

    // MARK: - Per-crossing, not once-ever

    /// After the player answers the dialog the marker moves; a fresh 500 steps later a background
    /// wake nudges again.
    func testAFreshCrossingAfterResolutionNudgesAgain() async throws {
        let spy = SpyNotificationDeliverer()
        let model = try makeModel(spy: spy, settings: isolatedWildSettings())
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)
        XCTAssertEqual(spy.kinds, [.wildBattle])

        // The player opens the app and flees: the encounter resolves and the marker moves to 100
        // (600 minus the 500 flee penalty).
        model.checkForWildEncounter()
        model.fleeWildEncounter()
        XCTAssertEqual(model.profile?.encounterMarker(forMap: Self.winMap), 100)

        // A fresh 500 steps past the new marker, and the next background wake nudges afresh.
        model.profile?.record(steps: 500, forMap: Self.winMap)
        await model.refresh(background: true)

        XCTAssertEqual(spy.kinds, [.wildBattle, .wildBattle], "a new crossing is a new nudge")
    }

    // MARK: - AC3 gates: asleep and the toggle

    /// Asleep the nudge is held — a "go and battle" at 3am is a notice at the one hour it cannot be
    /// acted on — and, crucially, the crossing is NOT spent: the next background wake past the window
    /// delivers it rather than losing it.
    func testAsleepSuppressesTheNudgeButDoesNotSpendTheCrossing() async throws {
        let spy = SpyNotificationDeliverer()
        // One model over a moving clock: asleep at 23:30, then awake at 10:00 the next day.
        let url = storeDirectory.appendingPathComponent("Asleep.store")
        let store = try GameStore(url: url)
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.nightTime)
        state.stage = .child
        state.strengthStat = 30
        state.healthDataLastSeen = Self.nightTime
        state.hungerUpdatedAt = Self.nightTime
        state.stageEnteredDate = Self.nightTime
        state.poopUpdatedAt = Self.nightTime
        state.setLight(.off, now: Self.nightTime.addingTimeInterval(-24 * 60 * 60))
        try store.save()

        var currentTime = Self.nightTime
        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            maps: fixtureCatalog(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: NoWildSamples(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: NoWildSleep(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { currentTime },
            chooseStartingDigitama: { $0.first },
            makeBattleGenerator: { SeededGenerator(seed: 1) },
            notificationSettings: isolatedWildSettings(),
            notificationDeliverer: spy
        )
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)
        XCTAssertTrue(model.isAsleep, "the control: 23:30 is inside the fallback sleep window")
        XCTAssertEqual(spy.delivered, [], "nothing fires at 3am")
        XCTAssertNil(model.profile?.wildBattleNotifiedMarker(forMap: Self.winMap),
                     "and the crossing is not marked spent")

        // Awake the next morning: the held crossing is nudged.
        currentTime = Self.dayTime.addingTimeInterval(24 * 60 * 60)
        await model.refresh(background: true)
        XCTAssertFalse(model.isAsleep)
        XCTAssertEqual(spy.kinds, [.wildBattle], "the morning wake delivers the held nudge")
    }

    func testTheToggleOffSuppressesTheNotification() async throws {
        let spy = SpyNotificationDeliverer()
        let settings = isolatedWildSettings()
        settings.setEnabled(false, for: .wildBattle)
        let model = try makeModel(spy: spy, settings: settings)
        await model.start()
        walked(600, into: Self.winMap, on: model)

        await model.refresh(background: true)

        XCTAssertEqual(spy.delivered, [], "a switched-off kind reaches nobody")
        XCTAssertNil(model.profile?.wildBattleNotifiedMarker(forMap: Self.winMap),
                     "and a suppressed crossing is not marked spent")
    }
}

// MARK: - Fixtures

/// Records what a real deliverer would have shown, scheduled or withdrawn.
@MainActor
final class SpyNotificationDeliverer: PetNotificationDelivering {
    private(set) var delivered: [PetNotification] = []
    private(set) var scheduled: [(notification: PetNotification, date: Date)] = []
    private(set) var cancelled: [NotificationKind] = []

    func deliver(_ notification: PetNotification) { delivered.append(notification) }
    func deliver(_ notification: PetNotification, at date: Date) { scheduled.append((notification, date)) }
    func cancel(_ kind: NotificationKind) { cancelled.append(kind) }

    var kinds: [NotificationKind] { delivered.map(\.kind) }
}

@MainActor
private func isolatedWildSettings() -> NotificationSettings {
    let name = "WildBattleNotificationTests-\(UUID().uuidString)"
    return NotificationSettings(defaults: UserDefaults(suiteName: name)!)
}

private final class NoWildSamples: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class NoWildSleep: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}
