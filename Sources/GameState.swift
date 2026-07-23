import Foundation
import SwiftData

/// One of the four energy types, each earned from a different HealthKit metric.
///
/// Raw values are the persisted spelling, so renaming a case rewrites saved games — change
/// `displayName` instead if the wording needs to shift.
enum EnergyType: String, Codable, CaseIterable {
    /// Steps.
    case strength
    /// Active calories.
    case vitality
    /// Sleep.
    case spirit
    /// Exercise minutes.
    case stamina

    /// What the UI calls this. Free to change — unlike `rawValue`, nothing persists it.
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .vitality: return "Vitality"
        case .spirit: return "Spirit"
        case .stamina: return "Stamina"
        }
    }

    /// What labels this type's energy bar: the real-world SOURCE the energy comes from, in short
    /// English. Like `displayName`, nothing persists it — unlike `rawValue`, this is free to change.
    ///
    /// The source and not the type (US-085): "Strength" does not tell a user that walking is what
    /// fills the first bar, and a single glyph told them even less. Four characters at most,
    /// because four of these share a 41mm screen with the Digimon — see `EnergyBarLayout`.
    ///
    /// Sleep is "Zz" and not the five-character "SLEEP" (US-113): it was the one label wide enough
    /// to set `nameWidth` for all four, so the other three paid a column's worth of width for it.
    /// The comic-strip snore is read as sleep without spelling it, and VoiceOver is handed
    /// `displayName` ("Spirit") rather than this, so nothing is spoken as "Zz".
    var shortName: String {
        switch self {
        case .strength: return "STEP"
        case .vitality: return "KCAL"
        case .spirit: return "Zz"
        case .stamina: return "EXER"
        }
    }
}

/// A Digimon's stage of life.
///
/// The raw value is the sprite subfolder name on disk, so a stage names the folder its art
/// lives in: `DigimonSpriteView(stage: state.stage.rawValue, name: ...)` needs no mapping table.
enum Stage: String, Codable, CaseIterable {
    case digitama = "Digitama"
    case babyI = "Baby I"
    case babyII = "Baby II"
    case child = "Child"
    case adult = "Adult"
    case perfect = "Perfect"
    case ultimate = "Ultimate-Super Ultimate"
    /// A side branch, not a rung on the ladder — hence no `ladderIndex`.
    case armorHybrid = "Armor-Hybrid"

    /// What the UI calls this stage. Free to change — unlike `rawValue`, nothing persists it.
    ///
    /// It differs from `rawValue` only where the folder name is not a stage name: the art for the
    /// final stage is filed under "Ultimate-Super Ultimate" because that one folder holds both,
    /// but the stage a Digimon reaches is the PRD's sixth rung, Ultimate.
    var displayName: String {
        switch self {
        case .ultimate: return "Ultimate"
        default: return rawValue
        }
    }

    /// Position on the linear Digitama -> Ultimate ladder, or nil for stages off it.
    ///
    /// Nil is why this is not just `allCases.firstIndex(of:)`: Armor-Hybrid has no rung, so a
    /// skip check must treat it as "unknown", not as the rung after Ultimate.
    var ladderIndex: Int? {
        switch self {
        case .digitama: return 0
        case .babyI: return 1
        case .babyII: return 2
        case .child: return 3
        case .adult: return 4
        case .perfect: return 5
        case .ultimate: return 6
        case .armorHybrid: return nil
        }
    }
}

/// Whether the Digimon is being cared for well enough.
enum HealthStatus: String, Codable, CaseIterable {
    case healthy
    case sick
    case dead
}

/// A running total per energy type.
///
/// A struct rather than four loose Ints so the same shape serves both the per-stage total and
/// the lifetime total, and so callers can address a total by `EnergyType` without a switch.
struct EnergyTotals: Codable, Equatable {
    var strength: Int = 0
    var vitality: Int = 0
    var spirit: Int = 0
    var stamina: Int = 0

    static let zero = EnergyTotals()

    subscript(type: EnergyType) -> Int {
        get {
            switch type {
            case .strength: return strength
            case .vitality: return vitality
            case .spirit: return spirit
            case .stamina: return stamina
            }
        }
        set {
            switch type {
            case .strength: strength = newValue
            case .vitality: vitality = newValue
            case .spirit: spirit = newValue
            case .stamina: stamina = newValue
            }
        }
    }

    /// Summed across all four types.
    var total: Int { strength + vitality + spirit + stamina }
}

/// When each energy type last went up, or nil for one that never has.
///
/// Exists only to break a tie for `dominantEnergyType`. Dates rather than a counter because the
/// clock is already injected everywhere energy is earned, so a test can order two increments
/// without waiting real time.
struct EnergyRecency: Codable, Equatable {
    var strength: Date?
    var vitality: Date?
    var spirit: Date?
    var stamina: Date?

    static let never = EnergyRecency()

    subscript(type: EnergyType) -> Date? {
        get {
            switch type {
            case .strength: return strength
            case .vitality: return vitality
            case .spirit: return spirit
            case .stamina: return stamina
            }
        }
        set {
            switch type {
            case .strength: strength = newValue
            case .vitality: vitality = newValue
            case .spirit: spirit = newValue
            case .stamina: stamina = newValue
            }
        }
    }
}

