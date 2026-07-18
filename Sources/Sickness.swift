import Foundation

/// When neglect makes a Digimon ill, and what makes it well again.
///
/// The counter this reads is the one US-027 fills — `careMistakeCount`, fed by all four kinds of
/// neglect. Nothing here derives anything from elapsed time itself: the audit has already turned
/// time into mistakes by the time this runs, so sickness is a pure function of the count and of the
/// day's energy, and needs no clock or marker of its own.
enum Sickness {
    /// Accumulated care mistakes that make a Digimon sick: three (PRD FR-32).
    static let careMistakesUntilSick = 3

    /// Energy earned in one local day that cures it: thirty (PRD FR-33). Measured across all four
    /// types together, not per type — a day spent walking should cure as well as a day spent asleep.
    static let energyInADayToCure = 30
}

extension GameState {
    /// Brings `healthStatus` into line with the care record and the day's earnings.
    ///
    /// Idempotent, so `refresh()` can call it every time the app comes to the front. Called AFTER
    /// `auditCareMistakes`, because the mistake that tips a Digimon over is usually one the audit
    /// has only just charged for time that passed while the app was closed.
    ///
    /// THE CURE IS CHECKED BEFORE THE ILLNESS, and the order is the whole design: a Digimon that
    /// falls sick on an active day is not instantly made well again by energy it had already earned
    /// before it fell ill. It stays visibly sick, and the next refresh — by which point the day's
    /// 30 points really do postdate the diagnosis — is what cures it.
    ///
    /// - Parameter energyEarnedToday: everything credited on today's local day, from the
    ///   `EnergyLedger`. Passed in rather than read off `self`, because `GameState` deliberately
    ///   does not hold the ledger: the day belongs to the watch, not to whoever is living on it.
    func updateSickness(energyEarnedToday: Int) {
        switch healthStatus {
        case .sick where energyEarnedToday >= Sickness.energyInADayToCure:
            // The care record is wiped with the cure, per AC3. That is the ONLY thing in the game
            // that ever lowers `careMistakeCount`, and it is what stops a cured Digimon from
            // relapsing on its next refresh off the same three mistakes it was just forgiven.
            healthStatus = .healthy
            careMistakeCount = 0
        case .healthy where careMistakeCount >= Sickness.careMistakesUntilSick:
            healthStatus = .sick
        default:
            // Already sick and still neglected, already healthy and well cared for, or dead —
            // death is final, and no amount of walking brings a Digimon back.
            break
        }
    }
}
