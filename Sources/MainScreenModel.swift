import Foundation
import OSLog
import SwiftUI

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

    private let makeStore: @MainActor () throws -> GameStore
    private let graph: EvolutionGraph
    private let energySource: HealthEnergySource
    private let calendar: Calendar
    private let now: () -> Date
    private let chooseStartingDigitama: ([EvolutionNode]) -> EvolutionNode?

    private var store: GameStore?
    private var ledger: EnergyLedger?
    private var isRefreshing = false

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "main")

    /// - Parameters:
    ///   - makeStore: deferred rather than taken as a `GameStore`, because opening the store
    ///     throws and touches the disk — neither belongs in a `View.init`. `@MainActor` because
    ///     `GameStore` is, and this runs when `start()` does rather than where it was written.
    ///   - now: the clock. Injected so a test can place a read on a chosen day without waiting.
    ///   - chooseStartingDigitama: picks a new game's egg from the graph's playable Digitama.
    ///     Random by default, per US-018's "a new game starts at a randomly selected Digitama";
    ///     injected so a test can pin one deterministically instead of chasing randomness.
    init(
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() },
        graph: EvolutionGraph = .bundled,
        energySource: HealthEnergySource = HealthEnergySource(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        chooseStartingDigitama: @escaping ([EvolutionNode]) -> EvolutionNode? = { $0.randomElement() }
    ) {
        self.makeStore = makeStore
        self.graph = graph
        self.energySource = energySource
        self.calendar = calendar
        self.now = now
        self.chooseStartingDigitama = chooseStartingDigitama
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
