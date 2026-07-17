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

    @Published private(set) var phase: Phase = .loading

    /// The saved game. `@Model` types are observable, so a view that reads its properties inside
    /// `body` redraws when energy is credited into it — this does not have to republish anything.
    @Published private(set) var state: GameState?

    private let makeStore: @MainActor () throws -> GameStore
    private let graph: EvolutionGraph
    private let energySource: HealthEnergySource
    private let calendar: Calendar
    private let now: () -> Date

    private var store: GameStore?
    private var ledger: EnergyLedger?
    private var isRefreshing = false

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "main")

    /// - Parameters:
    ///   - makeStore: deferred rather than taken as a `GameStore`, because opening the store
    ///     throws and touches the disk — neither belongs in a `View.init`. `@MainActor` because
    ///     `GameStore` is, and this runs when `start()` does rather than where it was written.
    ///   - now: the clock. Injected so a test can place a read on a chosen day without waiting.
    init(
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() },
        graph: EvolutionGraph = .bundled,
        energySource: HealthEnergySource = HealthEnergySource(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.makeStore = makeStore
        self.graph = graph
        self.energySource = energySource
        self.calendar = calendar
        self.now = now
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

    /// The egg a brand-new game starts at: the FIRST Digitama in the graph.
    ///
    /// Deliberately not a random one. "A new game starts at a randomly selected Digitama" is
    /// US-018's acceptance criterion, and choosing here would either pre-empt it or leave two
    /// places picking the starting egg.
    private var startingDigitamaId: String? {
        graph.nodes(at: .digitama).first { !$0.dexOnly }?.id
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
    }

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

    private enum GraphError: Error, CustomStringConvertible {
        case noDigitama

        var description: String {
            switch self {
            case .noDigitama: return "The evolution graph has no Digitama to start a game at."
            }
        }
    }
}
