import Foundation
import SwiftData

/// Where the player is adventuring, and how far they have got in each map (US-118).
///
/// A SINGLE global record, keyed dictionaries inside it, rather than one record per map: sixteen
/// rows that are only ever read together are sixteen fetches and sixteen chances to be half-written,
/// and the US-119 list wants all of them at once anyway. Same shape as `MetricLedger`'s
/// `[String: Double]` storage and for the same reason — the key vocabulary is data (`maps.json`)
/// rather than code, so a property per map would need a model migration every time a map is added.
///
/// **Deliberately NOT part of `GameState`.** Map progress outlives the Digimon that walked it: a
/// death, a rebirth and (US-124) putting one Digimon away for another must all leave the sixteen
/// maps exactly where they were. `resetGame` wipes `GameState` and never touches this, which is the
/// same arrangement `EnergyLedger` and `MetricLedger` already have.
///
/// US-123 folds these fields onto `PlayerProfile`, which is where everything that outlives a
/// Digimon ends up. The shape here is chosen to make that a move rather than a rewrite: one record,
/// three properties, no relationships.
@Model
final class MapProgress {
    /// The map the player's steps are accruing to, or nil for "nowhere chosen yet".
    ///
    /// Nil is a real state and not a stand-in for the first map: a save that has never opened the
    /// map list has not chosen anywhere to go, the game is fully playable without one (US-120), and
    /// silently defaulting to `01_grassland` would credit steps to a place the player never picked.
    var selectedMapId: String?

    /// Backing store for the per-map step counters. Absent means zero; nothing writes an explicit 0.
    private var recordedStorage: [String: Double]

    /// Backing store for the finish stamps. A map is finished if and only if it has one, so this
    /// doubles as the "already fired" marker that keeps a finish from re-firing every refresh once
    /// the counter is past the total.
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
}

extension MapProgress {
    /// Steps recorded in this map, in the units the reading is in — steps, so whole numbers in
    /// practice. `Double` because that is what a `HealthReading` carries; US-119 formats it.
    func recorded(forMap id: String) -> Double {
        recordedStorage[id] ?? 0
    }

    /// When this map was first finished, or nil if it has not been.
    func finishedAt(forMap id: String) -> Date? {
        finishedAtStorage[id]
    }

    func isFinished(forMap id: String) -> Bool {
        finishedAtStorage[id] != nil
    }

    /// Every map that has ever been walked in, id -> steps. For the US-119 list, which wants all
    /// sixteen rows in one read. A copy, so a caller cannot write progress by mutating it.
    var recordedByMap: [String: Double] {
        recordedStorage
    }

    /// Adds `steps` to a map's counter. Never decreases it and never caps it — see
    /// `MapStepCreditor`, which is the only thing that should be calling this.
    func record(steps: Double, forMap id: String) {
        guard steps > 0 else { return }
        recordedStorage[id] = recorded(forMap: id) + steps
    }

    /// Stamps a map finished, once. A second call is ignored, so the stamp is the moment the map
    /// was first crossed rather than the last time anything looked.
    func markFinished(_ id: String, at date: Date) {
        guard finishedAtStorage[id] == nil else { return }
        finishedAtStorage[id] = date
    }

    #if DEBUG
    /// Debug-only: wipes every counter, stamp and the selection.
    ///
    /// The inverse of the US-119 screenshot flags, and compiled out of release builds because it is
    /// the one operation the game itself must never perform — map progress is what outlives a
    /// Digimon's death and a rebirth, so a shipped "clear it all" would be a way to lose it. See
    /// `MainScreenModel.seedMapListDemoIfRequested`.
    func clearForDemo() {
        selectedMapId = nil
        recordedStorage = [:]
        finishedAtStorage = [:]
    }
    #endif
}

/// Credits already-deduplicated step deltas to the map the player is currently in (US-118).
///
/// The delta is claimed by the caller off `MetricLedger` and handed in, rather than read from
/// HealthKit here: the whole point of US-118's "walking 1,000 steps credits the map 1,000 and not
/// 2,000" is that there is ONE baseline for the day's step total. See `MetricLedger.claim`.
enum MapStepCreditor {
    /// Credits `steps` to `progress`' selected map, and returns what was credited.
    ///
    /// Nothing accrues when no map is selected, or when the selection names no map in the catalog —
    /// a delta with nowhere to go is dropped rather than parked somewhere it can later be mistaken
    /// for a real map's progress. It is NOT put back on the ledger: the reading it came from is
    /// already banked, and un-banking it would credit those steps again on the next refresh.
    ///
    /// A map is marked finished the first time its counter reaches `totalSteps`, with `now` as the
    /// stamp. The counter is not capped there — `totalSteps` is a finish line, not a ceiling — and
    /// `markFinished` ignores a second crossing, so passing the total again cannot re-fire it.
    @discardableResult
    static func credit(
        steps: Double,
        to progress: MapProgress,
        catalog: MapCatalog = .bundled,
        now: Date
    ) -> Double {
        guard steps > 0,
              let mapId = progress.selectedMapId,
              let map = catalog.map(id: mapId) else { return 0 }

        progress.record(steps: steps, forMap: mapId)
        if progress.recorded(forMap: mapId) >= Double(map.totalSteps) {
            progress.markFinished(mapId, at: now)
        }
        return steps
    }
}
