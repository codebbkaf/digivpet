import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-099 — the light button and the dimmed screen.
///
/// Two layers, like US-098's suite: `LightCycleTests` pins the pure cycle and what each state is
/// drawn as, and `LightButtonModelTests` drives the real `MainScreenModel` over a real `GameStore`,
/// so what is asserted is what the button's own handler does and what reaches disk.
///
/// What cannot be asserted here is the layering: that the scrim covers the sprite's slot and only
/// that (US-112), that the button — a toolbar item beside the Dex book since US-114, rather than a
/// lamp hanging in the corner of the room it lights — is outside the scrim's reach entirely, and
/// that the ceremony, battle, training and memorial overlays are never dimmed. Those are Simulator
/// screenshots, recorded in progress.txt.
///
/// No test waits real time.

private enum SwitchClock {
    /// Los Angeles, well away from UTC, for the same reason `LightTests` picks it.
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

    /// Midday, so the fallback 22:00–07:00 window has the Digimon awake — the light is a switch on
    /// the wall at any hour, and a sleeping Digimon would confound the "nothing is blocked" tests
    /// with a block that has nothing to do with the light.
    static let noon = at("2026-03-10 12:00")
}

/// No steps, calories or exercise minutes — nothing here is about earned energy, and the model is
/// funded by hand where a test needs it spendable.
private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

/// No sleep history, so the schedule stays at the 22:00–07:00 fallback and midday is awake.
private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - AC1: the cycle

final class LightCycleTests: XCTestCase {
    /// THE AC: one button, three states, in the order a room goes through at bedtime.
    func testTheLightCyclesOnThenSemiThenOffThenBack() {
        XCTAssertEqual(LightState.on.next, .semi)
        XCTAssertEqual(LightState.semi.next, .off)
        XCTAssertEqual(LightState.off.next, .on)
    }

    /// Three taps from anywhere come back to where they started — the cycle closes, so no state is
    /// reachable only once and none is a dead end.
    func testThreeTapsReturnToTheStateItStartedIn() {
        for start in LightState.allCases {
            XCTAssertEqual(start.next.next.next, start, "\(start) did not come back round")
        }
        // And the cycle visits all three on the way, rather than flipping between two of them.
        XCTAssertEqual(Set([LightState.on, .on.next, .on.next.next]), Set(LightState.allCases))
    }

    /// The three symbols the AC names, each to its own state. Distinct, or the button says nothing
    /// about which of the three the room is in.
    func testEachStateDrawsTheSymbolTheStoryNames() {
        XCTAssertEqual(LightState.on.symbolName, "lightbulb.fill")
        XCTAssertEqual(LightState.semi.symbolName, "lightbulb.led.fill")
        XCTAssertEqual(LightState.off.symbolName, "lightbulb.slash")
        XCTAssertEqual(Set(LightState.allCases.map(\.symbolName)).count, 3)
    }

    /// AC3, as far as arithmetic reaches: only `on` draws nothing, the other two really do darken,
    /// and neither goes all the way to black — the button and the Digimon have to stay visible.
    func testOnlyTheLitStateDrawsNoScrim() {
        XCTAssertEqual(LightState.on.dimOpacity, 0)
        XCTAssertGreaterThan(LightState.semi.dimOpacity, 0)
        XCTAssertGreaterThan(LightState.off.dimOpacity, LightState.semi.dimOpacity)
        XCTAssertLessThan(LightState.off.dimOpacity, 1)
    }
}

// MARK: - AC5/AC6: what the button does

