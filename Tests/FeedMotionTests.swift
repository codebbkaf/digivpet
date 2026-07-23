import CoreGraphics
import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-096 — the Digimon MOVES while it eats and while it refuses.
///
/// US-095 built the motion tracks and pinned their shapes; nothing on screen used one. This suite is
/// about the wiring: which motion each feed outcome publishes, that a BLOCKED feed publishes none,
/// and that the motion and the pose are set and cleared together — the property that makes it
/// impossible to leave a Digimon bobbing after it has stopped eating.
///
/// Driven through the real `MainScreenModel` and the real store rather than against `FeedAction`,
/// because the motion is not a fact about feeding — it is a fact about what the screen is shown.
/// No test waits real time: the clock is a chosen `Date` and the action hold is injected at
/// milliseconds rather than the app's two seconds.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 600_000)

    /// A fixed zone, so the day a refusal is keyed on is the same one wherever this runs.
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
final class FeedMotionTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeedMotionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    // MARK: - AC1: a fed Digimon chews

    func testAFedDigimonPlaysTheEatLoopAndTheChewMotion() async throws {
        let model = try await startedModel(named: "fed", hunger: 3, vitality: 20)

        XCTAssertEqual(model.feed(), .fed)
        XCTAssertEqual(model.animation, .eat, "the pose US-024 already published")
        XCTAssertEqual(model.actionMotion?.kind, .chew)
    }

    /// The chew is a VERTICAL bob, and downward — the Digimon leans into its bowl. Sampled through
    /// the shipped track rather than re-derived, so this checks the wiring picked the right motion
    /// and leaves the shape to `ActionMotionTests`.
    func testTheChewMovesTheSpriteVerticallyIntoTheBowl() async throws {
        let model = try await startedModel(named: "chew", hunger: 3, vitality: 20)
        model.feed()
        let motion = try XCTUnwrap(model.actionMotion)

        let mid = ActionMotion.offset(for: motion,
                                      at: motion.start.addingTimeInterval(
                                        ActionMotion.duration(of: .chew) / 6))
        XCTAssertEqual(mid.x, 0, "the chew has no sideways component")
        XCTAssertGreaterThan(mid.y, 0, "positive y is DOWN, i.e. into the food")
    }

    // MARK: - AC2: a refusal shakes its head

    func testARefusedFeedPlaysTheRefuseFrameAndTheShakeMotion() async throws {
        let model = try await startedModel(named: "refused", hunger: 0, vitality: 20)

        XCTAssertEqual(model.feed(), .refused)
        XCTAssertEqual(model.animation, .pose(.refuse), "the pose US-024 published, now looping (US-103)")
        XCTAssertEqual(model.actionMotion?.kind, .shake)
    }

    // MARK: - US-103: the refusal is a loop rather than one held frame

    /// Two frames, and the refuse frame FIRST: a refusal that opened on the walk frame would read
    /// as an ordinary step for half a second before the head turned away.
    func testTheRefusalAlternatesBetweenTheRefuseFrameAndTheWalkFrame() async throws {
        let model = try await startedModel(named: "refuseLoop", hunger: 0, vitality: 20)

        XCTAssertEqual(model.feed(), .refused)
        XCTAssertEqual(model.animation.stageFrames, [.refuse, .walk1])

        // Sampled through the shipped index rule at the pose's own beat, so this is the drawing the
        // screen actually puts up: what is shown at t is not what is shown at t + one beat.
        let beat = model.animation.frameDuration
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertNotEqual(SpriteAnimation.frameIndex(at: start, count: 2, duration: beat),
                          SpriteAnimation.frameIndex(at: start.addingTimeInterval(beat),
                                                     count: 2, duration: beat))
    }

    /// A refusal has to be legible without reading the caption, and what makes it legible is that it
    /// goes BOTH ways: a one-sided nudge is a flinch, a swing to each side is a "no".
    func testTheShakeSwingsToBothSidesHorizontally() async throws {
        let model = try await startedModel(named: "shake", hunger: 0, vitality: 20)
        model.feed()
        let motion = try XCTUnwrap(model.actionMotion)

        let duration = ActionMotion.duration(of: .shake)
        var lowest: CGFloat = 0
        var highest: CGFloat = 0
        for sample in stride(from: 0.0, through: duration, by: duration / 200) {
            let offset = ActionMotion.offset(for: motion,
                                             at: motion.start.addingTimeInterval(sample))
            XCTAssertEqual(offset.y, 0, "a head-shake is horizontal")
            lowest = min(lowest, offset.x)
            highest = max(highest, offset.x)
        }
        XCTAssertLessThan(lowest, 0)
        XCTAssertGreaterThan(highest, 0)
    }

    // MARK: - AC3: a blocked feed does not move at all

    /// Sleep stopped being a block at US-110 — a prodded Digimon wakes and eats — so what this pins
    /// now is the other half of AC3's rule: the woken feed is a WHOLE feed, chew and all. A wake
    /// that produced the eat loop without the motion would be exactly the "half-worked" reading the
    /// blocked cases are written to rule out. `testAFeedBlockedByDeathPlaysNoMotion` below is the
    /// blocked control this used to be.
    func testAFeedThatWakesTheDigimonStillChews() async throws {
        let model = try await startedModel(named: "asleep", hunger: 3, vitality: 20)
        model.isAsleep = true

        XCTAssertEqual(model.feed(), .fed)
        XCTAssertEqual(model.animation, .eat, "awake and eating, not resting")
        XCTAssertEqual(model.actionMotion?.kind, .chew)
        XCTAssertNil(model.actionMessage, "a meal eaten needs no caption")
    }

    func testAFeedBlockedByDeathPlaysNoMotion() async throws {
        let model = try await startedModel(named: "dead", hunger: 3, vitality: 20)
        model.state?.healthStatus = .dead

        guard case .blocked = model.feed() else { return XCTFail("expected a block") }
        XCTAssertNil(model.actionMotion)
        XCTAssertNotNil(model.actionMessage)
    }

    // MARK: - AC4/AC5: set and cleared with the pose, and it resumes where it stood

    /// The one property the whole design rests on: there is no window in which the pose and the
    /// motion disagree. Both are live straight after the feed, and both are gone once the hold
    /// expires — so a Digimon cannot go on bobbing after it has finished eating.
    func testTheMotionIsClearedWithThePose() async throws {
        let model = try await startedModel(named: "cleared", hunger: 3, vitality: 20)
        model.feed()
        XCTAssertNotNil(model.actionMotion)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.animation, .idle, "the pose is held, not stuck")
        XCTAssertNil(model.actionMotion, "and the motion went with it")
        XCTAssertTrue(model.isWandering, "so the walk resumes from exactly where it stood")
    }

    /// A second feed while the first is still held restarts the motion rather than leaving the first
    /// one running out underneath the new pose — `show` cancels and re-stamps both together.
    func testFeedingAgainRestartsTheMotionWithThePose() async throws {
        let model = try await startedModel(named: "again", hunger: 3, vitality: 20)
        model.feed()
        let first = try XCTUnwrap(model.actionMotion)

        model.feed()
        let second = try XCTUnwrap(model.actionMotion)
        XCTAssertEqual(second.kind, first.kind)
        XCTAssertEqual(model.animation, .eat)
    }

    /// A motion never runs while the walk does. Both would be legal to add — the view sums them —
    /// but the reason the sum is safe is that `isWandering` is false for every pose that carries a
    /// motion, so the walk is HELD for the motion's whole length.
    func testTheWalkIsHeldWhileAMotionRuns() async throws {
        let fed = try await startedModel(named: "held-fed", hunger: 3, vitality: 20)
        fed.feed()
        XCTAssertNotNil(fed.actionMotion)
        XCTAssertFalse(fed.isWandering)

        let refused = try await startedModel(named: "held-refused", hunger: 0, vitality: 20)
        refused.feed()
        XCTAssertNotNil(refused.actionMotion)
        XCTAssertFalse(refused.isWandering)
    }

    // MARK: - Fixtures

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// A Baby I with no outgoing edges, so nothing here can evolve and every change to the saved
    /// game is feeding's doing alone. The egg exists only because `start()` resolves a starting
    /// Digitama before it loads and throws `.noDigitama` without one — even when a saved game exists.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .babyI, spriteFile: "Botamon")
        ])
    }

    /// Seeds a saved game at "hero" with the given hunger and Vitality, then hands back a started
    /// model reading it off disk.
    private func startedModel(named name: String, hunger: Int, vitality: Int) async throws
        -> MainScreenModel {
        let url = storeURL(name)
        let seeding = try GameStore(url: url)
        let state = try seeding.loadOrCreate(digitamaId: "hero", now: Clock.start)
        state.currentDigimonId = "hero"
        state.stage = .babyI
        state.hunger = hunger
        state.stageEnergy[.vitality] = vitality
        try seeding.save()

        let model = MainScreenModel(
            makeStore: { try GameStore(url: url) },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Clock.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                  calendar: Clock.calendar)
            ),
            calendar: Clock.calendar,
            now: { Clock.start },
            chooseStartingDigitama: { $0.first },
            playFeedHaptic: {},
            // Milliseconds, so the clear is observable without waiting out the app's 2s. Shorter than
            // the shortest motion, so `show`'s repeat never fires here — the repeat is what fills the
            // app's full hold, and it is exercised by the Simulator demo rather than by a test that
            // would have to wait 1.2 real seconds to see it.
            actionDuration: 0.05
        )
        await model.start()
        XCTAssertEqual(model.phase, .playing)
        // Feeding spends meat since US-174; stock the larder so a fed test eats rather than blocks.
        model.profile?.meat = 10
        return model
    }
}
