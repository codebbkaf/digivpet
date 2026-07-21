import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// US-098 — the light's state and the lights-out rule.
///
/// No test waits real time. Every "clock" here is a chosen `Date` in a fixed time zone, and every
/// entry point under test takes both `now` and the calendar, which is what makes that possible.

private enum LightClock {
    /// Los Angeles, well away from UTC, so a night boundary computed in the wrong time zone is
    /// caught rather than passing by coincidence.
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

    static let minute: TimeInterval = 60

    /// The ordinary 22:00–07:00 window, wrapping midnight.
    static let night = SleepSchedule.fallback

    /// A night-shift worker's 02:00–10:00 window, which does NOT wrap midnight — the second branch
    /// of every question asked below.
    static let dayShift = SleepSchedule(bedtimeMinute: 2 * 60, wakeMinute: 10 * 60)
}

// MARK: - AC1: the three states

final class LightStateTests: XCTestCase {
    /// The raw values are the persisted spelling, so a rename here rewrites saved games.
    func testTheThreeStatesPersistUnderTheirOwnNames() {
        XCTAssertEqual(LightState.allCases, [.on, .semi, .off])
        XCTAssertEqual(LightState.on.rawValue, "on")
        XCTAssertEqual(LightState.semi.rawValue, "semi")
        XCTAssertEqual(LightState.off.rawValue, "off")
        XCTAssertEqual(LightState(rawValue: "semi"), .semi)
    }

    func testEachStateDimsTheScreenByItsOwnAmount() {
        XCTAssertEqual(LightState.on.dimOpacity, 0)
        XCTAssertEqual(LightState.semi.dimOpacity, 0.5)
        XCTAssertEqual(LightState.off.dimOpacity, 0.85)
    }

    /// Distinct, or the button would say nothing about which state a tap had reached.
    func testEachStateHasItsOwnSymbolAndName() {
        let symbols = LightState.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, LightState.allCases.count)
        XCTAssertEqual(LightState.off.symbolName, "lightbulb.slash")

        let names = LightState.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, LightState.allCases.count)
        XCTAssertFalse(names.contains(where: \.isEmpty))
    }

    func testAStateRoundTripsThroughCoding() throws {
        let data = try JSONEncoder().encode(LightState.semi)
        XCTAssertEqual(try JSONDecoder().decode(LightState.self, from: data), .semi)
    }
}

// MARK: - AC3: which night `now` belongs to

final class LightsOutWindowTests: XCTestCase {
    private let calendar = LightClock.calendar

    private func start(_ iso: String, _ schedule: SleepSchedule = LightClock.night) -> Date? {
        LightsOutRule.windowStart(containing: LightClock.at(iso), schedule: schedule,
                                  calendar: calendar)
    }

    /// The two halves of one wrapping night resolve to the SAME start — the whole reason a night
    /// cannot be keyed on a local day.
    func testBothSidesOfMidnightBelongToTheNightThatBegan() {
        let bedtime = LightClock.at("2026-03-10 22:00")
        XCTAssertEqual(start("2026-03-10 22:00"), bedtime, "bedtime itself is inside")
        XCTAssertEqual(start("2026-03-10 23:59"), bedtime)
        XCTAssertEqual(start("2026-03-11 00:00"), bedtime, "midnight is still last night")
        XCTAssertEqual(start("2026-03-11 06:59"), bedtime)
    }

    func testAnAwakeDigimonIsInNoWindowAtAll() {
        XCTAssertNil(start("2026-03-10 21:59"), "one minute before bedtime")
        XCTAssertNil(start("2026-03-11 07:00"), "waking is exclusive")
        XCTAssertNil(start("2026-03-11 14:00"), "the middle of the afternoon")
    }