/// The saved game: one record, holding everything about the Digimon currently being raised.
///
/// Time-based state (hunger, care mistakes, sickness, death) is stored as the timestamps it is
/// derived from rather than as ticked-forward counters, so it stays correct after the app has
/// been closed for days.
@Model
final class GameState {
    /// Node id in the evolution graph — not the sprite filename, which the graph resolves.
    var currentDigimonId: String
    var stage: Stage
    /// Energy earned since this stage began. Reset on evolution; decides the branch taken.
    var stageEnergy: EnergyTotals
    /// LEGACY (US-123): lifetime energy lives on `PlayerProfile` now, because it outlives the
    /// Digimon and — from US-124 — belongs to a player who has several of them. Read it through
    /// `PlayerProfile.lifetimeEnergy`; the only thing that may touch this is the migration, through
    /// `legacyLifetimeEnergy`.
    ///
    /// **The column stays, under its original name, and that is deliberate.** Deleting the property
    /// would delete the column with a live player's earnings still in it, and there is no second
    /// chance to read them. Renaming it would be no better: SwiftData FLATTENS a composite like
    /// `EnergyTotals` into one column per field, named by position (`ZSTRENGTH1`, `ZSTRENGTH2`, ...)
    /// rather than by property — verified by opening a store written by the previous build — so a
    /// rename is a schema change that has to be got exactly right for a value nothing is allowed to
    /// lose. Keeping it costs four unread columns.
    private var lifetimeEnergy: EnergyTotals
    /// Backing store for `energyLastEarned`, and the reason it is optional: this property was
    /// added to an already-shipped model, and an OPTIONAL attribute is the one shape SwiftData
    /// will migrate into an existing store without a default. A non-optional composite is not —
    /// it opens, then fails validation on the next save with "energyLastEarned is a required
    /// value", because the macro's default never reaches the store. `nil` means "written before
    /// this existed", which is exactly what `.never` means, so nothing is lost by folding them
    /// together.
    private var energyLastEarnedStorage: EnergyRecency?
    var birthDate: Date
    var stageEnteredDate: Date
    var careMistakeCount: Int
    /// Units of hunger, 0...`HungerClock.maximumHunger`. Grown by elapsed time, never by a tick —
    /// `hungerUpdatedAt` is what it is derived from.
    var hunger: Int
    /// The instant `hunger` was last brought up to date. Optional for the same migration reason as
    /// `energyLastEarnedStorage`: it was added to an already-shipped model, and an optional
    /// attribute is the one shape SwiftData migrates into an existing store without a default.
    /// `nil` means "saved before hunger was tracked", which `HungerClock.advance` reads as "start
    /// the clock now".
    var hungerUpdatedAt: Date?
    /// Backing store for `refusalCount`/`refusalDay`: how many feeds have been turned down, and the
    /// local day they were counted against. Optional for the same migration reason as
    /// `energyLastEarnedStorage` — an optional attribute is the one shape SwiftData migrates into an
    /// already-shipped store without a default. Both `nil` reads as "no refusals yet".
    ///
    /// A DAY is kept alongside the count because the count is only ever asked about per-day:
    /// US-027's care mistake is "3+ refusals in a day", not three refusals ever.
    private var refusalCountStorage: Int?
    private var refusalDayStorage: Date?
    /// Backing store for `battleCount`/`battleDay` (US-032): how many battles have been fought, and
    /// the local day they were counted against. Optional for the same migration reason as every
    /// other storage property here — an optional attribute is the one shape SwiftData migrates into
    /// an already-shipped store without a default. Both `nil` reads as "no battles yet today".
    ///
    /// Shaped exactly like `refusalCount`/`refusalDay`, and for the same reason: the count is only
    /// ever asked about per-day, because the cap is five battles A DAY and a lifetime counter would
    /// permanently retire a Digimon that fought five times last month.
    private var battleCountStorage: Int?
    private var battleDayStorage: Date?
    /// Backing store for `battleCharges`/`battleChargeSteps` (US-176): the spendable battle charges
    /// this Digimon has banked from walking, and the steps walked toward the next one. Per-Digimon —
    /// "battle time is stored in the specific Digimon" — so switching which Digimon is out shows its
    /// own count, never another's. Both optional for the same migration reason as every other storage
    /// property here: an optional attribute is the one shape SwiftData migrates into an
    /// already-shipped store without a default. Both `nil` reads as "nothing banked yet".
    private var battleChargesStorage: Int?
    private var battleChargeStepsStorage: Double?
    /// Backing store for `trainCharges`/`trainChargeKcal` (US-177): the spendable training charges
    /// this Digimon has banked from active calories, and the kcal burned toward the next one.
    /// Per-Digimon in the same sense and for the same reason as `battleChargesStorage` — switching
    /// which Digimon is out shows its own count, never another's. Both optional for the same
    /// migration reason as every other storage property here: an optional attribute is the one shape
    /// SwiftData migrates into an already-shipped store without a default. Both `nil` reads as
    /// "nothing banked yet".
    private var trainChargesStorage: Int?
    private var trainChargeKcalStorage: Double?
    /// Backing store for the four care-mistake markers (US-027). All optional for the same migration
    /// reason as `energyLastEarnedStorage` — an optional attribute is the one shape SwiftData
    /// migrates into an already-shipped store without a default.
    ///
    /// These are MARKERS, not counters: `careMistakeCount` is the counter, and each of these records
    /// how much of the elapsed time or of the day has already been charged against it, so an audit
    /// that runs on every foregrounding never charges the same neglect twice.
    private var healthDataLastSeenStorage: Date?
    private var starvationMistakesChargedStorage: Int?
    private var refusalMistakeDayStorage: Date?
    private var wakeMistakeDayStorage: Date?
    /// Backing store for `awakeUntil` (US-110): when the grace period a prodded Digimon was woken
    /// for runs out, or nil while it has not been woken. Optional for the same migration reason as
    /// every other storage property here, and also because "never woken" is a real state no default
    /// could express.
    ///
    /// SAVED rather than held on the model, which is the whole reason it lives here: a user who
    /// force-quits ten seconds into the five minutes they were charged a care mistake for must not
    /// come back to a Digimon that is asleep again.
    private var awakeUntilStorage: Date?
    /// Backing store for the two death markers (US-029): when the current illness began, and when it
    /// finally killed the Digimon. Optional for the same migration reason as every other storage
    /// property here — an optional attribute is the one shape SwiftData migrates into an
    /// already-shipped store without a default — and also because both are genuinely absent on a
    /// Digimon that is well, which no default could express.
    private var sickSinceStorage: Date?
    private var diedAtStorage: Date?
    /// Backing store for `deathWarningSentAt` (US-035): when the 24-hours-left warning was decided
    /// for the CURRENT illness, or nil while it has not been. Optional for the same migration reason
    /// as every other storage property here.
    ///
    /// Saved rather than held in memory because the warning is due at a moment nobody is watching:
    /// it falls 48 hours into an illness, and the refresh that notices is as likely to be a
    /// background wake as a foregrounding. An in-memory flag would be lost on the next launch and
    /// the user would be warned their Digimon is dying a second time.
    private var deathWarningSentStorage: Date?
    /// Backing store for `poopCount`/`poopUpdatedAt` (US-051): how many poops are on screen, and the
    /// instant that count was last brought up to date. Optional for the same migration reason as
    /// every other storage property here — an optional attribute is the one shape SwiftData migrates
    /// into an already-shipped store without a default. See `PoopClock` for the accrual rule and
    /// `Poop.swift` for the computed accessors.
    private var poopCountStorage: Int?
    private var poopUpdatedAtStorage: Date?
    /// Backing store for `poopMistakesCharged` (US-053). A MARKER in the same sense as
    /// `starvationMistakesChargedStorage`, and optional for the same migration reason.
    private var poopMistakesChargedStorage: Int?
    /// Backing store for `poopNotified` (US-054): whether the CURRENT full screen of mess has
    /// already been notified about. Optional for the same migration reason as every other storage
    /// property here.
    ///
    /// Saved rather than held in memory for the same reason as `deathWarningSentStorage`: the
    /// screen fills at a moment nobody is watching, and an in-memory flag would be lost on the next
    /// launch — so every launch onto a full screen would notify again. See
    /// `claimPoopNotification`.
    private var poopNotifiedStorage: Bool?
    /// Backing stores for the three per-metric totals (US-058), the ones a `window:` condition is
    /// compared against. Optional for the same migration reason as every other storage property
    /// here, and a plain `[String: Double]` rather than a `MetricTotals` composite because that is
    /// the shape SwiftData stores directly; `MetricTotals` is the value-type convenience on top.
    ///
    /// Three and not two, because `ConditionWindow` has three cases and `day` cannot be derived
    /// from the other two: a stage total says nothing about which single day was the best one.
    private var stageMetricTotalsStorage: [String: Double]?
    private var lifetimeMetricTotalsStorage: [String: Double]?
    private var stageBestDayMetricsStorage: [String: Double]?
    /// Backing stores for the three stage-scoped care counters (US-084), the ones the `care.*`
    /// conditions other than `careBattleCount`/`careBattleWinRatio` are compared against. Optional
    /// for the same migration reason as every other storage property here.
    ///
    /// Stage-scoped and cumulative, which is what makes them worth keeping at all — none of the
    /// three could be answered by a counter that already exists. `refusalCount` resets at local
    /// midnight, so it can never express "3+ overfeeds this stage"; `wakeMistakeDay` is a marker
    /// saying whether a night was disturbed, not how many times; and `strengthStat` is the REWARD
    /// training paid out, which US-075's graded gain is about to make a bad proxy for how often the
    /// user actually trained.
    private var stageTrainingSessionsStorage: Int?
    private var stageOverfeedsStorage: Int?
    private var stageSleepDisturbancesStorage: Int?
    /// Backing stores for the room light (US-098): which of the three states it is in, when it was
    /// last changed, and the two once-a-night markers. All optional for the same migration reason as
    /// every other storage property here — an optional attribute is the one shape SwiftData migrates
    /// into an already-shipped store without a default, and a non-optional one opens and then fails
    /// the next save with "is a required value" because the macro's default never reaches the store.
    ///
    /// `nil` for the state reads as `.on`, which is both what a new game starts in and the honest
    /// reading of a save written before the light existed: nobody had ever turned it off.
    private var lightStateStorage: LightState?
    private var lightStateChangedAtStorage: Date?
    private var lightAuditedNightStorage: Date?
    private var lightNotifiedNightStorage: Date?
    /// Backing store for `isActive` (US-124): whether this is the Digimon the player currently has
    /// out. Optional for the same migration reason as every other storage property here — an
    /// optional attribute is the one shape SwiftData migrates into an already-shipped store without
    /// a default.
    ///
    /// `nil` reads as ACTIVE, and that is the safe direction rather than a convenience: a store
    /// written before the box existed holds exactly ONE Digimon, so the only record that can carry
    /// a `nil` here is the one the player is raising. Reading it as frozen would hand them a fresh
    /// egg and leave their Digimon invisible in a store nothing looks at. The migration in
    /// `GameStore.loadOrCreateProfile` stamps it `true` on disk as well, so the default is a
    /// backstop and not the mechanism — it still matters, because a player who ran the US-123 build
    /// already has a profile and so never re-enters that migration.
    private var isActiveStorage: Bool?
    /// Backing stores for the freeze clock (US-125): when this Digimon was put away, and how long it
    /// has spent in the box across every spell it has ever had there. Optional for the same migration
    /// reason as every other storage property here.
    ///
    /// `frozenSinceStorage` is non-nil exactly while `isActive` is false — `GameStore.activate` is
    /// what keeps the two in step, because it is the only thing that may move either.
    ///
    /// `frozenDurationStorage` is a `Double` and not a `TimeInterval` only because that is the
    /// spelling SwiftData stores; they are the same type. It is a RECORD rather than a mechanism —
    /// `thaw(at:)` translates the timeline forward as it accrues here, so nothing has to consult it
    /// to read a frozen Digimon correctly. What it buys is the one question the translation destroys:
    /// `birthDate - frozenDuration` is the wall-clock instant the Digimon was really born.
    private var frozenSinceStorage: Date?
    private var frozenDurationStorage: Double?
    /// Backing store for `originDigitamaId` (US-127): the id of the Digitama this Digimon hatched
    /// from, carried UNCHANGED through every evolution so the "one of each egg" rule survives a
    /// Digimon evolving six times — `advance` moves `currentDigimonId` but never touches this.
    ///
    /// Optional for the same migration reason as every other storage property here — an optional
    /// attribute is the one shape SwiftData migrates into an already-shipped store without a default.
    /// A `nil` means "written before origins were tracked" and is BACKFILLED once, by
    /// `GameStore.loadOrCreateProfile` tracing `currentDigimonId` up the graph to its Digitama root;
    /// the computed accessor's `?? currentDigimonId` fallback is only the reading between opening
    /// such a store and that backfill running, and is correct for a record still at `.digitama`.
    private var originDigitamaStorage: String?
    var strengthStat: Int
    var healthStatus: HealthStatus
    var battleWins: Int
    var battleLosses: Int

