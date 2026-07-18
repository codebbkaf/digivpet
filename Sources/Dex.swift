import Foundation
import SwiftData

/// One Digimon the player has ever raised — an entry in the field guide.
///
/// The Dex outlives any single Digimon on purpose: death and rebirth (US-029) preserve it, which
/// is the whole reason it is its OWN `@Model` and not a field on `GameState`. `resetGame` is a
/// total wipe of the current game, but it deletes only `GameState`, so Dex entries survive it.
///
/// One record per discovered node id. It is a NEW entity, so adding it to `GameStore.schema` is a
/// lightweight migration a store written before it existed opens cleanly — the same shape US-014
/// proved safe for `EnergyLedger`. (An added non-optional ATTRIBUTE on an existing model would
/// not be; US-015's note is the warning.)
@Model
final class DexEntry {
    /// The evolution-graph node id, e.g. "botamon". Not the sprite filename — the graph resolves
    /// that. Treated as unique across the Dex by `GameStore.recordDiscovery`.
    var digimonId: String
    /// When this Digimon was first discovered. Kept from the first sighting, never overwritten.
    var firstDiscovered: Date

    init(digimonId: String, firstDiscovered: Date) {
        self.digimonId = digimonId
        self.firstDiscovered = firstDiscovered
    }
}
