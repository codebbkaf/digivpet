import Foundation
import OSLog
import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

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

    /// The battle currently being played out on screen, or nil when none is. Already RESOLVED when it
    /// lands here — see `BattleBout` — so the screen replays a decided outcome rather than rolling.
    @Published private(set) var pendingBattle: BattleBout?

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
    /// once the round is graded, for two reasons. "Nobody to fight" is then decided BEFORE the day's
    /// allowance is spent, so an empty roster cannot cost a battle; and the fight is rolled from the
    /// same sequence that picked the opponent, so one seed still produces one whole bout exactly as it
    /// did when `battle()` did both in a breath.
    ///
    /// Not persisted, like `PendingTraining`: a round interrupted by a force-quit is simply over, and
    /// the allowance that already reached disk is what makes walking out of it cost something.
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

    /// A training round in progress: the game being played, and what `TrainAction.begin` charged for
    /// it. Not persisted — a round interrupted by a force-quit is simply over, and the charge that
    /// already reached disk is what makes walking out of it cost something. See `train()`.
    struct PendingTraining: Equatable {
        let kind: MinigameKind
        let spent: EnergyType
        let cost: Int
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

    /// Whether the Digimon is in its sleep window, which blocks feeding and training.
    ///
    /// DERIVED, not saved: `refresh()` recomputes it from `sleepSchedule` and the clock, so it is
    /// deliberately NOT on `GameState` — sleep comes from health data, not from the saved game. It
    /// stays settable so the Simulator demos can force it, since the Simulator has neither sleep
    /// history nor a way to wait until 22:00.
    @Published var isAsleep = false

    /// The nightly window the Digimon sleeps in: inferred from the user's last night of sleep, or
    /// `.fallback` (22:00–07:00) when HealthKit had no usable history to infer from.
    @Published private(set) var sleepSchedule: SleepSchedule = .fallback

    private let makeStore: @MainActor () throws -> GameStore
    private let graph: EvolutionGraph
    /// Consulted for one thing only: the stage of a Digimon the graph has no node for, when picking
    /// its minigame (US-082). Unreachable from here in practice — a saved id with no node draws
    /// `SavedGameUnavailableView` and never shows a Train button — but the full lookup is what
    /// `MinigameAssignment` offers and half of it is not worth the saving. Injected alongside `graph`
    /// so a test on a fixture graph can hand over a matching fixture roster.
    private let roster: Roster
    private let energySource: HealthEnergySource
    private let calendar: Calendar
    private let now: () -> Date
    private let chooseStartingDigitama: ([EvolutionNode]) -> EvolutionNode?
    private let playFeedHaptic: @MainActor () -> Void
    private let playTrainHaptic: @MainActor () -> Void
    private let makeBattleGenerator: () -> SeededGenerator
    private let notifications: NotificationDispatcher
    /// The three notification toggles, handed to `NotificationSettingsView`. Owned here rather than
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
        energySource: HealthEnergySource = HealthEnergySource(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        chooseStartingDigitama: @escaping ([EvolutionNode]) -> EvolutionNode? = { $0.randomElement() },
        playFeedHaptic: @escaping @MainActor () -> Void = MainScreenModel.feedHaptic,
        playTrainHaptic: @escaping @MainActor () -> Void = MainScreenModel.trainHaptic,
        actionDuration: TimeInterval = 2.0,
        makeBattleGenerator: @escaping () -> SeededGenerator = {
            SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        },
        notificationSettings: NotificationSettings? = nil,
        notificationDeliverer: PetNotificationDelivering? = nil
    ) {
        self.makeStore = makeStore
        self.graph = graph
        self.roster = roster
        self.energySource = energySource
        self.calendar = calendar
        self.now = now
        self.chooseStartingDigitama = chooseStartingDigitama
        self.playFeedHaptic = playFeedHaptic
        self.playTrainHaptic = playTrainHaptic
        self.actionDuration = actionDuration
        self.makeBattleGenerator = makeBattleGenerator
        let settings = notificationSettings ?? NotificationSettings()
        self.notificationSettings = settings
        self.notifications = NotificationDispatcher(
            settings: settings,
            deliverer: notificationDeliverer ?? UserNotificationDeliverer()
        )
    }

    /// How to draw the Digimon currently being raised, or nil if the graph does not know it.
    var presentation: DigimonPresentation? {
        state.flatMap { graph.presentation(forId: $0.currentDigimonId) }
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
    private var startingDigitamaId: String? {
        chooseStartingDigitama(graph.nodes(at: .digitama).filter { !$0.dexOnly })?.id
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
                self.store = store
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
        seedWanderDemoIfRequested()
        seedSickDemoIfRequested()
        seedDeathDemoIfRequested()
        seedBattleDemoIfRequested()
        seedPoopDemoIfRequested()
        seedLightDemoIfRequested()
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
    /// - `-feedAsleepDemo` — hungry and funded but asleep, then fed: the blocked reason.
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
        }
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
        state.lifetimeEnergy = EnergyTotals(strength: 120, vitality: 80, spirit: 40, stamina: 30)
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
    /// - `-battleLimitDemo` — the day's five battles actually FOUGHT and dismissed, leaving the
    ///   disabled button and its reason (US-032). No scroll flag needed since US-039 — the action
    ///   row is on screen on both watch sizes.
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
        let limit = arguments.contains("-battleLimitDemo")
        let round = arguments.contains("-battleRoundDemo")
        guard staged.contains(where: arguments.contains) || losing || limit || round,
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

        if limit {
            // Really fought and really dismissed, one at a time, so the screenshot shows the state
            // the shipped rule produces rather than a hand-set counter. The last `finishBattle()`
            // leaves no pending bout, so the main screen — not the battle screen — is what draws.
            for _ in 0..<BattleLimits.perDay {
                battle()
                finishBattleRound(.good)
                finishBattle()
            }
            return
        }

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
                playerPower: state.battlePower,
                in: graph)
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
    /// is a prediction of the fight, it IS the fight, run once with no allowance spent and no state
    /// touched. Grade `.good` because that is what the arena demos stage.
    private static func demoBattleSeed(
        showing wanted: Effectiveness,
        playerWins: Bool,
        playerId: String,
        playerPower: Int,
        in graph: EvolutionGraph,
        limit: UInt64 = 4096
    ) -> UInt64? {
        let types = ElementCatalog.bundled
        let playerType = types.type(for: playerId, in: graph)

        for seed in 0..<limit {
            var generator = SeededGenerator(seed: seed)
            // Nil means the roster offers nobody at all, which no later seed can fix.
            guard let opponent = BattleMatchmaker.choose(in: graph, playerId: playerId,
                                                        using: &generator) else { return nil }
            let matchup = BattleModifiers.matchup(
                playerPower: playerPower,
                playerType: playerType,
                opponentPower: opponent.power,
                opponentType: types.type(for: opponent.node.id, in: graph),
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
        isAsleep = sleepSchedule.contains(now(), calendar: calendar)
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
        isAsleep = sleepSchedule.contains(now(), calendar: calendar)
    }
    #endif

    /// Credits whatever health data has been earned since the last read.
    ///
    /// Safe to call as often as the app is opened, which is the point: US-014's ledger makes
    /// crediting a DELTA, so a second read with no new activity credits nothing rather than paying
    /// for the same steps twice.
    func refresh() async {
        guard let state, let ledger, !isRefreshing else { return }
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

        let readings = await energySource.readings(now: now())
        let credited = EnergyCreditor.credit(readings, to: state, ledger: ledger, now: now(),
                                             calendar: calendar)
        // After crediting and before evolving, because `careMistakeCount` is one of the things an
        // edge is gated on — an audit run after `evolveIfReady` would let a neglected Digimon take
        // a branch it had just disqualified itself from, one refresh late.
        state.auditCareMistakes(now: now(),
                                health: CareMistakes.HealthDataVerdict(readings.values),
                                calendar: calendar)
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
    var isWandering: Bool {
        animation == .idle && pendingEvolution == nil && pendingBattle == nil
            && pendingTraining == nil && pendingBattleRound == nil && memorial == nil
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
        isAsleep = sleepSchedule.contains(now(), calendar: calendar)

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
        guard let state else { return nil }
        let outcome = FeedAction.feed(state, isAsleep: isAsleep, now: now(), calendar: calendar)

        switch outcome {
        case .fed:
            playFeedHaptic()
            // The eat loop swaps the frames; the chew dips the whole sprite into the bowl between
            // them, so a meal is something the Digimon does rather than something its art does.
            show(.eat, motion: .chew, message: nil)
        case .refused:
            // The head-shake is what makes a refusal legible without reading the caption: the
            // refuse frame alone is a still pose, and a still pose is what every block looks like.
            show(.still(.refuse), motion: .shake, message: "Not hungry.")
        case .blocked(let reason):
            // No animation and NO MOTION: nothing happened to the Digimon, so it keeps idling and
            // only the reason appears. Either would read as the action having half-worked.
            show(nil, message: reason)
            noteWakingEarly()
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
    /// **Saved immediately, exactly as `battle()` saves its allowance and for the same reason.** The
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
        let start = TrainAction.begin(state, isAsleep: isAsleep)

        switch start {
        case .started(let spent, let cost):
            // No pose and no haptic yet: the Digimon is about to be covered by the game, and the
            // attack frame belongs to the round LANDING rather than to it starting.
            pendingTraining = PendingTraining(
                kind: MinigameAssignment.game(for: state.currentDigimonId, in: graph, roster: roster),
                spent: spent,
                cost: cost
            )
        case .blocked(let reason):
            // No animation, as with a blocked feed: nothing happened to the Digimon, so it keeps
            // idling and only the reason appears. NO GAME EITHER — the round was never paid for, and
            // opening one would be a free training.
            show(nil, message: reason)
            noteWakingEarly()
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
        guard let round = pendingTraining, let state else { return }
        pendingTraining = nil
        let gain = TrainAction.finish(state, result: result)

        playTrainHaptic()
        // The attack frame for a round that bought something, held: it is a pose in the sheet, not a
        // loop, so there is no second frame to alternate with. A miss gets the angry frame instead —
        // the round happened and it was not enough, which is a different thing to show than a
        // successful blow. The caption names the currency, because the Digimon picked that itself
        // when the round opened and the bar dropping would otherwise be unexplained.
        //
        // The motion is what makes the two outcomes tell themselves apart at a glance: a paid round
        // LUNGES, forward in the direction the sprite faces and home again, and a miss RECOILS
        // backward. Both poses are single held frames, so without the motion a miss and a landed
        // blow are two stills that differ only in which sixteen-pixel drawing is up.
        show(gain > 0 ? .still(.attack) : .still(.angry),
             motion: gain > 0 ? .lunge : .recoil,
             message: "\(result.displayName) +\(gain) STR · -\(round.cost) \(round.spent.displayName)")

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
    /// The happy frame, held: it is a pose in the sheet rather than a loop, and it is the one
    /// action in the row whose whole reward is the Digimon being pleased about it. The hop is the
    /// other half of that reward — a held still frame is what every BLOCKED action looks like, so
    /// without the motion the happiest moment in the game reads the same as a refusal.
    @discardableResult
    func clean() -> Bool {
        guard let state, state.poopCount > 0 else { return false }
        state.poopCount = 0
        state.poopUpdatedAt = now()
        // The mess notice is withdrawn from the wrist, and the claim is re-armed here rather than
        // being left to the next refresh's `claimPoopNotification` — cleaning is the whole of what
        // ends a mess, so both halves of ending it belong in one place and are saved by the flush
        // below. A screen left to fill again is a new mess and earns a new notice.
        state.poopNotified = false
        notifications.cancel(.poop)
        show(.still(.happy), motion: .hop, message: "All clean!")

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
    /// no `guard isAsleep` and no `noteWakingEarly()` here.
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

    /// ENTERS a battle: picks an opponent near the player's stage, spends the day's allowance, and puts
    /// this Digimon's assigned minigame on screen as the PRE-BATTLE round (US-093).
    ///
    /// This is only the first half of a battle now. Nothing is rolled here — how hard the player hits
    /// depends on how the round goes, and that is `finishBattleRound(_:)`'s to say. What is settled here
    /// is everything that must not depend on it: eligibility, who is being fought, and the allowance.
    ///
    /// The round is a fight, not a workout. It costs NO energy, buys no `strengthStat` and counts no
    /// training session — `TrainAction` is never called from here. The only thing it is worth is the
    /// multiplier it hands `BattleModifiers`.
    ///
    /// **The allowance is spent HERE and saved immediately**, exactly as `TrainAction.begin` charges its
    /// energy and for the same reason: the battle is committed to the moment the game appears, so a
    /// force-quit mid-round must not hand it back.
    ///
    /// Blocked while asleep or dead, and blocked the same way feeding and training are: a message,
    /// no animation, and the waking-early mistake charged if it was the sleep window that stopped it.
    /// Prodding a sleeping Digimon into a fight is the same neglect as prodding it to eat. Blocked
    /// too once the day's `BattleLimits.perDay` battles are gone (US-032) — that guard sits AFTER the
    /// sleep one, so a Digimon prodded awake at its limit is still charged the waking-early mistake.
    /// A BLOCKED BATTLE OPENS NO GAME, for the reason a blocked `train()` opens none: the round is the
    /// thing being paid for.
    ///
    /// Returns the game that opened, so a test can assert the battle went ahead without a view; the
    /// screen reacts to `pendingBattleRound`.
    @discardableResult
    func battle() -> MinigameKind? {
        guard let state else { return nil }
        // The mirror of `train()`'s guard, and the same silence: one Digimon cannot be in two
        // minigames at once, and a second Battle tap would spend a second allowance on a fight the
        // first tap has already picked an opponent for.
        guard pendingBattleRound == nil, pendingTraining == nil else { return nil }
        guard state.healthStatus != .dead else {
            show(nil, message: "It cannot battle.")
            return nil
        }
        guard !isAsleep else {
            show(nil, message: "Asleep — let it rest.")
            noteWakingEarly()
            return nil
        }
        guard state.battlesRemaining(now: now(), calendar: calendar) > 0 else {
            show(nil, message: Self.battleLimitReason)
            return nil
        }
        guard let player = graph.presentation(forId: state.currentDigimonId) else {
            show(nil, message: "No Digimon to fight with.")
            return nil
        }

        // Drawn here and CARRIED, rather than made again when the round is graded — see
        // `PendingBattleRound`. Both refusals below this line are decided before the allowance is
        // spent, which is the point of matchmaking early.
        var generator = nextBattleGenerator()
        guard let opponent = BattleMatchmaker.choose(in: graph,
                                                    playerId: state.currentDigimonId,
                                                    using: &generator) else {
            show(nil, message: "Nobody to fight.")
            return nil
        }

        let game = MinigameAssignment.game(for: state.currentDigimonId, in: graph, roster: roster)
        state.consumeBattleAllowance(now: now(), calendar: calendar)
        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save the battle allowance: \(String(describing: error))")
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
    /// Charges nothing — the allowance went when the game appeared — so a `.miss` here is a battle that
    /// cost its allowance and bought a WEAKER fight rather than no fight, which is the whole reason the
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
        guard let round = pendingBattleRound, let state else { return nil }
        pendingBattleRound = nil

        let types = ElementCatalog.bundled
        let matchup = BattleModifiers.matchup(
            playerPower: state.battlePower,
            playerType: types.type(for: state.currentDigimonId, in: graph),
            opponentPower: round.opponent.power,
            opponentType: types.type(for: round.opponent.node.id, in: graph),
            training: result
        )

        var generator = round.generator
        let report = BattleEngine.resolve(playerPower: matchup.playerPower,
                                          opponentPower: matchup.opponentPower,
                                          using: &generator)
        // Each side's attack identity (US-070), resolved here where both ids and their graph nodes are
        // in hand: both combatants ARE graph nodes, so the pure two-tier core answers without a roster.
        let catalog = MoveCatalog.bundled
        let playerNode = graph.node(id: state.currentDigimonId)
        let bout = BattleBout(
            player: round.player,
            opponent: DigimonPresentation(displayName: round.opponent.node.displayName,
                                          stage: round.opponent.node.stage,
                                          spriteFile: round.opponent.node.spriteFile),
            report: report,
            playerMove: catalog.move(forId: state.currentDigimonId,
                                     line: playerNode?.line, stage: playerNode?.stage),
            opponentMove: catalog.move(forId: round.opponent.node.id,
                                       line: round.opponent.node.line, stage: round.opponent.node.stage),
            matchup: matchup
        )

        pendingBattle = bout
        Self.log.info("""
            Battle vs \(round.opponent.node.id) after a \(result.displayName) round: \
            \(report.playerWon ? "won" : "lost")
            """)
        return bout
    }

    /// Ends a pre-battle round the user walked out of — graded a `.miss`, and the battle fought anyway.
    ///
    /// Called when the app leaves the foreground mid-game, the same moment `abandonTraining()` is. It is
    /// NOT a cancel: the allowance went when the round opened, so backgrounding buys the fight at the
    /// miss multiplier rather than calling it off, and the bout is waiting on `pendingBattle` when the
    /// app comes back. Walking out of a round that was going badly is not a way to keep the battle.
    ///
    /// A no-op with no round in progress, which is every ordinary backgrounding.
    func abandonBattleRound() {
        guard pendingBattleRound != nil else { return }
        finishBattleRound(.miss)
    }

    /// Why the Battle button is disabled once the day's battles are gone.
    ///
    /// One string, shown in two places — the caption when a blocked tap somehow gets through, and
    /// the label under the disabled button — so the reason a user reads can never disagree with the
    /// reason the model enforced.
    static let battleLimitReason = "No battles left today."

    /// How many battles are still allowed today, for the button to disable itself against.
    ///
    /// Computed off the injected clock rather than stored, so it rolls over at local midnight with
    /// no timer: the same derivation the guard in `battle()` uses, which is what keeps the disabled
    /// button and the refusal from ever disagreeing.
    var battlesRemainingToday: Int {
        guard let state else { return 0 }
        return state.battlesRemaining(now: now(), calendar: calendar)
    }

    /// Files the battle's result and takes the screen down, so a battle is recorded exactly once.
    ///
    /// `recordBattle` moves the win/loss counters and NOTHING else — losing never kills and never
    /// counts as a care mistake (US-031), which is why this does not touch `healthStatus` or run any
    /// of the audits `refresh()` does.
    func finishBattle() {
        guard let bout = pendingBattle else { return }
        pendingBattle = nil
        state?.recordBattle(bout.report)

        do {
            try store?.save()
        } catch {
            // Same call as `feed()`: the in-memory result stands and the screen is not taken away,
            // but a lost save does not pass in silence.
            Self.log.error("Could not save after battling: \(String(describing: error))")
        }
    }

    /// Charges the waking-early care mistake if the action that was just blocked was blocked by the
    /// sleep window.
    ///
    /// `isAsleep` is what identifies it, not the reason string: both `FeedAction` and `TrainAction`
    /// check sleep FIRST, so a block while asleep is always the sleep block — and matching on prose
    /// would silently stop charging the day someone reworded the message.
    private func noteWakingEarly() {
        guard isAsleep, let state else { return }
        state.recordWakingEarly(now: now(), calendar: calendar)
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
        guard let node = graph.node(id: state.currentDigimonId),
              let target = EggHatcher.hatchTarget(for: node, stageEnergy: state.stageEnergy),
              let baby = graph.node(id: target) else { return }
        advance(state, to: baby)
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
                // counters US-084 keeps. No live HealthKit read here — `refresh()` must not block
                // on one, and everything an evolution asks about is already in the saved state.
                conditions: ConditionContext(state: state, now: now(), calendar: calendar)),
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
        return state.memorial(displayName: name ?? state.currentDigimonId)
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
