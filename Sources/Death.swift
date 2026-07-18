import Foundation

/// When an untreated illness kills a Digimon, and what is put on its memorial.
///
/// Like `Sickness` and `CareMistakes`, nothing here is ever ticked: death is derived from the
/// instant the illness began (`GameState.sickSince`) against an injected clock, so a Digimon left
/// sick over a long weekend is found dead the first time anyone looks rather than only if the app
/// happened to be open at the 72-hour mark.
enum Death {
    /// How long a Digimon may stay sick and untreated before it dies: 72 real hours (PRD FR-29).
    static let secondsSickUntilDeath: TimeInterval = 72 * 60 * 60

    /// Seconds in a day, for turning a lifespan into the whole days a memorial reports.
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
}

/// What a memorial screen says about the Digimon that just died.
///
/// A value rather than a live `GameState`, and that is the point: the state it was read off is
/// about to be replaced by the rebirth, so the screen has to keep its own copy of what it is
/// mourning. Everything on it is final by definition.
struct Memorial: Equatable {
    let displayName: String
    let stage: Stage
    /// Whole days between birth and death, rounded down — a Digimon that lived two and a half days
    /// lived two.
    let lifespanDays: Int
    /// The whole life's earnings. This is the one total that OUTLIVES the Digimon: the reborn one
    /// inherits it, so the number here is also the number it starts with.
    let lifetimeEnergy: EnergyTotals
    let strengthStat: Int
    let battleWins: Int
    let battleLosses: Int
}

extension GameState {
    /// Kills a Digimon that has been sick and untreated for `Death.secondsSickUntilDeath`.
    ///
    /// Idempotent, so `refresh()` can call it on every foregrounding. Runs AFTER `updateSickness`,
    /// which is what decides whether the Digimon is sick at all — this only measures how long it has
    /// been so.
    ///
    /// It also OWNS the `sickSince` marker, rather than `updateSickness` stamping it: the marker
    /// exists only to answer this question, and keeping it here means the illness rule stays the
    /// pure function of count-and-energy its own documentation promises, with no clock of its own.
    /// The clock starts at the refresh that first observed the illness, which is the earliest moment
    /// the game can honestly say it knew.
    func updateDeath(now: Date) {
        switch healthStatus {
        case .sick:
            guard let since = sickSince else {
                // The refresh that diagnosed it. Nothing has elapsed yet, so the countdown starts
                // rather than being measured.
                sickSince = now
                return
            }
            // Backwards means the device clock or the timezone moved, not that time passed.
            guard now.timeIntervalSince(since) >= Death.secondsSickUntilDeath else { return }
            healthStatus = .dead
            diedAt = now
        case .healthy:
            // Cured, so the next illness is measured from its own beginning rather than inheriting a
            // countdown that was already most of the way to killing it.
            sickSince = nil
        case .dead:
            // Death is final, and `diedAt` is already stamped. `sickSince` is deliberately left
            // alone: clearing it would erase the record of how the Digimon came to die.
            break
        }
    }

    /// What to put on this Digimon's memorial, or nil while it is still alive.
    ///
    /// - Parameter displayName: the name the evolution graph gives its current id. Passed in because
    ///   `GameState` saves only the id, and the graph is what turns that into a name.
    func memorial(displayName: String) -> Memorial? {
        guard healthStatus == .dead, let diedAt else { return nil }
        let lifespan = diedAt.timeIntervalSince(birthDate)
        return Memorial(
            displayName: displayName,
            stage: stage,
            // Clamped at zero, so a save restored onto a watch whose clock has been wound back
            // reports a short life rather than a negative one.
            lifespanDays: max(0, Int((lifespan / Death.secondsPerDay).rounded(.down))),
            lifetimeEnergy: lifetimeEnergy,
            strengthStat: strengthStat,
            battleWins: battleWins,
            battleLosses: battleLosses
        )
    }
}
