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

    /// Backing store for the per-map condition counters (US-206): map id -> `MetricTotals.values`,
    /// i.e. metric raw value -> how much of that metric was earned WHILE THIS MAP WAS SELECTED.
    ///
    /// This is what makes a map's Digitama conditions a question about the map rather than about the
    /// player's whole history. Every accumulating `health.*` metric lands here, and so do the three
    /// stage care counters and `care.battleCount` — each credited by the same call that credits the
    /// global one, off the same already-claimed delta, so a step counts once for the day's energy and
    /// once for this map and never twice for either (see `docs/metric-accounting.md`).
    ///
    /// Absent means NEVER CREDITED, and that distinction is load-bearing exactly as it is on
    /// `MetricTotals.known(_:)`: an un-walked map answers `health.steps` with `.unknown`, not with a
    /// zero that would satisfy an `atMost` gate for free.
    ///
    /// Inline `[:]` default so an existing save migrates without a hand-written migration, the same
    /// lightweight move `encounterMarkerStorage` relies on — a save written before this story simply
    /// has no map-scoped progress, which is the honest reading: nothing was ever measured per map.
    private var mapMetricStorage: [String: [String: Double]] = [:]

    /// Backing store for battles WON per map (US-206). Its own dictionary rather than a key in
    /// `mapMetricStorage` because "wins" is not a `ConditionMetric` — it is the numerator of
    /// `care.battleWinRatio`, whose denominator is the `care.battleCount` kept above.
    private var mapBattleWinStorage: [String: Int] = [:]

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
        wildBattleNotifiedMarkers: [String: Double] = [:],
        mapMetrics: [String: MetricTotals] = [:],
        mapBattleWins: [String: Int] = [:]
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
        self.mapMetricStorage = mapMetrics.mapValues(\.values)
        self.mapBattleWinStorage = mapBattleWins
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
        mapMetricStorage = [:]
        mapBattleWinStorage = [:]
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

// MARK: - Map-scoped progress (US-206)

extension PlayerProfile {
    /// Everything earned WHILE THIS MAP WAS SELECTED, as the same `MetricTotals` a `ConditionContext`
    /// reads its `health.*` windows out of.
    ///
    /// A copy, like `recordedByMap`: progress is written by `credit`, never by mutating a read.
    func mapMetrics(forMap id: String) -> MetricTotals {
        MetricTotals(values: mapMetricStorage[id] ?? [:])
    }

    /// Steps walked in this map — AC1's named counter, and simply `health.steps` out of the totals
    /// above.
    ///
    /// NOT `recorded(forMap:)`, and the two are deliberately different numbers: `recorded` is the map's
    /// PROGRESS toward its boss, which a flee or a lost fight takes 500 or 1,000 off (US-201/US-203).
    /// This one only ever goes up, because a lost fight does not un-walk the steps that were walked —
    /// an egg's condition must not be revoked by a battle that had nothing to do with it.
    func stepsWalked(forMap id: String) -> Double {
        mapMetrics(forMap: id)[.healthSteps]
    }

    /// Battles resolved in this map — the denominator of its `care.battleWinRatio`.
    func battlesFought(forMap id: String) -> Int {
        Int(mapMetrics(forMap: id)[.careBattleCount])
    }

    /// Battles WON in this map — AC1's other named counter, and the ratio's numerator.
    func battlesWon(forMap id: String) -> Int {
        mapBattleWinStorage[id] ?? 0
    }

    /// Adds a whole read's worth of deltas to a map's counters.
    ///
    /// `totals` are DELTAS — what `MetricCreditor.credit` just banked off the shared `MetricLedger`,
    /// the very same numbers the stage and lifetime totals were moved by — so this is a second
    /// SPENDER of one claim rather than a second claim. Two spenders of one delta is not double
    /// counting; two claims of one reading is, which is why nothing here reads a day total.
    func credit(_ totals: MetricTotals, forMap id: String) {
        for (metric, amount) in totals.values where amount > 0 {
            credit(rawMetric: metric, amount: amount, forMap: id)
        }
    }

    /// Adds one counter's delta to a map. The `care.*` path: a training session, a refusal, a
    /// disturbance or a resolved battle is worth 1 to the map the player is standing in.
    func credit(_ metric: ConditionMetric, amount: Double = 1, forMap id: String) {
        credit(rawMetric: metric.rawValue, amount: amount, forMap: id)
    }

    /// Records a resolved battle against this map: one fought, and one won if it was won.
    ///
    /// Fought is counted here, at the RESULT, rather than where `GameState.recordBattleStarted` counts
    /// the global one — so that the map's `care.battleCount` and its win count are the same population
    /// and the ratio between them can never exceed 1.
    func recordBattle(won: Bool, forMap id: String) {
        credit(.careBattleCount, forMap: id)
        if won { mapBattleWinStorage[id] = battlesWon(forMap: id) + 1 }
    }

    /// The one writer. Never writes a non-positive amount, which is what keeps "absent means never
    /// credited" true — see `mapMetricStorage`.
    private func credit(rawMetric: String, amount: Double, forMap id: String) {
        guard amount > 0 else { return }
        var totals = mapMetricStorage[id] ?? [:]
        totals[rawMetric] = (totals[rawMetric] ?? 0) + amount
        mapMetricStorage[id] = totals
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
