import Foundation

/// The four kinds of neglect that count against a Digimon, and the thresholds that define them.
///
/// Like `HungerClock`, nothing here is ever ticked. Every mistake is derived from a saved marker
/// against an injected clock, which is what makes the count correct after the app has been closed
/// for days: a Digimon left starving all weekend is charged for that weekend the first time anyone
/// looks, not only for the moments the app happened to be open.
///
/// `careMistakeCount` is the single counter all four feed. `EvolutionEngine` already reads it as an
/// edge's `maxCareMistakes`, so this story is what finally makes that gate bite; US-028 reads the
/// same count for sickness.
enum CareMistakes {
    /// How long a Digimon may sit at maximum hunger before each mistake: eight real hours.
    ///
    /// The PRD names the threshold but not what happens past it, so this is charged as a RATE — a
    /// Digimon left starving for 24h has been neglected three times over, not once. Nine hours is
    /// therefore exactly one mistake, which is US-027's headline test.
    static let secondsAtMaximumHungerPerMistake: TimeInterval = 8 * 60 * 60

    /// How long a full screen of poop may sit uncleaned before it is a mistake: six real hours.
    ///
    /// Charged from the CEILING rather than from the first poop, because one poop is a Digimon that
    /// has been alive for three hours, not a Digimon anyone has neglected — `PoopClock.maximumPoops`
    /// is the point at which the screen says nobody has visited. Six hours against starvation's
    /// eight, matching poop accruing faster than hunger: the mess is the more visible neglect, so it
    /// is the one that bites sooner.
    ///
    /// **ONCE PER SPELL, NOT A RATE — and unlike starvation, that is forced rather than chosen.**
    /// Poop is PAUSED while the Digimon sleeps, and `PoopClock` is explicit that the pause is only
    /// observed by a refresh that actually runs during it: an app left open through the night skips
    /// those hours, an app that was shut cannot know to. A rate would turn that gap into a different
    /// number of mistakes for the same 48 hours depending only on whether the app happened to be
    /// running — which is exactly what `ClosedAppRecomputeTests` exists to forbid. Charging the
    /// spell once makes the two agree, because both runs cross the threshold and neither can cross
    /// it twice. The game rule that falls out is a fair one: leaving the screen filthy is one act of
    /// neglect, and letting it happen AGAIN after cleaning is what costs a second.
    static let secondsAtMaximumPoopBeforeMistake: TimeInterval = 6 * 60 * 60

    /// Refusals in one local day that add up to overfeeding: three (PRD FR-30).
    static let refusalsPerMistake = 3

    /// A ceiling on the mistakes one call may charge for starvation. Not a game rule — a trap guard.
    /// `Int(Double)` traps outside `Int`'s range and elapsed time is only as sane as the device
    /// clock, so a save restored onto a watch set to the year 3000 must saturate rather than crash.
    /// A million eight-hour spells is roughly 913 years, well past any real neglect.
    ///
    /// Starvation only. The uncleaned-poop rule charges once per spell rather than by rate, so it
    /// converts no Double to Int and needs no guard of its own.
    static let maximumStarvationMistakesCharged = 1_000_000

    /// What a refresh's readings say about whether the user's day was really empty.
    ///
    /// Three-way and not a Bool, because "no number" has two very different causes and only one of
    /// them is neglect. `HealthReading` already draws the line — `noData` is a read that SUCCEEDED
    /// and found nothing, `unavailable` is a read that could not happen — and that enum's own
    /// documentation names this story as the reason it does.
    enum HealthDataVerdict: Equatable {
        /// At least one metric came back with a real number. Not a silent day.
        case seen
        /// HealthKit answered, and there was nothing recorded. THIS is the day that counts against
        /// the user, and it is the only one of the three that is ever charged.
        case silent
        /// Nothing could be read at all: HealthKit off, or every query failed. The day is
        /// unknowable, so it is neither charged nor held against a later read.
        case unreadable

        /// Reads the verdict off a refresh's readings.
        ///
        /// Any real number wins, because one recorded metric means the user's day was not empty
        /// however the other three came back. Failing that, one metric that answered "nothing" is
        /// enough to call the day silent — a read that partly worked did tell us about the day.
        init(_ readings: some Collection<HealthReading>) {
            if readings.contains(where: { $0.hasData }) {
                self = .seen
            } else if readings.contains(where: { $0 == .noData }) {
                self = .silent
            } else {
                self = .unreadable
            }
        }
    }
}

extension GameState {
    /// Brings the time-derived care mistakes up to date with `now`.
    ///
    /// Idempotent within a threshold, so the main screen can call it on every refresh — each rule
    /// keeps a marker of what it has already charged and only ever charges the difference. The two
    /// mistakes that are NOT here are the two that have a moment rather than a duration: a refusal
    /// is charged by `recordRefusal`, and waking the Digimon by `recordWakingEarly`.
    ///
    /// - Parameter health: what this refresh's readings say about the day. Passed in rather than
    ///   re-read, because the caller has just taken the readings.
    func auditCareMistakes(now: Date, health: CareMistakes.HealthDataVerdict,
                           calendar: Calendar = .current) {
        switch health {
        case .seen:
            // Charged BEFORE the stamp, or opening the app on the third silent day would move the
            // marker to today and forgive the two days that were actually missed.
            chargeMissingHealthDataDays(now: now, calendar: calendar)
            healthDataLastSeen = now
        case .silent:
            chargeMissingHealthDataDays(now: now, calendar: calendar)
        case .unreadable:
            // Moved forward WITHOUT charging. Neither charging (the user did nothing to cause a
            // HealthKit failure) nor leaving the marker behind (a week with HealthKit off would
            // then be charged in full by the first read that worked) — the days are simply written
            // off as unknowable.
            healthDataLastSeen = now
        }
        chargeStarvationMistakes(now: now)
        chargeUncleanedPoopMistakes(now: now)
    }

