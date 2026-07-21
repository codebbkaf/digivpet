import Foundation

/// The three positions of the room light.
///
/// Three and not a Bool because the middle one is the whole point: `semi` is the night light a user
/// leaves on to keep the Digimon visible, and US-101's rule is that it does NOT count as
/// lights-out. A Bool could not express a state that looks dark and still costs a care mistake.
///
/// Raw values are the persisted spelling, so renaming a case rewrites saved games — change
/// `displayName` instead if the wording needs to shift.
enum LightState: String, Codable, CaseIterable {
    /// Full daylight. Nothing is dimmed.
    case on
    /// The night light: dimmed enough to read as bedtime, not enough to be dark.
    case semi
    /// Lights out. The only state that satisfies `LightsOutRule`.
    case off

    /// What the UI calls this. Free to change — unlike `rawValue`, nothing persists it.
    var displayName: String {
        switch self {
        case .on: return "Light on"
        case .semi: return "Dimmed"
        case .off: return "Lights out"
        }
    }

    /// The SF Symbol for the light button in this state.
    ///
    /// The symbol names the state the light is IN, not the one tapping would move it to, so the
    /// button reads as an indicator that happens to be tappable rather than as a command whose
    /// label contradicts what the screen is doing.
    var symbolName: String {
        switch self {
        case .on: return "lightbulb.fill"
        case .semi: return "lightbulb.led.fill"
        case .off: return "lightbulb.slash"
        }
    }

    /// The state one tap of the light button moves to: on -> semi -> off -> on (US-099).
    ///
    /// A cycle rather than a toggle, because there are three states and one button. The order is the
    /// one the room goes through at bedtime — full light, night light, dark — so a user putting the
    /// Digimon to bed taps twice in the direction they are already thinking, and a third tap is the
    /// way back rather than a dead end.
    var next: LightState {
        switch self {
        case .on: return .semi
        case .semi: return .off
        case .off: return .on
        }
    }

    /// How black the scrim over the screen is in this state, 0...1.
    ///
    /// `off` stops at 0.85 rather than 1.0 deliberately: a fully black screen is indistinguishable
    /// from a crashed app, and the user still has to be able to find the light button to turn it
    /// back on. The Digimon stays a faint silhouette, which is what a real V-Pet's LCD does.
    var dimOpacity: Double {
        switch self {
        case .on: return 0
        case .semi: return 0.5
        case .off: return 0.85
        }
    }
}

/// Whether the light has been left on over a sleeping Digimon, and for how long.
///
/// PURE: every input is an argument and nothing is read from a store, a clock, HealthKit or a view.
/// That is what lets US-100's nudge and US-101's care mistake ask the SAME question at two
/// different graces without either of them owning the answer, and it is why every test here can
/// name an hour instead of waiting for one.
///
/// **The rule reads `lightStateChangedAt`, not observations.** Nothing about it depends on the app
/// having been running when the window opened, which is the difference between this and
/// `PoopClock`'s sleep pause — a user who put the light out at 21:00 and never opened the app again
/// is judged clean the next morning, because the timestamp says so.
///
/// The one thing that costs: a single timestamp says what the light is doing NOW and since when,
/// so any state reached after the deadline leaves the deadline itself unknown, and unknown is read
/// as clean. Both directions of that are deliberate. A lamp switched on at breakfast must not be
/// charged against the night before; and a light put out at dawn reads clean to this rule alone,
/// which is not the escape it looks like — turning it off means opening the app, and the refresh
/// that opening runs charges the night before the tap can land.
enum LightsOutRule {
    /// How long the light may stay on after bedtime before the user is nudged: ten minutes.
    ///
    /// Short, because the nudge is the avoidable half of the feature — it has to arrive while the
    /// user is still in the room, and `mistakeGrace - notifyGrace` is the twenty minutes they get
    /// to act on it.
    static let notifyGrace: TimeInterval = 10 * 60

    /// How long the light may stay on after bedtime before it is a care mistake: thirty minutes.
    ///
    /// Long enough that finishing a chapter is not neglect, short enough that the mistake belongs
    /// to the night it was made in rather than being decided at dawn.
    static let mistakeGrace: TimeInterval = 30 * 60

