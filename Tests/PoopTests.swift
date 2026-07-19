import CoreGraphics
import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-051 — poop that accumulates on a clock.
///
/// Two layers, like US-023's suite: `PoopClockTests` pins the pure rule, and `PoopStateTests`
/// drives the real `GameState` and the real `GameStore`, so the count is exercised through the
/// property that actually reaches disk.
///
/// No test waits real time. The "clock" is only ever two chosen `Date`s a fixed distance apart.

private enum Clock {
    static let start = Date(timeIntervalSinceReferenceDate: 700_000)
    static let hour: TimeInterval = 60 * 60

    static func after(_ hours: Double) -> Date { start.addingTimeInterval(hours * hour) }
}

final class PoopClockTests: XCTestCase {

    // MARK: - AC2: accumulation on an injected clock

    /// The headline number: 9 elapsed hours is exactly 3 poops at 3h each, not 2 and not 4.
    func testNineElapsedHoursAddsExactlyThreePoops() {
        let advanced = PoopClock.advance(poopCount: 0, lastUpdated: Clock.start,
                                         isPaused: false, now: Clock.after(9))
        XCTAssertEqual(advanced.poopCount, 3)
    }

    /// The interval boundary. 2h59m is worth nothing and 3h is worth one, so the unit really is 3h —
    /// a rate of "every couple of hours" would pass the 9h case above by accident.
    func testPoopAccruesOnlyOnWholeThreeHourIntervals() {
        let cases: [(hours: Double, expected: Int)] = [
            (0, 0), (2.98, 0), (3, 1), (5.9, 1), (6, 2), (8.9, 2), (9, 3), (12, 4)
        ]
        for (hours, expected) in cases {
            let advanced = PoopClock.advance(poopCount: 0, lastUpdated: Clock.start,
                                             isPaused: false, now: Clock.after(hours))
            XCTAssertEqual(advanced.poopCount, expected, "after \(hours)h")
        }
    }

    /// The part-worn interval is CARRIED, not discarded. Two 2h sessions must add the poop that four
    /// hours earned; stamping the timestamp to `now` on every call would leave the screen clean
    /// forever for anyone who opens the app more often than every three hours.
    func testAPartialIntervalIsCarriedAcrossCalls() {
        let first = PoopClock.advance(poopCount: 0, lastUpdated: Clock.start,
                                      isPaused: false, now: Clock.after(2))
        XCTAssertEqual(first.poopCount, 0, "2h alone is not a poop")

        let second = PoopClock.advance(poopCount: first.poopCount, lastUpdated: first.updatedAt,
                                       isPaused: false, now: Clock.after(4))
        XCTAssertEqual(second.poopCount, 1, "the first 2h was kept, so 4h total is one poop")
    }

    /// Calling repeatedly inside one interval is a no-op, which is what lets the main screen call
    /// this on every refresh without poop tracking how often the app is opened.
    func testRepeatedCallsWithinAnIntervalChangeNothing() {
        var count = 0
        var stamp: Date? = Clock.start
        for _ in 0..<5 {
            let advanced = PoopClock.advance(poopCount: count, lastUpdated: stamp,
                                             isPaused: false, now: Clock.after(2.5))
            count = advanced.poopCount
            stamp = advanced.updatedAt
        }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(stamp, Clock.start, "and the timestamp did not creep forward either")
    }

    /// A clock or timezone that moved backwards must not be read as poop cleaning itself, and must
    /// not leave a timestamp in the future that freezes accrual until the wall clock catches up.
    func testATimestampInTheFutureRestampsRatherThanAccruing() {
        let advanced = PoopClock.advance(poopCount: 1, lastUpdated: Clock.after(5),
                                         isPaused: false, now: Clock.start)
        XCTAssertEqual(advanced.poopCount, 1)
        XCTAssertEqual(advanced.updatedAt, Clock.start)
    }

    /// A save written before poop was tracked starts the clock now rather than back-filling a mess
    /// the user never had a chance to clean.
    func testAMissingTimestampStartsTheClockNow() {
        let advanced = PoopClock.advance(poopCount: 0, lastUpdated: nil,
                                         isPaused: false, now: Clock.after(48))
        XCTAssertEqual(advanced.poopCount, 0)
        XCTAssertEqual(advanced.updatedAt, Clock.after(48))
    }

    // MARK: - AC3: the ceiling

    /// Four is the ceiling, and a week of neglect does not push past it.
    func testTheCountIsCappedAtTheMaximum() {
        let advanced = PoopClock.advance(poopCount: 0, lastUpdated: Clock.start,
                                         isPaused: false, now: Clock.after(24 * 7))
        XCTAssertEqual(advanced.poopCount, PoopClock.maximumPoops)
        XCTAssertEqual(advanced.poopCount, 4)
    }