@MainActor
final class LightButtonModelTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("LightSwitch.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LightSwitchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// The real bundled graph, because two of these tests need a Digimon with an opponent to fight
    /// and a sheet to pose with; the light itself does not care which one it is.
    private func makeModel(now: Date = SwitchClock.noon) -> MainScreenModel {
        MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: SwitchClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: SwitchClock.calendar)
            ),
            calendar: SwitchClock.calendar,
            now: { now },
            chooseStartingDigitama: { $0.first },
            actionDuration: 0.05
        )
    }

    /// A started game on a Child that can eat, train and fight, awake and healthy — everything the
    /// blocking tests need to be about the light and nothing else.
    private func startedModel() async throws -> MainScreenModel {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        state.currentDigimonId = "agumon"
        state.stage = .child
        state.stageEnteredDate = SwitchClock.noon
        state.hunger = 2
        state.stageEnergy[.vitality] = 30
        state.stageEnergy[.strength] = 30
        model.isAsleep = false
        return model
    }

    /// THE AC: tapping the button walks the light round the cycle.
    func testTappingTheButtonCyclesTheLight() async throws {
        let model = try await startedModel()
        XCTAssertEqual(model.lightState, .on, "a new game starts lit")

        XCTAssertEqual(model.cycleLight(), .semi)
        XCTAssertEqual(model.lightState, .semi)
        XCTAssertEqual(model.cycleLight(), .off)
        XCTAssertEqual(model.lightState, .off)
        XCTAssertEqual(model.cycleLight(), .on)
        XCTAssertEqual(model.lightState, .on)
    }

    /// The tap stamps "since when" as well as the state, which is the pair US-101's rule reads. A
    /// light put out at bedtime carrying yesterday's stamp would be judged on the wrong night.
    func testTheTapStampsWhenTheLightChanged() async throws {
        let model = try await startedModel()
        model.cycleLight()

        XCTAssertEqual(model.state?.lightStateChangedAt, SwitchClock.noon)
    }

    /// AC5, end to end: turned down, then read back through a SECOND model on the same file, so what
    /// is asserted came off disk rather than out of the first one's memory.
    func testTheLightSurvivesRelaunch() async throws {
        let first = try await startedModel()
        first.cycleLight()
        first.cycleLight()
        XCTAssertEqual(first.lightState, .off)

        let second = makeModel()
        await second.start()
        XCTAssertEqual(second.lightState, .off, "the relaunched game came up in the dark")
    }

    /// AC6, the first half: the light is not neglect. Nine taps — three whole cycles, so every state
    /// is entered and left — and the care record is untouched.
    func testChangingTheLightIsNeverACareMistake() async throws {
        let model = try await startedModel()
        let before = try XCTUnwrap(model.state?.careMistakeCount)

        for _ in 0..<9 { model.cycleLight() }

        XCTAssertEqual(model.state?.careMistakeCount, before)
        XCTAssertNil(model.state?.lightAuditedNight, "no night was charged for by a tap")
    }

    /// AC6, the second half: with the light OUT, all four actions still work. Not "the buttons are
    /// still on screen" — each is actually taken, and each produces the outcome it produces in a lit
    /// room.
    func testTheLightBlocksNoneOfTheFourActions() async throws {
        let model = try await startedModel()
        model.cycleLight()
        model.cycleLight()
        XCTAssertEqual(model.lightState, .off)

        XCTAssertEqual(model.feed(), .fed(cost: FeedAction.vitalityCostPerFeed))

        model.state?.poopCount = 2
        XCTAssertTrue(model.clean())

        XCTAssertNotNil(model.train(), "training opened its round in the dark")
        model.abandonTraining()

        XCTAssertNotNil(model.battle(), "the battle opened its round in the dark")
    }

    /// The control for the test above: the actions are not simply unblockable. A DEAD Digimon
    /// refuses the same feed in the same darkness, so what the test above measured is the light
    /// having no say rather than nothing having any say.
    ///
    /// A dead one and not a sleeping one, since US-110: a sleeping Digimon is now WOKEN by the tap
    /// and fed, so it stopped being an example of anything blocked. Death is the block that stands.
    func testAnActionThatIsBlockedIsStillBlockedInTheDark() async throws {
        let model = try await startedModel()
        model.cycleLight()
        model.cycleLight()
        model.state?.healthStatus = .dead

        XCTAssertEqual(model.feed(), .blocked(reason: "It cannot eat."))
    }

    /// A tap with no saved game is a no-op rather than a crash — the same shape as `feed()` and
    /// `clean()` on a game that failed to open.
    func testTappingTheLightWithNoGameDoesNothing() async {
        struct Boom: Error {}
        let model = MainScreenModel(
            makeStore: { throw Boom() },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: SwitchClock.calendar),
                sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                                  calendar: SwitchClock.calendar)
            ),
            calendar: SwitchClock.calendar,
            now: { SwitchClock.noon }
        )
        await model.start()

        XCTAssertNil(model.cycleLight())
        XCTAssertEqual(model.lightState, .on, "and an unopened game draws an undimmed screen")
    }
}
