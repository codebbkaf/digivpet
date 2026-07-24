import Foundation
import OSLog
import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// Something a side screen asked of the main model that it cannot yet answer.
enum SideScreenStoreError: Error, Equatable {
    /// `sharedStore()` was called before `start()` opened the store. Unreachable from the app — the
    /// Dex is only reachable once the game is `.playing` — but a catchable condition rather than a
    /// crash, so the Dex degrades to an all-undiscovered grid instead of taking the app down.
    case notOpen
}

/// Everything the main screen needs to draw one Digimon: what to call it, and where its art is.
///
/// Derived from the graph rather than read off `GameState`, which saves only an id. The graph is
/// what turns that id into a name and a sprite, so a saved game survives its Digimon being renamed
/// or re-arted without a migration.
struct DigimonPresentation: Equatable {
    let displayName: String
    let stage: Stage
    /// Sheet filename, as `DigimonSpriteView` wants it.
    let spriteFile: String

    /// The sprite subfolder. `Stage.rawValue` IS the folder name on disk (US-006), so this needs
    /// no mapping table.
    var spriteStage: String { stage.rawValue }
}

extension EvolutionGraph {
    /// How to draw the Digimon with this id, or nil if no node has it.
    ///
    /// The STAGE COMES FROM THE NODE, not from `GameState.stage`, and the difference matters: the
    /// node's stage is where the art actually lives, so rendering from the saved copy would draw a
    /// placeholder the moment the two disagreed. `GameState.stage` is a saved duplicate of a fact
    /// the graph already knows — US-018/US-019 must keep it in step when they move a Digimon.
    func presentation(forId id: String) -> DigimonPresentation? {
        guard let node = node(id: id) else { return nil }
        return DigimonPresentation(
            displayName: node.displayName,
            stage: node.stage,
            spriteFile: node.spriteFile
        )
    }
}

extension Roster {
    /// How to draw the Digimon with this id, or nil if the roster has none.
    ///
    /// The roster's answer to `EvolutionGraph.presentation(forId:)`, and the one to reach for when
    /// the id might be any of the 1,025 rather than one of the 88 the graph authors — a Jogress
    /// participant (US-132) is an Ultimate no line reaches, so asking the graph about one answers
    /// nil and the screen silently draws nothing.
    func presentation(forId id: String) -> DigimonPresentation? {
        entry(id: id).map {
            DigimonPresentation(displayName: $0.displayName, stage: $0.stage, spriteFile: $0.spriteFile)
        }
    }
}

/// Drives the main screen: opens the saved game, and turns health data into energy every time the
/// app comes to the front.
@MainActor
final class MainScreenModel: ObservableObject {
    enum Phase: Equatable {
        /// Opening the store. Nothing to draw yet.
        case loading
        /// There is a saved game, in `state`.
        case playing
        /// The store could not be opened, so there is no game to show.
        ///
        /// This explains itself rather than trapping, unlike `EvolutionGraph.bundled`. The
        /// difference is that a broken graph is a broken BUILD, which US-009's validator catches
        /// before it ships, while a store that will not open is a real runtime condition on a real
        /// watch — a full disk, or a migration that failed.
        case failed(String)
    }

    /// A stage transition that just happened and has not yet been shown off: the form left behind
    /// and the form arrived at. The screen plays a full-screen ceremony for it (US-021) and then
    /// clears it via `acknowledgeEvolution()`.
    ///
    /// Set inside `advance()`, so it covers both an egg hatching and a Digimon evolving — either is
    /// a "you are now something new" moment worth a haptic. Because `advance()` runs during
    /// `refresh()`, and `refresh()` runs on `start()`, an evolution that became due while the app was
    /// closed lands here the first time the app is opened and reads its accumulated energy.
    struct EvolutionEvent: Equatable {
        /// The form left behind — its sprite is what the ceremony fades out from.
        let from: DigimonPresentation
        /// The form arrived at — its sprite and name are the reveal.
        let to: DigimonPresentation
    }

    @Published private(set) var phase: Phase = .loading

    /// The saved game. `@Model` types are observable, so a view that reads its properties inside
    /// `body` redraws when energy is credited into it — this does not have to republish anything.
    @Published private(set) var state: GameState?

    /// The most recent stage transition awaiting its on-screen ceremony, or nil once shown.
    @Published private(set) var pendingEvolution: EvolutionEvent?

    /// The most recent Digitama dropped by the selected map (US-128), awaiting its on-screen
    /// announcement, or nil once acknowledged. The drop is already in the box and the Dex by the time
    /// this is set — this is only how the player is told, the same shape `pendingEvolution` uses for
    /// the ceremony.
    @Published private(set) var pendingDigitamaDrop: DigitamaDropAnnouncement?

    /// The battle currently being played out on screen, or nil when none is. Already RESOLVED when it
    /// lands here — see `BattleBout` — so the screen replays a decided outcome rather than rolling.
    @Published private(set) var pendingBattle: BattleBout?

    /// A wild Digimon the player has walked into and not yet answered (US-201), or nil when there is
    /// no encounter pending. Set by `checkForWildEncounter` at the tail of a refresh — the app
    /// foreground — and cleared by `acceptWildEncounter` (BATTLE) or `fleeWildEncounter` (FLEE).
    @Published private(set) var pendingWildEncounter: WildEncounter?

    /// The map's boss, blocking the next map until it is beaten (US-203), or nil when none is pending.
    /// Set by `checkForBossEncounter` at the tail of a refresh — the app foreground — the first time
    /// the player has crossed the map's total AND met every resident, and cleared by
    /// `acceptBossEncounter` (BATTLE, the only action it offers). A win stamps the map finished and
    /// opens the next; a loss knocks 1,000 steps off the counter and lets the boss be re-challenged
    /// once the total is reached again.
    @Published private(set) var pendingBossEncounter: BossEncounter?

    /// The PRE-BATTLE round currently being played on screen, or nil when none is (US-093).
    ///
    /// A third state beside `pendingTraining` and `pendingBattle`, and deliberately not either of them:
    /// it is not a training — no energy, no `strengthStat`, no session counted — and it is not yet a
    /// battle, because the fight has not been rolled. What it holds is everything `battle()` settled
    /// before the game appeared, waiting on the one thing only the round can say.
    @Published private(set) var pendingBattleRound: PendingBattleRound?

    /// A pre-battle round in progress: the game on screen, and the half-built fight behind it.
    ///
    /// The opponent and the generator are picked in `battle()` and carried here rather than drawn again
    /// once the round is graded, for two reasons. "Nobody to fight" is then decided BEFORE the energy
    /// is spent, so an empty roster cannot cost a battle; and the fight is rolled from the
    /// same sequence that picked the opponent, so one seed still produces one whole bout exactly as it
    /// did when `battle()` did both in a breath.
    ///
    /// Not persisted, like `PendingTraining`: a round interrupted by a force-quit is simply over, and
    /// the energy that already reached disk is what makes walking out of it cost something.
    struct PendingBattleRound: Equatable {
        let game: MinigameKind
        let player: DigimonPresentation
        let opponent: BattleOpponent
        let generator: SeededGenerator
    }

    /// The training round currently being played on screen, or nil when none is (US-083).
    ///
    /// The exact inverse of `pendingBattle`: a battle is decided before its view appears and replayed,
    /// while a training round is PAID FOR before its view appears and decided by it. What is carried
    /// here is only what the payout still needs — which game to put on screen, and what entering it
    /// already cost, so the caption at the end can name the currency the bar was taken from.
    @Published private(set) var pendingTraining: PendingTraining?

    /// A training round in progress: the game being played. Not persisted — a round interrupted by a
    /// force-quit is simply over, and the charge that already reached disk (US-177) is what makes
    /// walking out of it cost something. See `train()`.
    struct PendingTraining: Equatable {
        let kind: MinigameKind
    }

    /// What the Digimon is doing on screen. `.idle` except for the moment after an action — feeding
    /// swaps in the eat loop, a refusal the refuse pose — and back again after `actionDuration`.
    @Published private(set) var animation: SpriteAnimation = .idle

    /// A short line about the last action, shown under the Digimon and cleared with the animation.
    /// This is where a blocked feed says WHY it was blocked, per US-024's "visible reason".
    @Published private(set) var actionMessage: String?

    /// The scripted nudge running under the current pose (US-095), or nil when nothing is moving the
    /// sprite — which is every resting pose, and every BLOCKED action.
    ///
    /// Set and cleared by the same `show(_:motion:message:)` call as `animation`, so the two cannot
    /// get out of step: there is no path that leaves a Digimon bobbing after it has stopped eating,
    /// or eating without bobbing.
    @Published private(set) var actionMotion: ActionMotion?

    /// Whether the Digimon is asleep right now.
    ///
    /// DERIVED, not saved: `refresh()` recomputes it from `sleepSchedule`, `state.awakeUntil` and
    /// the clock, so it is deliberately NOT on `GameState` — sleep comes from health data, not from
    /// the saved game. It stays settable so the Simulator demos can force it, since the Simulator
    /// has neither sleep history nor a way to wait until 22:00.
    ///
    /// Since US-110 it is no longer "in the sleep window": prodding a sleeping Digimon WAKES it for
    /// `SleepSchedule.wakeGracePeriod`, and this reads false for those five minutes even though the
    /// window still holds. What it gates is unchanged — the sleep loop, wandering, and the sleep
    /// arms of `FeedAction` and `TrainAction` — but a woken Digimon walks about and can be fed.
    @Published var isAsleep = false

    /// The nightly window the Digimon sleeps in: inferred from the user's last night of sleep, or
    /// `.fallback` (22:00–07:00) when HealthKit had no usable history to infer from.
    @Published private(set) var sleepSchedule: SleepSchedule = .fallback

    /// The asset-catalog name of the map the Digimon is adventuring in (US-115), or nil for "no map
    /// selected" — which draws no background at all and leaves the screen exactly as US-114 left it.
    ///
    /// Since US-118 this is the saved selection on `PlayerProfile`, resolved through the catalog:
    /// `selectMap(_:)` is what moves it, and the view above it did not change — which is the point
    /// of the seam being here rather than the view reaching for an asset name itself. Still nil on
    /// a save that has never chosen a map, which is every save until US-120 ships the picker.
    ///
    /// `-mapDemo=<asset>` still overrides it, which is how US-115's screenshots were taken.
    @Published private(set) var selectedMapAsset: String?

    /// Every Digimon the player has ever raised, by id — the Dex, as a set (US-121).
    ///
    /// "Has ever owned" is the question the map detail asks before it draws a Digitama's name, and
    /// the Dex is the record of it the game already keeps: it is written the moment an egg is
    /// handed over or hatched, and it survives death and rebirth, which is exactly the span the
    /// story means by "owns or has owned".
    @Published private(set) var discoveredDigimonIds: Set<String> = []

    private let makeStore: @MainActor () throws -> GameStore
    private let graph: EvolutionGraph
    /// Consulted for two things. The stage of a Digimon the graph has no node for, when picking its
    /// minigame (US-082) — unreachable from here in practice, since a saved id with no node draws
    /// `SavedGameUnavailableView` and never shows a Train button, but the full lookup is what
    /// `MinigameAssignment` offers and half of it is not worth the saving. And, since US-121, the
    /// name, stage and art of a map's opponents and Digitama, which are roster ids and have no graph
    /// node at all for the most part. Injected alongside `graph` so a test on a fixture graph can
    /// hand over a matching fixture roster.
    private let roster: Roster
    /// The sixteen adventure maps. Injected alongside `graph` and `roster` for the same reason: a
    /// test drives step accrual against a two-map fixture catalog rather than against whatever
    /// `maps.json` currently says a map is worth.
    private let maps: MapCatalog
    /// The fourteen Jogress recipes (US-131). Injected beside `roster` for its reason: a test builds
    /// a two-recipe fixture catalog over fixture Digimon rather than fusing whatever `jogress.json`
    /// currently ships.
    private let jogress: JogressCatalog
    private let energySource: HealthEnergySource
    /// Reads a single `health.*` metric over an arbitrary window. Held for US-178's cleaning charges:
    /// handwashing is a category event, not one of the three daily quantities `energySource` reads,
    /// so it is read here instead. Injected so a test drives washes from a fixture fetcher — the
    /// Simulator has no handwashing data, exactly as it has no steps.
    private let metricReader: HealthMetricReader
    private let calendar: Calendar
    private let now: () -> Date
    private let chooseStartingDigitama: ([EvolutionNode]) -> EvolutionNode?
    private let playFeedHaptic: @MainActor () -> Void
    private let playTrainHaptic: @MainActor () -> Void
    private let makeBattleGenerator: () -> SeededGenerator
    /// The seeded RNG one Digitama drop is chosen from (US-128). Separate from the battle generator
    /// so a test can pin which of several eligible eggs drops without also fixing the battle roll,
    /// and freshly seeded per check in the app so a map with several ready eggs does not always hand
    /// back the first one.
    private let makeDropGenerator: () -> SeededGenerator
    /// The seeded RNG that decides WHICH of a fusion's two eggs comes back (US-132 AC4). Its own
    /// generator for `makeDropGenerator`'s reason: a test that pins the returned egg must not have
    /// to pin the next battle roll as well to do it.
    private let makeJogressGenerator: () -> SeededGenerator
    private let notifications: NotificationDispatcher
    /// The three notification toggles, handed to the Settings screen (`SettingsView`). Owned here rather than
    /// created by the settings screen so the screen and the dispatcher read the same object — a
    /// second `NotificationSettings` would work (both read `UserDefaults`) but would not redraw the
    /// toggles, and would defeat the injected-defaults suite a test relies on.
    let notificationSettings: NotificationSettings
    /// `var` only so the DEBUG Simulator demo can hold a pose long enough to be screenshotted —
    /// nothing in the app or the tests reassigns it. See `seedFeedDemoIfRequested`.
    private var actionDuration: TimeInterval

    #if DEBUG
    /// Debug-only: a sleep window forced by a demo launch argument, winning over the inferred one.
    ///
    /// Needed because forcing `isAsleep` alone does not survive: `ContentView` refreshes on every
    /// return to `.active`, including the one right after launch, and that refresh re-derives
    /// `isAsleep` from the window and undoes it. Overriding the WINDOW instead means the real
    /// derivation is what puts the Digimon to sleep, so it stays asleep across any number of
    /// refreshes — and the demo exercises the shipped path rather than its output.
    private var sleepScheduleOverride: SleepSchedule?

    /// Debug-only: the seed a demo battle is matched and fought from, winning over the injected
    /// random one. See `seedBattleDemoIfRequested` — US-094's screenshots need a specific KIND of
    /// matchup, and the matchmaker draws its opponent from the same generator the fight is rolled
    /// from, so pinning the seed is how you ask for one without hand-setting the opponent.
    private var battleSeedOverride: UInt64?
    #endif

    /// The generator one battle is matched and resolved from — the injected one, unless a DEBUG demo
    /// has pinned a seed.
    private func nextBattleGenerator() -> SeededGenerator {
        #if DEBUG
        if let battleSeedOverride { return SeededGenerator(seed: battleSeedOverride) }
        #endif
        return makeBattleGenerator()
    }

    /// The app group directory the complication's snapshot and its Clean requests cross through.
    ///
    /// A settable property, and injectable for exactly one reason: the real container needs a
    /// signed entitlement that a test bundle does not have, so without this the round trip between
    /// the face and the game could only be tested one half at a time. The app never assigns it —
    /// resolved once here rather than per call, because it cannot change while the app runs.
    var complicationDirectory: URL? = ComplicationSnapshotStore.sharedDirectory()

