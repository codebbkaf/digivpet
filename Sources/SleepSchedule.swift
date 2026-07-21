import Foundation

/// The daily stretch during which the Digimon sleeps, as minutes past local midnight.
///
/// A TIME OF DAY rather than a `DateInterval`, because the question being asked is "is it bedtime?"
/// and that recurs every night. `LastNightSleepReader` already produces one concrete night; this
/// turns that night into the habit it stands for, so the Digimon is asleep tonight at the hour the
/// user was asleep last night without any new health data having arrived.
struct SleepSchedule: Equatable {
    /// Minutes past midnight the Digimon goes to sleep.
    let bedtimeMinute: Int
    /// Minutes past midnight it wakes. Exclusive — at exactly this minute it is awake.
    let wakeMinute: Int

    /// The window used when HealthKit has no usable sleep history: 22:00–07:00.
    ///
    /// Fixed rather than inferred because there is nothing to infer from, and a Digimon that never
    /// sleeps reads as broken. It is also what a user with no sleep tracking at all gets forever —
    /// see the PRD's "Sleep data is unreliable" risk.
    static let fallback = SleepSchedule(bedtimeMinute: 22 * 60, wakeMinute: 7 * 60)

    /// How much sleep a block must contain before its hours are taken as the user's habit.
    ///
    /// Three hours. `SleepAnalysis.longestAsleepBlock` already picks the night's longest block, but
    /// on a night whose only record is a 40-minute evening doze that block IS the doze — and a
    /// 40-minute sleep window starting at 20:15 is a worse answer than 22:00–07:00. Nothing in the
    /// data picks the exact number; it is a v1 judgement, sitting well below any real night's sleep
    /// and well above any nap.
    static let minimumInferableSleep: TimeInterval = 3 * 60 * 60

    /// How long a Digimon prodded awake inside its window stays awake before settling back down:
    /// five minutes.
    ///
    /// A BALANCE NUMBER, chosen rather than derived — nothing in the sleep data implies it. Long
    /// enough that the user can feed, train and watch the Digimon walk about after paying the
    /// waking-early mistake for it (US-110), short enough that one prod does not cancel the night.
    static let wakeGracePeriod: TimeInterval = 5 * 60

    /// The hours of `block`, taken as a nightly habit, or nil if the block is too short to be one.
    ///
    /// Uses the block's SPAN, not its asleep duration: the window is meant to cover the whole night
    /// including the brief awakenings inside it, or the Digimon would flicker awake at 03:00
    /// alongside the user rolling over.
    init?(inferredFrom block: SleepBlock, calendar: Calendar) {
        guard block.asleepDuration >= Self.minimumInferableSleep else { return nil }
        let bedtime = Self.minuteOfDay(block.span.start, calendar: calendar)
        let wake = Self.minuteOfDay(block.span.end, calendar: calendar)
        // A span landing on the same minute of day at both ends would be a 24-hour window, i.e. a
        // Digimon asleep forever. Only reachable from a full day's span, so the fallback is safer.
        guard bedtime != wake else { return nil }
        self.init(bedtimeMinute: bedtime, wakeMinute: wake)
    }

    init(bedtimeMinute: Int, wakeMinute: Int) {
        self.bedtimeMinute = bedtimeMinute
        self.wakeMinute = wakeMinute
    }

    /// Whether this window runs across midnight, as an ordinary night's does.
    var wrapsMidnight: Bool { wakeMinute <= bedtimeMinute }

    /// Whether `date` falls inside the window.
    ///
    /// Bedtime is inclusive and waking exclusive, so the two ends of consecutive days never both
    /// claim the same minute.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = Self.minuteOfDay(date, calendar: calendar)
        // A night-shift worker sleeping 02:00-10:00 gets the non-wrapping branch: the same two
        // numbers, read as one contiguous stretch of a single day rather than across two.
        return wrapsMidnight
            ? (minute >= bedtimeMinute || minute < wakeMinute)
            : (minute >= bedtimeMinute && minute < wakeMinute)
    }

    /// Whether the Digimon is actually asleep at `date`, given a wake the user has already paid for.
    ///
    /// The window alone stopped being the whole answer at US-110: prodding a sleeping Digimon wakes
    /// it for `wakeGracePeriod`, and `awakeUntil` is when that grace runs out. Kept here, beside
    /// `contains`, so the override is applied in ONE place — the model re-derives sleep on every
    /// refresh, and a second copy of this rule is exactly how a foregrounding would silently undo a
    /// wake the user was charged a care mistake for.
    ///
    /// An expired marker is simply IGNORED rather than needing to be cleared: it is an absolute
    /// instant, so a marker left over from 03:00 cannot make tomorrow night's 03:00 awake.
    ///
    /// - Parameter awakeUntil: when the current wake expires, or nil if the Digimon was never woken.
    func isAsleep(at date: Date, wokenUntil awakeUntil: Date?, calendar: Calendar = .current) -> Bool {
        guard contains(date, calendar: calendar) else { return false }
        guard let awakeUntil else { return true }
        return date >= awakeUntil
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