    /// Overshooting the ceiling applies only the intervals there was ROOM for, so the timestamp is
    /// left at the instant the ceiling was reached and not at `now`. US-053 measures how long the
    /// screen has been full from exactly that freeze.
    func testTheTimestampFreezesAtTheInstantTheCeilingWasReached() {
        let advanced = PoopClock.advance(poopCount: 2, lastUpdated: Clock.start,
                                         isPaused: false, now: Clock.after(30))
        XCTAssertEqual(advanced.poopCount, 4)
        XCTAssertEqual(advanced.updatedAt, Clock.after(6), "two poops' worth applied, not thirty hours")
    }

    /// And once at the ceiling nothing moves at all, however long passes.
    func testAtTheCeilingNothingAccruesAndTheTimestampHolds() {
        let advanced = PoopClock.advance(poopCount: PoopClock.maximumPoops, lastUpdated: Clock.start,
                                         isPaused: false, now: Clock.after(100))
        XCTAssertEqual(advanced.poopCount, PoopClock.maximumPoops)
        XCTAssertEqual(advanced.updatedAt, Clock.start)
    }

    // MARK: - AC5: paused while asleep or dead

    /// A paused stretch accrues nothing AND is skipped rather than banked: restamping to `now` is
    /// what stops the next waking refresh from paying out the whole night at once.
    func testAPausedCallAccruesNothingAndSkipsTheElapsedTime() {
        let advanced = PoopClock.advance(poopCount: 1, lastUpdated: Clock.start,
                                         isPaused: true, now: Clock.after(9))
        XCTAssertEqual(advanced.poopCount, 1, "nine hours asleep produced nothing")
        XCTAssertEqual(advanced.updatedAt, Clock.after(9), "and they were skipped, not banked")

        let afterWaking = PoopClock.advance(poopCount: advanced.poopCount,
                                            lastUpdated: advanced.updatedAt,
                                            isPaused: false, now: Clock.after(12))
        XCTAssertEqual(afterWaking.poopCount, 2, "only the 3 awake hours since counted")
    }
}

/// The same rule through the real model, the real store and the real save path.
@MainActor
final class PoopStateTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PoopTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func storeURL(_ name: String) -> URL {
        storeDirectory.appendingPathComponent("\(name).store")
    }

    /// AC2 through the model: a new game starts clean, with its clock stamped at the hatch.
    func testANewGameStartsCleanWithTheClockRunning() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Clock.start)
        XCTAssertEqual(state.poopCount, 0)
        XCTAssertEqual(state.poopUpdatedAt, Clock.start)
    }

    /// AC2/AC3 through `advancePoop`, which is what the main screen will call.
    func testAdvancePoopAgesTheCountAndHoldsAtTheCeiling() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Clock.start)

        state.advancePoop(isAsleep: false, now: Clock.after(7))
        XCTAssertEqual(state.poopCount, 2)

        state.advancePoop(isAsleep: false, now: Clock.after(48))
        XCTAssertEqual(state.poopCount, PoopClock.maximumPoops, "capped, not sixteen")
    }

    /// AC5: asleep produces nothing, through the same call the screen makes.
    func testASleepingDigimonProducesNoPoop() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Clock.start)
        state.advancePoop(isAsleep: true, now: Clock.after(9))
        XCTAssertEqual(state.poopCount, 0)
    }

    /// AC5: and neither does a dead one. Read off `healthStatus` rather than passed in, because
    /// unlike sleep, death IS saved-game state.
    func testADeadDigimonProducesNoPoop() {
        let state = GameState(currentDigimonId: "agu_digitama", now: Clock.start)
        state.healthStatus = .dead
        state.advancePoop(isAsleep: false, now: Clock.after(9))
        XCTAssertEqual(state.poopCount, 0)
    }

    /// AC6: the count and its timestamp survive a relaunch. The container is dropped and reopened on
    /// the same file, which is as close to quitting the app as a test gets.
    func testThePoopCountPersistsAcrossLaunches() async throws {
        let url = storeURL("Persist")

        do {
            let store = try GameStore(url: url)
            let state = try store.loadOrCreate(digitamaId: "hero", now: Clock.start)
            state.advancePoop(isAsleep: false, now: Clock.after(7))
            XCTAssertEqual(state.poopCount, 2)
            try store.save()
        }

        let reopened = try GameStore(url: url)
        let loaded = try reopened.loadOrCreate(digitamaId: "other", now: Clock.after(7))
        XCTAssertEqual(loaded.currentDigimonId, "hero", "the same saved game came back")
        XCTAssertEqual(loaded.poopCount, 2)
        XCTAssertEqual(loaded.poopUpdatedAt, Clock.after(6),
                       "and the frozen part-interval came with it")
    }

    /// AC6's other half: a reopened game can be advanced and SAVED again.
    ///
    /// Worth its own test because that is where an optional-backed property earns its keep. This
    /// does NOT open a genuinely pre-poop store — writing one would need a second `@Model` copy of
    /// the whole schema, as `DominantEnergyTests` does — so it proves the round trip, not the
    /// migration. The optionality itself is argued for on `poopCountStorage`.
    func testAReopenedGameCanBeAdvancedAndSavedAgain() async throws {
        let url = storeURL("Resave")

        do {
            let store = try GameStore(url: url)
            _ = try store.loadOrCreate(digitamaId: "hero", now: Clock.start)
            try store.save()
        }

        let reopened = try GameStore(url: url)
        let loaded = try reopened.loadOrCreate(digitamaId: "other", now: Clock.after(1))
        XCTAssertEqual(loaded.poopCount, 0)
        loaded.advancePoop(isAsleep: false, now: Clock.after(4))
        XCTAssertEqual(loaded.poopCount, 1)
        XCTAssertNoThrow(try reopened.save())
    }
}

