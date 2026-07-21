import CoreGraphics
import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-097 — the two actions with no loop of their own finally do something on screen.
///
/// Cleaning and training both end on a single HELD frame from the sheet: happy, attack, angry.
/// A held frame is exactly what a BLOCKED action looks like, so until now the happiest moment in
/// the game and a refused feed were the same event visually. This suite is about the motion each
/// one now carries — the hop of a clean screen, the lunge of a landed blow, the recoil of a miss —
/// and about the one case that must still move nothing at all: cleaning with nothing to clean.
///
/// Driven through the real `MainScreenModel` and the real store, as `FeedMotionTests` is, because
/// which motion plays is not a fact about `TrainAction` or `PoopClock` — it is a fact about what
/// the screen is shown. Shapes are sampled through the shipped `ActionMotion` track rather than
/// re-derived; pinning the shapes themselves is `ActionMotionTests`' job.
///
/// No test waits real time: the clock is a chosen `Date` and the action hold is injected at
/// milliseconds rather than the app's two seconds.

private enum Clock {
    /// Mid-afternoon in the zone below, which matters: nothing here forces the Digimon awake, and
    /// the fallback sleep window (22:00-07:00) would block every training in this file from a
    /// night-time instant.
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    /// A fixed zone, matching the other apply suites, so nothing here depends on where it runs.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
}

