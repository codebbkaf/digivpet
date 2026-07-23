import XCTest

@testable import DigiVPet

/// US-214 — the per-Digimon bedtime / wake / nap shown on the Sleep Time screen.
///
/// The whole point of this type is a promise a screenshot cannot check: the times are a PURE
/// function of the id, stable across launches and devices, and different Digimon get different
/// hours. So the assertions here are determinism, distinctness, the bands every routine has to land
/// inside, and — the one that catches the failure mode nothing else would — literal seeds, which go
/// red the moment somebody swaps FNV-1a for `String.hashValue`.
final class SleepRoutineTests: XCTestCase {
    // MARK: - AC3: determinism

    /// The same id gives the same routine, every time it is asked. Asked repeatedly rather than
    /// twice, because a generator accidentally held as shared state would only drift after a few
    /// draws.
    func testTheSameDigimonAlwaysGetsTheSameTimes() {
        let first = SleepRoutine.forDigimon(id: "agumon")
        for _ in 0..<20 {
            XCTAssertEqual(SleepRoutine.forDigimon(id: "agumon"), first)
        }
    }

    /// The seed is pinned to literals. This is the test that fails if the derivation is ever moved
    /// onto `String.hashValue`, which is per-process seeded: those routines would look perfectly
    /// plausible in a single run and change on the next launch.
    func testTheSeedIsAFixedFunctionOfTheIdAndNotSwiftsHash() {
        XCTAssertEqual(SleepRoutine.seed(for: "agumon"), 0xd8b1_0172_b8f8_25ce)
        XCTAssertEqual(SleepRoutine.seed(for: "gabumon"), 0x003e_775a_2fb1_ee62)
        XCTAssertEqual(SleepRoutine.seed(for: ""), 0xcbf2_9ce4_8422_2325,
                       "the empty id is the FNV-1a offset basis")
    }

    /// The times themselves, pinned for two shipped Digimon. A change to the bands or the draw ORDER
    /// is a change to every player's pet, so it should have to be made on purpose.
    func testTwoShippedDigimonHaveTheirTimesPinned() {
        let agumon = SleepRoutine.forDigimon(id: "agumon")
        XCTAssertEqual(agumon.bedtime, WatchTime(hour: 23, minute: 15))
        XCTAssertEqual(agumon.wakeTime, WatchTime(hour: 6, minute: 15))
        XCTAssertEqual(agumon.napStart, WatchTime(hour: 14, minute: 15))
        XCTAssertEqual(agumon.napEnd, WatchTime(hour: 14, minute: 45))

        let gabumon = SleepRoutine.forDigimon(id: "gabumon")
        XCTAssertEqual(gabumon.bedtime, WatchTime(hour: 21, minute: 45))
        XCTAssertEqual(gabumon.wakeTime, WatchTime(hour: 7, minute: 0))
        XCTAssertEqual(gabumon.napStart, WatchTime(hour: 13, minute: 45))
        XCTAssertEqual(gabumon.napEnd, WatchTime(hour: 14, minute: 45))
    }

    // MARK: - AC3: distinctness

    /// Known ids differ from each other — pairwise, so a derivation that collapsed half the roster
    /// onto one bedtime could not pass by having its one named pair happen to differ.
    func testDifferentDigimonGetDifferentTimes() {
        let ids = ["agumon", "gabumon", "greymon", "palmon", "betamon", "patamon"]
        var seen: [String: SleepRoutine] = [:]
        for id in ids {
            let routine = SleepRoutine.forDigimon(id: id)
            for (other, otherRoutine) in seen {
                XCTAssertNotEqual(routine, otherRoutine, "\(id) sleeps exactly like \(other)")
            }
            seen[id] = routine
        }
    }

    /// And the whole roster spreads, rather than six lucky names. Measured: 996 distinct routines
    /// across the 1,022 bundled ids — 18,785 routines exist, so the couple of dozen collisions are
    /// the birthday bound and not a flaw. The floor is set well under that so a roster edit cannot
    /// fail this, while a derivation that started ignoring part of the id would fall far through it.
    func testTheRosterSpreadsAcrossManyDistinctRoutines() {
        let ids = Roster.bundled.entries.map(\.id)
        XCTAssertGreaterThan(ids.count, 900, "sanity: the bundled roster is the big one")

        let distinct = Set(ids.map { id -> [Int] in
            let routine = SleepRoutine.forDigimon(id: id)
            return [routine.bedtime.minutes, routine.nightMinutes,
                    routine.napStart.minutes, routine.napMinutes]
        })
        XCTAssertGreaterThan(distinct.count, ids.count * 3 / 4,
                             "\(distinct.count) distinct routines across \(ids.count) Digimon")
    }

    // MARK: - AC2 / AC4: the shape of a routine

