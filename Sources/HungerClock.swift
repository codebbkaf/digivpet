import Foundation

/// How hunger grows with elapsed real time.
///
/// Hunger is never ticked. It is recomputed from `GameState.hungerUpdatedAt` against the clock,
/// which is what makes it correct after the app has been closed for days: an app that was never
/// opened still gets hungry. Every threshold lives here and nowhere else, matching `EnergyRates`
/// and `EvolutionTiming`.
enum HungerClock {
    /// How long one unit of hunger takes to accrue: four real hours (PRD FR-27).
    static let secondsPerHungerUnit: TimeInterval = 4 * 60 * 60

    /// The most hunger a Digimon can hold, i.e. "starving".
    ///
    /// Four, the classic V-Pet meter — the PRD fixes the RATE but not the ceiling, so this is the
    /// one number here not taken from it. Four units is 16h to go from fed to starving, which puts
    /// a full meter within one neglected day.
    static let maximumHunger = 4

    /// The result of aging `hunger` forward: the new value, and the timestamp to save with it.
    struct Advanced: Equatable {
        var hunger: Int
        /// The new `hungerUpdatedAt`. Deliberately NOT `now` — see `advance`.
        var updatedAt: Date
    }

    /// Ages `hunger` forward by however many whole 4h intervals have passed since `lastUpdated`.
    ///
    /// `updatedAt` moves by exactly the intervals that were APPLIED, never to `now`. Two
    /// consequences, both load-bearing:
    ///
    /// - A part-worn interval is carried, not dropped. Stamping `now` would mean two 3h sessions
    ///   accrue nothing, and an app opened often would never get hungry at all.
    /// - Once hunger is at the maximum, nothing is applied and the timestamp freezes at the instant
    ///   it hit the maximum. That is what US-027's "hunger at max for 8h+" care mistake needs, and
    ///   it comes free rather than needing a second saved date.
    ///
    /// The cost of that second point: after US-024 feeds a Digimon down off the maximum, the stale
    /// timestamp would immediately re-accrue every interval it sat there. **Feeding must restamp
    /// `hungerUpdatedAt` to the moment of the feed** — which is the natural reading of a feed anyway.
    ///
    /// - Parameter lastUpdated: nil for a save written before hunger was tracked. There is no
    ///   baseline to measure from, so the clock STARTS now rather than guessing at elapsed hunger
    ///   from `birthDate` — that would double-count against the hunger such a save already holds.
    static func advance(hunger: Int, lastUpdated: Date?, now: Date) -> Advanced {
        guard let lastUpdated else { return Advanced(hunger: hunger, updatedAt: now) }

        let elapsed = now.timeIntervalSince(lastUpdated)
        // Backwards means the clock or the timezone moved, not that the Digimon got less hungry.
        // Restamping keeps the timestamp from sitting in the future and freezing hunger until the
        // wall clock catches up.
        guard elapsed >= 0 else { return Advanced(hunger: hunger, updatedAt: now) }

        let room = maximumHunger - hunger
        guard room > 0 else { return Advanced(hunger: hunger, updatedAt: lastUpdated) }

        // Compared in Double space BEFORE converting, because `Int(Double)` traps outside Int's
        // range and `elapsed` is only as sane as the device clock. A save restored onto a watch set
        // to the year 3000 should starve the Digimon, not crash the app.
        let intervals = (elapsed / secondsPerHungerUnit).rounded(.down)
        guard intervals >= 1 else { return Advanced(hunger: hunger, updatedAt: lastUpdated) }
        let applied = intervals >= Double(room) ? room : Int(intervals)

        return Advanced(
            hunger: hunger + applied,
            updatedAt: lastUpdated.addingTimeInterval(Double(applied) * secondsPerHungerUnit)
        )
    }
}

extension GameState {
    /// Brings `hunger` up to date with `now`. Idempotent within an interval, so the main screen can
    /// call it on every refresh.
    ///
    /// A Digimon in the box does not get hungry (US-125). The guard is the first half of `Freeze`'s
    /// two-part promise; the other half is the shift `thaw(at:)` applies to `hungerUpdatedAt`, which
    /// is what stops the elapsed time being handed over in one lump the moment it comes out.
    func advanceHunger(now: Date) {
        guard isActive else { return }
        let advanced = HungerClock.advance(hunger: hunger, lastUpdated: hungerUpdatedAt, now: now)
        hunger = advanced.hunger
        hungerUpdatedAt = advanced.updatedAt
    }
}
