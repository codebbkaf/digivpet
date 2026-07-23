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

    /// Meat, the one global feed currency (US-174), shared across the whole box of Digimon.
    ///
    /// Earned by winning battles (US-175) and spent one unit per feed (`FeedAction.feed`), replacing
    /// the per-Digimon Vitality that used to buy a meal. Global rather than on `GameState` because a
    /// larder is the player's, not the pet's — putting one Digimon away to raise another must not
    /// strand the meat you battled for. Capped in display at `ConsumptionConfig.meatCap`.
    ///
    /// Inline default of 0 so an existing save migrates to an empty larder: SwiftData adds the new
    /// attribute with this default rather than needing a hand-written migration, and 0 is the honest
    /// starting stock — you battle to earn the first meal, you are not handed one.
    var meat: Int = 0

    /// Spendable cleaning charges (US-178), 0...`ConsumptionConfig.maxCleanCharges`. Earned from real
    /// HealthKit handwashing by `creditCleanCharges` and spent one at a time by `MainScreenModel.clean`,
    /// this is the currency that gates clearing the mess — the last arm of the care loop to draw on a
    /// real-world action.
    ///
    /// Global rather than on `GameState`, and here beside `meat` for the same reason: a habit is the
    /// player's, not one pet's. Putting one Digimon away to raise another must not strand the washes
    /// you banked, and every Digimon in the box makes the same mess out of the same larder of washes.
    ///
    /// Inline default of 0 so an existing save migrates to no washes banked, the same lightweight
    /// migration `meat` relies on — 0 is honest, you wash to earn the first clean.
    var cleanCharges: Int = 0

    /// Handwashing events banked toward the NEXT cleaning charge, `0..<handwashPerCleanCharge`. Kept
    /// so sub-threshold washing is not thrown away between refreshes when a charge costs more than one
    /// event — the same remainder `GameState.battleChargeSteps` keeps for steps. Default 0, migrated
    /// like `cleanCharges`.
    var handwashProgress: Double = 0

    /// The map the player's steps are accruing to, or nil for "nowhere chosen yet".
    ///
    /// Nil is a real state and not a stand-in for the first map: a save that has never opened the
    /// map list has not chosen anywhere to go, the game is fully playable without one (US-120), and
    /// silently defaulting to `01_grassland` would credit steps to a place the player never picked.
    var selectedMapId: String?

    /// Backing store for the per-map step counters. Absent means zero; nothing writes an explicit 0.
    private var recordedStorage: [String: Double]

    /// Backing store for the finish stamps. A map is finished if and only if it has one, and since
    /// US-203 a finish means its BOSS was beaten — not merely that the step counter crossed the total.
    /// This doubles as the "already fired" marker that keeps the boss gate from re-raising once the
    /// map is truly done (`checkForBossEncounter` skips a map that already carries a stamp).
    private var finishedAtStorage: [String: Date]

    /// Backing store for `ownedDigitamaIds`. An array because that is what SwiftData stores
    /// directly; the set is the shape every caller wants and `record(ownedDigitama:)` keeps it
    /// duplicate-free.
    private var ownedDigitamaStorage: [String]

    /// Backing store for the per-map wild-encounter markers (US-201): id -> the recorded-step total
    /// at the moment that map's last encounter resolved. Absent means zero — the first encounter is
    /// owed 500 steps from a standing start.
    ///
    /// Inline `[:]` default so an existing save migrates without a hand-written migration, the same
    /// lightweight move `meat` relies on: a save written before wild battles existed simply has no
    /// markers, which reads as "never met anything, first encounter is one walk away".
    private var encounterMarkerStorage: [String: Double] = [:]

    /// Backing store for the per-map "met" sets (US-201/US-202): id -> the roster ids of the map's
    /// residents the player has met (fought a wild encounter with, and won). An array because that is
    /// what SwiftData stores; `recordMet(_:forMap:)` keeps it duplicate-free. Migrated like the marker
    /// store — an old save has met nobody, which is the honest starting point.
    private var metStorage: [String: [String]] = [:]

    /// Backing store for the per-map wild-battle NOTIFICATION markers (US-205): id -> the
    /// `encounterMarker` value a background nudge was last raised against. Distinct from
    /// `encounterMarkerStorage` on purpose — that one moves when an encounter RESOLVES, this one only
    /// records that a crossing was already notified, so one threshold crossing raises at most one
    /// background notification even across process death (a background wake that finds the same
    /// marker already stamped stays silent). Absent means "never notified", so the first crossing
    /// nudges.
    ///
    /// Inline `[:]` default so an existing save migrates without a hand-written migration, the same
    /// lightweight move `encounterMarkerStorage` relies on.
    private var wildBattleNotifiedMarkerStorage: [String: Double] = [:]

    init(
        lifetimeEnergy: EnergyTotals = .zero,
        meat: Int = 0,
        cleanCharges: Int = 0,
        handwashProgress: Double = 0,
        selectedMapId: String? = nil,
        recorded: [String: Double] = [:],
        finishedAt: [String: Date] = [:],
        ownedDigitamaIds: Set<String> = [],
        encounterMarkers: [String: Double] = [:],
        met: [String: [String]] = [:],
        wildBattleNotifiedMarkers: [String: Double] = [:]
    ) {
        self.lifetimeEnergy = lifetimeEnergy
        self.meat = meat
        self.cleanCharges = cleanCharges
        self.handwashProgress = handwashProgress
        self.selectedMapId = selectedMapId
        self.recordedStorage = recorded
        self.finishedAtStorage = finishedAt
        self.ownedDigitamaStorage = ownedDigitamaIds.sorted()
        self.encounterMarkerStorage = encounterMarkers
        self.metStorage = met
        self.wildBattleNotifiedMarkerStorage = wildBattleNotifiedMarkers
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

    /// Takes `steps` off a map's counter, flooring at zero (US-201).
    ///
    /// The one place a map's progress goes DOWN: fleeing a wild encounter, or losing one, costs the
    /// map 500 steps, and losing its boss costs 1,000 (US-203). Floored so a penalty against a barely
    /// walked map cannot push the counter negative — the worst a loss can do is send the player back
    /// to the start of the map, not into debt. A no-op for a non-positive amount, matching `record`.
    func reduceRecorded(steps: Double, forMap id: String) {
        guard steps > 0 else { return }
        recordedStorage[id] = max(0, recorded(forMap: id) - steps)
    }

    /// Stamps a map TRULY finished — its boss beaten (US-203) — once. A second call is ignored, so the
    /// stamp is the moment the boss first fell rather than the last time anything looked. This stamp is
    /// what `MapListView.isUnlocked` reads to open the next map, so nothing but a boss win reaches it.
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
        encounterMarkerStorage = [:]
        metStorage = [:]
        wildBattleNotifiedMarkerStorage = [:]
    }
    #endif
}

