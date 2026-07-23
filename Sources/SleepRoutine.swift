import Foundation

/// A clock time inside one day, as minutes since midnight (US-214).
///
/// Not a `Date`: a `SleepRoutine` is a RECURRING daily habit, not an appointment, so there is no day
/// for a `Date` to sit on and nothing here should ever be compared against `now()`. Minutes since
/// midnight is also what makes the arithmetic ("bedtime plus eight hours") a wrap on 1440 rather
/// than a calendar question.
struct WatchTime: Equatable, Comparable, Hashable {
    /// Minutes since midnight, always normalised into `0..<1440` — 24:00 is 00:00, and adding a
    /// night's sleep to a bedtime after 22:00 lands on the next morning rather than past the end of
    /// the day.
    let minutes: Int

    init(minutesSinceMidnight: Int) {
        let day = WatchTime.minutesPerDay
        self.minutes = ((minutesSinceMidnight % day) + day) % day
    }

    init(hour: Int, minute: Int) {
        self.init(minutesSinceMidnight: hour * 60 + minute)
    }

    static let minutesPerDay = 24 * 60

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// Zero-padded 24-hour, `22:30` / `07:00`, which is the form AC6 asks for.
    ///
    /// Formatted here rather than through a `DateFormatter` on purpose: a formatter follows the
    /// device's 12/24-hour setting and its locale, so the same Digimon would read "10:30 PM" on one
    /// watch and "22:30" on another, and the string a test pins would depend on the simulator's
    /// region. These are the pet's habits, printed the way a V-Pet prints them.
    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// This time, `offset` minutes later (or earlier, if negative), wrapped into the same day.
    func adding(minutes offset: Int) -> WatchTime {
        WatchTime(minutesSinceMidnight: minutes + offset)
    }

    /// Minutes from here forward to `other`, wrapping past midnight — so 22:30 to 07:00 is 8 h 30 m
    /// rather than a negative number. Equal times read as a whole day, which no routine produces:
    /// every window built below has a non-zero length.
    func minutes(until other: WatchTime) -> Int {
        let raw = other.minutes - minutes
        return raw > 0 ? raw : raw + WatchTime.minutesPerDay
    }

    static func < (lhs: WatchTime, rhs: WatchTime) -> Bool { lhs.minutes < rhs.minutes }
}

/// When one Digimon sleeps: a bedtime, a wake time and one afternoon nap (US-214).
///
/// **Not `SleepSchedule`, and the difference matters.** `SleepSchedule` is the USER's window,
/// inferred from HealthKit, and it decides whether the Digimon is actually asleep right now
/// (`isAsleep(at:wokenUntil:)`). A `SleepRoutine` is the DIGIMON's own habit — flavour shown on the
/// Sleep Time screen so each creature's rest feels like its own — and it drives nothing in the
/// simulation. Adding a second thing that could put the Digimon to sleep would mean two answers to
/// one question, so this deliberately stays a display value.
///
/// DERIVED from the Digimon's id rather than authored, because there are 1,000+ entries in the
/// roster and a hand-written bedtime for each is a data set nobody would keep true. What the
/// derivation promises instead is that it is a PURE FUNCTION of the id: the same Digimon shows the
/// same times every time the screen is opened, on every device and after every reinstall, and two
/// different Digimon almost always differ. No `Date()`, no `SystemRandomNumberGenerator`, and
/// deliberately no `String.hashValue` — Swift seeds that per process, so a routine built on it would
/// change on every relaunch, which is exactly what AC3 rules out.
struct SleepRoutine: Equatable {
    /// When the Digimon turns in for the night.
    let bedtime: WatchTime
    /// When it gets up — `bedtime` plus `nightMinutes`, wrapped past midnight.
    let wakeTime: WatchTime
    /// The start of its one afternoon nap.
    let napStart: WatchTime
    /// The end of that nap — `napStart` plus `napMinutes`.
    let napEnd: WatchTime

    /// The night's length in minutes. Stored rather than re-derived from the two times, so the two
    /// readings can never disagree and a night can never read as zero.
    let nightMinutes: Int
    /// The nap's length in minutes.
    let napMinutes: Int