    /// A brand new Digimon: an unhatched egg with nothing accumulated yet.
    ///
    /// Every other field is `var`, so a test or a migration can set them individually rather
    /// than needing a twelve-argument initializer.
    ///
    /// - Parameter isActive: whether this Digimon is the one out. Defaults to true, because every
    ///   path that exists today — a first launch, a reset, a rebirth — creates the Digimon the
    ///   player is about to raise. US-126's box, which adds a Digimon the player is NOT switching
    ///   to, is the caller that passes false.
    /// - Parameter originDigitamaId: the egg this Digimon hatched from (US-127). Defaults to
    ///   `currentDigimonId`, because every path that exists today is born AS a Digitama and is its
    ///   own origin. The caller that passes something else is US-132's Jogress, whose result is born
    ///   at a later stage and inherits one of its parents' origins.
    init(currentDigimonId: String, stage: Stage = .digitama, isActive: Bool = true,
         originDigitamaId: String? = nil, now: Date) {
        self.currentDigimonId = currentDigimonId
        self.stage = stage
        self.stageEnergy = .zero
        self.lifetimeEnergy = .zero
        self.energyLastEarnedStorage = .never
        self.birthDate = now
        self.stageEnteredDate = now
        self.careMistakeCount = 0
        self.hunger = 0
        self.hungerUpdatedAt = now
        self.refusalCountStorage = 0
        self.refusalDayStorage = nil
        self.battleCountStorage = 0
        self.battleDayStorage = nil
        self.battleChargesStorage = 0
        self.battleChargeStepsStorage = 0
        self.trainChargesStorage = 0
        self.trainChargeKcalStorage = 0
        // Stamped with `now` rather than left nil, or a brand new game would be charged for every
        // day between the epoch and today the first time the audit ran.
        self.healthDataLastSeenStorage = now
        self.starvationMistakesChargedStorage = 0
        self.refusalMistakeDayStorage = nil
        self.wakeMistakeDayStorage = nil
        self.awakeUntilStorage = nil
        self.sickSinceStorage = nil
        self.diedAtStorage = nil
        self.deathWarningSentStorage = nil
        self.poopCountStorage = 0
        // Stamped with `now` rather than left nil, so a brand new game's poop clock starts at the
        // hatch instead of at whichever refresh happens to look first.
        self.poopUpdatedAtStorage = now
        self.poopMistakesChargedStorage = 0
        self.poopNotifiedStorage = false
        self.stageMetricTotalsStorage = [:]
        self.lifetimeMetricTotalsStorage = [:]
        self.stageBestDayMetricsStorage = [:]
        self.stageTrainingSessionsStorage = 0
        self.stageOverfeedsStorage = 0
        self.stageSleepDisturbancesStorage = 0
        self.lightStateStorage = .on
        // Stamped with `now` rather than left nil, so the light has been on since the egg was laid
        // and `LightsOutRule` has a real timestamp to read on the very first night.
        self.lightStateChangedAtStorage = now
        self.lightAuditedNightStorage = nil
        self.lightNotifiedNightStorage = nil
        self.isActiveStorage = isActive
        // Born frozen means frozen since birth (US-125). Without this stamp a Digimon added to the
        // box by US-126 would have no instant to measure its first spell from, so the day it was
        // finally taken out it would be handed every hour it had spent waiting.
        self.frozenSinceStorage = isActive ? nil : now
        self.frozenDurationStorage = 0
        self.originDigitamaStorage = originDigitamaId ?? currentDigimonId
        self.strengthStat = 0
        self.healthStatus = .healthy
        self.battleWins = 0
        self.battleLosses = 0
    }
}