    /// The non-wrapping branch: 02:00–10:00 is one contiguous stretch of a single day.
    func testANightShiftWindowNeverReachesBackToYesterday() {
        let bedtime = LightClock.at("2026-03-11 02:00")
        XCTAssertEqual(start("2026-03-11 02:00", LightClock.dayShift), bedtime)
        XCTAssertEqual(start("2026-03-11 09:59", LightClock.dayShift), bedtime)
        XCTAssertNil(start("2026-03-11 01:59", LightClock.dayShift))
        XCTAssertNil(start("2026-03-11 10:00", LightClock.dayShift))
        XCTAssertNil(start("2026-03-11 23:00", LightClock.dayShift))
    }

    /// `mostRecentWindowStart` is the wider question the care mistake asks: the night just gone,
    /// answered on a morning when `windowStart(containing:)` is already nil.
    func testTheMostRecentWindowSurvivesTheDigimonWakingUp() {
        let lastNight = LightClock.at("2026-03-10 22:00")
        for hour in ["2026-03-11 07:00", "2026-03-11 14:00", "2026-03-11 21:59"] {
            XCTAssertEqual(
                LightsOutRule.mostRecentWindowStart(at: LightClock.at(hour),
                                                    schedule: LightClock.night, calendar: calendar),
                lastNight, "at \(hour)")
        }
        // And rolls over the instant tonight's bedtime arrives.
        XCTAssertEqual(
            LightsOutRule.mostRecentWindowStart(at: LightClock.at("2026-03-11 22:00"),
                                                schedule: LightClock.night, calendar: calendar),
            LightClock.at("2026-03-11 22:00"))
    }
}

// MARK: - AC4: the nudge

final class LightsOutNotifyTests: XCTestCase {
    private let calendar = LightClock.calendar

    private func shouldNotify(_ iso: String, light: LightState = .on,
                              lastNotifiedNight: Date? = nil) -> Bool {
        LightsOutRule.shouldNotify(now: LightClock.at(iso), schedule: LightClock.night,
                                   lightState: light, lastNotifiedNight: lastNotifiedNight,
                                   calendar: calendar)
    }

    func testTheNudgeWaitsForTheTenMinuteGrace() {
        XCTAssertEqual(LightsOutRule.notifyGrace, 10 * LightClock.minute)
        XCTAssertFalse(shouldNotify("2026-03-10 22:09"))
        XCTAssertTrue(shouldNotify("2026-03-10 22:10"))
        XCTAssertTrue(shouldNotify("2026-03-11 03:00"), "still owed in the small hours")
    }

    func testADimmedLightIsStillALightLeftOn() {
        XCTAssertTrue(shouldNotify("2026-03-10 22:30", light: .semi))
    }

    func testNothingIsOwedWhenTheLightIsAlreadyOut() {
        XCTAssertFalse(shouldNotify("2026-03-10 22:30", light: .off))
    }

    func testNothingIsOwedWhileTheDigimonIsAwake() {
        XCTAssertFalse(shouldNotify("2026-03-10 21:59"))
        XCTAssertFalse(shouldNotify("2026-03-11 08:00"))
    }

    /// Once a night, however many refreshes land in it — and re-armed by the next night.
    func testTheNightAlreadyNotifiedIsNotNotifiedAgain() {
        let night = LightClock.at("2026-03-10 22:00")
        XCTAssertFalse(shouldNotify("2026-03-11 02:00", lastNotifiedNight: night))
        XCTAssertTrue(shouldNotify("2026-03-11 23:00", lastNotifiedNight: night))
    }
}

// MARK: - AC5/AC6/AC7/AC9: the mistake

final class LightsOutMistakeTests: XCTestCase {
    private let calendar = LightClock.calendar

    private func shouldCharge(_ iso: String, light: LightState = .on, changedAt: String? = nil,
                              lastAuditedNight: Date? = nil,
                              schedule: SleepSchedule = LightClock.night) -> Bool {
        LightsOutRule.shouldChargeMistake(
            now: LightClock.at(iso), schedule: schedule, lightState: light,
            lightStateChangedAt: changedAt.map(LightClock.at), lastAuditedNight: lastAuditedNight,
            calendar: calendar)
    }