    /// Night plus nap: how much rest a day on this routine holds. AC4's "sensible way" — the nap is
    /// counted INTO the day's total and the screen shows the split, rather than the nap sitting as a
    /// decoration beside a number that ignores it.
    var totalMinutes: Int { nightMinutes + napMinutes }

    // MARK: - Derivation

    /// The routine for a Digimon id. Total: every string answers, including the empty one, because
    /// the caller is a screen that has to draw something for whatever is on it.
    static func forDigimon(id: String) -> SleepRoutine {
        var generator = SeededGenerator(seed: seed(for: id))

        // Four draws in a fixed order. Each is a count of quarter-hour SLOTS inside a band, so every
        // time in the app lands on :00, :15, :30 or :45 — a Digimon that goes to bed at 22:37 reads
        // as a measurement, and these are habits.
        let bedtime = Bands.bedtimeEarliest.adding(minutes: quarters(&generator, of: Bands.bedtimeSlots))
        let nightMinutes = Bands.nightShortest + quarters(&generator, of: Bands.nightSlots)
        let napStart = Bands.napEarliest.adding(minutes: quarters(&generator, of: Bands.napSlots))
        let napMinutes = Bands.napShortest + quarters(&generator, of: Bands.napLengthSlots)

        return SleepRoutine(bedtime: bedtime,
                            wakeTime: bedtime.adding(minutes: nightMinutes),
                            napStart: napStart,
                            napEnd: napStart.adding(minutes: napMinutes),
                            nightMinutes: nightMinutes,
                            napMinutes: napMinutes)
    }

    /// The bands the four draws land in. Named constants rather than literals inside the arithmetic
    /// because they ARE the design of this feature: every Digimon in the game sleeps somewhere
    /// inside these, and widening one is the single knob a later balance pass would reach for.
    ///
    /// Chosen so no routine is absurd for a pet: nights of 7–10 h, bedtimes in the late evening,
    /// naps early-to-mid afternoon and half an hour to an hour and a half long.
    enum Bands {
        static let bedtimeEarliest = WatchTime(hour: 20, minute: 0)
        /// 20:00 through 24:00 — the last slot normalises to midnight.
        static let bedtimeSlots = 17

        static let nightShortest = 7 * 60
        /// 7 h through 10 h.
        static let nightSlots = 13

        static let napEarliest = WatchTime(hour: 12, minute: 0)
        /// 12:00 through 16:00.
        static let napSlots = 17

        static let napShortest = 30
        /// 30 m through 90 m.
        static let napLengthSlots = 5
    }

    /// One draw: a whole number of quarter-hours, `0..<slots` of them.
    private static func quarters(_ generator: inout SeededGenerator, of slots: Int) -> Int {
        Int(generator.next() % UInt64(slots)) * 15
    }

    /// FNV-1a (64-bit) over the id's UTF-8 bytes — a fixed, published algorithm, so the seed for
    /// `"agumon"` is the same number on every machine, every OS version and every launch. It feeds
    /// `SeededGenerator` (SplitMix64), which is what spreads four consecutive draws out of one seed.
    ///
    /// `SleepRoutineTests` pins this against literals for exactly that reason: if someone ever
    /// replaces it with `id.hashValue` the routines stay plausible on screen and only a pinned
    /// number notices — one launch later.
    static func seed(for id: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: - Reading it out

    /// A span of minutes as `8 h`, `8 h 30 m` or `45 m` — the watch-sized form, units on the numbers
    /// rather than spelled out, matching the `6 h` headline the Sleep screen already shows.
    static func durationText(minutes: Int) -> String {
        let clamped = max(minutes, 0)
        let hours = clamped / 60
        let remainder = clamped % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) m"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(remainder) m"
        }
    }

    /// The nap window as one string, `13:45 – 14:45`. An en dash, because it is a range.
    var napWindowText: String { "\(napStart.formatted) – \(napEnd.formatted)" }

    /// The split, said once: `8 h night + 1 h nap`. AC4's labelling — a player reading the day's
    /// total can see which part of it the nap is.
    var splitText: String {
        "\(SleepRoutine.durationText(minutes: nightMinutes)) night + "
            + "\(SleepRoutine.durationText(minutes: napMinutes)) nap"
    }
}