extension GameState {
    /// What a pre-US-123 store left on this Digimon, for `GameStore.loadOrCreateProfile` to copy
    /// onto a brand new `PlayerProfile` — and for nothing else.
    ///
    /// Read-only, and named so that a reader who wants "the player's lifetime energy" cannot reach
    /// it by accident and cannot be in any doubt when they read it deliberately. The value goes
    /// stale the moment the profile takes over; the profile is the answer from then on.
    var legacyLifetimeEnergy: EnergyTotals {
        lifetimeEnergy
    }

    /// When each type of `stageEnergy` last went up. Read only to break a `dominantEnergyType`
    /// tie, and written everywhere `stageEnergy` is — miss one and that increment silently stops
    /// counting as recent.
    ///
    /// Computed, so the optionality that persistence needs stops at the model boundary: a saved
    /// game from before this property existed reads as `.never` rather than as a `nil` every
    /// caller would have to remember to unwrap.
    var energyLastEarned: EnergyRecency {
        get { energyLastEarnedStorage ?? .never }
        set { energyLastEarnedStorage = newValue }
    }

    /// How many feeds have been refused on `refusalDay`.
    ///
    /// Computed for the same reason `energyLastEarned` is: the optionality persistence needs stops
    /// at the model boundary, so a save written before refusals were tracked reads as 0 rather than
    /// as a `nil` every caller has to unwrap.
    var refusalCount: Int {
        get { refusalCountStorage ?? 0 }
        set { refusalCountStorage = newValue }
    }

