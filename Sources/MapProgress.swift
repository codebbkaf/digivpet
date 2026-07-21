import Foundation
import SwiftData

/// LEGACY (US-118), kept only so a store written before US-123 can be READ.
///
/// The three fields on it moved to `PlayerProfile`, which is where everything that outlives a
/// Digimon now lives. Nothing in the game writes this any more, and nothing but
/// `GameStore.loadOrCreateProfile` reads it: that is where a record left by an older build is
/// copied onto the profile and then deleted.
///
/// **It stays in `GameStore.schema` on purpose.** Dropping the type would drop the table with the
/// player's sixteen counters still in it, and there would be no second chance to read them — the
/// same reason `GameState` still carries its `lifetimeEnergy` column. A dead entity in the schema
/// costs a table nobody opens; the alternative costs the player their map progress.
@Model
final class MapProgress {
    var selectedMapId: String?
    private var recordedStorage: [String: Double]
    private var finishedAtStorage: [String: Date]

    init(
        selectedMapId: String? = nil,
        recorded: [String: Double] = [:],
        finishedAt: [String: Date] = [:]
    ) {
        self.selectedMapId = selectedMapId
        self.recordedStorage = recorded
        self.finishedAtStorage = finishedAt
    }

    /// Every map that has ever been walked in, id -> steps.
    var recordedByMap: [String: Double] {
        recordedStorage
    }

    /// Every map that has been finished, id -> when. Both dictionaries are read whole because the
    /// migration copies them whole — a per-map accessor would need the caller to know the sixteen
    /// ids, and a store written by a build with a seventeenth map would quietly lose one.
    var finishedAtByMap: [String: Date] {
        finishedAtStorage
    }
}
