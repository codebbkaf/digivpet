import XCTest
import Foundation

@testable import DigiVPet

/// AC2 — the `.success` haptic. The Simulator has no haptics and `simctl` cannot capture one, so the
/// screenshot pass cannot show it; what IS checkable is that the ceremony fires it exactly once, at
/// the reveal (after the flash), and before it hands back. `playHaptic` is injected and the beat
/// durations are injectable, so the whole 4.2s sequence runs here in a few milliseconds.
@MainActor
final class EvolutionCeremonyHapticTests: XCTestCase {
    /// Each beat is long enough that a tap landing in the wrong one is unambiguous in the elapsed
    /// time, and short enough that the whole ceremony runs in well under a second.
    private static let beat: TimeInterval = 0.2

    /// The haptic fires exactly once, after the old form and the flash have both had their beats —
    /// i.e. at the reveal, not on appear — and the reveal is then held before handing back.
    func testTheHapticFiresOnceAtTheReveal() async throws {
        var haptics: [TimeInterval] = []
        var finishedAt: TimeInterval?
        let start = Date()

        let view = EvolutionCeremonyView(
            event: .init(
                from: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
                to: DigimonPresentation(displayName: "Greymon", stage: .adult, spriteFile: "Greymon")
            ),
            onFinish: { finishedAt = Date().timeIntervalSince(start) },
            playHaptic: { haptics.append(Date().timeIntervalSince(start)) },
            beforeDuration: Self.beat,
            flashDuration: Self.beat,
            afterDuration: Self.beat
        )

        await view.run()

        XCTAssertEqual(haptics.count, 1, "exactly one tap, not one per beat and not none")

        // The tap must land after BOTH the old-form beat and the flash beat. A haptic moved to the
        // start of the ceremony (on appear) would land near 0 and fail this.
        let tap = try XCTUnwrap(haptics.first)
        XCTAssertGreaterThanOrEqual(tap, Self.beat * 2,
                                    "the haptic lands at the reveal, after the old form and the flash")

        // And the reveal is held after the tap rather than finishing with it, so the name is readable.
        let finished = try XCTUnwrap(finishedAt, "the ceremony handed back")
        XCTAssertGreaterThanOrEqual(finished - tap, Self.beat * 0.8,
                                    "the reveal was held after the tap, not raced by onFinish")
    }
}