/// The Simulator has no HealthKit data and a test must not depend on the machine's, so both readers
/// are fed nothing. Copied rather than shared — the ones in the other apply suites are `private` to
/// their files.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class CleanTrainMotionTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CleanTrainMotionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    // MARK: - AC1: a clean screen is celebrated

    func testCleaningPlaysTheHappyFrameAndTheHopMotion() async throws {
        let model = try await startedModel(named: "clean")
        try stagePoop(in: model)

        XCTAssertTrue(model.clean())
        XCTAssertEqual(model.animation, .still(.happy), "the pose US-052 already published")
        XCTAssertEqual(model.actionMotion?.kind, .hop)
    }

    /// TWO hops, and both of them UP. The count is what the story asks for and what separates a
    /// celebration from the single bump of a stumble; measured as peaks in the shipped track, so it
    /// is the motion the screen actually gets rather than a restatement of `arcs(2,)`.
    func testTheHopLeavesTheGroundTwiceAndNeverSideways() async throws {
        let model = try await startedModel(named: "hop")
        try stagePoop(in: model)
        model.clean()
        let motion = try XCTUnwrap(model.actionMotion)

        let duration = ActionMotion.duration(of: .hop)
        var heights: [CGFloat] = []
        for sample in stride(from: 0.0, through: duration, by: duration / 600) {
            let offset = ActionMotion.offset(for: motion,
                                             at: motion.start.addingTimeInterval(sample))
            XCTAssertEqual(offset.x, 0, "a hop is straight up, not a sidestep")
            XCTAssertLessThanOrEqual(offset.y, 0, "negative y is UP, and a hop never digs in")
            heights.append(offset.y)
        }

        // A peak is a sample strictly higher than both its neighbours; two of them is two hops.
        let peaks = (1..<(heights.count - 1)).filter {
            heights[$0] < heights[$0 - 1] && heights[$0] < heights[$0 + 1]
        }
        XCTAssertEqual(peaks.count, 2, "two hops, not one stumble and not three jitters")
        // Both ends checked at the exact endpoints, with a tolerance: `elapsed` is the difference
        // of two `Date`s, so a sample asked for AT the duration lands a nanosecond short of it and
        // the track answers the last hair of the arc rather than the zero it reaches an instant
        // later. The tolerance is a thousandth of a sprite pixel — far below anything drawable.
        XCTAssertEqual(try XCTUnwrap(heights.first), 0, accuracy: 0.001, "it starts on the ground")
        XCTAssertEqual(ActionMotion.offset(for: motion,
                                           at: motion.start.addingTimeInterval(duration)).y,
                       0, accuracy: 0.001, "and lands back on it")
    }

    /// The hop goes with the pose, exactly as the chew does — there is no window in which the
    /// Digimon is still bouncing after it has stopped being pleased.
    func testTheHopIsClearedWithThePose() async throws {
        let model = try await startedModel(named: "cleared")
        try stagePoop(in: model)
        model.clean()
        XCTAssertNotNil(model.actionMotion)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle, "the pose is held, not stuck")
        XCTAssertNil(model.actionMotion, "and the motion went with it")
        XCTAssertTrue(model.isWandering, "so the walk resumes from exactly where it stood")
    }

    // MARK: - AC5: cleaning nothing stays a no-op

    /// The disabled Clean button already prevents this tap; the rule lives in the model regardless,
    /// and what US-097 adds to it is that a no-op must not move the sprite either. A hop with no
    /// mess on the ground would be the Digimon celebrating nothing.
    func testCleaningWithNothingToCleanPlaysNoPoseAndNoMotion() async throws {
        let model = try await startedModel(named: "nothing")

        XCTAssertEqual(model.poopCount, 0)
        XCTAssertFalse(model.clean())
        XCTAssertEqual(model.animation, .idle, "nothing happened to it")
        XCTAssertNil(model.actionMotion)
        XCTAssertNil(model.actionMessage)
    }

    // MARK: - AC2: the pile leaves rather than blinking out

    /// The exit is pinned where the view can be held to it: a transition inside a view graph is
    /// unreachable from a unit test, so the two numbers it is built from are named constants and
    /// these are them. `PoopGround` reads both — changing the shrink or the timing changes this.
    func testThePileLeavesByShrinkingAndFading() {
        XCTAssertEqual(PoopPile.vanishScale, 0.6)
        XCTAssertEqual(PoopPile.vanishDuration, 0.35)
        XCTAssertLessThan(PoopPile.vanishScale, 1, "it shrinks on the way out")
        XCTAssertGreaterThan(PoopPile.vanishScale, 0,
                             "but does not collapse to a point, which reads as a blink")
    }

    /// What DRIVES the fade: the count reaching zero, not a flag cleaning sets. The complication's
    /// `CleanIntent` zeroes the same count from another process, and the pile has to leave the same
    /// way when it does.
    func testTheCountIsWhatGoesToZero() async throws {
        let model = try await startedModel(named: "count")
        try stagePoop(in: model)
        XCTAssertGreaterThan(model.poopCount, 0)

        model.clean()

        XCTAssertEqual(model.poopCount, 0, "the one input `PoopGround` animates on")
    }

    // MARK: - AC3: a paid round lunges

    func testARoundThatBoughtAStatPlaysTheAttackFrameAndTheLungeMotion() async throws {
        let model = try await startedModel(named: "paid")
        model.train()
        model.finishTraining(.great)

        XCTAssertEqual(model.state?.strengthStat, TrainingResult.great.strengthGain,
                       "a round that bought something")
        XCTAssertEqual(model.animation, .still(.attack), "the pose US-083 already published")
        XCTAssertEqual(model.actionMotion?.kind, .lunge)
    }

    /// Forward and back. "Forward" is negative x because the pack's art faces LEFT unmirrored —
    /// `WanderingSpriteView` negates it for a Digimon walking the other way, which is what makes the
    /// blow go where the sprite is looking rather than over its shoulder.
    func testTheLungeCarriesTheSpriteForwardAndBringsItHome() async throws {
        let model = try await startedModel(named: "lunge")
        model.train()
        model.finishTraining(.perfect)
        let motion = try XCTUnwrap(model.actionMotion)

        let duration = ActionMotion.duration(of: .lunge)
        var furthest: CGFloat = 0
        for sample in stride(from: 0.0, through: duration, by: duration / 200) {
            let offset = ActionMotion.offset(for: motion,
                                             at: motion.start.addingTimeInterval(sample))
            XCTAssertEqual(offset.y, 0, "a thrust is level — it is not a hop")
            XCTAssertLessThanOrEqual(offset.x, 0, "and never goes backward, which is the recoil")
            furthest = min(furthest, offset.x)
        }
        XCTAssertLessThan(furthest, 0, "it did leave the spot")
        // Tolerance for the same reason the hop's endpoints carry one: `elapsed` is a difference of
        // `Date`s and lands a nanosecond short of the duration.
        XCTAssertEqual(ActionMotion.offset(for: motion,
                                           at: motion.start.addingTimeInterval(duration)).x,
                       0, accuracy: 0.001, "and came all the way home")
    }

    // MARK: - AC4: a miss recoils

    func testAMissPlaysTheAngryFrameAndTheRecoilMotion() async throws {
        let model = try await startedModel(named: "miss")
        model.train()
        model.finishTraining(.miss)

        XCTAssertEqual(model.state?.strengthStat, 0, "a round that bought nothing")
        XCTAssertEqual(model.animation, .still(.angry), "the pose US-083 already published")
        XCTAssertEqual(model.actionMotion?.kind, .recoil)
    }

    /// The point of the pair: a miss is legible as one WITHOUT reading the caption, because it goes
    /// the other way. Sampled from both rounds at once so the comparison is between the two motions
    /// the screen actually publishes.
    func testAMissMovesTheOppositeWayToALandedBlow() async throws {
        let landed = try await startedModel(named: "landed")
        landed.train()
        landed.finishTraining(.good)
        let lunge = try XCTUnwrap(landed.actionMotion)

        let missed = try await startedModel(named: "missed")
        missed.train()
        missed.finishTraining(.miss)
        let recoil = try XCTUnwrap(missed.actionMotion)

        let forward = ActionMotion.offset(
            for: lunge,
            at: lunge.start.addingTimeInterval(ActionMotion.duration(of: .lunge) / 4)).x
        let backward = ActionMotion.offset(
            for: recoil,
            at: recoil.start.addingTimeInterval(ActionMotion.duration(of: .recoil) / 4)).x

        XCTAssertLessThan(forward, 0, "a blow goes where the Digimon is facing")
        XCTAssertGreaterThan(backward, 0, "being hit sends it the other way")
    }

    /// Both training outcomes hold the walk for the motion's length, which is the property that makes
    /// adding a motion to a walk position safe — see `WanderingSpriteView.motion`.
    func testTheWalkIsHeldWhileEitherTrainingMotionRuns() async throws {
        let landed = try await startedModel(named: "heldPaid")
        landed.train()
        landed.finishTraining(.great)
        XCTAssertNotNil(landed.actionMotion)
        XCTAssertFalse(landed.isWandering)

        let missed = try await startedModel(named: "heldMiss")
        missed.train()
        missed.finishTraining(.miss)
        XCTAssertNotNil(missed.actionMotion)
        XCTAssertFalse(missed.isWandering)
    }

    // MARK: - Fixtures

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Child in the shipped `agumon` line with no outgoing edges, so nothing here can evolve and
    /// every change to the saved game is this action's doing alone. The egg exists only because
    /// `start()` resolves a starting Digitama before it loads, and throws `.noDigitama` without one.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, line: "agumon",
                          spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, line: "agumon",
                          spriteFile: "Agumon")
        ])
    }

    /// Winds the poop clock back half a day and runs the SHIPPED rule, rather than hand-setting the
    /// count: what is cleaned here is a mess the game itself produced.
    private func stagePoop(in model: MainScreenModel) throws {
        let state = try XCTUnwrap(model.state)
        state.poopUpdatedAt = Clock.start.addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: false, now: Clock.start)
        XCTAssertEqual(state.poopCount, PoopClock.maximumPoops, "staged a full screen to clean")
    }

    /// Seeds a saved game at "hero" funded for a training round, then hands back a started model
    /// reading it off disk.
    private func startedModel(named name: String) async throws -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .child
        state.stageEnergy[.strength] = 20
        try seeding.save()

        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            // Deliberately EMPTY: "hero" is in the fixture graph, which carries both its line and
            // its stage, so a roster consulted at all would be a bug.
            roster: Roster(entries: []),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            calendar: Clock.calendar,
            now: { Clock.start },
            chooseStartingDigitama: { $0.first },
            playTrainHaptic: {},
            // Milliseconds, so the clear is observable without waiting out the app's 2s. Shorter
            // than the shortest motion, so `show`'s repeat never fires here.
            actionDuration: 0.05
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        return model
    }
}