    func testTheMistakeWaitsForTheThirtyMinuteGrace() {
        XCTAssertEqual(LightsOutRule.mistakeGrace, 30 * LightClock.minute)
        XCTAssertFalse(shouldCharge("2026-03-10 22:29", changedAt: "2026-03-10 19:00"))
        XCTAssertTrue(shouldCharge("2026-03-10 22:30", changedAt: "2026-03-10 19:00"))
    }

    /// AC7. The night light is the trap this whole three-state enum exists for.
    func testSemiHeldAllNightStillChargesTheMistake() {
        XCTAssertTrue(shouldCharge("2026-03-11 06:00", light: .semi, changedAt: "2026-03-10 19:00"))
    }

    /// AC6, and the headline: the app was shut at 21:00 and not opened again until morning, and the
    /// verdict is still clean, because the rule reads the timestamp rather than observations.
    func testLightsOutBeforeBedtimeIsCleanEvenIfTheAppNeverRanAllNight() {
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", light: .off, changedAt: "2026-03-10 21:00"))
    }

    func testLightsOutAnyTimeInsideTheGraceIsClean() {
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", light: .off, changedAt: "2026-03-10 22:29"))
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", light: .off, changedAt: "2026-03-10 22:30"),
                       "the deadline itself still counts as making it")
    }

    /// The limit of a single timestamp, asserted rather than hidden: a light put out AFTER the grace
    /// reads as clean to the rule on its own, because what it was doing at the deadline is no longer
    /// knowable. In the shipped game that is not an escape — turning the light off means opening the
    /// app, and US-101's refresh charges the night before the tap can land — but nothing in this
    /// pure rule enforces that, so the test says what the rule really does.
    func testTheRuleAloneCannotSeeALightPutOutAfterTheGrace() {
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", light: .off, changedAt: "2026-03-10 22:31"))
    }

    /// The whole point of not gating the charge on the Digimon still being asleep: a night nobody
    /// was there for is judged by the morning that follows it.
    func testANightTheAppSleptThroughIsChargedTheNextMorning() {
        XCTAssertTrue(shouldCharge("2026-03-11 08:00", changedAt: "2026-03-05 12:00"))
    }

    /// AC9. A lamp switched on at breakfast changed state after last night's deadline, so the
    /// waking hours under it cost nothing.
    func testTheLightBeingOnWhileTheDigimonIsAwakeIsNeverAMistake() {
        XCTAssertFalse(shouldCharge("2026-03-11 09:00", changedAt: "2026-03-11 08:00"))
        XCTAssertFalse(shouldCharge("2026-03-11 14:00", changedAt: "2026-03-11 08:00"))
        XCTAssertFalse(shouldCharge("2026-03-11 21:59", changedAt: "2026-03-11 08:00"),
                       "right up to the moment the next window opens")
    }

    func testTheNightAlreadyChargedIsNotChargedAgain() {
        let night = LightClock.at("2026-03-10 22:00")
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", changedAt: "2026-03-05 12:00",
                                    lastAuditedNight: night))
        XCTAssertTrue(shouldCharge("2026-03-11 23:00", changedAt: "2026-03-05 12:00",
                                   lastAuditedNight: night), "tonight is a new night")
    }

    /// The non-wrapping branch charges on exactly the same terms.
    func testANightShiftWindowIsJudgedTheSameWay() {
        XCTAssertFalse(shouldCharge("2026-03-11 02:29", changedAt: "2026-03-10 19:00",
                                    schedule: LightClock.dayShift))
        XCTAssertTrue(shouldCharge("2026-03-11 02:30", changedAt: "2026-03-10 19:00",
                                   schedule: LightClock.dayShift))
        XCTAssertFalse(shouldCharge("2026-03-11 09:00", light: .off, changedAt: "2026-03-11 01:00",
                                    schedule: LightClock.dayShift))
    }

    /// A save written before the light was tracked has no timestamp. `.off` with no stamp is a
    /// light that has been out for as long as anything knows.
    func testAnUntrackedLightIsReadFromItsStateAlone() {
        XCTAssertFalse(shouldCharge("2026-03-11 08:00", light: .off, changedAt: nil))
        XCTAssertTrue(shouldCharge("2026-03-11 08:00", light: .on, changedAt: nil))
    }
}

