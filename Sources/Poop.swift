import Foundation

/// How poop accumulates on the screen with elapsed real time.
///
/// Shaped exactly like `HungerClock`, and for the same reason: poop is never ticked, it is
/// recomputed from `GameState.poopUpdatedAt` against the clock, so a Digimon left alone for a day
/// is found standing in a day's worth of mess rather than in none. Every threshold lives here and
/// nowhere else.
///
/// **The rule: one poop per three elapsed AWAKE hours, and nothing else.** Two choices in that,
/// both deliberate:
///
/// - *Elapsed time, not feeding.* The obvious V-Pet rule is "eating produces poop", but poop exists
///   here to be the visible face of neglect — US-053 charges care mistakes for leaving it — and
///   tying it to feeding would mean a Digimon nobody ever feeds makes no mess at all. That gets it
///   exactly backwards: the most neglected Digimon would have the cleanest screen. Time is the one
///   input that keeps running while the user is not looking.
/// - *Three hours, against hunger's four.* Slightly faster than hunger so that cleaning is its own
///   errand rather than something always done on the same visit as feeding, and so an ordinary
///   waking day produces a handful rather than one.
enum PoopClock {
    /// How long one poop takes to appear: three real awake hours.
    static let secondsPerPoop: TimeInterval = 3 * 60 * 60

    /// The most poops that can sit on screen at once.
    ///
    /// Four, matching `HungerClock.maximumHunger` — and for a second reason hunger does not have:
    /// four 16px sprites is what fits beside the Digimon on a 41mm screen without the ground row
    /// having to scroll. A fifth would have nowhere to go.
    static let maximumPoops = 4

    /// The result of aging `poopCount` forward: the new count, and the timestamp to save with it.
    struct Advanced: Equatable {
        var poopCount: Int
        /// The new `poopUpdatedAt`. Deliberately NOT `now` except when paused — see `advance`.
        var updatedAt: Date
    }

    /// Ages `poopCount` forward by however many whole 3h intervals have passed since `lastUpdated`.
    ///
    /// `updatedAt` moves by exactly the intervals that were APPLIED, never to `now`, which carries a
    /// part-worn interval across calls instead of dropping it — the same two consequences spelled
    /// out on `HungerClock.advance`, including the timestamp freezing at the instant the ceiling was
    /// reached. US-053 needs that freeze: it is how long the screen has been full of mess, with no
    /// second saved date.
    ///
    /// - Parameter isPaused: whether the Digimon is asleep or dead. A paused call accrues nothing
    ///   AND restamps to `now`, so the paused stretch is genuinely skipped rather than banked and
    ///   paid out by the next waking refresh. The honest limit of that: pausing is only observed by
    ///   a refresh that runs during it, so a night the app slept through is still charged. Poop is
    ///   not worth waking the watch for, and `SleepSchedule` is inferred from last night alone, so
    ///   reconstructing which of the closed hours were asleep would be guesswork dressed up as
    ///   arithmetic.
    static func advance(poopCount: Int, lastUpdated: Date?, isPaused: Bool, now: Date) -> Advanced {
        // Before the elapsed check, so a paused Digimon restamps rather than accruing on the way in.
        guard !isPaused else { return Advanced(poopCount: poopCount, updatedAt: now) }
        // nil is a save written before poop was tracked. There is no baseline to measure from, so
        // the clock STARTS now rather than back-filling a mess the user never had a chance to clean.
        guard let lastUpdated else { return Advanced(poopCount: poopCount, updatedAt: now) }

        let elapsed = now.timeIntervalSince(lastUpdated)
        // Backwards means the clock or the timezone moved, not that the poop cleaned itself.
        guard elapsed >= 0 else { return Advanced(poopCount: poopCount, updatedAt: now) }

        let room = maximumPoops - poopCount
        guard room > 0 else { return Advanced(poopCount: poopCount, updatedAt: lastUpdated) }

        // Compared in Double space BEFORE converting, because `Int(Double)` traps outside Int's
        // range and `elapsed` is only as sane as the device clock. See `HungerClock.advance`.
        let intervals = (elapsed / secondsPerPoop).rounded(.down)
        guard intervals >= 1 else { return Advanced(poopCount: poopCount, updatedAt: lastUpdated) }
        let applied = intervals >= Double(room) ? room : Int(intervals)

        return Advanced(
            poopCount: poopCount + applied,
            updatedAt: lastUpdated.addingTimeInterval(Double(applied) * secondsPerPoop)
        )
    }
}

extension GameState {
    /// Brings `poopCount` up to date with `now`. Idempotent within an interval, so the main screen
    /// can call it on every refresh.
    ///
    /// - Parameter isAsleep: whether the Digimon is currently in its sleep window. Passed in rather
    ///   than read off `self` for the same reason `FeedAction.feed` takes it — sleep is DERIVED from
    ///   the user's sleep history (US-026) and is not saved-game state. Death, which is, is read
    ///   here: a dead Digimon produces nothing.
    func advancePoop(isAsleep: Bool, now: Date) {
        let advanced = PoopClock.advance(
            poopCount: poopCount,
            lastUpdated: poopUpdatedAt,
            isPaused: isAsleep || healthStatus == .dead,
            now: now
        )
        poopCount = advanced.poopCount
        poopUpdatedAt = advanced.updatedAt
    }

    /// Whether this refresh is the one that owes the user a "there is a mess" notice, claiming it as
    /// it answers so no later refresh asks again.
    ///
    /// **The threshold is the screen FILLING**, `PoopClock.maximumPoops`, and it is the same
    /// threshold US-053 charges its care mistake from — deliberately, because that is what makes the
    /// notice worth sending. It arrives at the instant the mess starts costing something and
    /// `CareMistakes.secondsAtMaximumPoopBeforeMistake` hours before it does, so a user who acts on
    /// it pays nothing. Notifying on the FIRST poop would be notifying that the Digimon has been
    /// alive three hours.
    ///
    /// Claimed once per mess rather than once per refresh, on the same reasoning as
    /// `claimDeathWarning`: a user who opens the app five times over a filthy afternoon is told
    /// once. Dropping off the ceiling re-arms it — cleaning is the only thing that does that — so a
    /// screen cleaned and left to fill again is a NEW mess and is notified about afresh.
    ///
    /// THE CLAIM IS STAMPED WHETHER OR NOT A NOTIFICATION GOES OUT, exactly as `claimDeathWarning`
    /// stamps its own and for the same reason: the marker records that the game reached the moment,
    /// not that the user was told. Suppression is `NotificationDispatcher`'s job and is downstream
    /// of this.
    ///
    /// Call AFTER `advancePoop`, which is what may have just filled the screen.
    func claimPoopNotification() -> Bool {
        guard poopCount >= PoopClock.maximumPoops else {
            // Below the ceiling: nothing is owed, and the next fill starts clean.
            poopNotified = false
            return false
        }
        guard !poopNotified else { return false }
        poopNotified = true
        return true
    }
}
