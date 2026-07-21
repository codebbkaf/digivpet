import Foundation

/// The floor under the whole game (US-129): a player whose every Digimon is dead and whose box holds
/// no unhatched egg is handed one, immediately, with no condition and no map requirement.
///
/// This is not a reward, so it deliberately shares nothing with US-128's drop engine: there is no
/// map, no `ConditionContext`, no generator and no held-set check. A drop is something the player
/// EARNED and must never be handed twice; this is the answer to "I have lost everything", and being
/// handed the same egg a second life later is the point rather than a bug — which is why AC2 says it
/// fires even when `agu_digitama` was previously held by a Digimon that has since died.
///
/// The state it reads is the box itself (`GameStore.allStates()`), for the same reason
/// `heldDigitamaIds` derives rather than stores: "the player has nothing left to raise" is fully
/// determined by the records that exist, so there is nothing to keep in sync at a death, a hatch, a
/// reset or a Jogress, and no stored flag that can drift into locking a player out of their own game.
enum StrandedFailsafe {
    /// The egg the failsafe hands over. Agumon's, by name in the story: the line every player knows,
    /// wired into the evolution graph since US-014 and playable end to end.
    static let digitamaId = "agu_digitama"

    /// Whether the box leaves the player with nothing to raise.
    ///
    /// Spelled as AC1's two clauses rather than collapsed, because the criterion is what this has to
    /// keep meaning. They do collapse today — an unhatched Digitama IS a living record, so "no living
    /// Digimon and no unhatched Digitama" is exactly "nothing in the box is alive" — but writing it
    /// out is what makes a future where an egg is stored some other way fail here rather than
    /// silently strand somebody.
    ///
    /// An EMPTY box is stranded, vacuously and correctly: a player with no records at all has nothing
    /// to raise either. Nothing in the shipped app can produce one — `loadOrCreate` starts a Digimon
    /// when the box is empty, and it runs before this on every launch — so this is the honest answer
    /// to a state that should not arise rather than a path anything depends on.
    static func isStranded(in states: [GameState]) -> Bool {
        let livingDigimon = states.contains { !$0.isDead && $0.stage != .digitama }
        let unhatchedDigitama = states.contains { !$0.isDead && $0.stage == .digitama }
        return !livingDigimon && !unhatchedDigitama
    }
}