    private var store: GameStore?
    private var ledger: EnergyLedger?
    /// The de-duplication baseline for raw health readings. Held for US-118's step accrual: the map
    /// is credited the delta this ledger claims, never the day's total.
    private var metricLedger: MetricLedger?
    /// The most recent refresh's real per-metric reads (US-179), kept so the ConditionContext an
    /// evolution, a Jogress offer, a map's hints and a Digitama drop are judged on can answer a
    /// standing measurement — a resting heart rate is not something a running total can hold. Only
    /// `.value` reads are kept: a `.noData`/`.unavailable` answers nothing and, for an accumulating
    /// metric, must not switch on `ConditionContext`'s "we were never allowed to look" override,
    /// which is US-180's decision to make and not this story's. Empty until the first refresh, which
    /// is exactly what these build points saw before.
    private var conditionReadings: [ConditionMetric: HealthReading] = [:]
    /// The player: lifetime energy, map progress, and the Digitama ever owned (US-123). Nil only
    /// before `start()`.
    private(set) var profile: PlayerProfile?
    private var isRefreshing = false
    private var actionResetTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "main")

    /// - Parameters:
    ///   - makeStore: deferred rather than taken as a `GameStore`, because opening the store
    ///     throws and touches the disk — neither belongs in a `View.init`. `@MainActor` because
    ///     `GameStore` is, and this runs when `start()` does rather than where it was written.
    ///   - now: the clock. Injected so a test can place a read on a chosen day without waiting.
    ///   - chooseStartingDigitama: picks a new game's egg from the graph's playable Digitama.
    ///     Random by default, per US-018's "a new game starts at a randomly selected Digitama";
    ///     injected so a test can pin one deterministically instead of chasing randomness.
    ///   - playFeedHaptic: the light tap a feed plays. Injected for the same reason
    ///     `EvolutionCeremonyView.playHaptic` is — it is the one acceptance criterion no screenshot
    ///     can show, so a test spies on it instead.
    ///   - playTrainHaptic: the firmer tap a training session plays. Separate from `playFeedHaptic`
    ///     rather than one shared "action haptic", because the two actions are meant to FEEL
    ///     different on the wrist and a test has to be able to tell which one fired.
    ///   - actionDuration: how long the eat loop or refuse pose is held before returning to idle.
    ///     Injected so a test drives the whole action in milliseconds rather than waiting it out.
    ///   - makeBattleGenerator: the seeded RNG one battle is resolved from. Freshly seeded per battle
    ///     in the app, so two battles differ; injected with a FIXED seed by a test, which is what
    ///     makes US-031's "deterministic winner" assertable through the real model rather than only
    ///     against `BattleEngine` in isolation.
    ///   - notificationSettings: the three toggles. Nil builds one over `UserDefaults.standard`;
    ///     a test passes its own suite so it neither reads nor writes the real preferences.
    ///   - notificationDeliverer: where a notification goes. Nil builds the real
    ///     `UNUserNotificationCenter` one; a test passes a spy, which is the only way to assert
    ///     that something was suppressed — a notification that was not sent leaves no other trace.
    ///     Both are optional-and-nil rather than defaulted values because constructing either is a
    ///     `@MainActor` call, which a default argument would evaluate in the caller's context.
    init(
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() },
        graph: EvolutionGraph = .bundled,
        roster: Roster = .bundled,
        maps: MapCatalog = .bundled,
        jogress: JogressCatalog = .bundled,
        energySource: HealthEnergySource = HealthEnergySource(),
        metricReader: HealthMetricReader = HealthMetricReader(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        chooseStartingDigitama: @escaping ([EvolutionNode]) -> EvolutionNode? = { $0.randomElement() },
        playFeedHaptic: @escaping @MainActor () -> Void = MainScreenModel.feedHaptic,
        playTrainHaptic: @escaping @MainActor () -> Void = MainScreenModel.trainHaptic,
        actionDuration: TimeInterval = 2.0,
        makeBattleGenerator: @escaping () -> SeededGenerator = {
            SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        },
        makeDropGenerator: @escaping () -> SeededGenerator = {
            SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        },
        makeJogressGenerator: @escaping () -> SeededGenerator = {
            SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        },
        notificationSettings: NotificationSettings? = nil,
        notificationDeliverer: PetNotificationDelivering? = nil
    ) {
        self.makeStore = makeStore
        self.graph = graph
        self.roster = roster
        self.maps = maps
        self.jogress = jogress
        self.energySource = energySource
        self.metricReader = metricReader
        self.calendar = calendar
        self.now = now
        self.chooseStartingDigitama = chooseStartingDigitama
        self.playFeedHaptic = playFeedHaptic
        self.playTrainHaptic = playTrainHaptic
        self.actionDuration = actionDuration
        self.makeBattleGenerator = makeBattleGenerator
        self.makeDropGenerator = makeDropGenerator
        self.makeJogressGenerator = makeJogressGenerator
        let settings = notificationSettings ?? NotificationSettings()
        self.notificationSettings = settings
        self.notifications = NotificationDispatcher(
            settings: settings,
            deliverer: notificationDeliverer ?? UserNotificationDeliverer()
        )
    }

    /// How to draw the Digimon currently being raised, or nil if neither the graph nor the roster
    /// knows it.
    var presentation: DigimonPresentation? {
        state.flatMap { presentation(forId: $0.currentDigimonId) }
    }

    /// How to draw a saved id: from the GRAPH where a line reaches it, and from the ROSTER
    /// otherwise.
    ///
    /// The bridge US-122 built for opponents, applied to the Digimon the player has out — and
    /// US-132 is what makes it necessary rather than tidy. A Jogress result is an Ultimate no
    /// authored line reaches (`omegamon` is one of the 780 orphans until Phase E wires it), so a
    /// graph-only lookup answers nil for every fusion in the game and the main screen would draw
    /// `SavedGameUnavailableView` over a Digimon the player had just earned.
    ///
    /// The graph is asked FIRST and not merely preferred: for a wired id the two agree on the name
    /// and the sprite, but the graph's stage is where the ART lives (see
    /// `EvolutionGraph.presentation(forId:)`), and that is the one field a disagreement would draw
    /// a placeholder for.
    func presentation(forId id: String) -> DigimonPresentation? {
        graph.presentation(forId: id) ?? roster.presentation(forId: id)
    }

    /// The four energy bars for the Digimon currently being raised, or nil if the graph does not
    /// know it.
    ///
    /// The thresholds come from the CURRENT NODE's edges, so the bars re-aim themselves when a
    /// Digimon evolves without anything here having to notice.
    var energyProgress: EnergyProgress? {
        guard let state, let node = graph.node(id: state.currentDigimonId) else { return nil }
        return node.energyProgress(for: state.stageEnergy)
    }

    /// The egg a brand-new game starts at: one of the graph's playable Digitama, chosen by
    /// `chooseStartingDigitama` (random in the app).
    ///
    /// `dexOnly` Digitama are excluded — an egg that hatches has to animate, and a dexOnly node has
    /// no animated sheet to slice.
    ///
    /// Eggs whose thread does not yet reach an Ultimate are excluded too, which is US-144's doing:
    /// an orphan sweep authors one rung of the ladder at a time, so the file now holds eggs that
    /// hatch into a Baby I with nothing above it. Handing one of those to somebody who has just
    /// installed the app is a game that stops after a day. The `isEmpty` fallback keeps this total
    /// rather than correct-or-crash: if no thread were finished, a startable egg still beats none.
    private var startingDigitamaId: String? {
        let playable = graph.nodes(at: .digitama).filter { !$0.dexOnly }
        let raisable = playable.filter { graph.reachesUltimate(from: $0.id) }
        return chooseStartingDigitama(raisable.isEmpty ? playable : raisable)?.id
    }

    /// Opens the saved game, starting a new one if there is none, then reads health data once so
    /// the screen is current the moment it appears.
    func start() async {
        if store == nil {
            do {
                guard let digitamaId = startingDigitamaId else {
                    throw GraphError.noDigitama
                }
                let store = try makeStore()
                self.state = try store.loadOrCreate(digitamaId: digitamaId, now: now())
                self.ledger = try store.loadOrCreateLedger(now: now(), calendar: calendar)
                self.metricLedger = try store.loadOrCreateMetricLedger(now: now(), calendar: calendar)
                self.profile = try store.loadOrCreateProfile(roster: roster, graph: graph)
                // The Dex read once at open rather than on every redraw of the map detail: it is a
                // fetch of every entry, the screen that asks is drawn inside a `body`, and the set
                // only ever grows — `advance` inserts into it as it records.
                self.discoveredDigimonIds = Set((try? store.dexIds()) ?? [])
                self.store = store
                // US-129, the first of the three failsafe checks: a store left with nothing alive in
                // it — the app killed after the last Digimon died, or a grant whose save failed —
                // hands the player an egg here, before the screen is ever drawn. The other two are
                // in `refresh` (after a death) and, when it lands, after a Jogress.
                checkForStranding()
                publishSelectedMap()
                self.phase = .playing
            } catch {
                self.phase = .failed(String(describing: error))
                return
            }
        }
        requestNotificationAuthorization()
        await refresh()
        #if DEBUG
        seedCeremonyDemoIfRequested()
        seedFeedDemoIfRequested()
        seedTrainDemoIfRequested()
        seedSleepDemoIfRequested()
        seedSleepBarDemoIfRequested()
        seedWanderDemoIfRequested()
        seedWildEncounterDemoIfRequested()
        seedBossEncounterDemoIfRequested()
        seedSickDemoIfRequested()
        seedDeathDemoIfRequested()
        seedBattleDemoIfRequested()
        seedPoopDemoIfRequested()
        seedChargesDemoIfRequested()
        seedLightDemoIfRequested()
        seedMapDemoIfRequested()
        seedMapListDemoIfRequested()
        seedPartyDemoIfRequested()
        seedJogressDemoIfRequested()
        // Every seed above runs AFTER the refresh that published, so the snapshot on disk still
        // describes the pre-demo game — a `-sickDemo -complicationDemo` run would screenshot an idle
        // pose. Republishing here is the same rule as `clean()`'s, applied to the demos: the state
        // changed outside a refresh, so the face is told. DEBUG only, like the seeds themselves.
        publishComplicationSnapshot()
        #endif
    }

    /// Asks the system for permission to notify, before the refresh that may hatch an egg or find
    /// the Digimon sick — an unauthorized `add` fails silently, so the ask has to precede the first
    /// send rather than follow it.
    ///
    /// `-noNotificationPrompt` suppresses the ask in DEBUG builds only, and exists for exactly one
    /// reason: the system's permission alert is a full-screen sheet that `simctl` can neither tap
    /// nor dismiss, so every Simulator screenshot after this shipped would land on the alert instead
    /// of the screen under test. It suppresses the ASK, never a notification — the rules and the
    /// dispatcher are untouched by it.
    private func requestNotificationAuthorization() {
        #if DEBUG
        guard !CommandLine.arguments.contains("-noNotificationPrompt") else { return }
        #endif
        notifications.requestAuthorization()
    }

    #if DEBUG
    /// Debug-only: forces the evolution ceremony to play on launch so it can be screenshotted in the
    /// Simulator, which has no HealthKit data to drive a real evolution. Unreachable without the
    /// `-evolutionCeremonyDemo` launch argument, and the whole method is compiled out of release
    /// builds — the same discipline as US-011's `StubHealthAuthorizer`.
    private func seedCeremonyDemoIfRequested() {
        guard CommandLine.arguments.contains("-evolutionCeremonyDemo"),
              let from = graph.presentation(forId: "agumon"),
              let to = graph.presentation(forId: "greymon") else { return }
        pendingEvolution = EvolutionEvent(from: from, to: to)
    }

    /// Debug-only: puts the saved game into a state where feeding is worth screenshotting, since the
    /// Simulator has no HealthKit data and so a real game there is never hungry and never has the
    /// Vitality to spend. Unreachable without a launch argument and compiled out of release builds,
    /// the same discipline as `seedCeremonyDemoIfRequested`.
    ///
    /// - `-feedDemo` — hungry and funded, then fed: the eat loop and the spent Vitality.
    /// - `-feedRefuseDemo` — funded but not hungry, then fed: the refuse frame.
    /// - `-feedAsleepDemo` — hungry and funded but asleep, then fed: since US-110 this is the WAKE,
    ///   not a block. The Digimon is prodded out of the sleep loop, eats, and is left in the walk
    ///   loop once the pose runs out — which is the after half of the pair `-sleepDemo` opens.
    ///
    /// The pose is held for a minute in demo mode because `simctl` cannot tap Feed itself — the app
    /// has to arrive already showing the outcome, and two seconds is not long enough to boot,
    /// install, launch and screenshot inside.
    private func seedFeedDemoIfRequested() {
        let arguments = CommandLine.arguments
        let refusing = arguments.contains("-feedRefuseDemo")
        let sleeping = arguments.contains("-feedAsleepDemo")
        guard arguments.contains("-feedDemo") || refusing || sleeping, let state else { return }

        // Moved off the starting egg, because a Digitama sheet has no eat or refuse frames — an egg
        // would screenshot as the placeholder no matter how well feeding worked.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            // Restamped, or US-020's time gate is already open on a save from an earlier launch and
            // the next refresh evolves the demo out from under the screenshot.
            state.stageEnteredDate = now()
        }
        state.stageEnergy[.vitality] = 30
        state.hunger = refusing ? 0 : 3
        if sleeping { forceAsleepForDemo() }
        actionDuration = 60
        feed()
    }

    /// Debug-only: the training equivalent of `seedFeedDemoIfRequested`, for the same reason — the
    /// Simulator has no HealthKit data, so a real game there never has the Strength to spend, and
    /// `simctl` cannot tap the Train button in any case.
    ///
    /// - `-trainDemo` — funded and healthy, then trained: since US-083 that OPENS the assigned
    ///   minigame (Button Masher, for Agumon's line) over the main screen. Left to play itself out:
    ///   nothing taps it, so the game's own window expires and it grades its own `.miss` through the
    ///   shipped `onFinish`. A screenshot in the first seconds catches the round, one after ~7s
    ///   catches the payout caption — a whole training, unstaged, end to end.
    /// - `-trainResultDemo` — the same round, with a `.great` handed to `finishTraining` in place of
    ///   the grade a mashed round would have produced. It STAGES THE GRADE and nothing else: the
    ///   payout, the pose and the caption are the shipped ones, since this is the very call the
    ///   game's `onFinish` makes. `simctl` cannot mash a button, so the grade is what has to move.
    /// - `-trainAsleepDemo` — funded but asleep, then trained: the blocked reason, and NO game.
    /// - `-trainSickDemo` — funded but sick, then trained: the other blocked reason, and no game.
    private func seedTrainDemoIfRequested() {
        let arguments = CommandLine.arguments
        let sleeping = arguments.contains("-trainAsleepDemo")
        let sick = arguments.contains("-trainSickDemo")
        let grading = arguments.contains("-trainResultDemo")
        guard arguments.contains("-trainDemo") || sleeping || sick || grading, let state else { return }

        // Off the starting egg for the same reason feeding's demo is: a Digitama sheet has no
        // attack frame, so an egg would screenshot as the placeholder however well training worked.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            // Restamped, or US-020's gate is already open on a save from an earlier launch and the
            // next refresh evolves the demo out from under the screenshot.
            state.stageEnteredDate = now()
        }
        state.stageEnergy[.strength] = 30
        state.healthStatus = sick ? .sick : .healthy
        // Forced awake unless the demo is ABOUT sleep, for the reason `seedBattleDemoIfRequested`
        // documents: `begin` checks sleep first and the fallback window is 22:00-07:00, so an evening
        // screenshot run would land on "Asleep — let it rest." for every one of these flags — the
        // game, the sick block, all of it.
        if sleeping { forceAsleepForDemo() } else { forceAwakeForDemo() }
        actionDuration = 60
        train()
        if grading { finishTraining(.great) }
    }

    /// Debug-only: forces the Digimon into its sleep window so the sleep loop can be screenshotted.
    /// The Simulator has no sleep history to infer a window from, and no way to wait until 22:00.
    ///
    /// - `-sleepDemo` — asleep: the sleep1 <-> sleep2 loop instead of the walk loop.
    ///
    /// Since US-110 this is also the BEFORE half of the wake screenshot; `-feedAsleepDemo` is the
    /// after, and the two differ only in the tap, so a pair taken from them is a real comparison.
    private func seedSleepDemoIfRequested() {
        guard CommandLine.arguments.contains("-sleepDemo"), let state else { return }

        // Off the starting egg for the same reason the other demos are: a Digitama sheet has no
        // sleep frames, so an egg would screenshot as the placeholder however well this worked.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAsleepForDemo()
        animation = restingAnimation
    }

    /// Debug-only: puts a Child on the main screen with a known accumulated-sleep total so the Zz
    /// DashBar (US-182) can be screenshotted with a real fill — the Simulator has no HealthKit sleep
    /// to bank, so the accumulation is seeded directly.
    ///
    /// - `-sleepBarDemo` — 6 accumulated hours, so the Zz bar reads 6 of `sleepHoursCap` dashes.
    /// - `-sleepBarFullDemo` — 14 hours, a nearly-full bar, for the "two Digimon, different fill"
    ///   comparison AC3 asks for.
    /// - `-sleepTimeDemo` — the same 6 hours, seeded for US-213: the bar became an indigo ring around
    ///   the new Sleep button, and the flag that pushes the screen behind it (`ContentView`) needs the
    ///   same hours banked, or the ring photographs empty and the screen reads "0 h".
    /// - `-sleepBottomDemo` — US-214's push-and-scroll, which needs the same hours for the same
    ///   reason. Seeded here rather than by a second flag, so the shot is one argument.
    private func seedSleepBarDemoIfRequested() {
        let arguments = CommandLine.arguments
        let full = arguments.contains("-sleepBarFullDemo")
        guard arguments.contains("-sleepBarDemo") || full
                || arguments.contains("-sleepTimeDemo")
                || arguments.contains("-sleepBottomDemo"), let state else { return }

        // Off the starting egg so the bar sits under a real Digimon rather than the placeholder.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAwakeForDemo()
        state.accumulatedSleepMinutes = Double((full ? 14 : 6) * 60)
        animation = restingAnimation
    }

    /// Debug-only: puts a healthy Child on screen so US-037's walk — and in particular the MIRRORED
    /// sprite it draws when heading right — can be screenshotted.
    ///
    /// - `-wanderDemo` — a healthy Agumon, walking.
    ///
    /// Needed because every other demo flag seeds a state that SUSPENDS movement, and the default
    /// save is a Digitama, whose art is near enough symmetric that a flip cannot be seen in it. The
    /// walk itself is untouched: this only chooses who is doing it.
    private func seedWanderDemoIfRequested() {
        guard CommandLine.arguments.contains("-wanderDemo"), let state else { return }

        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            // Restamped for the same reason the other demos restamp it: an old `stageEnteredDate`
            // lets the next refresh evolve the demo out from under the screenshot.
            state.stageEnteredDate = now()
            // Hatched three days ago, so the strip reads a real `3Y` (US-200) rather than the `0Y`
            // a freshly seeded demo would show.
            state.hatchedDate = now().addingTimeInterval(-3 * Death.secondsPerDay)
        }
    }

    /// Debug-only: raises a wild encounter on launch so US-201's BATTLE/FLEE dialog can be
    /// screenshotted. The Simulator earns no steps, so a real save there never crosses the 500-step
    /// interval that summons one — and `simctl` cannot walk.
    ///
    /// - `-wildEncounterDemo` — a healthy Agumon on the first real map, with 600 steps recorded into
    ///   it and no marker, so the shipped `checkForWildEncounter` finds the crossing and rolls a
    ///   real opponent from that map's pool. The dialog on screen is the one the rule produces, not a
    ///   staged one.
    ///
    /// Steps are recorded straight onto the map's counter (the "step source" US-201 injects), then
    /// the shipped check runs — so what is screenshotted is the real trigger over a real map pool.
    private func seedWildEncounterDemoIfRequested() {
        guard CommandLine.arguments.contains("-wildEncounterDemo"),
              let state, let profile, let map = maps.maps.first else { return }

        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAwakeForDemo()
        selectMap(map.id)
        profile.record(steps: 600, forMap: map.id)
        checkForWildEncounter()
    }

    /// Debug-only: sets the first map up as done-but-for-the-boss so US-203's boss dialog can be
    /// screenshotted. The Simulator has no HealthKit steps, so a real game there can never walk a whole
    /// map or meet its residents, and the boss would never appear on its own.
    ///
    /// - `-bossEncounterDemo` — the first map walked past its total, every resident met, so the shipped
    ///   `checkForBossEncounter` finds the map complete and rolls its real boss (the highest-stage
    ///   resident). The dialog on screen is the one the rule produces, not a staged one.
    ///
    /// Recorded straight onto the map's counter and met-set (the same fields the real triggers write),
    /// then the shipped check runs — so what is screenshotted is the real gate over a real map pool.
    private func seedBossEncounterDemoIfRequested() {
        guard CommandLine.arguments.contains("-bossEncounterDemo"),
              let state, let profile, let map = maps.maps.first else { return }

        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAwakeForDemo()
        selectMap(map.id)
        profile.record(steps: Double(map.totalSteps) + 500, forMap: map.id)
        for resident in MapOpponentBand.residents(of: map, graph: graph, roster: roster,
                                                  excluding: state.currentDigimonId) {
            profile.recordMet(resident.id, forMap: map.id)
        }
        checkForBossEncounter()
    }

    /// Debug-only: makes the Digimon ill so the sick pose can be screenshotted. The Simulator has no
    /// HealthKit data, so a real game there can never accrue the health-data mistakes that would
    /// make it sick on its own — and waiting out three eight-hour starving spells is not a demo.
    ///
    /// - `-sickDemo` — three care mistakes, settled through the real rule: the slow hurt loop.
    ///
    /// The mistakes are set and `updateSickness` is what turns them into an illness, so the demo
    /// exercises the shipped rule rather than hand-setting the status it is supposed to produce.
    private func seedSickDemoIfRequested() {
        guard CommandLine.arguments.contains("-sickDemo"), let state else { return }

        // Off the starting egg for the same reason the other demos are: a Digitama sheet has no
        // hurt frames, so an egg would screenshot as the placeholder however well this worked.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        state.careMistakeCount = Sickness.careMistakesUntilSick
        state.updateSickness(energyEarnedToday: 0)
        settleRestingPose()
    }

    /// Debug-only: kills the Digimon so the memorial can be screenshotted. Waiting out 72 real hours
    /// of illness is not a demo, and the Simulator has no HealthKit data to make it ill in the first
    /// place.
    ///
    /// - `-deathDemo` — sick for 72 hours, settled through the real rule: the memorial screen.
    ///
    /// The illness and its start are set and `updateDeath` is what kills it, so the demo exercises
    /// the shipped rule rather than hand-setting the status it is supposed to produce. A six-day
    /// birth date gives the memorial a lifespan worth reading instead of "0 days".
    private func seedDeathDemoIfRequested() {
        guard CommandLine.arguments.contains("-deathDemo"), let state else { return }

        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        state.birthDate = now().addingTimeInterval(-6 * Death.secondsPerDay)
        profile?.lifetimeEnergy = EnergyTotals(strength: 120, vitality: 80, spirit: 40, stamina: 30)
        state.strengthStat = 7
        state.healthStatus = .sick
        state.sickSince = now().addingTimeInterval(-Death.secondsSickUntilDeath)
        state.updateDeath(now: now())
        settleRestingPose()
    }

    /// Debug-only: starts a battle on launch so it can be screenshotted. The Simulator has no
    /// HealthKit data, so a real game there never trains up anything to fight with — and `simctl`
    /// cannot tap the Battle button in any case.
    ///
    /// - `-battleDemo` — a well-trained Child, then battled: the attack and hurt frames.
    /// - `-battleTurnDemo` — the same, with `ContentView` holding one exchange for a minute so the
    ///   screenshot catches the attack and hurt frames rather than a 0.7s beat.
    /// - `-battleResultDemo` — the same, with `ContentView` pacing the replay down to nothing so the
    ///   screenshot lands on the result screen instead of mid-exchange. Its seed is searched for a
    ///   matchup with something to say (US-094): an element ADVANTAGE on the win, and — combined with
    ///   `-battleLossDemo` — a DISADVANTAGE on the loss.
    /// - `-battleIntroDemo` — the same seeding, with `ContentView` holding the STARE-DOWN instead of
    ///   racing past it, so US-094's element badges and effectiveness caption can be screenshotted.
    /// - `-battleSignatureDemo` — the same, with `ContentView` holding the KNOCKOUT exchange (US-073)
    ///   so the screenshot catches the signature move and its banner rather than an ordinary shot.
    /// - `-battleLossDemo` — an untrained Child against the stages above it: very likely the losing
    ///   result, and pinned to one by the seed search when it is combined with a matchup demo.
    ///   Genuinely fought rather than hand-set, so what is screenshotted is the real rule.
    /// - `-battleBrokeDemo` — Strength and Stamina emptied, leaving the disabled Battle button and its
    ///   reason (US-108, replacing `-battleLimitDemo` and the cap it screenshotted). Emptying the two
    ///   payable energies rather than hand-setting a flag, so what is screenshotted is the shipped
    ///   rule's own answer. No scroll flag needed since US-039 — the action row is on screen on both
    ///   watch sizes.
    /// - `-battleAffordableDemo` — the same screen with exactly one battle's worth of Strength, so
    ///   US-109's two screenshots differ in nothing but the energy: Battle live and NO caption under
    ///   the row. Its own flag because every other funded demo goes straight into the arena.
    /// - `-battleRoundDemo` — US-093's pre-battle round, left to play itself out: nothing taps it, so
    ///   the game's own window expires and its shipped `onFinish` grades the `.miss` that opens the
    ///   arena. One launch, screenshotted twice — the minigame in the first seconds, the arena after —
    ///   which is the whole of AC1 through AC5 with nothing staged. Fought as Piyomon; see below.
    ///
    /// The outcome is left to the real matchmaker and the real engine — only the player's stats and
    /// the seed are staged, so this exercises the shipped path rather than its output.
    private func seedBattleDemoIfRequested() {
        let arguments = CommandLine.arguments
        let losing = arguments.contains("-battleLossDemo")
        let staged = ["-battleDemo", "-battleResultDemo", "-battleTurnDemo", "-battleSignatureDemo",
                      "-battleIntroDemo"]
        // The two US-094 demos, and the only ones that need a matchup with something to SAY.
        let showingMatchup = ["-battleResultDemo", "-battleIntroDemo"]
        let broke = arguments.contains("-battleBrokeDemo")
        let affordable = arguments.contains("-battleAffordableDemo")
        let round = arguments.contains("-battleRoundDemo")
        guard staged.contains(where: arguments.contains) || losing || broke || round || affordable,
              let state else { return }

        // Off the starting egg for the same reason the other demos are: a Digitama sheet has no
        // attack or hurt frames, so an egg would screenshot as placeholders however well this worked.
        //
        // `-battleRoundDemo` fights as PIYOMON rather than Agumon, and the choice is the whole reason
        // the flag works: its assigned game is the Reflex Strike, which is the one of the six that
        // ENDS ON ITS OWN — it draws a delay, opens a reaction window, and grades a miss when nothing
        // taps it. Agumon's Button Masher sits on "Tap to start" forever, so `simctl`, which cannot
        // tap, would screenshot the same waiting round twice and never reach the arena.
        //
        // `-battleLossDemo` fights as an UNTRAINED Agumon rather than as Botamon, which is what it
        // used before US-094. A Baby I is matched against rungs 0-2, and NOTHING in that pool is
        // typed water or earth — the two elements that beat Botamon's fire — so a loss at a
        // DISADVANTAGE, which is half of what US-094 has to photograph, cannot exist there at all.
        // A Child at `strengthStat` 0 has the Adults above it in its pool, loses to them just as
        // reliably, and can lose to one it is badly matched against.
        if let node = graph.node(id: round ? "piyomon" : "agumon") {
            state.currentDigimonId = node.id
            state.stage = node.stage
            // Restamped, or US-020's gate is already open on a save from an earlier launch and the
            // next refresh evolves the demo out from under the screenshot.
            state.stageEnteredDate = now()
        }
        state.strengthStat = losing ? 0 : 12
        // Forced awake, because a sleeping Digimon refuses to battle and the fallback window is
        // 22:00-07:00 — so without this the demo screenshots "Asleep — let it rest." on any evening
        // run, which is exactly what happened the first time it was tried.
        forceAwakeForDemo()

        if broke {
            // Emptied rather than left alone: the Simulator has no HealthKit data, but a save from an
            // earlier demo launch may still be carrying energy, and the point of the flag is that the
            // button is unaffordable. Nothing else is done — the main screen draws, with Battle
            // disabled by the shipped rule reading these two zeroes.
            state.stageEnergy.strength = 0
            state.stageEnergy.stamina = 0
            return
        }

        if affordable {
            // The other half of US-109's pair: the same screen with the cost covered, so the two
            // 41mm screenshots differ in nothing but the energy. Exactly the price of one battle
            // rather than a comfortable pile, because the boundary is what the story is about.
            state.stageEnergy.strength = BattleCost.energy
            state.stageEnergy.stamina = 0
            return
        }

        // Enough for exactly the one fight these demos are about to start. Without it every arena
        // demo would screenshot US-108's refusal instead: the Simulator earns no steps, so a demo
        // Digimon has nothing to pay with.
        state.stageEnergy.strength = max(state.stageEnergy.strength, BattleCost.energy)

        // US-094's screenshots have to show a matchup that actually did something: an advantage on a
        // win, a disadvantage on the loss. So the SEED is searched for one — the real matchmaker and
        // the real engine decide what it produces, exactly as they do on a random seed, and all that
        // is staged is which of the seeds it is. Left random if the scan finds nothing, in which case
        // the screenshot shows whatever it drew.
        if showingMatchup.contains(where: arguments.contains) {
            battleSeedOverride = Self.demoBattleSeed(
                showing: losing ? .disadvantage : .advantage,
                playerWins: !losing,
                playerId: state.currentDigimonId,
                playerPower: state.battlePower(lifetimeEnergy: lifetimeEnergy),
                in: graph,
                roster: roster,
                map: selectedMap,
                recorded: selectedMapRecorded)
            if battleSeedOverride == nil {
                Self.log.error("No demo battle seed gives the matchup the screenshot wants")
            }
        }

        battle()
        // Every ARENA demo stages the grade, exactly as `-trainResultDemo` does and for the same
        // reason: `simctl` cannot play a round, and the arena is what these flags are for. `good` is
        // the neutral grade, so the fight they screenshot is the one they screenshotted before the
        // pre-battle round existed. `-battleRoundDemo` alone leaves the round up and lets the game
        // grade itself.
        if !round { finishBattleRound(.good) }
    }

    /// Debug-only: the lowest seed whose battle shows `wanted` on the element axis and ends the way
    /// `playerWins` says, or nil if none of the first `limit` does.
    ///
    /// PURE — it replays exactly what `battle()` and `finishBattleRound(.good)` are about to do with
    /// the same seed: `BattleMatchmaker.choose` draws first, then `BattleEngine.resolve` draws from
    /// what is left of the same generator. That shared sequence is why the answer holds: nothing here
    /// is a prediction of the fight, it IS the fight, run once with nothing spent and no state
    /// touched. Grade `.good` because that is what the arena demos stage.
    private static func demoBattleSeed(
        showing wanted: Effectiveness,
        playerWins: Bool,
        playerId: String,
        playerPower: Int,
        in graph: EvolutionGraph,
        roster: Roster,
        map: AdventureMap?,
        recorded: Double,
        limit: UInt64 = 4096
    ) -> UInt64? {
        let types = ElementCatalog.bundled
        let playerType = types.type(for: playerId, in: graph)

        for seed in 0..<limit {
            var generator = SeededGenerator(seed: seed)
            // Nil means the roster offers nobody at all, which no later seed can fix.
            // The map is carried in for the same reason the seed is searched at all: this must
            // replay exactly what `battle()` is about to draw, and since US-122 that depends on
            // where the player is adventuring.
            guard let opponent = BattleMatchmaker.choose(in: graph, roster: roster,
                                                        playerId: playerId,
                                                        map: map, recorded: recorded,
                                                        using: &generator) else { return nil }
            let matchup = BattleModifiers.matchup(
                playerPower: playerPower,
                playerType: playerType,
                opponentPower: opponent.power,
                opponentType: types.type(forId: opponent.node.id, line: opponent.node.line),
                training: .good)
            guard matchup.elementEffectiveness == wanted else { continue }

            let report = BattleEngine.resolve(playerPower: matchup.playerPower,
                                              opponentPower: matchup.opponentPower,
                                              using: &generator)
            if report.playerWon == playerWins { return seed }
        }
        return nil
    }

    /// Debug-only: fills the screen with poop so US-052's pile and its Clean button can be
    /// screenshotted. Waiting out twelve real hours is not a demo, and `simctl` cannot tap Clean.
    ///
    /// - `-poopDemo` — a full four poops beside the Digimon, and an enabled Clean button.
    /// - `-poopCleanDemo` — the same, then cleaned ten seconds after launch: the pile shrinking and
    ///   fading away, the hop, and the confirmation caption.
    ///
    /// The count is ACCRUED by winding the timestamp back twelve hours and running the real
    /// `advancePoop`, not hand-set, so what is screenshotted is the shipped rule's output. The
    /// Digimon is forced awake first because a sleeping one accrues nothing and the fallback window
    /// is 22:00-07:00 — an evening screenshot run would otherwise come back clean.
    private func seedPoopDemoIfRequested() {
        let arguments = CommandLine.arguments
        let cleaning = arguments.contains("-poopCleanDemo")
        guard arguments.contains("-poopDemo") || cleaning, let state else { return }

        // Off the starting egg like every other demo: an egg sheet has no happy frame, so the
        // clean demo would screenshot the placeholder however well cleaning worked.
        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAwakeForDemo()
        state.poopUpdatedAt = now().addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: isAsleep, now: now())

        if cleaning {
            // Held for a minute, because the caption clears itself in two and that is not long
            // enough to boot, install, launch and screenshot inside.
            actionDuration = 60
            // DEFERRED rather than cleaned here, and this is the one demo that has to be: the pile
            // leaves by a 0.35s shrink-and-fade (US-097), which is an event rather than a state, so
            // a clean run at launch is finished long before `simctl` has taken its first shot. The
            // delay puts the transition in the middle of a screenshot burst instead of before it.
            // The hop needs no such help — `show` repeats it for the whole minute the pose is held.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.poopCleanDemoDelay))
                self?.clean()
            }
        }
    }

    /// Debug-only: banks partial Train / Battle / Clean charges so US-199's three rings around those
    /// buttons can be screenshotted with a real fill. `simctl` cannot walk, exercise or wash, so the
    /// counts are what have to move — and only the counts: the rings are the shipped `DashRing`s
    /// drawing whatever this banks. It seeds its own awake Agumon, funds a battle so that button is
    /// enabled, and drops a little poop so Clean is enabled too.
    ///
    /// - `-chargesDemo` — Feed 13/20 (orange), Train 4/10 (red), Battle 7/10 (purple), Clean 5/8
    ///   (blue) and Map 1050/3000 (green): five partly filled rings on the action grid at once (meat
    ///   joined in US-208, map steps in US-212).
    private func seedChargesDemoIfRequested() {
        guard CommandLine.arguments.contains("-chargesDemo"), let state else { return }

        if let agumon = graph.node(id: "agumon") {
            state.currentDigimonId = agumon.id
            state.stage = agumon.stage
            state.stageEnteredDate = now()
        }
        forceAwakeForDemo()

        let config = ConsumptionConfig.bundled
        state.trainCharges = min(4, config.maxTrainCharges)
        state.battleCharges = min(7, config.maxBattleCharges)
        profile?.cleanCharges = min(5, config.maxCleanCharges)
        // The larder Feed's own ring reads (US-208), off the same cap the ring is drawn to.
        profile?.meat = min(13, config.meatCap)

        // Fund a battle so the purple ring sits on an ENABLED button rather than a greyed one, and
        // stage some mess so the blue ring's Clean button is enabled too.
        state.stageEnergy.strength = max(state.stageEnergy.strength, BattleCost.energy)
        state.poopUpdatedAt = now().addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: isAsleep, now: now())

        seedMapRingForChargesDemo()
    }

    /// The fifth ring (US-212): a map selected and part-walked, so Map's green ring can be
    /// screenshotted with a real fill beside the other four rather than as an empty circle. The
    /// Simulator earns no steps, so — exactly as with the charges above — the counter is what has to
    /// move; the ring is the shipped `DashRing` drawing whatever this banks.
    ///
    /// Two details that are the whole reason this is a method rather than two lines:
    ///
    /// * It walks the FIRST map to 35% (1050 of 3000), which the existing `-mapListDemo` family
    ///   cannot stand in for: every one of those finishes maps and pushes the map list, and the shot
    ///   this flag exists for is the grid on the main screen.
    /// * It then moves the map's wild-encounter marker up to the same total. Banking 1050 steps in
    ///   one go otherwise owes an encounter the moment the screen appears (US-201 raises one every
    ///   500 steps), and its dialog covers the grid — so without this, the flag hides the very thing
    ///   it seeds. Moving the marker is what a resolved encounter does, so this leaves the save in a
    ///   state the game itself can produce rather than an impossible one.
    ///
    /// IDEMPOTENT: `record(steps:)` accumulates, so the counter is set to the target rather than
    /// credited towards it — a second launch on the same container would otherwise read 2100/3000.
    private func seedMapRingForChargesDemo() {
        guard let profile, let map = maps.maps.first else { return }
        let walked = Double(map.totalSteps) * 0.35

        selectMap(map.id)
        profile.setRecorded(walked, forMap: map.id)
        profile.setEncounterMarker(walked, forMap: map.id)
        try? store?.save()
    }

    /// Debug-only: puts the room light into a state worth screenshotting. `simctl` cannot tap the
    /// light button any more than it can tap Feed, so the state is what has to move — and only the
    /// state: the scrim, the symbol and the button are the shipped ones drawing whatever this sets.
    ///
    /// - `-lightSemiDemo` — the night light: the half scrim.
    /// - `-lightOffDemo` — lights out: the full scrim.
    ///
    /// Set through the real `setLight(_:now:)` rather than by assignment, so the demo cannot leave a
    /// state and a stamp that disagree — which is exactly what US-101's rule would misread. Combine
    /// with `-wanderDemo` for a Digimon rather than an egg under the scrim.
    private func seedLightDemoIfRequested() {
        let arguments = CommandLine.arguments
        let semi = arguments.contains("-lightSemiDemo")
        guard semi || arguments.contains("-lightOffDemo"), let state else { return }

        state.setLight(semi ? .semi : .off, now: now())
    }

    /// Debug-only: selects a map to draw behind the Digimon, since nothing can select one yet — the
    /// picker is US-120.
    ///
    /// `-mapDemo=01_grassland`, taking the asset name inline rather than one flag per map: there are
    /// sixteen backgrounds and US-115 has to be photographed over the three brightest of them.
    ///
    /// Since US-118 it names a real map where it can: if a catalog map draws that asset, the demo
    /// goes through the shipped `selectMap(_:)`, so the run also accrues steps and can be
    /// screenshotted with progress on it. An asset no map uses still just draws — unvalidated on
    /// purpose, so a typo screenshots the missing-resource placeholder, which is the honest result
    /// and cheaper to spot than a silent fallback to grassland.
    ///
    /// **`-mapDemo=none` is its inverse, and exists because the selection is now SAVED.** A demo
    /// flag that writes to the store and has no way back poisons every screenshot taken on that
    /// container afterwards, silently, since the shot still looks plausible — which is exactly what
    /// `-lightOffDemo` cost US-115 an hour of. Pass `none` to go back to no map at all.
    private func seedMapDemoIfRequested() {
        let prefix = "-mapDemo="
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return
        }
        let asset = String(argument.dropFirst(prefix.count))
        if asset == "none" || asset.isEmpty {
            selectMap(nil)
        } else if let map = maps.maps.first(where: { $0.assetName == asset }) {
            selectMap(map.id)
        } else {
            selectedMapAsset = asset
        }
    }

    /// Debug-only: fills in map progress so US-119's list can be screenshotted at its widest. The
    /// Simulator earns no steps at all, so a real save there shows sixteen rows of `0 / n` with
    /// fifteen of them locked — which shows neither the finished mark nor the six-digit progress
    /// line the story has to prove does not truncate.
    ///
    /// - `-mapListDemo` — every map walked to exactly its total and finished, so map 16 reads
    ///   `50000 / 50000`, the widest realistic figure, and every row is unlocked.
    /// - `-mapListPartialDemo` — the mixed state a real player is in: the first two maps finished,
    ///   the third part-walked and selected, the rest locked. Both marks, a lock and an unlock line
    ///   on one screen.
    /// - `-mapStripWidestDemo` — US-120's strip at its widest: every map finished and the LAST one
    ///   selected, so the row on the MAIN screen reads `Cyberpunk 50000 / 50000`. Does not push the
    ///   list.
    /// - `-mapProgressResetDemo` — the inverse, and it exists because the three above WRITE TO THE
    ///   SAVE. A demo flag with no way back poisons every screenshot taken on that container
    ///   afterwards, silently; see `seedMapDemoIfRequested`, which learned it the expensive way.
    ///
    /// Steps are credited through the shipped `MapStepCreditor`, and each fully walked map is then
    /// stamped finished with `markFinished` — because since US-203 walking a map to its total no
    /// longer finishes it (its boss does), and this demo is FOR the finished/unlocked list rather than
    /// for the boss fight. The stamp is the same one a boss win writes; the demo just skips the fight.
    private func seedMapListDemoIfRequested() {
        let arguments = CommandLine.arguments
        guard let profile else { return }

        if arguments.contains("-mapProgressResetDemo") {
            profile.clearForDemo()
            publishSelectedMap()
            try? store?.save()
            return
        }

        let partial = arguments.contains("-mapListPartialDemo")
        // US-120's widest strip: every map finished and the LAST one selected, so the main screen
        // reads `Cyberpunk 50000 / 50000` — the longest name this row can carry beside the widest
        // figure it can carry. It does NOT push the list, because what it is for is the row the list
        // is reached FROM. Same seed, same idempotency, same `-mapProgressResetDemo` inverse.
        let widest = arguments.contains("-mapStripWidestDemo")
        guard arguments.contains("-mapListDemo") || partial || widest else { return }

        // Cleared first, or the flag is not IDEMPOTENT: the selection and the counters are saved,
        // so a second launch adds a second map's worth on top of the first. The screenshot caught
        // exactly that — map 16 read `100000 / 50000` on the second run — and a doubled counter
        // still looks plausible, which is what makes it worth a line of code rather than a note.
        profile.clearForDemo()

        // Walked one map at a time through the real creditor — crediting the whole lot against one
        // selection would bank every step on that one map. Each fully walked map is then stamped
        // finished directly (US-203 moved the finish to the boss, and this demo stands in for the win),
        // so the unlock chain opens exactly as it does after a real boss is beaten.
        for (index, map) in maps.maps.enumerated() {
            if partial && index > 2 { break }
            profile.selectedMapId = map.id
            let fullyWalked = !(partial && index == 2)
            let steps = fullyWalked ? Double(map.totalSteps) : Double(map.totalSteps) / 3
            MapStepCreditor.credit(steps: steps, to: profile, catalog: maps, now: now())
            if fullyWalked { profile.markFinished(map.id, at: now()) }
        }
        if widest {
            selectMap(maps.maps.last?.id)
        } else {
            selectMap(partial ? maps.maps.dropFirst(2).first?.id : maps.maps.first?.id)
        }
    }

    /// Debug-only: fills the box so US-126's party screen can be screenshotted with the four states
    /// it has to show at once. Nothing in the shipped game puts a second Digimon in the box yet —
    /// US-128's drops are what will — so a real save on the Simulator has exactly one row.
    ///
    /// `-partyDemo` leaves the save holding: the active Digitama the game started at, a frozen
    /// Child, a frozen unhatched Digitama (AC6's row), and a DEAD Adult (AC5's). Four entries, three
    /// statuses, both kinds of untappable row.
    ///
    /// IDEMPOTENT, and it has to be: this flag WRITES TO THE SAVE, so a second launch would
    /// otherwise stack another three Digimon into the box and the screenshot would show seven. Every
    /// frozen record is cleared before the three are inserted, which also means the flag never
    /// touches the Digimon the player — or the previous demo — has out.
    private func seedPartyDemoIfRequested() {
        guard CommandLine.arguments.contains("-partyDemo"), let store else { return }
        let context = store.container.mainContext
        for stale in ((try? store.allStates()) ?? []) where !stale.isActive {
            context.delete(stale)
        }
        // Born before the active record, so birth order — which is the order the box is listed in —
        // puts the three seeded rows above the running game rather than in whatever order the
        // fetch happens to return them.
        let day: TimeInterval = 86_400
        let child = GameState(currentDigimonId: "agumon", stage: .child, isActive: false,
                              now: now().addingTimeInterval(-3 * day))
        let egg = GameState(currentDigimonId: "gabu_digitama", isActive: false,
                            now: now().addingTimeInterval(-2 * day))
        let gone = GameState(currentDigimonId: "greymon", stage: .adult, isActive: false,
                             now: now().addingTimeInterval(-1 * day))
        gone.healthStatus = .dead
        gone.diedAt = now()
        for state in [child, egg, gone] {
            context.insert(state)
        }
        try? store.save()
    }

    /// Debug-only: puts a fusable PAIR in the box so US-132's entry point and the ceremony it plays
    /// can be screenshotted. Nothing on the Simulator can raise two Ultimates, and a real save there
    /// never holds a pair any recipe names.
    ///
    /// - `-jogressDemo` — WarGreymon and MetalGarurumon, both frozen, which is the shipped
    ///   `wargreymon + metalgarurumon -> omegamon` recipe. Photographs the entry point offering it.
    /// - `-jogressListDemo` — the same box, with `ContentView` pushing the pair list on top of the
    ///   entry point, so `JogressOfferRow`'s three-sprite layout can be photographed on both screens.
    /// - `-jogressCeremonyDemo` — the same box, then the fusion PERFORMED through the real
    ///   `performJogress`, so what is photographed is the ceremony a real Jogress raises rather than
    ///   a hand-set `pendingEvolution` (which is what `-evolutionCeremonyDemo` is for).
    ///
    /// Deliberately leaves the Digimon the player has OUT alone, so the pair are two FROZEN records
    /// and the fusion exercises the case where neither parent was active — the one that would leave
    /// two Digimon out if `performJogress` did not freeze the survivors.
    ///
    /// IDEMPOTENT, like `-partyDemo` and for the reason US-119's screenshot found the hard way:
    /// this flag WRITES TO THE SAVE, so a second launch without the clear would stack a second pair
    /// into the box and the entry point would read "4 pairs ready".
    private func seedJogressDemoIfRequested() {
        let ceremony = CommandLine.arguments.contains("-jogressCeremonyDemo")
        let wants = ceremony
            || CommandLine.arguments.contains("-jogressDemo")
            // The pair list has nothing to draw without the same seeded box the entry point needs.
            || CommandLine.arguments.contains("-jogressListDemo")
        guard wants, let store else { return }
        let context = store.container.mainContext
        for stale in ((try? store.allStates()) ?? []) where !stale.isActive {
            context.delete(stale)
        }
        let day: TimeInterval = 86_400
        // Stages and sprites off the ROSTER rather than typed here, so the seed cannot disagree with
        // the file the offer is built from. Origins are the two eggs these two really hatch from,
        // which is what makes the returned egg meaningful in the shot.
        let pair = [("wargreymon", "agu_digitama"), ("metalgarurumon", "gabu_digitama")]
        for (index, (id, origin)) in pair.enumerated() {
            guard let entry = roster.entry(id: id) else { continue }
            context.insert(GameState(currentDigimonId: id, stage: entry.stage, isActive: false,
                                     originDigitamaId: origin,
                                     now: now().addingTimeInterval(-Double(3 - index) * day)))
        }
        try? store.save()

        guard ceremony, let offer = jogressBoard.offers.first else { return }
        performJogress(offer)
    }

    /// How long `-poopCleanDemo` waits before cleaning. Long enough to launch, settle and start
    /// taking screenshots; short enough that a burst does not have to run for a minute.
    private static let poopCleanDemoDelay: TimeInterval = 10

    /// Debug-only: puts a two-hour sleep window around the current moment and derives from it, so
    /// the Digimon is asleep NOW and stays asleep across the refresh every foregrounding runs.
    ///
    /// A window rather than `isAsleep = true` for exactly that reason — see `sleepScheduleOverride`.
    private func forceAsleepForDemo() {
        let parts = calendar.dateComponents([.hour, .minute], from: now())
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Modulo 1440, so a demo run at 00:30 or 23:30 wraps rather than going out of range.
        sleepScheduleOverride = SleepSchedule(bedtimeMinute: (minute + 1440 - 60) % 1440,
                                              wakeMinute: (minute + 60) % 1440)
        sleepSchedule = sleepScheduleOverride ?? .fallback
        // Cleared, because the demo store survives between launches: a `-sleepDemo` run within five
        // minutes of the last one would otherwise open on a Digimon still awake from that run's
        // Feed tap, which is the opposite of what this demo is for.
        state?.awakeUntil = nil
        isAsleep = sleepSchedule.isAsleep(at: now(), wokenUntil: state?.awakeUntil,
                                          calendar: calendar)
    }

    /// Debug-only: the inverse of `forceAsleepForDemo` — a sleep window on the far side of the clock
    /// from now, so the Digimon is definitely AWAKE and stays awake across every refresh.
    ///
    /// Needed because the demos run at whatever hour the screenshot pass happens to be taken, and the
    /// inferred window in a Simulator with no sleep history is the 22:00-07:00 fallback. An evening
    /// run without this screenshots the sleep block instead of the feature under test.
    private func forceAwakeForDemo() {
        let parts = calendar.dateComponents([.hour, .minute], from: now())
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Ten to twelve hours from now, modulo the day — a window that cannot contain this moment.
        sleepScheduleOverride = SleepSchedule(bedtimeMinute: (minute + 600) % 1440,
                                              wakeMinute: (minute + 720) % 1440)
        sleepSchedule = sleepScheduleOverride ?? .fallback
        isAsleep = sleepSchedule.isAsleep(at: now(), wokenUntil: state?.awakeUntil,
                                          calendar: calendar)
    }
    #endif

    /// Credits whatever health data has been earned since the last read.
    ///
    /// Safe to call as often as the app is opened, which is the point: US-014's ledger makes
    /// crediting a DELTA, so a second read with no new activity credits nothing rather than paying
    /// for the same steps twice.
    /// - Parameter background: true when this refresh is a background wake (a `BGAppRefreshTask` or a
    ///   HealthKit observer update) rather than the app coming to the front. It changes exactly one
    ///   thing at the tail: a due wild encounter raises a NOTIFICATION (US-205) instead of the on-screen
    ///   BATTLE/FLEE dialog, because there is no screen to put a dialog on. Everything else — crediting,
    ///   sickness, death, hatching, evolving — is identical, so a background wake and a foregrounding
    ///   never run two different versions of the rules.
    func refresh(background: Bool = false) async {
        guard let state, let ledger, let profile, !isRefreshing else { return }
        // A read is several awaits long, and scenePhase can go active again inside one (the app
        // being raised twice in quick succession). Two overlapping reads would both see the same
        // pre-credit ledger and could credit the same steps twice.
        isRefreshing = true
        defer { isRefreshing = false }

        // Captured before any rule runs, because the sickness notification is owed for the
        // TRANSITION into illness (AC2), not for being ill: a Digimon left sick for three days
        // must be told about once, not once per refresh.
        let healthBefore = state.healthStatus

        // FIRST, ahead of every clock: a Clean tapped on the watch face happened at some point
        // before this refresh, so it must land before anything ages the mess forward. See
        // `applyPendingCleanRequest`.
        applyPendingCleanRequest()

        // Before the read, not after: hunger is owed for time already elapsed, and the read is
        // several awaits long. Nothing here depends on the energy about to be credited.
        state.advanceHunger(now: now())

        await updateSleepState()

        // After the sleep window is known, because poop is paused while the Digimon sleeps and
        // `isAsleep` is what says so — running this before `updateSleepState` would charge the
        // stretch against last launch's answer. Like hunger, it is owed for time already elapsed,
        // so it is settled before the health read rather than after it.
        state.advancePoop(isAsleep: isAsleep, now: now())

        let dayReadings = await energySource.dayReadings(now: now())
        let readings = dayReadings.byEnergyType
        let credited = EnergyCreditor.credit(readings, to: state, profile: profile,
                                             ledger: ledger, now: now(), calendar: calendar)

        // US-179: the day's per-metric health reads, banked into the stage / lifetime / best-day
        // totals every `health.*` evolution condition is compared against. This is the ONE claimer of
        // these metrics off `MetricLedger` — the map, battle, train and clean charges below spend the
        // deltas `MetricCreditor` hands back rather than claiming a second time, so a step is
        // de-duplicated once and shared, never counted twice (AC3). The three daily quantities and
        // last night's sleep are seeded from the read the energy path already made, so nothing is read
        // from HealthKit twice in one refresh.
        let metrics = await healthReadings(dayReadings: dayReadings)
        conditionReadings = metrics
        // Nil only on a store that would not open its metric ledger, which is the same story that
        // leaves the map and charge paths idle below; `creditedMetrics` is then empty and every
        // consumer credits nothing, exactly as before this was wired.
        let creditedMetrics = metricLedger.map {
            MetricCreditor.credit(metrics, to: state, ledger: $0, now: now(), calendar: calendar)
        } ?? .zero
        // Beside the metric credit and off the SAME claimed deltas, because a map records the steps
        // that bought that energy — see `creditMapSteps`. Before the evolution and hatch checks below
        // only because everything is; nothing here depends on it.
        creditMapSteps(creditedMetrics[.healthSteps])
        // US-206, off the SAME claimed deltas again: everything this read brought in also accrues to
        // the map the player is standing in, which is what a map's Digitama conditions are measured
        // against. A second SPENDER of one claim, never a second claim — see `PlayerProfile.credit`.
        creditMapMetrics(creditedMetrics)
        // The exercise-to-training loop (US-177): the active calories this same read brought in buy
        // training charges on the Digimon that burned them, spent off the same claimed delta so a
        // calorie counts once as energy and once as a charge, never read twice.
        creditTrainCharges(creditedMetrics[.healthActiveEnergy])
        // The clean-to-handwash loop (US-178): the day's handwashing buys global cleaning charges,
        // off the same claimed delta as everything else — handwashing is a category event, read into
        // `metrics` alongside the rest rather than by a query of its own.
        creditCleanCharges(creditedMetrics[.healthHandwashing])
        // US-181: last night's sleep this read brought in accumulates on the Digimon that is OUT —
        // per-Digimon, off the SAME claimed delta as everything else, so a frozen Digimon accrues
        // nothing and last night's minutes are never counted twice. Distinct from the nightly sleep
        // energy `EnergyCreditor.credit` already banked above: this is the lifetime total the sleep
        // evolution gate (US-183) reads, that was a stage-energy top-up.
        state.creditSleep(minutes: creditedMetrics[.healthSleep])
        // After crediting and before evolving, because `careMistakeCount` is one of the things an
        // edge is gated on — an audit run after `evolveIfReady` would let a neglected Digimon take
        // a branch it had just disqualified itself from, one refresh late.
        state.auditCareMistakes(now: now(),
                                health: CareMistakes.HealthDataVerdict(readings.values),
                                calendar: calendar)
        // The fifth mistake, charged beside the other four and for the same reasons — see
        // `auditLights`, which is separate only because it needs the sleep window and that is the
        // model's to know rather than the saved game's.
        auditLights(state)
        // Straight after the audit and before evolving, for both of the same reasons: the mistake
        // that tips a Digimon over is usually one the audit has only just charged, and a sick
        // Digimon's evolution is paused — so a sickness settled after `evolveIfReady` would let it
        // evolve one refresh into an illness it already had.
        state.updateSickness(energyEarnedToday: ledger.creditedToday.total)
        // Straight after the illness is settled, because death only measures how long that illness
        // has run — and a cure decided above must be able to stop the countdown in the same refresh
        // it happened, rather than a Digimon dying of an illness it no longer has.
        state.updateDeath(now: now())
        // After both, so neither can be told to the user before the game itself has settled it —
        // and after `updateDeath` in particular, because a Digimon that has just been found dead
        // is past both messages.
        notifyHealthChanges(state, healthBefore: healthBefore)
        // Alongside the health notices and after `updateDeath` for the same reason: the mess notice
        // is decided from the settled state, and a Digimon just found dead is past being nagged.
        // The count it reads was settled by `advancePoop` above, and the claim it stamps is saved by
        // the same flush that saves that count.
        notifyPoop(state)
        // After `updateSleepState`, because both halves of it are asked about the sleep window this
        // refresh has just settled — and before the save, because the once-a-night marker it stamps
        // is what stops the next refresh sending the same nudge twice.
        notifyLights(state)
        // The pose is settled again here and not only in `updateSleepState`, because falling sick,
        // being cured or dying all change the resting pose too and are decided after the sleep
        // window.
        settleRestingPose()
        // The energy just credited may be what tips an egg over its hatch threshold or a Digimon
        // over an evolution's, so both run after crediting and before the save, letting one flush
        // persist the change. A hatch leaves the new Baby I with zero stage energy, so evolving in
        // the same refresh is a natural no-op — never a double move.
        hatchIfReady(state)
        evolveIfReady(state)
        // US-207 removed US-128's after-a-step drop check from here. A day's walking still moves the
        // map's counters and can turn a slot "Ready to find", but a refresh no longer awards
        // anything: an egg is found by winning a fight in the map, never by time or by steps
        // passing. See `checkForDigitamaDrop`.
        //
        // US-129, after `updateDeath`: the refresh that finds the last
        // Digimon dead is the moment the player has nothing left, so the egg is waiting by the time
        // the memorial is drawn. A no-op on every other refresh — see
        // `GameStore.grantFailsafeDigitamaIfStranded`.
        checkForStranding()
        do {
            try store?.save()
        } catch {
            // In-memory energy is kept: the ledger did not persist either, so the next launch
            // simply re-credits it. Losing a save is not worth taking the screen away from the
            // user, but it should not pass in silence.
            Self.log.error("Could not save after crediting: \(String(describing: error))")
        }
        Self.log.info("Refreshed health: credited \(credited.total) energy")
        // Last, once every rule above has settled: the complication must never show a Digimon
        // mid-refresh — hatched but not yet evolved, or sick but not yet dead.
        publishComplicationSnapshot()
        // US-203, checked BEFORE the wild encounter so the boss takes precedence when both are due:
        // once the player has walked the whole map and met every resident, the boss is what stands in
        // the way, and a wild foe should not appear over it. Like the wild check it persists nothing
        // (the encounter is not saved), so it runs after the flush above.
        checkForBossEncounter()
        // US-201, after the step accrual above credited this refresh's walking to the map: a wild
        // encounter greets the player if they have crossed 500 steps into it since the last one. It
        // sets no saved state (the encounter is not persisted), so it needs no flush of its own — it
        // runs after the save, over the settled game the snapshot above describes. Silent while a boss
        // is pending (its own guard), so the two dialogs never stack.
        //
        // US-205 splits foreground from background here: a foregrounding raises the on-screen dialog,
        // a background wake — where there is no screen — raises a local notification inviting the
        // player to open the app instead. The two are mutually exclusive by design; the notification
        // path stamps a saved marker for itself, so it flushes rather than leaning on the save above.
        if background {
            notifyWildEncounterIfDue()
        } else {
            checkForWildEncounter()
        }
    }

    /// Reads today's health metrics for `refresh`, seeded from the read the energy path already made.
    ///
    /// The three daily quantities (`health.steps` / `health.activeEnergy` / `health.exerciseMinutes`)
    /// and last night's sleep come straight off `dayReadings`, so a metric is not read from HealthKit
    /// twice in one refresh and the map, battle and train charges spend the SAME step and calorie
    /// totals the ledger banks. Everything else readable over today's window — distance, flights,
    /// stand hours, handwashing, and the standing measurements a running total cannot hold — is read
    /// here so a `health.*` condition on it has data too.
    ///
    /// Only `.value` reads are kept. A `.noData`/`.unavailable` answers nothing: it credits no total
    /// (`MetricCreditor` skips it anyway) and it must not be handed to `ConditionContext` as an
    /// `.unavailable`, which would switch on the "we were never allowed to look" override that turns
    /// an accumulating `atMost` gate to `.unknown` — that is US-180's call, not this story's.
    private func healthReadings(dayReadings: HealthDayReadings) async -> [ConditionMetric: HealthReading] {
        var raw: [ConditionMetric: HealthReading] = [
            .healthSteps: dayReadings.quantities[.steps] ?? .noData,
            .healthActiveEnergy: dayReadings.quantities[.activeEnergy] ?? .noData,
            .healthExerciseMinutes: dayReadings.quantities[.exercise] ?? .noData,
            .healthSleep: dayReadings.sleep,
        ]
        let interval = HealthDay.interval(containing: now(), calendar: calendar)
        let rest = ReadableHealthMetric.all.filter { raw[$0.metric] == nil }
        for (metric, reading) in await metricReader.readings(of: rest, in: interval) {
            raw[metric] = reading
        }
        return raw.filter { if case .value = $0.value { return true } else { return false } }
    }

    /// Accrues the steps this read brought in to the map the player is adventuring in (US-118).
    ///
    /// `steps` is the delta `MetricCreditor` already claimed off `MetricLedger` this refresh — the
    /// ledger that remembers what of today's STEP TOTAL has been banked. That shared claim is the
    /// whole point: a health reading is a cumulative day total — 4,000 steps at noon and still those
    /// same 4,000 at 18:00 — so crediting the reading each refresh would gain 4,000 every launch. The
    /// metric totals, the map and the battle charges all spend this one delta rather than each
    /// claiming its own.
    ///
    /// Called from `refresh` alone, so the map is credited from the same read that bought the
    /// energy — and only ever the map that is selected AT THE MOMENT OF THE READ. Steps banked
    /// while a different map was selected stay where they were put: nothing here can reach them,
    /// because the ledger has already spent them and only the counter they landed on remembers.
    private func creditMapSteps(_ steps: Double) {
        guard let profile else { return }
        MapStepCreditor.credit(steps: steps, to: profile, catalog: maps, now: now())
        // The SAME claimed delta also buys battle charges (US-176). Credited to `state`, the Digimon
        // that is OUT, so charges are per-Digimon and the one who walked them is the one who keeps
        // them; a frozen Digimon does not refresh and so accrues nothing.
        let config = ConsumptionConfig.bundled
        state?.creditBattleCharges(steps: steps, stepsPerCharge: config.stepsPerBattleCharge,
                                   maxCharges: config.maxBattleCharges)
    }

    /// Accrues this read's per-metric deltas to the map the player is adventuring in (US-206).
    ///
    /// `credited` is what `MetricCreditor` just banked off the shared `MetricLedger` — the same
    /// deltas the stage, lifetime, map-step and charge paths spend — so a metric is de-duplicated
    /// once and shared, exactly as `creditMapSteps` documents. Only the map SELECTED AT THE MOMENT OF
    /// THE READ is credited, which is what stops progress leaking between maps: what was walked while
    /// another map was chosen stays on that map's counter, because the ledger has already spent it
    /// and only the counter it landed on remembers.
    private func creditMapMetrics(_ credited: MetricTotals) {
        guard let profile, let mapId = profile.selectedMapId, maps.map(id: mapId) != nil else {
            return
        }
        profile.credit(credited, forMap: mapId)
    }

    /// Adds one care counter's tick to the selected map (US-206) — a training session, a refusal or a
    /// sleep disturbance, credited beside the global counter the same act moves on `GameState`.
    ///
    /// Silent with nowhere selected, or with a selection the catalog no longer knows: a tick with no
    /// map to land on is dropped rather than parked somewhere it could later be mistaken for real
    /// progress, which is `MapStepCreditor`'s rule applied to the care counters.
    private func creditMapCare(_ metric: ConditionMetric) {
        guard let profile, let mapId = profile.selectedMapId, maps.map(id: mapId) != nil else {
            return
        }
        profile.credit(metric, forMap: mapId)
    }

    /// Converts the active calories this read brought in into training charges (US-177).
    ///
    /// `kcal` is the delta `MetricCreditor` claimed off the shared `MetricLedger` this refresh, so
    /// nothing double-counts it, and it buys charges at `kcalPerTrain` on `state` — the Digimon that
    /// is OUT, so a charge is per-Digimon and a frozen Digimon (which does not refresh) accrues
    /// nothing.
    private func creditTrainCharges(_ kcal: Double) {
        guard let state else { return }
        let config = ConsumptionConfig.bundled
        state.creditTrainCharges(kcal: kcal, kcalPerCharge: config.kcalPerTrain,
                                 maxCharges: config.maxTrainCharges)
    }

    /// Converts the day's handwashing count into global cleaning charges (US-178).
    ///
    /// `events` is the handwashing delta `MetricCreditor` claimed off the same `MetricLedger` as
    /// every other metric this refresh, so refreshing twice does not count the same washes again —
    /// the identical de-duplication the step and calorie paths lean on. It buys charges at
    /// `handwashPerCleanCharge` on the PROFILE, not on `state`: a habit is the player's, so every
    /// Digimon in the box cleans out of the one banked larder of washes.
    private func creditCleanCharges(_ events: Double) {
        guard let profile else { return }
        let config = ConsumptionConfig.bundled
        profile.creditCleanCharges(events: events, eventsPerCharge: config.handwashPerCleanCharge,
                                   maxCharges: config.maxCleanCharges)
    }

    /// Chooses the map the Digimon is adventuring in, from here on.
    ///
    /// Not retroactive, and that is the design: steps already credited to the previous map stay
    /// there. Only what is read AFTER this accrues to the new one, which is what makes a map a
    /// place you went rather than a filter over your day.
    ///
    /// Passing an id the catalog does not know, or nil, leaves the player nowhere — legal, and what
    /// a fresh save already is. US-120's list is the caller.
    func selectMap(_ id: String?) {
        guard let profile else { return }
        profile.selectedMapId = id
        publishSelectedMap()
        do {
            try store?.save()
        } catch {
            // In-memory selection is kept: the screen already shows the new map, and the next
            // refresh saves it. Same call as `refresh`'s — a failed flush is not worth taking the
            // screen away from the user, but it does not pass in silence.
            Self.log.error("Could not save the map selection: \(String(describing: error))")
        }
    }

    /// The player's whole earnings, or zero before `start()` has opened the profile.
    ///
    /// One read for every caller that needs it — `battlePower`, the memorial, the battle seed
    /// search — so there is a single place the "no profile yet" answer is decided. Zero is the
    /// honest reading of it: a player whose profile has not been opened has earned nothing yet as
    /// far as this screen can tell.
    var lifetimeEnergy: EnergyTotals { profile?.lifetimeEnergy ?? .zero }

    /// The active Digimon's age in "years" against the injectable clock (US-200): one per whole real
    /// day since it hatched, 0 before there is a state to read. Computed here so the view reads the
    /// same clock the model settles the game on, rather than reaching for `Date()` of its own.
    var ageYears: Int { state?.ageYears(now: now()) ?? 0 }

    /// The global meat larder (US-174), or zero before `start()` has opened the profile — the
    /// number the feed DashBar fills and `FeedAction` spends. Zero is the honest reading: a player
    /// whose profile has not been opened has an empty larder as far as this screen can tell.
    var meat: Int { profile?.meat ?? 0 }

    /// The most meat the larder shows, and so the total of the feed DashBar (US-174). Read off the
    /// shipped `ConsumptionConfig` rather than hard-coded so retuning the economy is a data edit,
    /// the same source the drop range and the caps come from.
    var meatCap: Int { ConsumptionConfig.bundled.meatCap }

    /// The global cleaning charges (US-178), or zero before `start()` has opened the profile — the
    /// number the clean DashBar fills and `clean()` spends. Global like `meat`, so it does not depend
    /// on which Digimon is out. Zero is the honest reading before a profile exists.
    var cleanCharges: Int { profile?.cleanCharges ?? 0 }

    /// The most cleaning charges the bar shows, and so the total of the clean DashBar (US-178). Off
    /// the shipped `ConsumptionConfig`, the same source `meatCap` reads, so the economy retunes as
    /// data.
    var cleanChargeCap: Int { ConsumptionConfig.bundled.maxCleanCharges }

    /// The active Digimon's spendable battle charges (US-176) — the number the charge DashBar fills
    /// and `battle()` spends. Off `state`, so switching which Digimon is out shows ITS charges and
    /// never another's. Zero before `start()` has opened a Digimon.
    var battleCharges: Int { state?.battleCharges ?? 0 }

    /// The most charges the bar shows, and so the total of the battle DashBar (US-176). Off the
    /// shipped `ConsumptionConfig`, the same source `meatCap` reads, so the economy retunes as data.
    var battleChargeCap: Int { ConsumptionConfig.bundled.maxBattleCharges }

    /// The active Digimon's spendable training charges (US-177) — the number the train DashBar fills
    /// and `TrainAction.begin` spends. Off `state`, so switching which Digimon is out shows ITS
    /// charges and never another's. Zero before `start()` has opened a Digimon.
    var trainCharges: Int { state?.trainCharges ?? 0 }

    /// The most charges the train bar shows, and so its total (US-177). Off the shipped
    /// `ConsumptionConfig`, the same source `battleChargeCap` reads.
    var trainChargeCap: Int { ConsumptionConfig.bundled.maxTrainCharges }

    /// The active Digimon's accumulated HealthKit sleep in whole hours (US-182), what the main-screen
    /// Zz DashBar fills. Off `state`, so switching which Digimon is out shows ITS lifetime sleep
    /// (US-181) and never another's. Floored to a whole hour because the bar counts hour dashes; the
    /// fractional part lives on until it rounds up. Zero before `start()` has opened a Digimon.
    var sleepHours: Int { Int(state?.accumulatedSleepHours ?? 0) }

    /// The total of the main-screen Zz DashBar (US-182): a nominal display ceiling in hours, so the
    /// bar reads as an at-a-glance "how rested is this Digimon" rather than the exact evolution gate.
    /// The precise `required`-vs-`earned` sleep bar belongs to the detail view (US-183); this one just
    /// needs a fixed number of dashes to fill, and 16 is the headline requirement the PRD authors
    /// against (Agumon needs 16 h). A constant and not a `GameState` value — every Digimon's main-screen
    /// bar is the same length, only its fill differs.
    var sleepHoursCap: Int { Self.sleepHoursDisplayCap }

    /// The nominal full-bar sleep in hours for the main-screen Zz DashBar — see `sleepHoursCap`.
    static let sleepHoursDisplayCap = 16

    /// The id of the Digimon currently out, or `""` before `start()` has opened one (US-214).
    ///
    /// The Sleep Time screen's schedule is derived from this and nothing else, so switching who is
    /// out switches the bedtime shown alongside that Digimon's own banked hours. A String rather
    /// than an optional because `SleepRoutine.forDigimon(id:)` is total: there is no id for which
    /// the screen would rather show nothing.
    var activeDigimonId: String { state?.currentDigimonId ?? "" }

    /// Every Digitama the player currently HOLDS (US-127) — an unhatched egg in the box, or any
    /// living Digimon that hatched from one. The seam US-128's drop engine filters a map's slots
    /// against so a held egg is never dropped a second time. Empty before `start()` has opened the
    /// store, which is the honest reading: nothing is held until the box exists.
    var heldDigitamaIds: Set<String> { (try? store?.heldDigitamaIds()) ?? [] }

    /// The one open `GameStore`, handed to the side screens (the Dex) so they read the live game
    /// through THIS model's context instead of opening a second `GameStore` on the same file. Two
    /// live contexts on one store is the US-193 crash: a `GameState` fetched through one is
    /// invalidated when the other resets, the `ModelContext.reset` fatal error. See `GameSession`
    /// in `DigiVPetApp` — one model, one store, one context — which is the invariant this preserves.
    ///
    /// Throws before `start()` has opened the store, which the Dex never hits: its toolbar button
    /// only draws in `.playing`, and the store is open by then. A `throws` rather than a force
    /// unwrap so the Dex, which already degrades a store failure to an all-undiscovered grid, keeps
    /// that graceful fallback instead of crashing.
    func sharedStore() throws -> GameStore {
        guard let store else { throw SideScreenStoreError.notOpen }
        return store
    }

    /// The sixteen maps as `MapListView` draws them (US-119): catalog order, with the save's
    /// counters, finish stamps and selection folded in.
    ///
    /// Computed rather than published, because everything it reads is already observable — the
    /// catalog is a constant and `PlayerProfile` is a `@Model`, so a view that builds this inside
    /// `body` redraws when a step is credited to it.
    var mapRows: [MapListRow] {
        MapListRow.rows(in: maps, progress: profile)
    }

    /// Where the Digimon is adventuring and how far across it it has walked (US-120): the selected
    /// map, or the first map as a prompt when the player has chosen nowhere.
    ///
    /// Named for the strip it once fed, which US-210 deleted; what reads it now is the green
    /// `DashRing` around the grid's Map button (US-212), off `recordedSteps`/`totalSteps`.
    ///
    /// Computed off the same injected catalog and the same `PlayerProfile` as `mapRows`, and for the
    /// same reason: both are already observable, so a step credited to the selected map moves the
    /// bar and the list together rather than through two published copies that can drift.
    ///
    /// Nil only for an empty catalog, which the shipped file cannot be — the bar simply is not
    /// drawn, rather than drawing a reading with nothing behind it.
    var mapStrip: MapStrip? {
        MapStrip.make(in: maps, progress: profile)
    }

    /// The box of Digimon as `PartyView` draws it (US-126): every owned Digimon and every unhatched
    /// Digitama, oldest first, with the one that is out marked.
    ///
    /// Computed rather than published, for `mapRows`' reason: everything it reads is already
    /// observable — the graph is a constant and each `GameState` is a `@Model` — so a screen that
    /// builds this inside `body` redraws when a Digimon in the box changes. The fetch behind it is
    /// a handful of records, and the party screen is not a place the player stays.
    var partyRows: [PartyRow] {
        PartyRow.rows(for: boxedStates, in: graph, roster: roster)
    }

    /// Every saved Digimon, in the order `PartyRow.id` indexes. One accessor, so the list the rows
    /// were built from and the list `activate(_:)` indexes into can never be two different orders.
    private var boxedStates: [GameState] {
        (try? store?.allStates()) ?? []
    }

    /// Puts the Digimon on this row out, freezing whichever one was out before (US-126 AC3).
    ///
    /// The switch itself is `GameStore.activate(_:now:)` and nothing here: one saved transaction
    /// moves both `isActive` flags AND both freeze clocks, so a crash mid-switch cannot leave the
    /// box with zero Digimon out or two. All this adds is which record the row means, and telling
    /// the screen about it afterwards.
    ///
    /// An unhatched Digitama is activated by exactly this path, which is what starts it hatching
    /// (AC6): the egg becomes the state `refresh()` credits energy to, and `hatchIfReady` is what
    /// the next refresh runs on it. Nothing here has to know it is an egg.
    ///
    /// A row that is not selectable — the active one, or a dead one — is refused rather than
    /// activated, which is AC4 and AC5 at the seam rather than only in the view.
    ///
    /// - Returns: whether the Digimon on this row is now the one out.
    @discardableResult
    func activate(_ row: PartyRow) -> Bool {
        guard let store, row.isSelectable else { return false }
        let states = boxedStates
        // The row has to still DESCRIBE the record at its position, not merely be in range. The
        // box's order is birth order, and US-125's thaw moves a Digimon's birth date forward by the
        // span it spent frozen — so taking one out really does reorder the list. A tap carried over
        // from a stale list would otherwise activate whichever Digimon had moved into that slot.
        guard row.id >= 0, row.id < states.count,
              PartyRow.rows(for: states, in: graph, roster: roster)[row.id] == row else { return false }
        let target = states[row.id]
        do {
            try store.activate(target, now: now())
            state = target
            // Cleared rather than left standing: a ceremony still pending from the Digimon being
            // put AWAY would otherwise play over the one just taken out, crediting it with an
            // evolution that happened to somebody else. Same rule as `dismissMemorial`'s.
            pendingEvolution = nil
            // The screen is holding the previous Digimon's pose — which may be a sleep loop or the
            // dead frame — so it is settled from the new one's own health before it is drawn.
            animation = restingAnimation
            publishComplicationSnapshot()
            Self.log.info("Activated \(target.currentDigimonId)")
            return true
        } catch {
            // The store put every flag back the way it was, so the box is exactly as it stood and
            // the screen still shows the Digimon that is really out. Worth a line, not worth taking
            // the screen away from the player.
            Self.log.error("Could not change which Digimon is out: \(String(describing: error))")
            return false
        }
    }

    /// What the party screen's Jogress entry point offers (US-132): every pair in the box that
    /// matches a recipe, is both alive and has its conditions met — or the one line saying why there
    /// is none.
    ///
    /// Computed rather than published, for `partyRows`' reason: the catalog and the roster are
    /// constants and each `GameState` is a `@Model`, so a screen that builds this inside `body`
    /// redraws when the box changes.
    var jogressBoard: JogressBoard {
        JogressBoard.make(for: boxedStates, catalog: jogress, roster: roster) {
            ConditionContext(state: $0, now: self.now(), calendar: self.calendar,
                             readings: self.conditionReadings)
        }
    }

    /// Fuses the pair on this offer (US-132): both parents leave the box, the result comes out as the
    /// Digimon the player has out, and one of the two eggs comes back.
    ///
    /// The transaction itself is `GameStore.performJogress` and nothing here — one save, so a crash
    /// cannot land between losing two Digimon and gaining one. All this adds is which records the
    /// offer means, the ceremony the screen plays, and the failsafe check afterwards.
    ///
    /// THE OFFER IS RE-DERIVED FROM THE LIVE BOX BEFORE IT IS ACTED ON, which is `activate(_:)`'s
    /// staleness rule applied to a pair rather than to a row — and it matters more here, because
    /// this CONSUMES what it indexes. Taking a Digimon out reorders the box (US-125's thaw moves a
    /// birth date), so a party screen held across one switch could otherwise offer up two Digimon
    /// the player never chose. An offer the box no longer makes is refused, not adjusted.
    ///
    /// AC7: the ceremony is `EvolutionCeremonyView`'s, raised the same way a hatch or an evolution
    /// raises it — the fusion is a "you are now something new" moment and the screen already knows
    /// how to play one. Both forms come through `presentation(forId:)`, which falls back to the
    /// roster: every Jogress participant is an Ultimate the 88-node graph has never heard of (the
    /// Codebase Patterns' first rule), so a graph-only lookup would be nil for all of them and the
    /// ceremony would be skipped on every fusion in the game.
    ///
    /// - Returns: whether the fusion happened.
    @discardableResult
    func performJogress(_ offer: JogressOffer) -> Bool {
        guard let store, jogressBoard.offers.contains(offer) else { return false }
        let states = boxedStates
        guard offer.first.rowId < states.count, offer.second.rowId < states.count else { return false }
        let first = states[offer.first.rowId]
        let second = states[offer.second.rowId]
        guard let recipe = jogress.recipe(for: first.currentDigimonId,
                                          and: second.currentDigimonId) else { return false }
        var generator = makeJogressGenerator()
        do {
            let outcome = try store.performJogress(recipe, parents: (first, second), roster: roster,
                                                   now: now(), using: &generator)
            state = outcome.result
            // Kept in step with the store the way `advance` and the drop check do, so the Dex and
            // US-121's map detail reveal both the fusion and the returned egg at once rather than at
            // the next launch.
            discoveredDigimonIds.insert(outcome.result.currentDigimonId)
            discoveredDigimonIds.insert(outcome.returnedDigitamaId)
            // The form left behind is the FIRST parent — the one nearer the top of the party list,
            // so the ceremony fades out of the Digimon the player picked first rather than out of
            // whichever id happened to sort earlier.
            if let from = presentation(forId: offer.first.digimonId),
               let to = presentation(forId: outcome.result.currentDigimonId) {
                pendingEvolution = EvolutionEvent(from: from, to: to)
            }
            // The screen is holding a pose belonging to a Digimon that no longer exists.
            animation = restingAnimation
            // AC8. A no-op by construction — the fusion is alive and in the box, so the player is
            // not stranded — and called anyway, because "the box just changed shape" is exactly the
            // moment US-129 exists for and a later change to what a Jogress consumes must not have
            // to remember to add it.
            checkForStranding()
            publishComplicationSnapshot()
            Self.log.info("Jogress: \(outcome.consumedIds.joined(separator: " + ")) -> \(outcome.result.currentDigimonId), \(outcome.returnedDigitamaId) returned")
            return true
        } catch {
            // The store left the box exactly as it stood — every refusal is decided before the first
            // mutation, and a failed write is rolled back — so the two parents are still there and
            // the screen is still true. Worth a line, not worth taking the screen away from the
            // player.
            Self.log.error("Could not perform the Jogress: \(String(describing: error))")
            return false
        }
    }

    /// The map the next battle draws its opponents from (US-122), or nil for "nowhere chosen yet" —
    /// which is the roster-wide pick this game had before maps existed.
    ///
    /// A selection naming a map the catalog no longer holds reads as nil too, for the same reason
    /// `MapStepCreditor` drops a delta with nowhere to go: a retired map id is not a place to fight.
    private var selectedMap: AdventureMap? {
        profile?.selectedMapId.flatMap { maps.map(id: $0) }
    }

    /// Steps banked in the selected map, which is the numerator of US-122's progress ratio.
    private var selectedMapRecorded: Double {
        guard let profile, let id = profile.selectedMapId else { return 0 }
        return profile.recorded(forMap: id)
    }

    /// What one map's detail screen draws (US-121), or nil if the map is locked — which is what
    /// "a locked map has no reachable detail view" means at the seam the view pushes from.
    ///
    /// A function of the row rather than of an id, because the lock is a fact about the row and
    /// `MapDetail.make` reads it rather than deciding it a second way.
    func mapDetail(for row: MapListRow) -> MapDetail? {
        MapDetail.make(for: row, in: maps, roster: roster,
                       discovered: mapDetailDiscoveries, met: mapDetailMet(for: row),
                       held: mapDetailHeld, context: mapDetailContext(for: row.id))
    }

    /// The Digitama in the box, for the "Found" mark US-207 puts over a held slot's conditions.
    ///
    /// The same `heldDigitamaIds` the drop engine is handed, so the screen cannot mark an egg found
    /// that the engine would still drop — one read, one truth.
    private var mapDetailHeld: Set<String> {
        #if DEBUG
        return heldDigitamaIds.union(Self.mapDetailDemoHeld)
        #else
        return heldDigitamaIds
        #endif
    }

    /// The residents of `row`'s map the player has met (US-202), plus whatever `-mapDetailFoesDemo`
    /// pretends to. Read off the profile per map — a meeting on one map does not reveal the same
    /// Digimon on another, which is why this is keyed and not a flat Dex read.
    private func mapDetailMet(for row: MapListRow) -> Set<String> {
        let saved = profile?.metDigimon(forMap: row.id) ?? []
        #if DEBUG
        return saved.union(mapDetailDemoMet(for: row))
        #else
        return saved
        #endif
    }

    /// The ids a map detail treats as met. The Dex, plus whatever `-mapDetailDemo` pretends to.
    private var mapDetailDiscoveries: Set<String> {
        #if DEBUG
        return discoveredDigimonIds.union(Self.mapDetailDemoDiscoveries)
        #else
        return discoveredDigimonIds
        #endif
    }

    /// The counters ONE map's hints are warmed against (US-206): that map's own progress, read the
    /// same way `checkForDigitamaDrop` reads it, so a slot the detail screen promises is "Ready to
    /// find" is exactly the slot that can drop.
    ///
    /// Map-scoped rather than the whole-life `ConditionContext(state:)` an evolution is judged on:
    /// a map's egg is a question about what has been done in that map, and the global counters
    /// answered it "yes" for a veteran the instant a new map was selected. See
    /// `ConditionContext.mapScoped`.
    ///
    /// `.unknown` before `start()` has a profile — every condition then reads as unearned, which is
    /// the honest answer for a game that has not begun.
    private func mapDetailContext(for mapId: String) -> ConditionContext {
        #if DEBUG
        if let demo = Self.mapDetailDemoContext { return demo }
        #endif
        guard let profile else { return .unknown }
        return .mapScoped(mapId, profile: profile,
                          lightState: state?.lightState, readings: conditionReadings)
    }

    #if DEBUG
    /// Whether any of US-121's three screenshot flags is present. `-mapDetailSlotsDemo` and
    /// `-mapDetailFoesDemo` are `-mapDetailDemo` scrolled to the eggs and to the pool — same
    /// screen, same seeding, a different scroll position — so the two below must answer to all
    /// three, or a scrolled shot is a photograph of an unseeded screen.
    private static var isMapDetailDemo: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("-mapDetailDemo")
            || arguments.contains("-mapDetailSlotsDemo")
            || arguments.contains("-mapDetailFoesDemo")
    }

    /// Debug-only: the part-met totals `-mapDetailDemo` draws the Digitama hints against, or nil
    /// when the flag is absent.
    ///
    /// The Simulator has no HealthKit data at all, so a real game there earns nothing and every
    /// slot on the screen would read `far` — which is a photograph of one third of the story. This
    /// puts 2,100 steps on the best day of the stage, which clears `01_grassland`'s Patamon slot
    /// (`health.steps day atLeast 2000`) and so marks it READY, while its Palmon slot
    /// (`care.battleCount stage atLeast 1`) stays unearned and its Agumon slot is revealed by the
    /// starting egg's own Dex entry. One screenshot, all three states.
    ///
    /// A context literal rather than seeded state, so it cannot write a fake game to the store —
    /// the same discipline, and the same reason, as `DexModel.revealDemoContext`. Since US-206 the
    /// real screen reads `ConditionContext.mapScoped` instead, so what this stands in for is 2,100
    /// steps walked IN THAT MAP; the numbers and the picture are unchanged, because a `.day` window
    /// is answered off `bestDayThisStage` either way.
    private static var mapDetailDemoContext: ConditionContext? {
        guard isMapDetailDemo else { return nil }
        return ConditionContext(bestDayThisStage: MetricTotals(values: [
            ConditionMetric.healthSteps.rawValue: 2_100,
        ]))
    }

    /// Debug-only: the Digitama `-mapDetailDemo` pretends the player has raised, so the screenshot
    /// has a REVEALED slot beside its two withheld ones.
    ///
    /// A brand-new save discovers exactly one Digitama — the egg it was handed — and which one is
    /// RANDOM among the graph's six, of which only three live in the starting map. So a fresh
    /// install shows a revealed slot about half the time, which is no good for a photograph that
    /// has to show the mix every time.
    ///
    /// Unioned into the read rather than written to the Dex, and for the reason
    /// `mapDetailDemoContext` is a literal: a flag that seeds the store leaves the container
    /// poisoned for every screenshot taken on it afterwards, which US-119 learned the expensive way.
    /// Nothing here reaches disk, so there is nothing to undo.
    private static var mapDetailDemoDiscoveries: Set<String> {
        isMapDetailDemo ? ["agu_digitama"] : []
    }

    /// Debug-only: the Digitama `-mapDetailDemo` pretends are in the box, so the screenshot has a
    /// HELD slot — art, "Found", and its condition line still under it, which is US-207's whole
    /// point — beside the ready one and the withheld one.
    ///
    /// The same egg `mapDetailDemoDiscoveries` reveals, because the two states stack: an egg can
    /// only read "Found" on a row that has art to put it beside. A fresh save's own starting egg
    /// hatches immediately, so nothing is really held on the Simulator and a real screen would
    /// photograph the mark's absence. Unioned into the read, never written — same rule as above.
    private static var mapDetailDemoHeld: Set<String> {
        isMapDetailDemo ? ["agu_digitama"] : []
    }

    /// Debug-only: the residents `-mapDetailFoesDemo` pretends the player has met, so the pool shot
    /// shows the US-202 MIX — real art beside withheld "?" rows — every time rather than a wall of
    /// "?" (the Simulator earns no steps, so a real save there has met nobody).
    ///
    /// Every OTHER resident of the map, by pool order, so any stage group with two or more members
    /// straddles the two states. Instance rather than static because the mix is a fact about the
    /// map being viewed, and read off the catalog rather than typed so it cannot name a resident the
    /// map does not field. Nothing here reaches disk, matching `mapDetailDemoDiscoveries`.
    private func mapDetailDemoMet(for row: MapListRow) -> Set<String> {
        guard Self.isMapDetailDemo, let map = maps.map(id: row.id) else { return [] }
        return Set(map.opponentPool.enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map(\.element))
    }
    #endif

    /// Republishes the background asset from the saved selection. The one place the two are joined.
    private func publishSelectedMap() {
        selectedMapAsset = profile?.selectedMapId.flatMap { maps.map(id: $0)?.assetName }
    }

    /// The pose the Digimon returns to when nothing else is happening: the slow hurt loop while it
    /// is sick, the sleep loop (sleep1 <-> sleep2) while it is in its sleep window, the walk loop
    /// otherwise, and the hurt2 frame held still once it is dead.
    ///
    /// Everything that ends an action reverts to THIS rather than to `.idle`, which is what keeps a
    /// Digimon fed at 23:59 from going back to pacing about.
    ///
    /// The rule itself lives on `SpriteAnimation.resting(for:isAsleep:)` — a pure function of the
    /// two facts it turns on, which is what lets it be tested without a store or a view. All this
    /// adds is where those two facts come from. No game at all rests the same as a healthy one.
    var restingAnimation: SpriteAnimation {
        .resting(for: state?.healthStatus ?? .healthy, isAsleep: isAsleep)
    }

    /// Whether the Digimon should be walking about the screen right now (US-037).
    ///
    /// Expressed as "the pose is the plain idle walk, and nothing is covering the screen" rather
    /// than as a list of the states that forbid it. That is not a shortcut — it is the same fact
    /// said once instead of twice. Sleeping, sickness and death are ALREADY exactly what makes
    /// `restingAnimation` return something other than `.idle`, so a state added to that switch
    /// later suspends movement automatically instead of needing to be remembered here — US-068 gave
    /// sickness a LOOP rather than a held frame and did not have to touch this line, which is the
    /// arrangement paying for itself. Eating and
    /// every other momentary pose fall out of the same rule for free: a Digimon holding still to
    /// eat should not slide across the screen while it does.
    ///
    /// The four overlays are checked because a battle, a ceremony, a training round or a memorial has
    /// the screen, and a sprite pacing on unseen underneath it is work spent drawing nothing. Each
    /// clears on its own, at which point this returns true again and the walk resumes from where it
    /// stood.
    ///
    /// A Digitama is the one suspension the pose does NOT already say (US-217). An egg's resting
    /// animation is the plain `.idle` loop — the wobble — so every clause below is happily true
    /// while it sits there, and the egg used to pace the floor on legs it does not have. Naming the
    /// stage is therefore an ADDED condition rather than a replacement: asleep, eating, sick, dead
    /// and every overlay still turn the walk off through exactly the reasons they always did.
    var isWandering: Bool {
        state?.stage != .digitama
            && animation == .idle && pendingEvolution == nil && pendingBattle == nil
            && pendingTraining == nil && pendingBattleRound == nil && memorial == nil
            && pendingWildEncounter == nil && pendingBossEncounter == nil
    }

    /// Every pose `settleRestingPose` is allowed to swap out. Exactly the poses `restingAnimation`
    /// can return — miss one and a Digimon that entered that state keeps holding it after leaving,
    /// which is how a reborn egg would go on lying dead.
    private static let restingPoses: Set<SpriteAnimation> = [
        .idle, .sleep, .sick, .still(.hurt2)
    ]

    /// Re-infers the sleep window from last night's sleep and puts the Digimon into or out of it.
    ///
    /// Runs on every `refresh()`, i.e. every time the app comes to the front. That is enough to be
    /// right whenever anyone is looking: nothing observes the window closing while the screen is
    /// dark, and US-033's background refresh is what will re-evaluate it without a foreground.
    private func updateSleepState() async {
        let block = await energySource.lastNightSleepBlock(now: now())
        // A night too short to be a habit, or no night at all, both land on 22:00-07:00. Neither
        // tells us anything about when this user sleeps, so neither should move the window.
        let inferred = block.flatMap { SleepSchedule(inferredFrom: $0, calendar: calendar) } ?? .fallback
        #if DEBUG
        sleepSchedule = sleepScheduleOverride ?? inferred
        #else
        sleepSchedule = inferred
        #endif
        // Through `isAsleep(at:wokenUntil:)` and NEVER through `contains` alone. This is the line a
        // wake lives or dies on: `refresh()` runs on every foregrounding and on every background
        // wake, so asking the window by itself here would put a Digimon the user was charged a care
        // mistake for waking straight back to sleep, seconds later and without a tap.
        isAsleep = sleepSchedule.isAsleep(at: now(), wokenUntil: state?.awakeUntil,
                                          calendar: calendar)

        settleRestingPose()
    }

    /// Swaps whichever resting pose is on screen for the one that is now current.
    ///
    /// Only a RESTING pose is swapped. An eat loop or an attack pose mid-action is left alone, and
    /// its own timer reverts it to whichever resting pose is current by then.
    ///
    /// Called both after the sleep window is re-derived and after sickness is settled, because
    /// either can change the answer and the two are decided at different points of a refresh.
    private func settleRestingPose() {
        if Self.restingPoses.contains(animation) {
            animation = restingAnimation
        }
    }

    /// Feeds the Digimon: spends Vitality, takes a unit off hunger, and plays the eat loop with a
    /// light tap.
    ///
    /// Returns the outcome so a test can assert on it directly; the screen reacts to `animation` and
    /// `actionMessage` instead. A refusal or a block still saves nothing new in the energy sense but
    /// is still flushed, because a refusal increments a counter US-027 will read on a later launch.
    @discardableResult
    func feed() -> FeedOutcome? {
        guard let state, let profile else { return nil }
        // FIRST, so the meal is really eaten rather than the user paying a care mistake for a block
        // (US-110). `FeedAction` is handed the woken answer, so its own sleep arm never fires from
        // here — see `wakeIfAsleep`, which is also where the dead case is kept out.
        wakeIfAsleep()
        let outcome = FeedAction.feed(state, profile: profile, isAsleep: isAsleep,
                                      now: now(), calendar: calendar)

        switch outcome {
        case .fed:
            playFeedHaptic()
            // The eat loop swaps the frames; the chew dips the whole sprite into the bowl between
            // them, so a meal is something the Digimon does rather than something its art does.
            show(.eat, motion: .chew, message: nil)
        case .refused:
            // A refusal is an overfeed, counted on the map it happened in as well as on the Digimon
            // (US-206) — `05_wasteland`'s and `15_dungeon`'s eggs are gated on exactly this.
            creditMapCare(.careOverfeeds)
            // The refuse pose alternates with the walk frame, so the Digimon is drawn turning its
            // head away rather than holding one picture; the head-shake dips that whole sprite side
            // to side, which is what makes a refusal legible without reading the caption.
            show(.pose(.refuse), motion: .shake, message: "Not hungry.")
        case .blocked(let reason):
            // No animation and NO MOTION: nothing happened to the Digimon, so it keeps idling and
            // only the reason appears. Either would read as the action having half-worked.
            show(nil, message: reason)
        }

        do {
            try store?.save()
        } catch {
            // Same call as `refresh()`: the in-memory change stands and the screen is not taken
            // away, but a lost save does not pass in silence.
            Self.log.error("Could not save after feeding: \(String(describing: error))")
        }
        return outcome
    }

    /// ENTERS a training round: spends Strength or Stamina, counts the session, and puts this
    /// Digimon's assigned minigame on screen (US-083).
    ///
    /// This is only the first half of a training now. `strengthStat` is NOT raised here — the round
    /// has not been played yet, and what it is worth is `finishTraining(_:)`'s to say. What is settled
    /// here is everything that must not depend on how the round goes: eligibility, the charge, and the
    /// session count evolution reads.
    ///
    /// **Saved immediately, exactly as `battle()` saves its own charge and for the same reason.** The
    /// energy is gone the moment the game appears, so force-quitting mid-round must not hand it back —
    /// a charge that only reached disk when the grade did would make every losing round free.
    ///
    /// Returns the start so a test can assert on it directly; the screen reacts to `pendingTraining`,
    /// `animation` and `actionMessage` instead.
    @discardableResult
    func train() -> TrainingStart? {
        guard let state else { return nil }
        // A round already in play is not restarted, and — the point — is not charged for a second
        // time. The overlay makes a second tap unreachable by covering the button; this guard is what
        // makes "unreachable" a rule rather than a property of the layout. nil, as with no saved
        // game: nothing happened, and there is no reason to show over a game already on screen.
        //
        // A PRE-BATTLE round counts too (US-093): one Digimon cannot be in two minigames at once, and
        // a Train tap that got through one would charge energy for a round whose grade the battle is
        // waiting on. `battle()` carries the mirror of this guard.
        guard pendingTraining == nil, pendingBattleRound == nil else { return nil }
        // Before the rule is asked, so the round really opens (US-110). A woken Digimon that turns
        // out to be sick or broke is still blocked by `TrainAction` — and still charged the
        // disturbance, because it really was disturbed: it is awake and walking about either way.
        wakeIfAsleep()
        let start = TrainAction.begin(state, isAsleep: isAsleep)

        switch start {
        case .started:
            // The session `TrainAction.begin` just counted, counted again against the map it was
            // trained in (US-206). Here rather than in `finishTraining` for the reason the global
            // count is taken at `begin`: the session is one per STARTED round, and a round walked
            // out of still happened.
            creditMapCare(.careTrainingSessions)
            // No pose and no haptic yet: the Digimon is about to be covered by the game, and the
            // attack frame belongs to the round LANDING rather than to it starting.
            pendingTraining = PendingTraining(
                kind: MinigameAssignment.game(for: state.currentDigimonId, in: graph, roster: roster)
            )
        case .blocked(let reason):
            // No animation, as with a blocked feed: nothing happened to the Digimon, so it keeps
            // idling and only the reason appears. NO GAME EITHER — the round was never paid for, and
            // opening one would be a free training.
            show(nil, message: reason)
        }

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after training: \(String(describing: error))")
        }
        return start
    }

    /// Pays out the round the minigame just graded, takes the game down, and says what it earned.
    ///
    /// The other half of `train()`, and the one call every minigame's `onFinish` lands in. Charges
    /// nothing — `TrainAction.begin` already did — so a `.miss` here is a round that cost energy and
    /// bought no stat, which is the whole reason the two halves are separate.
    ///
    /// A no-op without a round in progress, so a game that called back twice cannot be paid twice.
    func finishTraining(_ result: TrainingResult) {
        guard pendingTraining != nil, let state else { return }
        pendingTraining = nil
        let gain = TrainAction.finish(state, result: result)

        // US-207 removed US-128's after-a-train drop check from here. A training session still
        // MEETS a slot gated on `care.trainingSessions` — the map detail marks it "Ready to find"
        // the moment the round is graded — but meeting it no longer hands the egg over; the next
        // won battle in that map is what looks for it. See `checkForDigitamaDrop`.
        playTrainHaptic()
        // The attack frame for a round that bought something. A miss gets the angry frame instead —
        // the round happened and it was not enough, which is a different thing to show than a
        // successful blow. The caption names the grade and the STR it bought; the training charge it
        // spent (US-177) is read off the bar, exactly as a battle's charge is.
        //
        // Both are `.pose`, so the sheet frame alternates with the walk frame and the Digimon is
        // seen swinging or bristling rather than being shoved about as one picture. The motion is
        // the other half of telling the two outcomes apart at a glance: a paid round LUNGES, forward
        // in the direction the sprite faces and home again, and a miss RECOILS backward.
        show(gain > 0 ? .pose(.attack) : .pose(.angry),
             motion: gain > 0 ? .lunge : .recoil,
             message: "\(result.displayName) +\(gain) STR")

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after training: \(String(describing: error))")
        }
    }

    /// Ends a round the user walked out of — graded a `.miss`, and with nothing refunded.
    ///
    /// Called when the app leaves the foreground mid-game (US-083 AC4). Leaving is not an escape
    /// hatch: the energy went at `train()` and the session was already counted, so a round abandoned
    /// because it was going badly costs exactly what one played to the end costs. It simply buys no
    /// stat.
    ///
    /// A no-op with no round in progress, which is every ordinary backgrounding.
    func abandonTraining() {
        guard pendingTraining != nil else { return }
        finishTraining(.miss)
    }

    /// Clears the mess: sets `poopCount` to zero and says so in the caption slot.
    ///
    /// A no-op with nothing to clean, which the disabled button already prevents — but the guard is
    /// here too, because "the button was disabled" is a fact about a view and this is where the
    /// rule belongs. Returning it is also what lets a test assert the no-op without a view graph.
    ///
    /// **The restamp is not cosmetic.** `PoopClock` freezes `poopUpdatedAt` at the instant the
    /// ceiling was reached, so a screen that has been full for a day carries a timestamp a day old.
    /// Clearing the count without moving that timestamp would let the very next refresh find four
    /// intervals' worth of elapsed time and put all four poops straight back — cleaning would
    /// visibly undo itself. The clock starts again from the moment the user cleaned.
    ///
    /// The happy frame, alternating with the walk frame: this is the one action in the row whose
    /// whole reward is the Digimon being pleased about it, so it is drawn celebrating rather than
    /// holding one picture. The hop is the other half of that reward — it lifts the whole sprite off
    /// the floor, which no frame swap on its own can do.
    @discardableResult
    func clean() -> Bool {
        guard let state, state.poopCount > 0 else { return false }
        // Cleaning draws on a real handwash (US-178), capped at two and shared across the whole box.
        // Asked AFTER "is there a mess" so a Digimon with nothing to clean stays a silent no-op — the
        // "go wash" affordance only makes sense when there is a mess it is refusing to clear. Spent
        // through the profile so the count and the "was there one?" answer come from one place, and
        // nothing below runs until a charge is actually taken: the mess stays, poop unchanged.
        // Mirrors `battle()`'s "No charge — go walk." for the same reason it does not disable the
        // button — the message is how a zero says why.
        guard let profile, profile.spendCleanCharge() else {
            show(nil, message: "No charge — go wash.")
            return false
        }
        state.poopCount = 0
        state.poopUpdatedAt = now()
        // The mess notice is withdrawn from the wrist, and the claim is re-armed here rather than
        // being left to the next refresh's `claimPoopNotification` — cleaning is the whole of what
        // ends a mess, so both halves of ending it belong in one place and are saved by the flush
        // below. A screen left to fill again is a new mess and earns a new notice.
        state.poopNotified = false
        notifications.cancel(.poop)
        show(.pose(.happy), motion: .hop, message: "All clean!")

        do {
            try store?.save()
        } catch {
            // Same call as `feed()`: the in-memory clean stands and the screen is not taken away,
            // but a lost save does not pass in silence.
            Self.log.error("Could not save after cleaning: \(String(describing: error))")
        }
        // Cleaning is the one ACTION that changes the complication's pose (US-047): it takes the
        // mess away, so the face must stop showing the angry frame. Feeding and training do not
        // reach the pose at all, and everything else that does — sickness, sleep, death — is settled
        // inside `refresh()`, which publishes for itself.
        publishComplicationSnapshot()
        return true
    }

    /// How many poops are on screen, for the pile to draw and the Clean button to disable itself
    /// against. Zero when there is no game, which is also what leaves the button disabled.
    var poopCount: Int { state?.poopCount ?? 0 }

    /// Which state the room light is in, for the button to draw itself as and the scrim to dim by
    /// (US-099). `.on` with no saved game, which is the same reading `GameState` gives a save
    /// written before the light existed — an undimmed screen is the safe answer either way.
    var lightState: LightState { state?.lightState ?? .on }

    /// Moves the light on the round: on -> semi -> off -> on.
    ///
    /// NOT an action in the sense the other five are. It costs no energy, is refused by nothing, is
    /// blocked by nothing — not sleep, not sickness, not death — and it charges no care mistake:
    /// what US-101 charges for is a light left ON over a sleeping Digimon, so the tap that puts it
    /// out is the only way to avoid that and can hardly be a mistake in itself. There is deliberately
    /// no `guard isAsleep` and no `wakeIfAsleep()` here — the light is the one control that reaches
    /// a sleeping Digimon without waking it.
    ///
    /// Saved immediately, like every other tap that changes the game: the state and its timestamp are
    /// what `LightsOutRule` reads on the next launch, and a light put out at bedtime that never
    /// reached disk would be charged for as a night spent under it.
    ///
    /// Returns the state moved to so a test can assert on it directly; the screen reads `lightState`.
    @discardableResult
    func cycleLight() -> LightState? {
        guard let state else { return nil }
        // Through `setLight` rather than by assignment, because it is the one thing that keeps the
        // state and the "since when" stamp in step — see `GameState.setLight(_:now:)`.
        state.setLight(state.lightState.next, now: now())
        // US-100 AC5, and exactly what `clean()` does with the mess notice: the nudge asked for one
        // thing, that thing has now been done, and a notice still sitting on the wrist — or worse,
        // one queued to arrive at 22:10 in a room that went dark at 21:00 — is worse than none.
        // `cancel` reaches the pending request and the delivered one alike; `withdrawLightsNotice`
        // gives back the claim only if the notice never actually appeared.
        if state.lightState == .off {
            state.withdrawLightsNotice(now: now())
            notifications.cancel(.lights)
        }

        do {
            try store?.save()
        } catch {
            // Same call as `feed()` and `clean()`: the light on screen stands and is not snapped
            // back, but a lost save does not pass in silence.
            Self.log.error("Could not save after changing the light: \(String(describing: error))")
        }
        return state.lightState
    }

    /// Whether the sick badge is owed (US-069).
    ///
    /// Deliberately `== .sick` and not `!= .healthy`: a dead Digimon is past being ill, and the
    /// memorial is the only thing that state owes anyone. Written as a property rather than read
    /// off `state` in the view so the badge and the pose can never disagree about what "sick" means.
    var isSick: Bool { state?.healthStatus == .sick }

    /// ENTERS a battle: picks an opponent near the player's stage, spends `BattleCost.energy`, and puts
    /// this Digimon's assigned minigame on screen as the PRE-BATTLE round (US-093).
    ///
    /// This is only the first half of a battle now. Nothing is rolled here — how hard the player hits
    /// depends on how the round goes, and that is `finishBattleRound(_:)`'s to say. What is settled here
    /// is everything that must not depend on it: eligibility, who is being fought, and the charge.
    ///
    /// The round is a fight, not a workout. It costs NO energy, buys no `strengthStat` and counts no
    /// training session — `TrainAction` is never called from here. The only thing it is worth is the
    /// multiplier it hands `BattleModifiers`.
    ///
    /// **`BattleCost.energy` is spent HERE and saved immediately**, exactly as `TrainAction.begin`
    /// charges its energy and through the same `EnergyPurchase` rule: the battle is committed to the
    /// moment the game appears, so a force-quit mid-round has still paid for it.
    ///
    /// Blocked while dead. NOT blocked while asleep since US-110 — a sleeping Digimon is WOKEN and
    /// then fights, which is the same treatment feeding and training give it, and the waking-early
    /// mistake is charged for the disturbance that really happened rather than for a refusal.
    /// Prodding a sleeping Digimon into a fight is the same neglect as prodding it to eat. Blocked
    /// when neither payable energy can cover the cost (US-108) — that guard sits AFTER the wake, so a
    /// Digimon prodded awake with no energy is still charged the waking-early mistake, and BEFORE
    /// matchmaking, so a Digimon that cannot afford a fight is told so rather than told there is
    /// nobody to fight. A BLOCKED BATTLE OPENS NO GAME AND SPENDS NOTHING, for the reason a blocked
    /// `train()` opens none: the round is the thing being paid for.
    ///
    /// Returns the game that opened, so a test can assert the battle went ahead without a view; the
    /// screen reacts to `pendingBattleRound`.
    @discardableResult
    func battle() -> MinigameKind? {
        guard let state else { return nil }
        // The mirror of `train()`'s guard, and the same silence: one Digimon cannot be in two
        // minigames at once, and a second Battle tap would spend a second cost on a fight the first
        // tap has already picked an opponent for.
        guard pendingBattleRound == nil, pendingTraining == nil else { return nil }
        guard state.healthStatus != .dead else {
            show(nil, message: "It cannot battle.")
            return nil
        }
        // After the death guard and before everything else, so a sleeping Digimon is prodded into
        // the fight rather than told to rest (US-110). A woken Digimon with no energy still hears
        // about the energy below, and has still been charged the disturbance — being dragged out of
        // bed for a fight that then does not happen is exactly the neglect the mistake is for.
        wakeIfAsleep()
        // The battle currency since US-176: a fight spends one charge, walked up from steps at
        // `stepsPerBattleCharge`. Asked before matchmaking, like the energy guard below, so an
        // out-of-charges Digimon hears why rather than hearing about an opponent it cannot fight.
        // Mirrors the meat larder's "go battle" affordance — the purple dash bar shows the count and
        // an empty one plus this message is the whole reason Battle did nothing.
        guard state.battleCharges > 0 else {
            show(nil, message: "No charge — go walk.")
            return nil
        }
        // Asked BEFORE matchmaking and answered by the same `EnergyPurchase` rule that charges below,
        // so a Digimon that cannot afford a fight hears why instead of hearing about opponents.
        guard EnergyPurchase.payer(for: BattleCost.energy,
                                   from: BattleCost.payableWith, in: state) != nil else {
            show(nil, message: BattleCost.insufficientEnergyReason)
            return nil
        }
        // Through the roster fallback, for the reason `presentation(forId:)` gives: a Jogress result
        // (US-132) is on no authored line, and a graph-only lookup would tell the player who had
        // just fused two Ultimates that they have "No Digimon to fight with".
        guard let player = presentation(forId: state.currentDigimonId) else {
            show(nil, message: "No Digimon to fight with.")
            return nil
        }

        // Drawn here and CARRIED, rather than made again when the round is graded — see
        // `PendingBattleRound`. Both refusals below this line are decided before the energy is
        // spent, which is the point of matchmaking early.
        var generator = nextBattleGenerator()
        guard let opponent = BattleMatchmaker.choose(in: graph,
                                                    roster: roster,
                                                    playerId: state.currentDigimonId,
                                                    map: selectedMap,
                                                    recorded: selectedMapRecorded,
                                                    using: &generator) else {
            show(nil, message: "Nobody to fight.")
            return nil
        }

        let game = MinigameAssignment.game(for: state.currentDigimonId, in: graph, roster: roster)
        // Charged where the allowance used to be spent, and never refunded: a round dismissed halfway
        // has still been paid for, exactly as `TrainAction.begin` documents.
        EnergyPurchase.charge(BattleCost.energy, from: BattleCost.payableWith, in: state)
        // Spent where the energy is and saved by the same flush, so a round dismissed halfway has
        // still cost its charge — a walk earned the fight, and walking away from it does not refund
        // the walk. The `> 0` guard above ran before matchmaking, so this never dips below zero.
        state.battleCharges -= 1
        state.recordBattleStarted(now: now(), calendar: calendar)
        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save the battle's cost: \(String(describing: error))")
        }

        // No pose and no caption: the Digimon is about to be covered by the game, and the attack
        // frame belongs to the arena rather than to the walk up to it.
        pendingBattleRound = PendingBattleRound(game: game, player: player, opponent: opponent,
                                                generator: generator)
        Self.log.info("Pre-battle \(game.rawValue) vs \(opponent.node.id)")
        return game
    }

    /// Fights the battle the graded round just decided the player's edge in, and hands the replay to
    /// the screen via `pendingBattle`.
    ///
    /// The other half of `battle()`, and the call the pre-battle minigame's `onFinish` lands in.
    /// Charges nothing — the energy went when the game appeared — so a `.miss` here is a battle that
    /// cost its energy and bought a WEAKER fight rather than no fight, which is the whole reason the
    /// two halves are separate.
    ///
    /// The grade reaches the fight through `BattleModifiers.matchup`, which is also where the two
    /// typings are applied, and the report is resolved from the EFFECTIVE powers it returns. The
    /// matchup rides along on the bout so nothing downstream has to re-derive the arithmetic the
    /// battle was actually fought with. As before, the whole thing is resolved before a single frame is
    /// drawn, so the view stays a replay of a decided outcome.
    ///
    /// A no-op without a round in progress, so a game that called back twice cannot start two battles.
    @discardableResult
    func finishBattleRound(_ result: TrainingResult) -> BattleBout? {
        guard let round = pendingBattleRound else { return nil }
        pendingBattleRound = nil

        var generator = round.generator
        guard let bout = resolveBattle(player: round.player, opponent: round.opponent,
                                       result: result, using: &generator) else { return nil }

        pendingBattle = bout
        Self.log.info("""
            Battle vs \(round.opponent.node.id) after a \(result.displayName) round: \
            \(bout.report.playerWon ? "won" : "lost")
            """)
        return bout
    }

    /// Resolves a fight between the loaded Digimon and `opponent` at grade `result`, into a replayable
    /// `BattleBout` — the shared core of the pre-battle round (US-093) and the wild encounter (US-201).
    ///
    /// Split out of `finishBattleRound` so a wild encounter, which has no pre-battle minigame, fights
    /// the exact same fight rather than spelling the matchup, HP, Agility, element and meat arithmetic
    /// a second time — a second copy would let one path be quietly easier than the other. Every draw
    /// happens in the same order off the caller's `generator`, so a seed still pins one whole bout.
    ///
    /// Nil only with no `state`, which is a game not yet loaded — every caller has already unwrapped it.
    private func resolveBattle(player: DigimonPresentation,
                               opponent: BattleOpponent,
                               result: TrainingResult,
                               using generator: inout SeededGenerator) -> BattleBout? {
        guard let state else { return nil }

        let types = ElementCatalog.bundled
        let matchup = BattleModifiers.matchup(
            playerPower: state.battlePower(lifetimeEnergy: lifetimeEnergy),
            playerType: types.type(for: state.currentDigimonId, in: graph),
            opponentPower: opponent.power,
            // Off the node in hand rather than off a graph lookup: since US-122 an opponent may be a
            // roster-only Digimon with no graph node, and asking the graph about one would answer
            // `.unauthored` where the node itself still carries what is known.
            opponentType: types.type(forId: opponent.node.id, line: opponent.node.line),
            training: result
        )

        // Each side's HP dash bar is drawn to its per-stage base HP (US-188), so a Child fights on
        // five dashes and an Ultimate on twelve; a stage the table omits falls back to the flat pool.
        // The PLAYER's is its EFFECTIVE HP — base plus what training banked (US-191) — so a trained
        // Digimon fights on more dashes; the wild opponent is no `GameState`, so it fights on base.
        let config = ConsumptionConfig.bundled
        let playerMaxHP = config.stats(for: state.stage)
            .map { state.effectiveStat(.hp, base: $0.baseHP) } ?? BattleEngine.startingHitPoints
        let opponentMaxHP = config.stats(for: opponent.node.stage)?.baseHP
            ?? BattleEngine.startingHitPoints

        // Each side's Agility decides how many of the other's swings it slips (US-189). Both come
        // straight off the stage stat table, so a faster stage dodges more; nil when either stage has
        // no stats — an edge no playable Digimon hits — in which case the fight falls back to the
        // pre-dodge always-lands model rather than crediting one side an untouchable Agility of zero.
        // The player's Agility is its EFFECTIVE value (US-191): training slips more swings, exactly as
        // it adds HP dashes above.
        let agility: BattleAgility?
        if let playerAgility = config.stats(for: state.stage)?.baseAgility,
           let opponentAgility = config.stats(for: opponent.node.stage)?.baseAgility {
            agility = BattleAgility(player: state.effectiveStat(.agility, base: playerAgility),
                                    opponent: opponentAgility,
                                    coefficients: config.hitRate)
        } else {
            agility = nil
        }

        // Each landed swing is scaled by the attacker-vs-defender element matchup (US-190): the two
        // typings the matchup already resolved feed a separate, stronger damage table than the power
        // factors above, so a good element is felt blow by blow while still denting at least one dash.
        let elements = BattleElements(player: matchup.playerType.element,
                                      opponent: matchup.opponentType.element,
                                      multipliers: config.elementDamage)

        let report = BattleEngine.resolve(playerPower: matchup.playerPower,
                                          opponentPower: matchup.opponentPower,
                                          playerMaxHitPoints: playerMaxHP,
                                          opponentMaxHitPoints: opponentMaxHP,
                                          agility: agility,
                                          elements: elements,
                                          using: &generator)
        // The win's meat drop (US-175), rolled off the SAME generator the fight was resolved from so
        // the seed pins it too, and credited to the global larder here rather than in `finishBattle`
        // because this is the only half with a generator in hand. Zero on a loss and zero at a full
        // larder — `MeatReward` clamps to the room under the cap, so the number banked below and the
        // number the result screen shows are one value. The credit is in-memory until `finishBattle`
        // saves alongside the win/loss record, exactly as the energy cost is.
        var meatGained = 0
        if report.playerWon, let profile {
            meatGained = MeatReward.rolled(from: config.meatPerBattleWin,
                                           current: profile.meat, cap: config.meatCap,
                                           using: &generator)
            profile.meat += meatGained
        }
        // Each side's attack identity (US-070), resolved here where both ids and their nodes are in
        // hand, so the pure core answers without a second roster lookup. The opponent's node may be
        // a roster-only one promoted by `MapOpponentBand` since US-122 — it carries an empty line,
        // which misses `lineDefaults` and lands on the stage tier, exactly as intended.
        let catalog = MoveCatalog.bundled
        let playerNode = graph.node(id: state.currentDigimonId)
        return BattleBout(
            player: player,
            opponent: DigimonPresentation(displayName: opponent.node.displayName,
                                          stage: opponent.node.stage,
                                          spriteFile: opponent.node.spriteFile),
            report: report,
            playerMove: catalog.move(forId: state.currentDigimonId,
                                     line: playerNode?.line, stage: playerNode?.stage),
            opponentMove: catalog.move(forId: opponent.node.id,
                                       line: opponent.node.line, stage: opponent.node.stage),
            matchup: matchup,
            meatGained: meatGained
        )
    }

    /// Ends a pre-battle round the user walked out of — graded a `.miss`, and the battle fought anyway.
    ///
    /// Called when the app leaves the foreground mid-game, the same moment `abandonTraining()` is. It is
    /// NOT a cancel: the energy went when the round opened, so backgrounding buys the fight at the
    /// miss multiplier rather than calling it off, and the bout is waiting on `pendingBattle` when the
    /// app comes back. Walking out of a round that was going badly is not a way to keep the battle.
    ///
    /// A no-op with no round in progress, which is every ordinary backgrounding.
    func abandonBattleRound() {
        guard pendingBattleRound != nil else { return }
        finishBattleRound(.miss)
    }

    /// Whether the Digimon can pay `BattleCost.energy` right now, for the button to disable itself
    /// against.
    ///
    /// Derived rather than stored, and derived by asking `EnergyPurchase` the same question the guard
    /// in `battle()` asks, which is what keeps the disabled button and the refusal from ever
    /// disagreeing. False with no state, because a Digimon that is not loaded cannot fight either.
    var canAffordBattle: Bool {
        guard let state else { return false }
        return EnergyPurchase.payer(for: BattleCost.energy,
                                    from: BattleCost.payableWith, in: state) != nil
    }

    /// Files the battle's result and takes the screen down, so a battle is recorded exactly once.
    ///
    /// `recordBattle` moves the win/loss counters and, since US-192, makes a LOSS matter: it heals a
    /// sick Digimon or charges a healthy one a care mistake (reversing US-031). It settles no clocks
    /// of its own — the care mistake it may add rides the ordinary neglect ladder to sickness and
    /// death on the next `refresh()`, exactly as a mistake from any other source does.
    func finishBattle() {
        guard let bout = pendingBattle else { return }
        pendingBattle = nil
        state?.recordBattle(bout.report)
        // US-206: the same result filed against the map it was fought in, so a map's
        // `care.battleCount` and `care.battleWinRatio` slots ask what happened HERE. Both counters
        // move together off one call, which is what keeps the ratio between them from exceeding 1.
        if let profile, let mapId = profile.selectedMapId, maps.map(id: mapId) != nil {
            profile.recordBattle(won: bout.report.playerWon, forMap: mapId)
        }

        do {
            try store?.save()
        } catch {
            // Same call as `feed()`: the in-memory result stands and the screen is not taken away,
            // but a lost save does not pass in silence.
            Self.log.error("Could not save after battling: \(String(describing: error))")
        }
        // US-207: a WIN is the one moment an egg is found, and it is a coin flip even then. After
        // the save above so the recorded result is on disk whether or not an egg then drops — and
        // gated on the result here rather than inside the check, because "a loss awards nothing" is
        // a fact about this call site: there is no other way to reach the engine.
        if bout.report.playerWon {
            checkForDigitamaDrop()
        }
    }

    // MARK: - Wild encounters (US-201)

    /// How far into a map the player walks between wild encounters — 500 steps. Measured against the
    /// map's recorded total at the LAST encounter (`PlayerProfile.encounterMarker`), so it is 500
    /// NEW steps each time rather than a multiple of 500 of lifetime walking.
    static let wildEncounterStepInterval: Double = 500

    /// Raises a wild encounter if the player has walked `wildEncounterStepInterval` into their map
    /// since the last one resolved (US-201).
    ///
    /// Called at the tail of every `refresh()` — the app coming to the front — so an encounter that
    /// came due while the app was closed greets the player the moment they open it, exactly as a hatch
    /// or evolution does. Internal rather than private so a test can drive the trigger against a
    /// seeded map counter without a whole health read; the step source it reads (the map's recorded
    /// total) and the clock are both injected, which is US-201's "the trigger is testable".
    ///
    /// Silent when anything is already on screen — a pending encounter, battle, round, ceremony or
    /// memorial — because the dialog must not appear over one of those, and because the same steps
    /// should not raise a second foe while the first is unanswered. Silent with no map selected, with
    /// a dead Digimon, and when the map's pool offers nobody the roster knows.
    func checkForWildEncounter() {
        guard pendingWildEncounter == nil, pendingBossEncounter == nil, pendingBattle == nil,
              pendingBattleRound == nil, pendingTraining == nil, pendingEvolution == nil,
              memorial == nil,
              let state, state.healthStatus != .dead,
              let profile, let map = selectedMap else { return }
        let recorded = profile.recorded(forMap: map.id)
        guard recorded - profile.encounterMarker(forMap: map.id) >= Self.wildEncounterStepInterval else {
            return
        }
        // Drawn here and CARRIED on the encounter, exactly as `battle()` carries its generator onto
        // the pre-battle round: the opponent is picked now and the fight, if accepted, is rolled from
        // the same sequence, so one seed still produces one whole bout.
        var generator = nextBattleGenerator()
        guard let opponent = BattleMatchmaker.choose(in: graph, roster: roster,
                                                     playerId: state.currentDigimonId,
                                                     map: map, recorded: recorded,
                                                     using: &generator) else { return }
        pendingWildEncounter = WildEncounter(
            opponent: opponent,
            presentation: DigimonPresentation(displayName: opponent.node.displayName,
                                              stage: opponent.node.stage,
                                              spriteFile: opponent.node.spriteFile),
            mapId: map.id,
            generator: generator)
        // The 500-step meeting itself is a meeting (US-202): the moment the encounter surfaces, this
        // resident is MET and its "?" on the map detail becomes its art. Recorded on the profile
        // now; the flee/accept that answers this modal both save, so the meeting reaches disk
        // whichever way the player resolves it. `recordMet` is idempotent, so meeting the same foe
        // again is one meeting.
        profile.recordMet(opponent.node.id, forMap: map.id)
        // The dialog is now on screen, so a background nudge that got the player here has done its
        // job — withdraw it rather than leave a "go and battle" notice on the wrist over the battle
        // they are already looking at, exactly as cleaning withdraws the mess notice (US-054).
        notifications.cancel(.wildBattle)
    }

    /// Raises a wild-battle NOTIFICATION when one is due but the app is not in front (US-205).
    ///
    /// The background twin of `checkForWildEncounter`: run only from a background wake (`refresh(background:)`),
    /// where there is no screen to put the BATTLE/FLEE dialog on. It reads the same trigger — 500 steps
    /// into the map past the last encounter's marker — and, if crossed, hands the system a local
    /// notification inviting the player to open the app. It deliberately does NOT set
    /// `pendingWildEncounter`, pick an opponent or record a meeting: all of that is the foreground
    /// refresh's job the moment the player taps in, which re-derives the encounter from the same
    /// counter (US-201). Tapping the notification launches the app, so the dialog is waiting with no
    /// deep-link plumbing of its own.
    ///
    /// **Best-effort, no timing guarantee.** watchOS grants background refreshes when it chooses, at
    /// most roughly every `BackgroundRefreshSchedule.interval` (~30 minutes) and often less; a crossing
    /// may sit unannounced until the next wake or until the app is opened. This is opportunistic by
    /// construction — see `BackgroundRefreshSchedule` and `docs/background-wild-battle.md`.
    ///
    /// Silent under the same guards `checkForWildEncounter` uses (a pending encounter, battle, round,
    /// training, evolution or memorial; no map; a dead Digimon), so a boss due at the same time takes
    /// precedence and the same steps never raise two things. Silent too while asleep (the notice does
    /// not fire at 3am) and while the toggle is off — `NotificationDispatcher.send` enforces both.
    ///
    /// It fires at most ONCE per threshold crossing, even across process death: the crossing is keyed
    /// by the `encounterMarker` it is measured from — which only moves when an encounter resolves — so
    /// once a nudge is delivered its marker is stamped on the profile and saved, and a later wake that
    /// finds the same marker already stamped stays silent. The stamp is taken only on actual delivery,
    /// so a crossing suppressed by sleep is nudged on the next wake past the window rather than lost.
    func notifyWildEncounterIfDue() {
        guard pendingWildEncounter == nil, pendingBossEncounter == nil, pendingBattle == nil,
              pendingBattleRound == nil, pendingTraining == nil, pendingEvolution == nil,
              memorial == nil,
              let state, state.healthStatus != .dead,
              let profile, let map = selectedMap else { return }
        let recorded = profile.recorded(forMap: map.id)
        let marker = profile.encounterMarker(forMap: map.id)
        guard recorded - marker >= Self.wildEncounterStepInterval else { return }
        // Already nudged for this crossing? The marker only moves when an encounter resolves, so a
        // stamp equal to the current marker means the notice for this crossing has gone out — say
        // nothing until the player acts and the marker moves on.
        guard profile.wildBattleNotifiedMarker(forMap: map.id) != marker else { return }
        let name = presentation?.displayName ?? "Your Digimon"
        let delivered = notifications.send(
            .wildBattle,
            body: "\(name) has walked into a wild Digimon. Open the app to battle.",
            isAsleep: isAsleep)
        // Stamp only on real delivery, so a crossing the sleep gate or a switched-off toggle held
        // back is still owed and gets its nudge from a later wake rather than being silently spent.
        guard delivered else { return }
        profile.setWildBattleNotifiedMarker(marker, forMap: map.id)
        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save the wild-battle notification marker: \(String(describing: error))")
        }
    }

    /// FLEE: the Digimon turns away and the map loses 500 steps (US-201).
    ///
    /// The penalty is what keeps fleeing from being free — a wild encounter is walked into, and walking
    /// out of it sends the player back the 500 steps that raised it. The marker is then moved to the
    /// map's new total, so the next encounter is 500 fresh steps from here rather than being owed
    /// immediately. A no-op with no encounter pending.
    func fleeWildEncounter() {
        guard let encounter = pendingWildEncounter, let profile else { return }
        pendingWildEncounter = nil
        profile.reduceRecorded(steps: Self.wildEncounterStepInterval, forMap: encounter.mapId)
        profile.setEncounterMarker(profile.recorded(forMap: encounter.mapId), forMap: encounter.mapId)
        // The refuse pose, recoiling backward: the Digimon turns tail, which is the sad/refuse
        // animation US-201 asks a flee to play.
        show(.pose(.refuse), motion: .recoil, message: "Fled!")

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after fleeing: \(String(describing: error))")
        }
    }

    /// BATTLE: fights the wild Digimon and settles the map on the outcome (US-201).
    ///
    /// The fight is resolved through the same `resolveBattle` core the pre-battle round uses — graded
    /// `.good`, since a wild encounter has no minigame to earn a grade from — and handed to the screen
    /// on `pendingBattle`, so it replays a decided outcome exactly as a chosen battle does. The
    /// consequence is read off that decided report:
    /// - The wild Digimon counts as MET on this map whichever way it goes (US-202/US-203) — fighting
    ///   it is a meeting; `checkForWildEncounter` already met it at surface, this is the fight path
    ///   owning it too.
    /// - WIN: no step penalty.
    /// - LOSS: the map loses 500 steps, the same penalty a flee costs.
    ///
    /// The marker is moved to the map's total AFTER any penalty, so the next 500 is measured from where
    /// this one left off. `finishBattle` still files the win/loss record when the replay ends, exactly
    /// as it does for a chosen battle. A no-op with no encounter pending, or before a game is loaded.
    @discardableResult
    func acceptWildEncounter() -> BattleBout? {
        guard let encounter = pendingWildEncounter, let state, let profile,
              let player = presentation(forId: state.currentDigimonId) else { return nil }
        pendingWildEncounter = nil

        var generator = encounter.generator
        guard let bout = resolveBattle(player: player, opponent: encounter.opponent,
                                       result: .good, using: &generator) else { return nil }

        // Fighting it is a meeting whatever the result (US-202): win OR loss, you have now met this
        // resident, so it is recorded either way rather than only on a win. Idempotent, and usually
        // already true — `checkForWildEncounter` met it the moment the dialog surfaced — but kept
        // explicit so the fight path owns the meeting and does not lean on the surface having.
        profile.recordMet(encounter.opponent.node.id, forMap: encounter.mapId)
        if !bout.report.playerWon {
            profile.reduceRecorded(steps: Self.wildEncounterStepInterval, forMap: encounter.mapId)
        }
        profile.setEncounterMarker(profile.recorded(forMap: encounter.mapId), forMap: encounter.mapId)

        pendingBattle = bout
        Self.log.info("""
            Wild battle vs \(encounter.opponent.node.id): \(bout.report.playerWon ? "won" : "lost")
            """)

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after a wild battle: \(String(describing: error))")
        }
        return bout
    }

    // MARK: - Boss encounters (US-203)

    /// How many steps a lost boss costs the map — 1,000, double a wild loss (US-203). Knocked off the
    /// counter so the player has to keep walking before the boss can be re-challenged, which is what
    /// makes losing it matter rather than being a free retry.
    static let bossLossStepPenalty: Double = 1_000

    /// Whether the current selection's map is done EXCEPT for the boss: the counter has crossed the
    /// total and every meetable resident has been met, but the boss has not yet been beaten (US-203).
    ///
    /// Pure and read off the profile, so a test can assert the trigger conditions without raising the
    /// dialog. Nil-safe: no profile, no map, an unfinished-by-anything map — every one of those is
    /// "not ready", so this only ever answers true when a boss genuinely stands in the way.
    private func mapAwaitsBoss(_ map: AdventureMap) -> Bool {
        guard let state, let profile else { return false }
        guard !profile.isFinished(forMap: map.id) else { return false }
        guard profile.recorded(forMap: map.id) >= Double(map.totalSteps) else { return false }
        let residents = MapOpponentBand.residents(of: map, graph: graph, roster: roster,
                                                  excluding: state.currentDigimonId)
        guard !residents.isEmpty else { return false }
        let met = profile.metDigimon(forMap: map.id)
        return residents.allSatisfy { met.contains($0.id) }
    }

    /// Raises the map's boss the first time the player has walked the whole map AND met every resident
    /// of it, and it has not yet been beaten (US-203).
    ///
    /// Called at the tail of every `refresh()`, ahead of `checkForWildEncounter`, so the boss greets
    /// the player the moment the last resident is met and the map is complete. Internal rather than
    /// private so a test can drive the trigger against a seeded counter and met-set without a whole
    /// health read — the step source (the map's recorded total) and the clock are both injected.
    ///
    /// Silent when anything is already on screen — a pending boss, wild encounter, battle, round,
    /// ceremony or memorial — because its BATTLE-only dialog must not stack over one of those. Silent
    /// with no map selected, a dead Digimon, a map already finished, and a map whose boss cannot be
    /// resolved (no meetable resident at all).
    func checkForBossEncounter() {
        guard pendingBossEncounter == nil, pendingWildEncounter == nil, pendingBattle == nil,
              pendingBattleRound == nil, pendingTraining == nil, pendingEvolution == nil,
              memorial == nil,
              let state, state.healthStatus != .dead,
              let map = selectedMap, mapAwaitsBoss(map) else { return }
        guard let bossNode = MapOpponentBand.boss(of: map, graph: graph, roster: roster,
                                                  excluding: state.currentDigimonId) else { return }
        // Drawn and CARRIED, exactly as the wild encounter carries its generator: the boss is rolled
        // now and the fight, if accepted, replays from the same sequence, so one seed pins one bout.
        var generator = nextBattleGenerator()
        let opponent = BattleMatchmaker.rolled(bossNode, using: &generator)
        pendingBossEncounter = BossEncounter(
            opponent: opponent,
            presentation: DigimonPresentation(displayName: opponent.node.displayName,
                                              stage: opponent.node.stage,
                                              spriteFile: opponent.node.spriteFile),
            mapId: map.id,
            generator: generator)
    }

    /// BATTLE: fights the map's boss and settles the map on the outcome (US-203).
    ///
    /// The one action the boss dialog offers — there is no flee, a boss being a gate the player must
    /// pass rather than an ambush. The fight is resolved through the same `resolveBattle` core the wild
    /// encounter uses, graded `.good` (no minigame), and handed to the screen on `pendingBattle` to
    /// replay a decided outcome. The consequence is read off that decided report:
    /// - WIN: the map is stamped TRULY finished (`markFinished`), which is what opens the next map —
    ///   the boss is the gate US-203 puts on the unlock chain.
    /// - LOSS: the map loses `bossLossStepPenalty` (1,000) steps, so the counter drops back below the
    ///   total and the boss can only be re-challenged once the player has walked it up again.
    ///
    /// `finishBattle` still files the win/loss record when the replay ends, exactly as a chosen or wild
    /// battle does. A no-op with no boss pending, or before a game is loaded.
    @discardableResult
    func acceptBossEncounter() -> BattleBout? {
        guard let encounter = pendingBossEncounter, let state, let profile,
              let player = presentation(forId: state.currentDigimonId) else { return nil }
        pendingBossEncounter = nil

        var generator = encounter.generator
        guard let bout = resolveBattle(player: player, opponent: encounter.opponent,
                                       result: .good, using: &generator) else { return nil }

        if bout.report.playerWon {
            profile.markFinished(encounter.mapId, at: now())
        } else {
            profile.reduceRecorded(steps: Self.bossLossStepPenalty, forMap: encounter.mapId)
        }

        pendingBattle = bout
        Self.log.info("""
            Boss battle on \(encounter.mapId) vs \(encounter.opponent.node.id): \
            \(bout.report.playerWon ? "won — map finished" : "lost")
            """)

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after a boss battle: \(String(describing: error))")
        }
        return bout
    }

    /// Wakes a sleeping Digimon so the action the user just asked for can actually happen, and
    /// charges the waking-early care mistake for the disturbance.
    ///
    /// Called at the TOP of `feed()`, `train()` and `battle()`, before the pure rule is consulted —
    /// which is what US-110 changed. Until then these three charged the mistake and then blocked the
    /// action, so the user paid for a disturbance that never happened. Now the disturbance is real:
    /// the Digimon is awake, walking about and edible for the next `wakeGracePeriod`.
    ///
    /// Three things happen together and none of them is optional:
    /// - `recordWakingEarly` counts it — every time in `stageSleepDisturbances`, at most once a day
    ///   in `careMistakeCount`. Neither rule is this method's, and neither changed.
    /// - `awakeUntil` is stamped on the SAVED game, so a force-quit mid-grace does not undo it.
    /// - `isAsleep` is turned off here and now, because the actions read it in this same call stack
    ///   and the next re-derivation is a whole refresh away.
    ///
    /// A no-op when the Digimon is already awake — a second action inside the grace period is not a
    /// second disturbance, so it costs nothing and extends nothing.
    ///
    /// A no-op when the Digimon is DEAD, which is why every caller can rely on this rather than
    /// repeating a death guard: waking a corpse is not a thing, and the mistake would be charged for
    /// a disturbance that cannot have happened. The actions' own death blocks are untouched.
    private func wakeIfAsleep() {
        guard isAsleep, let state, state.healthStatus != .dead else { return }
        state.recordWakingEarly(now: now(), calendar: calendar)
        // The disturbance counted against the map it happened in as well (US-206) — `05_wasteland`'s
        // and `15_dungeon`'s eggs want them, `03_ocean`'s and `11_city_night`'s want none.
        creditMapCare(.careSleepDisturbances)
        state.awakeUntil = now() + SleepSchedule.wakeGracePeriod
        isAsleep = false
        // The sleep loop is on screen right now and the Digimon is no longer in it. Left to the next
        // refresh, a woken Digimon would keep the sleep frames until the app was backgrounded.
        settleRestingPose()
    }

    /// Shows an action's pose and caption, then returns to the resting pose after `actionDuration`.
    ///
    /// The previous reset is cancelled first, so tapping Feed twice in quick succession holds the
    /// second action for its full duration instead of being cut short by the first one's timer.
    ///
    /// A nil animation means "nothing happened to the Digimon" — a blocked action — so it keeps
    /// RESTING, which for a sleeping Digimon is the sleep loop and not the walk loop. A nil `motion`
    /// means the same about the sprite's position, and a blocked action passes both: motion would
    /// read as the action having half-worked.
    ///
    /// The motion is RESTARTED for as long as the pose is held, rather than played once and left to
    /// run out. Every track in `ActionMotion` is shorter than the two seconds a pose is held for —
    /// chewing is 1.2s — so a single play would leave the Digimon eating stock-still for the rest of
    /// the loop. Restarting is seamless because every track is `.zero` at both ends, and the last
    /// repeat is only begun if a whole one still fits, so the sprite is always home before the pose
    /// ends rather than being cut off mid-arc.
    private func show(_ animation: SpriteAnimation?,
                      motion kind: ActionMotion.Kind? = nil,
                      message: String?) {
        actionResetTask?.cancel()
        self.animation = animation ?? restingAnimation
        self.actionMessage = message
        self.actionMotion = kind.map { ActionMotion(kind: $0, start: now()) }

        actionResetTask = Task { [actionDuration] in
            var held: TimeInterval = 0
            if let kind {
                let period = ActionMotion.duration(of: kind)
                while held + 2 * period <= actionDuration {
                    try? await Task.sleep(for: .seconds(period))
                    guard !Task.isCancelled else { return }
                    held += period
                    self.actionMotion = ActionMotion(kind: kind, start: self.now())
                }
            }
            try? await Task.sleep(for: .seconds(actionDuration - held))
            guard !Task.isCancelled else { return }
            self.animation = self.restingAnimation
            self.actionMessage = nil
            self.actionMotion = nil
        }
    }

    /// The light tap a feed plays. No-ops where `WKInterfaceDevice` is unavailable (never on
    /// watchOS), mirroring `EvolutionCeremonyView.successHaptic`.
    static func feedHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    /// The firmer tap a training session plays. `.directionUp` rather than feeding's `.click`
    /// because the two actions should be distinguishable without looking at the watch — this one is
    /// the Digimon getting stronger. No-ops where `WKInterfaceDevice` is unavailable (never on
    /// watchOS).
    static func trainHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.directionUp)
        #endif
    }

    /// Hatches the egg into its linked Baby I form once total energy crosses the threshold.
    ///
    /// A no-op unless the current Digimon is a Digitama that is ready to hatch. Moves the saved game
    /// onto the Baby I node and keeps `GameState.stage` in step with the graph — the two are a saved
    /// duplicate (US-006) and the screen renders the stage from the graph, so a stale saved stage
    /// would draw a placeholder. `stageEnergy` resets for the new stage while `lifetimeEnergy` is
    /// left to carry the whole life; the Dex records the hatched form.
    private func hatchIfReady(_ state: GameState) {
        // Unlike evolution, hatching is NOT paused by illness — an egg has no care record of its own
        // to have spoiled (US-028). Death is different: a dead egg does not hatch, and without this
        // it would, because the energy that opened the threshold is still sitting there.
        guard state.healthStatus != .dead else { return }
        // Nor does a Digimon in the box (US-125). The model only ever holds the ACTIVE record, so
        // nothing here can reach a frozen one today; the guard is what keeps that true the day
        // something else calls this.
        guard state.isActive else { return }
        guard let node = graph.node(id: state.currentDigimonId),
              let target = EggHatcher.hatchTarget(for: node, stageEnergy: state.stageEnergy),
              let baby = graph.node(id: target) else { return }
        advance(state, to: baby)
        // Stamps the moment age is counted from (US-200). Set here, in the one hatch-specific path,
        // rather than in `advance`, which is shared with evolution — an evolution must not reset the
        // Digimon's age. `now()` is the same instant `advance` stamped `stageEnteredDate` with.
        state.hatchedDate = now()
        Self.log.info("Hatched \(node.id) into \(baby.id)")
    }

    /// Evolves the Digimon into whichever branch its earned energy qualifies for, once one does.
    ///
    /// A no-op until the stage's time gate has opened (US-020), and then unless the current node
    /// has an outgoing edge that qualifies (US-019's `qualifies` rule: dominant type, per-type
    /// threshold, care mistakes, battle wins) or an `isDefault` fallback to keep it from getting
    /// stuck. The branch is chosen from the CURRENT node's edges and by the CURRENT
    /// `stageEnergy`/`dominantEnergyType`, so a Digimon that was fed steps as a child can still
    /// take the sleep branch as an adult. Applies the same stage reset a hatch does — see `advance`.
    private func evolveIfReady(_ state: GameState) {
        // Paused, not cancelled, while the Digimon is unwell (US-028): an edge that qualifies now
        // still qualifies once it is cured, because nothing here consumes the energy that opened
        // it. Hatching is deliberately NOT gated — an egg has no care record of its own to have
        // spoiled, and stalling one would leave a new game with nothing to look at.
        guard state.healthStatus == .healthy else { return }
        // A Digimon in the box is never EVALUATED for evolution (US-125), which is stronger than
        // "does not evolve": its stage gate is a clock and `stageEnteredDate` is shifted on the way
        // out, so a month in the box buys no progress toward the next stage. See `hatchIfReady` for
        // why the guard is here even though nothing can reach it with a frozen record.
        guard state.isActive else { return }
        guard let node = graph.node(id: state.currentDigimonId),
              let target = EvolutionEngine.scheduledEvolutionTarget(
                for: node,
                stageEnergy: state.stageEnergy,
                dominant: state.dominantEnergyType,
                careMistakes: state.careMistakeCount,
                battleWins: state.battleWins,
                stageEnteredAt: state.stageEnteredDate,
                now: now(),
                // US-060: the edge's own `conditions`, answered off the totals US-058 banks and the
                // counters US-084 keeps, plus US-179's `conditionReadings` for a standing measurement
                // no total can hold. No live HealthKit read here — `refresh()` already made this
                // refresh's read before it reached here, so nothing blocks.
                conditions: ConditionContext(state: state, now: now(), calendar: calendar,
                                             readings: conditionReadings)),
              let next = graph.node(id: target) else { return }
        advance(state, to: next)
        Self.log.info("Evolved \(node.id) into \(next.id)")
    }

    /// Tells the user about the two health moments worth interrupting them for (US-035 AC2): the
    /// Digimon falling ill, and its illness being 24 hours from killing it.
    ///
    /// Both are decided from the state AFTER every rule in `refresh()` has run, so neither can
    /// announce something the game then changes its mind about. Whether either actually reaches the
    /// wrist is `NotificationDispatcher`'s call — the toggle and the sleep window are its business,
    /// not this method's, which is why nothing here looks at either.
    private func notifyHealthChanges(_ state: GameState, healthBefore: HealthStatus) {
        let name = presentation?.displayName ?? "Your Digimon"
        if healthBefore != .sick && state.healthStatus == .sick {
            notifications.send(.sickness,
                               body: "\(name) has fallen ill. Care for it to make it well again.",
                               isAsleep: isAsleep)
        }
        // Claimed rather than merely checked, so the warning is decided once per illness even
        // across relaunches — see `claimDeathWarning`.
        if state.claimDeathWarning(now: now()) {
            notifications.send(.deathWarning,
                               body: "\(name) has 24 hours left. Earn 30 energy today to cure it.",
                               isAsleep: isAsleep)
        }
    }

    /// Tells the user the screen has filled with mess, once per mess (US-054).
    ///
    /// A dead Digimon is not nagged about its litter: `advancePoop` pauses while dead so the count
    /// cannot grow, but a Digimon that died on a full screen would otherwise be claimed against on
    /// the next refresh. The memorial is the only message that state owes anyone.
    ///
    /// The claim is what makes this once-per-mess across relaunches — see `claimPoopNotification`.
    private func notifyPoop(_ state: GameState) {
        guard state.healthStatus != .dead else { return }
        guard state.claimPoopNotification() else { return }
        let name = presentation?.displayName ?? "Your Digimon"
        notifications.send(.poop,
                           body: "\(name)'s screen is filthy. Clean it before it gets sick.",
                           isAsleep: isAsleep)
    }

    /// Tells the user the light is still on over a sleeping Digimon (US-100), at most once a night.
    ///
    /// Two paths to the same nudge, and the second is what makes the feature work at all:
    ///
    /// 1. **Now**, when this refresh has landed inside the sleep window past `notifyGrace` — the
    ///    user has the app open at 22:10 and can act on it immediately.
    /// 2. **Ahead**, when this refresh happens while the Digimon is still awake: the instant the
    ///    nudge falls due is computable (tonight's bedtime plus the grace) and is handed to the
    ///    system there and then. Without this a user who leaves the light on and puts the watch
    ///    down for the evening is never told, because nothing runs to tell them — and being told is
    ///    the entire difference between US-101's mistake being avoidable and being a surprise.
    ///
    /// `lightNotifiedNight` is stamped by BOTH, with the night each is for, so one night can only
    /// ever produce one of them. That the stamp is taken whether or not the toggle let the notice
    /// through is the same choice `claimPoopNotification` makes: the claim is on the night, not on
    /// the delivery, and a user who switches the toggle on at midnight is asking to be nudged
    /// tomorrow rather than retroactively.
    ///
    /// A dead Digimon is not nagged about its lighting, for the reason `notifyPoop` gives.
    private func notifyLights(_ state: GameState) {
        guard state.healthStatus != .dead else { return }
        // Checked here as well as inside `shouldNotify` because it also gates the scheduling half,
        // which asks a question about tonight rather than about now: a light already out at
        // teatime has nothing to queue.
        guard state.lightState != .off else { return }
        let name = presentation?.displayName ?? "Your Digimon"
        let body = "\(name) is trying to sleep with the light on. Tap the lamp to turn it out."

        if LightsOutRule.shouldNotify(now: now(), schedule: sleepSchedule,
                                      lightState: state.lightState,
                                      lastNotifiedNight: state.lightNotifiedNight,
                                      calendar: calendar) {
            state.lightNotifiedNight = LightsOutRule.mostRecentWindowStart(at: now(),
                                                                          schedule: sleepSchedule,
                                                                          calendar: calendar)
            notifications.send(.lights, body: body, isAsleep: isAsleep)
            return
        }

        // Only while AWAKE. Inside the window there is nothing left to schedule — either the nudge
        // was owed and has just gone out above, or this night has already had its one.
        guard LightsOutRule.windowStart(containing: now(), schedule: sleepSchedule,
                                        calendar: calendar) == nil else { return }
        let night = LightsOutRule.nextWindowStart(after: now(), schedule: sleepSchedule,
                                                  calendar: calendar)
        guard state.lightNotifiedNight != night else { return }
        state.lightNotifiedNight = night
        notifications.schedule(.lights, body: body,
                               at: night.addingTimeInterval(LightsOutRule.notifyGrace))
    }

    /// Charges the care mistake for a night slept under the light (US-101), at most once a night.
    ///
    /// Beside `auditCareMistakes` rather than inside it, and the reason is the argument list: this
    /// rule is the only one of the five that needs the SLEEP WINDOW, which is derived from HealthKit
    /// by `updateSleepState` and belongs to the model. Every other mistake is a question the saved
    /// game can answer about itself, so `GameState` keeps them and this one is asked from here.
    ///
    /// It runs in the same place in `refresh()` as the audit it sits beside — after crediting, before
    /// `updateSickness` and `evolveIfReady` — so the night just charged for counts toward the illness
    /// and gates the same edges in the very refresh that discovered it, with no plumbing of its own.
    ///
    /// NOT gated on the Digimon being asleep NOW: the neglect happened at bedtime, and the whole
    /// point of `LightsOutRule` reading timestamps is that a night nobody opened the app for is still
    /// judged by the morning that follows it. Nor is it gated on `.dead` — unlike the notices, which
    /// are messages to a user and would be tactless, a count on a dead Digimon changes nothing that
    /// is still running, and `auditCareMistakes` keeps no such guard either.
    ///
    /// **EVERY unaudited night, not just the last one**, and `ClosedAppRecomputeTests` is why. An app
    /// left open over a long weekend refreshes inside each of those nights and charges each; an app
    /// that was shut sees only the morning at the end of them. Charging one night per refresh would
    /// make the same three nights cost three mistakes or one depending only on whether anyone was
    /// watching, which is exactly the asymmetry that rule exists to forbid. Unlike US-053's mess —
    /// paused by a sleep only a running refresh can observe — nothing here is observation-dependent:
    /// each night's verdict is a timestamp compared with a deadline, so it can be recovered long
    /// afterwards, and the honest answer is one mistake per night that was slept through lit.
    ///
    /// The walk stops on its own. Going back, `shouldChargeMistake` fails at the night already
    /// audited or at the first deadline that precedes `lightStateChangedAt` — and every earlier one
    /// precedes it too, so a light that has only been on since this morning ends the loop
    /// immediately. `maximumNightsChargedAtOnce` bounds the one case that cannot end itself: a save
    /// with no stamp at all, which reads as lit for all of time.
    private func auditLights(_ state: GameState) {
        // The most recent night whose deadline has actually passed. Starting from
        // `mostRecentWindowStart` alone would stop the walk dead at 22:10, when tonight is not yet
        // owed and last night may well be.
        var night = LightsOutRule.mostRecentWindowStart(at: now(), schedule: sleepSchedule,
                                                        calendar: calendar)
        if night.addingTimeInterval(LightsOutRule.mistakeGrace) > now() {
            night = LightsOutRule.previousWindowStart(before: night, schedule: sleepSchedule,
                                                      calendar: calendar)
        }

        var owed: [Date] = []
        while owed.count < LightsOutRule.maximumNightsChargedAtOnce {
            // Asked AT each night's own deadline rather than at `now`, which is what turns the
            // one-night rule into a question about a particular night without changing it: at that
            // instant `mostRecentWindowStart` is that night, and the grace is exactly satisfied.
            let deadline = night.addingTimeInterval(LightsOutRule.mistakeGrace)
            guard LightsOutRule.shouldChargeMistake(now: deadline, schedule: sleepSchedule,
                                                    lightState: state.lightState,
                                                    lightStateChangedAt: state.lightStateChangedAt,
                                                    lastAuditedNight: state.lightAuditedNight,
                                                    calendar: calendar) else { break }
            owed.append(deadline)
            night = LightsOutRule.previousWindowStart(before: night, schedule: sleepSchedule,
                                                      calendar: calendar)
        }

        // Oldest first, so `lightAuditedNight` ends on the most recent night charged. Paid in the
        // other order it would end on the oldest, and the next refresh would charge the newer nights
        // all over again.
        for deadline in owed.reversed() {
            state.recordLightsLeftOn(now: deadline, schedule: sleepSchedule, calendar: calendar)
        }
    }

    /// Moves the saved game onto `next`, the one reset a hatch and an evolution both perform: the
    /// current id and `GameState.stage` step to the new node (the saved stage is a duplicate of a
    /// graph fact the screen renders from, so a stale one would draw a placeholder), `stageEnergy`
    /// resets so the new stage starts fresh, `stageEnteredDate` is stamped for the time gate US-020
    /// will read, `lifetimeEnergy` is left untouched to carry the whole life, and the new form is
    /// recorded in the Dex.
    private func advance(_ state: GameState, to next: EvolutionNode) {
        // Captured before the id moves so the ceremony has the form being left behind.
        let from = graph.presentation(forId: state.currentDigimonId)
        state.currentDigimonId = next.id
        state.stage = next.stage
        // One call rather than the assignments spelled out here, so every stage-scoped total resets
        // together — see `GameState.enterStage(at:)`, which owns the list.
        state.enterStage(at: now())
        store?.recordDiscovery(id: next.id, now: now())
        // Kept in step with the store rather than re-fetched, so US-121's map detail reveals a
        // Digitama the moment it is hatched from rather than at the next launch.
        discoveredDigimonIds.insert(next.id)
        // A transition the screen has not celebrated yet. Both forms are drawn from the graph, so a
        // missing node (a save whose id the roster dropped) simply skips the ceremony rather than
        // showing half of one.
        if let from, let to = graph.presentation(forId: next.id) {
            pendingEvolution = EvolutionEvent(from: from, to: to)
            // Sent from `advance` rather than from `evolveIfReady`, so a HATCH is announced too:
            // both are the same "you are now something new" moment the ceremony already treats
            // alike, and an egg opening while the app is shut is the one a user most wants told.
            notifications.send(.evolution,
                               body: "\(from.displayName) digivolved into \(to.displayName)!",
                               isAsleep: isAsleep)
        }
    }

    /// Clears the pending evolution once its ceremony has finished, so it plays exactly once.
    func acknowledgeEvolution() {
        pendingEvolution = nil
    }

    /// Looks for an egg in the map the player has just won a battle in, and awards at most one
    /// (US-128, rewritten by US-207).
    ///
    /// **A won battle is the only moment an egg is found.** US-128 ran this after a train, after a
    /// battle of either result, and after a step accrual tick, and it handed the egg over the
    /// instant a condition held; US-207 narrows it to the win and makes the hand-over a coin flip.
    /// The two changes are one rule: meeting a slot's conditions no longer GIVES you the egg, it
    /// makes the egg findable, and each win in that map is one look for it.
    ///
    /// The engine collects the slots whose conditions are all met and whose egg is not already HELD
    /// (US-127), then hands back one; an empty set awards nothing. A losing fight never reaches here
    /// — `finishBattle` gates the call on the result — and a miss on the roll consumes nothing, so
    /// the next win looks again.
    ///
    /// The context is the same `ConditionContext` an evolution and the map detail's hints are judged
    /// on, off the same saved state, so the egg that drops is exactly the one the detail promised was
    /// "Ready to find". A dead active Digimon drops nothing — the caller already refuses to run on
    /// one, and this is belt to its braces.
    private func checkForDigitamaDrop() {
        guard let state, let store, let profile, state.healthStatus != .dead else { return }
        guard let mapId = profile.selectedMapId, let map = maps.map(id: mapId) else { return }
        // US-206: the SELECTED MAP's own counters, not the player's lifetime totals — the same
        // `mapScoped` reading `mapDetailContext(for:)` draws its hints and its "Ready to find" mark
        // from, so what the map promised is what the map gives.
        let context = ConditionContext.mapScoped(mapId, profile: profile,
                                                 lightState: state.lightState,
                                                 readings: conditionReadings)
        let held = (try? store.heldDigitamaIds()) ?? []
        var generator = makeDropGenerator()
        // US-207: the roll comes FIRST and is unconditional, so one win draws one Double whatever
        // the map holds — a seeded generator then forces the same branch in a test whether or not a
        // slot happens to be eligible, rather than the draw order depending on the fixture.
        let findsIt = DigitamaDropEngine.findsTheEgg(using: &generator)
        guard let dropId = DigitamaDropEngine.award(
            in: map, context: context, held: held, using: &generator
        ) else { return }
        // Nothing above this line wrote anything, so a miss leaves the conditions exactly as they
        // were — the slot stays met, stays unheld, and the next win rolls again (AC4).
        guard findsIt else { return }

        do {
            try store.grantDigitama(dropId, now: now())
        } catch {
            // The egg simply is not awarded — the box is unchanged, so the same check on the next
            // won battle will offer it again. Not worth interrupting the player over a failed flush.
            Self.log.error("Could not grant dropped Digitama: \(String(describing: error))")
            return
        }
        // Kept in step with the store the way `advance` does, so US-121's map detail reveals the egg
        // the instant it drops rather than at the next launch.
        discoveredDigimonIds.insert(dropId)
        // The announcement, off the roster because most eggs have no graph node (only six are wired).
        // A drop whose id the roster does not know is granted and recorded all the same — it simply
        // shows no banner rather than a blank one — but the US-117 validator makes that unreachable
        // for shipped data.
        if let entry = roster.entry(id: dropId) {
            pendingDigitamaDrop = DigitamaDropAnnouncement(
                id: entry.id, displayName: entry.displayName,
                spriteFile: entry.spriteFile, stage: entry.stage)
        }
    }

    /// Clears the pending drop once its banner has been dismissed, so it shows exactly once.
    func acknowledgeDigitamaDrop() {
        pendingDigitamaDrop = nil
    }

    /// Hands the player a fresh `agu_digitama` if their box has left them with nothing to raise
    /// (US-129), from the two places the box can empty today: `start()` and the refresh that settles
    /// a death. US-132's Jogress is the third and must call this after it consumes its parents.
    ///
    /// Silent on purpose — it does NOT raise `pendingDigitamaDrop`. That banner announces a REWARD
    /// the player earned on a map, and the failsafe is a floor rather than a prize; more concretely,
    /// it fires at exactly the moment the memorial covers the screen, so a banner would either be
    /// hidden under it or arrive after a rebirth had already replaced the egg it named. The party
    /// screen is where the egg is found.
    ///
    /// The Dex set is kept in step the way `advance` and the drop check do, so the map detail and the
    /// Dex reveal the egg at once rather than at the next launch.
    private func checkForStranding() {
        guard let store else { return }
        do {
            guard let egg = try store.grantFailsafeDigitamaIfStranded(now: now()) else { return }
            discoveredDigimonIds.insert(egg.currentDigimonId)
            Self.log.info("Failsafe: the box held nothing alive, granted \(egg.currentDigimonId)")
        } catch {
            // The player keeps whatever the box already held, and the next launch checks again — the
            // condition is derived from the box, so a failed grant is retried for free rather than
            // being lost.
            Self.log.error("Could not grant the failsafe Digitama: \(String(describing: error))")
        }
    }

    /// What to show on the memorial screen, or nil while the Digimon lives.
    ///
    /// Computed off `state` rather than published on death, so it cannot get out of step: the
    /// memorial is up for exactly as long as the saved game says the Digimon is dead, and the
    /// rebirth that replaces that game is what takes it down. The name comes from the graph, which
    /// is the only thing that knows it — `GameState` saves only an id.
    var memorial: Memorial? {
        guard let state else { return nil }
        let name = graph.presentation(forId: state.currentDigimonId)?.displayName
        // A saved id the roster has since dropped still deserves a memorial, so the id itself is the
        // fallback name rather than the whole screen being skipped.
        return state.memorial(displayName: name ?? state.currentDigimonId,
                              lifetimeEnergy: lifetimeEnergy)
    }

    /// Dismisses the memorial and starts the next Digimon at a fresh, randomly chosen Digitama.
    ///
    /// `lifetimeEnergy` and the Dex come across — see `GameStore.rebirth`. The pose is settled
    /// afterwards because the Digimon on screen is currently holding the dead frame, and the new egg
    /// has to go back to wobbling.
    func dismissMemorial() {
        guard let store, state?.healthStatus == .dead, let digitamaId = startingDigitamaId else {
            return
        }
        do {
            state = try store.rebirth(digitamaId: digitamaId, now: now())
            // Cleared rather than left: a ceremony still pending from the dead Digimon's last
            // evolution would otherwise play over its successor's first moments.
            pendingEvolution = nil
            animation = restingAnimation
            Self.log.info("Rebirth at \(digitamaId)")
        } catch {
            Self.log.error("Could not start the next Digimon: \(String(describing: error))")
        }
    }

    private enum GraphError: Error, CustomStringConvertible {
        case noDigitama

        var description: String {
            switch self {
            case .noDigitama: return "The evolution graph has no Digitama to start a game at."
            }
        }
    }
}