/// US-052 — what the mess looks like.
///
/// A SwiftUI shape has no output a unit test can read, so what is pinned here is the arithmetic
/// that decides whether it FITS. That the pile actually looks like poop, and sits beside the
/// Digimon rather than under it, is a Simulator screenshot recorded in progress.txt.
final class PoopPileTests: XCTestCase {
    /// The reason `PoopClock.maximumPoops` is four: a full pile has to fit the room left beside a
    /// full-scale sprite on the narrowest supported screen (176pt at 41mm), or the last poop is
    /// drawn off the bezel and neglect stops being visible at exactly the point it matters most.
    func testAFullPileFitsBesideTheDigimon() {
        let count = CGFloat(PoopClock.maximumPoops)
        let spacing: CGFloat = 3
        let pile = count * PoopShape.baseWidth + (count - 1) * spacing

        let sprite = SpriteScale.maximum * CGFloat(SpriteSheet.frameSize)
        let roomBesideIt = (176 - sprite) / 2

        XCTAssertLessThanOrEqual(pile, roomBesideIt)
    }

    /// A poop is smaller than the Digimon standing next to it. Obvious, and exactly the kind of
    /// thing a "just make it a bit clearer" edit breaks — at which point the screen reads as five
    /// characters rather than one Digimon and its mess.
    func testOnePoopIsSmallerThanTheSprite() {
        XCTAssertLessThan(PoopShape.baseWidth, SpriteScale.minimum * CGFloat(SpriteSheet.frameSize))
    }
}

// MARK: - US-053: uncleaned poop as neglect