// MARK: - Wild encounters (US-201)

extension PlayerProfile {
    /// The recorded-step total this map's last wild encounter resolved at (US-201). Zero when the map
    /// has never had one, so the first encounter is owed a full 500 steps from a standing start.
    func encounterMarker(forMap id: String) -> Double {
        encounterMarkerStorage[id] ?? 0
    }

    /// Moves this map's encounter marker to `steps` — always the map's recorded total at the moment an
    /// encounter (a flee, a win or a loss) has just resolved, so the next 500 is measured from where
    /// the last one left off rather than from zero.
    func setEncounterMarker(_ steps: Double, forMap id: String) {
        encounterMarkerStorage[id] = steps
    }

    /// The residents of this map the player has met (US-201/US-202): won a wild encounter against, or
    /// surfaced by a 500-step meeting. A copy, so a caller cannot record a meeting by mutating it.
    func metDigimon(forMap id: String) -> Set<String> {
        Set(metStorage[id] ?? [])
    }

    func hasMet(_ digimonId: String, forMap id: String) -> Bool {
        metStorage[id]?.contains(digimonId) ?? false
    }

    /// Records a resident as met on this map. Idempotent — meeting the same wild Digimon twice is one
    /// meeting here — which is what makes it safe to call from every path that surfaces one.
    func recordMet(_ digimonId: String, forMap id: String) {
        var met = metStorage[id] ?? []
        guard !met.contains(digimonId) else { return }
        met.append(digimonId)
        metStorage[id] = met
    }

