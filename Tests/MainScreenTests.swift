import XCTest
import Foundation
import SwiftData

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, as in `EnergyCreditingTests`: a test that
/// passed only in the machine's own zone would be no test at all.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static let morning = date("2026-07-17 08:00")
    static let evening = date("2026-07-17 20:00")
}

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

@MainActor
final class MainScreenModelTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("MainScreen.store") }
    private var steps: FixtureSampleFetcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        steps = FixtureSampleFetcher()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// The model under test, reading whatever `steps` is loaded with and nothing else.
    ///
    /// The starting egg is pinned to the FIRST playable Digitama rather than a random one, so these
    /// tests can name it (agu_digitama); the randomness itself is exercised in `EggHatchingTests`.
    private func makeModel(
        graph: EvolutionGraph = .bundled,
        now: @escaping () -> Date = { Fixture.morning }
    ) -> MainScreenModel {
        let source = HealthEnergySource(
            todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
            sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                              calendar: Fixture.losAngeles)
        )
        return MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: graph,
            energySource: source,
            calendar: Fixture.losAngeles,
            now: now,
            chooseStartingDigitama: { $0.first }
        )
    }

    private func walk(_ count: Double) {
        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 07:00"),
                         end: Fixture.date("2026-07-17 07:30"),
                         value: count)
        ]
    }

    // MARK: - What the screen shows

    /// THE AC: the stage name and the Digimon's display name are both available to draw, and they
    /// describe the Digimon that was actually saved.
    func testAStartedGameNamesItsDigimonAndItsStage() async throws {
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.phase, .playing)
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertEqual(presentation.displayName, "Agu Digitama")
        XCTAssertEqual(presentation.stage, .digitama)
        XCTAssertEqual(presentation.stage.displayName, "Digitama")
    }

    /// The control for the test above: with a DIFFERENT Digimon saved, the screen must name THAT
    /// one. Without this, the assertions above would also pass on a model that hard-coded the egg.
    func testTheScreenNamesTheSavedDigimonRatherThanTheStartingEgg() async throws {
        let store = try GameStore(url: storeURL)
        let saved = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        saved.currentDigimonId = "greymon"
        saved.stage = .adult
        try store.save()

        let model = makeModel()
        await model.start()

        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertEqual(presentation.displayName, "Greymon")
        XCTAssertEqual(presentation.stage, .adult)
        XCTAssertEqual(presentation.spriteStage, "Adult")
        XCTAssertEqual(presentation.spriteFile, "Greymon")
    }

    /// `GameState.stage` is a saved DUPLICATE of a fact the graph already knows, so the two can
    /// disagree — and when they do, the graph is right, because its stage is where the art really
    /// is. A screen that trusted the saved copy would draw the '?' placeholder for a Digimon whose
    /// sheet is on disk the whole time.
    ///
    /// The saved stage is left at the `.digitama` a fresh game starts on, deliberately: that is
    /// what a half-applied evolution looks like, and it is the shape US-018/US-019 have to keep in
    /// step when they move a Digimon.
    func testTheStageShownComesFromTheGraphNotFromTheSavedCopy() async throws {
        let store = try GameStore(url: storeURL)
        let saved = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        saved.currentDigimonId = "greymon"
        try store.save()
        XCTAssertEqual(saved.stage, .digitama, "the stale saved stage this test turns on")

        let model = makeModel()
        await model.start()

        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertEqual(presentation.stage, .adult, "Greymon is an Adult, whatever the save says")
        XCTAssertEqual(presentation.spriteStage, "Adult")
        XCTAssertNotNil(
            SpriteSheetCache.shared.sheet(stage: presentation.spriteStage, name: presentation.spriteFile),
            "and the stage it names is one the art really loads from"
        )
    }

    /// The screen can only render art the sprite loader can really slice, so "has a presentation"
    /// has to mean more than "the node decoded". A first launch that drew the '?' placeholder
    /// would satisfy every other test here.
    func testTheStartingEggsArtLoadsAsARealAnimatedSheet() async throws {
        let model = makeModel()
        await model.start()

        let presentation = try XCTUnwrap(model.presentation)
        let sheet = try XCTUnwrap(
            SpriteSheetCache.shared.sheet(stage: presentation.spriteStage, name: presentation.spriteFile),
            "the starting egg must have art on disk, or the main screen opens on a placeholder"
        )
        XCTAssertEqual(sheet.kind, .egg)
        // The idle loop is what the screen asks for; an egg with no idle frames would animate
        // nothing.
        XCTAssertEqual(SpriteAnimation.idle.frames(from: sheet).count, 2)
    }

    /// A saved id the graph no longer knows must produce NO presentation rather than a plausible
    /// wrong one — the screen shows its explanatory state instead.
    func testADigimonTheGraphDoesNotKnowHasNoPresentation() async throws {
        let store = try GameStore(url: storeURL)
        let saved = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        saved.currentDigimonId = "nosuchmon"
        try store.save()

        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.phase, .playing, "the store opened; it is the graph that cannot answer")
        XCTAssertNil(model.presentation)
    }

    /// A store that will not open explains itself instead of trapping. Unlike a broken evolution
    /// graph, this is a real runtime condition that a user's watch can produce.
    func testAStoreThatCannotBeOpenedLandsOnTheFailedState() async {
        struct Boom: Error {}
        let model = MainScreenModel(
            makeStore: { throw Boom() },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning }
        )

        await model.start()

        XCTAssertNil(model.state)
        XCTAssertNil(model.presentation)
        guard case .failed = model.phase else {
            return XCTFail("expected .failed, got \(model.phase)")
        }
    }

    /// The starting egg is picked from the graph, not hard-coded: a graph whose first Digitama is
    /// a different one starts there.
    func testTheStartingEggComesFromTheGraph() async throws {
        let gabu = try XCTUnwrap(EvolutionGraph.bundled.node(id: "gabu_digitama"))
        let model = makeModel(graph: EvolutionGraph(nodes: [gabu]))
        await model.start()

        XCTAssertEqual(model.state?.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(model.presentation?.displayName, "Gabu Digitama")
    }

    /// A graph with no egg to start at cannot start a game, and says so rather than crashing on an
    /// empty roster.
    func testAGraphWithNoDigitamaFailsRatherThanGuessing() async {
        let model = makeModel(graph: EvolutionGraph(nodes: []))
        await model.start()

        guard case .failed = model.phase else {
            return XCTFail("expected .failed, got \(model.phase)")
        }
    }

    // MARK: - The refresh

    /// THE AC's other half, at the seam the view drives: a refresh reads health data and credits
    /// the energy it finds. The view calls exactly this when scenePhase becomes .active.
    func testRefreshingCreditsTheEnergyInTodaysHealthData() async throws {
        walk(1_000)
        let model = makeModel()
        await model.start()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.stageEnergy.strength, 10, "1,000 steps at 1 Strength per 100")
        XCTAssertEqual(model.lifetimeEnergy.strength, 10)
    }

    /// Re-opening the app must not pay for the same steps again — the AC says "refreshes", not
    /// "re-credits". This is US-014's delta rule reaching the screen, and it is why `refresh` is
    /// safe to wire to every activation.
    func testRefreshingAgainWithNoNewActivityCreditsNothingMore() async throws {
        walk(1_000)
        let model = makeModel()
        await model.start()

        await model.refresh()
        await model.refresh()

        XCTAssertEqual(model.state?.stageEnergy.strength, 10)
    }

    /// The control for the test above: a repeat refresh crediting nothing must be the LEDGER's
    /// doing, not a model that stopped reading after the first time.
    func testRefreshingAfterMoreActivityCreditsOnlyTheDifference() async throws {
        walk(1_000)
        let model = makeModel()
        await model.start()
        XCTAssertEqual(model.state?.stageEnergy.strength, 10)

        walk(2_500)
        await model.refresh()

        XCTAssertEqual(model.state?.stageEnergy.strength, 25, "25 total, not 10 + 25")
    }

    /// Energy credited on screen has to reach the disk, or a day's walking dies with the process.
    /// Asserted through a SECOND store on the same file, so what is read came off disk rather than
    /// out of the first context's memory.
    func testCreditedEnergyIsSaved() async throws {
        walk(1_000)
        let model = makeModel()
        await model.start()

        let reopened = try GameStore(url: storeURL)
        let saved = try reopened.loadOrCreate(digitamaId: "unused", now: Fixture.morning)
        XCTAssertEqual(saved.currentDigimonId, "agu_digitama", "the existing save, not a new one")
        XCTAssertEqual(saved.stageEnergy.strength, 10)
    }

    /// Spirit comes from the sleep reader, which `TodayHealthReader` cannot be asked for at all
    /// (US-012). A model wired only to the quantity reader would leave Spirit permanently zero and
    /// still pass every other test here.
    func testSpiritIsReadFromSleepRatherThanFromTheDailyQuantities() async throws {
        let sleep = FixtureSleepFetcher()
        sleep.samples = [
            SleepSample(start: Fixture.date("2026-07-16 23:00"),
                        end: Fixture.date("2026-07-17 06:00"),
                        category: .asleepCore)
        ]
        let model = MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: sleep, calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning }
        )

        await model.start()

        XCTAssertEqual(model.state?.stageEnergy.spirit, 28, "420 min asleep at 1 Spirit per 15")
    }

    /// The clock is injected, so a refresh reads the day it is actually given. Without this, the
    /// day the ledger keys on would be whenever the suite happened to run.
    func testTheRefreshReadsAgainstTheInjectedClock() async throws {
        walk(1_000)
        var now = Fixture.morning
        let model = makeModel(now: { now })
        await model.start()
        XCTAssertEqual(model.state?.stageEnergy.strength, 10)

        // Same day, more walking: the delta, against the same ledger day.
        walk(1_500)
        now = Fixture.evening
        await model.refresh()

        XCTAssertEqual(model.state?.stageEnergy.strength, 15)
        XCTAssertEqual(model.state?.energyLastEarned.strength, Fixture.evening,
                       "credited at the injected time, not at Date()")
    }

    /// A refresh before the store is open must do nothing rather than crash on a nil state — the
    /// view's `.task` and its scenePhase change can both fire before `start()` has finished.
    func testRefreshingBeforeStartIsHarmless() async {
        walk(1_000)
        let model = makeModel()

        await model.refresh()

        XCTAssertNil(model.state)
        XCTAssertEqual(model.phase, .loading)
    }

    // MARK: - US-052: the clean action

    /// AC3: cleaning zeroes the count and says so in the caption slot the screen already draws —
    /// `actionMessage` is the same property a refused feed puts its reason in.
    func testCleaningClearsThePoopAndConfirmsIt() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        // US-178: cleaning spends a handwash charge; stock one so the mess can be cleared.
        model.profile?.cleanCharges = model.cleanChargeCap
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: false, now: Fixture.morning)
        XCTAssertEqual(state.poopCount, PoopClock.maximumPoops, "staged a full screen to clean")

        XCTAssertTrue(model.clean())

        XCTAssertEqual(model.poopCount, 0)
        XCTAssertEqual(model.actionMessage, "All clean!")
    }

    /// The bug the restamp exists to stop. `PoopClock` freezes `poopUpdatedAt` at the instant the
    /// ceiling was reached, so without moving it, the very next refresh finds twelve hours of
    /// elapsed time and puts all four poops straight back — cleaning would undo itself in front of
    /// the user. Asserted through a real `refresh()` rather than against the timestamp, because it
    /// is the visible outcome that matters.
    func testCleaningIsNotUndoneByTheNextRefresh() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        // US-178: cleaning spends a handwash charge; stock one so the clean happens.
        model.profile?.cleanCharges = model.cleanChargeCap
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: false, now: Fixture.morning)
        model.clean()

        await model.refresh()

        XCTAssertEqual(model.poopCount, 0)
    }

    /// AC4's other side: with nothing to clean the action is a no-op that leaves no caption behind.
    /// The disabled button already prevents the tap; the rule lives in the model regardless.
    func testCleaningWithNoPoopDoesNothing() async {
        let model = makeModel()
        await model.start()

        XCTAssertEqual(model.poopCount, 0)
        XCTAssertFalse(model.clean())
        XCTAssertNil(model.actionMessage)
    }

    /// The wiring US-051 deliberately left undone: `refresh()` is what ages the count, so poop
    /// actually accumulates in the running app rather than only in `PoopClock`'s tests.
    func testARefreshAgesThePoopCount() async throws {
        // Nine hours after the save was stamped, and awake — three poops at 3h each.
        let model = makeModel(now: { Fixture.morning })
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-9 * 60 * 60)

        await model.refresh()

        XCTAssertEqual(model.poopCount, 3)
    }

    /// And the pause holds through the real refresh too: a Digimon inside its sleep window accrues
    /// nothing, however long the app was shut. `isAsleep` is forced rather than inferred because
    /// the fixture fetcher has no sleep history and `refresh()` re-derives the window from it.
    func testARefreshWhileAsleepAgesNothing() async throws {
        // 02:00, inside the 22:00-07:00 fallback window every one of these fixtures infers.
        let night = Fixture.date("2026-07-18 02:00")
        let model = makeModel(now: { night })
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.poopCount = 0
        state.poopUpdatedAt = night.addingTimeInterval(-9 * 60 * 60)

        await model.refresh()

        XCTAssertTrue(model.isAsleep, "the fixture night really is inside the sleep window")
        XCTAssertEqual(model.poopCount, 0)
    }

    // MARK: - US-053: neglect through the real refresh

    /// US-053 AC1 end to end, through the ordering `refresh()` actually runs in: `advancePoop` fills
    /// the screen and FREEZES the timestamp at the moment it filled, then `auditCareMistakes` reads
    /// the gap since that freeze. The freeze is what makes a second saved date unnecessary, so it is
    /// worth pinning through the real refresh rather than against a hand-built state.
    ///
    /// Thirty hours since the last stamp: twelve of them fill the screen, and the eighteen that
    /// remain are one spell's worth of neglect. Nothing is hand-set but the stale timestamp, so what
    /// is asserted is the shipped rules composing.
    func testAFullScreenLeftUncleanedIsChargedThroughARefresh() async throws {
        let model = makeModel(now: { Fixture.morning })
        await model.start()
        let state = try XCTUnwrap(model.state)
        let before = state.careMistakeCount
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-30 * 60 * 60)

        await model.refresh()

        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops)
        XCTAssertEqual(state.careMistakeCount, before + 1)
        XCTAssertEqual(state.poopMistakesCharged, 1)
    }

    /// AC4 through the real `clean()`: cleaning ends the spell, so the next refresh charges nothing
    /// more however long the screen had been full before the user got to it.
    func testCleaningStopsTheChargingThroughTheRealModel() async throws {
        let model = makeModel(now: { Fixture.morning })
        await model.start()
        let state = try XCTUnwrap(model.state)
        // US-178: cleaning spends a handwash charge; stock one so the clean below happens.
        model.profile?.cleanCharges = model.cleanChargeCap
        let before = state.careMistakeCount
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-18 * 60 * 60)
        await model.refresh()
        let chargedBeforeCleaning = state.careMistakeCount
        XCTAssertEqual(chargedBeforeCleaning, before + 1,
                       "twelve hours filled the screen, the remaining six are one spell")

        model.clean()
        await model.refresh()

        XCTAssertEqual(state.careMistakeCount, chargedBeforeCleaning, "a clean screen charges nothing")
        XCTAssertEqual(state.poopMistakesCharged, 0)
    }
}

final class StageDisplayNameTests: XCTestCase {
    /// The folder name is not always a stage name. `rawValue` must keep naming the folder on disk
    /// (it is what resolves sprites, and what saved games persist), while the UI shows the stage.
    func testTheFinalStageIsShownAsUltimateButStillResolvesItsFolder() {
        XCTAssertEqual(Stage.ultimate.displayName, "Ultimate")
        XCTAssertEqual(Stage.ultimate.rawValue, "Ultimate-Super Ultimate")
    }

    /// Every other stage's folder IS its name, so they must not drift apart by accident.
    func testEveryOtherStageShowsItsFolderName() {
        for stage in Stage.allCases where stage != .ultimate {
            XCTAssertEqual(stage.displayName, stage.rawValue, "\(stage)")
        }
    }

    /// No stage may show an empty label, which would leave the screen with a blank line under the
    /// sprite rather than a stage.
    func testEveryStageHasALabel() {
        for stage in Stage.allCases {
            XCTAssertFalse(stage.displayName.isEmpty, "\(stage)")
        }
    }
}
