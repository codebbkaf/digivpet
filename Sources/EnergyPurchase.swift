import Foundation

/// The one rule for paying for an action with energy: whichever of the payable energies the Digimon
/// holds MOST of pays the whole cost, ties going to the first in the list.
///
/// Lifted out of `TrainAction.begin` in US-108, when battling grew a cost of its own. Training and
/// battling charge the same points from the same pair, and a second copy of this arithmetic would be
/// a second place for a refund, a wrong payer or a `lifetimeEnergy` mistake to appear — the reason
/// the PRD asks for exactly one implementation.
///
/// Clock-free and view-free, like the actions that call it.
enum EnergyPurchase {
    /// Which of `payableWith` would pay `cost`, or nil if none of them holds enough.
    ///
    /// Reads only, so a button can ask what a tap would do without doing it — and asking here rather
    /// than re-deriving it means a disabled button and the refusal behind it cannot disagree.
    static func payer(for cost: Int, from payableWith: [EnergyType], in state: GameState) -> EnergyType? {
        // `max(by:)` keeps the FIRST of equal elements, which is what makes ties go to whichever
        // energy the caller listed first — Strength, for both of today's callers.
        guard let richest = payableWith.max(by: { state.stageEnergy[$0] < state.stageEnergy[$1] }),
              state.stageEnergy[richest] >= cost else {
            return nil
        }
        return richest
    }

    /// Charges `cost` to the richest payable energy and answers which one paid, or nil — having
    /// spent NOTHING — when none of them can cover it.
    ///
    /// Taken from `stageEnergy` alone: `lifetimeEnergy` records what was ever EARNED, and the ledger
    /// keys on what was credited rather than on what is held, so a spend can never be re-credited by
    /// the next health read. **Nothing here ever gives energy back** — the callers commit to the
    /// round they opened, and a refund would make walking out of it free.
    @discardableResult
    static func charge(_ cost: Int, from payableWith: [EnergyType], in state: GameState) -> EnergyType? {
        guard let payer = payer(for: cost, from: payableWith, in: state) else { return nil }
        state.stageEnergy[payer] -= cost
        return payer
    }
}