    /// The local day `refusalCount` is counted against, or nil before the first refusal.
    var refusalDay: Date? {
        get { refusalDayStorage }
        set { refusalDayStorage = newValue }
    }

    /// How many battles have been fought on `battleDay`. Read through
    /// `battlesFought(now:calendar:)`, which is the only form that answers the question anyone
    /// actually asks — this raw count is meaningless without the day it belongs to.
    var battleCount: Int {
        get { battleCountStorage ?? 0 }
        set { battleCountStorage = newValue }
    }

    /// The local day `battleCount` is counted against, or nil before the first battle.
    var battleDay: Date? {
        get { battleDayStorage }
        set { battleDayStorage = newValue }
    }

    /// Spendable battle charges (US-176), 0...`ConsumptionConfig.maxBattleCharges`. Earned from steps
    /// by `creditBattleCharges` and spent one at a time by starting a battle, this is the currency
    /// that gates fighting since US-176 replaced US-032's per-day cap.
    ///
    /// Computed for the same reason `refusalCount` is: the optionality persistence needs stops at the
    /// model boundary, so a save written before charges existed reads as 0 rather than as a `nil`
    /// every caller has to unwrap.
    var battleCharges: Int {
        get { battleChargesStorage ?? 0 }
        set { battleChargesStorage = newValue }
    }

    /// Steps walked toward the NEXT battle charge, `0..<stepsPerBattleCharge`. Kept so sub-threshold
    /// walking is not thrown away between refreshes — 200 steps now and 200 later is a charge, not
    /// two forgotten remainders — because a health reading arrives as many small deltas across a day.
    var battleChargeSteps: Double {
        get { battleChargeStepsStorage ?? 0 }
        set { battleChargeStepsStorage = newValue }
    }

    /// Converts newly walked `steps` into battle charges (US-176).
    ///
    /// `steps` is a DELTA — the steps this read brought in, already claimed off the shared
    /// `MetricLedger` so the map and the charges spend one delta and not two. Every `stepsPerCharge`
    /// steps buys one charge, up to `maxCharges`; the sub-threshold remainder is banked on
    /// `battleChargeSteps` so a day of short walks still earns. At the cap the remainder is dropped —
    /// holding steps toward an uncollectable eleventh charge would hand one out the instant another
    /// was spent.
    func creditBattleCharges(steps: Double, stepsPerCharge: Int, maxCharges: Int) {
        guard steps > 0, stepsPerCharge > 0 else { return }
        var progress = battleChargeSteps + steps
        let threshold = Double(stepsPerCharge)
        while battleCharges < maxCharges && progress >= threshold {
            progress -= threshold
            battleCharges += 1
        }
        battleChargeSteps = battleCharges < maxCharges ? progress : 0
    }

    /// Spendable training charges (US-177), 0...`ConsumptionConfig.maxTrainCharges`. Earned from
    /// active calories by `creditTrainCharges` and spent one at a time by `TrainAction.begin`, this
    /// is the currency that gates training since US-177 replaced the per-session Strength/Stamina
    /// cost.
    ///
    /// Computed for the same reason `battleCharges` is: the optionality persistence needs stops at
    /// the model boundary, so a save written before charges existed reads as 0 rather than as a
    /// `nil` every caller has to unwrap.
    var trainCharges: Int {
        get { trainChargesStorage ?? 0 }
        set { trainChargesStorage = newValue }
    }

    /// Active kilocalories burned toward the NEXT training charge, `0..<kcalPerTrain`. Kept for the
    /// same reason `battleChargeSteps` is: a health reading arrives as many small deltas across a
    /// day, so 30 kcal now and 30 later is a charge, not two forgotten remainders.
    var trainChargeKcal: Double {
        get { trainChargeKcalStorage ?? 0 }
        set { trainChargeKcalStorage = newValue }
    }

    /// Converts newly burned active `kcal` into training charges (US-177).
    ///
    /// `kcal` is a DELTA — the active calories this read brought in, claimed off the shared
    /// `MetricLedger` so no other consumer of `health.activeEnergy` double-counts it. Every
    /// `kcalPerCharge` kilocalories buys one charge, up to `maxCharges`; the sub-threshold remainder
    /// is banked on `trainChargeKcal` so a day of short efforts still earns. At the cap the remainder
    /// is dropped, exactly as `creditBattleCharges` drops it, and for the same reason.
    func creditTrainCharges(kcal: Double, kcalPerCharge: Int, maxCharges: Int) {
        guard kcal > 0, kcalPerCharge > 0 else { return }
        var progress = trainChargeKcal + kcal
        let threshold = Double(kcalPerCharge)
        while trainCharges < maxCharges && progress >= threshold {
            progress -= threshold
            trainCharges += 1
        }
        trainChargeKcal = trainCharges < maxCharges ? progress : 0
    }

    /// The last instant HealthKit gave a real number for any metric, or nil on a save written
    /// before this was tracked. `CareMistakes` charges a mistake per whole local day between this
    /// and today, and moves it forward by exactly the days it charged.
    var healthDataLastSeen: Date? {
        get { healthDataLastSeenStorage }
        set { healthDataLastSeenStorage = newValue }
    }

    /// How many mistakes the CURRENT starving spell has already been charged. Reset to zero the
    /// moment hunger drops off the maximum, so a fed-then-starved-again Digimon starts over.
    var starvationMistakesCharged: Int {
        get { starvationMistakesChargedStorage ?? 0 }
        set { starvationMistakesChargedStorage = newValue }
    }

    /// The local day an overfeeding mistake was last charged for, or nil if never. Distinct from
    /// `refusalDay`, which counts the refusals themselves — this one caps the MISTAKE at one a day
    /// however many refusals follow the third.
    var refusalMistakeDay: Date? {
        get { refusalMistakeDayStorage }
        set { refusalMistakeDayStorage = newValue }
    }

