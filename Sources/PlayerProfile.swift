import Foundation
import SwiftData

/// Everything the PLAYER owns, as opposed to everything one Digimon is (US-123).
///
/// One global record, like `EnergyLedger` and `MetricLedger`, and it is the answer to a question
/// that gets asked once per wave: where does a fact live when it must survive a death, a rebirth,
/// and — from US-124 — putting one Digimon away to raise another? Not on `GameState`, which is the
/// Digimon and is deleted whole every time one is replaced.
///
/// What it holds, and why each one is here rather than there:
/// - `lifetimeEnergy` — the whole player's earnings. It already outlived a Digimon before this
///   story: `GameStore.rebirth` read it off the corpse and copied it onto the fresh egg, which
///   worked only because there was exactly ONE Digimon. With a box of them that copy has no single
///   source and no single destination.
/// - the map fields — moved wholesale from `MapProgress` (US-118), which was written in this shape
///   for exactly this move.
/// - `ownedDigitamaIds` — every Digitama the player has ever been handed. US-127 refines this into
///   the HELD set (an unhatched egg, or a living Digimon that hatched from it) so a map cannot drop
///   the same egg twice; "ever owned" is the honest thing to record until origins are tracked.
///
/// Keyed dictionaries rather than a property per map for the same reason `MapProgress` used them:
/// the key vocabulary is data (`maps.json`), so a property per map would need a model migration
/// every time a map is added.
@Model
final class PlayerProfile {
    /// Energy earned over the player's whole history, across every Digimon. The number
    /// `BattlePower` reads and the one a memorial reports.
    var lifetimeEnergy: EnergyTotals

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

    /// Backing store for `ownedDigitamaIds`. An array because that is what SwiftData stores
    /// directly; the set is the shape every caller wants and `record(ownedDigitama:)` keeps it
    /// duplicate-free.
    private var ownedDigitamaStorage: [String]

    init(
        lifetimeEnergy: EnergyTotals = .zero,
        selectedMapId: String? = nil,
        recorded: [String: Double] = [:],
        finishedAt: [String: Date] = [:],
        ownedDigitamaIds: Set<String> = []
    ) {
        self.lifetimeEnergy = lifetimeEnergy
        self.selectedMapId = selectedMapId
        self.recordedStorage = recorded
        self.finishedAtStorage = finishedAt
        self.ownedDigitamaStorage = ownedDigitamaIds.sorted()
    }
}

// MARK: - Map progress

extension PlayerProfile {
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

    /// Copies a pre-US-123 `MapProgress` record onto this profile, wholesale.
    ///
    /// Assignment rather than merge: this only ever runs on a profile that has just been created,
    /// so there is nothing on it to merge with, and a merge rule would be a rule nobody could test
    /// against a real store.
    func adopt(_ progress: MapProgress) {
        selectedMapId = progress.selectedMapId
        recordedStorage = progress.recordedByMap
        finishedAtStorage = progress.finishedAtByMap
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

// MARK: - Digitama ever owned

extension PlayerProfile {
    /// Every Digitama the player has ever been handed, in no particular order.
    var ownedDigitamaIds: Set<String> {
        Set(ownedDigitamaStorage)
    }

    /// Records a Digitama as owned. Idempotent — being handed the same egg twice is one egg here,
    /// which is what makes this safe to call from every path that starts a game.
    func record(ownedDigitama id: String) {
        guard !ownedDigitamaStorage.contains(id) else { return }
        ownedDigitamaStorage.append(id)
    }
}

/// Credits already-deduplicated step deltas to the map the player is currently in (US-118).
///
/// The delta is claimed by the caller off `MetricLedger` and handed in, rather than read from
/// HealthKit here: the whole point of US-118's "walking 1,000 steps credits the map 1,000 and not
/// 2,000" is that there is ONE baseline for the day's step total. See `MetricLedger.claim`.
enum MapStepCreditor {
    /// Credits `steps` to the profile's selected map, and returns what was credited.
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
        to profile: PlayerProfile,
        catalog: MapCatalog = .bundled,
        now: Date
    ) -> Double {
        guard steps > 0,
              let mapId = profile.selectedMapId,
              let map = catalog.map(id: mapId) else { return 0 }

        profile.record(steps: steps, forMap: mapId)
        if profile.recorded(forMap: mapId) >= Double(map.totalSteps) {
            profile.markFinished(mapId, at: now)
        }
        return steps
    }
}
