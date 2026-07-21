import Foundation

/// Putting a Digimon away in the box and taking it out again (US-125).
///
/// **Freezing is a clock offset, not a paused timer**, and that is the whole design. Every
/// time-derived reading in this game — hunger, the starvation and missing-data care mistakes, the
/// mess on the floor, how long an illness has run, how old the Digimon is, whether its stage's
/// evolution gate has opened — is derived on demand from a saved `Date` against an injected clock,
/// deliberately, so that an app which was never opened still gets hungry. There is no counter
/// anywhere to stop ticking.
///
/// So a frozen Digimon is protected twice, and it needs both halves:
///
/// 1. **Nothing accrues while it is away.** Every accrual method on `GameState` refuses to run on
///    an inactive record — see `advanceHunger`, `advancePoop`, `auditCareMistakes`,
///    `updateSickness`, `updateDeath` — so the STORED counters (hunger, poop, care mistakes) cannot
///    move. In practice nothing even holds a frozen record: `MainScreenModel` is built on
///    `GameStore.loadOrCreate`, which returns the active one. The guards are what make that a rule
///    rather than an accident of who happens to call what.
/// 2. **The timeline is translated on the way out.** The readings DERIVED fresh from a stored date
///    cannot be guarded, because nothing runs to guard: age is `now - birthDate` however long ago
///    that was. `thaw(at:)` moves every such instant forward by the span the Digimon spent away,
///    so each of those subtractions comes out exactly as it did at the moment of the freeze.
///
/// The alternative — leaving the dates alone and subtracting `frozenDuration` at every read — was
/// rejected: it means finding and correcting every one of those subtractions, forever, and one
/// missed reader is a Digimon that quietly starved in the box.
///
/// ## What is shifted, and what deliberately is not
///
/// Shifted: every instant an ELAPSED SPAN is measured from. Because the whole set moves together by
/// the same amount, the gaps BETWEEN them are preserved too — a Digimon frozen mid-illness comes out
/// with its illness exactly as far along, not restarted.
///
/// Not shifted: the LOCAL-DAY and NIGHT keys — `refusalDay`, `battleDay`, `refusalMistakeDay`,
/// `wakeMistakeDay`, `lightAuditedNight`, `lightNotifiedNight`. These are not spans; they are
/// calendar keys asking "was this already charged TODAY". A day that is over is over whoever was in
/// the box while it passed, and every one of them reads a stale key as "not yet charged this day",
/// which is the correct answer for the fresh day the Digimon is taken out into. Shifting them would
/// do real harm in the opposite direction: a key dragged forward into today would forgive the first
/// real mistake of the day the player is actually living in.
enum Freeze {}

/// What a `freeze` or `thaw` did, so `GameStore.activate(_:now:)` can put it back if the save that
/// was supposed to make it durable fails.
///
/// Exists because the activate has to be all-or-nothing across SEVERAL records, and a half-applied
/// switch is the one outcome that loses a Digimon: the frozen clock and the `isActive` flag must
/// agree, or the next thaw measures a span that never happened.
struct FreezeChange {
    /// The `frozenSince` to put back — nil when undoing a freeze, the original instant when undoing
    /// a thaw.
    fileprivate let restoredFrozenSince: Date?
    /// How far the timeline was moved. Zero for a freeze, which only stamps a marker.
    fileprivate let shift: TimeInterval
}

extension GameState {
    /// Puts this Digimon away, starting the clock its thaw will be measured against.
    ///
    /// Does NOT touch `isActive`: the two belong together, and keeping them together is
    /// `GameStore.activate(_:now:)`'s job, because "exactly one Digimon is out" is a fact about the
    /// whole store rather than about any one record.
    ///
    /// Freezing an already-frozen Digimon is a no-op that returns nil rather than restamping. That
    /// matters: `activate` freezes every record it did not just thaw, so this runs on Digimon that
    /// have been in the box for weeks, and restamping would hand each of them the whole spell they
    /// had already served.
    @discardableResult
    func freeze(at now: Date) -> FreezeChange? {
        guard frozenSince == nil else { return nil }
        frozenSince = now
        return FreezeChange(restoredFrozenSince: nil, shift: 0)
    }

    /// Takes this Digimon out of the box, banking the span it spent there and translating its whole
    /// timeline forward by exactly that span.
    ///
    /// A Digimon that was not frozen is a no-op returning nil, so activating the one already out
    /// costs nothing and cannot shift anything.
    ///
    /// A `now` BEFORE the freeze means the device clock or the timezone moved, not that the Digimon
    /// came out before it went in. The span is clamped at zero: refusing to shift is the honest
    /// answer, where a negative shift would age it by wall-clock nonsense.
    @discardableResult
    func thaw(at now: Date) -> FreezeChange? {
        guard let since = frozenSince else { return nil }
        frozenSince = nil
        let span = max(0, now.timeIntervalSince(since))
        guard span > 0 else { return FreezeChange(restoredFrozenSince: since, shift: 0) }
        frozenDuration += span
        shiftTimeline(by: span)
        return FreezeChange(restoredFrozenSince: since, shift: span)
    }

    /// Puts back exactly what `freeze` or `thaw` changed. Only `GameStore.activate(_:now:)` should
    /// need this, and only when the save it was part of has already failed.
    func undo(_ change: FreezeChange) {
        if change.shift != 0 {
            shiftTimeline(by: -change.shift)
            frozenDuration -= change.shift
        }
        frozenSince = change.restoredFrozenSince
    }

    /// Moves every instant an elapsed span is measured from by `span`.
    ///
    /// One list, in one place, and that is the point: the day a new time-derived field is added to
    /// `GameState`, this is the single line it has to be added to for a frozen Digimon to stay
    /// frozen. See the type comment for why the day and night keys are absent rather than forgotten.
    ///
    /// `diedAt` is here for completeness rather than for use — a dead Digimon cannot be activated
    /// (US-126), so nothing can reach this with one — but leaving it out would shrink the lifespan a
    /// memorial reports, since `birthDate` moves and it would not.
    private func shiftTimeline(by span: TimeInterval) {
        birthDate += span
        stageEnteredDate += span
        hungerUpdatedAt = hungerUpdatedAt.map { $0 + span }
        poopUpdatedAt = poopUpdatedAt.map { $0 + span }
        healthDataLastSeen = healthDataLastSeen.map { $0 + span }
        awakeUntil = awakeUntil.map { $0 + span }
        sickSince = sickSince.map { $0 + span }
        diedAt = diedAt.map { $0 + span }
        deathWarningSentAt = deathWarningSentAt.map { $0 + span }
        lightStateChangedAt = lightStateChangedAt.map { $0 + span }
        // Read only to break a `dominantEnergyType` tie, so what matters is the ORDER among the
        // four. Moved with everything else all the same: an instant left behind while `birthDate`
        // moves forward is a timestamp from before the Digimon was born.
        var earned = energyLastEarned
        for type in EnergyType.allCases {
            earned[type] = earned[type].map { $0 + span }
        }
        energyLastEarned = earned
    }
}