    /// The local day a waking-early mistake was last charged for, or nil if never. One a day for the
    /// same reason as `refusalMistakeDay`: prodding a sleeping Digimon six times is one bad night,
    /// not six.
    var wakeMistakeDay: Date? {
        get { wakeMistakeDayStorage }
        set { wakeMistakeDayStorage = newValue }
    }

    /// When the wake a disturbed Digimon is currently enjoying runs out, or nil if it has never been
    /// woken (US-110).
    ///
    /// Set to `now + SleepSchedule.wakeGracePeriod` by the model when a sleeping Digimon is prodded
    /// into feeding, training or battling, and read back by `SleepSchedule.isAsleep(at:wokenUntil:)`
    /// — which is the ONE place it overrides the window, so the every-refresh re-derivation cannot
    /// undo the wake.
    ///
    /// Never cleared on a schedule, and it does not need to be: it is an absolute instant, so once
    /// it is past it reads as expired forever and cannot leak into the next night.
    var awakeUntil: Date? {
        get { awakeUntilStorage }
        set { awakeUntilStorage = newValue }
    }

    /// When the CURRENT illness began, or nil while the Digimon is well. `Death.updateDeath` owns
    /// it: stamped by the refresh that first saw the Digimon sick, cleared by the cure, and left
    /// standing after death as the record of what killed it.
    var sickSince: Date? {
        get { sickSinceStorage }
        set { sickSinceStorage = newValue }
    }

    /// When the Digimon died, or nil while it lives. Stored rather than derived, so a memorial reads
    /// the same however long it sits on screen before it is dismissed.
    var diedAt: Date? {
        get { diedAtStorage }
        set { diedAtStorage = newValue }
    }

    /// When the 24-hours-left warning was decided for the current illness, or nil while it has not
    /// been. `Death.settleDeathWarning` owns it, and clears it with the cure so the NEXT illness
    /// gets its own warning rather than inheriting a spent one.
    var deathWarningSentAt: Date? {
        get { deathWarningSentStorage }
        set { deathWarningSentStorage = newValue }
    }

    /// How many poops are on screen, 0...`PoopClock.maximumPoops`. Grown by elapsed time, never by a
    /// tick — `poopUpdatedAt` is what it is derived from, and `advancePoop(isAsleep:now:)` is what
    /// derives it. See `PoopClock` for the rule.
    ///
    /// Computed for the same reason `refusalCount` is: the optionality persistence needs stops at
    /// the model boundary, so a save written before poop was tracked reads as 0 rather than as a
    /// `nil` every caller has to unwrap.
    var poopCount: Int {
        get { poopCountStorage ?? 0 }
        set { poopCountStorage = newValue }
    }

    /// The instant `poopCount` was last brought up to date, or nil on a save written before poop was
    /// tracked, which `PoopClock.advance` reads as "start the clock now".
    var poopUpdatedAt: Date? {
        get { poopUpdatedAtStorage }
        set { poopUpdatedAtStorage = newValue }
    }

    /// How many mistakes the CURRENT full screen of poop has already been charged. Reset to zero the
    /// moment the count drops off the ceiling — which cleaning is what does — so a screen cleaned and
    /// left to fill again starts over rather than being charged instantly.
    var poopMistakesCharged: Int {
        get { poopMistakesChargedStorage ?? 0 }
        set { poopMistakesChargedStorage = newValue }
    }

    /// Whether the CURRENT full screen of mess has already been notified about. Re-armed by
    /// `claimPoopNotification` the moment the count drops off the ceiling, on the same rule as
    /// `poopMistakesCharged`.
    var poopNotified: Bool {
        get { poopNotifiedStorage ?? false }
        set { poopNotifiedStorage = newValue }
    }

    /// Whether this is the Digimon the player has out (US-124). Exactly one saved `GameState` is
    /// active at a time; every other one is frozen in the box.
    ///
    /// Read it, but do not WRITE it directly outside `GameStore`: the invariant is a property of
    /// the whole store rather than of one record, so flipping one on leaves two active unless the
    /// other is flipped off in the same transaction. `GameStore.activate(_:)` is the only thing
    /// that can promise that, and it is why this is not simply a stored property callers set.
    ///
    /// Computed for the same reason `energyLastEarned` is: the optionality persistence needs stops
    /// at the model boundary. See `isActiveStorage` for why `nil` reads as active.
    var isActive: Bool {
        get { isActiveStorage ?? true }
        set { isActiveStorage = newValue }
    }

    /// When this Digimon was put away, or nil while it is the one out (US-125). See `Freeze.swift`
    /// for what it is measured for, and `GameStore.activate(_:now:)` — the only thing that may move
    /// it — for why it is not written anywhere else.
    var frozenSince: Date? {
        get { frozenSinceStorage }
        set { frozenSinceStorage = newValue }
    }

    /// How long this Digimon has spent in the box, summed over every spell there.
    ///
    /// Computed for the same reason `energyLastEarned` is: the optionality persistence needs stops
    /// at the model boundary, so a save written before the box existed reads as "never frozen"
    /// rather than as a `nil` every caller has to unwrap.
    var frozenDuration: TimeInterval {
        get { frozenDurationStorage ?? 0 }
        set { frozenDurationStorage = newValue }
    }

    /// The Digitama this Digimon hatched from (US-127), unchanged across every evolution.
    ///
    /// This is what makes "one of each egg, ever, until it dies" survive six digivolutions: the
    /// held set (see `GameStore.heldDigitamaIds`) is read off this and not off `currentDigimonId`,
    /// which has long since moved on. See `originDigitamaStorage` for why `nil` reads as the current
    /// id — it is a transient reading before the one-time backfill, right for a `.digitama` record.
    var originDigitamaId: String {
        get { originDigitamaStorage ?? currentDigimonId }
        set { originDigitamaStorage = newValue }
    }