// MARK: - AC2/AC8: the state on the model

@MainActor
final class LightGameStateTests: XCTestCase {
    private let calendar = LightClock.calendar
    private let born = LightClock.at("2026-03-10 12:00")

    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("GameState.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LightTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func newGame() -> GameState {
        GameState(currentDigimonId: "hero", stage: .babyI, now: born)
    }

    func testANewGameStartsWithTheLightOnAndStampedAtBirth() {
        let state = newGame()
        XCTAssertEqual(state.lightState, .on)
        XCTAssertEqual(state.lightStateChangedAt, born)
        XCTAssertNil(state.lightAuditedNight)
        XCTAssertNil(state.lightNotifiedNight)
    }

    func testSettingTheLightStampsWhenItChanged() {
        let state = newGame()
        let evening = LightClock.at("2026-03-10 21:00")
        state.setLight(.off, now: evening)

        XCTAssertEqual(state.lightState, .off)
        XCTAssertEqual(state.lightStateChangedAt, evening)

        // A no-op tap must not push the stamp forward, or a light out since dinner would read as
        // one only just switched off.
        state.setLight(.off, now: LightClock.at("2026-03-11 03:00"))
        XCTAssertEqual(state.lightStateChangedAt, evening)
    }

    /// AC8, in the manner of `recordWakingEarly` — and the reason it is keyed on the night rather
    /// than the day: 23:00 and 01:00 are one night and must cost one mistake.
    func testTheMistakeIsChargedAtMostOncePerNight() {
        let state = newGame()
        XCTAssertEqual(state.careMistakeCount, 0)

        state.recordLightsLeftOn(now: LightClock.at("2026-03-10 23:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1)
        XCTAssertEqual(state.lightAuditedNight, LightClock.at("2026-03-10 22:00"))

        state.recordLightsLeftOn(now: LightClock.at("2026-03-11 01:00"), calendar: calendar)
        state.recordLightsLeftOn(now: LightClock.at("2026-03-11 06:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 1, "one night, whatever side of midnight it is read")

        state.recordLightsLeftOn(now: LightClock.at("2026-03-11 23:00"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 2, "the next night is its own mistake")
    }

    /// The counter every other mistake feeds, so nothing new has to be plumbed for the evolution
    /// gate or for sickness to see it.
    func testTheMistakeLandsOnTheSameCounterAsEveryOther() {
        let state = newGame()
        state.recordWakingEarly(now: LightClock.at("2026-03-10 23:30"), calendar: calendar)
        state.recordLightsLeftOn(now: LightClock.at("2026-03-10 23:30"), calendar: calendar)
        XCTAssertEqual(state.careMistakeCount, 2)
    }

    /// AC2. Written, the container dropped, then read through a brand new one pointed at the same
    /// file — so what is asserted came off disk rather than out of the first context's cache.
    func testTheLightSurvivesARelaunch() throws {
        let night = LightClock.at("2026-03-10 22:00")
        let changed = LightClock.at("2026-03-10 21:00")
        do {
            let store = try GameStore(url: storeURL)
            let state = newGame()
            state.setLight(.semi, now: changed)
            state.lightAuditedNight = night
            state.lightNotifiedNight = night.addingTimeInterval(10 * LightClock.minute)
            store.container.mainContext.insert(state)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let loaded = try XCTUnwrap(
            try reopened.container.mainContext.fetch(FetchDescriptor<GameState>()).first)
        XCTAssertEqual(loaded.lightState, .semi)
        XCTAssertEqual(loaded.lightStateChangedAt, changed)
        XCTAssertEqual(loaded.lightAuditedNight, night)
        XCTAssertEqual(loaded.lightNotifiedNight, night.addingTimeInterval(10 * LightClock.minute))
    }
}