    /// The start of the sleep window `now` falls in, or nil if the Digimon is awake.
    ///
    /// The nil is what US-100 hangs on: the nudge only makes sense while the Digimon is actually
    /// trying to sleep. The mistake asks the wider question — see `mostRecentWindowStart`.
    static func windowStart(containing now: Date, schedule: SleepSchedule,
                            calendar: Calendar = .current) -> Date? {
        guard schedule.contains(now, calendar: calendar) else { return nil }
        return mostRecentWindowStart(at: now, schedule: schedule, calendar: calendar)
    }

    /// The start of the latest sleep window that has opened at or before `now` — the window the
    /// Digimon is in, or the one it has most recently come out of.
    ///
    /// Never nil, because there is always a last night. This is the key both once-a-night markers
    /// are stamped with, and it is what identifies a night to the morning that follows it: a local
    /// day cannot, because an ordinary night has two of them.
    ///
    /// Two candidates and no arithmetic on minutes-of-day, so a night-shift window that never
    /// crosses midnight takes exactly the same path as an ordinary one that always does.
    static func mostRecentWindowStart(at now: Date, schedule: SleepSchedule,
                                      calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let tonight = bedtime(on: today, schedule: schedule, calendar: calendar)
        guard tonight > now else { return tonight }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            ?? today.addingTimeInterval(-24 * 60 * 60)
        return bedtime(on: yesterday, schedule: schedule, calendar: calendar)
    }

    /// The start of the next sleep window that opens strictly after `now` — tonight's bedtime, seen
    /// from an afternoon.
    ///
    /// The forward twin of `mostRecentWindowStart`, and US-100 AC4 is the whole reason it exists: a
    /// nudge that can only be posted by a refresh landing inside the window is a nudge a user with
    /// the app closed all evening never gets, so the evening's refresh has to be able to name the
    /// instant the nudge falls due and hand it to the system ahead of time.
    ///
    /// Only ever asked while the Digimon is awake. The `<=` is what makes a night-shift 02:00–10:00
    /// window asked at 14:00 answer tomorrow's 02:00 rather than the 02:00 that has already passed.
    static func nextWindowStart(after now: Date, schedule: SleepSchedule,
                                calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let tonight = bedtime(on: today, schedule: schedule, calendar: calendar)
        guard tonight <= now else { return tonight }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(24 * 60 * 60)
        return bedtime(on: tomorrow, schedule: schedule, calendar: calendar)
    }

    /// Whether this moment is the one that owes the user a "lights out" nudge.
    ///
    /// Reads the light state as it is NOW rather than as it was at the deadline, unlike
    /// `shouldChargeMistake`: there is no point telling someone to turn off a light they have
    /// already turned off, however late they got round to it.
    static func shouldNotify(now: Date, schedule: SleepSchedule, lightState: LightState,
                             lastNotifiedNight: Date?, calendar: Calendar = .current) -> Bool {
        guard lightState != .off else { return false }
        guard let night = windowStart(containing: now, schedule: schedule, calendar: calendar) else {
            return false
        }
        guard now >= night.addingTimeInterval(notifyGrace) else { return false }
        return lastNotifiedNight != night
    }

    /// Whether the night ending at or containing `now` has been slept through under the light.
    ///
    /// Deliberately NOT gated on the Digimon still being asleep. A night the app was closed for
    /// would otherwise cost nothing at all, and the neglect it is charging happened at bedtime
    /// whether or not anyone was there to see it — the same principle as `chargeStarvationMistakes`
    /// charging for a weekend nobody opened the app during. What an awake Digimon is never charged
    /// for is the light being on WHILE it is awake: a lamp switched on at breakfast changed state
    /// after last night's deadline, so it fails the test below.
    static func shouldChargeMistake(now: Date, schedule: SleepSchedule, lightState: LightState,
                                    lightStateChangedAt: Date?, lastAuditedNight: Date?,
                                    calendar: Calendar = .current) -> Bool {
        let night = mostRecentWindowStart(at: now, schedule: schedule, calendar: calendar)
        let deadline = night.addingTimeInterval(mistakeGrace)
        guard now >= deadline else { return false }
        guard lastAuditedNight != night else { return false }
        return wasLit(at: deadline, lightState: lightState, lightStateChangedAt: lightStateChangedAt)
    }