    /// Whether `originDigitamaId` has ever been written, as opposed to falling back to the current
    /// id. `GameStore` uses this to backfill exactly the records a pre-US-127 store left `nil`,
    /// touching no record that already knows its origin.
    var hasStoredOrigin: Bool { originDigitamaStorage != nil }

    /// Whether this Digimon has died. A dead Digimon releases its origin Digitama (US-127), so the
    /// held set is derived from the LIVING records only.
    var isDead: Bool { healthStatus == .dead }

    /// Each metric's total since this stage began — what a `window: .stage` condition is compared
    /// against. Cleared by `enterStage(at:)`, exactly as `stageEnergy` is.
    ///
    /// Computed for the same reason `energyLastEarned` is: the optionality persistence needs stops
    /// at the model boundary, so a save written before metric totals existed reads as empty rather
    /// than as a `nil` every caller has to unwrap.
    var stageMetricTotals: MetricTotals {
        get { MetricTotals(values: stageMetricTotalsStorage ?? [:]) }
        set { stageMetricTotalsStorage = newValue.values }
    }

    /// Each metric's total over the Digimon's whole life — a `window: .lifetime` condition. Never
    /// reset; `enterStage(at:)` deliberately leaves it standing.
    var lifetimeMetricTotals: MetricTotals {
        get { MetricTotals(values: lifetimeMetricTotalsStorage ?? [:]) }
        set { lifetimeMetricTotalsStorage = newValue.values }
    }

    /// Each metric's BEST single local day this stage — what a `window: .day` condition is compared
    /// against.
    ///
    /// The best day and not the current one, because a criterion like "walk 10,000 steps in a day"
    /// is a thing you achieved, not a thing you must be achieving at the instant the evolution
    /// check happens to run. Against today's number, one good Tuesday would stop counting at
    /// Tuesday midnight and the user would be told to do it again — and, worse, whether it counted
    /// would depend on what time of day the app was opened.
    ///
    /// Stage-scoped, and so cleared by `enterStage(at:)` alongside `stageMetricTotals`: a
    /// `window: .day` condition sits on an evolution edge, and edges ask what you did to earn THIS
    /// evolution. A best day carried across evolutions would let one Tuesday buy every branch that
    /// asks for a good day, forever.
    var stageBestDayMetrics: MetricTotals {
        get { MetricTotals(values: stageBestDayMetricsStorage ?? [:]) }
        set { stageBestDayMetricsStorage = newValue.values }
    }

    /// How many training sessions have been run this stage — `care.trainingSessions`.
    ///
    /// Counted per SESSION and never per outcome. Digital Monster Color's branches ask how much you
    /// trained, not how well: a session that missed every prompt is still a session, and the bands
    /// US-061 authors ("8–31 trains the good branch, 32+ overtrains into the junk one") only mean
    /// what they say if a miss costs the same as a hit. US-075's graded gain steers `strengthStat`;
    /// it must never be the thing evolution reads.
    ///
    /// Computed for the same reason `refusalCount` is: the optionality persistence needs stops at
    /// the model boundary.
    var stageTrainingSessions: Int {
        get { stageTrainingSessionsStorage ?? 0 }
        set { stageTrainingSessionsStorage = newValue }
    }

    /// How many feeds have been refused this stage — `care.overfeeds`.
    ///
    /// Distinct from `refusalCount`, which is TODAY's and rolls over at local midnight. Both count
    /// the same event and neither can be derived from the other: a stage-long gate cannot be read
    /// off a daily count, and the daily care mistake cannot be read off a stage-long one.
    var stageOverfeeds: Int {
        get { stageOverfeedsStorage ?? 0 }
        set { stageOverfeedsStorage = newValue }
    }

    /// How many times the Digimon has been disturbed in its sleep window this stage —
    /// `care.sleepDisturbances`.
    ///
    /// Every disturbance, not one a night. `wakeMistakeDay` caps the MISTAKE at one a day, because
    /// six prods is one bad night's care; this counter is the other question — how often it
    /// happened at all — and a marker cannot answer it.
    var stageSleepDisturbances: Int {
        get { stageSleepDisturbancesStorage ?? 0 }
        set { stageSleepDisturbancesStorage = newValue }
    }

    /// Which of the three states the room light is in. Reads `.on` on a save written before the
    /// light existed, for the reason `lightStateStorage` documents. Written through
    /// `setLight(_:now:)`, which is the only thing that keeps it and its timestamp in step.
    var lightState: LightState {
        get { lightStateStorage ?? .on }
        set { lightStateStorage = newValue }
    }

    /// When `lightState` last changed, or nil on a save written before the light was tracked.
    ///
    /// THE LIGHTS-OUT RULE HANGS OFF THIS. `LightsOutRule` asks whether the light had been put out
    /// by a deadline, not whether anything ever observed it being out — which is exactly what lets a
    /// night the app slept through be judged correctly the next morning.
    var lightStateChangedAt: Date? {
        get { lightStateChangedAtStorage }
        set { lightStateChangedAtStorage = newValue }
    }

    /// The `LightsOutRule.windowStart` of the night a lights-left-on mistake was last charged for,
    /// or nil if never.
    ///
    /// A NIGHT and not a local day, which is the one thing that separates it from `wakeMistakeDay`:
    /// a night crosses midnight, so a day key would let 23:00 and 01:00 of the SAME night each
    /// charge their own mistake.
    var lightAuditedNight: Date? {
        get { lightAuditedNightStorage }
        set { lightAuditedNightStorage = newValue }
    }

    /// The `LightsOutRule.windowStart` of the night the lights-out notice was last sent for, or nil
    /// if never. Kept apart from `lightAuditedNight` because the two fall at different graces — the
    /// nudge is meant to arrive with twenty minutes still left to act on it.
    var lightNotifiedNight: Date? {
        get { lightNotifiedNightStorage }
        set { lightNotifiedNightStorage = newValue }
    }