    /// One mistake per whole local day that passed with no health data at all.
    ///
    /// TODAY IS NEVER CHARGED: it is still in progress, and a user who has not moved yet at 08:00
    /// has not neglected anything. Only the days strictly between the last data and today are full
    /// days that went by empty.
    private func chargeMissingHealthDataDays(now: Date, calendar: Calendar) {
        guard let lastSeen = healthDataLastSeen else {
            // A save written before this was tracked has no baseline. The clock starts now rather
            // than charging for a silence nothing actually observed.
            healthDataLastSeen = now
            return
        }

        let lastDay = calendar.startOfDay(for: lastSeen)
        let today = calendar.startOfDay(for: now)
        // Backwards means the clock or the timezone moved, not that data arrived.
        guard today > lastDay else { return }

        let elapsedDays = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        let missedDays = elapsedDays - 1
        guard missedDays > 0 else { return }

        careMistakeCount += missedDays
        // Moved forward by exactly the days CHARGED, never to today — the same discipline as
        // `HungerClock.advance`. Landing on yesterday leaves today uncharged and still in play, so
        // the next launch after midnight charges it once and only once.
        healthDataLastSeen = calendar.date(byAdding: .day, value: missedDays, to: lastDay) ?? now
    }

    /// One mistake per eight hours spent at maximum hunger.
    ///
    /// Reads `hungerUpdatedAt` directly, which works because `HungerClock` FREEZES that timestamp at
    /// the instant hunger reached the maximum and leaves it there. So the gap between it and `now`
    /// is exactly how long the Digimon has been starving, and no second saved date is needed.
    private func chargeStarvationMistakes(now: Date) {
        guard hunger >= HungerClock.maximumHunger, let starvingSince = hungerUpdatedAt else {
            // Not starving. The spell is over, so the next one starts from zero rather than
            // inheriting a count that would make its first hour instantly a mistake.
            starvationMistakesCharged = 0
            return
        }

        let elapsed = now.timeIntervalSince(starvingSince)
        guard elapsed >= 0 else { return }

        // Compared in Double space before converting, for the reason `maximumStarvationMistakes-
        // Charged` documents.
        let spells = (elapsed / CareMistakes.secondsAtMaximumHungerPerMistake).rounded(.down)
        let earned = spells >= Double(CareMistakes.maximumStarvationMistakesCharged)
            ? CareMistakes.maximumStarvationMistakesCharged
            : Int(spells)

        let uncharged = earned - starvationMistakesCharged
        guard uncharged > 0 else { return }
        careMistakeCount += uncharged
        starvationMistakesCharged = earned
    }

    /// One mistake per six hours a FULL screen of poop has gone uncleaned.
    ///
    /// Reads `poopUpdatedAt` directly, exactly as `chargeStarvationMistakes` reads `hungerUpdatedAt`
    /// and for exactly the same reason: `PoopClock.advance` FREEZES that timestamp at the instant the
    /// ceiling was reached and leaves it there while the screen stays full. So the gap between it and
    /// `now` is already "how long has the mess been at its worst", and this rule needs no second
    /// saved date of its own.
    ///
    /// Cleaning is what stops the charging, and it stops it twice over: `clean()` zeroes `poopCount`,
    /// which fails the guard below and resets the marker, and it restamps `poopUpdatedAt`, so the
    /// screen's next spell at the ceiling is measured from the clean rather than from before it.
    private func chargeUncleanedPoopMistakes(now: Date) {
        guard poopCount >= PoopClock.maximumPoops, let fullSince = poopUpdatedAt else {
            // Not full. The spell is over, so the next one starts from zero rather than inheriting a
            // count that would make its first hour instantly a mistake.
            poopMistakesCharged = 0
            return
        }

        let elapsed = now.timeIntervalSince(fullSince)
        // Backwards means the clock or the timezone moved, not that anybody cleaned up.
        guard elapsed >= CareMistakes.secondsAtMaximumPoopBeforeMistake else { return }

        // ONE, not `elapsed / threshold`. No Double-to-Int conversion happens here at all, so this
        // rule needs no saturation guard of the kind starvation carries — a spell of any length,
        // up to `.distantFuture`, is worth exactly this.
        guard poopMistakesCharged == 0 else { return }
        careMistakeCount += 1
        poopMistakesCharged = 1
    }

    /// Charges the mistake for disturbing a sleeping Digimon, at most once per local day.
    ///
    /// Called when an action is attempted inside the sleep window. The action itself is blocked, so
    /// the Digimon is not really woken — but the PRD counts the attempt, and once a day is the right
    /// cap: prodding it six times is one bad night's care, not six.
    func recordWakingEarly(now: Date, calendar: Calendar = .current) {
        // Counted BEFORE the once-a-day guard, and so on every disturbance. The mistake is capped
        // at one a night; `stageSleepDisturbances` (US-084) is the count of how often it happened,
        // which is a different question and the one `care.sleepDisturbances` gates on.
        stageSleepDisturbances += 1

        let today = calendar.startOfDay(for: now)
        guard wakeMistakeDay != today else { return }
        wakeMistakeDay = today
        careMistakeCount += 1
    }
}
