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
    private let playFeedHaptic: () -> Void
    private let playTrainHaptic: () -> Void
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
    init(
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() },
        graph: EvolutionGraph = .bundled,
        energySource: HealthEnergySource = HealthEnergySource(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        chooseStartingDigitama: @escaping ([EvolutionNode]) -> EvolutionNode? = { $0.randomElement() },
        playFeedHaptic: @escaping () -> Void = MainScreenModel.feedHaptic,
        playTrainHaptic: @escaping () -> Void = MainScreenModel.trainHaptic,
        actionDuration: TimeInterval = 2.0
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
        await refresh()
        #if DEBUG
        seedCeremonyDemoIfRequested()
        seedFeedDemoIfRequested()
        seedTrainDemoIfRequested()
        seedSleepDemoIfRequested()
        #endif
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

        // Before the read, not after: hunger is owed for time already elapsed, and the read is
        // several awaits long. Nothing here depends on the energy about to be credited.
        state.advanceHunger(now: now())

        await updateSleepState()

        let readings = await energySource.readings(now: now())
        let credited = EnergyCreditor.credit(readings, to: state, ledger: ledger, now: now(),
                                             calendar: calendar)
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
    }

    /// The pose the Digimon returns to when nothing else is happening: the sleep loop
    /// (sleep1 <-> sleep2) while it is in its sleep window, the walk loop otherwise.
    ///
    /// Everything that ends an action reverts to THIS rather than to `.idle`, which is what keeps a
    /// Digimon fed at 23:59 from going back to pacing about.
    var restingAnimation: SpriteAnimation { isAsleep ? .sleep : .idle }

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

        // Only a RESTING pose is swapped. An eat loop or an attack pose mid-action is left alone,
        // and its own timer reverts it to whichever resting pose is current by then.
        if animation == .idle || animation == .sleep {
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
        }

        do {
            try store?.save()
        } catch {
            Self.log.error("Could not save after training: \(String(describing: error))")
        }
        return outcome
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
        }
    }

    /// Clears the pending evolution once its ceremony has finished, so it plays exactly once.
    func acknowledgeEvolution() {
        pendingEvolution = nil
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
