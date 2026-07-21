import Foundation

/// One dropped Digitama, told to the player (US-128).
///
/// A value built from the roster the moment a drop is granted, so the banner has a name, a stage and
/// a sprite to draw without reaching back into the store. Identifiable off the id so SwiftUI can
/// animate one banner out and the next in — the same shape `EvolutionEvent` gives the ceremony.
struct DigitamaDropAnnouncement: Equatable, Identifiable {
    /// The roster id of the egg, which is also its Dex id.
    let id: String
    let displayName: String
    /// As `RosterEntry.spriteFile` — the basename `IdleSpriteView` resolves under the stage folder.
    let spriteFile: String
    /// Always `.digitama`, but read off the roster rather than assumed, because it is the folder the
    /// idle sprite is drawn from.
    let stage: Stage
}

/// The rule that turns "the player met a map's stated conditions" into "an egg drops" (US-128).
///
/// Pure and view-free, exactly like `MapOpponentBand` and the rest of the map arithmetic: it takes
/// a map, the player's counters as a `ConditionContext`, and the set of Digitama already HELD, and
/// answers with the one id to award — or nil for nothing. `MainScreenModel` is the only caller, and
/// it runs this at the three moments a drop is earned (after a train, after a battle, after a step
/// accrual tick), never on a timer.
///
/// Reusing `ConditionReveal.allMet` — the very predicate the map detail's "Ready to find" mark and
/// the evolution engine both read — is deliberate: a slot the player was PROMISED was ready on the
/// detail screen must be exactly the slot that can drop here, and a second reading of "all met"
/// would be a second chance for the two to disagree.
enum DigitamaDropEngine {
    /// Every slot in `map` the player has EARNED and does not already hold.
    ///
    /// A slot is a candidate when all of its conditions currently hold AND its Digitama is not in the
    /// held set (US-127) — an egg already in the box, or a living Digimon that hatched from it, is
    /// never dropped a second time, which is the whole rule that stops a player farming duplicates.
    ///
    /// A slot with NO conditions is vacuously all-met, so it is a candidate the moment the map is
    /// selected and the egg is not held — the honest reading of "no criterion left to satisfy". No
    /// shipped slot is authored that way (FR-13 gives every one a tier-scaled condition), but nothing
    /// here forbids it.
    static func eligibleSlots(
        in map: AdventureMap,
        context: ConditionContext,
        held: Set<String>
    ) -> [DigitamaSlot] {
        map.digitamaSlots.filter { slot in
            !held.contains(slot.digitamaId)
                && ConditionReveal.allMet(slot.conditions, in: context)
        }
    }

    /// The one Digitama id to award this check, or nil for none.
    ///
    /// At most one, always: an empty eligible set awards nothing, and a set of several hands back a
    /// single member chosen with `generator` (AC5). The generator is `inout` and injected so the
    /// choice is deterministic under a seeded generator — three eligible eggs pick the same one every
    /// run of a test, and a fresh random seed per check in the app makes it a real drop rather than
    /// always the first slot.
    ///
    /// A nil `map` — the player has selected nowhere — awards nothing, so the caller need not special
    /// case "no map": there is no place for an egg to be found.
    static func award<G: RandomNumberGenerator>(
        in map: AdventureMap?,
        context: ConditionContext,
        held: Set<String>,
        using generator: inout G
    ) -> String? {
        guard let map else { return nil }
        return eligibleSlots(in: map, context: context, held: held)
            .randomElement(using: &generator)?
            .digitamaId
    }
}
