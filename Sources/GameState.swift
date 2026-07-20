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

    /// The single glyph that labels this type's energy bar. Like `displayName`, nothing persists
    /// it — a bar is one glyph wide because four of them share a 41mm screen with the Digimon.
    var symbol: String {
        switch self {
        case .strength: return "力"
        case .vitality: return "活"
        case .spirit: return "心"
        case .stamina: return "耐"
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
    /// Energy earned over the Digimon's whole life. Survives evolution and death.
    var lifetimeEnergy: EnergyTotals
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
    var strengthStat: Int
    var healthStatus: HealthStatus
    var battleWins: Int
    var battleLosses: Int

    /// A brand new Digimon: an unhatched egg with nothing accumulated yet.
    ///
    /// Every other field is `var`, so a test or a migration can set them individually rather
    /// than needing a twelve-argument initializer.
    init(currentDigimonId: String, stage: Stage = .digitama, now: Date) {
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
        // Stamped with `now` rather than left nil, or a brand new game would be charged for every
        // day between the epoch and today the first time the audit ran.
        self.healthDataLastSeenStorage = now
        self.starvationMistakesChargedStorage = 0
        self.refusalMistakeDayStorage = nil
        self.wakeMistakeDayStorage = nil
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
        self.strengthStat = 0
        self.healthStatus = .healthy
        self.battleWins = 0
        self.battleLosses = 0
    }
}

extension GameState {
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
        let today = calendar.startOfDay(for: now)
        if refusalDay != today {
            refusalDay = today
            refusalCount = 0
        }
        refusalCount += 1

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
    /// makes the cap reset at local midnight without anything having to run at midnight — the app
    /// may have been closed straight through it.
    func battlesFought(now: Date, calendar: Calendar = .current) -> Int {
        battleDay == calendar.startOfDay(for: now) ? battleCount : 0
    }

    /// How many battles are still allowed in the local day containing `now`.
    ///
    /// Clamped at zero so a save whose cap was lowered in an update reads as "none left" rather than
    /// as a negative the UI would have to defend against.
    func battlesRemaining(now: Date, calendar: Calendar = .current) -> Int {
        max(0, BattleLimits.perDay - battlesFought(now: now, calendar: calendar))
    }

    /// Spends one of the day's battles. Rolls the count over when the day changes, for the same
    /// reason `recordRefusal` does.
    ///
    /// Separate from `recordBattle`, which files the RESULT: this is spent when the fight starts, so
    /// dismissing the result screen — or force-quitting before it — cannot hand back an allowance
    /// and let the cap be farmed.
    func consumeBattleAllowance(now: Date, calendar: Calendar = .current) {
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