/// US-021 — evolution animation and haptic.
///
/// The ceremony itself is a view (a flash between two sprites, a `.success` haptic, the new name),
/// verified by build and Simulator screenshot. What is unit-testable is the seam that drives it:
/// `MainScreenModel.pendingEvolution`. These tests pin that a transition through `refresh()`
/// publishes an event carrying BOTH forms, that a non-evolving refresh publishes nothing, that the
/// event survives to the first app open (the "evolved while closed" AC), and that acknowledging it
/// clears it so the ceremony plays once.

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class EvolutionCeremonyModelTests: XCTestCase {
    private var storeDirectory: URL!
    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

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

    private static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    /// Now, and a stage start ~16 days earlier so a Child's 72h time gate (US-020) is well cleared.
    private static let morning = date("2026-07-17 08:00")
    private static let lastStage = date("2026-07-01 08:00")

    /// A start egg, a branching Child "hero", and its two adult branches — the shape `refresh()`
    /// evolves through.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon",
                          evolutions: [
                              EvolutionEdge(to: "greymon", requiredEnergy: .strength, minEnergy: 40,
                                            maxCareMistakes: 3),
                              EvolutionEdge(to: "seadramon", requiredEnergy: .spirit, minEnergy: 40,
                                            maxCareMistakes: 3)
                          ]),
            EvolutionNode(id: "greymon", displayName: "Greymon", stage: .adult, spriteFile: "Greymon"),
            EvolutionNode(id: "seadramon", displayName: "Seadramon", stage: .adult,
                          spriteFile: "Garurumon")
        ])
    }

    /// Seeds a saved game at "hero" with the given dominant energy and care history, then builds a
    /// model over the same store so `start()`'s refresh sees exactly that state.
    private func makeModelAtHero(
        storeName: String = "Ceremony",
        dominant: EnergyType,
        stageAmount: Int = 60,
        careMistakes: Int = 0
    ) throws -> MainScreenModel {
        let store = try GameStore(url: storeURL(storeName))
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.lastStage)
        state.stage = .child
        var totals = EnergyTotals()
        totals[dominant] = stageAmount
        state.stageEnergy = totals
        state.careMistakeCount = careMistakes
        state.stageEnteredDate = Self.lastStage
        try store.save()

        return MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Self.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Self.losAngeles)
            ),
            calendar: Self.losAngeles,
            now: { Self.morning },
            chooseStartingDigitama: { $0.first }
        )
    }

    /// AC1 + AC3: an evolution publishes an event naming both forms — the old one to fade out from,
    /// the new one (with the name to announce) to reveal.
    func testEvolvingPublishesAnEventWithBothForms() async throws {
        let model = try makeModelAtHero(dominant: .strength)
        XCTAssertNil(model.pendingEvolution, "nothing has happened before the app opens")

        await model.start()

        let event = try XCTUnwrap(model.pendingEvolution, "the evolution should have produced a ceremony")
        XCTAssertEqual(event.from.displayName, "Hero", "the form left behind")
        XCTAssertEqual(event.from.spriteFile, "Agumon")
        XCTAssertEqual(event.to.displayName, "Greymon", "the announced new form")
        XCTAssertEqual(event.to.spriteFile, "Greymon")
        XCTAssertEqual(event.to.stage, .adult)
        XCTAssertEqual(model.state?.currentDigimonId, "greymon", "and the game really moved")
    }

    /// AC4: the event is present the first time the app is opened, which is when `start()` credits
    /// the energy accumulated while the app was closed and the evolution becomes due. So an
    /// evolution that "happened while closed" is celebrated on open, not silently applied.
    func testTheCeremonyIsPresentOnTheFirstAppOpen() async throws {
        let model = try makeModelAtHero(dominant: .spirit)
        await model.start()

        // A spirit-dominant hero takes the other branch — the event follows the branch, not a
        // hardcoded target.
        let event = try XCTUnwrap(model.pendingEvolution)
        XCTAssertEqual(event.to.displayName, "Seadramon")
    }

    /// A refresh that evolves nothing publishes no ceremony — the control, so the assertions above
    /// cannot pass on a model that always sets an event.
    func testANonEvolvingRefreshPublishesNoCeremony() async throws {
        // 39 < the 40 minEnergy, so nothing qualifies and the Digimon stays put.
        let model = try makeModelAtHero(dominant: .strength, stageAmount: 39)
        await model.start()

        XCTAssertNil(model.pendingEvolution, "no transition, so no ceremony")
        XCTAssertEqual(model.state?.currentDigimonId, "hero")
    }

    /// Care mistakes that block the evolution also block its ceremony — the event tracks the actual
    /// transition, not merely the attempt.
    func testABlockedEvolutionPublishesNoCeremony() async throws {
        let model = try makeModelAtHero(dominant: .strength, careMistakes: 4)
        await model.start()

        XCTAssertNil(model.pendingEvolution, "neglect held the evolution back, so there is nothing to celebrate")
        XCTAssertEqual(model.state?.currentDigimonId, "hero")
    }

    /// Acknowledging the ceremony clears it, so it plays exactly once and a later refresh with no
    /// new evolution does not replay it.
    func testAcknowledgingClearsTheCeremony() async throws {
        let model = try makeModelAtHero(dominant: .strength)
        await model.start()
        XCTAssertNotNil(model.pendingEvolution)

        model.acknowledgeEvolution()
        XCTAssertNil(model.pendingEvolution, "acknowledged, so it will not replay")

        // A second refresh (a return to the app) finds nothing new to evolve and leaves it cleared.
        await model.refresh()
        XCTAssertNil(model.pendingEvolution, "no new transition brings the ceremony back")
    }
}