    /// Every routine in the game lands inside the authored bands, and its nap is a real window.
    /// Run over the whole roster because the bands are a promise about EVERY Digimon, not about the
    /// handful anyone will screenshot.
    func testEveryRoutineLandsInsideItsBands() {
        for id in Roster.bundled.entries.map(\.id) {
            let routine = SleepRoutine.forDigimon(id: id)

            // Bedtime: 20:00 through midnight, which normalises to 00:00 — so it is either in the
            // evening band or exactly midnight.
            let bed = routine.bedtime.minutes
            XCTAssertTrue(bed >= 20 * 60 || bed == 0, "\(id) goes to bed at \(routine.bedtime.formatted)")

            XCTAssertGreaterThanOrEqual(routine.nightMinutes, 7 * 60, "\(id)'s night")
            XCTAssertLessThanOrEqual(routine.nightMinutes, 10 * 60, "\(id)'s night")
            XCTAssertEqual(routine.bedtime.minutes(until: routine.wakeTime), routine.nightMinutes,
                           "\(id) wakes exactly a night after it went to bed")

            XCTAssertGreaterThanOrEqual(routine.napStart.minutes, 12 * 60, "\(id)'s nap start")
            XCTAssertLessThanOrEqual(routine.napStart.minutes, 16 * 60, "\(id)'s nap start")
            XCTAssertGreaterThanOrEqual(routine.napMinutes, 30, "\(id)'s nap")
            XCTAssertLessThanOrEqual(routine.napMinutes, 90, "\(id)'s nap")
            XCTAssertEqual(routine.napStart.minutes(until: routine.napEnd), routine.napMinutes,
                           "\(id)'s nap ends exactly a nap after it starts")

            XCTAssertEqual(routine.totalMinutes, routine.nightMinutes + routine.napMinutes,
                           "the day's rest is the night plus the nap")

            for time in [routine.bedtime, routine.wakeTime, routine.napStart, routine.napEnd] {
                XCTAssertEqual(time.minutes % 15, 0,
                               "\(id) has a time off the quarter hour: \(time.formatted)")
            }
        }
    }

    /// Every id answers, including ones no save can hold — the screen has to draw something for
    /// whatever is on it, so there is no nil branch to get wrong.
    func testEveryIdAnswersIncludingTheEmptyOne() {
        XCTAssertEqual(SleepRoutine.forDigimon(id: ""), SleepRoutine.forDigimon(id: ""))
        XCTAssertGreaterThan(SleepRoutine.forDigimon(id: "").totalMinutes, 0)
        XCTAssertGreaterThan(SleepRoutine.forDigimon(id: "not-a-digimon").totalMinutes, 0)
        XCTAssertGreaterThan(SleepRoutine.forDigimon(id: "🥚").totalMinutes, 0,
                             "the seed walks UTF-8 bytes, so a multi-byte id is not a crash")
    }

    // MARK: - AC6: how it reads

    /// 24-hour, zero-padded, exactly the `22:30` / `07:00` form the AC names — and independent of the
    /// device's 12/24-hour setting, which is why it is not a `DateFormatter`.
    func testTimesAreFormattedForTheWatch() {
        XCTAssertEqual(WatchTime(hour: 22, minute: 30).formatted, "22:30")
        XCTAssertEqual(WatchTime(hour: 7, minute: 0).formatted, "07:00")
        XCTAssertEqual(WatchTime(hour: 0, minute: 5).formatted, "00:05")
        XCTAssertEqual(WatchTime(hour: 24, minute: 0).formatted, "00:00", "midnight wraps to the day's start")
    }

    /// The wrap is the whole reason these are minutes and not `Date`s: a night that crosses midnight
    /// is a positive length, and arithmetic past either end of the day stays inside it.
    func testTimeArithmeticWrapsAroundMidnight() {
        XCTAssertEqual(WatchTime(hour: 22, minute: 30).adding(minutes: 8 * 60 + 30),
                       WatchTime(hour: 7, minute: 0))
        XCTAssertEqual(WatchTime(hour: 22, minute: 30).minutes(until: WatchTime(hour: 7, minute: 0)),
                       8 * 60 + 30)
        XCTAssertEqual(WatchTime(hour: 1, minute: 0).adding(minutes: -90), WatchTime(hour: 23, minute: 30))
        XCTAssertEqual(WatchTime(minutesSinceMidnight: -15), WatchTime(hour: 23, minute: 45))
    }

    /// Durations read the way the screen's headline does — `6 h` — with the minutes only when there
    /// are any, and a sub-hour nap as minutes alone.
    func testDurationsReadInWatchSizedUnits() {
        XCTAssertEqual(SleepRoutine.durationText(minutes: 8 * 60), "8 h")
        XCTAssertEqual(SleepRoutine.durationText(minutes: 8 * 60 + 30), "8 h 30 m")
        XCTAssertEqual(SleepRoutine.durationText(minutes: 45), "45 m")
        XCTAssertEqual(SleepRoutine.durationText(minutes: 0), "0 m")
        XCTAssertEqual(SleepRoutine.durationText(minutes: -60), "0 m", "a negative span is not a negative label")
    }

    /// AC4: the nap is counted into the day and labelled, so a player can see which part of the
    /// total it is rather than wondering whether it was included.
    func testTheNapIsLabelledInsideTheDaysTotal() {
        let gabumon = SleepRoutine.forDigimon(id: "gabumon")
        XCTAssertEqual(gabumon.nightMinutes, 9 * 60 + 15)
        XCTAssertEqual(gabumon.napMinutes, 60)
        XCTAssertEqual(gabumon.totalMinutes, 10 * 60 + 15)
        XCTAssertEqual(gabumon.splitText, "9 h 15 m night + 1 h nap")
        XCTAssertEqual(gabumon.napWindowText, "13:45 – 14:45")
        XCTAssertEqual(SleepRoutine.durationText(minutes: gabumon.totalMinutes), "10 h 15 m")
    }
}
