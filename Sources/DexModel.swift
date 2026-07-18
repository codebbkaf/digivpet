import Foundation
import OSLog
import SwiftUI

/// One cell of the Dex grid: a Digimon from the roster, and when — or whether — it was met.
struct DexRow: Identifiable, Equatable {
    let node: EvolutionNode
    /// When this Digimon was first discovered, or nil if it never has been.
    let firstDiscovered: Date?

    var id: String { node.id }
    var isDiscovered: Bool { firstDiscovered != nil }
}

/// Drives the Dex screen: the whole roster, marked up with what the player has actually met.
///
/// The roster comes from the graph and the discoveries from the store, and this joins them. It
/// never opens the store itself for the same reason `MainScreenModel` doesn't take one directly:
/// opening throws and touches the disk, neither of which belongs in a `View.init`.
///
/// Note what this deliberately does NOT do: touch a single sprite. Rows carry the node, not its
/// art, so building all 865 rows decodes nothing — `IdleSpriteCache` is reached only from the
/// cells a `LazyVGrid` actually puts on screen.
@MainActor
final class DexModel: ObservableObject {
    /// Every Digimon in the roster, discovered first and alphabetical within each half.
    ///
    /// Discovered-first because the Dex is a trophy case: what the player has earned should not be
    /// buried among placeholders. Sorting is done once here rather than in `body`, which re-runs.
    @Published private(set) var rows: [DexRow] = []

    /// True once `load()` has run, so the screen can tell "no Digimon yet" from "not read yet".
    @Published private(set) var isLoaded = false

    private let graph: EvolutionGraph
    private let makeStore: @MainActor () throws -> GameStore

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "dex")

    init(
        graph: EvolutionGraph = .bundled,
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() }
    ) {
        self.graph = graph
        self.makeStore = makeStore
    }

    /// How many of the roster have been met, and how many there are — the header's count.
    // `filter(_:).count` rather than `count(where:)`, which is watchOS 11+ and this app is 10.0.
    var discoveredCount: Int { rows.filter(\.isDiscovered).count }
    var totalCount: Int { rows.count }

    /// Reads the Dex and builds the grid's rows.
    ///
    /// A store that will not open degrades to an all-undiscovered Dex rather than an error screen:
    /// the roster is still worth showing, and the Dex is a side screen — losing it must not be
    /// louder than losing the game itself.
    func load() {
        var discoveries: [String: Date] = [:]
        do {
            let store = try makeStore()
            #if DEBUG
            seedDexDemoIfRequested(store)
            #endif
            discoveries = try store.dexDiscoveries()
        } catch {
            Self.log.error("Could not read the Dex: \(String(describing: error))")
        }

        rows = graph.nodes
            .map { DexRow(node: $0, firstDiscovered: discoveries[$0.id]) }
            .sorted { left, right in
                if left.isDiscovered != right.isDiscovered { return left.isDiscovered }
                return left.node.displayName.localizedCaseInsensitiveCompare(right.node.displayName)
                    == .orderedAscending
            }
        isLoaded = true
    }

    #if DEBUG
    /// Debug-only: fills in a few discoveries so the Dex can be screenshotted with BOTH halves
    /// visible. The Simulator has no HealthKit data, so a real game there never evolves far enough
    /// to discover anything past its starting egg. Unreachable without `-dexDemo`, and compiled out
    /// of release builds — the same discipline as `MainScreenModel.seedCeremonyDemoIfRequested`.
    private func seedDexDemoIfRequested(_ store: GameStore) {
        guard CommandLine.arguments.contains("-dexDemo") else { return }
        for id in ["botamon", "koromon", "agumon", "greymon"] {
            store.recordDiscovery(id: id)
        }
        try? store.save()
    }
    #endif
}