    /// Whether the light is KNOWN to have been burning at `deadline` — the single question the
    /// mistake turns on.
    ///
    /// Two conditions, and the second is the one that does the work. A state on its own says nothing
    /// about a moment in the past; only a state that was already in force BEFORE the deadline does.
    /// That is what keeps a lamp switched on at breakfast from being charged against the night
    /// before, and it is why an unknown night is read as clean rather than as neglect.
    static func wasLit(at deadline: Date, lightState: LightState,
                       lightStateChangedAt: Date?) -> Bool {
        guard lightState != .off else { return false }
        // nil is a save written before the light was tracked. A light that has been on for as long
        // as anything knows was on at the deadline too.
        return (lightStateChangedAt ?? .distantPast) <= deadline
    }

    /// The instant `schedule`'s bedtime falls on the local day containing `day`.
    ///
    /// `bySettingHour` rather than adding minutes to midnight, so a night on which the clocks change
    /// lands on the wall-clock bedtime the user actually keeps rather than an hour either side of it.
    private static func bedtime(on day: Date, schedule: SleepSchedule, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: schedule.bedtimeMinute / 60,
                      minute: schedule.bedtimeMinute % 60, second: 0,
                      of: day)
            // Only reachable if the wall-clock time genuinely does not exist on this day and no
            // later one matches either. Minutes past midnight is the answer that is at worst an
            // hour out, which beats returning nil and skipping the night's audit entirely.
            ?? calendar.startOfDay(for: day)
                .addingTimeInterval(TimeInterval(schedule.bedtimeMinute) * 60)
    }
}

extension GameState {
    /// Moves the light to `state` and stamps when, which is the pair `LightsOutRule` reads.
    ///
    /// One method rather than two assignments at the call site, because the rule is only correct if
    /// nothing can change the state without moving the timestamp: a light set to `.off` still
    /// carrying last week's stamp would read as a night that had been dark all along.
    ///
    /// Setting the state it is already in changes nothing, deliberately. The stamp means "since
    /// when", so a no-op tap must not push it forward and turn a light that has been out since
    /// dinner into one that was only just switched off.
    func setLight(_ state: LightState, now: Date) {
        guard state != lightState else { return }
        lightState = state
        lightStateChangedAt = now
    }

    /// Gives back the once-a-night claim IF the notice it stands for has not gone out yet.
    ///
    /// The mirror of `clean()` clearing `poopNotified`: US-100 AC5 says putting the light out
    /// withdraws the nudge, and a claim left standing for a notice that was cancelled before it ever
    /// appeared would swallow the one this night still might owe — the user who puts the light out
    /// at 20:00 and turns it back on at 21:00 has to be nudged at 22:10 like anyone else.
    ///
    /// `night > now` is the whole test, and it is exact rather than approximate: a stamp for a night
    /// whose bedtime is still ahead can only have come from the scheduling path, because the
    /// immediate one stamps the night it is already inside. So a stamp in the FUTURE means "queued,
    /// not yet seen" and a stamp in the past means "the user has read it" — and a notice already
    /// read stays claimed, which is what keeps one night to one nudge however often the light is
    /// flicked afterwards.
    func withdrawLightsNotice(now: Date) {
        guard let night = lightNotifiedNight, night > now else { return }
        lightNotifiedNight = nil
    }

    /// Charges the mistake for a night spent under the light, at most once per night.
    ///
    /// Shaped like `recordWakingEarly` and capped for the same reason — one bad night is one
    /// mistake — but keyed on `LightsOutRule.mostRecentWindowStart` rather than on the local day,
    /// because a night has two of those and would otherwise be charged twice by an app opened
    /// either side of midnight.
    func recordLightsLeftOn(now: Date, schedule: SleepSchedule = .fallback,
                            calendar: Calendar = .current) {
        let night = LightsOutRule.mostRecentWindowStart(at: now, schedule: schedule,
                                                        calendar: calendar)
        guard lightAuditedNight != night else { return }
        lightAuditedNight = night
        careMistakeCount += 1
    }
}