/// US-053 — a full screen left uncleaned charges care mistakes, and enough of them make the
/// Digimon sick.
///
/// Every fixture here neutralises the OTHER two rules `auditCareMistakes` runs — hunger is empty
/// and health data was seen at this very instant — so any movement in `careMistakeCount` belongs to
/// the rule under test and nothing else.
final class PoopNeglectTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// A Digimon standing in a full screen of poop since `fullSince`.
    ///
    /// `poopUpdatedAt` is set rather than accrued because that is precisely the fixture's premise:
    /// `PoopClock.advance` freezes the timestamp at the instant the ceiling was reached, and this
    /// state is one that reached it then.
    private func fullState(since fullSince: Date) -> GameState {
        let state = GameState(currentDigimonId: "hero", stage: .babyI, now: fullSince)
        state.hunger = 0
        state.poopCount = PoopClock.maximumPoops
        state.poopUpdatedAt = fullSince
        return state
    }

    private func audit(_ state: GameState, at now: Date) {
        state.healthDataLastSeen = now
        state.auditCareMistakes(now: now, health: .seen, calendar: calendar)
    }

    // MARK: AC1 — the threshold

    /// The boundary, and the fact that it is a CEILING rather than a rate. Six hours at maximum poop
    /// is worth one mistake and 5h59m is worth none, so the unit really is six hours — but a day and
    /// a week are also worth exactly one, because the spell is charged once.
    ///
    /// That last column is the load-bearing one: see `secondsAtMaximumPoopBeforeMistake`. Sleep
    /// pauses poop only when a refresh runs to observe it, so a rate would score the same 48 hours
    /// differently depending on whether the app was open — which is what
    /// `ClosedAppRecomputeTests.testFortyEightHoursShutMatchesFortyEightHoursOpen` forbids.
    func testOneMistakeIsChargedPerSpellAtTheCeilingHoweverLongItLasts() {
        let cases: [(hours: Double, expected: Int)] = [
            (0, 0), (5.9, 0), (6, 1), (11.9, 1), (12, 1), (24, 1), (24 * 7, 1)
        ]
        for (hours, expected) in cases {
            let state = fullState(since: Clock.start)
            audit(state, at: Clock.after(hours))
            XCTAssertEqual(state.careMistakeCount, expected, "at \(hours)h full")
        }
    }

    /// AC2, the headline: the audit runs on every foregrounding, and seven hours of neglect is one
    /// mistake however many times anyone looks at it.
    func testTheMistakeIsChargedOnceNotOnEveryRefresh() {
        let state = fullState(since: Clock.start)

        for _ in 0..<5 { audit(state, at: Clock.after(7)) }

        XCTAssertEqual(state.careMistakeCount, 1)
        XCTAssertEqual(state.poopMistakesCharged, 1, "and the marker records what was charged")
    }

    /// Only a FULL screen counts. One poop is a Digimon that has been alive three hours, not one
    /// anybody has neglected — so nothing below the ceiling is ever charged, however long it sits.
    func testPoopBelowTheCeilingIsNeverAMistake() {
        let state = fullState(since: Clock.start)
        state.poopCount = PoopClock.maximumPoops - 1

        audit(state, at: Clock.after(48))

        XCTAssertEqual(state.careMistakeCount, 0)
    }

    /// AC4: cleaning stops the charging. The marker is cleared with the spell, so the screen's next
    /// fill is measured from the clean rather than inheriting a tally that would make its first hour
    /// instantly another mistake.
    func testCleaningStopsFurtherCharging() {
        let state = fullState(since: Clock.start)
        audit(state, at: Clock.after(7))
        XCTAssertEqual(state.careMistakeCount, 1)

        // Cleaned, exactly as `MainScreenModel.clean()` does it: zeroed and restamped.
        state.poopCount = 0
        state.poopUpdatedAt = Clock.after(7)
        audit(state, at: Clock.after(30))
        XCTAssertEqual(state.careMistakeCount, 1, "a clean screen is not being neglected")
        XCTAssertEqual(state.poopMistakesCharged, 0, "and the spell's tally was cleared")

        // Full again, from the new stamp: six hours from THERE, not from the old spell. This is the
        // only way to be charged twice, and it is the fair one — letting the screen fill AGAIN after
        // cleaning is a second act of neglect.
        state.poopCount = PoopClock.maximumPoops
        state.poopUpdatedAt = Clock.after(30)
        audit(state, at: Clock.after(35))
        XCTAssertEqual(state.careMistakeCount, 1, "five hours into the new spell is not yet a mistake")
        audit(state, at: Clock.after(36))
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    /// An absurd elapsed time must not trap. Starvation needs a saturation ceiling for this because
    /// it converts `elapsed / threshold` to `Int`; charging once per spell never converts anything,
    /// so the answer here is simply one.
    func testAnAbsurdSpellIsStillOneMistakeAndDoesNotTrap() {
        let state = fullState(since: .distantPast)

        audit(state, at: .distantFuture)

        XCTAssertEqual(state.careMistakeCount, 1)
    }

    // MARK: AC3 — the sickness path

    /// The point of the whole story: a filthy screen makes the Digimon ill, through the EXISTING
    /// `Sickness` path — nothing here knows what illness is, it only feeds the counter
    /// `updateSickness` already reads.
    ///
    /// One spell is one mistake, so poop is the mistake that TIPS a Digimon already one short of the
    /// threshold rather than one that can carry it there alone. That is the honest shape of the rule
    /// after AC2: a single uncleaned screen is one act of neglect, and illness is what a Digimon
    /// neglected in several ways at once gets.
    func testAFullScreenIsTheMistakeThatTipsADigimonIntoSickness() {
        let state = fullState(since: Clock.start)
        state.careMistakeCount = Sickness.careMistakesUntilSick - 1

        audit(state, at: Clock.after(5))
        state.updateSickness(energyEarnedToday: 0)
        XCTAssertEqual(state.careMistakeCount, Sickness.careMistakesUntilSick - 1,
                       "five hours at the ceiling has not yet crossed the threshold")
        XCTAssertEqual(state.healthStatus, .healthy)

        audit(state, at: Clock.after(6))

        XCTAssertEqual(state.careMistakeCount, Sickness.careMistakesUntilSick)
        state.updateSickness(energyEarnedToday: 0)
        XCTAssertEqual(state.healthStatus, .sick)
    }
}