    /// The `encounterMarker` value this map's last BACKGROUND wild-battle notification was raised
    /// against (US-205), or nil if none ever was. Compared to the current marker to decide whether a
    /// crossing has already been notified — see `MainScreenModel.notifyWildEncounterIfDue`.
    func wildBattleNotifiedMarker(forMap id: String) -> Double? {
        wildBattleNotifiedMarkerStorage[id]
    }

    /// Stamps that a background wild-battle notification has been raised for the crossing measured
    /// from `marker` on this map, so a later background wake before the player acts does not raise a
    /// second one for the same crossing.
    func setWildBattleNotifiedMarker(_ marker: Double, forMap id: String) {
        wildBattleNotifiedMarkerStorage[id] = marker
    }
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

// MARK: - Cleaning charges

extension PlayerProfile {
    /// Converts newly counted handwashing `events` into cleaning charges (US-178).
    ///
    /// `events` is a DELTA — the handwashes this read brought in, already claimed off the shared
    /// `MetricLedger` under `.healthHandwashing` so a day's washes are counted once. Every
    /// `eventsPerCharge` events buys one charge, up to `maxCharges`; the sub-threshold remainder is
    /// banked on `handwashProgress` so a day of single washes still earns when a charge costs more
    /// than one. At the cap the remainder is dropped — holding events toward an uncollectable charge
    /// would hand one out the instant another was spent. Mirrors `GameState.creditBattleCharges`.
    func creditCleanCharges(events: Double, eventsPerCharge: Int, maxCharges: Int) {
        guard events > 0, eventsPerCharge > 0 else { return }
        var progress = handwashProgress + events
        let threshold = Double(eventsPerCharge)
        while cleanCharges < maxCharges && progress >= threshold {
            progress -= threshold
            cleanCharges += 1
        }
        handwashProgress = cleanCharges < maxCharges ? progress : 0
    }

    /// Spends one cleaning charge, returning whether there was one to spend.
    ///
    /// The one place a charge leaves the larder, so `MainScreenModel.clean` can ask "did this cost a
    /// charge?" without reaching into the count. A no-op at zero — cleaning is unavailable then, which
    /// the caller turns into the "go wash" affordance.
    func spendCleanCharge() -> Bool {
        guard cleanCharges > 0 else { return false }
        cleanCharges -= 1
        return true
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
    /// Reaching `totalSteps` no longer FINISHES the map — since US-203 a map is finished only when its
    /// boss is beaten, and `MainScreenModel.checkForBossEncounter` is what raises that fight once the
    /// counter has crossed the total AND every resident has been met. This still validates `mapId`
    /// against the catalog (a delta for a map the catalog does not know is dropped) but no longer
    /// stamps a finish of its own; the counter is uncapped, so it keeps climbing past the total toward
    /// the boss gate. `now` is kept in the signature for the US-118 call sites though the finish it
    /// used to stamp has moved to the boss.
    @discardableResult
    static func credit(
        steps: Double,
        to profile: PlayerProfile,
        catalog: MapCatalog = .bundled,
        now: Date
    ) -> Double {
        guard steps > 0,
              let mapId = profile.selectedMapId,
              catalog.map(id: mapId) != nil else { return 0 }

        profile.record(steps: steps, forMap: mapId)
        return steps
    }
}