    /// Wins as a 0.0–1.0 fraction of battles fought — `care.battleWinRatio`.
    ///
    /// Derived rather than stored, so it cannot drift from the record it summarises. Zero battles
    /// is 0.0 and never a divide by zero: a Digimon that has never fought has not won, and any
    /// `atLeast` gate on the ratio must fail it rather than crash — or, worse, read as a perfect
    /// record. Lifetime, like the `battleWins`/`battleLosses` it comes from.
    var battleWinRatio: Double {
        let fought = battleWins + battleLosses
        guard fought > 0 else { return 0 }
        return Double(battleWins) / Double(fought)
    }

    /// Counts one training session, however it went. Called by `TrainAction.train` for every
    /// session that actually ran — see `stageTrainingSessions` for why the grade is not consulted.
    func recordTrainingSession() {
        stageTrainingSessions += 1
    }

    /// The reset a hatch and an evolution both perform: this stage's accumulated progress goes, the
    /// lifetime totals stay, and the stage clock restarts at `now`.
    ///
    /// One method rather than four assignments at the call site, because "stage totals reset when
    /// `stageEnteredDate` moves" is only true if nothing can move that date without clearing them —
    /// and a later story adding a fifth stage-scoped total should have exactly one place to add it.
    func enterStage(at now: Date) {
        stageEnergy = .zero
        stageMetricTotals = .zero
        stageBestDayMetrics = .zero
        stageTrainingSessions = 0
        stageOverfeeds = 0
        stageSleepDisturbances = 0
        stageEnteredDate = now
    }

    /// Counts one refused feed against the local day containing `now`.
    ///
    /// Rolls the count over when the day changes, so `refusalCount` always means "today's", which is
    /// the only question anyone asks of it — US-027's overfeeding mistake is three refusals in ONE
    /// day, and a lifetime counter would trip it for someone who refused once a month for a quarter.
    ///
    /// The third refusal of a day is also a care mistake (US-027) — charged here rather than in the
    /// audit, because the refusal count is already per-day and there is nothing elapsed to derive.
    func recordRefusal(now: Date, calendar: Calendar = .current) {
        // A Digimon in the box cannot be offered food, so it cannot refuse any (US-125). Refused
        // here for the reason `recordWakingEarly` gives.
        guard isActive else { return }
        let today = calendar.startOfDay(for: now)
        if refusalDay != today {
            refusalDay = today
            refusalCount = 0
        }
        refusalCount += 1
        // The stage-long tally is deliberately outside the rollover above: it counts refusals since
        // the stage began, so nothing about the day it happened on may reset it.
        stageOverfeeds += 1

        // `refusalMistakeDay` and not `refusalCount == 3`: the fourth and fifth refusals of a day
        // must not each add another mistake, and the marker says so directly.
        if refusalCount >= CareMistakes.refusalsPerMistake, refusalMistakeDay != today {
            refusalMistakeDay = today
            careMistakeCount += 1
        }
    }

    /// How many battles have been fought in the local day containing `now`.
    ///
    /// Reads the rollover rather than writing it: a stale `battleDay` means the count belongs to a
    /// day that is over, and a day that is over always has zero battles fought in it. That is what
    /// makes the count reset at local midnight without anything having to run at midnight — the app
    /// may have been closed straight through it.
    ///
    /// It no longer gates anything — US-108 replaced the daily cap with `BattleCost` — but it is read
    /// by `ConditionEvaluator` for the `.day`-window battle conditions an evolution edge can ask for,
    /// which is why the count and its rollover are still kept.
    func battlesFought(now: Date, calendar: Calendar = .current) -> Int {
        battleDay == calendar.startOfDay(for: now) ? battleCount : 0
    }

    /// Counts a battle that has STARTED. Rolls the count over when the day changes, for the same
    /// reason `recordRefusal` does.
    ///
    /// Separate from `recordBattle`, which files the RESULT: this is counted when the fight starts,
    /// so dismissing the result screen — or force-quitting before it — cannot un-count a battle that
    /// really was fought, exactly as the energy it cost is never handed back.
    func recordBattleStarted(now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if battleDay != today {
            battleDay = today
            battleCount = 0
        }
        battleCount += 1
    }

    /// The energy type this stage has earned the most of — the branch the evolution engine takes.
    ///
    /// Deliberately `stageEnergy`, not `lifetimeEnergy`: the branch is chosen by what this stage
    /// was fed, so a Digimon that spent its childhood walking can still evolve down the sleep
    /// branch if that is how it spends adulthood.
    ///
    /// Nil while all four totals are zero. A caller must get "no leaning yet" rather than an
    /// arbitrary type, because a fresh egg has genuinely not chosen anything and picking for it
    /// would silently hard-code the first branch.
    var dominantEnergyType: EnergyType? {
        guard stageEnergy.total > 0 else { return nil }
        // `allCases` order decides nothing on its own — `outranks` is a strict test, so a later
        // type replaces an earlier one only by really beating it.
        return EnergyType.allCases.reduce(nil) { leader, type in
            guard let leader else { return type }
            return outranks(type, leader) ? type : leader
        }
    }

    /// Whether `type` beats `other`: more energy wins, and a tie goes to the one earned most
    /// recently.
    private func outranks(_ type: EnergyType, _ other: EnergyType) -> Bool {
        guard stageEnergy[type] == stageEnergy[other] else {
            return stageEnergy[type] > stageEnergy[other]
        }
        // Tied. A type never earned this stage cannot outrank one that has; if neither has a
        // timestamp, or both were earned in the same instant — every type credited by one read
        // shares its `now` — nothing distinguishes them, so the incumbent keeps it and the answer
        // stays stable across calls.
        guard let mine = energyLastEarned[type] else { return false }
        guard let theirs = energyLastEarned[other] else { return true }
        return mine > theirs
    }
}
