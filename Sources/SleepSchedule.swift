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

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
