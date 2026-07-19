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

    /// What the Digimon is doing on screen. `.idle` except for the moment after an action — feeding
    /// swaps in the eat loop, a refusal the refuse pose — and back again after `actionDuration`.
    @Published private(set) var animation: SpriteAnimation = .idle

    /// A short line about the last action, shown under the Digimon and cleared with the animation.
    /// This is where a blocked feed says WHY it was blocked, per US-024's "visible reason".
    @Published private(set) var actionMessage: String?

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
    #endif

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
    /// Simulator has no HealthKit data, so a real game there never has the Strength to spend.
    ///
    /// - `-trainDemo` — funded and healthy, then trained: the attack pose and the raised stat.
    /// - `-trainAsleepDemo` — funded but asleep, then trained: the blocked reason.
    /// - `-trainSickDemo` — funded but sick, then trained: the other blocked reason.
    private func seedTrainDemoIfRequested() {
        let arguments = CommandLine.arguments
        let sleeping = arguments.contains("-trainAsleepDemo")
        let sick = arguments.contains("-trainSickDemo")
        guard arguments.contains("-trainDemo") || sleeping || sick, let state else { return }

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
        if sleeping { forceAsleepForDemo() }
        actionDuration = 60
        train()
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
    /// - `-sickDemo` — three care mistakes, settled through the real rule: the held angry frame.
    ///
    /// The mistakes are set and `updateSickness` is what turns them into an illness, so the demo
    /// exercises the shipped rule rather than hand-setting the status it is supposed to produce.
    private func seedSickDemoIfRequested() {
        guard CommandLine.arguments.contains("-sickDemo"), let state else { return }

        // Off the starting egg for the same reason the other demos are: a Digitama sheet has no
        // angry frame, so an egg would screenshot as the placeholder however well this worked.
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
    ///   screenshot lands on the result screen instead of mid-exchange.
    /// - `-battleLossDemo` — an untrained Baby I against the stages above it: very likely the losing
    ///   result. Genuinely fought rather than hand-set, so what is screenshotted is the real rule.
    /// - `-battleLimitDemo` — the day's five battles actually FOUGHT and dismissed, leaving the
    ///   disabled button and its reason (US-032). Pair with `-battleScrollDemo` to bring it on screen.
    ///
    /// The outcome is left to the real matchmaker and the real engine — only the player's stats and
    /// the seed are staged, so this exercises the shipped path rather than its output.
    private func seedBattleDemoIfRequested() {
        let arguments = CommandLine.arguments
        let losing = arguments.contains("-battleLossDemo")
        let staged = ["-battleDemo", "-battleResultDemo", "-battleTurnDemo"]
        let limit = arguments.contains("-battleLimitDemo")
        guard staged.contains(where: arguments.contains) || losing || limit, let state else { return }

        // Off the starting egg for the same reason the other demos are: a Digitama sheet has no
        // attack or hurt frames, so an egg would screenshot as placeholders however well this worked.
        if let node = graph.node(id: losing ? "botamon" : "agumon") {
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
                finishBattle()
            }
            return
        }

        battle()
    }

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

        // Before the read, not after: hunger is owed for time already elapsed, and the read is
        // several awaits long. Nothing here depends on the energy about to be credited.
        state.advanceHunger(now: now())

        await updateSleepState()

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

    /// The pose the Digimon returns to when nothing else is happening: the angry frame held still
    /// while it is sick, the sleep loop (sleep1 <-> sleep2) while it is in its sleep window, the
    /// walk loop otherwise.
    ///
    /// Everything that ends an action reverts to THIS rather than to `.idle`, which is what keeps a
    /// Digimon fed at 23:59 from going back to pacing about.
    ///
    /// SICKNESS WINS OVER SLEEP, and it is the one state that stops the sprite moving at all — a
    /// held `.still` has no second frame to alternate with, so US-028's "does not idle-animate"
    /// falls out of the pose rather than needing a flag the view has to remember to honour.
    var restingAnimation: SpriteAnimation {
        switch state?.healthStatus {
        case .dead: return .still(.hurt2)
        case .sick: return .still(.angry)
        default: return isAsleep ? .sleep : .idle
        }
    }

    /// Whether the Digimon should be walking about the screen right now (US-037).
    ///
    /// Expressed as "the pose is the plain idle walk, and nothing is covering the screen" rather
    /// than as a list of the states that forbid it. That is not a shortcut — it is the same fact
    /// said once instead of twice. Sleeping, sickness and death are ALREADY exactly what makes
    /// `restingAnimation` return something other than `.idle`, so a state added to that switch
    /// later suspends movement automatically instead of needing to be remembered here. Eating and
    /// every other momentary pose fall out of the same rule for free: a Digimon holding still to
    /// eat should not slide across the screen while it does.
    ///
    /// The three overlays are checked because a battle, a ceremony or a memorial has the screen,
    /// and a sprite pacing on unseen underneath it is work spent drawing nothing. Each clears on
    /// its own, at which point this returns true again and the walk resumes from where it stood.
    var isWandering: Bool {
        animation == .idle && pendingEvolution == nil && pendingBattle == nil && memorial == nil
    }

    /// Every pose `settleRestingPose` is allowed to swap out. Exactly the poses `restingAnimation`
    /// can return — miss one and a Digimon that entered that state keeps holding it after leaving,
    /// which is how a reborn egg would go on lying dead.
    private static let restingPoses: Set<SpriteAnimation> = [
        .idle, .sleep, .still(.angry), .still(.hurt2)
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
            show(.eat, message: nil)
        case .refused:
            show(.still(.refuse), message: "Not hungry.")
        case .blocked(let reason):
            // No animation: nothing happened to the Digimon, so it keeps idling and only the
            // reason appears. Animating a block would read as the action having half-worked.
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

    /// Trains the Digimon: spends Strength or Stamina, raises `strengthStat`, and holds the attack
    /// pose with a firm tap.
    ///
    /// Returns the outcome so a test can assert on it directly; the screen reacts to `animation` and
    /// `actionMessage` instead. Saved even when blocked is cheap and keeps this identical to
    /// `feed()` — there is simply nothing to write in that case.
    @discardableResult
    func train() -> TrainOutcome? {
        guard let state else { return nil }
        let outcome = TrainAction.train(state, isAsleep: isAsleep)

        switch outcome {
        case .trained(let spent, let cost, _):
            playTrainHaptic()
            // The attack frame, held: it is a pose in the sheet, not a loop, so there is no second
            // frame to alternate with. The caption says which currency paid, because the Digimon
            // picks that itself and the bar dropping would otherwise be unexplained.
            show(.still(.attack), message: "Trained! -\(cost) \(spent.displayName)")
        case .blocked(let reason):
            // No animation, as with a blocked feed: nothing happened to the Digimon, so it keeps
            // idling and only the reason appears.
            show(nil, message: reason)
            noteWakingEarly()
        }

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after training: \(String(describing: error))")
        }
        return outcome
    }

    /// Picks an opponent near the player's stage, fights the battle out, and hands the replay to the
    /// screen via `pendingBattle`.
    ///
    /// The whole battle is RESOLVED HERE, before a single frame is drawn: `BattleEngine` is pure and
    /// takes its randomness from `makeBattleGenerator()`, so the outcome is fixed by the seed and the
    /// view is a replay. Nothing is written to the saved game yet — the record is filed by
    /// `finishBattle()`, once the user has actually seen the result.
    ///
    /// Blocked while asleep or dead, and blocked the same way feeding and training are: a message,
    /// no animation, and the waking-early mistake charged if it was the sleep window that stopped it.
    /// Prodding a sleeping Digimon into a fight is the same neglect as prodding it to eat. Blocked
    /// too once the day's `BattleLimits.perDay` battles are gone (US-032) — that guard sits AFTER the
    /// sleep one, so a Digimon prodded awake at its limit is still charged the waking-early mistake.
    ///
    /// Returns the bout so a test can assert on it directly; the screen reacts to `pendingBattle`.
    @discardableResult
    func battle() -> BattleBout? {
        guard let state else { return nil }
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

        var generator = makeBattleGenerator()
        guard let opponent = BattleMatchmaker.choose(in: graph,
                                                    playerId: state.currentDigimonId,
                                                    using: &generator) else {
            show(nil, message: "Nobody to fight.")
            return nil
        }

        let report = BattleEngine.resolve(playerPower: state.battlePower,
                                          opponentPower: opponent.power,
                                          using: &generator)
        let bout = BattleBout(
            player: player,
            opponent: DigimonPresentation(displayName: opponent.node.displayName,
                                          stage: opponent.node.stage,
                                          spriteFile: opponent.node.spriteFile),
            report: report
        )
        // Spent here and not in `finishBattle()`: the fight has happened by this line, so walking
        // away from the result screen must not hand the allowance back. Saved immediately for the
        // same reason — an allowance that only reaches disk when the result is dismissed would be
        // returned by force-quitting mid-battle.
        state.consumeBattleAllowance(now: now(), calendar: calendar)
        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save the battle allowance: \(String(describing: error))")
        }

        pendingBattle = bout
        Self.log.info("Battle vs \(opponent.node.id): \(report.playerWon ? "won" : "lost")")
        return bout
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
    /// RESTING, which for a sleeping Digimon is the sleep loop and not the walk loop.
    private func show(_ animation: SpriteAnimation?, message: String?) {
        actionResetTask?.cancel()
        self.animation = animation ?? restingAnimation
        self.actionMessage = message

        actionResetTask = Task { [actionDuration] in
            try? await Task.sleep(for: .seconds(actionDuration))
            guard !Task.isCancelled else { return }
            self.animation = self.restingAnimation
            self.actionMessage = nil
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
                now: now()),
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
        state.stageEnergy = .zero
        state.stageEnteredDate = now()
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
